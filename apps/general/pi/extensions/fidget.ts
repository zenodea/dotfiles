/**
 * Fidget — a small corner overlay to keep the hands busy while reading.
 *
 * alt+r or /fidget opens it; Esc or alt+r closes it; ←/→ switch toy. The
 * toy last used, Tetris's best scores and its handling are kept in <agent dir>/fidget.json.
 *
 *   rain   Letters fall and pile up. a-z pops every copy of that letter,
 *          lowest first (none on screen: one drops in); space pops them all.
 *   ember  Nothing to aim at or read. Every key warms the box from about
 *          where it sits on the keyboard; a steady rhythm keeps it lit.
 *   tetris Standard tetrominoes and rules, handling like tetr.io, in lib/tetris.ts.
 *          A game in progress pauses when the overlay closes and resumes as
 *          soon as it reopens.
 */

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { type ExtensionAPI, getAgentDir, type Theme } from "@earendil-works/pi-coding-agent";
import { decodeKittyPrintable, isKeyRelease, isKeyRepeat, matchesKey, parseKey } from "@earendil-works/pi-tui";
import { type Bests, type Handling, type KeyEvent, Tetris } from "./lib/tetris.ts";

const SHORTCUT = "alt+r";
const COLS = 15; // rain's letter columns, one every other cell
const ROWS = 9;
const INNER = COLS * 2 + 1;
const BOX = INNER + 2;
const FRAME_MS = 1000 / 60;
const HINT = " ←→ · esc ";

type Tone = Parameters<Theme["fg"]>[0];
const MODES = ["rain", "ember", "tetris"] as const;
type Mode = (typeof MODES)[number];

interface Toy {
	readonly width: number;
	/** Set if the toy wants key releases as well as presses. */
	readonly wantsRelease?: boolean;
	step(now: number): void;
	press(data: string, now: number): void;
	draw(theme: Theme): string[];
	/** True while the toy needs the arrow keys itself. */
	busy?(): boolean;
	/** The overlay is closing or moving to another toy. */
	blur?(): void;
	/** The overlay just showed this toy. */
	focus?(now: number): void;
}

const bold = (s: string) => `\x1b[1m${s}\x1b[22m`;
const inverse = (s: string) => `\x1b[7m${s}\x1b[27m`;
const pick = <T>(items: readonly T[] | string): T => items[Math.floor(Math.random() * items.length)] as T;
const printable = (data: string) => (decodeKittyPrintable(data) ?? (data.length === 1 ? data : "")).toLowerCase();

/** The frame both toys sit in: title and badge on top, count and key hint below. */
function box(theme: Theme, edgeTone: Tone, title: string, badge: string, badgeTone: Tone, count: string, rows: string[]) {
	const edge = (s: string) => theme.fg(edgeTone, s);
	const fill = (used: number) => "─".repeat(BOX - used);
	return [
		edge(`╭─ ${title} ${fill(title.length + 5 + badge.length)}`) + bold(theme.fg(badgeTone, badge)) + edge("╮"),
		...rows.map((row) => edge("│") + row + edge("│")),
		edge(`╰─${count}${fill(count.length + HINT.length + 4)}`) + theme.fg("dim", HINT) + edge("─╯"),
	];
}

// ── rain ────────────────────────────────────────────────────────────────────

const DRIFT = 1.6; // rows per second, letters arriving on their own
const DROP = 18; // rows per second, summoned letters and collapsing piles
const SPAWN_MS = 800;
const STAGGER_MS = 45; // between pops of one chain
const COMBO_MS = 1500;
const GRAVITY = 16;
// Home row three times as likely as the bottom row, so the hands stay put.
const BAG = "asdfghjkl".repeat(3) + "qwertyuiop".repeat(2) + "zxcvbnm";
// Spark colour as a combo builds.
const HEAT: Tone[] = ["accent", "success", "warning", "error"];

interface Letter {
	ch: string;
	col: number;
	y: number;
	vy: number;
	resting: boolean;
	popAt?: number;
}

interface Spark {
	x: number;
	y: number;
	vx: number;
	vy: number;
	born: number;
	life: number;
	tone: Tone;
}

interface Flash {
	x: number;
	y: number;
	ch: string;
	born: number;
	tone: Tone;
}

