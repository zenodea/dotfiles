/**
 * Web - two tools: web_search and web_fetch.
 *
 * web_search  asks Exa's free MCP endpoint (no API key), the same zero-config
 *             search pi-web-access used.
 * web_fetch   downloads a page and turns its HTML into plain text: headings,
 *             list items and links survive, scripts and styles don't.
 */

import type { ExtensionAPI, Theme } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";

const EXA_MCP = "https://mcp.exa.ai/mcp";
const TIMEOUT_MS = 30_000;
const DEFAULT_CHARS = 20_000;
const USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36";

// Abort on Esc (the turn's signal) or after TIMEOUT_MS, whichever comes first.
function withTimeout(signal: AbortSignal | undefined): AbortSignal {
	const timeout = AbortSignal.timeout(TIMEOUT_MS);
	return signal ? AbortSignal.any([signal, timeout]) : timeout;
}

function clip(text: string, max: number): string {
	return text.length <= max ? text : `${text.slice(0, max)}\n\n[… cut at ${max} of ${text.length} characters; ask for more with a larger maxChars]`;
}

async function exaSearch(query: string, numResults: number, signal?: AbortSignal): Promise<string> {
	const response = await fetch(`${EXA_MCP}?tools=web_search_exa`, {
		method: "POST",
		headers: { "Content-Type": "application/json", Accept: "application/json, text/event-stream" },
		body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "web_search_exa", arguments: { query, numResults } } }),
		signal: withTimeout(signal),
	});
	const body = await response.text();
	if (!response.ok) throw new Error(`Exa search failed (${response.status}): ${body.slice(0, 300)}`);

	// The reply is either JSON or server-sent events with JSON in "data:" lines.
	const candidates = [...body.split("\n").filter((l) => l.startsWith("data:")).map((l) => l.slice(5).trim()), body];
	for (const candidate of candidates) {
		try {
			const rpc = JSON.parse(candidate) as { result?: { content?: { type: string; text?: string }[] }; error?: { message?: string } };
			if (rpc.error) throw new Error(`Exa search error: ${rpc.error.message ?? "unknown"}`);
			const text = rpc.result?.content?.map((c) => c.text ?? "").join("\n").trim();
			if (text !== undefined) return text || "No results";
		} catch (error) {
			if (error instanceof Error && error.message.startsWith("Exa")) throw error;
		}
	}
	throw new Error("Exa search returned nothing readable");
}

const ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", mdash: "—", ndash: "–", hellip: "…" };

function decode(text: string): string {
	return text.replace(/&(#x[\da-f]+|#\d+|\w+);/gi, (whole, code: string) => {
		if (code[0] === "#") {
			const n = code[1]?.toLowerCase() === "x" ? parseInt(code.slice(2), 16) : parseInt(code.slice(1), 10);
			return Number.isFinite(n) ? String.fromCodePoint(n) : whole;
		}
		return ENTITIES[code.toLowerCase()] ?? whole;
	});
}

// Good-enough HTML to text: keep the main content, its structure and its links.
function htmlToText(html: string, base: string): string {
	const title = /<title[^>]*>([\s\S]*?)<\/title>/i.exec(html)?.[1]?.trim();
	let body = /<(main|article)[\s>][\s\S]*<\/\1>/i.exec(html)?.[0] ?? /<body[\s\S]*<\/body>/i.exec(html)?.[0] ?? html;
	body = body
		.replace(/<!--[\s\S]*?-->/g, "")
		.replace(/<(script|style|noscript|svg|template|iframe|nav|footer|form)[\s\S]*?<\/\1>/gi, "")
		.replace(/<h([1-6])[^>]*>/gi, (_m, n: string) => `\n\n${"#".repeat(Number(n))} `)
		.replace(/<li[^>]*>/gi, "\n- ")
		.replace(/<(pre|code)[^>]*>/gi, "`")
		.replace(/<\/(pre|code)>/gi, "`")
		.replace(/<a\s[^>]*href="([^"#][^"]*)"[^>]*>([\s\S]*?)<\/a>/gi, (_m, href: string, text: string) => {
			const label = text.replace(/<[^>]+>/g, "").trim();
			try {
				return label ? `${label} (${new URL(decode(href), base).href})` : "";
			} catch {
				return label;
			}
		})
		.replace(/<(br|\/p|\/div|\/tr|\/h[1-6]|\/ul|\/ol|\/table|\/section|\/blockquote)[^>]*>/gi, "\n")
		.replace(/<[^>]+>/g, "");
	const text = decode(body)
		.replace(/[ \t\f\v\r]+/g, " ")
		.replace(/ *\n */g, "\n")
		.replace(/\n{3,}/g, "\n\n")
		.trim();
	return title ? `# ${decode(title)}\n\n${text}` : text;
}

