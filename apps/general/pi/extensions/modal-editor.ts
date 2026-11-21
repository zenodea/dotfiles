/**
 * Modal Editor - vim mode for pi's prompt. Starts in normal mode; Escape goes to
 * normal, and in normal mode passes through (aborts the agent, etc.).
 *   counts      3w 2dd 5x d2w ...
 *   move        h j k l  w b e W B E  0 ^ $  gg G  f F t T ; ,  %  [ ] sentences  { } paragraphs
 *               (k on the first line and j on the last browse prompt history)
 *   operators   d c y + any motion or text object; dd cc yy for lines
 *   objects     iw aw iW aW  i" a" i' a' i` a`  i( a( ib  i[ a[  i{ a{ iB  i< a<  is as  ip ap
 *   edit        x X s S D C Y  p P  J  ~  r{char}  u  ctrl+r redo  . repeat
 *   insert      i a I A o O
 *   select      v / V, then motions, text objects or o; y d x c s ~ u U J p act on it
 *   transcript  ctrl+u / ctrl+d half page, ctrl+b / ctrl+f page, ctrl+y / ctrl+e line
 *   reading     (label READING) with an empty prompt, a cursor walks the transcript and lights up
 *               the sentence or table cell under it (lib/reader.ts):
 *               h j k l move   [ ] sentences   { } paragraphs   ( ) messages
 *               gg G first / last   0 $ line   y copy what is lit   Escape hide
 * Also: the terminal cursor's shape shows the mode, pi's working indicator sits on
 * the top border, footer.ts's status line is drawn into the bottom border, and the
 * terminal title drops pi's "π - " prefix.
 */

