import { AssistantMessageComponent, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { MouseRegion, Text } from "@earendil-works/pi-tui";
import { liveTheme } from "./lib/live.ts";

const ORIGINAL = Symbol.for("dotfiles.pi.thinking.original");
const BAR = "▏";
const PREVIEW_CHARS = 40;

type Theme = { fg(color: string, text: string): string; italic(text: string): string };

const ESCAPE = /\x1b\[[0-9;]*m/g;
const PATH =
	/(?:~|\.{1,2})?\/?(?:[\w.@-]+\/)+[\w.@-]+(?::\d+)?|\b[\w.-]+\.(?:ts|tsx|js|jsx|mjs|py|sh|zsh|md|json|toml|ya?ml|lua|rs|go|conf|css|html)(?::\d+)?\b/g;

const colorParams = (theme: Theme, color: string) =>
	/38;[25](?:;\d+)+/.exec(theme.fg(color, "x"))?.[0] ?? "";

function accentLine(line: string, theme: Theme): string {
	const grey = colorParams(theme, "thinkingText");
	if (!grey || !line.includes(grey)) return line;
	line = line.replace(/\x1b\[23m/g, "") + "\x1b[23m";
	const plain = line.replace(ESCAPE, "").trim();
	const boldText = [...line.matchAll(/\x1b\[1m([\s\S]*?)\x1b\[22m/g)].map((m) => m[1]!.replace(ESCAPE, "")).join("").trim();
	const heading = plain !== "" && boldText === plain;
	const strong = colorParams(theme, heading ? "accent" : "text");
	line = line.replace(/\x1b\[1m[\s\S]*?\x1b\[22m/g, (run) => run.split(grey).join(strong));
	if (heading) return line;
	const blue = `\x1b[${colorParams(theme, "mdLink")}m`;
	const back = `\x1b[${grey}m`;
	let current = "";
	return line
		.split(/(\x1b\[[0-9;]*m)/)
		.map((part) => {
			if (part.startsWith("\x1b[")) {
				const color = /38;[25](?:;\d+)+/.exec(part)?.[0];
				if (color) current = color;
				else if (part === "\x1b[39m" || part === "\x1b[0m") current = "";
				return part;
			}
			return current === grey ? part.replace(PATH, (path) => `${blue}${path}${back}`) : part;
		})
		.join("");
}

type Content = { type: string; text?: string; thinking?: string };
type Run = { text: string; last: boolean };

interface LiveState {
	opened: Map<number, boolean>;
	userSet: Set<number>;
}
const live = new WeakMap<object, LiveState>();

function thinkingRuns(content: Content[]): Run[] {
	const runs: Run[] = [];
	for (let i = 0; i < content.length; i++) {
		if (content[i]!.type !== "thinking") continue;
		const parts: string[] = [];
		for (; i < content.length && content[i]!.type === "thinking"; i++) {
			const text = content[i]!.thinking?.trim();
			if (text) parts.push(text);
		}
		if (parts.length) runs.push({ text: parts.join("\n\n"), last: i >= content.length });
		i--;
	}
	return runs;
}

function followLive(component: any, runs: Run[], streaming: boolean): void {
	if (!component.hideThinkingBlock) return;
	const overrides: Map<number, boolean> = component.thinkingVisibilityOverrides;
	let state = live.get(component);
	if (!state) live.set(component, (state = { opened: new Map(), userSet: new Set() }));

	runs.forEach((run, index) => {
		if (state.userSet.has(index)) return;
		const ours = state.opened.get(index);
		const current = overrides.get(index);
		if (current !== undefined && current !== ours) {
			state.userSet.add(index);
			state.opened.delete(index);
			return;
		}
		if (streaming && run.last) {
			overrides.set(index, false);
			state.opened.set(index, false);
		} else if (ours !== undefined) {
			overrides.delete(index);
			state.opened.delete(index);
		}
	});
}

function words(text: string): string {
	const count = text.split(/\s+/).filter(Boolean).length;
	return count >= 1000 ? `${(count / 1000).toFixed(1)}k words` : `${count} words`;
}

function preview(text: string): string {
	const plain = text
		.replace(/[*_`#>]+/g, "")
		.replace(/\s+/g, " ")
		.trim();
	return plain.length > PREVIEW_CHARS ? `${plain.slice(0, PREVIEW_CHARS).trimEnd()}…` : plain;
}

function decorate(component: any, runs: Run[], theme: Theme): void {
	const overrides: Map<number, boolean> = component.thinkingVisibilityOverrides;
	const bar = `\x1b[2m${theme.fg("accent", BAR)}\x1b[22m`;
	const regions = (component.contentContainer?.children ?? []).filter((child: unknown) => child instanceof MouseRegion);

	regions.forEach((region: any, index: number) => {
		const run = runs[index];
		if (!run) return;
		const hidden = overrides.get(index) ?? component.hideThinkingBlock;
		if (hidden && region.child instanceof Text) {
			const label = `Thinking · ${words(run.text)} · "${preview(run.text)}"`;
			region.child.setText(theme.italic(theme.fg("thinkingText", label)));
		}
		const render = region.render.bind(region);
		region.render = (width: number): string[] =>
			width < 2
				? render(width)
				: render(width - 1).map((line: string) => {
						try {
							return bar + (hidden ? line : accentLine(line, theme));
						} catch {
							return bar + line;
						}
					});
	});
}

function patch() {
	const prototype = (AssistantMessageComponent as any)?.prototype;
	if (typeof prototype?.updateContent !== "function") return;
	const updateContent = (prototype[ORIGINAL] ??= prototype.updateContent);

	prototype.updateContent = function (this: any, message: { content: Content[] }, isStreaming: boolean = this.isStreaming) {
		const theme = liveTheme();
		let runs: Run[] = [];
		try {
			runs = thinkingRuns(message.content);
			followLive(this, runs, isStreaming);
		} catch {}
		const result = updateContent.call(this, message, isStreaming);
		try {
			if (theme && runs.length) decorate(this, runs, theme);
		} catch {}
		return result;
	};
}

export default function (_pi: ExtensionAPI) {
	patch();
}
