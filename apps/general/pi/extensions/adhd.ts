/**
 * ADHD Mode Extension
 *
 * /adhd toggles a short set of reply-shaping rules in the system prompt: say
 * what happened and what is needed first, restate where we are, one next step,
 * no tangents. A trimmed, agent-oriented cut of the i-have-adhd skill; the full
 * skill is still there as /skill:i-have-adhd.
 *
 * The choice is remembered across sessions in <agent dir>/adhd.json.
 */

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { type ExtensionAPI, type ExtensionContext, getAgentDir } from "@earendil-works/pi-coding-agent";

const RULES_FILE = join(getAgentDir(), "rules", "adhd.md");

function loadRules(): string | undefined {
	try {
		return readFileSync(RULES_FILE, "utf8").trim() || undefined;
	} catch {
		return undefined;
	}
}

const STATE_FILE = join(getAgentDir(), "adhd.json");

const REMINDER = "<reminder>ADHD reply style is on: follow the <adhd> section of the system prompt.</reminder>";

function load(): boolean {
	try {
		return JSON.parse(readFileSync(STATE_FILE, "utf8")).enabled === true;
	} catch {
		return false;
	}
}

export default function (pi: ExtensionAPI) {
	let enabled = load();

	const showStatus = (ctx: ExtensionContext) => {
		if (ctx.hasUI) ctx.ui.setStatus("adhd", enabled ? ctx.ui.theme.fg("accent", "adhd") : undefined);
	};

	pi.on("session_start", async (_event, ctx) => showStatus(ctx));

	pi.registerCommand("adhd", {
		description: "Toggle ADHD mode: replies lead with the result, restate progress, one next step",
		handler: async (_args, ctx) => {
			enabled = !enabled;
			try {
				writeFileSync(STATE_FILE, `${JSON.stringify({ enabled })}\n`);
			} catch {
				// Still applies to this session; it just won't be remembered.
			}
			showStatus(ctx);
			if (enabled && !loadRules()) ctx.ui.notify(`ADHD mode on, but ${RULES_FILE} is missing: run dotfiles --sync`, "warning");
			else ctx.ui.notify(enabled ? "ADHD mode on (from your next message)" : "ADHD mode off", "info");
		},
	});

	pi.on("context", async (event, ctx) => {
		if (!enabled || !ctx.hasUI || !loadRules()) return;
		for (const message of event.messages) {
			if (message.role !== "user") continue;
			if (typeof message.content === "string") message.content = `${message.content}\n\n${REMINDER}`;
			else message.content = [...message.content, { type: "text", text: REMINDER }];
		}
	});

	pi.on("before_agent_start", async (event) => {
		const rules = enabled ? loadRules() : undefined;
		if (rules) event.systemPromptOptions.sections.adhd = rules;
		else delete event.systemPromptOptions.sections.adhd;
	});
}