class Rain implements Toy {
	readonly width = BOX;
	private letters: Letter[] = [];
	private sparks: Spark[] = [];
	private flashes: Flash[] = [];
	private combo = 0;
	private lastPop = 0;
	private popped = 0;
	private nextSpawn = 0;
	private last = performance.now();

	constructor() {
		for (let i = 0; i < 6; i++) this.spawn(Math.random() * (ROWS - 2));
	}

	private column(col: number): Letter[] {
		return this.letters.filter((l) => l.col === col).sort((a, b) => b.y - a.y);
	}

	/** A random column from those with the fewest letters, if its top cell is clear. */
	private freeColumn(limit: number): number | undefined {
		const open = Array.from({ length: COLS }, (_, col) => this.column(col))
			.map((stack, col) => ({ col, size: stack.length, top: Math.min(ROWS, ...stack.map((l) => l.y)) }))
			.filter((c) => c.size < limit && c.top >= 1.5);
		if (!open.length) return undefined;
		const least = Math.min(...open.map((c) => c.size));
		return pick(open.filter((c) => c.size <= least + 1)).col;
	}

	private spawn(y = 0, ch: string = pick<string>(BAG), vy = DRIFT * (0.8 + Math.random() * 0.5)): boolean {
		const col = this.freeColumn(vy === DROP ? ROWS - 1 : ROWS - 3);
		if (col === undefined) return false;
		this.letters.push({ ch, col, y, vy, resting: false });
		return true;
	}

	private burst(x: number, y: number, count: number, tone: Tone): void {
		for (let i = 0; i < count; i++) {
			const angle = (i / count) * Math.PI * 2 + Math.random() * 0.6;
			const speed = 5 + Math.random() * 7;
			this.sparks.push({
				x,
				y,
				vx: Math.cos(angle) * speed * 2, // cells are twice as tall as wide
				vy: Math.sin(angle) * speed - 3,
				born: this.last,
				life: 260 + Math.random() * 260,
				tone,
			});
		}
	}

	private tone(): Tone {
		return HEAT[Math.min(HEAT.length - 1, Math.floor(this.combo / 5))]!;
	}

	private pop(letter: Letter, now: number): void {
		const index = this.letters.indexOf(letter);
		if (index < 0) return;
		this.letters.splice(index, 1);
		this.combo = now - this.lastPop < COMBO_MS ? this.combo + 1 : 1;
		this.lastPop = now;
		this.popped++;
		const x = letter.col * 2 + 1;
		const y = Math.round(letter.y);
		this.flashes.push({ x, y, ch: letter.ch.toUpperCase(), born: now, tone: this.tone() });
		this.burst(x, y, 5 + Math.min(7, this.combo), this.tone());
	}

	press(data: string, now: number): void {
		const ch = printable(data);
		if (ch === " ") {
			for (const l of this.letters) {
				if (l.popAt === undefined) l.popAt = now + l.col * 28 + (ROWS - 1 - l.y) * 14;
			}
			return;
		}
		if (ch.length !== 1 || ch < "a" || ch > "z") return;
		const hits = this.letters.filter((l) => l.ch === ch && l.popAt === undefined).sort((a, b) => b.y - a.y);
		if (!hits.length) {
			// Nothing to pop: the key still does something, and a second press pops it.
			if (!this.spawn(0, ch, DROP)) this.burst(Math.floor(Math.random() * INNER), ROWS - 1, 3, "dim");
			return;
		}
		hits.forEach((l, i) => {
			l.popAt = now + i * STAGGER_MS;
		});
		this.pop(hits[0]!, now); // the first one goes on the keypress itself, not a frame later
	}