async function fetchPage(url: string, signal?: AbortSignal): Promise<{ text: string; type: string; finalUrl: string }> {
	const response = await fetch(url, {
		headers: { "User-Agent": USER_AGENT, Accept: "text/html,application/xhtml+xml,text/plain,application/json;q=0.9,*/*;q=0.5" },
		redirect: "follow",
		signal: withTimeout(signal),
	});
	if (!response.ok) throw new Error(`HTTP ${response.status} ${response.statusText} for ${url}`);
	const type = response.headers.get("content-type") ?? "";
	if (/pdf|image\/|audio\/|video\/|octet-stream|zip/i.test(type)) throw new Error(`${url} is ${type}, not a text page`);
	const raw = await response.text();
	const html = /html|xml/i.test(type) || /^\s*<(!doctype|html)/i.test(raw);
	return { text: html ? htmlToText(raw, response.url || url) : raw, type, finalUrl: response.url || url };
}

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: "web_search",
		label: "Web Search",
		description: "Search the web. Returns titles, URLs and snippets; read a full page with web_fetch.",
		parameters: Type.Object({
			query: Type.String({ description: "What to search for" }),
			numResults: Type.Optional(Type.Number({ description: "How many results, 1-10 (default 5)" })),
		}),
		async execute(_id, params, signal) {
			const count = Math.min(10, Math.max(1, Math.round(params.numResults ?? 5)));
			const text = await exaSearch(params.query, count, signal);
			return { content: [{ type: "text", text: clip(text, DEFAULT_CHARS) }], details: { chars: text.length } };
		},
		renderCall(args, theme) {
			return new Text(theme.fg("toolTitle", theme.bold("web_search ")) + theme.fg("muted", args.query ?? ""), 0, 0);
		},
		renderResult: (result, _options, theme) => renderSize(result, theme, "characters of results"),
	});

	pi.registerTool({
		name: "web_fetch",
		label: "Web Fetch",
		description: "Download a web page (or raw text/JSON) and return it as readable text with its links.",
		parameters: Type.Object({
			url: Type.String({ description: "http(s) URL to read" }),
			maxChars: Type.Optional(Type.Number({ description: `Characters to return (default ${DEFAULT_CHARS})` })),
		}),
		async execute(_id, params, signal) {
			if (!/^https?:\/\//i.test(params.url)) throw new Error("Only http(s) URLs can be fetched");
			const page = await fetchPage(params.url, signal);
			const text = clip(page.text, Math.max(1000, params.maxChars ?? DEFAULT_CHARS));
			const header = page.finalUrl !== params.url ? `(redirected to ${page.finalUrl})\n\n` : "";
			return { content: [{ type: "text", text: header + text }], details: { chars: page.text.length, url: page.finalUrl } };
		},
		renderCall(args, theme) {
			return new Text(theme.fg("toolTitle", theme.bold("web_fetch ")) + theme.fg("muted", args.url ?? ""), 0, 0);
		},
		renderResult: (result, _options, theme) => renderSize(result, theme, "characters"),
	});
}

// "12,345 characters", or the error text when the tool failed.
function renderSize(result: { content: { type: string; text?: string }[]; details?: unknown }, theme: Theme, unit: string) {
	const chars = (result.details as { chars?: number } | undefined)?.chars;
	if (chars !== undefined) return new Text(theme.fg("dim", `${chars.toLocaleString()} ${unit}`), 0, 0);
	return new Text(theme.fg("error", result.content.map((c) => c.text ?? "").join("\n")), 0, 0);
}
