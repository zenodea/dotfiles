import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import type { ExtensionAPI, ExtensionContext, Theme } from "@earendil-works/pi-coding-agent";
import { Box, colorToHex, Container, getPngDimensions, hyperlink, Image, Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";

const PAGE_WIDTH = 880;
const PAGE_HEIGHT = 3000;
const PIXEL_RATIO = 2;
const MARGIN = 8;
const CELL = { width: 9, height: 18 };
const RENDER_TIMEOUT_MS = 30_000;
const SPINNER = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
const CHARS_PER_SPIN = 48;
const FIGURE_DIR = join(tmpdir(), "pi-figures");
const BROWSERS = [
	"chromium",
	"google-chrome-stable",
	"google-chrome",
	"chromium-browser",
	"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
	"/Applications/Chromium.app/Contents/MacOS/Chromium",
];

const DESCRIPTION = [
	"Show the user a picture inline in the conversation: a diagram, a chart or an illustrated example.",
	"You write HTML; it is rendered to an image and displayed at the point where you call the tool.",
].join(" ");

const HTML_DESCRIPTION = [
	"Body HTML only (no <html> or <body>): inline SVG, or HTML with a <style> block.",
	`The page is ${PAGE_WIDTH}px wide and at most ${PAGE_HEIGHT}px tall, with a transparent background, so the terminal shows through; the picture is cropped to its content.`,
	"It is a static image: no animation, hover or interaction.",
	"There is no network: no remote fonts, images, stylesheets or scripts.",
	"Draw straight onto the page: no background panel or card behind the figure.",
	"Colour only with the theme's CSS variables, never hardcoded colours, so it matches the terminal in light and dark themes:",
	"--fg (text and lines), --muted, --border, --bg (the terminal background), --accent, --blue, --green, --yellow, --orange, --red, --purple.",
	"Keep text at 13px or larger.",
	"Write maths as MathML (<math> elements), which is typeset natively; LaTeX is not rendered.",
].join(" ");

const REVIEW =
	" The attached image is what they see. If labels overlap, text is clipped or it is hard to read, call figure again with the same title and a corrected version, which replaces this one; otherwise carry on.";

const GUIDELINES = [
	"Call figure when a picture would teach better than prose: structures, flows, state changes, geometry, before/after comparisons. Draw it by hand in SVG or HTML.",
	"Weave figures into the explanation: write the text that leads up to a picture, call figure at that point, then carry on below it. Never end your turn on the sentence that introduces a figure: the figure call belongs in that same message. Prefer several small figures, each beside the paragraph it illustrates, over one big figure at the start or the end.",
	"After figure the picture is already on screen with its title as the caption: refer to it in the text, without describing the HTML.",
];

type ColorName = "bg" | "fg" | "muted" | "border" | "accent" | "blue" | "green" | "yellow" | "orange" | "red" | "purple";

type Palette = Record<ColorName, string>;

interface Figure {
	png: string;
	preview: string;
	widthPx: number;
	heightPx: number;
	source: string;
	replaces?: string;
}

function paletteOf(theme: Theme): Palette {
	const hex = (token: keyof Theme["colors"]) => colorToHex(theme.colors[token]);
	return {
		bg: hex("toolSuccessBg"),
		fg: hex("text"),
		muted: hex("muted"),
		border: hex("border"),
		accent: hex("accent"),
		blue: hex("mdLink"),
		green: hex("success"),
		yellow: hex("warning"),
		orange: hex("mdCode"),
		red: hex("error"),
		purple: hex("syntaxKeyword"),
	};
}

function page(body: string, colors: Palette): string {
	const variables = Object.entries(colors)
		.map(([name, value]) => `--${name}:${value}`)
		.join(";");
	return [
		`<!doctype html><meta charset="utf-8"><style>`,
		`:root{${variables}}`,
		`html,body{margin:0;background:transparent;color:var(--fg);font:15px/1.5 system-ui,sans-serif}`,
		`body{width:${PAGE_WIDTH}px}`,
		`#figure{display:inline-block;max-width:100%}`,
		`</style><div id="figure">${body}</div>`,
	].join("\n");
}

class FigureView extends Box {
	constructor(
		readonly key: string,
		figure: Figure,
		caption: string,
		view: { showImages: boolean; expanded: boolean; pad: number },
		theme: Theme,
	) {
		super(view.pad, 0);
		if (view.showImages) {
			this.addChild(
				new Image(
					figure.png,
					"image/png",
					{ fallbackColor: (text) => theme.fg("muted", text) },
					{
						maxWidthCells: Math.ceil(figure.widthPx / PIXEL_RATIO / CELL.width),
						maxHeightCells: Math.ceil(figure.heightPx / PIXEL_RATIO / CELL.height) + 1,
						filename: figure.source,
					},
					{ widthPx: figure.widthPx, heightPx: figure.heightPx },
				),
			);
		}
		if (caption) this.addChild(new Text(theme.italic(theme.fg("muted", caption)), 0, 0));
		if (view.expanded || !view.showImages) this.addChild(new Text(theme.fg("dim", hyperlink(figure.source, pathToFileURL(figure.source).href)), 0, 0));
	}
}

export default function (pi: ExtensionAPI) {
	let browser: Promise<string> | undefined;
	let latest: { title: string; id: string } | undefined;
	const replaced = new Set<string>();
	const redraw = new Map<string, () => void>();

	function restore(ctx: ExtensionContext): void {
		latest = undefined;
		replaced.clear();
		redraw.clear();
		for (const entry of ctx.sessionManager.getBranch()) {
			if (entry.type !== "message" || entry.message.role !== "toolResult" || entry.message.toolName !== "figure") continue;
			const earlier = (entry.message.details as Figure | undefined)?.replaces;
			if (earlier) replaced.add(earlier);
		}
	}

	pi.on("session_start", async (_event, ctx) => restore(ctx));
	pi.on("session_tree", async (_event, ctx) => restore(ctx));
	pi.on("agent_start", async () => {
		latest = undefined;
	});

	function findBrowser(): Promise<string> {
		browser ??= (async () => {
			for (const candidate of BROWSERS) {
				const probe = await pi.exec(candidate, ["--version"], { timeout: 5000 }).catch(() => undefined);
				if (probe?.code === 0) return candidate;
			}
			throw new Error("figure needs Chromium or Chrome installed");
		})();
		return browser;
	}

	async function screenshot(source: string, shot: string, signal?: AbortSignal): Promise<void> {
		const profile = await mkdtemp(join(FIGURE_DIR, "profile-"));
		try {
			const result = await pi.exec(
				await findBrowser(),
				[
					"--headless",
					"--disable-gpu",
					"--hide-scrollbars",
					"--default-background-color=00000000",
					"--no-first-run",
					"--disable-background-networking",
					"--disable-component-update",
					"--host-resolver-rules=MAP * ~NOTFOUND",
					`--user-data-dir=${profile}`,
					`--force-device-scale-factor=${PIXEL_RATIO}`,
					`--window-size=${PAGE_WIDTH},${PAGE_HEIGHT}`,
					`--screenshot=${shot}`,
					pathToFileURL(source).href,
				],
				{ signal, timeout: RENDER_TIMEOUT_MS },
			);
			if (result.code !== 0) throw new Error(`The browser could not render the figure: ${result.stderr.slice(-300)}`);
		} finally {
			await rm(profile, { recursive: true, force: true });
		}
	}

	async function magick(args: string[], signal?: AbortSignal): Promise<void> {
		const result = await pi.exec("magick", args, { signal, timeout: RENDER_TIMEOUT_MS }).catch(() => undefined);
		if (result?.code !== 0) throw new Error(`figure needs ImageMagick (magick): ${result?.stderr.slice(-300) ?? "not found"}`);
	}

	async function render(html: string, colors: Palette, signal?: AbortSignal): Promise<Figure> {
		await mkdir(FIGURE_DIR, { recursive: true });
		const name = createHash("sha256").update(html).digest("hex").slice(0, 12);
		const source = join(FIGURE_DIR, `${name}.html`);
		const shot = join(FIGURE_DIR, `${name}.png`);
		await writeFile(source, page(html, colors));
		await screenshot(source, shot, signal);
		const preview = join(FIGURE_DIR, `${name}.preview.png`);
		await magick([shot, "-trim", "+repage", "-bordercolor", "none", "-border", String(MARGIN * PIXEL_RATIO), shot], signal);
		await magick([shot, "-background", colors.bg, "-flatten", "-resize", `${100 / PIXEL_RATIO}%`, preview], signal);
		const png = (await readFile(shot)).toString("base64");
		const size = getPngDimensions(png);
		const blank = 2 * MARGIN * PIXEL_RATIO + 2;
		if (!size || (size.widthPx <= blank && size.heightPx <= blank)) throw new Error("The figure rendered blank: the HTML drew nothing visible");
		return { png, preview: (await readFile(preview)).toString("base64"), widthPx: size.widthPx, heightPx: size.heightPx, source };
	}

	pi.on("context", async (event, ctx) => {
		if (!ctx.model?.input.includes("image")) return;
		for (const message of event.messages) {
			if (message.role !== "toolResult" || message.toolName !== "figure" || message.isError) continue;
			const preview = (message.details as Figure | undefined)?.preview;
			if (preview) message.content = [...message.content, { type: "image", data: preview, mimeType: "image/png" }];
		}
	});

	pi.registerTool({
		name: "figure",
		label: "Figure",
		description: DESCRIPTION,
		promptGuidelines: GUIDELINES,
		parameters: Type.Object({
			title: Type.String({ description: "A few words naming the figure" }),
			html: Type.String({ description: HTML_DESCRIPTION }),
		}),
		async execute(id, params, signal, _onUpdate, ctx) {
			if (!ctx.hasUI) throw new Error("figure needs the interactive terminal to show a picture");
			const figure = await render(params.html, paletteOf(ctx.ui.theme), signal);
			if (latest?.title === params.title) {
				figure.replaces = latest.id;
				replaced.add(latest.id);
				redraw.get(latest.id)?.();
			}
			latest = { title: params.title, id };
			const width = Math.round(figure.widthPx / PIXEL_RATIO);
			const height = Math.round(figure.heightPx / PIXEL_RATIO);
			const cut = height >= PAGE_HEIGHT ? ` It is taller than the ${PAGE_HEIGHT}px page, so the bottom is cut off: split it into smaller figures.` : "";
			const review = ctx.model?.input.includes("image") ? REVIEW : "";
			return { content: [{ type: "text", text: `Figure shown to the user (${width} x ${height} px).${review}${cut}` }], details: figure };
		},
		renderShell: "self",
		renderCall(args, theme, context) {
			if (!context.isPartial && !context.isError) return new Container();
			const title = args.title ?? "";
			if (context.isError) return new Text(theme.fg("muted", `figure ${title}`), context.outputPad, 0);
			const written = args.html?.length ?? 0;
			const spinner = SPINNER[Math.floor(written / CHARS_PER_SPIN) % SPINNER.length];
			const progress = context.argsComplete ? `rendering ${title}` : `drawing ${title} · ${written.toLocaleString()} chars`;
			return new Text(`${theme.fg("accent", spinner)} ${theme.fg("muted", progress)}`, context.outputPad, 0);
		},
		renderResult(result, { expanded }, theme, context) {
			const figure = result.details as Figure | undefined;
			redraw.set(context.toolCallId, context.invalidate);
			if (replaced.has(context.toolCallId)) return new Container();
			if (!figure?.png) {
				const message = result.content.map((part) => (part.type === "text" ? part.text : "")).join("\n");
				return new Text(theme.fg("error", message), context.outputPad, 0);
			}
			const caption = context.args.title ?? "";
			const view = { showImages: context.showImages, expanded, pad: context.outputPad };
			const key = [figure.source, caption, view.showImages, view.expanded, view.pad].join("|");
			const last = context.lastComponent;
			return last instanceof FigureView && last.key === key ? last : new FigureView(key, figure, caption, view, theme);
		},
	});
}
