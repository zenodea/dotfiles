/**
 * Recall - search the whole conversation, including what compaction summarised away.
 *
 * Compaction keeps a summary in context, but every message stays in the
 * session file. recall({ query }) searches the current branch and returns the
 * best-matching messages as #N snippets; recall({ expand: N }) returns #N in full.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";

const MAX_HITS = 8;
const SNIPPET = 240;
const EXPAND_CHARS = 12_000;

// Everything readable in a message: text, tool calls, bash commands and output. Thinking is skipped.
function textOf(message: any): string {
	const parts: string[] = [];
	if (typeof message.command === "string") parts.push(`$ ${message.command}`);
	if (typeof message.output === "string") parts.push(message.output);
	const content = message.content;
	if (typeof content === "string") parts.push(content);
	else if (Array.isArray(content)) {
		for (const part of content) {
			if (part.type === "text") parts.push(part.text);
			else if (part.type === "toolCall") parts.push(`${part.name} ${JSON.stringify(part.arguments)}`);
		}
	}
	return parts.join("\n");
}

function label(message: any): string {
	return message.role === "toolResult" ? `${message.toolName} result` : message.role;
}

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: "recall",
		label: "Recall",
		description:
			"Search earlier parts of this conversation, including messages replaced by a compaction summary. query: words (any match, best first) or /regex/. expand: a #N from a previous search, to read that message in full.",
		parameters: Type.Object({
			query: Type.Optional(Type.String({ description: "Words to look for, or /regex/" })),
			expand: Type.Optional(Type.Number({ description: "Message #N to return in full" })),
		}),

		async execute(_id, params, _signal, _onUpdate, ctx) {
			const messages = ctx.sessionManager
				.getBranch()
				.map((entry, n) => ({ n, message: entry.type === "message" ? (entry.message as any) : undefined }))
				.filter((m) => m.message && m.message.role !== "system");

			if (params.expand !== undefined) {
				const hit = messages.find((m) => m.n === params.expand);
				if (!hit) throw new Error(`No message #${params.expand} on this branch`);
				const text = textOf(hit.message);
				const body = text.length > EXPAND_CHARS ? `${text.slice(0, EXPAND_CHARS)}\n[… ${text.length - EXPAND_CHARS} more characters]` : text;
				return { content: [{ type: "text", text: `#${hit.n} ${label(hit.message)}\n${body}` }], details: { hits: 1 } };
			}

			const query = params.query?.trim();
			if (!query) throw new Error("Give a query or an expand number");
			const regex = /^\/(.+)\/([a-z]*)$/.exec(query);
			const patterns = regex
				? [new RegExp(regex[1]!, regex[2]!.includes("i") ? "i" : "")]
				: query.split(/\s+/).map((word) => new RegExp(word.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "i"));

			const hits = messages
				.map((m) => {
					const text = textOf(m.message);
					const score = patterns.filter((p) => p.test(text)).length;
					return { ...m, text, score };
				})
				.filter((m) => m.score > 0)
				.sort((a, b) => b.score - a.score || b.n - a.n)
				.slice(0, MAX_HITS);

			if (!hits.length) return { content: [{ type: "text", text: `Nothing matches "${query}"` }], details: { hits: 0 } };
			const lines = hits.map((hit) => {
				const at = Math.max(0, (patterns.map((p) => hit.text.search(p)).find((i) => i >= 0) ?? 0) - SNIPPET / 3);
				const snippet = hit.text.slice(at, at + SNIPPET).replace(/\s+/g, " ").trim();
				return `#${hit.n} ${label(hit.message)}: ${at > 0 ? "…" : ""}${snippet}…`;
			});
			lines.push("", "Read one in full with recall({ expand: N }).");
			return { content: [{ type: "text", text: lines.join("\n") }], details: { hits: hits.length } };
		},

		renderCall(args, theme) {
			const what = args.expand !== undefined ? `#${args.expand}` : (args.query ?? "");
			return new Text(theme.fg("toolTitle", theme.bold("recall ")) + theme.fg("muted", what), 0, 0);
		},
		renderResult(result, _options, theme) {
			const hits = (result.details as { hits?: number } | undefined)?.hits;
			if (hits === undefined) return new Text(theme.fg("error", result.content.map((c) => (c.type === "text" ? c.text : "")).join("")), 0, 0);
			return new Text(theme.fg("dim", hits === 1 ? "1 message" : `${hits} messages`), 0, 0);
		},
	});
}
