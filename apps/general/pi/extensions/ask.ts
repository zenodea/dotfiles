/**
 * Ask - lets the agent ask you a question with options to pick from.
 *
 * Based on pi's examples/extensions/question.ts.
 *   j / k or ↑ / ↓   move          1-9      pick that option
 *   Enter            pick          Esc      cancel
 * The last option is always "Type something", which opens a small editor.
 *
 * While a question is open it emits "ask:blocked" so modal-editor keeps the
 * mouse wheel and page keys scrolling the transcript.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Editor, type EditorTheme, Key, matchesKey, Text, visibleWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui";
import { Type } from "typebox";

const BLOCKED_EVENT = "ask:blocked";

interface Option {
	label: string;
	description?: string;
	isOther?: boolean;
}

interface AskDetails {
	question: string;
	options: string[];
	answer: string | null;
	wasCustom?: boolean;
}

const AskParams = Type.Object({
	question: Type.String({ description: "The question to ask the user" }),
	options: Type.Array(
		Type.Object({
			label: Type.String({ description: "Short label for the option" }),
			description: Type.Optional(Type.String({ description: "One line explaining the option" })),
		}),
		{ description: "2-6 options; put the recommended one first" },
	),
});

type Answer = { answer: string; wasCustom: boolean; index?: number } | null;

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: "ask_user",
		label: "Ask",
		description:
			"Ask the user one question with options to pick from. Use it when you are blocked on a decision only the user can make; put the recommended option first.",
		parameters: AskParams,
		executionMode: "sequential",

		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const labels = params.options.map((o) => o.label);
			const reply = (text: string, details: Partial<AskDetails> = {}) => ({
				content: [{ type: "text" as const, text }],
				details: { question: params.question, options: labels, answer: null, ...details } as AskDetails,
			});

			if (ctx.mode !== "tui") return reply("Error: no UI to ask the user (non-interactive mode)");
			if (params.options.length === 0) return reply("Error: no options given");

			const options: Option[] = [...params.options, { label: "Type something", isOther: true }];

			pi.events.emit(BLOCKED_EVENT, { active: true });
			let result: Answer;
			try {
				result = await ctx.ui.custom<Answer>(
					(tui, theme, _kb, done) => {
						let index = 0;
						let editing = false;
						let cached: string[] | undefined;

						const editorTheme: EditorTheme = {
							borderColor: (s) => theme.fg("accent", s),
							selectList: {
								selectedPrefix: (t) => theme.fg("accent", t),
								selectedText: (t) => theme.fg("accent", t),
								description: (t) => theme.fg("muted", t),
								scrollInfo: (t) => theme.fg("dim", t),
								noMatch: (t) => theme.fg("warning", t),
							},
						};
						const editor = new Editor(tui, editorTheme);
						editor.onSubmit = (value) => {
							const text = value.trim();
							if (text) return done({ answer: text, wasCustom: true });
							editing = false;
							editor.setText("");
							refresh();
						};

						function refresh() {
							cached = undefined;
							tui.requestRender();
						}

						function pick(i: number) {
							const option = options[i]!;
							if (option.isOther) {
								index = i;
								editing = true;
								return refresh();
							}
							done({ answer: option.label, wasCustom: false, index: i + 1 });
						}

						function handleInput(data: string) {
							if (editing) {
								if (matchesKey(data, Key.escape)) {
									editing = false;
									editor.setText("");
									return refresh();
								}
								editor.handleInput(data);
								return refresh();
							}
							if (matchesKey(data, Key.up) || data === "k") {
								index = Math.max(0, index - 1);
								return refresh();
							}
							if (matchesKey(data, Key.down) || data === "j") {
								index = Math.min(options.length - 1, index + 1);
								return refresh();
							}
							const number = Number(data);
							if (data.length === 1 && number >= 1 && number <= options.length) return pick(number - 1);
							if (matchesKey(data, Key.enter)) return pick(index);
							if (matchesKey(data, Key.escape)) done(null);
						}

						function render(width: number): string[] {
							if (cached) return cached;
							const lines: string[] = [];
							const w = Math.max(1, width);
							const add = (prefix: string, text: string) => {
								const pad = visibleWidth(prefix);
								if (pad >= w) return void lines.push(...wrapTextWithAnsi(prefix + text, w));
								wrapTextWithAnsi(text, w - pad).forEach((line, i) => lines.push(`${i === 0 ? prefix : " ".repeat(pad)}${line}`));
							};

							lines.push(theme.fg("accent", "─".repeat(w)));
							add(" ", theme.fg("text", params.question));
							lines.push("");
							options.forEach((option, i) => {
								const selected = i === index;
								const active = selected || (option.isOther && editing);
								const label = `${i + 1}. ${option.label}${option.isOther && editing ? " ✎" : ""}`;
								add(selected ? theme.fg("accent", "> ") : "  ", theme.fg(active ? "accent" : "text", label));
								if (option.description) add("     ", theme.fg("muted", option.description));
							});
							if (editing) {
								lines.push("");
								add(" ", theme.fg("muted", "Your answer:"));
								for (const line of editor.render(Math.max(1, w - 2))) lines.push(` ${line}`);
							}
							lines.push("");
							const hint = editing ? "Enter submit • Esc back" : "j/k move • 1-9 or Enter pick • Esc cancel";
							add(" ", theme.fg("dim", hint));
							lines.push(theme.fg("accent", "─".repeat(w)));
							cached = lines;
							return lines;
						}

						return { render, invalidate: () => (cached = undefined), handleInput };
					},
					{ blocked: { kind: "question", message: params.question } },
				);
			} finally {
				pi.events.emit(BLOCKED_EVENT, { active: false });
			}

			if (!result) return reply("The user cancelled the question");
			if (result.wasCustom) return reply(`The user wrote: ${result.answer}`, { answer: result.answer, wasCustom: true });
			return reply(`The user picked: ${result.index}. ${result.answer}`, { answer: result.answer, wasCustom: false });
		},

		renderCall(args, theme) {
			let text = theme.fg("toolTitle", theme.bold("ask ")) + theme.fg("muted", args.question);
			const options = Array.isArray(args.options) ? args.options : [];
			if (options.length) {
				const numbered = [...options.map((o: Option) => o.label), "Type something"].map((o, i) => `${i + 1}. ${o}`);
				text += `\n${theme.fg("dim", `  ${numbered.join(", ")}`)}`;
			}
			return new Text(text, 0, 0);
		},

		renderResult(result, _options, theme) {
			const details = result.details as AskDetails | undefined;
			if (!details) {
				const first = result.content[0];
				return new Text(first?.type === "text" ? first.text : "", 0, 0);
			}
			if (details.answer === null) return new Text(theme.fg("warning", "Cancelled"), 0, 0);
			if (details.wasCustom) {
				return new Text(theme.fg("success", "✓ ") + theme.fg("muted", "(wrote) ") + theme.fg("accent", details.answer), 0, 0);
			}
			const n = details.options.indexOf(details.answer) + 1;
			return new Text(theme.fg("success", "✓ ") + theme.fg("accent", n > 0 ? `${n}. ${details.answer}` : details.answer), 0, 0);
		},
	});
}
