/**
 * Vim - motions, text objects and sentences over plain text, for modal-editor.ts.
 * Positions are string offsets into the prompt; lines are split on "\n".
 * A range is [from, to), linewise when its third element is true.
 */

import { sentenceBreaks } from "./reader.ts";

export interface Find {
	key: string; // f F t T
	ch: string;
}
export interface Target {
	pos: number;
	linewise?: boolean;
	inclusive?: boolean;
	find?: Find;
}
export type Range = [from: number, to: number, linewise?: boolean];

const BULLET = /^\s*([-*•+]|\d+[.)])\s+/;
const isSpace = (ch?: string) => ch === undefined || /\s/.test(ch);
// 0 space, 1 word, 2 punctuation; a WORD (big) is anything that is not space.
const kind = (ch: string | undefined, big: boolean) => (isSpace(ch) ? 0 : big || /\w/.test(ch!) ? 1 : 2);

// (lastIndexOf reads a start of -1 as 0, so offset 0 needs its own case.)
export const lineStart = (t: string, p: number) => (p <= 0 ? 0 : t.lastIndexOf("\n", p - 1) + 1);
export const lineEnd = (t: string, p: number) => (t.indexOf("\n", p) + 1 || t.length + 1) - 1;
// Where a normal-mode cursor may sit on p's line: on a character, never on the newline.
export const lastChar = (t: string, p: number) => Math.max(lineStart(t, p), lineEnd(t, p) - 1);
export function firstNonBlank(t: string, p: number): number {
	let i = lineStart(t, p);
	while (i < lineEnd(t, p) && /[ \t]/.test(t[i]!)) i++;
	return i;
}

export function toLineCol(t: string, p: number): { line: number; col: number } {
	return { line: t.slice(0, p).split("\n").length - 1, col: p - lineStart(t, p) };
}
export function toOffset(t: string, line: number, col: number): number {
	let p = 0;
	for (let i = 0; i < line && p <= t.length; i++) p = t.indexOf("\n", p) + 1 || t.length + 1;
	return Math.min(t.length, p + col);
}

const wordStart = (t: string, p: number, big: boolean) => {
	const k = kind(t[p], big);
	let i = p;
	if (k) while (i < t.length && kind(t[i], big) === k) i++;
	while (i < t.length && isSpace(t[i])) i++;
	return i;
};
const wordEnd = (t: string, p: number, big: boolean) => {
	let i = p + 1;
	while (i < t.length && isSpace(t[i])) i++;
	const k = kind(t[i], big);
	while (i + 1 < t.length && kind(t[i + 1], big) === k) i++;
	return Math.min(i, Math.max(0, t.length - 1));
};
const wordBack = (t: string, p: number, big: boolean) => {
	let i = p - 1;
	while (i > 0 && isSpace(t[i])) i--;
	const k = kind(t[i], big);
	while (i > 0 && kind(t[i - 1], big) === k) i--;
	return Math.max(0, i);
};

// The count-th f/F/t/T target on the line. A repeated t/T skips a match right next to the cursor.
function findChar(t: string, p: number, f: Find, count: number, repeat: boolean): number | undefined {
	const forward = f.key === "f" || f.key === "t";
	const till = f.key === "t" || f.key === "T";
	const step = forward ? 1 : -1;
	const [lo, hi] = [lineStart(t, p), lineEnd(t, p)];
	for (let i = p + step * (repeat && till ? 2 : 1), n = 0; i >= lo && i < hi; i += step) {
		if (t[i] === f.ch && ++n === count) return till ? i - step : i;
	}
	return undefined;
}

