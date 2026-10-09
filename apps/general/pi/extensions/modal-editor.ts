/**
 * Modal Editor - a small vim mode for pi's prompt
 *
 * Deliberately basic: no counts, registers, text objects, or block selection.
 *
 * Insert mode   Escape -> normal
 * Normal mode   Escape passes through (aborts the agent, etc.)
 *   move        h j k l   w b e   0 ^ $   gg G
 *   insert      i a I A o O
 *   edit        x X   dd D dw db d0 d$   cc C cw   u (undo)   p (paste last delete or yank)
 *   select      v (characters)  V (lines), extended with the move keys;
 *               y copy to the clipboard, d / x delete, c change, Escape cancel
 *   transcript  ctrl+u / ctrl+d half page, ctrl+b / ctrl+f page,
 *               ctrl+y / ctrl+e one line; with an empty prompt, j k gg G
 *               scroll the transcript too
 *
 * pi's working indicator is drawn on the top border, so nothing moves when a
 * turn starts. The terminal's own cursor shows the mode: a bar in insert, a block in normal.
 * Also draws the status line from footer.ts into the bottom border.
 */

import { spawn } from "node:child_process";
import { CustomEditor, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
	CURSOR_MARKER,
	isKeyRelease,
	type KeyId,
	matchesKey,
	truncateToWidth,
	type TuiMouseEvent,
	visibleWidth,
} from "@earendil-works/pi-tui";
import { liveTheme, startsUserMessage, transcript } from "./lib/live.ts";

const STATUS_LINE = Symbol.for("dotfiles.pi.status-line");

// DECSCUSR cursor shapes (steady), and the reset to the terminal's default.
const CURSOR_SHAPE = { insert: "\x1b[6 q", normal: "\x1b[2 q", visual: "\x1b[2 q", vline: "\x1b[2 q" };
const CURSOR_SHAPE_RESET = "\x1b[0 q";

// Keys the base editor already understands, as the bytes it expects.
const KEY = {
	left: "\x1b[D",
	right: "\x1b[C",
	up: "\x1b[A",
	down: "\x1b[B",
	wordLeft: "\x1bb",
	wordRight: "\x1bf",
	lineStart: "\x01",
	lineEnd: "\x05",
	deleteChar: "\x1b[3~",
	backspace: "\x7f",
	deleteWord: "\x1bd",
	deleteWordBack: "\x17",
	deleteToStart: "\x15",
	deleteToEnd: "\x0b",
	paste: "\x19",
	undo: "\x1f",
};

// Normal mode: one key -> the editor keys it stands for.
const MOTIONS: Record<string, string[]> = {
	h: [KEY.left],
	j: [KEY.down],
	k: [KEY.up],
	l: [KEY.right],
	// The editor's word key stops after a word; vim's e sits on its last letter.
	e: [KEY.right, KEY.wordRight, KEY.left],
	b: [KEY.wordLeft],
	"0": [KEY.lineStart],
	"^": [KEY.lineStart],
	$: [KEY.lineEnd],
	x: [KEY.deleteChar],
	X: [KEY.backspace],
	D: [KEY.deleteToEnd],
	u: [KEY.undo],
	p: [KEY.paste],
};

// Normal mode: keys that end in insert mode, after these editor keys.
const INSERTS: Record<string, string[]> = {
	i: [],
	a: [KEY.right],
	I: [KEY.lineStart],
	A: [KEY.lineEnd],
	C: [KEY.deleteToEnd],
};

// Two-key commands. "dd", "cc", "gg" and "dw" are handled in code.
const OPERATORS: Record<string, string[]> = {
	de: [KEY.deleteWord],
	db: [KEY.deleteWordBack],
	d0: [KEY.deleteToStart],
	d$: [KEY.deleteToEnd],
	cw: [KEY.deleteWord],
	ce: [KEY.deleteWord],
	cb: [KEY.deleteWordBack],
	c$: [KEY.deleteToEnd],
};

// Keys that only move the cursor; these also extend a selection.
const MOVES = new Set(["h", "j", "k", "l", "w", "b", "e", "0", "^", "$", "g", "gg", "G"]);

