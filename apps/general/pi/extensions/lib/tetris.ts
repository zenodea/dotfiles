/**
 * Tetris — the third toy in fidget.ts (formerly Strata).
 *
 * Seven tetrominoes, a 10×20 well, seven-bag randomizer, hold, ghost, five
 * previews, and modern line-clear / T-spin / combo scoring.
 * Endless speeds up every 10 lines; sprint is a timed 40-line game.
 *
 * It handles like tetr.io, as practice for it: SRS+ kicks with 180° turns,
 * DAS / ARR / SDF in tetr.io's own units (t on the pause screen sets them), no
 * wait for a line clear, and a piece that finds the top of the well full spawns
 * above it instead of ending the game. Held keys repeat on their own clock,
 * between frames, so their timing does not depend on the frame rate.
 *
 * Esc hides and pauses; reopening resumes. p pauses; any key resumes.
 * j and l move left/right, k soft drops, space hard drops, d/f rotate, a turns 180°, s holds.
 * m while paused picks a mode. Menus use vim's own keys: j/k pick a row, h/l change it.
 * Game logic and drawing have no pi imports at runtime, so tests can drive it directly.
 */

import type { Theme } from "@earendil-works/pi-coding-agent";

type Tone = Parameters<Theme["fg"]>[0];
type Cell = [x: number, y: number];

export interface KeyEvent {
	key: string;
	kind: "press" | "repeat" | "release";
}

const W = 10;
const H = 20;
const BUF = 4; // hidden rows above the well; row y of the well is grid[y + BUF]
const ROWS = H + BUF;
const SIDE = 12; // width of the panel beside the well
export const WIDTH = W * 2 + SIDE + 3;

const GAME_MODES = ["endless", "sprint"] as const;
type GameMode = (typeof GAME_MODES)[number];
/** Best score per mode; for sprint, the best time in milliseconds. */
export type Bests = Partial<Record<GameMode, number>>;

const MODE_NOTE: Record<GameMode, string> = {
	endless: "10 lines per level",
	sprint: "40 lines, timed",
};
const ROWS_PER_LEVEL = 10;
const SPRINT_ROWS = 40;

/**
 * Handling in tetr.io's units, so its settings can be copied over as they are:
 * DAS and ARR in frames (1/60 s), SDF as a multiple of gravity (41 is instant).
 * They apply to a key once the terminal has been seen to report its release
 * (Kitty keyboard protocol); until then the system's own key repeat moves it.
 */
export interface Handling {
	das: number;
	arr: number;
	sdf: number;
}
const TUNE = [
	{ id: "das", min: 1, max: 20 },
	{ id: "arr", min: 0, max: 5 },
	{ id: "sdf", min: 5, max: 41 },
] as const;
const DEFAULT_HANDLING: Handling = { das: 10, arr: 2, sdf: 6 }; // tetr.io's own defaults
const FRAME = 1000 / 60;
const SDF_INSTANT = 41;
const STALL_MS = 100; // a longer gap between updates is a stall, not held time
const LOCK_MS = 500; // time on the ground before a piece sets
const MAX_RESETS = 15; // moves that may put that off
const CLEAR_MS = 80; // the clear animation; play does not wait for it

const LEFT = new Set(["left", "j"]);
const RIGHT = new Set(["right", "l"]);
const DOWN = new Set(["down", "k"]);
const DROP = new Set(["space"]);
const TURN = new Set(["up", "x", "f"]);

const KINDS = {
	I: { rows: ["....", "####", "....", "...."], tone: "mdLink" },
	O: { rows: ["##", "##"], tone: "warning" },
	T: { rows: [".#.", "###", "..."], tone: "accent" },
	S: { rows: [".##", "##.", "..."], tone: "success" },
	Z: { rows: ["##.", ".##", "..."], tone: "error" },
	J: { rows: ["#..", "###", "..."], tone: "syntaxKeyword" },
	L: { rows: ["..#", "###", "..."], tone: "syntaxNumber" },
} satisfies Record<string, { rows: string[]; tone: Tone }>;
type Kind = keyof typeof KINDS;

