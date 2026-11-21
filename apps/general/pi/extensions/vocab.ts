import { readFileSync, renameSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { type ExtensionAPI, type ExtensionContext, getAgentDir, type Theme } from "@earendil-works/pi-coding-agent";
import { type Component, type Focusable, fuzzyFilter, Input, Markdown, matchesKey, truncateToWidth, visibleWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui";
import { liveTheme } from "./lib/live.ts";

const FILE = join(getAgentDir(), "vocab.json");
const SHORTCUT = "alt+w";
const WIDTH = 48;
const LIST_ROWS = 6;
const MEANING_ROWS = 4;
const BLOCK = /\s*<!--\s*vocab\b([\s\S]*?)(?:-->|$)/g;
const BOLD = /\*\*([^*\n]{1,60})\*\*/g;
const CHAT_MARK = "•";
const STYLE = /\x1b\[[0-9;:]*m/g;
const ORIGINAL_RENDER = Symbol.for("dotfiles.pi.vocab.original");
const DRAWN_AT = Symbol.for("dotfiles.pi.vocab.generation");
const ORIGINAL_MOUSE = Symbol.for("dotfiles.pi.vocab.mouse");
const SQUIGGLED = /\x1b\[4:3m(?:\x1b\[58:[0-9:]*m)?(.*?)\x1b\[59m\x1b\[24m/g;

const PROMPT = `The user forgets terminology. When a reply uses a technical term or a project-specific name, even a basic one, write it in **bold** the first time, and end the reply with one hidden block that lists each new term:

<!-- vocab
term | plain definition, at most 15 words, no jargon
-->

At most 5 terms per reply, and no block when nothing is new. Skip terms that are already bold earlier in this conversation. The user cannot see the block, so never mention it.`;

type Entries = Record<string, string>;
type Found = [term: string, meaning: string];

let known = new Set<string>();
let generation = 0;
let openAt: ((term: string) => void) | undefined;

interface Keys {
	matches(data: string, keybinding: "tui.select.up" | "tui.select.down"): boolean;
}

function load(): Entries | undefined {
	let raw: string;
	try {
		raw = readFileSync(FILE, "utf8");
	} catch {
		return {};
	}
	try {
		const parsed = JSON.parse(raw);
		return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : undefined;
	} catch {
		return undefined;
	}
}

function know(entries: Entries): void {
	const terms = Object.keys(entries).map((term) => term.toLowerCase());
	if (terms.length === known.size && terms.every((term) => known.has(term))) return;
	known = new Set(terms);
	generation += 1;
}

function squiggleEachWord(text: string): string {
	const accent = liveTheme()?.getFgAnsi("accent").match(/\[38;([25]);([0-9;]+)m/);
	const colour = accent ? `\x1b[58:${accent[1]}:${accent[1] === "2" ? ":" : ""}${accent[2]!.replaceAll(";", ":")}m` : "";
	return text
		.split(" ")
		.map((word) => (word ? `\x1b[4:3m${colour}${word}\x1b[59m\x1b[24m` : word))
		.join(" ");
}

function underlineKnownTerms(): void {
	const prototype = Markdown?.prototype as any;
	if (typeof prototype?.render !== "function") return;
	const render: (width: number) => string[] = (prototype[ORIGINAL_RENDER] ??= prototype.render);
	prototype.render = function (this: any, width: number): string[] {
		const theme = this.theme;
		const bold: ((text: string) => string) | undefined = theme?.bold;
		if (!bold || known.size === 0) return render.call(this, width);
		if (this[DRAWN_AT] !== generation) {
			this[DRAWN_AT] = generation;
			this.invalidate();
		}
		theme.bold = (text: string) => (known.has(text.replace(STYLE, "").trim().toLowerCase()) ? bold(squiggleEachWord(text)) : bold(text));
		try {
			return render.call(this, width);
		} finally {
			theme.bold = bold;
		}
	};
}

function termAt(lines: string[], row: number, column: number, text: string): string | undefined {
	const line = lines[row];
	if (!line) return undefined;
	const words = [...line.matchAll(SQUIGGLED)].map((match) => {
		const start = visibleWidth(line.slice(0, match.index));
		const word = match[1]!.replace(STYLE, "");
		return { start, end: start + visibleWidth(word), word };
	});
	const hit = words.findIndex((word) => column >= word.start && column < word.end);
	if (hit < 0) return undefined;
	let first = hit;
	let last = hit;
	while (first > 0 && words[first - 1]!.end + 1 === words[first]!.start) first -= 1;
	while (last < words.length - 1 && words[last]!.end + 1 === words[last + 1]!.start) last += 1;
	const phrase = words
		.slice(first, last + 1)
		.map((word) => word.word)
		.join(" ")
		.toLowerCase();
	if (known.has(phrase)) return phrase;
	const within = text.toLowerCase();
	return [...known].find((term) => term.includes(phrase) && within.includes(term));
}

function openOnClick(): void {
	const prototype = Markdown?.prototype as any;
	if (typeof prototype?.render !== "function") return;
	if (!Object.hasOwn(prototype, ORIGINAL_MOUSE)) prototype[ORIGINAL_MOUSE] = prototype.handleMouse;
	const handleMouse: ((event: unknown) => unknown) | undefined = prototype[ORIGINAL_MOUSE];
	prototype.handleMouse = function (this: any, event: { type?: string; button?: string; x: number; y: number; width: number }) {
		const earlier = handleMouse?.call(this, event);
		if (earlier || event.type !== "click" || event.button !== "left" || !openAt || known.size === 0) return earlier;
		const term = termAt(this.render(event.width), event.y, event.x, this.text ?? "");
		if (!term) return undefined;
		openAt(term);
		return { handled: true };
	};
}

function save(entries: Entries): void {
	const draft = `${FILE}.${process.pid}.tmp`;
	try {
		writeFileSync(draft, `${JSON.stringify(entries, null, 1)}\n`);
		renameSync(draft, FILE);
	} catch {}
}

function extract(text: string): { text: string; found: Found[] } {
	const found: Found[] = [];
	const rest = text.replace(BLOCK, (_block, body: string) => {
		for (const line of body.split("\n")) {
			const cut = line.indexOf("|");
			if (cut < 1) continue;
			const term = line.slice(0, cut).replace(/[*`]/g, "").trim();
			const meaning = line.slice(cut + 1).trim();
			if (term && meaning && term.length <= 60) found.push([term, meaning.slice(0, 240)]);
		}
		return "";
	});
	return { text: rest, found };
}

function remember(found: Found[]): void {
	const entries = load();
	if (!entries) return;
	const stored = new Set(Object.keys(entries).map((term) => term.toLowerCase()));
	let added = false;
	for (const [term, meaning] of found) {
		const lower = term.toLowerCase();
		if (stored.has(lower)) continue;
		entries[term] = meaning;
		stored.add(lower);
		added = true;
	}
	if (added) save(entries);
	know(entries);
}

function usedInChat(ctx: ExtensionContext, entries: Entries): string[] {
	const stored = new Map(Object.keys(entries).map((term) => [term.toLowerCase(), term]));
	const perReply: string[][] = [];
	for (const entry of ctx.sessionManager.getBranch()) {
		if (entry.type !== "message" || entry.message.role !== "assistant") continue;
		const used: string[] = [];
		for (const part of entry.message.content) {
			if (part.type !== "text") continue;
			for (const match of part.text.matchAll(BOLD)) {
				const term = stored.get(match[1]!.trim().toLowerCase());
				if (term) used.push(term);
			}
		}
		perReply.push(used);
	}
	return [...new Set(perReply.reverse().flat())];
}

function newestFirst(entries: Entries, chat: string[]): string[] {
	const taken = new Set(chat);
	return [...chat, ...Object.keys(entries).reverse().filter((term) => !taken.has(term))];
}

class Dictionary implements Component, Focusable {
	private readonly tui: { requestRender(): void };
	private readonly theme: Theme;
	private readonly keys: Keys;
	private readonly entries: Entries;
	private readonly terms: string[];
	private readonly chat: Set<string>;
	private readonly close: () => void;
	private readonly input = new Input({ prompt: "> " });
	private shown: string[];
	private at = 0;

	constructor(tui: { requestRender(): void }, theme: Theme, keys: Keys, entries: Entries, chat: string[], selected: string | undefined, close: () => void) {
		this.tui = tui;
		this.theme = theme;
		this.keys = keys;
		this.entries = entries;
		this.terms = newestFirst(entries, chat);
		this.chat = new Set(chat);
		this.close = close;
		this.shown = this.terms;
		if (selected) this.select(selected);
	}

	select(wanted: string): void {
		this.input.setValue("");
		this.shown = this.terms;
		this.at = Math.max(0, this.terms.findIndex((term) => term.toLowerCase() === wanted));
		this.tui.requestRender();
	}

	get focused(): boolean {
		return this.input.focused;
	}

	set focused(value: boolean) {
		this.input.focused = value;
	}

	private filter(): void {
		const query = this.input.getValue().trim();
		this.at = 0;
		if (!query) {
			this.shown = this.terms;
			return;
		}
		const byName = fuzzyFilter(this.terms, query, (term) => term);
		const named = new Set(byName);
		const needle = query.toLowerCase();
		const byMeaning = this.terms.filter((term) => !named.has(term) && this.entries[term]!.toLowerCase().includes(needle));
		this.shown = [...byName, ...byMeaning];
	}

	private move(by: number): void {
		this.at = Math.max(0, Math.min(this.shown.length - 1, this.at + by));
	}

	handleInput(data: string): void {
		if (matchesKey(data, "escape") || matchesKey(data, "ctrl+c") || matchesKey(data, SHORTCUT)) {
			this.close();
			return;
		}
		if (matchesKey(data, "ctrl+k") || this.keys.matches(data, "tui.select.up")) this.move(-1);
		else if (matchesKey(data, "ctrl+j") || this.keys.matches(data, "tui.select.down")) this.move(1);
		else if (matchesKey(data, "ctrl+h")) this.move(-LIST_ROWS);
		else if (matchesKey(data, "ctrl+l")) this.move(LIST_ROWS);
		else {
			const before = this.input.getValue();
			this.input.handleInput(data);
			if (this.input.getValue() !== before) this.filter();
		}
		this.tui.requestRender();
	}

	render(width: number): string[] {
		const inner = Math.min(width, WIDTH) - 4;
		if (inner < 20) return [];
		const { theme, shown, at } = this;
		const edge = (text: string) => theme.fg("border", text);
		const row = (text = "") => {
			const fitted = truncateToWidth(text, inner);
			return `${edge("│")} ${fitted}${" ".repeat(Math.max(0, inner - visibleWidth(fitted)))} ${edge("│")}`;
		};

		const lines = [
			`${edge("╭─ ")}${theme.fg("accent", "vocab")}${edge(` ${"─".repeat(inner - 20)} `)}${theme.fg("muted", `${CHAT_MARK} this chat`)}${edge(" ─╮")}`,
			row(this.input.render(inner)[0] ?? ""),
			row(),
		];

		const top = Math.max(0, Math.min(at - Math.floor(LIST_ROWS / 2), shown.length - LIST_ROWS));
		for (let i = 0; i < LIST_ROWS; i++) {
			const term = shown[top + i];
			if (term === undefined) {
				lines.push(row(i === 0 && shown.length === 0 ? theme.fg("muted", this.terms.length ? "no match" : "no terms yet") : ""));
				continue;
			}
			const mark = this.chat.has(term) ? theme.fg("muted", ` ${CHAT_MARK}`) : "";
			const name = truncateToWidth(term, inner - 4);
			lines.push(row(top + i === at ? `${theme.fg("accent", theme.bold(`▸ ${name}`))}${mark}` : `  ${name}${mark}`));
		}

		lines.push(row());
		const selected = shown[at];
		const meaning = selected === undefined ? [] : wrapTextWithAnsi(this.entries[selected]!, inner);
		for (let i = 0; i < MEANING_ROWS; i++) lines.push(row(meaning[i] ?? ""));

		const count = ` ${shown.length ? at + 1 : 0}/${shown.length} `;
		lines.push(edge(`╰${"─".repeat(inner + 1 - count.length)}${count}─╯`));
		return lines;
	}

	invalidate(): void {}
}

export default function (pi: ExtensionAPI) {
	let open: Dictionary | undefined;
	let opening = false;
	know(load() ?? {});
	underlineKnownTerms();
	openOnClick();

	const show = async (ctx: ExtensionContext, selected?: string) => {
		if (ctx.mode !== "tui") return;
		if (open && selected) open.select(selected);
		if (open || opening) return;
		const entries = load();
		if (!entries) {
			ctx.ui.notify(`${FILE} is not valid JSON`, "error");
			return;
		}
		know(entries);
		opening = true;
		try {
			await ctx.ui.custom<void>(
				(tui: { requestRender(): void }, theme: Theme, keys: Keys, done: () => void) =>
					(open = new Dictionary(tui, theme, keys, entries, usedInChat(ctx, entries), selected, done)),
				{ overlay: true, overlayOptions: { anchor: "top-right", width: WIDTH, margin: 1 } },
			);
		} finally {
			open = undefined;
			opening = false;
		}
	};

	pi.on("session_start", async (_event, ctx) => {
		openAt = (term) => void show(ctx, term);
	});

	pi.registerShortcut(SHORTCUT, { description: "Open or close the vocab dictionary", handler: async (ctx) => show(ctx) });
	pi.registerCommand("vocab", {
		description: "Open the vocab dictionary (alt+w)",
		handler: async (_args, ctx) => show(ctx),
	});

	pi.on("before_agent_start", async (event, ctx) => {
		if (ctx.hasUI) event.systemPromptOptions.sections.vocab = PROMPT;
		else delete event.systemPromptOptions.sections.vocab;
	});

	pi.on("message_end", async (event) => {
		if (event.message.role !== "assistant") return;
		const found: Found[] = [];
		let changed = false;
		const content = event.message.content.map((part) => {
			if (part.type !== "text" || !part.text.includes("<!--")) return part;
			const result = extract(part.text);
			if (result.text === part.text) return part;
			changed = true;
			found.push(...result.found);
			return { ...part, text: result.text };
		});
		if (!changed) return;
		remember(found);
		return { message: { ...event.message, content } };
	});
}
