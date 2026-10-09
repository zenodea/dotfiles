import type { ExtensionAPI, Theme } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import { liveTheme, startsUserMessage, transcript } from "./lib/live.ts";

const BAR = "▌";
const ESCAPES = /\x1b\[[0-9;:]*[A-Za-z]|\x1b\][^\x07]*\x07/g;

interface Pinned {
	view: any;
	row: number;
	text: string;
	rect?: { x: number; y: number; width: number };
}

function currentMessage(tui: any, theme: Theme): Pinned | undefined {
	const found = transcript(tui);
	const background = theme.getBgAnsi("userMessageBg");
	if (!found || !background) return undefined;
	const { view, box, rows } = found;

	const top = view.scrollTop;
	for (let row = Math.min(top, rows.length - 1); row >= 0; row--) {
		const first = rows[row] ?? "";
		if (!startsUserMessage(first, background)) continue;
		if (row === top) return undefined;
		const lines: string[] = [];
		for (let r = row; r < rows.length && (rows[r] ?? "").includes(background); r++) {
			if (r > row && /^\x1b\]133;A/.test(rows[r] ?? "")) break;
			lines.push((rows[r] ?? "").replace(ESCAPES, "").replace(BAR, ""));
		}
		const text = lines.join(" ").replace(/\s+/g, " ").trim();
		return text ? { view, row, text, rect: box.rect } : undefined;
	}
	return undefined;
}

export default function (pi: ExtensionAPI) {
	let tui: any;
	let overlay: { hide(): void } | undefined;
	let pinned: Pinned | undefined;

	const row = {
		render(width: number): string[] {
			const theme = liveTheme();
			if (!theme || !pinned || width < 6) return [];
			const room = width - 4;
			const body = truncateToWidth(theme.fg("userMessageText", pinned.text), room, "…");
			const pad = " ".repeat(Math.max(0, room - visibleWidth(body)));
			return [theme.bg("userMessageBg", `${theme.fg("accent", BAR)} ${body}${pad} ${theme.fg("muted", "↑")}`)];
		},
		invalidate() {},
		handleMouse(event: { type?: string; button?: string }) {
			if (event.type !== "click" || event.button !== "left" || !pinned) return undefined;
			pinned.view.scrollTo(pinned.row, { disableFollow: true });
			tui?.requestRender?.();
			return { handled: true };
		},
	};

	const options: Record<string, unknown> = {
		anchor: "top-left",
		width: "100%",
		maxHeight: 1,
		margin: 0,
		nonCapturing: true,
		visible: () => visible(),
	};

	const visible = (): boolean => {
		const theme = liveTheme();
		try {
			pinned = tui && theme ? currentMessage(tui, theme) : undefined;
		} catch {
			pinned = undefined;
		}
		const rect = pinned?.rect;
		if (rect && rect.width > 0) {
			options.row = rect.y;
			options.col = rect.x;
			options.width = rect.width;
		}
		return pinned !== undefined;
	};

	pi.on("session_start", async (_event, ctx) => {
		if (!ctx.hasUI) return;
		overlay?.hide();
		overlay = undefined;
		ctx.ui.setWidget(
			"pinned-prompt",
			(host) => {
				tui = host;
				if (!overlay && tui?.showOverlay) {
					overlay = tui.showOverlay(row, options);
				}
				return { render: () => [], invalidate() {} };
			},
			{ placement: "belowEditor" },
		);
	});

	pi.on("session_shutdown", async () => {
		overlay?.hide();
		overlay = undefined;
		tui = undefined;
	});
}