const DECK = Object.keys(KINDS) as Kind[];
// SRS+ wall kicks as tetr.io uses them, with y positive downward (the well's coordinate system).
const KICKS: Record<string, Cell[]> = {
	"0>1": [[0, 0], [-1, 0], [-1, -1], [0, 2], [-1, 2]],
	"1>0": [[0, 0], [1, 0], [1, 1], [0, -2], [1, -2]],
	"1>2": [[0, 0], [1, 0], [1, 1], [0, -2], [1, -2]],
	"2>1": [[0, 0], [-1, 0], [-1, -1], [0, 2], [-1, 2]],
	"2>3": [[0, 0], [1, 0], [1, -1], [0, 2], [1, 2]],
	"3>2": [[0, 0], [-1, 0], [-1, 1], [0, -2], [-1, -2]],
	"3>0": [[0, 0], [-1, 0], [-1, 1], [0, -2], [-1, -2]],
	"0>3": [[0, 0], [1, 0], [1, -1], [0, 2], [1, 2]],
	"0>2": [[0, 0], [0, -1], [1, -1], [-1, -1], [1, 0], [-1, 0]],
	"2>0": [[0, 0], [0, 1], [-1, 1], [1, 1], [-1, 0], [1, 0]],
	"1>3": [[0, 0], [1, 0], [1, -2], [1, -1], [0, -2], [0, -1]],
	"3>1": [[0, 0], [-1, 0], [-1, -2], [-1, -1], [0, -2], [0, -1]],
};
// The I's kicks are SRS with the tests reordered so that left and right mirror each other.
const I_KICKS: Record<string, Cell[]> = {
	"0>1": [[0, 0], [1, 0], [-2, 0], [-2, 1], [1, -2]],
	"1>0": [[0, 0], [-1, 0], [2, 0], [-1, 2], [2, -1]],
	"1>2": [[0, 0], [-1, 0], [2, 0], [-1, -2], [2, 1]],
	"2>1": [[0, 0], [-2, 0], [1, 0], [-2, -1], [1, 2]],
	"2>3": [[0, 0], [2, 0], [-1, 0], [2, -1], [-1, 2]],
	"3>2": [[0, 0], [1, 0], [-2, 0], [1, -2], [-2, 1]],
	"3>0": [[0, 0], [1, 0], [-2, 0], [1, 2], [-2, -1]],
	"0>3": [[0, 0], [-1, 0], [2, 0], [2, 1], [-1, -2]],
	"0>2": [[0, 0], [0, -1]],
	"2>0": [[0, 0], [0, 1]],
	"1>3": [[0, 0], [1, 0]],
	"3>1": [[0, 0], [-1, 0]],
};

/** Fixed square rotation boxes keep the SRS pivot in place. */
interface Piece {
	kind: Kind;
	cells: Cell[];
	size: number;
	x: number;
	y: number;
	rotation: number;
}

function shape(kind: Kind): Piece {
	const rows = KINDS[kind].rows;
	const cells: Cell[] = [];
	rows.forEach((row, y) => {
		[...row].forEach((c, x) => {
			if (c === "#") cells.push([x, y]);
		});
	});
	return { kind, cells, size: rows.length, x: Math.floor((W - rows.length) / 2), y: 0, rotation: 0 };
}

/** A piece at half size: two rows of its shape in one line of half blocks. */
function tiny(kind: Kind): string {
	const [top = "", bottom = ""] = KINDS[kind].rows.filter((row) => row.includes("#"));
	return [...top].map((c, i) => (c === "#" ? (bottom[i] === "#" ? "█" : "▀") : bottom[i] === "#" ? "▄" : " ")).join("");
}

const blocks = (p: Piece): Cell[] => p.cells.map(([x, y]) => [x + p.x, y + p.y]);
const bottom = (p: Piece): number => Math.max(...blocks(p).map(([, y]) => y));
const emptyRow = (): Row => Array<Tone | undefined>(W).fill(undefined);
const bold = (s: string) => `\x1b[1m${s}\x1b[22m`;
const number = (n: number) => Math.round(n).toLocaleString("en-US");
const clock = (ms: number) => `${Math.floor(ms / 60000)}:${(Math.floor(ms / 1000) % 60).toString().padStart(2, "0")}.${Math.floor(ms / 100) % 10}`;

type Row = (Tone | undefined)[];
type Phase = "title" | "play" | "paused" | "over" | "tune";

export class Tetris {
	readonly width = WIDTH;
	readonly wantsRelease = true;

	private parse: (data: string) => KeyEvent | undefined;
	private bests: Bests;
	private save: (bests: Bests) => void;
	private handling: Handling = { ...DEFAULT_HANDLING };
	private saveHandling: (handling: Handling) => void;

	private mode: GameMode = "endless";
	private phase: Phase = "title";
	private grid: Row[] = Array.from({ length: ROWS }, emptyRow);
	private piece: Piece | undefined;
	private queue: Kind[] = [];
	private deck: Kind[] = [];
	private held: Kind | undefined;
	private canHold = true;
	private score = 0;
	private rows = 0;
	private level = 1;
	private streak = 0;
	private backToBack = false;
	private rotationKick: number | undefined;
	private farKick = false; // the last quarter turn used its final kick, which makes a T-spin a full one
	private elapsed = 0;
	private last = 0;
	private fallAt = 0;
	private groundedAt = 0;
	private resets = 0;
	private lowest = 0; // the lowest row any cell of this piece has reached
	// Drawn only: the stack as it was before the rows went, for the length of the wipe.
	private clearing: { rows: number[]; at: number; grid: Row[] } | undefined;
	private flashes: { x: number; y: number; until: number; tone: Tone; snug: boolean }[] = [];
	private sparks: { x: number; y: number; vx: number; vy: number; born: number; life: number; tone: Tone }[] = [];
	private glowUntil = 0; // the whole stack lights up for a moment after a clear
	private shown = 0; // the score on screen, rolling up to the real one
	private trails: { x: number; from: number; to: number; until: number }[] = [];
	private banner: { text: string; until: number } | undefined;
	private gain: { text: string; until: number } | undefined;
	private overAt = 0;
	private finished = false;
	private record = false;
	private tuning = 0; // the row picked on the handling screen
	private tunedFrom: Exclude<Phase, "play" | "tune"> = "title";
	// Held keys use our clock, but only keys whose key-up has been seen to arrive. A terminal
	// or multiplexer may say it reports key-ups and not deliver them, and a key that never
	// comes up would run every tap into the wall.
	private ups = new Set<string>();
	private heldKeys = new Set<string>();
	private dir = 0;
	private repeatAt = 0; // when the held direction next moves the piece
	private soft = false;
	private softAt = 0;
	private inputAt = 0; // when held keys were last brought up to date