// The bracket matching the first bracket at or after p on its line.
function matchBracket(t: string, p: number): number | undefined {
	let i = p;
	while (i < lineEnd(t, p) && !"()[]{}".includes(t[i]!)) i++;
	const ch = t[i];
	if (!ch || !"()[]{}".includes(ch)) return undefined;
	const open = "([{".includes(ch);
	const pair = { "(": ")", ")": "(", "[": "]", "]": "[", "{": "}", "}": "{" }[ch]!;
	for (let j = i + (open ? 1 : -1), depth = 0; j >= 0 && j < t.length; j += open ? 1 : -1) {
		if (t[j] === ch) depth++;
		else if (t[j] === pair && depth-- === 0) return j;
	}
	return undefined;
}

// Paragraphs: runs of non-blank lines; a list item starts a new one. [from, to) without the newline.
export function paragraphs(t: string): Range[] {
	const out: Range[] = [];
	let start = -1;
	let p = 0;
	for (const line of t.split("\n")) {
		const blank = !line.trim();
		if ((blank || BULLET.test(line)) && start !== -1) {
			out.push([start, p - 1]);
			start = -1;
		}
		if (!blank && start === -1) start = p;
		p += line.length + 1;
	}
	if (start !== -1) out.push([start, t.length]);
	return out;
}

// Sentences inside paragraphs, list markers left out. Newlines count as spaces, so offsets hold.
export function sentences(t: string): Range[] {
	return paragraphs(t).flatMap(([from, to]) => {
		const text = t.slice(from, to).replace(/\n/g, " ");
		const marker = BULLET.exec(text)?.[0].length ?? 0;
		return sentenceBreaks(text.slice(marker)).map(([s, e]): Range => [from + marker + s, from + marker + e]);
	});
}

const starts = (ranges: Range[]) => ranges.map(([from]) => from);

// Where a motion goes from p. goal is the column j/k aim for; undefined when key is no motion.
export function motion(t: string, p: number, key: string, count: number, hasCount: boolean, goal: number, lastFind?: Find): Target | undefined {
	const repeat = (step: (q: number) => number) => {
		let q = p;
		for (let i = 0; i < count; i++) q = step(q);
		return q;
	};
	// The start of the line n lines away (stopping at the first or last line).
	const lineAway = (n: number) => {
		let s = lineStart(t, p);
		for (let i = 0; i < Math.abs(n); i++) {
			if (n > 0 && lineEnd(t, s) < t.length) s = lineEnd(t, s) + 1;
			else if (n < 0 && s > 0) s = lineStart(t, s - 1);
		}
		return s;
	};
	const lineNumber = (n: number) => toOffset(t, Math.max(0, n - 1), 0);
	const jump = (list: number[], dir: number) => {
		let q = p;
		for (let i = 0; i < count; i++) q = dir > 0 ? (list.find((s) => s > q) ?? q) : ([...list].reverse().find((s) => s < q) ?? q);
		return q;
	};
	const find = (f: Find | undefined, again: boolean): Target | undefined => {
		if (!f) return undefined;
		const pos = findChar(t, p, f, count, again);
		return pos === undefined ? undefined : { pos, inclusive: f.key === "f" || f.key === "t", find: f };
	};

	switch (key) {
		case "h":
			return { pos: Math.max(lineStart(t, p), p - count) };
		case "l":
			return { pos: Math.min(lineEnd(t, p), p + count) };
		case "j":
		case "k": {
			const s = lineAway(key === "j" ? count : -count);
			return { pos: Math.min(s + goal, lastChar(t, s)), linewise: true };
		}
		case "w":
		case "W":
			return { pos: repeat((q) => wordStart(t, q, key === "W")) };
		case "e":
		case "E":
			return { pos: repeat((q) => wordEnd(t, q, key === "E")), inclusive: true };
		case "b":
		case "B":
			return { pos: repeat((q) => wordBack(t, q, key === "B")) };
		case "0":
			return { pos: lineStart(t, p) };
		case "^":
			return { pos: firstNonBlank(t, p) };
		case "$": {
			const s = lineAway(count - 1);
			return { pos: Math.max(s, lineEnd(t, s) - 1), inclusive: true };
		}
		case "gg":
		case "G": {
			const s = hasCount ? lineNumber(count) : key === "gg" ? 0 : lineStart(t, t.length);
			return { pos: firstNonBlank(t, s), linewise: true };
		}
		case "]":
		case "[":
			return { pos: jump(starts(sentences(t)), key === "]" ? 1 : -1) };
		case "}":
		case "{":
			return { pos: jump(starts(paragraphs(t)), key === "}" ? 1 : -1) };
		case "%": {
			const pos = matchBracket(t, p);
			return pos === undefined ? undefined : { pos, inclusive: true };
		}
		case ";":
			return find(lastFind, true);
		case ",": {
			const flipped = lastFind && { ...lastFind, key: { f: "F", F: "f", t: "T", T: "t" }[lastFind.key]! };
			const target = find(flipped, true);
			return target && { ...target, find: lastFind };
		}
	}
	if (/^[fFtT].$/s.test(key)) return find({ key: key[0]!, ch: key[1]! }, false);
	return undefined;
}

