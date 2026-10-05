import { type Component, stripTerminalSequences, type TUI, type TuiMouseEvent, visibleWidth } from "@earendil-works/pi-tui";
import { describe, expect, it, vi } from "vitest";
import { TODO_PANEL_HOST, TODO_PANEL_REQUEST, type TodoPanelHost, WorkspaceTodos } from "../src/ui/workspace-todos.js";

function fixture() {
  const listeners = new Map<string, Set<(data: unknown) => void>>();
  const events = {
    on(name: string, handler: (data: unknown) => void) {
      const handlers = listeners.get(name) ?? new Set();
      handlers.add(handler);
      listeners.set(name, handlers);
      return () => { handlers.delete(handler); };
    },
    emit(name: string, data: unknown) { for (const handler of listeners.get(name) ?? []) handler(data); },
  };
  const offers: TodoPanelHost[] = [];
  events.on(TODO_PANEL_HOST, data => offers.push(data as TodoPanelHost));
  const panel = new WorkspaceTodos(events);
  const requestRender = vi.fn();
  const tui = { requestRender } as unknown as TUI;
  return { panel, tui, events, offers, requestRender, listeners };
}

const render = (panel: WorkspaceTodos, width = 38) => panel.render(width).map(line => stripTerminalSequences(line).replace(/ ─+$/, "").trimEnd());

const headingClick: TuiMouseEvent = {
  type: "click", button: "left", x: 3, y: 0, screenX: 123, screenY: 20,
  width: 38, height: 12, shift: false, alt: false, ctrl: false,
};

function donor(text: string) {
  return { render: vi.fn(() => [text]), invalidate: vi.fn(), handleMouse: vi.fn() };
}

