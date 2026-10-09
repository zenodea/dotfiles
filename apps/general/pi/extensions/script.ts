import type { ExtensionAPI, Theme } from "@earendil-works/pi-coding-agent";
import { liveTheme } from "./lib/live.ts";

const ORIGINAL = Symbol.for("dotfiles.pi.script.original");

type Style = Parameters<Theme["style"]>[1];
type ThemeInternals = { fgAnsi?: unknown; dimTokens?: unknown };

const ALWAYS = ["syntaxString"];

const scriptTokens = new WeakMap<Theme, Set<string>>();

function isScript(theme: Theme, token: string): boolean {
	let tokens = scriptTokens.get(theme);
	if (!tokens) {
		const { fgAnsi, dimTokens } = theme as unknown as ThemeInternals;
		const gray =
			fgAnsi instanceof Map && dimTokens instanceof Set
				? [...fgAnsi].filter(([name, ansi]) => ansi === fgAnsi.get("muted") || dimTokens.has(name)).map(([name]) => name)
				: [];
		tokens = new Set([...gray, ...ALWAYS]);
		scriptTokens.set(theme, tokens);
	}
	return tokens.has(token);
}

function patch(prototype: Theme) {
	const original: { fg: Theme["fg"]; style: Theme["style"] } = ((prototype as any)[ORIGINAL] ??= {
		fg: prototype.fg,
		style: prototype.style,
	});

	prototype.fg = function (this: Theme, color, text) {
		const colored = original.fg.call(this, color, text);
		if (!isScript(this, color)) return colored;
		const inner = colored.includes("\x1b[23m") ? colored.replaceAll("\x1b[23m", "\x1b[3m") : colored;
		return `\x1b[3m${inner}\x1b[23m`;
	};

	prototype.style = function (this: Theme, text: string, options: Style) {
		const script = typeof options.fg === "string" && isScript(this, options.fg);
		return original.style.call(this, text, script ? { ...options, italic: true } : options);
	};
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async (_event, ctx) => {
		if (!ctx.hasUI) return;
		const prototype = Object.getPrototypeOf(liveTheme() ?? {});
		if (Object.hasOwn(prototype, "fg") && Object.hasOwn(prototype, "tokenAnsi")) patch(prototype);
	});
}
