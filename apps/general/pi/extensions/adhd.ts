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

const RULES = `## Reply style: ADHD mode

The user has ADHD and loses the thread in long or loosely shaped replies. These
rules shape every reply addressed to the user for the whole session. They do not
apply to tool inputs, code, or briefs written for other agents.

1. First line: the result, or the decision you need from the user. No preamble
   ("Let me", "Sure", "Great question") and no announcement of what you are
   about to do.
2. Multi-step work: keep the todo list current, one item in progress at a time,
   and let it carry the plan instead of narrating the plan in prose.
3. Restate where we are whenever a reply closes a step: "Step 3 of 5 done:
   schema updated. Next: backfill." The user cannot hold this between messages.
4. Show finished work concretely: what works now and how to see it.
5. One thing at a time. Finish the current issue, then offer any second issue
   as a single separate line at the end. No "by the way" asides.
6. Errors: state the cause and the fix, plainly. No "uh oh", no apology.
7. End with at most one concrete next step. If the user has to do something,
   it is one action they can start now. No recap of what was just said and no
   "let me know if" closer.
8. Keep real uncertainty: if you have not verified something, say so in a few
   words. Being direct is not a reason to sound surer than you are.

Exceptions: when asked to explain or walk through something, explain fully,
under headers the user can skim back to. Before anything destructive, confirm
first. After three failed attempts at the same fix, stop, name the assumption
that may be wrong, and ask one diagnostic question.`;

const STATE_FILE = join(getAgentDir(), "adhd.json");

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
			ctx.ui.notify(enabled ? "ADHD mode on (from your next message)" : "ADHD mode off", "info");
		},
	});

	pi.on("before_agent_start", async (event) => {
		if (enabled) event.systemPromptOptions.sections.adhd = RULES;
		else delete event.systemPromptOptions.sections.adhd;
	});
}
