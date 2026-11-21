/**
 * Reader - a reading cursor in the transcript, with the sentence under it lit up.
 *
 * The transcript is read as its rendered rows. Each row is text, a table border,
 * a table row, code, or blank, and is cut into units:
 *   text   sentences, inside paragraphs (blank rows, list items and messages split them)
 *   table  cells; a cell is lit and the rest of its row softly tinted, borders never
 *   code   one unit per line
 * Paragraphs are text paragraphs, table rows and code blocks; messages start at
 * pi's OSC 133 prompt marks.
 *
 * modal-editor.ts drives it: hjkl move, [ ] sentences, { } paragraphs, ( ) messages.
 * After { or } the whole paragraph is lit, until [ or ] go back to one sentence.
 */

import type { Theme } from "@earendil-works/pi-coding-agent";
import { sliceByColumn, stripTerminalSequences, visibleWidth } from "@earendil-works/pi-tui";

export interface Pos {
	row: number;
	col: number;
}
interface Span {
	row: number;
	start: number;
	end: number;
}
interface Box {
	top: number;
	bottom: number;
	left: number;
	right: number;
}
interface Unit {
	start: Pos;
	spans: Span[];
	tint: Span[];
	box?: Box;
	// Index into the paragraphs; -1 for lines outside any (tool output).
	para: number;
}
interface Model {
	rows: string[];
	length: number;
	plain: string[];
	units: Unit[];
	byRow: Map<number, Unit[]>;
	byPara: Map<number, Unit[]>;
	paragraphs: Pos[];
	messages: Pos[];
}

const MESSAGE_MARK = "\x1b]133;A";
const BULLET = /^([-*•+]|\d+[.)])\s/;
const ABBREVIATIONS = new Set(["e.g", "i.e", "vs", "etc", "mr", "mrs", "ms", "dr", "st", "no", "approx", "incl", "cf"]);
// SGR/CSI codes, and OSC/APC strings ended by BEL or ST (hyperlinks use ST, pi's cursor marker is APC).
const ANSI = /\x1b\[[0-9;:]*[A-Za-z]|\x1b[\]_][^\x07\x1b]*(?:\x07|\x1b\\)/g;
// Left bars pi and the visual extensions draw: your messages ▌, thinking ▏.
const BARS = /^[▌▏▎▍]$/;
const BARS_ALL = /[▌▏▎▍]/g;
const LEADING_MARKS = /^(?:\x1b\]133;[A-Z][^\x07]*\x07)+/;

const before = (a: Pos, b: Pos) => a.row < b.row || (a.row === b.row && a.col < b.col);

// A row as plain characters with their columns; message bars (yours ▌, thinking ▏) read as spaces.
function chars(plain: string): { ch: string; col: number }[] {
	const out: { ch: string; col: number }[] = [];
	let col = 0;
	for (const ch of plain) {
		out.push({ ch: BARS.test(ch) ? " " : ch, col });
		col += Math.max(1, visibleWidth(ch));
	}
	return out;
}

// [first, last+1) columns of the non-space text between two columns.
function extent(row: { ch: string; col: number }[], from = 0, to = Infinity): [number, number] | undefined {
	const inside = row.filter((c) => c.col >= from && c.col < to && c.ch.trim());
	return inside.length ? [inside[0]!.col, inside[inside.length - 1]!.col + 1] : undefined;
}

// Sentence ends: . ! ? … followed (after closing quotes or brackets) by a space or the end.
export function sentenceBreaks(text: string): [number, number][] {
	const out: [number, number][] = [];
	let start = 0;
	for (let i = 0; i < text.length; i++) {
		if (!".!?…".includes(text[i]!)) continue;
		let end = i + 1;
		while (end < text.length && ".!?…\"')]”’".includes(text[end]!)) end++;
		if (end < text.length && text[end] !== " ") continue;
		const word = /([\w.]+)\.$/.exec(text.slice(start, i + 1))?.[1]?.toLowerCase() ?? "";
		if (text[i] === "." && (ABBREVIATIONS.has(word) || /^[a-z]$/i.test(word))) continue;
		out.push([start, end]);
		start = end + 1;
		i = end;
	}
	if (start < text.length) out.push([start, text.length]);
	return out.map(([s, e]) => [s + (text.slice(s, e).length - text.slice(s, e).trimStart().length), e] as [number, number]).filter(([s, e]) => e > s);
}

