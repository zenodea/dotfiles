import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type { Component, TUI, TuiMouseEvent, TuiMouseEventResult } from "@earendil-works/pi-tui";
import { sidebarHeading, sidebarLine } from "./workspace-layout.js";

export const TODO_PANEL_HOST = "agent-workspace:todo-panel:v1";
export const TODO_PANEL_REQUEST = "agent-workspace:todo-panel-request:v1";

export type TodoPanelFactory = (tui: TUI) => Component;
export type TodoPanelHost = {
  owner: object;
  mount?: (factory?: TodoPanelFactory) => boolean;
};

/** Delegates the leased Todo component into the sidebar; never copies task state. */
export class WorkspaceTodos implements Component {
  private owner = {};
  private tui: TUI | undefined;
  private generation = 0;
  private component: Component | undefined;
  private unsubscribe: (() => void) | undefined;

  constructor(private events?: ExtensionAPI["events"]) {
    this.unsubscribe = events?.on(TODO_PANEL_REQUEST, () => this.publish());
  }

  setHost(tui?: TUI): void {
    if (this.tui === tui) return;
    this.tui = tui;
    this.generation++;
    this.component = undefined;
    this.publish();
  }

  private publish(): void {
    const tui = this.tui;
    const generation = this.generation;
    // A host offer is a lease on this exact attachment. A late donor update
    // cannot mount into a detached/replaced workspace through an old offer.
    const offer: TodoPanelHost = {
      owner: this.owner,
      mount: tui ? factory => {
        if (this.tui !== tui || this.generation !== generation) return false;
        try {
          this.component = factory?.(tui);
          tui.requestRender();
          return true;
        } catch {
          this.component = undefined;
          return false;
        }
      } : undefined,
    };
    this.events?.emit(TODO_PANEL_HOST, offer);
  }

  render(width: number): string[] {
    if (!this.tui || width <= 0) return [];
    const lines = this.component?.render(width) ?? [];
    if (!lines.length) return [sidebarHeading(" Todos", width)];
    // The donor owns its heading and hit geometry; only fill/reset its cells.
    return lines.map((line, index) => index === 0 ? sidebarHeading(line, width) : sidebarLine(line, width));
  }

  handleMouse(event: TuiMouseEvent): TuiMouseEventResult | undefined { return this.component?.handleMouse?.(event); }

  invalidate(): void { this.component?.invalidate(); }

  dispose(): void {
    this.setHost();
    this.unsubscribe?.();
    this.unsubscribe = undefined;
  }
}
