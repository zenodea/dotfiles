import {
	BashExecutionComponent,
	type ExtensionAPI,
	getLanguageFromPath,
	highlightCode,
	type Theme,
} from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { liveTheme } from "./lib/live.ts";

const HEREDOC = /<<-?\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\1/;

const INTERPRETERS: [RegExp, string][] = [
	[/\b(python[0-9.]*|uv run|ipython)\b/, "python"],
	[/\b(node|bun|deno|tsx)\b/, "javascript"],
	[/\bruby\b/, "ruby"],
	[/\bperl\b/, "perl"],
	[/\b(psql|sqlite3|duckdb|mysql)\b/, "sql"],
	[/\b(bash|sh|zsh)\b/, "bash"],
];

function heredocLanguage(opener: string): string | undefined {
	const target = opener.match(/>\s*([^\s<>|;&]+)/)?.[1];
	if (/\b(cat|tee)\b/.test(opener) && target) return getLanguageFromPath(target);
	for (const [pattern, lang] of INTERPRETERS) if (pattern.test(opener)) return lang;
	return undefined;
}

export function highlightCommand(command: string): string[] {
	const out: string[] = [];
	const lines = command.split("\n");
	let shell: string[] = [];
	const flushShell = () => {
		if (shell.length) out.push(...highlightCode(shell.join("\n"), "bash"));
		shell = [];
	};

	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		shell.push(line);
		const match = line.match(HEREDOC);
		if (!match) continue;

		const tag = match[2];
		let end = i + 1;
		while (end < lines.length && lines[end].trim() !== tag) end++;
		flushShell();
		const body = lines.slice(i + 1, end);
		if (body.length) out.push(...highlightCode(body.join("\n"), heredocLanguage(line.slice(0, match.index))));
		if (end < lines.length) shell.push(lines[end]);
		i = end;
	}
	flushShell();
	return out;
}

const ORIGINAL = Symbol.for("dotfiles.pi.bash-highlight.original");
const HIGHLIGHTED = Symbol.for("dotfiles.pi.bash-highlight.highlighted");

function patchUserBash() {
	const prototype = (BashExecutionComponent as any)?.prototype;
	if (typeof prototype?.render !== "function") return;
	const render: (width: number) => string[] = (prototype[ORIGINAL] ??= prototype.render);

	prototype.render = function (width: number): string[] {
		const header = this.contentContainer?.children?.[0];
		const theme = liveTheme();
		if (theme && header instanceof Text && !(header as any)[HIGHLIGHTED] && typeof this.command === "string") {
			const lines = highlightCommand(this.command);
			lines[0] = `${theme.fg("bashMode", theme.bold("$"))} ${lines[0]}`;
			header.setText(lines.join("\n"));
			(header as any)[HIGHLIGHTED] = true;
		}
		return render.call(this, width);
	};
}

export default function (pi: ExtensionAPI) {
	patchUserBash();

	pi.registerToolRenderer((toolName, next) => {
		const renderers = next();
		const renderCall = renderers?.renderCall;
		if (toolName !== "bash" || !renderCall) return renderers;

		return {
			...renderers,
			renderCall(args, theme: Theme, context) {
				const component = renderCall(args, theme, context);
				const command = (args as { command?: unknown })?.command;
				if (!(component instanceof Text) || typeof command !== "string" || !command) return component;

				const timeout = (args as { timeout?: unknown }).timeout;
				const suffix = timeout ? theme.fg("muted", ` (timeout ${timeout}s)`) : "";
				const lines = highlightCommand(command);
				lines[0] = `${theme.fg("toolTitle", theme.bold("$"))} ${lines[0]}`;
				lines[lines.length - 1] += suffix;
				component.setText(lines.join("\n"));
				return component;
			},
		};
	});
}