	step(now: number): void {
		const dt = Math.min(0.1, (now - this.last) / 1000);
		this.last = now;

		if (now >= this.nextSpawn) {
			this.spawn();
			this.nextSpawn = now + SPAWN_MS * (0.6 + Math.random() * 0.8);
		}
		for (const l of this.letters.filter((l) => l.popAt !== undefined && l.popAt <= now)) this.pop(l, now);

		// Each letter falls to the floor or onto whatever is below it in its column.
		for (let col = 0; col < COLS; col++) {
			const stack = this.column(col);
			stack.forEach((l, i) => {
				const floor = ROWS - 1 - i;
				if (l.y >= floor) return;
				if (l.resting) {
					l.resting = false;
					l.vy = DROP;
				}
				const below = i > 0 ? stack[i - 1]!.y - 1 : floor;
				l.y = Math.min(floor, below, l.y + l.vy * dt);
				if (l.y < floor) return;
				l.resting = true;
				if (l.vy === DROP) {
					const x = col * 2 + 1;
					this.sparks.push(
						{ x, y: floor, vx: -7, vy: -1, born: now, life: 160, tone: "dim" },
						{ x, y: floor, vx: 7, vy: -1, born: now, life: 160, tone: "dim" },
					);
				}
			});
		}

		for (const s of this.sparks) {
			s.x += s.vx * dt;
			s.y += s.vy * dt;
			s.vy += GRAVITY * dt;
			s.vx *= 0.9;
		}
		this.sparks = this.sparks.filter((s) => now - s.born < s.life && s.y < ROWS && s.x >= 0 && s.x < INNER);
		this.flashes = this.flashes.filter((f) => now - f.born < 240);
	}

	draw(theme: Theme): string[] {
		const now = this.last;
		const grid: string[][] = Array.from({ length: ROWS }, () => Array<string>(INNER).fill(" "));
		const put = (x: number, y: number, cell: string) => {
			const row = grid[Math.round(y)];
			const cx = Math.round(x);
			if (row && cx >= 0 && cx < INNER) row[cx] = cell;
		};

		for (const l of this.letters) {
			const cell =
				l.popAt !== undefined
					? bold(theme.fg("accent", l.ch.toUpperCase()))
					: theme.fg(l.resting ? "muted" : "text", l.ch);
			put(l.col * 2 + 1, l.y, cell);
		}
		for (const s of this.sparks) {
			const age = (now - s.born) / s.life;
			put(s.x, s.y, theme.fg(age < 0.7 ? s.tone : "dim", age < 0.35 ? "✦" : age < 0.7 ? "•" : "·"));
		}
		for (const f of this.flashes) {
			const age = now - f.born;
			put(f.x, f.y, theme.fg(f.tone, age < 70 ? inverse(bold(f.ch)) : age < 150 ? "✹" : "○"));
		}

		const hot = now - this.lastPop < COMBO_MS && this.combo > 1;
		return box(
			theme,
			"borderMuted",
			"rain",
			hot ? ` ×${this.combo} ` : "",
			this.tone(),
			this.popped ? ` ${this.popped} ` : "",
			grid.map((row) => row.join("")),
		);
	}
}

// ── ember ───────────────────────────────────────────────────────────────────

const KEY_ROWS = ["`1234567890-=", "qwertyuiop[]\\", "asdfghjkl;'", "zxcvbnm,./"];
const KEY_INDENT = [0, 1.5, 1.75, 2.25]; // how far each keyboard row starts to the right
const COOL_S = 0.45; // a warmed cell fades in about this long
const CALM_S = 2.5; // the whole-box glow fades in about this long
const RIPPLE_SPEED = 18; // cells per second
const RIPPLE_S = 0.8;
// Warmth to shade: big soft blocks, readable from the corner of the eye.
const GLOW: [number, Tone | "", string][] = [
	[0.05, "", " "],
	[0.15, "dim", "░"],
	[0.3, "muted", "░"],
	[0.45, "muted", "▒"],
	[0.62, "accent", "▒"],
	[0.82, "accent", "▓"],
	[1.05, "warning", "▓"],
	[Number.POSITIVE_INFINITY, "warning", "█"],
];

interface Ripple {
	x: number;
	y: number;
	born: number;
	power: number;
}

class Ember implements Toy {
	readonly width = BOX;
	private warmth: number[][] = Array.from({ length: ROWS }, () => Array<number>(INNER).fill(0));
	private ripples: Ripple[] = [];
	private glow = 0; // rises with typing rhythm, lifts the whole box
	private last = performance.now();

