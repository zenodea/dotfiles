import { type Component, HStack, ScrollView, Text, type TuiMouseEvent, VStack, visibleWidth } from "@earendil-works/pi-tui";
import { getScrollViewBox, getScrollViewsAt, renderLayoutFrame } from "@earendil-works/pi-tui/dist/layout.js";
import { retargetMouseEvent } from "@earendil-works/pi-tui/dist/tui.js";
import { describe, expect, it, vi } from "vitest";
import { sidebarHeading, sidebarLine, WorkspaceLayout, WorkspaceScrollView } from "../src/ui/workspace-layout.js";

const LAYOUT_NODE = Symbol.for("@earendil-works/pi-tui/layout-node");
const VIEWPORT_TUI = Symbol.for("@earendil-works/pi-tui/viewport");

type Node = { type: string; gap?: number; align?: string; entries?: readonly { component: object; basis?: number | string; grow?: number; shrink?: number; minSize?: number; maxSize?: number; visible?: (viewport: { width: number; height: number }) => boolean }[] };

function node(component: object): Node {
  return (component as { [LAYOUT_NODE](): Node })[LAYOUT_NODE]();
}

function fixture(columns = 160) {
  const document = new Text("main", 0, 0);
  const transcript = new ScrollView(document, { follow: "end", primary: true });
  const dock = new VStack([new Text("editor", 0, 0)]);
  const root = new VStack([
    { component: transcript, basis: 0, grow: 1, shrink: 1, minSize: 1 },
    { component: dock, basis: "auto", grow: 0, shrink: 1, minSize: 1 },
  ]);
  const tui = {
    mode: "fullscreen",
    terminal: { columns, rows: 40 },
    layoutRoot: root as object,
    requestRender: vi.fn(),
    setLayoutRoot(component: object | undefined) { this.layoutRoot = component; },
    [VIEWPORT_TUI]: true,
  };
  return { tui, root, transcript, dock };
}