function build(rows: string[]): Model {
	const plain = rows.map((r) => stripTerminalSequences(r));
	const cells = plain.map(chars);
	const kind = rows.map((raw, r) => {
		const s = plain[r]!.replace(BARS_ALL, " ").trim();
		if (!s) return "blank";
		// Tool output and other boxed messages paint a background from the first column
		// (your messages too, but those start with their ▌ bar): read them line by line.
		if (raw.replace(LEADING_MARKS, "").startsWith("\x1b[48;") && !BARS.test(plain[r]!.trimStart()[0] ?? "")) return "box";
		if (/^[┌├└]/.test(s) && /[─┬┼┴]/.test(s)) return "border";
		if (s.startsWith("│") && s.endsWith("│")) return "cell";
		// pi colours its own markdown fences; a ``` in plain text is just text.
		if (s.startsWith("```") && /\x1b\[[0-9;]*m```/.test(raw)) return "fence";
		return "text";
	});
	const units: Unit[] = [];
	const paragraphs: Pos[] = [];
	const messages: Pos[] = [];
	const isMessageStart = (r: number) => rows[r]!.startsWith(MESSAGE_MARK);

	// Inside a markdown code block. A new message or a boxed row ends it, so one
	// unclosed fence can never swallow the rest of the transcript.
	let inCode = false;
	for (let r = 0; r < rows.length; ) {
		if (kind[r] === "box") inCode = false;
		if (isMessageStart(r)) {
			inCode = false;
			let first = r;
			while (first < rows.length && kind[first] === "blank" && (first === r || !isMessageStart(first))) first++;
			if (first < rows.length) messages.push({ row: first, col: extent(cells[first]!)?.[0] ?? 0 });
		}
		const k = kind[r];
		if (k === "fence") {
			inCode = !inCode;
			if (inCode && r + 1 < rows.length) paragraphs.push({ row: r + 1, col: extent(cells[r + 1]!)?.[0] ?? 0 });
			r++;
		} else if (inCode || k === "blank" || k === "box") {
			const span = k === "blank" ? undefined : extent(cells[r]!);
			if (span) units.push({ start: { row: r, col: span[0] }, spans: [{ row: r, start: span[0], end: span[1] }], tint: [], para: inCode ? paragraphs.length - 1 : -1 });
			r++;
		} else if (k === "border" || k === "cell") {
			r = buildTable(r, kind, cells, units, paragraphs);
		} else {
			r = buildParagraph(r, kind, cells, plain, units, paragraphs, isMessageStart);
		}
	}

	const byRow = new Map<number, Unit[]>();
	for (const unit of units) {
		for (const row of new Set([...unit.spans.map((s) => s.row), ...(unit.box ? range(unit.box.top, unit.box.bottom) : [])])) {
			byRow.set(row, [...(byRow.get(row) ?? []), unit]);
		}
	}
	const byPara = new Map<number, Unit[]>();
	for (const unit of units) if (unit.para >= 0) byPara.set(unit.para, [...(byPara.get(unit.para) ?? []), unit]);
	return { rows, length: rows.length, plain, units, byRow, byPara, paragraphs, messages };
}

function range(from: number, to: number): number[] {
	return Array.from({ length: Math.max(0, to - from + 1) }, (_, i) => from + i);
}

// A text paragraph from row r: rows until a blank, a non-text row, a new message or a new list item.
function buildParagraph(r: number, kind: string[], cells: { ch: string; col: number }[][], plain: string[], units: Unit[], paragraphs: Pos[], isMessageStart: (r: number) => boolean): number {
	const segments: { row: number; col: number; offset: number; text: string }[] = [];
	let text = "";
	let row = r;
	do {
		const span = extent(cells[row]!);
		if (span) {
			let [from] = span;
			const line = cells[row]!.filter((c) => c.col >= from && c.col < span[1]);
			// Leave a list marker out of the sentence.
			const marker = row === r ? BULLET.exec(line.map((c) => c.ch).join(""))?.[0].length ?? 0 : 0;
			const kept = line.slice(marker);
			if (kept.length) {
				from = kept[0]!.col;
				if (text) text += " ";
				segments.push({ row, col: from, offset: text.length, text: kept.map((c) => c.ch).join("") });
				text += segments[segments.length - 1]!.text;
			}
		}
		row++;
	} while (row < kind.length && kind[row] === "text" && !isMessageStart(row) && !BULLET.test(plain[row]!.replace(BARS_ALL, " ").trim()));

	if (segments.length) paragraphs.push({ row: segments[0]!.row, col: segments[0]!.col });
	// Offset in the joined text -> spans on rows.
	const spansFor = (s: number, e: number): Span[] =>
		segments
			.map((seg) => {
				const a = Math.max(s, seg.offset) - seg.offset;
				const b = Math.min(e, seg.offset + seg.text.length) - seg.offset;
				if (b <= a) return undefined;
				const cols = chars(seg.text);
				const startCol = seg.col + cols[a]!.col;
				const endCol = seg.col + (b < cols.length ? cols[b]!.col : visibleWidth(seg.text));
				return { row: seg.row, start: startCol, end: endCol };
			})
			.filter((x): x is Span => !!x);
	for (const [s, e] of sentenceBreaks(text)) {
		const spans = spansFor(s, e);
		if (spans.length) units.push({ start: { row: spans[0]!.row, col: spans[0]!.start }, spans, tint: [], para: paragraphs.length - 1 });
	}
	return row;
}

// A table from row r: each run of │ rows between borders is a table row, cut into cells at the │ columns.
function buildTable(r: number, kind: string[], cells: { ch: string; col: number }[][], units: Unit[], paragraphs: Pos[]): number {
	while (r < kind.length && (kind[r] === "border" || kind[r] === "cell")) {
		if (kind[r] === "border") {
			r++;
			continue;
		}
		const top = r;
		while (r < kind.length && kind[r] === "cell") r++;
		const bottom = r - 1;
		const bars = cells[top]!.filter((c) => c.ch === "│").map((c) => c.col);
		const rowCells: Unit[] = [];
		for (let i = 0; i + 1 < bars.length; i++) {
			const box = { top, bottom, left: bars[i]!, right: bars[i + 1]! };
			const spans = range(top, bottom)
				.map((row) => {
					const span = extent(cells[row]!, box.left + 1, box.right);
					return span ? { row, start: span[0], end: span[1] } : undefined;
				})
				.filter((x): x is Span => !!x);
			if (spans.length) rowCells.push({ start: { row: spans[0]!.row, col: spans[0]!.start }, spans, tint: [], box, para: paragraphs.length });
		}
		for (const cell of rowCells) cell.tint = rowCells.filter((other) => other !== cell).flatMap((other) => other.spans);
		if (rowCells.length) paragraphs.push(rowCells[0]!.start);
		units.push(...rowCells);
	}
	return r;
}

export class Reader {
	cursor: Pos | undefined;
	private model: Model | undefined;
	private goalCol = 0;
	// { } light whole paragraphs (a table row, a code block); [ ] go back to sentences.
	private wide = false;

	get active(): boolean {
		return this.cursor !== undefined;
	}

	stop(): void {
		this.cursor = undefined;
		this.wide = false;
	}

	private load(rows: string[]): Model {
		if (!this.model || this.model.rows !== rows || this.model.length !== rows.length) this.model = build(rows);
		return this.model;
	}

	// The unit under the cursor: a table cell's box, else a span on the row, else the nearest span on it.
	unitAt(rows: string[], pos: Pos): Unit | undefined {
		const candidates = this.load(rows).byRow.get(pos.row) ?? [];
		const inBox = candidates.find((u) => u.box && pos.col > u.box.left && pos.col < u.box.right);
		if (inBox) return inBox;
		let best: Unit | undefined;
		let distance = Infinity;
		for (const unit of candidates) {
			if (unit.box) continue;
			for (const span of unit.spans.filter((s) => s.row === pos.row)) {
				const d = pos.col < span.start ? span.start - pos.col : pos.col >= span.end ? pos.col - span.end + 1 : 0;
				if (d < distance) [best, distance] = [unit, d];
			}
		}
		return best;
	}

	// Target where the eyes most likely are: the unit nearest the middle of the
	// viewport (one that covers the middle row wins), else the last unit.
	start(rows: string[], top: number, height: number): void {
		const model = this.load(rows);
		const middle = top + Math.floor(height / 2);
		let unit: Unit | undefined;
		let distance = Infinity;
		for (let row = top; row < top + height; row++) {
			for (const candidate of model.byRow.get(row) ?? []) {
				const d = Math.abs(row - middle);
				if (d < distance) [unit, distance] = [candidate, d];
			}
		}
		unit ??= model.units[model.units.length - 1];
		this.cursor = unit ? { ...unit.start } : { row: middle, col: 0 };
		this.goalCol = this.cursor.col;
	}

	// One motion. Returns false when the key is not a reader motion.
	move(rows: string[], key: string, count = 1): boolean {
		const model = this.load(rows);
		const starts = model.units.map((u) => u.start);
		const lastCol = (row: number) => Math.max(0, visibleWidth(model.plain[row] ?? "") - 1);
		let pos = this.cursor ?? { row: 0, col: 0 };
		// Forward: the next start after the cursor. Back: the current unit's own start first, as in vim.
		const jump = (list: Pos[], dir: number, current?: Pos) =>
			dir > 0
				? (list.find((p) => before(pos, p)) ?? pos)
				: current && before(current, pos)
					? current
					: ([...list].reverse().find((p) => before(p, pos)) ?? pos);
		const motions: Record<string, () => Pos> = {
			h: () => ({ row: pos.row, col: Math.max(0, pos.col - 1) }),
			l: () => ({ row: pos.row, col: Math.min(lastCol(pos.row), pos.col + 1) }),
			j: () => ({ row: Math.min(model.length - 1, pos.row + 1), col: this.goalCol }),
			k: () => ({ row: Math.max(0, pos.row - 1), col: this.goalCol }),
			"]": () => jump(starts, 1),
			"[": () => jump(starts, -1, this.unitAt(rows, pos)?.start),
			"}": () => jump(model.paragraphs, 1),
			"{": () => jump(model.paragraphs, -1),
			")": () => jump(model.messages, 1),
			"(": () => jump(model.messages, -1),
			gg: () => starts[0] ?? { row: 0, col: 0 },
			G: () => starts[starts.length - 1] ?? { row: model.length - 1, col: 0 },
			"0": () => ({ row: pos.row, col: 0 }),
			$: () => ({ row: pos.row, col: lastCol(pos.row) }),
		};
		const motion = motions[key];
		if (!motion) return false;
		for (let n = 0; n < count; n++) pos = motion();
		this.cursor = { ...pos };
		if (key !== "j" && key !== "k") this.goalCol = pos.col;
		if ("{}[]".includes(key)) this.wide = "{}".includes(key);
		return true;
	}

	// What is lit: the unit (with its table row tinted), or its whole paragraph.
	private lit(rows: string[]): { spans: Span[]; tint: Span[] } | undefined {
		const unit = this.cursor && this.unitAt(rows, this.cursor);
		if (!unit) return undefined;
		const paragraph = this.wide && unit.para >= 0 ? this.load(rows).byPara.get(unit.para) : undefined;
		return paragraph ? { spans: paragraph.flatMap((u) => u.spans), tint: [] } : { spans: unit.spans, tint: unit.tint };
	}

	// The lit text, for copying.
	text(rows: string[]): string {
		const plain = this.load(rows).plain;
		const spans = this.lit(rows)?.spans ?? [];
		return spans.map((s) => sliceByColumn(plain[s.row]!.replace(BARS_ALL, " "), s.start, s.end - s.start)).join(" ");
	}

	// Paint the unit, its row tint and the cursor onto the visible screen rows.
	paint(screen: string[], rows: string[], box: any, scrollTop: number, theme: Theme): string[] {
		if (!this.cursor || !box?.rect) return screen;
		const lit = this.lit(rows);
		const { rect } = box;
		const out = [...screen];
		const colors = highlightColors(theme);
		const apply = (spans: Span[], open: string) => {
			if (!open) return;
			for (const span of spans) {
				const y = rect.y + span.row - scrollTop;
				if (y < rect.y || y >= rect.y + rect.height || out[y] === undefined) continue;
				out[y] = paintColumns(out[y]!, rect.x + span.start, rect.x + span.end, open);
			}
		};
		if (lit) {
			apply(lit.tint, colors.tint);
			apply(lit.spans, colors.strong);
		}
		apply([{ row: this.cursor.row, start: this.cursor.col, end: this.cursor.col + 1 }], "\x1b[7m");
		return out;
	}
}

// Wrap columns [start, end) of a line in `open`, re-opening it after every escape inside,
// then restore whatever background was active at `end`.
export function paintColumns(line: string, start: number, end: number, open: string): string {
	const width = visibleWidth(line);
	if (end <= start || start >= width) return line;
	end = Math.min(end, width);
	const head = sliceByColumn(line, 0, start, true);
	const body = sliceByColumn(line, start, end - start, true);
	const tail = sliceByColumn(line, end, width - end, true);
	const restore = open === "\x1b[7m" ? "\x1b[27m" : lastBackground(head + body);
	return `${head}${open}${body.replace(ANSI, (code) => code + open)}${restore}${tail}`;
}

// The last background colour set in a string, or the default.
function lastBackground(text: string): string {
	let bg = "\x1b[49m";
	for (const code of text.match(/\x1b\[[0-9;:]*m/g) ?? []) {
		const params = code.slice(2, -1).split(";");
		for (let i = 0; i < params.length; i++) {
			const p = params[i];
			if (p === "0" || p === "" || p === "49") bg = "\x1b[49m";
			else if (p === "48") {
				bg = `\x1b[${params.slice(i, params[i + 1] === "2" ? i + 5 : i + 3).join(";")}m`;
				break;
			} else if (/^(4[0-7]|10[0-7])$/.test(p!)) bg = `\x1b[${p}m`;
		}
	}
	return bg;
}

// Strong highlight and soft tint: the accent colour mixed into the card background
// (the theme's closest colour to the page itself).
export function highlightColors(theme: Theme): { strong: string; tint: string } {
	const rgb = (read: () => string) => {
		try {
			return /\[(?:38|48);2;(\d+);(\d+);(\d+)m/.exec(read())?.slice(1).map(Number);
		} catch {
			return undefined;
		}
	};
	const accent = rgb(() => theme.getFgAnsi("accent"));
	const page = rgb(() => theme.getBgAnsi("customMessageBg"));
	if (!accent || !page) return { strong: "\x1b[7m", tint: "" };
	const mix = (amount: number) => `\x1b[48;2;${page.map((p, i) => Math.round(p + (accent[i]! - p) * amount)).join(";")}m`;
	return { strong: mix(0.34), tint: mix(0.14) };
}

// Exported for tests.
export const _test = { build, sentenceBreaks };
