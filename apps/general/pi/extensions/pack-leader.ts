/**
 * Pack Leader Extension
 *
 * /pack-leader picks the harness, model and thinking level that Pack Leader
 * hands to new workers: three searchable lists, saved with
 * `pack-leader config set`. Explicit flags on `pack-leader worker start`
 * still win. The same picker outside pi: `pack-leader config pick`.
 */

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { DynamicBorder, getSelectListTheme } from "@earendil-works/pi-coding-agent";
import { Container, Input, type SelectItem, SelectList, Text } from "@earendil-works/pi-tui";

const run = promisify(execFile);

const KINDS: SelectItem[] = [
	{ value: "claude", label: "claude", description: "Claude Code" },
	{ value: "codex", label: "codex", description: "OpenAI Codex" },
	{ value: "pi", label: "pi", description: "pi coding agent" },
];
const THINKING: Record<string, string[]> = {
	claude: ["low", "medium", "high", "xhigh", "max"],
	codex: ["minimal", "low", "medium", "high", "xhigh"],
	pi: ["off", "minimal", "low", "medium", "high", "xhigh", "max"],
};

type Config = { kind: string; kinds: Record<string, { model?: string | null; thinking?: string | null }> };

async function current(): Promise<Config> {
	const { stdout } = await run("pack-leader", ["config", "show"]);
	return JSON.parse(stdout) as Config;
}

function modelsFor(kind: string, ctx: ExtensionContext): SelectItem[] {
	if (kind === "claude") return ["opus", "sonnet", "haiku"].map((v) => ({ value: v, label: v }));
	const models = ctx.modelRegistry.getAvailable();
	if (kind === "codex") return models.filter((m) => m.provider === "openai").map((m) => ({ value: m.id, label: m.id }));
	return models.map((m) => ({ value: `${m.provider}/${m.id}`, label: `${m.provider}/${m.id}`, description: m.name }));
}

/** A list with a search box above it. Resolves to the value, the typed text when nothing matched and `allowCustom`, or undefined. */
function pick(ctx: ExtensionContext, title: string, items: SelectItem[], now: string | null | undefined, allowCustom = false): Promise<string | undefined> {
	const marked = items.map((i) => (i.value === now ? { ...i, description: [i.description, "(current)"].filter(Boolean).join("  ") } : i));
	return ctx.ui.custom<string | undefined>((tui, theme, _kb, done) => {
		const container = new Container();
		container.addChild(new DynamicBorder());
		container.addChild(new Text(theme.fg("accent", theme.bold(title)), 1, 0));
		const input = new Input({ prompt: theme.fg("accent", "› "), placeholder: allowCustom ? "search, or type a name" : "search" });
		container.addChild(input);
		const list = new SelectList(marked, Math.min(Math.max(marked.length, 1), 12), getSelectListTheme());
		const at = marked.findIndex((i) => i.value === now);
		if (at >= 0) list.setSelectedIndex(at);
		list.onSelect = (item) => done(item.value);
		list.onCancel = () => done(undefined);
		container.addChild(list);
		container.addChild(new DynamicBorder());
		return {
			render: (width: number) => container.render(width),
			invalidate: () => container.invalidate(),
			handleInput(data: string) {
				const nav = data === "\x1b[A" || data === "\x1b[B" || data === "\r" || data === "\n" || data === "\x1b" || data === "\x0b" || data === "\x0a";
				if (nav) {
					if ((data === "\r" || data === "\n") && !list.getSelectedItem()) {
						const typed = input.getValue().trim();
						if (allowCustom && typed) return done(typed);
						return;
					}
					list.handleInput(data === "\x0b" ? "\x1b[A" : data === "\x0a" ? "\x1b[B" : data);
				} else {
					input.handleInput(data);
					list.setFilter(input.getValue());
				}
				tui.requestRender();
			},
		};
	});
}

export default function packLeaderExtension(pi: ExtensionAPI) {
	pi.registerCommand("pack-leader", {
		description: "Harness, model and thinking level for Pack Leader workers",
		handler: async (_args, ctx) => {
			if (ctx.mode !== "tui") {
				ctx.ui.notify("/pack-leader needs the TUI", "error");
				return;
			}
			let config: Config;
			try {
				config = await current();
			} catch (err) {
				ctx.ui.notify(`pack-leader is not on PATH: ${(err as Error).message}`, "error");
				return;
			}
			const kind = await pick(ctx, "Pack Leader: workers run in", KINDS, config.kind);
			if (!kind) return;
			const now = config.kinds[kind] ?? {};
			const model = await pick(ctx, `Model for ${kind}`, modelsFor(kind, ctx), now.model, true);
			if (model === undefined) return;
			const thinking = await pick(ctx, `Thinking level for ${kind}`, (THINKING[kind] ?? THINKING.pi!).map((v) => ({ value: v, label: v })), now.thinking);
			if (thinking === undefined) return;

			const args = ["config", "set", "--kind", kind, "--default", ...(model ? ["--model", model] : ["--clear-model"]), ...(thinking ? ["--thinking", thinking] : ["--clear-thinking"])];
			try {
				await run("pack-leader", args);
				ctx.ui.notify(`pack workers: ${kind}${model ? ` · ${model}` : ""}${thinking ? ` · ${thinking}` : ""}`, "info");
			} catch (err) {
				ctx.ui.notify(`pack-leader config set failed: ${(err as Error).message}`, "error");
			}
		},
	});
}
