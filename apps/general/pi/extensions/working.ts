/**
 * Working Message Extension
 *
 * Replaces "Working" with what the run has cost so far: elapsed time, tokens
 * sent up and tokens received down.
 *
 *   ⠋ 12s · ↑45k · ↓1.2k
 *
 * Up counts everything sent to the model across the run's requests (cached or
 * not), so it grows with each tool round-trip. Down is exact once a message
 * ends; while one is streaming it is the larger of the provider's running count
 * and a rough four-characters-per-token estimate.
 */

import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

function formatTokens(count: number): string {
	if (count < 1000) return count.toString();
	if (count < 10000) return `${(count / 1000).toFixed(1)}k`;
	if (count < 1000000) return `${Math.round(count / 1000)}k`;
	return `${(count / 1000000).toFixed(1)}M`;
}

function formatElapsed(ms: number): string {
	const seconds = Math.floor(ms / 1000);
	return seconds < 60 ? `${seconds}s` : `${Math.floor(seconds / 60)}m${String(seconds % 60).padStart(2, "0")}s`;
}

const sent = (message: AssistantMessage) =>
	(message.usage?.input ?? 0) + (message.usage?.cacheRead ?? 0) + (message.usage?.cacheWrite ?? 0);

function streamedEstimate(message: AssistantMessage): number {
	let characters = 0;
	for (const block of message.content ?? []) {
		if (block.type === "text") characters += block.text.length;
		else if (block.type === "thinking") characters += block.thinking.length;
		else if (block.type === "toolCall") characters += JSON.stringify(block.arguments ?? {}).length;
	}
	return Math.ceil(characters / 4);
}

export default function (pi: ExtensionAPI) {
	let startedAt = 0;
	// Finished messages of this run, and the one still streaming.
	let done = { up: 0, down: 0 };
	let live = { up: 0, down: 0 };
	let timer: ReturnType<typeof setInterval> | undefined;

	const show = (ctx: ExtensionContext) => {
		if (!ctx.hasUI || !startedAt) return;
		const up = done.up + live.up;
		const down = done.down + live.down;
		ctx.ui.setWorkingMessage(ctx.ui.theme.italic(`${formatElapsed(Date.now() - startedAt)} · ↑${formatTokens(up)} · ↓${formatTokens(down)}`));
	};

	const stop = (ctx: ExtensionContext) => {
		if (timer) clearInterval(timer);
		timer = undefined;
		startedAt = 0;
		if (ctx.hasUI) ctx.ui.setWorkingMessage();
	};

	pi.on("agent_start", async (_event, ctx) => {
		stop(ctx);
		startedAt = Date.now();
		done = { up: 0, down: 0 };
		live = { up: 0, down: 0 };
		show(ctx);
		timer = setInterval(() => show(ctx), 1000);
	});

	pi.on("message_update", async (event, ctx) => {
		if (event.message.role !== "assistant") return;
		const message = event.message as AssistantMessage;
		// Providers often report only a token or two until the message ends.
		live = { up: sent(message), down: Math.max(message.usage?.output ?? 0, streamedEstimate(message)) };
		show(ctx);
	});

	pi.on("message_end", async (event, ctx) => {
		if (event.message.role !== "assistant") return;
		const message = event.message as AssistantMessage;
		done = { up: done.up + sent(message), down: done.down + (message.usage?.output ?? 0) };
		live = { up: 0, down: 0 };
		show(ctx);
	});

	pi.on("agent_end", async (_event, ctx) => stop(ctx));
	pi.on("session_shutdown", async (_event, ctx) => stop(ctx));
}
