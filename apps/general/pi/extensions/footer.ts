/**
 * Status Line Extension
 *
 * Folds pi's footer into one line: model, stats and extension statuses such
 * as the permission mode.
 *
 * The footer itself renders one blank row of padding. The line is published as a function on
 * globalThis, and modal-editor.ts draws it into the editor's bottom border,
 * level with the INSERT/NORMAL label.
 */

import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

function formatTokens(count: number): string {
	if (count < 1000) return count.toString();
	if (count < 10000) return `${(count / 1000).toFixed(1)}k`;
	if (count < 1000000) return `${Math.round(count / 1000)}k`;
	if (count < 10000000) return `${(count / 1000000).toFixed(1)}M`;
	return `${Math.round(count / 1000000)}M`;
}

const STATUS_LINE = Symbol.for("dotfiles.pi.status-line");

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async (_event, ctx) => {
		if (!ctx.hasUI) return;

		ctx.ui.setFooter((_tui, theme, footerData) => {
			const sep = theme.fg("dim", " │ ");

			let contextCache: { at: number; usage: ReturnType<typeof ctx.getContextUsage> } | undefined;
			let totals: { leaf: string | null; input: number; output: number; cost: number } | undefined;

			const statusLine = (): string[] => {
				// Drawn on every frame; the totals only change when the leaf moves.
				const leaf = ctx.sessionManager.getLeafId();
				if (!totals || totals.leaf !== leaf) {
					totals = { leaf, input: 0, output: 0, cost: 0 };
					for (const entry of ctx.sessionManager.getBranch()) {
						if (entry.type === "message" && entry.message.role === "assistant") {
							const message = entry.message as AssistantMessage;
							totals.input += message.usage.input;
							totals.output += message.usage.output;
							totals.cost += message.usage.cost.total;
						}
					}
				}
				const { input, output, cost } = totals;
				const stats: string[] = [];
				if (input) stats.push(`↑${formatTokens(input)}`);
				if (output) stats.push(`↓${formatTokens(output)}`);
				if (cost) stats.push(`$${cost.toFixed(3)}`);

				// Estimating context walks the session; once a second is plenty for a status line.
				if (!contextCache || Date.now() - contextCache.at > 1000) contextCache = { at: Date.now(), usage: ctx.getContextUsage() };
				const usage = contextCache.usage;
				const contextWindow = usage?.contextWindow ?? ctx.model?.contextWindow ?? 0;
				const percent = usage?.percent ?? null;
				const context = `${percent === null ? "?" : `${percent.toFixed(1)}%`}/${formatTokens(contextWindow)}`;
				const contextColor = (percent ?? 0) > 90 ? "error" : (percent ?? 0) > 70 ? "warning" : "dim";

				const statuses = Array.from(footerData.getExtensionStatuses().entries())
					.sort(([a], [b]) => a.localeCompare(b))
					.map(([, text]) => text.replace(/[\r\n\t]/g, " ").replace(/ +/g, " ").trim())
					.filter(Boolean)
					// Statuses that bring no colour of their own: the permission
					// system's "yolo" is a warning, anything else stays quiet.
					.map((text) => (text.includes("\x1b[") ? text : theme.fg(text === "yolo" ? "warning" : "dim", text)));

				const rest = [
					[stats.length ? theme.fg("dim", stats.join(" ")) : "", theme.fg(contextColor, context)]
						.filter(Boolean)
						.join(" "),
					...statuses,
				];

				let model = ctx.model?.id || "no-model";
				if (ctx.model?.reasoning) {
					const level = pi.getThinkingLevel() || "off";
					model += level === "off" ? " • thinking off" : ` • ${level}`;
				}
				const withProvider =
					footerData.getAvailableProviderCount() > 1 && ctx.model ? `(${ctx.model.provider}) ${model}` : model;

				// Widest first: the editor falls back to the one without the provider.
				return [withProvider, model].map((text) => [theme.fg("dim", text), ...rest].join(sep));
			};
			(globalThis as any)[STATUS_LINE] = statusLine;

			return {
				dispose() {
					// A newer session's footer may already have replaced it.
					if ((globalThis as any)[STATUS_LINE] === statusLine) delete (globalThis as any)[STATUS_LINE];
				},
				invalidate() {},
				render: () => [""],
			};
		});
	});
}