const MODE_LABEL = { insert: " INSERT ", normal: " NORMAL ", visual: " VISUAL ", vline: " V-LINE " };
// Theme colour each mode's label is filled with.
const MODE_COLOR = { insert: "success", normal: "accent", visual: "syntaxKeyword", vline: "syntaxKeyword" } as const;

type Position = { line: number; col: number };

// Copy to the system clipboard: the platform's tool, else the terminal's OSC 52.
function copyToClipboard(text: string, write: (sequence: string) => void): void {
	const osc52 = () => write(`\x1b]52;c;${Buffer.from(text).toString("base64")}\x07`);
	const [command, ...args] = process.platform === "darwin" ? ["pbcopy"] : process.env.WAYLAND_DISPLAY ? ["wl-copy"] : ["xclip", "-selection", "clipboard"];
	try {
		const child = spawn(command!, args, { stdio: ["pipe", "ignore", "ignore"] });
		child.on("error", osc52);
		child.stdin.on("error", () => {});
		child.stdin.end(text);
	} catch {
		osc52();
	}
}

// Transcript scrolling, in viewport fractions (or single lines).
const SCROLLS: [key: KeyId, pages: number, lines: number][] = [
	["ctrl+u", -0.5, 0],
	["ctrl+d", 0.5, 0],
	["ctrl+b", -1, 0],
	["ctrl+f", 1, 0],
	["ctrl+y", 0, -1],
	["ctrl+e", 0, 1],
];

class ModalEditor extends CustomEditor {
	private mode: "normal" | "insert" | "visual" | "vline" = "insert";
	private pending = "";
	// Where a selection started; the cursor is its other end.
	private anchor: Position = { line: 0, col: 0 };
	// Text from the last y / selection delete, for p. Cleared by a normal-mode delete,
	// whose text lives in the editor's own kill ring instead.
	private register: string | undefined;

	// The selection as [start, end) on its first and last lines. A character
	// selection includes the character under whichever end is later.
	private selection(): { start: Position; end: Position; lines: string[] } {
		const lines = this.getLines();
		const cursor = this.getCursor();
		const [first, last] =
			cursor.line < this.anchor.line || (cursor.line === this.anchor.line && cursor.col < this.anchor.col)
				? [cursor, this.anchor]
				: [this.anchor, cursor];
		if (this.mode === "vline") {
			return { start: { line: first.line, col: 0 }, end: { line: last.line, col: (lines[last.line] ?? "").length }, lines };
		}
		const text = lines[last.line] ?? "";
		const under = [...(this as any).segment(text.slice(last.col), "grapheme")][0]?.segment ?? "";
		return { start: { ...first }, end: { line: last.line, col: Math.min(text.length, last.col + under.length) }, lines };
	}

	private setCursor(position: Position): void {
		const state = (this as any).state;
		const lines = this.getLines();
		state.cursorLine = Math.max(0, Math.min(position.line, lines.length - 1));
		state.cursorCol = Math.max(0, Math.min(position.col, (lines[state.cursorLine] ?? "").length));
		this.tui.requestRender();
	}

	private visual(data: string): void {
		const command = this.pending + data;
		this.pending = "";

		if (MOVES.has(command)) {
			// At the first or last line, up and down would step into prompt history.
			const { line } = this.getCursor();
			if ((command === "k" && line === 0) || (command === "j" && line === this.getLines().length - 1)) return;
			return this.normal(command);
		}
		if (command === "v" || command === "V") {
			const mode = command === "v" ? "visual" : "vline";
			this.mode = this.mode === mode ? "normal" : mode;
			return;
		}
		if (!["y", "d", "x", "c"].includes(command)) return;

		const { start, end, lines } = this.selection();
		const linewise = this.mode === "vline";
		const picked = [lines[start.line]!.slice(start.col), ...lines.slice(start.line + 1, end.line + 1)];
		picked[picked.length - 1] = picked[picked.length - 1]!.slice(0, end.col - (start.line === end.line ? start.col : 0));
		this.register = picked.join("\n") + (linewise ? "\n" : "");
		copyToClipboard(this.register, (sequence) => (this.tui as any).terminal?.write?.(sequence));

		this.mode = command === "c" ? "insert" : "normal";
		if (command === "y") return this.setCursor(start);

		const joined = lines[start.line]!.slice(0, start.col) + lines[end.line]!.slice(end.col);
		// Deleting whole lines removes them; changing them leaves one empty line to type on.
		const kept = linewise && command !== "c" ? [] : [joined];
		const rest = [...lines.slice(0, start.line), ...kept, ...lines.slice(end.line + 1)];
		this.setText(rest.join("\n"));
		this.setCursor(start);
	}

