/**
 * todo-overlay.ts — Live todo component hosted in the workspace sidebar.
 *
 * Attachment-scoped factory registration, register-once + requestRender()
 * refresh, heading collapse, and auto-hide when empty. The workspace supplies
 * the bounded scroll container; native above-editor placement stays disabled.
 *
 * Reads live state via `getRenderState()` (the ctx-less foreground slot) at render
 * time — NEVER `replayFromBranch` from `tool_execution_end` (branch is stale;
 * `message_end` runs after).
 */

import type { ExtensionUIContext, Theme } from "@earendil-works/pi-coding-agent";
import { type Component, type TUI, truncateToWidth } from "@earendil-works/pi-tui";
import { getMaxWidgetLines, getStartCollapsed } from "./config.js";
import { formatStatusLabel, t } from "./state/i18n-bridge.js";
import { selectHasActive, selectOverlayLayout, selectShowTaskIds, selectTodoCounts } from "./state/selectors.js";
import { getRenderState } from "./state/store.js";
import { formatOverlayTaskLine } from "./view/format.js";

const WIDGET_KEY = "rpiv-todos";

/** Optional workspace lease; no native widget is shown when mounting fails. */
export type TodoPanelHost = {
	owner: object;
	mount: (factory?: (tui: TUI) => Component) => boolean;
};

// English fallbacks for localized overlay chrome strings.
const OVERLAY_HEADING = "Todos";
const OVERLAY_MORE = "more";

export class TodoOverlay {
	private uiCtx: ExtensionUIContext | undefined;
	private widgetRegistered = false;
	private panelHost: TodoPanelHost | undefined;
	private inPanel = false;
	private tui: TUI | undefined;
	private completedTaskIdsPendingHide = new Set<number>();
	private hiddenCompletedTaskIds = new Set<number>();
	private lastNextId: number | undefined;
	private collapsed = getStartCollapsed();

	setUICtx(ctx: ExtensionUIContext): void {
		// Identity-compare so repeat session_start handlers are idempotent;
		// on identity change (/reload) invalidate so update() re-registers.
		if (ctx !== this.uiCtx) {
			this.uiCtx = ctx;
			this.widgetRegistered = false;
			this.tui = undefined;
		}
	}

	setPanelHost(host?: TodoPanelHost): void {
		if (this.panelHost === host) return;
		if (this.inPanel) this.panelHost?.mount();
		else if (this.widgetRegistered) this.uiCtx?.setWidget(WIDGET_KEY, undefined);
		this.panelHost = host;
		this.inPanel = false;
		this.widgetRegistered = false;
	}

	update(): void {
		if (!this.uiCtx) return;
		const snapshot = this.getSnapshot();
		const visible = this.selectOverlayTasks(snapshot);

		if (visible.length === 0) {
			if (this.widgetRegistered) {
				if (this.inPanel) this.panelHost?.mount();
				else this.uiCtx.setWidget(WIDGET_KEY, undefined);
				this.inPanel = false;
				this.widgetRegistered = false;
				this.tui = undefined;
			}
			return;
		}

		if (!this.widgetRegistered) {
			const factory = (tui: TUI): Component => {
				this.tui = tui;
				return {
					render: (width: number) => this.uiCtx ? this.renderWidget(this.uiCtx.theme, width) : [],
					handleMouse: (event) => {
						if (event.type !== "click" || event.button !== "left" || event.y !== 0) return undefined;
						this.toggleCollapse();
						return { handled: true, focus: false };
					},
					invalidate: () => {}, // No cached strings; reads the live theme.
				};
			};
			this.inPanel = this.panelHost?.mount(factory) === true;
			// Keep task tools and host leases, but never restore the persistent editor strip.
			this.widgetRegistered = this.inPanel;
		} else {
			this.tui?.requestRender();
		}
	}

	resetCompletedDisplayState(): void {
		this.completedTaskIdsPendingHide.clear();
		this.hiddenCompletedTaskIds.clear();
		this.lastNextId = undefined;
	}

	hideCompletedTasksFromPreviousTurn(): void {
		if (this.completedTaskIdsPendingHide.size === 0) return;
		for (const taskId of this.completedTaskIdsPendingHide) {
			this.hiddenCompletedTaskIds.add(taskId);
		}
		this.completedTaskIdsPendingHide.clear();
		this.tui?.requestRender();
	}

	toggleCollapse(): void {
		this.collapsed = !this.collapsed;
		// Forced full redraw on the collapsed↔expanded height step, mirroring the
		// lane-dock's requestRender(shapeChanged); distinct from the non-forced
		// requestRender() refresh paths in update()/hideCompletedTasksFromPreviousTurn().
		this.tui?.requestRender(true);
	}

	isRegistered(): boolean {
		return this.widgetRegistered;
	}