	constructor(
		parse: (data: string) => KeyEvent | undefined,
		bests: Bests,
		save: (bests: Bests) => void,
		handling: Partial<Handling> = {},
		saveHandling: (handling: Handling) => void = () => {},
	) {
		this.parse = parse;
		this.bests = bests;
		this.save = save;
		this.saveHandling = saveHandling;
		for (const { id, min, max } of TUNE) {
			const value = handling[id];
			if (typeof value === "number" && Number.isFinite(value)) this.handling[id] = Math.min(max, Math.max(min, value));
		}
	}

	/** Whether this key is known to come up again. Letters stand for each other; other keys each for themselves. */
	private comesUp(key: string): boolean {
		return this.ups.has(key.length === 1 ? "letter" : key);
	}

	/** While a game is running, or handling is being set, the arrow keys are the game's. */
	busy(): boolean {
		return this.phase === "play" || this.phase === "tune";
	}

	/** Opening the overlay starts or resumes immediately. */
	focus(now: number): void {
		if (this.phase === "title") this.start(now);
		else if (this.phase === "paused") this.resume(now);
	}

	private resume(now: number): void {
		this.last = this.inputAt = now;
		this.phase = "play";
		this.groundedAt = 0;
		this.fallAt = now + this.interval();
	}

	/** The overlay is closing or switching toy. */
	blur(): void {
		if (this.phase === "play") this.phase = "paused";
		this.heldKeys.clear();
		this.dir = 0;
		this.soft = false;
		this.bank();
	}

	// ── rules ───────────────────────────────────────────────────────────────

	private start(now: number): void {
		this.bank();
		this.grid = Array.from({ length: ROWS }, emptyRow);
		this.queue = [];
		this.deck = [];
		this.held = undefined;
		this.score = this.rows = this.streak = this.elapsed = 0;
		this.level = 1;
		this.backToBack = false;
		this.heldKeys.clear();
		this.dir = 0;
		this.soft = false;
		this.last = this.inputAt = now;
		this.clearing = this.banner = this.gain = undefined;
		this.flashes = [];
		this.trails = [];
		this.sparks = [];
		this.shown = this.glowUntil = 0;
		this.finished = this.record = false;
		this.phase = "play";
		this.spawn(now);
	}

	private interval(): number {
		return 1000 * Math.max(0.05, 0.8 - (this.level - 1) * 0.007) ** (this.level - 1);
	}

	/** Time per row of a held soft drop; 0 drops straight to the ground. */
	private softMs(): number {
		const every = this.interval() / this.handling.sdf;
		return this.handling.sdf >= SDF_INSTANT || every < 1 ? 0 : every;
	}

	private deal(): Kind {
		if (!this.deck.length) {
			this.deck = [...DECK];
			for (let i = this.deck.length - 1; i > 0; i--) {
				const j = Math.floor(Math.random() * (i + 1));
				[this.deck[i], this.deck[j]] = [this.deck[j]!, this.deck[i]!];
			}
		}
		return this.deck.pop()!;
	}

	/** The cell at row y of the well; rows above it, down to -BUF, are the hidden ones. */
	private at(x: number, y: number): Tone | undefined {
		return this.grid[y + BUF]?.[x];
	}

	private fits(p: Piece, dx = 0, dy = 0): boolean {
		return blocks(p).every(([x, y]) => {
			const cx = x + dx;
			const cy = y + dy;
			return cx >= 0 && cx < W && cy >= -BUF && cy < H && !this.at(cx, cy);
		});
	}

	private enter(piece: Piece, now: number): void {
		this.groundedAt = 0;
		this.resets = 0;
		this.rotationKick = undefined;
		this.farKick = false;
		this.fallAt = now + this.interval();
		// A piece that finds the top of the well taken comes in above it, where tetr.io
		// spawns every piece. The game ends only when there is no room there either.
		for (const up of [0, 1, 2]) {
			if (!this.fits(piece, 0, -up)) continue;
			piece.y -= up;
			this.lowest = bottom(piece);
			this.piece = piece;
			return;
		}
		this.topOut(now);
	}

