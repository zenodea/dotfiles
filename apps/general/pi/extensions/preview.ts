import { type ExtensionAPI, keyHint, type Theme } from "@earendil-works/pi-coding-agent";
import type { Component } from "@earendil-works/pi-tui";

const PREVIEW_LINES = 5;
const RESULT_TOOLS = new Set(["grep", "find", "ls"]);

function headLength(lines: string[]): number {
	const blank = lines.findIndex((line) => line.trim() === "");
	return blank === -1 ? -1 : blank + 1;
}

class Preview implements Component {
	private width?: number;
	private lines: string[] = [];

	constructor(
		readonly inner: Component,
		private theme: Theme,
	) {}

	render(width: number): string[] {
		if (width === this.width) return this.lines;
		const lines = this.inner.render(width);
		const head = headLength(lines);
		const body = lines.length - head;
		if (head === -1 || body <= PREVIEW_LINES + 1) {
			this.lines = lines;
		} else {
			const hidden = body - PREVIEW_LINES;
			const hint =
				this.theme.fg("muted", `... (${hidden} more lines,`) +
				` ${keyHint("app.tools.expand", "to expand")}${this.theme.fg("muted", ")")}`;
			this.lines = [...lines.slice(0, head + PREVIEW_LINES), hint];
		}
		this.width = width;
		return this.lines;
	}

	invalidate(): void {
		this.width = undefined;
		this.inner.invalidate?.();
	}
}

function unwrap<T extends { lastComponent: Component | undefined }>(context: T): T {
	const last = context.lastComponent;
	return last instanceof Preview ? { ...context, lastComponent: last.inner } : context;
}

export default function (pi: ExtensionAPI) {
	pi.registerToolRenderer((toolName, next) => {
		const renderers = next();
		const { renderCall, renderResult } = renderers ?? {};

		if (RESULT_TOOLS.has(toolName) && renderResult) {
			return {
				...renderers,
				renderResult(result, options, theme, context) {
					context = unwrap(context);
					if (options.expanded || options.isPartial) return renderResult(result, options, theme, context);
					return new Preview(renderResult(result, { ...options, expanded: true }, theme, context), theme);
				},
			};
		}

		if (toolName === "write" && renderCall) {
			return {
				...renderers,
				renderCall(args, theme, context) {
					context = unwrap(context);
					if (context.expanded) return renderCall(args, theme, context);
					return new Preview(renderCall(args, theme, { ...context, expanded: true }), theme);
				},
			};
		}

		return renderers;
	});
}
