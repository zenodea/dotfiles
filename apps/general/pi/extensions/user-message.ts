import { type ExtensionAPI, type Theme, UserMessageComponent } from "@earendil-works/pi-coding-agent";
import { liveTheme } from "./lib/live.ts";

const ORIGINAL = Symbol.for("dotfiles.pi.user-message.original");
const BAR = "▌";

const MARKS = /^(?:\x1b\]133;[ABC]\x07)*/;

function patch() {
	const prototype = UserMessageComponent?.prototype as any;
	if (typeof prototype?.render !== "function") return;
	const render: (width: number) => string[] = (prototype[ORIGINAL] ??= prototype.render);

	prototype.render = function (width: number): string[] {
		const theme = liveTheme();
		if (!theme || width < 2) return render.call(this, width);
		const bar = theme.bg("userMessageBg", theme.fg("accent", BAR));
		return render.call(this, width - 1).map((line) => {
			const marks = MARKS.exec(line)![0];
			return marks + bar + line.slice(marks.length);
		});
	};
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async (_event, ctx) => {
		if (!ctx.hasUI) return;
		patch();
	});
}