	// Paint the selection onto the rendered rows. Rows between the borders are
	// padding + one wrapped chunk of plain text (+ the cursor marker), so string
	// offsets within a chunk are offsets within its row.
	private paintSelection(lines: string[], width: number): void {
		const editor = this as any;
		const pad = Math.min(editor.paddingX ?? 0, Math.max(0, Math.floor((width - 1) / 2)));
		const { start, end, lines: text } = this.selection();

		// Which logical line and offsets each wrapped row holds.
		const layout: { text: string }[] = editor.layoutText(editor.lastWidth);
		const rows: { line: number; from: number; to: number }[] = [];
		for (let line = 0, at = 0; line < text.length && at < layout.length; line++) {
			let from = 0;
			do {
				const to = from + layout[at++]!.text.length;
				rows.push({ line, from, to });
				from = to;
			} while (from < text[line]!.length && at < layout.length);
		}

		const visible = editor.renderedVisibleLineCount ?? 0;
		for (let index = 0; index < visible; index++) {
			const row = rows[(editor.scrollOffset ?? 0) + index];
			const rendered = lines[index + 1];
			if (!row || rendered === undefined || row.line < start.line || row.line > end.line) continue;
			const from = Math.max(row.from, row.line === start.line ? start.col : 0);
			const to = Math.min(row.to, row.line === end.line ? end.col : row.to);
			// An empty stretch (a blank line, or the newline itself) still shows one cell.
			const a = pad + Math.min(from, row.to) - row.from;
			const b = to > from ? pad + to - row.from : a + 1;

			const marker = rendered.indexOf(CURSOR_MARKER);
			const plain = marker === -1 ? rendered : rendered.slice(0, marker) + rendered.slice(marker + CURSOR_MARKER.length);
			if (plain.includes("\x1b") || b > plain.length) continue; // not the plain row this expects
			const inserts: [number, string][] = [[a, "\x1b[7m"], [b, "\x1b[27m"]];
			if (marker !== -1) inserts.push([marker, CURSOR_MARKER]);
			lines[index + 1] = inserts
				.sort((x, y) => y[0] - x[0])
				.reduce((out, [at, sequence]) => out.slice(0, at) + sequence + out.slice(at), plain);
		}
	}

	private shape = "";

	// pi draws its own cursor as a reverse-video cell after CURSOR_MARKER. With the
	// terminal's cursor switched on instead (see the factory below), drop that
	// cell's highlight and set the shape for the mode.
	private syncCursor(lines: string[]): void {
		const host = this.tui as any;
		if (host.getShowHardwareCursor?.() === false) host.setShowHardwareCursor?.(true);

		const index = lines.findIndex((line) => line.includes(CURSOR_MARKER));
		if (index === -1) return;
		const line = lines[index]!;
		const start = line.indexOf("\x1b[7m", line.indexOf(CURSOR_MARKER));
		const end = start === -1 ? -1 : Math.min(...["\x1b[0m", "\x1b[27m"].map((reset) => line.indexOf(reset, start)).filter((at) => at !== -1));
		if (start !== -1 && Number.isFinite(end)) {
			lines[index] = line.slice(0, start) + line.slice(start + 4, end) + line.slice(end + (line.startsWith("\x1b[0m", end) ? 4 : 5));
		}
		const shape = CURSOR_SHAPE[this.mode];
		if (shape !== this.shape) {
			this.shape = shape;
			(this.tui as any).terminal?.write?.(shape);
		}
	}