	private spawn(now: number): void {
		while (this.queue.length < 6) this.queue.push(this.deal());
		this.canHold = true;
		this.enter(shape(this.queue.shift()!), now);
	}

	/** A successful move on the ground buys a little more time, up to a limit. */
	private nudged(now: number): void {
		if (this.groundedAt && this.resets < MAX_RESETS) {
			this.groundedAt = now;
			this.resets++;
		}
	}

	/** Reaching a new lowest row gives the piece its lock resets back. */
	private sank(p: Piece): void {
		if (bottom(p) <= this.lowest) return;
		this.lowest = bottom(p);
		this.resets = 0;
	}

	/** One square sideways, or as far as it goes. A slide of any length is one move. */
	private shift(dx: number, now: number, far = false): void {
		const p = this.piece;
		if (!p) return;
		let n = 0;
		while ((far || !n) && this.fits(p, dx * (n + 1), 0)) n++;
		if (!n) return;
		p.x += dx * n;
		this.rotationKick = undefined;
		this.nudged(now);
	}

	/** way: 1 clockwise, -1 counterclockwise, 2 half a turn. */
	private turn(way: number, now: number): void {
		const p = this.piece;
		if (!p || p.kind === "O") return;
		const last = p.size - 1;
		const rotation = (p.rotation + way + 4) % 4;
		const cells: Cell[] = p.cells.map(([x, y]) => (way === 2 ? [last - x, last - y] : way > 0 ? [last - y, x] : [y, last - x]));
		const kicks = (p.kind === "I" ? I_KICKS : KICKS)[`${p.rotation}>${rotation}`]!;
		for (const [i, [dx, dy]] of kicks.entries()) {
			const moved = { ...p, cells, rotation, x: p.x + dx, y: p.y + dy };
			if (!this.fits(moved)) continue;
			this.piece = moved;
			this.rotationKick = i;
			this.farKick = way !== 2 && i === 4;
			this.sank(moved);
			this.nudged(now);
			return;
		}
	}

	private spin(p: Piece): "full" | "mini" | undefined {
		if (p.kind !== "T" || this.rotationKick === undefined) return undefined;
		const occupied = (dx: number, dy: number): boolean => {
			const x = p.x + dx;
			const y = p.y + dy;
			return x < 0 || x >= W || y >= H || y < -BUF || !!this.at(x, y);
		};
		const corners = [occupied(0, 0), occupied(2, 0), occupied(2, 2), occupied(0, 2)];
		if (corners.filter(Boolean).length < 3) return undefined;
		const front = p.rotation;
		return (corners[front] && corners[(front + 1) % 4]) || this.farKick ? "full" : "mini";
	}

	private reach(p: Piece): number {
		let rows = 0;
		while (this.fits(p, 0, rows + 1)) rows++;
		return rows;
	}

	/** One row down, or all the way to the ground without locking. */
	private softDrop(now: number, far = false): void {
		const p = this.piece;
		if (!p) return;
		const rows = far ? this.reach(p) : this.fits(p, 0, 1) ? 1 : 0;
		if (!rows) return;
		p.y += rows;
		this.rotationKick = undefined;
		this.score += rows;
		this.fallAt = now + this.interval();
		this.sank(p);
	}

	private hardDrop(now: number): void {
		const p = this.piece;
		if (!p) return;
		const rows = this.reach(p);
		for (const [x, y] of blocks(p)) this.trails.push({ x, from: y, to: y + rows, until: now + 130 });
		p.y += rows;
		if (rows) this.rotationKick = undefined;
		this.score += rows * 2;
		if (rows > 1) {
			// Dust kicked out sideways from under the piece.
			for (const [x, y] of blocks(p)) {
				if (y + 1 < H && !this.at(x, y + 1)) continue;
				for (const vx of [-9, 9]) this.sparks.push({ x: x * 2 + 1, y, vx, vy: -1.5, born: now, life: 170, tone: "dim" });
			}
		}
		this.lock(now);
	}

	private swapHeld(now: number): void {
		const p = this.piece;
		if (!p || !this.canHold) return;
		const back = this.held;
		this.held = p.kind;
		this.piece = undefined;
		if (back) this.enter(shape(back), now);
		else this.spawn(now);
		this.canHold = false;
	}

	private award(points: number, now: number): void {
		this.score += points;
		this.gain = { text: `+${number(points)}`, until: now + 800 };
	}