describe("WorkspaceTodos", () => {
  it("reserves a width-safe heading for absent/empty donors without changing their state", () => {
    const h = fixture();
    h.panel.setHost(h.tui);
    for (const width of [1, 24, 38, 80]) {
      const lines = h.panel.render(width);
      expect(lines).toHaveLength(1);
      expect(lines[0]).toMatch(/^\x1b\[0m/);
      expect(visibleWidth(lines[0])).toBe(width);
    }
    expect(render(h.panel)).toEqual([" Todos"]);
    h.offers.at(-1)?.mount?.(() => ({ render: () => [], invalidate: () => {} }));
    expect(render(h.panel)).toEqual([" Todos"]);
    expect(h.panel.handleMouse(headingClick)).toBeUndefined();
    h.panel.dispose();
  });

  it("forwards heading clicks and the donor's focus result without changing coordinates", () => {
    const h = fixture();
    h.panel.setHost(h.tui);
    const result = { handled: true, focus: false };
    let collapsed = true;
    const component: Component = {
      render: () => collapsed ? ["Todos"] : ["Todos", "Task 32"],
      invalidate() {},
      handleMouse: vi.fn(event => {
        expect(event).toBe(headingClick);
        collapsed = !collapsed;
        return result;
      }),
    };
    h.offers.at(-1)?.mount?.(() => component);
    expect(render(h.panel)).toEqual(["Todos"]);
    expect(h.panel.handleMouse(headingClick)).toBe(result);
    expect(render(h.panel)).toEqual(["Todos", "Task 32"]);
    expect(h.panel.handleMouse(headingClick)).toBe(result);
    expect(render(h.panel)).toEqual(["Todos"]);
    expect(component.handleMouse).toHaveBeenCalledTimes(2);
    h.panel.dispose();
  });

  it("renders live donor rows at the supplied width and delegates invalidation", () => {
    const h = fixture();
    h.panel.setHost(h.tui);
    let text = "pending";
    const invalidate = vi.fn();
    const donorRender = vi.fn((width: number) => [text.slice(0, width)]);
    const factory = vi.fn((tui: TUI) => {
      expect(tui).toBe(h.tui);
      return { render: donorRender, invalidate };
    });
    expect(h.offers.at(-1)?.mount?.(factory)).toBe(true);
    expect(render(h.panel)).toEqual(["pending"]);
    text = "completed";
    expect(render(h.panel, 4)).toEqual(["comp"]);
    expect(donorRender.mock.calls).toEqual([[38], [4]]);
    expect(factory).toHaveBeenCalledOnce();
    expect(h.panel.handleMouse(headingClick)).toBeUndefined();
    h.panel.invalidate();
    expect(invalidate).toHaveBeenCalledOnce();
    expect(h.requestRender).toHaveBeenCalledOnce();
    h.panel.dispose();
  });

  it("unmounts and replaces donors without dispatching to the old component", () => {
    const h = fixture();
    expect(render(h.panel)).toEqual([]);
    expect(h.panel.handleMouse(headingClick)).toBeUndefined();
    h.panel.invalidate();
    h.panel.setHost(h.tui);
    const offer = h.offers.at(-1)!;
    const old = donor("old");
    const current = donor("current");
    offer.mount?.(() => old);
    offer.mount?.(() => current);
    expect(render(h.panel)).toEqual(["current"]);
    expect(h.panel.handleMouse(headingClick)).toBeUndefined();
    h.panel.invalidate();
    expect(current.handleMouse).toHaveBeenCalledWith(headingClick);
    expect(current.invalidate).toHaveBeenCalledOnce();
    expect(offer.mount?.()).toBe(true);
    expect(h.requestRender).toHaveBeenCalledTimes(3);
    expect(render(h.panel)).toEqual([" Todos"]);
    expect(h.panel.handleMouse(headingClick)).toBeUndefined();
    h.panel.invalidate();
    expect(current.render).toHaveBeenCalledOnce();
    expect(current.handleMouse).toHaveBeenCalledOnce();
    expect(current.invalidate).toHaveBeenCalledOnce();
    expect(old.render).not.toHaveBeenCalled();
    expect(old.handleMouse).not.toHaveBeenCalled();
    expect(old.invalidate).not.toHaveBeenCalled();
    h.panel.dispose();
  });

  it("rejects stale leases even when reattached to the same stable TUI proxy", () => {
    const h = fixture();
    h.panel.setHost(h.tui);
    const old = h.offers.at(-1)!;
    const oldDonor = donor("old");
    expect(old.mount?.(() => oldDonor)).toBe(true);
    h.panel.setHost();
    expect(h.offers.at(-1)?.owner).toBe(old.owner);
    expect(h.offers.at(-1)?.mount).toBeUndefined();
    expect(render(h.panel)).toEqual([]);
    expect(h.panel.handleMouse(headingClick)).toBeUndefined();
    h.panel.invalidate();
    const staleFactory = vi.fn(() => donor("stale"));
    expect(old.mount?.(staleFactory)).toBe(false);
    h.panel.setHost(h.tui);
    const current = h.offers.at(-1)!;
    expect(current.owner).toBe(old.owner);
    expect(current.mount?.(() => donor("new"))).toBe(true);
    expect(old.mount?.(staleFactory)).toBe(false);
    expect(old.mount?.()).toBe(false);
    expect(staleFactory).not.toHaveBeenCalled();
    expect(render(h.panel)).toEqual(["new"]);
    expect(h.requestRender).toHaveBeenCalledTimes(2);
    expect(oldDonor.render).not.toHaveBeenCalled();
    expect(oldDonor.handleMouse).not.toHaveBeenCalled();
    expect(oldDonor.invalidate).not.toHaveBeenCalled();
    h.panel.dispose();
  });

  it("supports late donors and clears failed factories without a native fallback", () => {
    const h = fixture();
    h.events.emit(TODO_PANEL_REQUEST, {});
    expect(h.offers.at(-1)?.mount).toBeUndefined();
    h.panel.setHost(h.tui);
    const count = h.offers.length;
    h.panel.setHost(h.tui);
    expect(h.offers).toHaveLength(count);
    h.events.emit(TODO_PANEL_REQUEST, {});
    expect(h.offers).toHaveLength(count + 1);
    const offer = h.offers.at(-1)!;
    const old = donor("ready");
    expect(offer.mount?.(() => old)).toBe(true);
    expect(offer.mount?.(() => { throw new Error("donor unavailable"); })).toBe(false);
    expect(render(h.panel)).toEqual([" Todos"]);
    expect(h.panel.handleMouse(headingClick)).toBeUndefined();
    h.panel.invalidate();
    expect(old.render).not.toHaveBeenCalled();
    expect(old.handleMouse).not.toHaveBeenCalled();
    expect(old.invalidate).not.toHaveBeenCalled();
    expect(offer.mount?.(() => donor("recovered"))).toBe(true);
    expect(render(h.panel)).toEqual(["recovered"]);
    h.panel.dispose();
  });

  it("disposal releases the donor, fences its lease, and unsubscribes idempotently", () => {
    const h = fixture();
    h.panel.setHost(h.tui);
    const offer = h.offers.at(-1)!;
    const component = donor("ready");
    offer.mount?.(() => component);
    h.panel.dispose();
    expect(h.offers.at(-1)?.owner).toBe(offer.owner);
    expect(h.offers.at(-1)?.mount).toBeUndefined();
    expect(h.listeners.get(TODO_PANEL_REQUEST)?.size).toBe(0);
    const count = h.offers.length;
    h.events.emit(TODO_PANEL_REQUEST, {});
    h.panel.dispose();
    expect(h.offers).toHaveLength(count);
    const staleFactory = vi.fn(() => component);
    expect(offer.mount?.(staleFactory)).toBe(false);
    expect(staleFactory).not.toHaveBeenCalled();
    expect(render(h.panel)).toEqual([]);
    expect(h.panel.handleMouse(headingClick)).toBeUndefined();
    h.panel.invalidate();
    expect(component.render).not.toHaveBeenCalled();
    expect(component.handleMouse).not.toHaveBeenCalled();
    expect(component.invalidate).not.toHaveBeenCalled();
  });
});