	// A filled block in the mode's colour: bold, with the colour as the background.
	private paintLabel(label: string): string {
		const theme = liveTheme();
		return theme ? theme.fg(MODE_COLOR[this.mode], `\x1b[1;3;7m${label}\x1b[22;23;27m`) : label;
	}

	private send(keys: string[]): void {
		for (const key of keys) super.handleInput(key);
	}

	// The fullscreen renderer owns the transcript's scroll view; regular mode has none.
	private scrollTranscript(pages: number, lines: number): void {
		const tui = this.tui as any;
		const view = tui.getPrimaryScrollView?.();
		if (!view) return;
		tui.scrollBy?.(lines + Math.trunc(pages * Math.max(2, view.viewportHeight)));
	}

	private jumpToUserMessage(direction: -1 | 1): void {
		const tui = this.tui as any;
		const found = transcript(tui);
		const background = liveTheme()?.getBgAnsi("userMessageBg");
		if (!found || !background) return tui.scrollToPrompt?.(direction);
		const { view, rows } = found;

		for (let row = view.scrollTop + direction; row >= 0 && row < rows.length; row += direction) {
			if (!startsUserMessage(rows[row], background)) continue;
			view.scrollTo(row, { disableFollow: true });
			this.tui.requestRender();
			return;
		}
		if (direction === 1) this.scrollTranscriptTo("end");
	}

	private scrollTranscriptTo(edge: "start" | "end"): void {
		const view = (this.tui as any).getPrimaryScrollView?.();
		if (edge === "start") view?.scrollToStart?.();
		else view?.scrollToEnd?.();
		this.tui.requestRender();
	}

	private normal(data: string): void {
		const empty = this.getText() === "";
		const command = this.pending + data;
		this.pending = "";

		if (command === "d" || command === "c" || command === "g") {
			this.pending = command;
			return;
		}

		if (command === "v" || command === "V") {
			this.anchor = this.getCursor();
			this.mode = command === "v" ? "visual" : "vline";
			return;
		}

		if (command === "p" && this.register !== undefined) {
			// A line-wise yank goes on its own line below, as in vim.
			if (this.register.endsWith("\n")) {
				this.send([KEY.lineEnd]);
				this.insertTextAtCursor(`\n${this.register.slice(0, -1)}`);
			} else {
				this.insertTextAtCursor(this.register);
			}
			return;
		}
		if (/^[dcxXDC]/.test(command)) this.register = undefined;

		if (command === "gg" || command === "G") {
			if (empty) return this.scrollTranscriptTo(command === "G" ? "end" : "start");
			const last = this.getLines().length - 1;
			this.setCursor(command === "gg" ? { line: 0, col: 0 } : { line: last, col: Number.MAX_SAFE_INTEGER });
			return;
		}

		if (empty && (command === "j" || command === "k")) return this.scrollTranscript(0, command === "j" ? 1 : -1);

		if (command === "[" || command === "]") return this.jumpToUserMessage(command === "[" ? -1 : 1);

		if (command === "dd" || command === "cc") {
			this.send([KEY.lineStart, KEY.deleteToEnd]);
			if (command === "cc") this.mode = "insert";
			// dd also removes the emptied line: join with the next, or the previous if last.
			else if (this.getCursor().line < this.getLines().length - 1) this.send([KEY.deleteChar]);
			else if (this.getLines().length > 1) this.send([KEY.backspace, KEY.lineStart]);
			return;
		}

		// The editor's word keys stop at the end of a word; vim's w and dw also
		// take the space after it.
		if (command === "w" || command === "dw") {
			this.send([command === "w" ? KEY.wordRight : KEY.deleteWord]);
			const { line, col } = this.getCursor();
			if (this.getLines()[line]?.[col] === " ") this.send([command === "w" ? KEY.right : KEY.deleteChar]);
			return;
		}

		if (command === "o" || command === "O") {
			this.send([command === "o" ? KEY.lineEnd : KEY.lineStart]);
			this.insertTextAtCursor("\n");
			if (command === "O") this.send([KEY.up]);
			this.mode = "insert";
			return;
		}

		if (command in OPERATORS) {
			this.send(OPERATORS[command]!);
			if (command[0] === "c") this.mode = "insert";
		} else if (command in MOTIONS) {
			this.send(MOTIONS[command]!);
		} else if (command in INSERTS) {
			this.send(INSERTS[command]!);
			this.mode = "insert";
		}
		// Anything else, including a half-typed operator, is dropped.
	}