	private lock(now: number): void {
		const p = this.piece;
		if (!p) return;
		this.piece = undefined;
		this.clearing = undefined; // a wipe still showing gives way to the stack as it is
		const cells = blocks(p);
		const spin = this.spin(p);
		const tone = KINDS[p.kind].tone;
		for (const [x, y] of cells) this.grid[y + BUF]![x] = tone;
		// Snug: nothing left empty straight under the piece. It glows a little longer as it sets.
		const snug = cells.every(([x, y]) => y + 1 >= H || !!this.at(x, y + 1));
		for (const [x, y] of cells) this.flashes.push({ x, y, until: now + (snug ? 300 : 90), tone, snug });

		const full = this.grid.flatMap((row, i) => (row.every(Boolean) ? [i] : []));
		const n = full.length;
		const difficult = n > 0 && (n === 4 || !!spin);
		const table = spin === "full" ? [400, 800, 1200, 1600] : spin === "mini" ? [100, 200, 400] : [0, 100, 300, 500, 800];
		const perfect = n > 0 && this.grid.every((row, i) => full.includes(i) || !row.some(Boolean));
		const perfectBonus = perfect ? (n === 4 && this.backToBack ? 3200 : [0, 800, 1200, 1800, 2000][n]!) : 0;
		const points = (table[n]! * (difficult && this.backToBack ? 1.5 : 1) + perfectBonus) * this.level;
		if (n) this.streak++;
		else this.streak = 0;
		if (points) this.award(points + Math.max(0, this.streak - 1) * 50 * this.level, now);
		if (n) this.backToBack = difficult;
		if (spin) this.banner = { text: spin === "mini" ? "mini T-spin" : "T-spin", until: now + 900 };
		if (!n) return this.spawn(now);
		for (const i of full) {
			this.grid[i]!.forEach((cell, x) => {
				this.sparks.push({
					x: x * 2 + Math.random() * 2,
					y: i - BUF,
					vx: (Math.random() - 0.5) * 30,
					vy: -4 - Math.random() * 9 - n,
					born: now + CLEAR_MS * 0.25,
					life: 380 + Math.random() * 420,
					tone: cell ?? "text",
				});
			});
		}
		this.glowUntil = now + 70 * n;
		this.rows += n;
		const before = this.level;
		if (this.mode === "endless") this.level = 1 + Math.floor(this.rows / ROWS_PER_LEVEL);
		const text =
			this.level > before
				? `level ${this.level}`
				: n === 4
					? "tetris!"
					: !spin && this.streak >= 2
						? `${this.streak - 1} combo`
						: undefined;
		if (text) this.banner = { text, until: now + 900 };
		if (perfect) this.banner = { text: "perfect clear", until: now + 900 };
		// Play does not wait for the clear: the stack drops and the next piece is live now.
		// Only the picture lags, showing the wipe over the stack as it was.
		this.clearing = { rows: full.map((i) => i - BUF), at: now, grid: this.grid };
		this.grid = this.grid.filter((_, i) => !full.includes(i));
		while (this.grid.length < ROWS) this.grid.unshift(emptyRow());
		if (this.mode === "sprint" && this.rows >= SPRINT_ROWS) return this.finish(now, true);
		this.spawn(now);
	}

	private topOut(now: number): void {
		this.piece = undefined;
		this.finish(now, false);
	}

	private finish(now: number, done: boolean): void {
		this.phase = "over";
		this.overAt = now;
		this.finished = done;
		this.heldKeys.clear();
		this.dir = 0;
		this.soft = false;
		if (this.mode !== "sprint") return this.bank();
		if (done && this.elapsed < (this.bests.sprint ?? Number.POSITIVE_INFINITY)) this.keep(this.elapsed);
	}

	/** Record the score so far if it beats the best (sprint is timed and only counts when finished). */
	private bank(): void {
		if (this.mode !== "sprint" && this.score > (this.bests[this.mode] ?? 0)) this.keep(this.score);
	}

	private keep(value: number): void {
		this.bests[this.mode] = Math.round(value);
		this.record = true;
		this.save(this.bests);
	}

	// ── time and keys ───────────────────────────────────────────────────────

	step(now: number): void {
		const elapsed = Math.max(0, now - this.last);
		const dt = Math.min(100, elapsed);
		this.last = now;
		this.flashes = this.flashes.filter((f) => f.until > now);
		this.trails = this.trails.filter((t) => t.until > now);
		if (this.banner && this.banner.until <= now) this.banner = undefined;
		if (this.gain && this.gain.until <= now) this.gain = undefined;
		if (this.clearing && now - this.clearing.at >= CLEAR_MS) this.clearing = undefined;
		for (const s of this.sparks) {
			if (s.born > now) continue;
			s.x += (s.vx * dt) / 1000;
			s.y += (s.vy * dt) / 1000;
			s.vy += (24 * dt) / 1000;
		}
		this.sparks = this.sparks.filter((s) => now - s.born < s.life && s.y < H && s.x >= 0 && s.x < W * 2);
		const gap = this.score - this.shown;
		this.shown = Math.abs(gap) < 1 ? this.score : this.shown + gap * Math.min(1, dt / 120);
		if (this.phase !== "play") return;

		// The sprint clock uses real time, even if rendering stalls.
		this.elapsed += elapsed;
		this.repeatKeys(now);
		this.fall(now);
		this.glide(now);
	}