// Text objects: iw aw iW aW, i" a" i' a' i` a`, i( a( ib ab and the other brackets, is as, ip ap.
export function textObject(t: string, p: number, object: string): Range | undefined {
	const around = object[0] === "a";
	const ch = object[1]!;
	const blankAt = (i: number) => /[ \t]/.test(t[i] ?? "");

	if (ch === "w" || ch === "W") {
		const big = ch === "W";
		const k = kind(t[p], big);
		const same = (i: number) => i >= 0 && i < t.length && t[i] !== "\n" && kind(t[i], big) === k && (k !== 0 || blankAt(i));
		let [from, to] = [p, p + 1];
		while (same(from - 1)) from--;
		while (same(to)) to++;
		if (around && blankAt(to)) while (blankAt(to)) to++;
		else if (around) while (blankAt(from - 1)) from--;
		return [from, to];
	}
	if (`"'\``.includes(ch)) {
		const quotes: number[] = [];
		for (let i = lineStart(t, p); i < lineEnd(t, p); i++) if (t[i] === ch && t[i - 1] !== "\\") quotes.push(i);
		for (let n = 0; n + 1 < quotes.length; n += 2) {
			const [a, b] = [quotes[n]!, quotes[n + 1]!];
			if (p <= b) return around ? [a, b + 1] : [a + 1, b];
		}
		return undefined;
	}
	const pair = ({ "(": "()", ")": "()", b: "()", "[": "[]", "]": "[]", "{": "{}", "}": "{}", B: "{}", "<": "<>", ">": "<>" } as Record<string, string>)[ch];
	if (pair) {
		const [open, close] = [pair[0]!, pair[1]!];
		let a = -1;
		for (let i = p, depth = 0; i >= 0; i--) {
			if (t[i] === close && i !== p) depth++;
			else if (t[i] === open && depth-- === 0) {
				a = i;
				break;
			}
		}
		if (a < 0) return undefined;
		for (let i = a + 1, depth = 0; i < t.length; i++) {
			if (t[i] === open) depth++;
			else if (t[i] === close && depth-- === 0) return around ? [a, i + 1] : [a + 1, i];
		}
		return undefined;
	}
	if (ch === "s") {
		const sentence = sentences(t).find(([, e]) => p < e);
		if (!sentence) return undefined;
		let [from, to] = sentence;
		if (around) while (blankAt(to)) to++;
		return [from, to];
	}
	if (ch === "p") {
		const paragraph = paragraphs(t).find(([, e]) => p <= e);
		if (!paragraph) return undefined;
		let to = paragraph[1];
		// ap takes the blank lines after it too.
		if (around) while (to < t.length && !t.slice(to + 1, lineEnd(t, to + 1)).trim()) to = lineEnd(t, to + 1);
		return [lineStart(t, paragraph[0]), to, true];
	}
	return undefined;
}