describe("WorkspaceLayout", () => {
  it("translates a child pointer capture once and leaves wheel events to the host", () => {
    const handleMouse = vi.fn((event: TuiMouseEvent) => event.type === "press" ? { handled: true, capture: true } : undefined);
    const document: Component = { render: () => Array.from({ length: 30 }, (_, i) => `row ${i}`), handleMouse, invalidate: () => {} };
    const scroll = new WorkspaceScrollView(document, { primary: true, follow: "none", scrollbar: "always" });
    renderLayoutFrame(scroll, 20, 5, () => {});
    scroll.scrollTo(10);
    const frame = renderLayoutFrame(scroll, 20, 5, () => {});
    expect(frame.lines[1]).toContain("row 11");
    const event: TuiMouseEvent = { type: "press", button: "left", x: 2, y: 1, screenX: 12, screenY: 21, width: 20, height: 5, shift: false, alt: false, ctrl: false };
    const result = scroll.handleMouse(event);
    expect(handleMouse).toHaveBeenCalledExactlyOnceWith({ ...event, y: 11, width: 19, height: 30 });
    expect(result?.target.component).toBe(document);
    expect(result?.capture).toBe(true);
    expect(retargetMouseEvent({ ...event, type: "release", screenY: 23 }, result!.target).y).toBe(13);
    handleMouse.mockClear();
    expect(scroll.handleMouse({ ...event, x: 19 })).toBeUndefined(); // Reserved scrollbar column.
    expect(scroll.handleMouse({ ...event, y: 5 })).toBeUndefined(); // Outside viewport.
    expect(scroll.handleMouse({ ...event, type: "wheel", button: "none", wheelDelta: 1 })).toBeUndefined();
    expect(handleMouse).not.toHaveBeenCalled();
  });

  it("paints unused sidebar space with a background reset without adding blank scrollback", () => {
    const { tui } = fixture();
    const content = new Text("short tree", 0, 0);
    const sidebar = new ScrollView(content, { primary: false, follow: "none" });
    const layout = new WorkspaceLayout(sidebar);
    layout.attach(tui);
    const columns = node(node(tui.layoutRoot).entries![0].component).entries!;
    const panel = node(columns[1].component).entries!;
    // 40 rows less a five-row dock: a fixed 2/5 slot, two rows for Git, and the last one flexes.
    expect(panel.map(entry => entry.basis)).toEqual([14, 2, 0]);
    expect(panel.map(entry => entry.grow)).toEqual([0, 0, 1]);
    const slot = node(panel[0].component).entries!;
    expect(slot[0].component).toBe(sidebar);
    const filler = slot[1].component as Component;
    const blank = filler.render(38);
    expect(blank).toHaveLength(40);
    expect(blank.every(line => line.startsWith("\x1b[0m") && visibleWidth(line) === 38)).toBe(true);
    expect(sidebar.render(38)).toHaveLength(1);
    tui.terminal.rows = 60;
    expect(filler.render(38)).toHaveLength(60);
    layout.detach();
  });

  it("attaches through real layout primitives and restores the exact native root", () => {
    const { tui, root, transcript } = fixture();
    const layout = new WorkspaceLayout(new Text("tree", 0, 0));

    expect(layout.attach(tui)).toBe(true);
    expect(tui.layoutRoot).not.toBe(root);
    const workspace = node(tui.layoutRoot);
    expect(workspace.type).toBe("vstack");
    const content = node(workspace.entries![0].component);
    expect(content.type).toBe("hstack");
    expect(content.entries![0].component).toBe(transcript);

    layout.detach();
    expect(tui.layoutRoot).toBe(root);
  });

  it("places a fixed sidebar on the right when wide and a full-width drawer when narrow", () => {
    const wide = fixture();
    const sidebar = new Text("tree", 0, 0);
    const wideLayout = new WorkspaceLayout(sidebar);
    wideLayout.attach(wide.tui);
    const wideEntries = node(node(wide.tui.layoutRoot).entries![0].component).entries!;
    expect(wideEntries[0].grow).toBe(1);
    expect(wideEntries[1].maxSize).toBe(38);

    const narrow = fixture(80);
    const narrowLayout = new WorkspaceLayout(sidebar);
    narrowLayout.attach(narrow.tui);
    let entries = node(node(narrow.tui.layoutRoot).entries![0].component).entries!;
    expect(entries[0].visible?.({ width: 80, height: 40 })).toBe(true);
    expect(entries[1].visible?.({ width: 80, height: 40 })).toBe(false);

    narrowLayout.setDrawerOpen(true);
    entries = node(node(narrow.tui.layoutRoot).entries![0].component).entries!;
    expect(entries[0].visible?.({ width: 80, height: 40 })).toBe(false);
    expect(entries[1].visible?.({ width: 80, height: 40 })).toBe(true);
    expect(entries[1].basis).toBe(0);
    expect(entries[1].grow).toBe(1);
    expect(entries[1].maxSize).toBeUndefined();
  });

  it("fails open without changing unsupported roots or regular mode", () => {
    const sidebar = new Text("tree", 0, 0);
    const layout = new WorkspaceLayout(sidebar);
    const unsupported = {
      mode: "fullscreen",
      terminal: { columns: 160, rows: 40 },
      layoutRoot: new HStack([new Text("not chat", 0, 0)]),
      requestRender: vi.fn(),
      setLayoutRoot: vi.fn(),
      [VIEWPORT_TUI]: true,
    };
    expect(layout.attach(unsupported)).toBe(false);
    expect(unsupported.setLayoutRoot).not.toHaveBeenCalled();

    const regular = { ...unsupported, mode: "regular" };
    expect(layout.attach(regular)).toBe(false);

    const extra = fixture();
    extra.tui.layoutRoot = new VStack([
      { component: extra.transcript },
      { component: extra.dock },
      { component: new Text("host-owned extra", 0, 0) },
    ]);
    expect(layout.attach(extra.tui)).toBe(false);
  });

  it("forgets stale roots across stable-proxy renderer mode switches", () => {
    const first = fixture();
    const layout = new WorkspaceLayout(new Text("tree", 0, 0));
    expect(layout.sync(first.tui)).toBe(true);
    const staleWorkspace = first.tui.layoutRoot;

    first.tui.mode = "regular";
    first.tui.layoutRoot = undefined;
    expect(layout.sync(first.tui)).toBe(false);
    expect(layout.attached).toBe(false);

    const second = fixture();
    first.tui.mode = "fullscreen";
    first.tui.layoutRoot = second.root;
    expect(layout.sync(first.tui)).toBe(true);
    expect(first.tui.layoutRoot).not.toBe(staleWorkspace);
    layout.detach();
    expect(first.tui.layoutRoot).toBe(second.root);
  });

  it.each([80, 160])("reserves three content-independent slots through overflow, collapse and resize at %i columns", columns => {
    const { tui, transcript } = fixture(columns);
    const labels = ["Agents", "Git", "Todos"];
    const bodies: string[][] = [[], [], []];
    const scrollers = labels.map((label, index) => new WorkspaceScrollView({
      render: width => [sidebarHeading(label, width), ...bodies[index].map(line => sidebarLine(line, width))],
      invalidate: () => {},
    }, { follow: "none", primary: false, overscroll: "contain" }));
    const [tree, git, todos] = scrollers;
    const layout = new WorkspaceLayout(tree, todos, git);
    expect(layout.isSidebarVisible).toBe(false);
    expect(layout.attach(tui)).toBe(true);
    expect(layout.isSidebarVisible).toBe(columns >= 120);
    layout.setDrawerOpen(true);
    expect(layout.isSidebarVisible).toBe(true);
    const panel = node(node(node(tui.layoutRoot).entries![0].component).entries![1].component).entries!;
    expect(panel.map(entry => node(entry.component).entries![0].component)).toEqual(scrollers);
    expect(panel.map(({ basis, grow, minSize }) => ({ basis, grow, minSize }))).toEqual([
      { basis: 14, grow: 0, minSize: 1 }, { basis: 2, grow: 0, minSize: 1 }, { basis: 0, grow: 1, minSize: 1 },
    ]);
    const frame = () => renderLayoutFrame(tui.layoutRoot as Component, columns, tui.terminal.rows, () => {});
    const bounds = () => {
      const current = frame();
      return scrollers.map(scroll => {
        const box = getScrollViewBox(current, scroll)!;
        return { start: box.parent!.rect.y, end: box.parent!.rect.y + box.parent!.rect.height };
      });
    };
    for (const height of [40, 18, 10, 5, 60, 40]) {
      tui.terminal.rows = height;
      scrollers.forEach(scroll => { scroll.scrollToStart(); });
      bodies.forEach(body => { body.length = 0; });
      const empty = bounds();
      expect(empty[0].start).toBe(0);
      expect(empty.at(-1)!.end).toBe(height - 1); // Native one-line dock is untouched.
      for (let index = 0; index < labels.length; index++) {
        expect(empty[index].end).toBeGreaterThan(empty[index].start);
        if (index > 0) expect(empty[index].start).toBe(empty[index - 1].end);
        expect(frame().lines[empty[index].start]).toContain(labels[index]);
      }
      bodies.forEach((body, index) => { body.push(`${labels[index]} first`, `${labels[index]} second`); });
      expect(bounds()).toEqual(empty);
      bodies.forEach((body, index) => { body.push(...Array.from({ length: 100 }, (_, row) => `${labels[index]} overflow ${row}`)); });
      expect(bounds()).toEqual(empty);
      const current = frame();
      expect(current.primaryScrollView).toBe(columns >= 120 ? transcript : tree);
      for (const scroll of scrollers) {
        const box = getScrollViewBox(current, scroll)!;
        expect(getScrollViewsAt(current, box.rect.x + 2, box.rect.y)).toEqual([scroll]);
        const previous = scrollers.map(view => view.scrollTop);
        const mainTop = transcript.scrollTop;
        scroll.scrollToEnd();
        const endFrame = frame();
        expect(endFrame.lines[box.rect.y + box.rect.height - 1]).toContain("overflow 99");
        expect(bounds()).toEqual(empty);
        scrollers.forEach((other, index) => { if (other !== scroll) expect(other.scrollTop).toBe(previous[index]); });
        expect(transcript.scrollTop).toBe(mainTop);
        scroll.scrollToStart();
      }
      // Collapse/absence consumes only the header inside its existing slot.
      bodies[1].length = 0; bodies[2].length = 0;
      expect(bounds()).toEqual(empty);
      expect(scrollers[1].render(38)).toHaveLength(1);
      expect(scrollers[2].render(38)).toHaveLength(1);
    }
    layout.setDrawerOpen(false);
    expect(layout.isSidebarVisible).toBe(columns >= 120);
    tui.mode = "regular";
    expect(layout.isSidebarVisible).toBe(false);
    layout.detach();
    expect(layout.isSidebarVisible).toBe(false);
  });

  it("does not overwrite a replacement root during disposal", () => {
    const { tui } = fixture();
    const layout = new WorkspaceLayout(new Text("tree", 0, 0));
    layout.attach(tui);
    const replacement = new VStack([new Text("replacement", 0, 0)]);
    tui.layoutRoot = replacement;

    layout.detach();

    expect(tui.layoutRoot).toBe(replacement);
  });
});