	/**
	 * Held keys act when their repeats fall due, not when the next frame happens to
	 * come: every repeat since the last update is played at its own time.
	 */
	private repeatKeys(now: number): void {
		// After a stall a key-up may still be waiting to be read, so held time is not
		// trusted: one step at most, never a backlog thrown across the well.
		const stalled = now - this.inputAt > STALL_MS;
		this.inputAt = now;
		if (this.soft && now >= this.softAt) {
			const every = this.softMs();
			if (!every) this.softDrop(now, true);
			else if (stalled) {
				this.softDrop(now);
				this.softAt = now + every;
			} else for (; this.softAt <= now; this.softAt += every) this.softDrop(this.softAt);
		}
		if (this.dir && now >= this.repeatAt) {
			const every = this.handling.arr * FRAME;
			if (stalled) {
				this.shift(this.dir, now);
				this.repeatAt = now + Math.max(FRAME, every);
			} else if (!every) this.shift(this.dir, now, true);
			else for (; this.repeatAt <= now; this.repeatAt += every) this.shift(this.dir, this.repeatAt);
		}
	}

	/** Instant settings hold: the piece stays against the wall and on the ground through spawns, turns and drops. */
	private glide(now: number): void {
		if (this.dir && now >= this.repeatAt && !this.handling.arr) this.shift(this.dir, now, true);
		if (this.soft && now >= this.softAt && !this.softMs()) this.softDrop(now, true);
	}

	/** Gravity, and setting on the ground. */
	private fall(now: number): void {
		const p = this.piece;
		if (!p) return;
		if (this.fits(p, 0, 1)) {
			this.groundedAt = 0;
			if (now < this.fallAt) return;
			// Catch up at high levels, where gravity can exceed one row per frame.
			p.y += Math.min(this.reach(p), 1 + Math.floor((now - this.fallAt) / this.interval()));
			this.rotationKick = undefined;
			this.fallAt = now + this.interval();
			this.sank(p);
		} else if (!this.groundedAt) {
			// Out of resets, a piece that hops back up sets the moment it lands again.
			if (this.resets >= MAX_RESETS) this.lock(now);
			else this.groundedAt = now;
		} else if (now - this.groundedAt >= LOCK_MS) {
			this.lock(now);
		}
	}

	/** The handling screen, on vim's keys rather than the game's: j/k pick a row, h/l change it. */
	private tune(key: string): void {
		const { id, min, max } = TUNE[this.tuning]!;
		const by = key === "h" || key === "left" ? -1 : key === "l" || key === "right" ? 1 : 0;
		if (by) {
			const value = Math.min(max, Math.max(min, this.handling[id] + by));
			if (value === this.handling[id]) return;
			this.handling[id] = value;
			this.saveHandling({ ...this.handling });
		} else if (key === "j" || key === "down") {
			this.tuning = (this.tuning + 1) % TUNE.length;
		} else if (key === "k" || key === "up") {
			this.tuning = (this.tuning + TUNE.length - 1) % TUNE.length;
		} else if (key === "enter" || key === "space" || key === "t") {
			this.phase = this.tunedFrom;
		}
	}

	press(data: string, now: number): void {
		const event = this.parse(data);
		if (!event) return;
		const { key, kind } = event;
		// Repeats that fell due before this key happen first, at their own times.
		if (this.phase === "play") this.repeatKeys(now);

		if (kind === "release") {
			this.ups.add(key.length === 1 ? "letter" : key);
			if (!this.heldKeys.delete(key)) return;
			this.soft = [...this.heldKeys].some((held) => DOWN.has(held));
			// The most recently pressed direction wins; releasing it restores the other held key.
			const horizontal = [...this.heldKeys].findLast((held) => LEFT.has(held) || RIGHT.has(held));
			const dir = horizontal ? (LEFT.has(horizontal) ? -1 : 1) : 0;
			if (dir !== this.dir) {
				this.dir = dir;
				// It takes over already charged, but never moves on the key-up itself.
				this.repeatAt = now + Math.max(FRAME, this.handling.arr * FRAME);
			}
			return;
		}

		if (this.phase === "tune") return this.tune(key);
		if (this.phase !== "play") {
			if (kind === "repeat") return;
			const go = key === "enter" || key === "space";
			if (key === "t") {
				this.tunedFrom = this.phase;
				this.phase = "tune";
			} else if (this.phase === "paused") {
				if (key === "r") {
					this.start(now);
				} else if (key === "m") {
					this.phase = "title";
				} else {
					// Any other key resumes, and is not also played as a move.
					this.resume(now);
				}
			} else if (key === "m") {
				this.mode = GAME_MODES[(GAME_MODES.indexOf(this.mode) + 1) % GAME_MODES.length]!;
				this.score = 0; // The previous game's record was already banked on pause or game over.
				this.phase = "title";
			} else if (go && now - this.overAt > 600) {
				// The pause after a game ends keeps a held drop key from starting the next one.
				this.start(now);
			}
			return;
		}

		const movement = LEFT.has(key) || RIGHT.has(key) || DOWN.has(key);
		const held = this.comesUp(key);
		if (kind === "repeat" && (held || !movement)) return;
		if (held) {
			if (this.heldKeys.has(key)) return;
			this.heldKeys.add(key);
		}
		if (key === "p") return this.blur();
		if (LEFT.has(key) || RIGHT.has(key)) {
			const dx = LEFT.has(key) ? -1 : 1;
			this.shift(dx, now);
			if (held) {
				this.dir = dx;
				this.repeatAt = now + this.handling.das * FRAME;
			}
		} else if (DOWN.has(key)) {
			this.softDrop(now, !this.softMs());
			if (held) {
				this.soft = true;
				this.softAt = now + this.softMs();
			}
		} else if (DROP.has(key)) {
			this.hardDrop(now);
		} else if (TURN.has(key) || key === "d" || key === "z" || key === "a") {
			this.turn(key === "a" ? 2 : TURN.has(key) ? 1 : -1, now);
		} else if (key === "s" || key === "c") {
			this.swapHeld(now);
		}
		this.glide(now);
	}

