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
const EDITOR_VIEW_EVENT = "subagents:editor-view";
const EDITOR_VIEW_REQUEST_EVENT = "subagents:editor-view:request";
const EDITOR_STATUS_REQUEST_EVENT = "subagents:editor-status:request";
type ViewedAgent = { id: string; modelId?: string; modelName?: string; thinkingLevel?: string };

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async (_event, ctx) => {
		if (!ctx.hasUI) return;

		ctx.ui.setFooter((_tui, theme, footerData) => {
			const sep = theme.fg("dim", " │ ");

			let contextCache: { at: number; usage: ReturnType<typeof ctx.getContextUsage> } | undefined;
			let totals: { leaf: string | null; cost: number } | undefined;
			let viewedAgent: ViewedAgent | null = null;
			type AgentStatus = { cost: number; usage?: ReturnType<typeof ctx.getContextUsage>; contextWindow?: number; reasoning?: boolean };
			let agentStatus: { at: number; value?: AgentStatus } | undefined;

			const statusLine = (): string[] => {
				let cost: number | undefined;
				let usage: ReturnType<typeof ctx.getContextUsage>;
				if (viewedAgent) {
					if (!agentStatus || Date.now() - agentStatus.at > 1000) {
						const snapshot: typeof agentStatus = { at: Date.now() };
						pi.events.emit(EDITOR_STATUS_REQUEST_EVENT, { agentId: viewedAgent.id, respond: (value: AgentStatus) => { snapshot.value = value; } });
						agentStatus = snapshot;
					}
					cost = agentStatus.value?.cost;
					usage = agentStatus.value?.usage;
				} else {
					const leaf = ctx.sessionManager.getLeafId();
					if (!totals || totals.leaf !== leaf) {
						totals = { leaf, cost: 0 };
						for (const entry of ctx.sessionManager.getBranch()) {
							if (entry.type === "message" && entry.message.role === "assistant") {
								totals.cost += (entry.message as AssistantMessage).usage.cost.total;
							}
						}
					}
					cost = totals.cost;
					if (!contextCache || Date.now() - contextCache.at > 1000) contextCache = { at: Date.now(), usage: ctx.getContextUsage() };
					usage = contextCache.usage;
				}
				const stats = [cost === undefined ? "$?" : `$${cost.toFixed(3)}`];
				const contextWindow = usage?.contextWindow ?? (viewedAgent ? agentStatus?.value?.contextWindow : ctx.model?.contextWindow) ?? 0;
				const percent = usage?.percent ?? null;
				const context = `${percent === null ? "?" : `${percent.toFixed(1)}%`}/${viewedAgent && !contextWindow ? "?" : formatTokens(contextWindow)}`;
				const contextColor = (percent ?? 0) > 90 ? "error" : (percent ?? 0) > 70 ? "warning" : "dim";

				const colored = Array.from(footerData.getExtensionStatuses().entries())
					.sort(([a], [b]) => a.localeCompare(b))
					.map(([key, text]) => [key, text.replace(/[\r\n\t]/g, " ").replace(/ +/g, " ").trim()] as const)
					// The classifier labels its judge "judge:provider/model"; the model is enough.
					.map(([key, text]) => [key, text.replace(/\bjudge:(?:[^/\s]+\/)?/, "")] as const)
					.filter(([, text]) => text)
					// Statuses that bring no colour of their own: the permission
					// system's "yolo" is a warning, anything else stays quiet.
					.map(([key, text]) => [key, text.includes("\x1b[") ? text : theme.fg(text === "yolo" ? "warning" : "dim", text)] as const);
				// The permission system and its judge are one subject: one segment,
				// judge first, dot-separated, ahead of the other statuses.
				const isPermission = (key: string) => key.includes("permission");
				const permission = colored
					.filter(([key]) => isPermission(key))
					.sort(([a], [b]) => Number(b.includes("classifier")) - Number(a.includes("classifier")))
					.map(([, text]) => text);
				const statuses = [
					...(permission.length ? [permission.join(theme.fg("dim", " · "))] : []),
					...colored.filter(([key]) => !isPermission(key)).map(([, text]) => text),
				];

				const rest = [
					[stats.length ? theme.fg("dim", stats.join(" ")) : "", theme.fg(contextColor, context)]
						.filter(Boolean)
						.join(" "),
					...statuses,
				];

				let model = viewedAgent ? viewedAgent.modelId || viewedAgent.modelName || "unknown-model" : ctx.model?.id || "no-model";
				if (viewedAgent ? agentStatus?.value?.reasoning !== false : ctx.model?.reasoning) {
					const level = viewedAgent ? viewedAgent.thinkingLevel ?? "thinking ?" : pi.getThinkingLevel() || "off";
					model += level === "off" ? " • thinking off" : ` • ${level}`;
				}
				return [theme.italic([theme.fg("dim", model), ...rest].join(sep))];
			};
			(globalThis as any)[STATUS_LINE] = statusLine;
			const unsubscribe = pi.events.on(EDITOR_VIEW_EVENT, (value) => {
				if (!value || typeof value !== "object") return;
				const update = value as { version?: number; agent?: ViewedAgent | null };
				if (update.version !== 1 || update.agent === undefined) return;
				const next = update.agent;
				if (next !== null && (typeof next !== "object" || typeof next.id !== "string"
					|| [next.modelId, next.modelName, next.thinkingLevel].some(field => field !== undefined && typeof field !== "string"))) return;
				if (JSON.stringify(next) === JSON.stringify(viewedAgent)) return;
				viewedAgent = next ? { ...next } : null;
				agentStatus = undefined;
				contextCache = undefined;
				totals = undefined;
				_tui.requestRender();
			});
			pi.events.emit(EDITOR_VIEW_REQUEST_EVENT, { version: 1 });

			return {
				dispose() {
					unsubscribe();
					// A newer session's footer may already have replaced it.
					if ((globalThis as any)[STATUS_LINE] === statusLine) delete (globalThis as any)[STATUS_LINE];
				},
				invalidate() {},
				render: () => [""],
			};
		});
	});
}
