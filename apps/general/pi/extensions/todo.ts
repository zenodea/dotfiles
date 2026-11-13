/**
 * Todo - the agent's task list, with a panel above the editor.
 *
 * Based on pi's examples/extensions/todo.ts. Tasks are pending ○, in progress ◐
 * or completed ✓. The panel shows while anything is unfinished:
 *
 *   ▾ Todos (1/3)
 *   ├─ ✓ #1 read the config
 *   ├─ ◐ #2 write the guard (testing regexes)
 *   └─ ○ #3 clean up packages
 *
 * /todos shows the whole list. State lives in the tool results, so /tree and
 * forks see the list as it was at that point.
 */

import { StringEnum } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext, Theme } from "@earendil-works/pi-coding-agent";
import { matchesKey, Text, truncateToWidth } from "@earendil-works/pi-tui";
import { Type } from "typebox";

type Status = "pending" | "in_progress" | "completed";

interface Task {
	id: number;
	subject: string;
	status: Status;
	activeForm?: string;
}

interface TodoDetails {
	action: string;
	tasks: Task[];
	nextId: number;
	error?: string;
}

const PANEL = "todo-panel";
const PANEL_ROWS = 8;

const TodoParams = Type.Object({
	action: StringEnum(["create", "update", "delete", "list", "clear"] as const),
	subject: Type.Optional(Type.String({ description: "Task subject line (create)" })),
	subjects: Type.Optional(Type.Array(Type.String(), { description: "Several task subjects at once (create)" })),
	id: Type.Optional(Type.Number({ description: "Task id (update, delete)" })),
	status: Type.Optional(StringEnum(["pending", "in_progress", "completed"] as const, { description: "New status (update)" })),
	activeForm: Type.Optional(
		Type.String({ description: "Present-continuous label shown while in_progress, e.g. 'writing tests' (create, update)" }),
	),
});

function glyph(status: Status, theme: Theme): string {
	if (status === "completed") return theme.fg("success", "✓");
	if (status === "in_progress") return theme.fg("warning", "◐");
	return theme.fg("dim", "○");
}

function taskLine(task: Task, theme: Theme): string {
	const color = task.status === "in_progress" ? "accent" : task.status === "completed" ? "muted" : "text";
	let subject = theme.fg(color, task.subject);
	if (task.status === "completed") subject = theme.strikethrough(subject);
	let line = `${glyph(task.status, theme)} ${theme.fg("dim", `#${task.id}`)} ${subject}`;
	if (task.status === "in_progress" && task.activeForm) line += ` ${theme.fg("muted", `(${task.activeForm})`)}`;
	return line;
}

function summary(tasks: Task[]): string {
	return tasks.length ? tasks.map((t) => `[${t.status === "completed" ? "x" : t.status === "in_progress" ? "~" : " "}] #${t.id} ${t.subject}`).join("\n") : "No tasks";
}

// The panel: heading plus a tree of rows; completed tasks give way first when there are too many.
function panelLines(tasks: Task[], theme: Theme, width: number): string[] {
	const done = tasks.filter((t) => t.status === "completed").length;
	const color = tasks.some((t) => t.status === "in_progress") ? "accent" : "dim";
	const lines = [truncateToWidth(theme.fg(color, `▾ Todos (${done}/${tasks.length})`), width)];

	let shown = tasks;
	if (shown.length > PANEL_ROWS) {
		const open = tasks.filter((t) => t.status !== "completed");
		const closed = tasks.filter((t) => t.status === "completed").slice(-Math.max(0, PANEL_ROWS - open.length));
		shown = [...closed, ...open].sort((a, b) => a.id - b.id).slice(0, PANEL_ROWS);
	}
	const hidden = tasks.length - shown.length;
	shown.forEach((task, i) => {
		const last = i === shown.length - 1 && hidden === 0;
		lines.push(truncateToWidth(`${theme.fg("dim", last ? "└─" : "├─")} ${taskLine(task, theme)}`, width));
	});
	if (hidden > 0) lines.push(truncateToWidth(`${theme.fg("dim", "└─")} ${theme.fg("dim", `+${hidden} more`)}`, width));
	lines.push("");
	return lines;
}