	// ── drawing ─────────────────────────────────────────────────────────────

	draw(theme: Theme): string[] {
		const now = this.last;
		const fg = (tone: Tone, s: string) => theme.fg(tone, s);

		// The stack. When a game ends it greys out from the floor up.
		const greyFrom = this.phase === "over" && !this.finished ? H - Math.floor((now - this.overAt) / 25) : H;
		const block = now < this.glowUntil ? "██" : "▓▓";
		const stack = (this.clearing?.grid ?? this.grid).slice(BUF);
		const well = stack.map((row, y) =>
			row.map((tone) => (tone ? (y >= greyFrom ? fg("muted", "▒▒") : fg(tone, block)) : "  ")),
		);
		const put = (x: number, y: number, cell: string, onlyIfEmpty = false) => {
			if (y < 0 || y >= H || x < 0 || x >= W) return;
			if (!onlyIfEmpty || !stack[y]![x]) well[y]![x] = cell;
		};

		// Clearing rows flash, then wipe outward from the middle.
		if (this.clearing) {
			const t = (now - this.clearing.at) / CLEAR_MS;
			const wipe = (t - 0.25) / 0.75;
			for (const y of this.clearing.rows) {
				for (let x = 0; x < W; x++) {
					if (!stack[y]?.[x]) continue;
					const reach = Math.abs(x - (W - 1) / 2) / (W / 2);
					const tone: Tone = "text";
					put(x, y, wipe < 0 ? bold(fg(tone, "██")) : reach < wipe ? "  " : reach < wipe + 0.2 ? fg("warning", "✦ ") : fg(tone, "▓▓"));
				}
			}
		}
		for (const t of this.trails) {
			for (let y = t.from; y < t.to; y++) put(t.x, y, fg("dim", "░░"), true);
		}
		for (const s of this.sparks) {
			if (s.born > now) continue;
			const age = (now - s.born) / s.life;
			const glyph = age < 0.4 ? "✦" : age < 0.75 ? "•" : "·";
			put(Math.floor(s.x / 2), Math.round(s.y), fg(age < 0.75 ? s.tone : "dim", Math.floor(s.x) % 2 ? ` ${glyph}` : `${glyph} `), true);
		}
		if (this.piece && this.phase !== "over") {
			const tone = KINDS[this.piece.kind].tone;
			const reach = this.reach(this.piece);
			for (const [x, y] of blocks(this.piece)) put(x, y + reach, fg(tone, "░░"), true);
			for (const [x, y] of blocks(this.piece)) put(x, y, fg(tone, "██"));
		}
		for (const f of this.flashes) put(f.x, f.y, bold(fg(f.snug && f.until - now < 210 ? f.tone : "text", "██")));

		const field = well.map((row) => row.join(""));
		this.panel().forEach(([text, tone, strong], i) => {
			const left = Math.max(0, Math.floor((W * 2 - text.length) / 2));
			const styled = strong ? bold(fg(tone, text)) : fg(tone, text);
			field[this.panelTop() + i] = " ".repeat(left) + styled + " ".repeat(Math.max(0, W * 2 - left - text.length));
		});

		const side = this.side(theme);
		// The frame warms up with a streak.
		const edgeTone: Tone = this.streak >= 4 ? "warning" : this.banner || this.streak >= 2 ? "accent" : "borderMuted";
		const edge = (s: string) => fg(edgeTone, s);
		const title = "╭─ tetris ";
		const badge = ` ${this.banner?.text ?? this.mode} `;
		const hint = this.phase === "play" ? " p pause · esc hide " : this.phase === "tune" ? " enter done · esc " : " ←→ toy · esc ";
		return [
			edge(title + "─".repeat(WIDTH - title.length - badge.length - 2)) + bold(fg("accent", badge)) + edge("─╮"),
			...field.map((row, y) => edge("│") + row + edge("│") + side[y] + edge("│")),
			edge(`╰─${"─".repeat(WIDTH - hint.length - 4)}`) + fg("dim", hint) + edge("─╯"),
		];
	}

	private panelTop(): number {
		return this.phase === "over" ? 6 : 1;
	}

