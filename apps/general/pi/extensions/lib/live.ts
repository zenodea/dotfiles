import type { Theme } from "@earendil-works/pi-coding-agent";

const THEME_KEY = Symbol.for("@earendil-works/pi-coding-agent:theme");

export function liveTheme(): Theme | undefined {
	return (globalThis as any)[THEME_KEY];
}

export interface Transcript {
	view: any;
	box: any;
	rows: string[];
}

export function transcript(tui: any): Transcript | undefined {
	const view = tui?.getPrimaryScrollView?.();
	if (!view) return undefined;
	const find = (box: any): any => (box?.scrollView === view ? box : box?.children?.map(find).find(Boolean));
	const box = find(tui.currentLayout?.root);
	const rows: string[] | undefined = box?.scrollContentLines;
	return rows ? { view, box, rows } : undefined;
}

export function startsUserMessage(row: string | undefined, background: string): boolean {
	return !!row && /^\x1b\]133;A/.test(row) && row.includes(background);
}