export default function (pi: ExtensionAPI) {
	let tasks: Task[] = [];
	let nextId = 1;

	function showPanel(ctx: ExtensionContext) {
		if (!ctx.hasUI) return;
		if (!tasks.some((t) => t.status !== "completed")) return ctx.ui.setWidget(PANEL, undefined);
		const snapshot = tasks.map((t) => ({ ...t }));
		ctx.ui.setWidget(PANEL, (_tui, theme) => ({ render: (width: number) => panelLines(snapshot, theme, width), invalidate() {} }));
	}

	function reconstruct(ctx: ExtensionContext) {
		tasks = [];
		nextId = 1;
		for (const entry of ctx.sessionManager.getBranch()) {
			if (entry.type !== "message" || entry.message.role !== "toolResult" || entry.message.toolName !== "todo") continue;
			const details = entry.message.details as TodoDetails | undefined;
			if (details?.tasks) {
				tasks = details.tasks;
				nextId = details.nextId;
			}
		}
		showPanel(ctx);
	}

	pi.on("session_start", (_event, ctx) => reconstruct(ctx));
	pi.on("session_tree", (_event, ctx) => reconstruct(ctx));

	pi.registerTool({
		name: "todo",
		label: "Todo",
		description:
			"Track multi-step work as a task list the user sees above the editor. create (subject or subjects), update (id, status, activeForm), delete (id), list, clear. Keep exactly one task in_progress while working.",
		parameters: TodoParams,

		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const result = (text: string, error?: string) => {
				showPanel(ctx);
				return {
					content: [{ type: "text" as const, text: error ? `Error: ${error}` : text }],
					details: { action: params.action, tasks: tasks.map((t) => ({ ...t })), nextId, error } as TodoDetails,
				};
			};
			const find = () => (params.id === undefined ? undefined : tasks.find((t) => t.id === params.id));

			switch (params.action) {
				case "create": {
					const subjects = [...(params.subject ? [params.subject] : []), ...(params.subjects ?? [])].map((s) => s.trim()).filter(Boolean);
					if (!subjects.length) return result("", "subject or subjects required for create");
					const created = subjects.map((subject) => ({ id: nextId++, subject, status: "pending" as Status, activeForm: params.activeForm }));
					tasks = [...tasks, ...created];
					return result(`Created ${created.map((t) => `#${t.id}`).join(", ")}\n${summary(tasks)}`);
				}
				case "update": {
					const task = find();
					if (!task) return result("", `task #${params.id} not found`);
					if (params.status) task.status = params.status;
					if (params.subject) task.subject = params.subject;
					if (params.activeForm !== undefined) task.activeForm = params.activeForm;
					return result(`Updated #${task.id}\n${summary(tasks)}`);
				}
				case "delete": {
					const task = find();
					if (!task) return result("", `task #${params.id} not found`);
					tasks = tasks.filter((t) => t !== task);
					return result(`Deleted #${task.id}\n${summary(tasks)}`);
				}
				case "clear":
					tasks = [];
					nextId = 1;
					return result("Cleared all tasks");
				default:
					return result(summary(tasks));
			}
		},

		renderCall(args, theme) {
			let text = theme.fg("toolTitle", theme.bold("todo ")) + theme.fg("muted", args.action);
			if (args.id !== undefined) text += ` ${theme.fg("accent", `#${args.id}`)}`;
			if (args.status) text += ` ${theme.fg("dim", args.status)}`;
			const subjects = [args.subject, ...(Array.isArray(args.subjects) ? args.subjects : [])].filter(Boolean);
			if (subjects.length) text += ` ${theme.fg("dim", subjects.map((s) => `"${s}"`).join(", "))}`;
			return new Text(text, 0, 0);
		},

		renderResult(result, { expanded }, theme) {
			const details = result.details as TodoDetails | undefined;
			if (!details) {
				const first = result.content[0];
				return new Text(first?.type === "text" ? first.text : "", 0, 0);
			}
			if (details.error) return new Text(theme.fg("error", `Error: ${details.error}`), 0, 0);
			if (!details.tasks.length) return new Text(theme.fg("dim", "No tasks"), 0, 0);
			const shown = expanded ? details.tasks : details.tasks.slice(-5);
			const more = details.tasks.length - shown.length;
			const lines = shown.map((t) => taskLine(t, theme));
			if (more > 0) lines.unshift(theme.fg("dim", `… ${more} earlier`));
			return new Text(lines.join("\n"), 0, 0);
		},
	});

	pi.registerCommand("todos", {
		description: "Show the whole task list",
		handler: async (_args, ctx) => {
			if (ctx.mode !== "tui") return ctx.ui.notify("/todos needs interactive mode", "error");
			await ctx.ui.custom<void>((_tui, theme, _kb, done) => ({
				render(width: number) {
					const body = tasks.length ? tasks.map((t) => `  ${taskLine(t, theme)}`) : [`  ${theme.fg("dim", "No tasks yet")}`];
					const title = theme.fg("accent", ` Todos (${tasks.filter((t) => t.status === "completed").length}/${tasks.length}) `);
					const lines = ["", theme.fg("borderMuted", "───") + title, "", ...body, "", `  ${theme.fg("dim", "Esc or q to close")}`, ""];
					return lines.map((line) => truncateToWidth(line, width));
				},
				invalidate() {},
				handleInput(data: string) {
					if (matchesKey(data, "escape") || data === "q") done();
				},
			}));
		},
	});
}