	press(data: string, now: number): void {
		const ch = printable(data);
		let x = Math.random() * (INNER - 1);
		let y = Math.random() * (ROWS - 1);
		let power = 1;
		if (ch === " ") {
			x = (INNER - 1) / 2;
			y = ROWS - 1;
			power = 1.6;
		}
		KEY_ROWS.forEach((keys, row) => {
			const i = ch ? keys.indexOf(ch) : -1;
			if (i < 0) return;
			x = Math.min(1, (i + KEY_INDENT[row]!) / 12.5) * (INNER - 1);
			y = (row / (KEY_ROWS.length - 1)) * (ROWS - 1);
		});

		this.ripples.push({ x, y, born: now, power });
		this.glow = Math.min(1.4, this.glow + 0.09 * power);
		// The spot itself lights on the keypress, before the ripple spreads.
		for (let dy = -1; dy <= 1; dy++) {
			for (let dx = -2; dx <= 2; dx++) {
				const row = this.warmth[Math.round(y) + dy];
				const cx = Math.round(x) + dx;
				if (row && cx >= 0 && cx < INNER) row[cx] = Math.min(3, row[cx]! + power * (dx || dy ? 0.45 : 0.9));
			}
		}
	}

	step(now: number): void {
		const dt = Math.min(0.1, (now - this.last) / 1000);
		this.last = now;
		this.glow *= Math.exp(-dt / CALM_S);
		this.ripples = this.ripples.filter((r) => now - r.born < RIPPLE_S * 1000);
		const cool = Math.exp(-dt / COOL_S);
		for (let y = 0; y < ROWS; y++) {
			const row = this.warmth[y]!;
			for (let x = 0; x < INNER; x++) {
				let w = row[x]! * cool;
				for (const r of this.ripples) {
					const age = (now - r.born) / 1000;
					const distance = Math.hypot(x - r.x, (y - r.y) * 2); // cells are twice as tall as wide
					if (Math.abs(distance - age * RIPPLE_SPEED) < 1.5) w += r.power * (1 - age / RIPPLE_S) * dt * 4;
				}
				row[x] = Math.min(3, w);
			}
		}
	}

	draw(theme: Theme): string[] {
		const t = this.last / 1000;
		const rows = this.warmth.map((row, y) => {
			let line = "";
			let run = "";
			let tone: Tone | "" = "";
			const flush = () => {
				line += tone ? theme.fg(tone, run) : run;
				run = "";
			};
			row.forEach((w, x) => {
				// The glow breathes a little so a lit box never sits still.
				const raw = w + this.glow * (0.28 + 0.14 * Math.sin(t * 2.6 + x * 0.8 + y * 1.9));
				const level = 1.2 * (1 - Math.exp(-raw / 0.9)); // squashed, so hot areas keep a gradient
				const [, cellTone, ch] = GLOW.find(([max]) => level < max)!;
				if (cellTone !== tone) {
					flush();
					tone = cellTone;
				}
				run += ch;
			});
			flush();
			return line;
		});
		const edgeTone: Tone = this.glow > 0.75 ? "warning" : this.glow > 0.35 ? "accent" : "borderMuted";
		return box(theme, edgeTone, "ember", "", "dim", "", rows);
	}
}

// ── overlay ─────────────────────────────────────────────────────────────────

const STATE_FILE = join(getAgentDir(), "fidget.json");

function readState(): { mode?: Mode | "strata"; tetris?: Bests; handling?: Partial<Handling> } {
	try {
		return JSON.parse(readFileSync(STATE_FILE, "utf8")) ?? {};
	} catch {
		return {};
	}
}

function writeState(patch: { mode?: Mode; tetris?: Bests; handling?: Handling }): void {
	try {
		writeFileSync(STATE_FILE, `${JSON.stringify({ ...readState(), ...patch })}\n`);
	} catch {
		// Not remembered this time.
	}
}

function keyEvent(data: string): KeyEvent | undefined {
	const key = (parseKey(data) ?? printable(data)).toLowerCase().replace(/^shift\+/, "");
	if (!key) return undefined;
	return { key, kind: isKeyRelease(data) ? "release" : isKeyRepeat(data) ? "repeat" : "press" };
}

