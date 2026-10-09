import { type ExtensionAPI, getLanguageFromPath, highlightCode, type Theme } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";

const DIFF_LINE = /^([+-\s])(\s*\d*)\s(.*)$/;

const replaceTabs = (text: string) => text.replace(/\t/g, "   ");

function changedSpan(from: string, to: string): [[number, number], [number, number]] {
	let start = 0;
	while (start < from.length && start < to.length && from[start] === to[start]) start++;
	let end = 0;
	while (end < from.length - start && end < to.length - start && from[from.length - 1 - end] === to[to.length - 1 - end]) end++;
	const trim = (text: string, at: number) => at + (text.slice(at).match(/^\s*/)?.[0].length ?? 0);
	return [
		[trim(from, start), from.length - end],
		[trim(to, start), to.length - end],
	];
}

function inverse(line: string, [start, end]: [number, number]): string {
	if (end <= start) return line;
	let out = "";
	let visible = 0;
	for (let i = 0; i < line.length; ) {
		const escape = line.slice(i).match(/^\x1b\[[0-9;]*m/)?.[0];
		if (escape) {
			out += escape;
			i += escape.length;
			continue;
		}
		if (visible === start) out += "\x1b[7m";
		out += line[i];
		i++;
		visible++;
		if (visible === end) out += "\x1b[27m";
	}
	return out;
}

function renderDiff(diff: string, lang: string, theme: Theme): string {
	type Row = { prefix: string; lineNum: string; content: string };
	const out: string[] = [];
	const rows = diff.split("\n").map((line) => {
		const match = line.match(DIFF_LINE);
		return match ? { prefix: match[1]!, lineNum: match[2]!, content: replaceTabs(match[3]!) } : line;
	});

	const block = (run: Row[], color: "toolDiffRemoved" | "toolDiffAdded") =>
		!run.length
			? []
			: highlightCode(run.map((row) => row.content).join("\n"), lang).map(
			(code, index) => `${theme.fg(color, `${run[index]!.prefix}${run[index]!.lineNum}`)} ${code}`,
		);

	for (let i = 0; i < rows.length; ) {
		const row = rows[i]!;
		if (typeof row === "string") {
			out.push(theme.fg("toolDiffContext", row));
			i++;
			continue;
		}
		if (row.prefix !== "-" && row.prefix !== "+") {
			out.push(theme.fg("toolDiffContext", ` ${row.lineNum} ${row.content}`));
			i++;
			continue;
		}
		const take = (prefix: string) => {
			const run: Row[] = [];
			while (i < rows.length) {
				const next = rows[i]!;
				if (typeof next === "string" || next.prefix !== prefix) break;
				run.push(next);
				i++;
			}
			return run;
		};
		const removed = take("-");
		const added = take("+");
		const removedLines = block(removed, "toolDiffRemoved");
		const addedLines = block(added, "toolDiffAdded");
		if (removed.length === 1 && added.length === 1) {
			const [from, to] = changedSpan(removed[0]!.content, added[0]!.content);
			const gutter = (r: Row) => r.prefix.length + r.lineNum.length + 1;
			removedLines[0] = inverse(removedLines[0]!, [from[0] + gutter(removed[0]!), from[1] + gutter(removed[0]!)]);
			addedLines[0] = inverse(addedLines[0]!, [to[0] + gutter(added[0]!), to[1] + gutter(added[0]!)]);
		}
		out.push(...removedLines, ...addedLines);
	}
	return out.join("\n");
}

function repaint(component: unknown, args: unknown, theme: Theme): void {
	const preview = (component as { preview?: { diff?: unknown } } | undefined)?.preview;
	const body = (component as { children?: unknown[] } | undefined)?.children?.[2];
	if (typeof preview?.diff !== "string" || !(body instanceof Text)) return;
	const path = (args as { path?: unknown; file_path?: unknown } | undefined)?.path ?? (args as any)?.file_path;
	const lang = typeof path === "string" ? getLanguageFromPath(path) : undefined;
	if (!lang) return;
	try {
		body.setText(renderDiff(preview.diff, lang, theme));
	} catch {}
}

export default function (pi: ExtensionAPI) {
	pi.registerToolRenderer((toolName, next) => {
		const renderers = next();
		const { renderCall, renderResult } = renderers ?? {};
		if (toolName !== "edit" || !renderCall || !renderResult) return renderers;

		return {
			...renderers,
			renderCall(args, theme, context) {
				const component = renderCall(args, theme, context);
				repaint(component, args, theme);
				return component;
			},
			renderResult(result, options, theme, context) {
				const component = renderResult(result, options, theme, context);
				repaint((context.state as { callComponent?: unknown }).callComponent, context.args, theme);
				return component;
			},
		};
	});
}