	handleInput(data: string): void {
		// Escape toggles to normal mode, or passes through for app handling
		if (matchesKey(data, "escape")) {
			if (this.mode !== "normal") {
				this.mode = "normal";
				this.pending = "";
			} else if (this.pending) {
				this.pending = "";
			} else {
				super.handleInput(data); // abort agent, etc.
			}
			return;
		}

		// Insert mode: pass everything through
		if (this.mode === "insert") {
			super.handleInput(data);
			return;
		}

		for (const [key, pages, lines] of SCROLLS) {
			if (matchesKey(data, key)) return this.scrollTranscript(pages, lines);
		}

		// Printable keys are commands; control sequences (ctrl+c, enter, etc.) go to super
		if (data.length === 1 && data.charCodeAt(0) >= 32) {
			if (this.mode === "normal") this.normal(data);
			else this.visual(data);
		} else {
			if (this.mode !== "normal") this.mode = "normal";
			super.handleInput(data);
		}
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
		if (hardwareCursor) this.syncCursor(lines);
		if ((this.mode === "visual" || this.mode === "vline") && hardwareCursor) this.paintSelection(lines, width);

		// Add mode indicator to bottom border
		const label = MODE_LABEL[this.mode];
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

const ASK_USER_BLOCKED = "rpiv:ask-user:blocked";
const WHEEL = /^\x1b\[<(\d+);\d+;\d+[Mm]$/;
const WHEEL_LINES = 3;
const PAGE_OVERLAP = 4;

function transcriptScroll(data: string, tui: any): number | undefined {
	const wheel = WHEEL.exec(data);
	if (wheel) {
		const button = Number(wheel[1]);
		if ((button & 64) === 0 || (button & 2) !== 0) return undefined;
		return (button & 1) === 0 ? -WHEEL_LINES : WHEEL_LINES;
	}
	const page = Math.max(1, (tui.getPrimaryScrollView?.()?.viewportHeight ?? 10) - PAGE_OVERLAP);
	if (matchesKey(data, "pageUp")) return -page;
	if (matchesKey(data, "pageDown")) return page;
	return undefined;
}

export default function (pi: ExtensionAPI) {
	let restore: (() => void) | undefined;
	let asking = false;
	let editorTui: any;
	let stopScrollListener: (() => void) | undefined;

	pi.events.on(ASK_USER_BLOCKED, (data: unknown) => {
		asking = Boolean((data as { active?: unknown } | undefined)?.active);
	});

	pi.on("session_start", (_event, ctx) => {
		stopScrollListener?.();
		stopScrollListener = ctx.ui.onTerminalInput((data) => {
			if (!asking || !editorTui) return undefined;
			const delta = transcriptScroll(data, editorTui);
			if (delta === undefined) return undefined;
			if (!isKeyRelease(data)) {
				editorTui.scrollBy?.(delta);
				editorTui.requestRender?.();
			}
			return { consume: true };
		});

		ctx.ui.setEditorComponent((tui, theme, kb) => {
			editorTui = tui;
			const host = tui as any;
			if (typeof host.setShowHardwareCursor === "function" && typeof host.terminal?.write === "function") {
				host.setShowHardwareCursor(true);
				hardwareCursor = true;
				restore = () => host.terminal.write(CURSOR_SHAPE_RESET);
			}
			// Draw pi's working indicator on the top border instead of on a row of its own.
			return new ModalEditor(tui, theme, kb, { embedWorkingStatus: true });
		});
	});

	pi.on("session_shutdown", (event) => {
		if (event.reason === "quit") restore?.();
		restore = undefined;
		stopScrollListener?.();
		stopScrollListener = undefined;
		editorTui = undefined;
		asking = false;
	});
}