const MAKE: Record<Mode, () => Toy> = {
	rain: () => new Rain(),
	ember: () => new Ember(),
	// Strata records stay in the state file; its old scores and 24-line times aren't comparable.
	tetris: () => {
		const { tetris, handling } = readState();
		return new Tetris(keyEvent, tetris ?? {}, (tetris) => writeState({ tetris }), handling ?? {}, (handling) => writeState({ handling }));
	},
};
// Toys outlive the overlay, so reopening resumes the same game.
const toys: Partial<Record<Mode, Toy>> = {};
const toyFor = (mode: Mode): Toy => (toys[mode] ??= MAKE[mode]());
const rememberedMode = readState().mode;
let mode: Mode = rememberedMode === "strata" ? "tetris" : MODES.includes(rememberedMode as Mode) ? rememberedMode as Mode : "rain";

class Fidget {
	/** Asks pi for key releases too; they are passed on only to a toy that wants them. */
	readonly wantsKeyRelease = true;
	private tui: { requestRender(): void };
	private theme: Theme;
	private close: (reopen: boolean) => void;
	private toy: Toy = toyFor(mode);
	private timer: ReturnType<typeof setInterval> | undefined;

	constructor(tui: { requestRender(): void }, theme: Theme, close: (reopen: boolean) => void) {
		this.tui = tui;
		this.theme = theme;
		this.close = close;
		this.guard(() => this.toy.focus?.(performance.now()));
		this.timer = setInterval(() => {
			this.guard(() => this.toy.step(performance.now()));
			this.tui.requestRender();
		}, FRAME_MS);
	}

	private quit(reopen = false): void {
		this.toy.blur?.();
		this.dispose();
		this.close(reopen);
	}

	/** An uncaught error in an extension takes pi down with it; a toy closes itself instead. */
	private guard(run: () => void): void {
		try {
			run();
		} catch {
			this.quit();
		}
	}

	private swap(by: number): void {
		mode = MODES[(MODES.indexOf(mode) + by + MODES.length) % MODES.length]!;
		writeState({ mode });
		const next = toyFor(mode);
		// An overlay keeps the size it opened with, so a toy of another size reopens it.
		if (next.width !== this.toy.width) return this.quit(true);
		this.toy.blur?.();
		this.toy = next;
		this.toy.focus?.(performance.now());
	}

	handleInput(data: string): void {
		const now = performance.now();
		if (isKeyRelease(data)) {
			if (this.toy.wantsRelease) this.guard(() => this.toy.press(data, now));
			return;
		}
		const fresh = !isKeyRepeat(data);
		if (fresh && (matchesKey(data, "escape") || matchesKey(data, "ctrl+c") || matchesKey(data, SHORTCUT))) {
			this.quit();
			return;
		}
		this.guard(() => {
			const free = fresh && !this.toy.busy?.();
			if (free && matchesKey(data, "left")) this.swap(-1);
			else if (free && matchesKey(data, "right")) this.swap(1);
			else this.toy.press(data, now);
		});
		this.tui.requestRender();
	}

	render(width: number): string[] {
		if (width < this.toy.width) return [];
		try {
			return this.toy.draw(this.theme);
		} catch {
			setTimeout(() => this.quit());
			return [];
		}
	}

	invalidate(): void {}

	dispose(): void {
		if (this.timer) clearInterval(this.timer);
		this.timer = undefined;
	}
}

export default function (pi: ExtensionAPI) {
	let open = false;

	const play = async (ctx: any) => {
		if (open || ctx.mode !== "tui") return;
		open = true;
		try {
			let reopen = true;
			while (reopen) {
				reopen = await ctx.ui.custom(
					(tui: { requestRender(): void }, theme: Theme, _keys: unknown, done: (reopen: boolean) => void) =>
						new Fidget(tui, theme, done),
					{ overlay: true, overlayOptions: { anchor: "bottom-right", width: toyFor(mode).width, margin: 1 } },
				);
			}
		} finally {
			open = false;
		}
	};

	pi.registerCommand("fidget", {
		description: "Fidget toys: letter rain, ember and Tetris (alt+r)",
		handler: async (_args, ctx) => play(ctx),
	});
	pi.registerCommand("tetris", {
		description: "Play Tetris in the fidget overlay",
		handler: async (_args, ctx) => {
			if (open || ctx.mode !== "tui") return;
			mode = "tetris";
			writeState({ mode });
			await play(ctx);
		},
	});
	pi.registerShortcut(SHORTCUT, {
		description: "Fidget toys: letter rain, ember and Tetris",
		handler: play,
	});
}
