/**
 * Rex - pi inside a Rex terminal.
 *
 * Tells pi which Rex session and pane it is in, and that the rex command (and
 * /skill:rex) can open tabs, rename windows and so on. `rex skill setup` gives
 * Claude Code this through a SessionStart hook; pi has no hooks, so this does the
 * hook's job, with the text from the rex CLI at every session start.
 *
 * Names an unnamed session after the first request, in a few words, the way
 * Claude Code titles its terminal. pi then titles the terminal "<name> - <folder>"
 * (modal-editor.ts drops pi's "π - "), which Rex shows as the window name.
 * /name still renames it; a named session is never renamed.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { resetCapabilitiesCache } from "@earendil-works/pi-tui";

// Same choice `rex skill setup` installed for the other agents.
const SESSION_NAMING = false;
const NAMER = { provider: "openai", model: "gpt-6-luna" };
const NAME_PROMPT =
	"Name this coding session after the user's request, in 2 to 5 plain words, like a window title. Reply with the name only: no quotes, no trailing period.";

export default function (pi: ExtensionAPI) {
	if (process.env.TERM_PROGRAM === "rex" && !process.env.PI_IMAGE_PROTOCOL) {
		process.env.PI_IMAGE_PROTOCOL = "kitty";
		resetCapabilitiesCache();
	}

	let context: string | undefined;
	let naming = false;

	pi.on("session_start", async () => {
		context = undefined;
		naming = false;
		if (!process.env.REX_SESSION && process.env.TERM_PROGRAM !== "rex") return;
		const args = ["__internal", "session-start", "--agent", "pi", `--feature-session-naming=${SESSION_NAMING}`];
		const result = await pi.exec("rex", args, { timeout: 5000 }).catch(() => undefined);
		if (result?.code === 0 && result.stdout.trim()) context = result.stdout.trim();
	});

	// A few words from a small model, off the turn's path: the reply does not wait for it.
	async function nameSession(prompt: string, ctx: ExtensionContext): Promise<void> {
		const model = ctx.modelRegistry.find(NAMER.provider, NAMER.model);
		if (!model) return;
		try {
			const response = await ctx.modelRegistry.complete(
				model,
				{ systemPrompt: NAME_PROMPT, messages: [{ role: "user", content: [{ type: "text", text: prompt.slice(0, 2000) }], timestamp: Date.now() }] },
				{ signal: AbortSignal.timeout(20_000) },
			);
			const text = response.content.map((part) => (part.type === "text" ? part.text : "")).join("");
			const name = (text.trim().split("\n")[0] ?? "").replace(/^["'`]+|["'`.]+$/g, "").slice(0, 60).trim();
			if (name && !pi.getSessionName()) pi.setSessionName(name);
		} catch {}
	}

	pi.on("before_agent_start", async (event, ctx) => {
		if (context) event.systemPromptOptions.sections.rex = context;
		else delete event.systemPromptOptions.sections.rex;

		if (!naming && event.messageType === "user" && event.prompt?.trim() && !pi.getSessionName()) {
			naming = true;
			void nameSession(event.prompt, ctx);
		}
	});
}