import { CustomEditor, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { type KeyId, matchesKey, truncateToWidth, type TuiMouseEvent, visibleWidth } from "@earendil-works/pi-tui";
import { liveTheme, transcript } from "./lib/live.ts";
import { paintColumns, Reader } from "./lib/reader.ts";
import { type Find, firstNonBlank, lastChar, lineEnd, lineStart, motion, type Range, type Target, textObject, toLineCol, toOffset } from "./lib/vim.ts";

const reader = new Reader();
const READER_KEYS = new Set(["h", "j", "k", "l", "[", "]", "{", "}", "(", ")", "gg", "G", "0", "$"]);
const READER_MARGIN = 2;

const STATUS_LINE = Symbol.for("dotfiles.pi.status-line");

// DECSCUSR cursor shapes (steady), and the reset to the terminal's default.
const CURSOR_SHAPE = { insert: "\x1b[6 q", normal: "\x1b[2 q", visual: "\x1b[2 q", vline: "\x1b[2 q" };
const CURSOR_SHAPE_RESET = "\x1b[0 q";
const UP = "\x1b[A";
const DOWN = "\x1b[B";

const MODE_LABEL = { insert: " INSERT ", normal: " NORMAL ", visual: " VISUAL ", vline: " V-LINE ", reading: " READING " };
// Theme colours each mode's label may be filled with, first choice first. A choice that
// looks the same as NORMAL's accent is skipped, so the modes never share a colour.
const MODE_COLORS = {
	normal: ["accent"],
	insert: ["success", "warning"],
	visual: ["syntaxKeyword", "error"],
	vline: ["syntaxKeyword", "error"],
	reading: ["syntaxFunction", "syntaxNumber"],
} as const;

// A command that is still being typed: a count, an operator, g, f/t/r, or i/a of a text object.
const UNFINISHED = /^(g|[fFtTr]|[ia])$/;

// Transcript scrolling, in viewport fractions (or single lines).
const SCROLLS: [key: KeyId, pages: number, lines: number][] = [
	["ctrl+u", -0.5, 0],
	["ctrl+d", 0.5, 0],
	["ctrl+b", -1, 0],
	["ctrl+f", 1, 0],
	["ctrl+y", 0, -1],
	["ctrl+e", 0, 1],
];

// READING is only a label: normal mode while the reading cursor is out.
type Mode = Exclude<keyof typeof MODE_LABEL, "reading">;
type Snapshot = { text: string; pos: number };
type Change = { keys: string; typed: string[] };

class ModalEditor extends CustomEditor {
	private mode: Mode = "normal";
	private keys = "";
	// Where a selection started; the cursor is its other end.
	private anchor = 0;
	// The column j and k aim for.
	private goal = 0;
	private register = { text: "", linewise: false };
	private lastFind: Find | undefined;
	private undos: Snapshot[] = [];
	private redos: Snapshot[] = [];
	// The last change, for "."; an insert-mode change keeps what was typed.
	private lastChange: Change | undefined;
	private typing: Change | undefined;
	private replaying = false;

	// The cursor as an offset into the text.
	private get pos(): number {
		const { line, col } = this.getCursor();
		return toOffset(this.getText(), line, col);
	}

	// Move the cursor; outside insert mode it stays on a character.
	private place(pos: number): void {
		const t = this.getText();
		pos = Math.max(0, Math.min(pos, t.length));
		if (this.mode !== "insert") pos = Math.min(pos, lastChar(t, pos));
		const { line, col } = toLineCol(t, pos);
		const state = (this as any).state;
		state.cursorLine = line;
		state.cursorCol = col;
		this.tui.requestRender();
	}

	private base(data: string): void {
		super.handleInput(data);
	}

	// Replace the text but keep pi's store of large pastes, which setText clears.
	private write(text: string): void {
		const editor = this as any;
		const pastes = new Map(editor.pastes ?? []);
		const counter = editor.pasteCounter;
		this.setText(text);
		for (const [id, paste] of pastes) editor.pastes?.set(id, paste);
		if (counter !== undefined) editor.pasteCounter = counter;
	}

	private snapshot(): void {
		this.undos.push({ text: this.getText(), pos: this.pos });
		this.redos = [];
	}

	private change(text: string, pos: number, keys?: string): void {
		this.snapshot();
		this.write(text);
		this.place(pos);
		if (keys && !this.replaying) this.lastChange = { keys, typed: [] };
	}

	private undo(redo: boolean, count: number): void {
		const [from, to] = redo ? [this.redos, this.undos] : [this.undos, this.redos];
		for (let i = 0; i < count && from.length; i++) {
			const snap = from.pop()!;
			to.push({ text: this.getText(), pos: this.pos });
			this.write(snap.text);
			this.place(snap.pos);
		}
	}

	// Enter insert mode; a command that already changed the text has taken its snapshot.
	private insert(keys: string, snapshot = true): void {
		if (snapshot) this.snapshot();
		this.mode = "insert";
		this.typing = this.replaying ? undefined : { keys, typed: [] };
	}

	private stopInsert(): void {
		this.mode = "normal";
		const top = this.undos[this.undos.length - 1];
		if (top && top.text === this.getText()) this.undos.pop();
		if (this.typing?.keys) this.lastChange = this.typing;
		this.typing = undefined;
		const p = this.pos;
		this.place(p > lineStart(this.getText(), p) ? p - 1 : p);
	}

	// "." runs the last change again, typed text included.
	private repeat(count: number): void {
		const change = this.lastChange;
		if (!change) return;
		this.replaying = true;
		try {
			for (let i = 0; i < count; i++) {
				this.run(change.keys);
				if (this.mode !== "insert") continue;
				for (const data of change.typed) this.base(data);
				this.stopInsert();
			}
		} finally {
			this.replaying = false;
		}
	}

	// [from, to) of the visual selection; V takes whole lines.
	private selected(): Range {
		const t = this.getText();
		const [a, b] = [Math.min(this.anchor, this.pos), Math.max(this.anchor, this.pos)];
		return this.mode === "vline" ? [lineStart(t, a), lineEnd(t, b), true] : [a, Math.min(t.length, b + 1)];
	}

	// count whole lines from the cursor's line.
	private lines(count: number): Range {
		const t = this.getText();
		let end = lineEnd(t, this.pos);
		for (let i = 1; i < count && end < t.length; i++) end = lineEnd(t, end + 1);
		return [lineStart(t, this.pos), end, true];
	}

	// The range an operator takes from the cursor to a motion's target.
	private span(target: Target, op: string, key: string, count: number): Range {
		const t = this.getText();
		const p = this.pos;
		// cw on a word acts like ce: the space after it stays.
		if (op === "c" && /^[wW]$/.test(key) && !/\s/.test(t[p] ?? " ")) target = motion(t, p, key === "w" ? "e" : "E", count, false, 0)!;
		let [from, to] = p <= target.pos ? [p, target.pos] : [target.pos, p];
		if (target.inclusive) to++;
		// dw on a line's last word stops at the line end.
		if (/^[wW]$/.test(key) && to > lineEnd(t, from)) to = lineEnd(t, from);
		return [from, to, target.linewise];
	}

	private operate(op: string, [from, to, linewise]: Range, keys: string): void {
		const t = this.getText();
		if (linewise) [from, to] = [lineStart(t, from), lineEnd(t, to)];
		const text = t.slice(from, to) + (linewise ? "\n" : "");
		this.register = { text, linewise: !!linewise };
		if (op === "y") {
			(this.tui as any).copyTextToClipboard?.(text);
			return this.place(linewise ? this.pos : from);
		}
		// Deleting whole lines takes a newline with them; changing them leaves an empty line.
		if (linewise && op === "d") {
			if (to < t.length) to++;
			else if (from > 0) from--;
		}
		const next = t.slice(0, from) + t.slice(to);
		this.change(next, linewise && op === "d" ? firstNonBlank(next, Math.min(from, next.length)) : from, op === "c" ? undefined : keys);
		if (op === "c") {
			this.insert(keys, false);
			this.place(from);
		}
	}

	private paste(before: boolean, count: number, keys: string): void {
		const { text, linewise } = this.register;
		if (!text) return;
		const t = this.getText();
		const p = this.pos;
		const body = text.repeat(count);
		if (linewise) {
			const at = before ? lineStart(t, p) : lineEnd(t, p);
			const added = before ? body : `\n${body.slice(0, -1)}`;
			const next = t.slice(0, at) + added + t.slice(at);
			return this.change(next, firstNonBlank(next, before ? at : at + 1), keys);
		}
		const at = before ? p : Math.min(p + 1, lineEnd(t, p));
		this.change(t.slice(0, at) + body + t.slice(at), at + body.length - 1, keys);
	}

	// Rewrite a range: toggle, lower or upper case.
	private recase([from, to]: Range, how: string, keys?: string): void {
		const t = this.getText();
		const flip = (ch: string) => (ch === ch.toUpperCase() ? ch.toLowerCase() : ch.toUpperCase());
		const part = t.slice(from, to);
		const cased = how === "u" ? part.toLowerCase() : how === "U" ? part.toUpperCase() : [...part].map(flip).join("");
		this.change(t.slice(0, from) + cased + t.slice(to), how === "~" && keys ? to : from, keys);
	}

	// Join the lines of [from, to] (at least two), with one space where each break was.
	private join([from, to]: Range, keys?: string): void {
		const t = this.getText();
		const end = Math.max(lineEnd(t, to), lineEnd(t, lineEnd(t, from) + 1));
		if (lineEnd(t, from) >= t.length) return;
		this.change(t.slice(0, from) + t.slice(from, end).replace(/\n[ \t]*/g, " ") + t.slice(end), lineEnd(t, from), keys);
	}

	private moveTo(target: Target, key: string): void {
		if (target.find) this.lastFind = target.find;
		this.place(target.pos);
		if (key === "$") this.goal = Number.POSITIVE_INFINITY;
		else if (key !== "j" && key !== "k") this.goal = toLineCol(this.getText(), this.pos).col;
	}

	// One key of a normal or visual command; runs once the command is complete.
	private feed(data: string): void {
		this.keys += data;
		if (this.run(this.keys) !== "more") this.keys = "";
	}

	private run(keys: string): "more" | void {
		const t = this.getText();
		const p = this.pos;
		if (this.mode === "visual" || this.mode === "vline") return this.visualKey(keys);

		// With an empty prompt the keys read the transcript; y copies what is lit.
		if (!t && /^([1-9]\d*)?y$/.test(keys)) return void this.read("y", 1);
		const m = /^([1-9]\d*)?(?:([dcy])([1-9]\d*)?)?([\s\S]*)$/.exec(keys)!;
		const hasCount = Boolean(m[1] || m[3]);
		const count = Number(m[1] ?? 1) * Number(m[3] ?? 1);
		const op = m[2];
		const rest = m[4]!;
		if (!rest || (UNFINISHED.test(rest) && (op || !/^[ia]$/.test(rest)))) return "more";
		if (!t && !op && READER_KEYS.has(rest) && this.read(rest, count)) return;

		if (op && rest === op) return this.operate(op, this.lines(count), keys);
		if (op && /^[ia].$/.test(rest)) {
			const range = textObject(t, p, rest);
			return range && this.operate(op, range, keys);
		}
		// k on the first line and j on the last browse prompt history, as before.
		const { line } = toLineCol(t, p);
		if (!op && count === 1 && ((rest === "k" && line === 0) || (rest === "j" && lineEnd(t, p) >= t.length))) return this.base(rest === "k" ? UP : DOWN);
		const target = motion(t, p, rest, count, hasCount, this.goal, this.lastFind);
		if (target && op) return this.operate(op, this.span(target, op, rest, count), keys);
		if (target) return this.moveTo(target, rest);
		if (!op) this.command(rest, count, keys);
	}

	private command(key: string, count: number, keys: string): void {
		const t = this.getText();
		const p = this.pos;
		const [start, end] = [lineStart(t, p), lineEnd(t, p)];
		switch (key) {
			case "i":
				return this.insert(keys);
			case "a":
				this.insert(keys);
				return this.place(Math.min(p + 1, end));
			case "I":
				this.insert(keys);
				return this.place(firstNonBlank(t, p));
			case "A":
				this.insert(keys);
				return this.place(end);
			case "o":
			case "O": {
				const at = key === "o" ? end : start;
				this.change(`${t.slice(0, at)}\n${t.slice(at)}`, key === "o" ? at + 1 : at);
				this.insert(keys, false);
				return this.place(key === "o" ? at + 1 : at);
			}
			case "x":
				return end > start ? this.operate("d", [p, Math.min(end, p + count)], keys) : undefined;
			case "X":
				return p > start ? this.operate("d", [Math.max(start, p - count), p], keys) : undefined;
			case "s":
				return this.operate("c", [p, Math.min(end, p + count)], keys);
			case "S":
				return this.operate("c", this.lines(count), keys);
			case "D":
			case "C":
				return this.operate(key === "D" ? "d" : "c", [p, this.lines(count)[1]], keys);
			case "Y":
				return this.operate("y", this.lines(count), keys);
			case "p":
			case "P":
				return this.paste(key === "P", count, keys);
			case "J":
				return this.join([p, this.lines(Math.max(2, count))[1]], keys);
			case "~":
				if (end > start) this.recase([p, Math.min(end, p + count)], "~", keys);
				return;
			case "u":
				return this.undo(false, count);
			case ".":
				return this.repeat(count);
			case "v":
			case "V":
				this.anchor = p;
				this.mode = key === "v" ? "visual" : "vline";
				return this.tui.requestRender();
		}
		if (/^r.$/s.test(key) && p + count <= end) this.change(t.slice(0, p) + key[1]!.repeat(count) + t.slice(p + count), p + count - 1, keys);
	}

	private visualKey(keys: string): "more" | void {
		const m = /^([1-9]\d*)?([\s\S]*)$/.exec(keys)!;
		const count = Number(m[1] ?? 1);
		const rest = m[2]!;
		if (!rest || UNFINISHED.test(rest)) return "more";
		const t = this.getText();
		if (/^[ia].$/.test(rest)) {
			const range = textObject(t, this.pos, rest);
			if (!range) return;
			if (range[2]) this.mode = "vline";
			this.anchor = range[0];
			return this.place(range[1] - 1);
		}
		const target = motion(t, this.pos, rest, count, Boolean(m[1]), this.goal, this.lastFind);
		if (target) return this.moveTo(target, rest);

		const range = this.selected();
		if (rest === "v" || rest === "V") {
			const mode = rest === "v" ? "visual" : "vline";
			this.mode = this.mode === mode ? "normal" : mode;
			return this.place(this.pos);
		}
		if (rest === "o") {
			const p = this.pos;
			this.place(this.anchor);
			this.anchor = p;
			return;
		}
		// The selection's actions; any other key leaves the selection as it is.
		if (!["y", "d", "x", "c", "s", "~", "u", "U", "J", "p"].includes(rest)) return;
		this.mode = "normal";
		if ("ydxcs".includes(rest)) return this.operate(rest === "x" ? "d" : rest === "s" ? "c" : rest, range, "");
		if ("~uU".includes(rest)) return this.recase(range, rest);
		if (rest === "J") return this.join(range);
		// p replaces the selection with the register.
		const { text, linewise } = this.register;
		const body = linewise && range[2] ? text.slice(0, -1) : text;
		this.change(t.slice(0, range[0]) + body + t.slice(range[1]), range[0] + Math.max(0, body.length - 1));
	}

	// Paint [from, to) onto the rendered rows. Rows between the borders are padding
	// plus one wrapped chunk of the text, styled however pi likes, so ranges are
	// placed by visible columns and painted around any escapes.
	private paintRange(lines: string[], width: number, [from, to]: Range, open: string): void {
		const editor = this as any;
		const pad = Math.min(editor.paddingX ?? 0, Math.max(0, Math.floor((width - 1) / 2)));
		const text = this.getLines();
		const all = this.getText();
		const [start, end] = [toLineCol(all, from), toLineCol(all, to)];

		// Which logical line and offsets each wrapped row holds.
		const layout: { text: string }[] = editor.layoutText(editor.lastWidth);
		const rows: { line: number; from: number; to: number }[] = [];
		for (let line = 0, at = 0; line < text.length && at < layout.length; line++) {
			let a = 0;
			do {
				const b = a + layout[at++]!.text.length;
				rows.push({ line, from: a, to: b });
				a = b;
			} while (a < text[line]!.length && at < layout.length);
		}

		const visible = editor.renderedVisibleLineCount ?? 0;
		for (let index = 0; index < visible; index++) {
			const row = rows[(editor.scrollOffset ?? 0) + index];
			const rendered = lines[index + 1];
			if (!row || rendered === undefined || row.line < start.line || row.line > end.line) continue;
			const a = Math.max(row.from, row.line === start.line ? start.col : 0);
			const b = Math.min(row.to, row.line === end.line ? end.col : row.to);
			const line = text[row.line] ?? "";
			// An empty stretch (a blank line, or the newline itself) still shows one cell.
			const x = pad + visibleWidth(line.slice(row.from, Math.min(a, row.to)));
			const y = b > a ? pad + visibleWidth(line.slice(row.from, b)) : x + 1;
			lines[index + 1] = paintColumns(rendered, x, y, open);
		}
	}

	private shape = "";

	// Keep the terminal's own cursor on (pi then stops drawing its fake one) and
	// shaped for the mode.
	private syncCursor(): void {
		const host = this.tui as any;
		if (host.getShowHardwareCursor?.() === false) host.setShowHardwareCursor?.(true);
		const shape = CURSOR_SHAPE[this.mode];
		if (shape !== this.shape) {
			this.shape = shape;
			(this.tui as any).terminal?.write?.(shape);
		}
	}

	// A filled block in the mode's colour: bold, with the colour as the background.
	private paintLabel(label: string): string {
		const theme = liveTheme();
		if (!theme) return label;
		const choices: readonly string[] = MODE_COLORS[this.shownMode()];
		const accent = theme.fg("accent", "x");
		const color = choices.find((c) => c === "accent" || theme.fg(c as any, "x") !== accent) ?? choices[choices.length - 1]!;
		return theme.fg(color as any, `\x1b[1;3;7m${label}\x1b[22;23;27m`);
	}

	private shownMode(): keyof typeof MODE_LABEL {
		return this.mode === "normal" && reader.active ? "reading" : this.mode;
	}

	// The fullscreen renderer owns the transcript's scroll view; regular mode has none.
	// A visible reading cursor moves with the page, as in vim.
	private scrollTranscript(pages: number, lines: number): void {
		const tui = this.tui as any;
		const view = tui.getPrimaryScrollView?.();
		if (!view) return;
		const delta = lines + Math.trunc(pages * Math.max(2, view.viewportHeight));
		tui.scrollBy?.(delta);
		if (reader.cursor && pages !== 0) reader.cursor = { ...reader.cursor, row: Math.max(0, reader.cursor.row + delta) };
	}

	// Reading keys with an empty prompt. The first key only shows the cursor
	// (on the sentence nearest the middle); jumps also move from there.
	private read(command: string, count = 1): boolean {
		const tui = this.tui as any;
		const found = transcript(tui);
		if (!found) return false;
		const { view, rows } = found;
		if (command === "y") {
			const text = reader.text(rows);
			if (text) tui.copyTextToClipboard?.(text);
			return true;
		}
		const starting = !reader.active;
		if (starting) reader.start(rows, view.scrollTop, view.viewportHeight);
		if (!(starting && "hjkl".includes(command)) && !reader.move(rows, command, count)) return false;

		// hjkl scroll only at the edges; a jump that lands outside the middle half
		// brings the lit text to the middle of the screen, like vim's zz.
		const row = reader.cursor!.row;
		const height = Math.max(1, view.viewportHeight);
		const top = view.scrollTop;
		if ("hjkl".includes(command)) {
			if (row < top + READER_MARGIN) view.scrollTo(Math.max(0, row - READER_MARGIN), { disableFollow: true });
			else if (row >= top + height - READER_MARGIN) view.scrollTo(row - height + 1 + READER_MARGIN, { disableFollow: true });
		} else if (row < top + height / 4 || row >= top + (height * 3) / 4) {
			view.scrollTo(Math.max(0, row - Math.floor(height / 2)), { disableFollow: true });
		}
		tui.requestRender();
		return true;
	}

	handleInput(data: string): void {
		this.handleKey(data);
		// The reading cursor belongs to an empty prompt in normal mode.
		if (reader.active && (this.mode !== "normal" || this.getText() !== "")) {
			reader.stop();
			this.tui.requestRender();
		}
	}

	private handleKey(data: string): void {
		// Escape leaves insert or visual mode, drops a half-typed command, hides the
		// reading cursor, or passes through (aborts the agent, etc.).
		if (matchesKey(data, "escape")) {
			if (this.mode === "insert") return this.stopInsert();
			if (this.mode !== "normal" || this.keys) {
				this.mode = "normal";
				this.keys = "";
				return this.place(this.pos);
			}
			if (reader.active) {
				reader.stop();
				return this.tui.requestRender();
			}
			return this.base(data);
		}

		if (this.mode === "insert") {
			const submit = matchesKey(data, "enter");
			this.base(data);
			if (submit) this.typing = undefined;
			else this.typing?.typed.push(data);
			if (!this.getText()) [this.undos, this.redos] = [[], []];
			return;
		}

		for (const [key, pages, lines] of SCROLLS) {
			if (matchesKey(data, key)) return this.scrollTranscript(pages, lines);
		}
		if (matchesKey(data, "ctrl+r")) return this.undo(true, 1);

		// Printable keys are commands; control keys (enter, arrows, ...) go to pi's editor.
		if (data.length === 1 && data.charCodeAt(0) >= 32) return this.feed(data);
		this.keys = "";
		if (this.mode !== "normal") this.mode = "normal";
		this.base(data);
		if (!this.getText()) [this.undos, this.redos] = [[], []];
	}

	private listHeight(): number {
		return ((this as any).autocompleteMaxVisible ?? 5) + 1;
	}

	render(width: number): string[] {
		const lines = this.renderEditor(width);
		const list = (this as any).renderedAutocompleteHeight ?? 0;
		if (list <= 0 || list >= lines.length) return lines;
		const editorRows = lines.length - list;
		const padding = Array.from({ length: Math.max(0, this.listHeight() - list) }, () => " ".repeat(width));
		return [this.borderColor("─".repeat(width)), ...lines.slice(editorRows), ...padding, ...lines.slice(0, editorRows)];
	}

	handleMouse(event: TuiMouseEvent): ReturnType<CustomEditor["handleMouse"]> {
		const list = (this as any).renderedAutocompleteHeight ?? 0;
		if (list <= 0) return super.handleMouse(event);
		const editorRows = ((this as any).renderedVisibleLineCount ?? 0) + 2;
		const above = 1 + Math.max(list, this.listHeight());
		if (event.y >= above) return super.handleMouse({ ...event, y: event.y - above });
		if (event.y >= 1 && event.y <= list) return super.handleMouse({ ...event, y: event.y - 1 + editorRows });
		return undefined;
	}

	private renderEditor(width: number): string[] {
		const lines = super.render(width);
		if (lines.length === 0) return lines;
		if (hardwareCursor) {
			this.syncCursor();
			if (this.mode === "visual" || this.mode === "vline") this.paintRange(lines, width, this.selected(), "\x1b[7m");
		}

		// Add mode indicator to bottom border
		const label = MODE_LABEL[this.shownMode()];
		// The bottom border follows the visible text rows; an open autocomplete list comes after it.
		const last = Math.min(lines.length - 1, 1 + ((this as any).renderedVisibleLineCount ?? lines.length));
		const border = lines[last]!;
		if (visibleWidth(border) < label.length) return lines;

		// footer.ts publishes the status line, widest variant first; draw it into
		// the same border. A border carrying its own text (a scroll hint) is left alone.
		const status = (globalThis as any)[STATUS_LINE]?.() as string[] | undefined;
		if (status?.length && /^─+$/.test(border.replace(/\x1b\[[0-9;]*m/g, ""))) {
			const rule = (n: number) => truncateToWidth(border, n, "");
			const room = width - label.length - 4;
			const fits = status.find((text) => visibleWidth(text) <= room);
			const left = fits ?? truncateToWidth(status[status.length - 1]!, room, "…");
			lines[last] = `${rule(1)} ${left} ${rule(room - visibleWidth(left) + 1)}${this.paintLabel(label)}`;
			return lines;
		}

		lines[last] = truncateToWidth(border, width - label.length, "") + this.paintLabel(label);
		return lines;
	}
}

// Whether this session switched the terminal's cursor on; false leaves pi's drawn cursor alone.
let hardwareCursor = false;

// The fullscreen renderer runs every frame through applySearchHighlights after
// laying it out; the reading highlight is painted in the same pass. The hook goes
// in once per TUI and calls the latest painter, so /reload swaps in new code.
const READER_PAINT = Symbol.for("dotfiles.pi.reader-paint");
const READER_HOOK = Symbol.for("dotfiles.pi.reader-hook");
function paintReaderOn(host: any): void {
	host[READER_PAINT] = (painted: string[], layout: any) => {
		const theme = liveTheme();
		const view = host.getPrimaryScrollView?.();
		if (!reader.active || !theme || !view) return painted;
		const find = (box: any): any => (box?.scrollView === view ? box : box?.children?.map(find).find(Boolean));
		const box = find(layout?.root);
		const rows = box?.scrollContentLines;
		return rows ? reader.paint(painted, rows, box, view.scrollTop, theme) : painted;
	};
	if (host[READER_HOOK] || typeof host.applySearchHighlights !== "function") return;
	const original = host.applySearchHighlights.bind(host);
	host.applySearchHighlights = (screen: string[], layout: any) => host[READER_PAINT](original(screen, layout), layout);
	host[READER_HOOK] = true;
}

// pi titles the terminal "π - <session name> - <folder>" (Rex shows it as the
// window name); every title it writes loses the "π - ".
const TITLE_PATCHED = Symbol.for("dotfiles.pi.title-prefix");
function dropTitlePrefix(terminal: any): void {
	if (!terminal || terminal[TITLE_PATCHED] || typeof terminal.setTitle !== "function") return;
	const setTitle = terminal.setTitle.bind(terminal);
	terminal.setTitle = (title: string) => setTitle(String(title).replace(/^π - /, ""));
	terminal[TITLE_PATCHED] = true;
}

export default function (pi: ExtensionAPI) {
	let restore: (() => void) | undefined;

	pi.on("session_start", (_event, ctx) => {
		ctx.ui.setEditorComponent((tui, theme, kb) => {
			const host = tui as any;
			if (typeof host.setShowHardwareCursor === "function" && typeof host.terminal?.write === "function") {
				host.setShowHardwareCursor(true);
				hardwareCursor = true;
				restore = () => host.terminal.write(CURSOR_SHAPE_RESET);
			}
			paintReaderOn(host);
			dropTitlePrefix(host.terminal);
			// Draw pi's working indicator on the top border instead of on a row of its own.
			return new ModalEditor(tui, theme, kb, { embedWorkingStatus: true });
		});
	});

	pi.on("session_shutdown", (event) => {
		reader.stop();
		if (event.reason === "quit") restore?.();
		restore = undefined;
	});
}