	private getSnapshot() {
		const state = getRenderState();
		if (this.lastNextId !== undefined && state.nextId < this.lastNextId) {
			this.resetCompletedDisplayState();
		}
		this.lastNextId = state.nextId;
		const completedTaskIds = new Set(
			state.tasks.filter((task) => task.status === "completed").map((task) => task.id),
		);
		for (const taskId of this.completedTaskIdsPendingHide) {
			if (!completedTaskIds.has(taskId)) this.completedTaskIdsPendingHide.delete(taskId);
		}
		for (const taskId of this.hiddenCompletedTaskIds) {
			if (!completedTaskIds.has(taskId)) this.hiddenCompletedTaskIds.delete(taskId);
		}
		return { tasks: [...state.tasks], nextId: state.nextId };
	}

	private selectOverlayTasks(snapshot: ReturnType<TodoOverlay["getSnapshot"]>) {
		return snapshot.tasks.filter((task) => task.status !== "deleted" && !this.shouldHideCompletedTask(task));
	}

	private shouldHideCompletedTask(task: ReturnType<TodoOverlay["getSnapshot"]>["tasks"][number]): boolean {
		return task.status === "completed" && this.hiddenCompletedTaskIds.has(task.id);
	}

	private renderWidget(theme: Theme, width: number): string[] {
		const snapshot = this.getSnapshot();
		const overlayTasks = this.selectOverlayTasks(snapshot);
		if (overlayTasks.length === 0) return [];

		const overlayState = { tasks: overlayTasks, nextId: snapshot.nextId };
		const truncate = (line: string): string => truncateToWidth(line, width, "…");
		const counts = selectTodoCounts(overlayState);
		const hasActive = selectHasActive(overlayState);
		const showIds = selectShowTaskIds(overlayState);

		const headingColor = hasActive ? "accent" : "dim";
		const headingIcon = this.collapsed ? "▸" : "▾";
		const headingText = `${t("overlay.heading", OVERLAY_HEADING)} (${counts.completed}/${counts.total})`;
		const heading = truncate(`${theme.fg(headingColor, headingIcon)} ${theme.fg(headingColor, headingText)}`);

		// Hidden rows must not be marked as displayed for completion fading.
		if (this.collapsed) return this.withTrailingSpacer([heading]);

		const lines: string[] = [heading];
		// Budget for content rows (heading + tasks/summary). The rendered widget is
		// one line taller — withTrailingSpacer() appends a blank row below the panel.
		// Pi's global tool-output expansion mode is read on every render so its
		// expand/collapse shortcut also expands this live widget. Optional chaining
		// preserves compatibility with hosts predating getToolsExpanded().
		// The workspace supplies a bounded ScrollView, so expansion exposes every
		// task there. The non-panel row budget is retained without native mounting.
		const bodyBudget = this.inPanel || this.uiCtx?.getToolsExpanded?.() === true ? overlayTasks.length : getMaxWidgetLines() - 1;
		const layout = selectOverlayLayout(overlayState, bodyBudget);
		for (const task of layout.visible) {
			lines.push(truncate(`${theme.fg("dim", "├─")} ${formatOverlayTaskLine(task, theme, showIds)}`));
		}

		const newlyDisplayedCompletedTaskIds = overlayTasks
			.filter(
				(task) =>
					task.status === "completed" &&
					!this.completedTaskIdsPendingHide.has(task.id) &&
					!this.hiddenCompletedTaskIds.has(task.id),
			)
			.map((task) => task.id);
		for (const taskId of newlyDisplayedCompletedTaskIds) {
			this.completedTaskIdsPendingHide.add(taskId);
		}

		if (layout.hiddenCompleted === 0 && layout.truncatedTail === 0) {
			const last = lines.length - 1;
			lines[last] = lines[last].replace("├─", "└─");
			return this.withTrailingSpacer(lines);
		}

		const totalHidden = layout.hiddenCompleted + layout.truncatedTail;
		const overflowParts: string[] = [];
		if (layout.hiddenCompleted > 0) overflowParts.push(`${layout.hiddenCompleted} ${formatStatusLabel("completed")}`);
		if (layout.truncatedTail > 0) overflowParts.push(`${layout.truncatedTail} ${formatStatusLabel("pending")}`);
		const more = t("overlay.more", OVERLAY_MORE);
		const summary =
			overflowParts.length > 0 ? `+${totalHidden} ${more} (${overflowParts.join(", ")})` : `+${totalHidden} ${more}`;
		lines.push(truncate(`${theme.fg("dim", "└─")} ${theme.fg("dim", summary)}`));
		return this.withTrailingSpacer(lines);
	}

	/**
	 * Keep a trailing blank line below the Todo content for panel spacing.
	 */
	private withTrailingSpacer(lines: string[]): string[] {
		if (lines.length === 0) return lines;
		lines.push("");
		return lines;
	}

	dispose(): void {
		if (this.inPanel) this.panelHost?.mount();
		this.panelHost = undefined;
		this.inPanel = false;
		if (this.uiCtx) this.uiCtx.setWidget(WIDGET_KEY, undefined);
		this.widgetRegistered = false;
		this.tui = undefined;
		this.uiCtx = undefined;
		this.collapsed = getStartCollapsed();
		this.resetCompletedDisplayState();
	}
}