	/** Text laid over the well when no game is running: [text, tone, bold]. */
	private panel(): [string, Tone, boolean][] {
		const keys = (name: string, does: string): [string, Tone, boolean] => [`${name.padEnd(10)}${does.padEnd(10)}`, "muted", false];
		const help: [string, Tone, boolean][] = [
			["", "dim", false],
			keys("←→  j l", "move"),
			keys("↓   k", "soft drop"),
			keys("space", "hard drop"),
			keys("d / f", "turn ↶ / ↷"),
			keys("a", "turn 180°"),
			keys("s", "hold"),
			keys("p  esc", "pause"),
		];
		if (this.phase === "title") {
			return [
				["tetris", "accent", true],
				["", "dim", false],
				[`‹ ${this.mode} ›`, "text", true],
				[MODE_NOTE[this.mode], "dim", false],
				["", "dim", false],
				["enter start · m mode", "text", false],
				["t handling", "dim", false],
				...help,
			];
		}
		if (this.phase === "paused") {
			return [
				["paused", "accent", true],
				["", "dim", false],
				["any key resumes", "text", true],
				["r restart · m modes", "dim", false],
				["t handling", "dim", false],
				...help,
			];
		}
		if (this.phase === "tune") {
			const show = { das: "DAS", arr: "ARR", sdf: "SDF" };
			const settings = TUNE.map(({ id }, i): [string, Tone, boolean] => {
				const value = +this.handling[id].toFixed(1);
				const instant = id === "sdf" ? value >= SDF_INSTANT : !value;
				const amount = id === "sdf" ? (instant ? "∞" : `${value}×`) : `${value}F`;
				const note = instant ? "instant" : id === "sdf" ? "" : `${Math.round(value * FRAME)}ms`;
				const picked = i === this.tuning;
				return [`${picked ? "›" : " "} ${show[id]} ${amount.padStart(5)} ${note.padStart(7)}`, picked ? "text" : "muted", picked];
			});
			return [
				["handling", "accent", true],
				["", "dim", false],
				...settings,
				["", "dim", false],
				["j k row · h l change", "text", false],
				["as in tetr.io config", "dim", false],
				["", "dim", false],
				// Without key-up events a held key is only the system's repeat, which these cannot change.
				...(["letter", "left", "right"].some((key) => this.ups.has(key))
					? []
					: ([["no key-up events:", "warning", false], ["system repeat moves", "warning", false], ["", "dim", false]] as [string, Tone, boolean][])),
				["enter done", "text", false],
			];
		}
		if (this.phase !== "over" || this.last - this.overAt < 500) return [];
		const sprint = this.mode === "sprint";
		const best = this.bests[this.mode];
		return [
			[this.finished ? "done" : "game over", "accent", true],
			["", "dim", false],
			[sprint && this.finished ? `${SPRINT_ROWS} lines ${clock(this.elapsed)}` : `${number(this.score)} points`, "text", true],
			this.record
				? ["new best", "success", true]
				: [best === undefined ? "" : `best ${sprint ? clock(best) : number(best)}`, "dim", false],
			["", "dim", false],
			["enter again · m mode", "text", false],
		];
	}

	private side(theme: Theme): string[] {
		const fg = (tone: Tone, s: string) => theme.fg(tone, s);
		const side = Array<string>(H).fill(" ".repeat(SIDE));
		const line = (y: number, text: string, tone: Tone, strong = false) => {
			const padded = ` ${text}`.slice(0, SIDE).padEnd(SIDE);
			side[y] = strong ? bold(fg(tone, padded)) : fg(tone, padded);
		};
		const mini = (y: number, kind: Kind | undefined, tone?: Tone) => {
			if (!kind) return;
			KINDS[kind].rows.filter((row) => row.includes("#")).forEach((row, i) => {
				side[y + i] = `  ${[...row.padEnd(5, ".")].map((c) => (c === "#" ? fg(tone ?? KINDS[kind].tone, "██") : "  ")).join("")}`;
			});
		};

		// Five previews, as tetr.io shows: the next piece at full size, the four after it at half.
		line(0, "next", "dim");
		mini(1, this.queue[0]);
		this.queue.slice(1, 5).forEach((kind, i) => {
			const cells = tiny(kind);
			side[4 + i * 2] = `   ${fg(KINDS[kind].tone, cells)}${" ".repeat(SIDE - 3 - cells.length)}`;
		});
		line(12, "hold", "dim");
		mini(13, this.held, this.canHold ? undefined : "muted");

		if (this.gain) line(15, this.gain.text, "accent", true);
		line(16, number(this.shown), "text", true);
		if (this.mode === "sprint") {
			line(17, `${Math.max(0, SPRINT_ROWS - this.rows)} to go`, "muted");
			line(18, clock(this.elapsed), "text");
		} else {
			line(17, `lvl ${this.level} · ${this.rows}`, "muted");
			if (this.streak >= 2) line(18, `${this.streak - 1} combo`, "warning");
		}
		const best = this.bests[this.mode];
		if (best !== undefined) line(19, `best ${this.mode === "sprint" ? clock(best) : number(best)}`, "dim");
		return side;
	}
}
