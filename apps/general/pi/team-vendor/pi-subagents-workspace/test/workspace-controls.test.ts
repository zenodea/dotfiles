import { type Component, Container, ScrollView, stripTerminalSequences, type Terminal, Text, TuiAltScreen, type TuiMouseEvent } from "@earendil-works/pi-tui";
import { getLayoutBoxesAt, renderLayoutFrame } from "@earendil-works/pi-tui/dist/layout.js";
import { dispatchMouseEvent } from "@earendil-works/pi-tui/dist/tui.js";
import { describe, expect, it, vi } from "vitest";
import { createWorkflowTask, updateWorkflowProgressBatch } from "../src/workflow/task.js";
import { cursorRow, DOWN, ENTER, ESCAPE, F6, F7, harness, LEFT, node, plain, RIGHT, record, selectedContent, UP } from "./agent-workspace-metadata-harness.js";

const mouse = (x: number, y: number, width = 100, height = 8): TuiMouseEvent => ({
  type: "click", button: "left", x, y, screenX: x, screenY: y, width, height, shift: false, alt: false, ctrl: false,
});

function workflow() {
  const task = createWorkflowTask({ id: "wf_controls", script: "", meta: { name: "controls", description: "界面 long description ".repeat(10) } });
  updateWorkflowProgressBatch(task, Array.from({ length: 12 }, (_, index) => ({
    type: "workflow_agent" as const, index, label: `worker-${index}`, state: "done" as const, promptPreview: `assignment ${index}`, resultPreview: `result ${index}`,
  })));
  task.value = "result line\n".repeat(60);
  return task;
}

function stagedWorkflow() {
  const task = workflow();
  task.meta!.phases = [{ title: "Plan" }, { title: "Build" }, { title: "Verify" }];
  updateWorkflowProgressBatch(task, task.meta!.phases.flatMap((phase, phaseIndex) => [
    { type: "workflow_phase" as const, index: phaseIndex, title: phase.title },
    ...Array.from({ length: 4 }, (_, offset) => ({
      type: "workflow_agent" as const, index: phaseIndex * 4 + offset, label: `worker-${phaseIndex * 4 + offset}`,
      state: "done" as const, phaseIndex, phaseTitle: phase.title, promptPreview: `assignment ${phaseIndex * 4 + offset}`,
    })),
  ]));
  return task;
}

function renderScroll(scroll: ScrollView, width = 100, height = 8) {
  return renderLayoutFrame(scroll, width, height, () => {});
}

function clickTab(scroll: ScrollView, tab: string, width = 100) {
  const frame = renderScroll(scroll, width);
  const y = frame.lines.findIndex(line => plain([line]).includes(tab));
  expect(y).toBeGreaterThanOrEqual(0);
  const x = plain([frame.lines[y]]).indexOf(tab);
  // Use the styled line's visible coordinates (the harness's bold adds '*').
  const styledX = frame.lines[y].replace(/\x1b\[[0-9;]*m/g, "").indexOf(tab);
  expect(x).toBeGreaterThanOrEqual(0);
  return scroll.handleMouse(mouse(styledX, y, width));
}

// Mirrors pi 0.85's native deepest-first layout dispatch. It already supplies
// document-local coordinates; an owning ScrollView must not add its offset twice.
function clickLayout(frame: ReturnType<typeof renderLayoutFrame>, x: number, y: number) {
  for (const box of getLayoutBoxesAt(frame, x, y)) {
    if (box.component.handleMouse === Container.prototype.handleMouse) continue;
    const result = dispatchMouseEvent(box.component, { ...mouse(x, y), x: x - box.rect.x, y: y - box.rect.y, width: box.rect.width, height: box.rect.height });
    if (result) return result;
  }
  return undefined;
}

describe("workspace controls through rendered scroll views", () => {
  it.each([80, 160])("clicks mixed-height workflow/stage/agent rows after scrolling at %i columns", columns => {
    const h = harness(columns, [], [stagedWorkflow()]);
    const width = columns < 120 ? columns : 38;
    try {
      const sidebar = node(node(node(node(h.tui.layoutRoot).entries[0].component).entries[1].component).entries[0].component).entries[0].component as ScrollView;
      for (const route of ["scroll", "layout"]) {
        for (const [label, offset, expected] of [
          ["Workflow controls", 1, "[overview]"], // Workflow summary line.
          ["Build", 0, "[overview]"], // One-line stage.
          ["worker-4", 0, "assignment 4"], // The row immediately after that stage.
          ["worker-4", 1, "assignment 4"], // Agent secondary line.
        ] as const) {
          h.workspace.focusTree();
          const row = sidebar.render(width).findIndex(line => line.includes(label)) + offset;
          expect(row).toBeGreaterThan(0);
          renderScroll(sidebar, width, 6);
          sidebar.scrollTo(row, { disableFollow: true });
          const frame = renderScroll(sidebar, width, 6);
          expect(sidebar.scrollTop).toBe(row);
          expect((route === "scroll" ? sidebar.handleMouse(mouse(8, 0, width, 6)) : clickLayout(frame, 8, 0))?.handled).toBe(true);
          expect(plain((selectedContent(h.tui) as ScrollView).render(100))).toContain(expected);
          const filled = plain(sidebar.render(width)).split("\n").filter(line => line.includes("●"));
          expect(filled).toHaveLength(1);
          expect(filled[0]).toContain(`● ${label === "Build" ? "Workflow controls" : label}`);
        }
      }
    } finally { h.workspace.dispose(); }
  });

  it.each([80, 160])("keeps every mixed-height cursor row fully visible in a small viewport at %i columns", columns => {
    const h = harness(columns, [], [stagedWorkflow()]);
    const width = columns < 120 ? columns : 38;
    try {
      const sidebar = node(node(node(node(h.tui.layoutRoot).entries[0].component).entries[1].component).entries[0].component).entries[0].component as ScrollView;
      h.workspace.focusTree();
      renderScroll(sidebar, width, 3);
      const assertVisible = () => {
        const all = sidebar.render(width);
        const cursor = all.findIndex(line => plain([line]).startsWith("›"));
        const detail = /Workflow controls|worker-\d+/.test(plain([all[cursor]]));
        const frame = renderScroll(sidebar, width, 3);
        expect(cursor).toBeGreaterThanOrEqual(sidebar.scrollTop);
        expect(cursor + Number(detail)).toBeLessThan(sidebar.scrollTop + sidebar.viewportHeight);
        expect(plain(frame.lines)).toContain(plain([all[cursor]]));
        if (detail) expect(plain(frame.lines)).toContain(plain([all[cursor + 1]]));
      };
      assertVisible();
      // Main, workflow, three one-line stages and twelve two-line agents.
      for (const key of [...Array<string>(16).fill(DOWN), ...Array<string>(16).fill(UP)]) {
        expect(h.input(key)?.consume).toBe(true);
        assertVisible();
      }
      expect(cursorRow(h)).toContain("Main");
      expect(sidebar.scrollTop).toBe(1);
    } finally { h.workspace.dispose(); }
  });

  it("dispatches real fullscreen mouse/wheel events without translating document coordinates twice", () => {
    const task = workflow();
    const h = harness(160, [], [task]);
    let input: ((data: string) => void) | undefined;
    const terminal: Terminal = {
      columns: 160, rows: 12, kittyProtocolActive: false,
      start: onInput => { input = onInput; }, stop: () => {}, drainInput: async () => {},
      write: () => {}, moveBy: () => {}, hideCursor: () => {}, showCursor: () => {},
      clearLine: () => {}, clearFromCursor: () => {}, clearScreen: () => {}, setTitle: () => {}, setProgress: () => {},
    };
    const tui = new TuiAltScreen(terminal);
    const setRoot = h.tui.setLayoutRoot.bind(h.tui);
    h.tui.setLayoutRoot = root => { setRoot(root); tui.setLayoutRoot(root as Component | undefined); };
    h.tui.getFocusedComponent = () => tui.getFocusedComponent();
    h.tui.setFocus = component => tui.setFocus(component as Component | null);
    h.tui.hasOverlay = () => tui.hasOverlay();
    tui.setLayoutRoot(h.tui.layoutRoot as Component);
    tui.addInputListener(h.input);
    tui.start();
    try {
      input?.(RIGHT);
      const overview = selectedContent(h.tui) as ScrollView;
      tui.renderNow();
      overview.scrollTo(2, { disableFollow: true });
      tui.renderNow();
      // Pick cells from the compact header after applying its scroll offset.
      const all = overview.render(121);
      const tabRow = all.findIndex(line => line.includes("activity"));
      const column = all[tabRow].indexOf("activity") + 1;
      const screenRow = tabRow - overview.scrollTop + 1;
      input?.(`\x1b[<0;${column};${screenRow}M`); input?.(`\x1b[<0;${column};${screenRow}m`);
      const activity = selectedContent(h.tui) as ScrollView;
      expect(activity).not.toBe(overview);
      expect(plain(activity.render(100))).toContain("[activity]");
      input?.(RIGHT); // Results has scrollable content; Activity has native conversations only.
      const results = selectedContent(h.tui) as ScrollView;
      tui.renderNow();
      input?.("\x1b[<65;8;7M"); // Wheel down over the primary pane.
      expect(results.scrollTop).toBeGreaterThan(0);
      expect(overview.scrollTop).toBe(2);
      tui.setFocus(results.children[0]);
      input?.(ESCAPE);
      input?.(DOWN);
      expect(cursorRow(h)).toContain("worker-0");
      input?.(ENTER);
      expect(plain((selectedContent(h.tui) as ScrollView).render(100))).toContain("assignment 0");
    } finally { h.workspace.dispose(); tui.stop(); }
  });

  it("clicks every agent tab, redraws immediately, and does not follow metadata to the bottom", () => {
    const h = harness();
    try {
      h.input(RIGHT);
      let scroll = selectedContent(h.tui) as ScrollView;
      renderScroll(scroll);
      scroll.scrollTo(1, { disableFollow: true });
      const activity = scroll;
      for (const [tab, body] of [["details", "Assignment"], ["context", "Model test/model"], ["activity", "inspect files"]]) {
        h.tui.requestRender.mockClear();
        expect(clickTab(scroll, tab)?.handled).toBe(true);
        expect(h.tui.requestRender).toHaveBeenCalled();
        scroll = selectedContent(h.tui) as ScrollView;
        const frame = renderScroll(scroll);
        expect(plain(frame.lines)).toContain(`[${tab}]`);
        expect(plain(scroll.render(100))).toContain(body);
        expect(scroll.scrollTop).toBe(tab === "activity" ? 1 : 0);
        expect(scroll.followEnd).toBe(tab === "activity");
        expect(scroll.isFollowingEnd).toBe(false);
      }
      expect(scroll).toBe(activity);
      h.input(F7);
      scroll = selectedContent(h.tui) as ScrollView;
      expect(plain(scroll.render(100))).toContain("[details]");
    } finally { h.workspace.dispose(); }
  });

  it("clicks workflow tabs through a scrolled header, updates the store, and retains per-tab scroll", () => {
    const h = harness(160, [], [workflow()]);
    try {
      h.input(RIGHT);
      const overview = selectedContent(h.tui) as ScrollView;
      renderScroll(overview);
      overview.scrollTo(2, { disableFollow: true });
      h.tui.requestRender.mockClear();
      expect(clickTab(overview, "activity")?.handled).toBe(true);
      const activity = selectedContent(h.tui) as ScrollView;
      expect(activity).not.toBe(overview);
      expect(plain(renderScroll(activity).lines)).toContain("[activity]");
      expect(activity.scrollTop).toBe(0);
      expect(h.tui.requestRender).toHaveBeenCalled();
      h.input(F7); // Click and keyboard must agree about the current tab.
      const results = selectedContent(h.tui) as ScrollView;
      expect(plain(renderScroll(results).lines)).toContain("[results]");
      results.scrollTo(3, { disableFollow: true });
      expect(clickTab(results, "details")?.handled).toBe(true);
      const details = selectedContent(h.tui) as ScrollView;
      expect(plain(renderScroll(details).lines)).toContain("[details]");
      expect(clickTab(details, "overview")?.handled).toBe(true);
      expect(selectedContent(h.tui)).toBe(overview);
      expect(overview.scrollTop).toBe(2);
      expect(clickTab(overview, "results")?.handled).toBe(true);
      expect(selectedContent(h.tui)).toBe(results);
      expect(results.scrollTop).toBe(3);
      // Inactive cached documents retain the tab their ScrollView belongs to.
      expect(plain(overview.render(100))).toContain("[overview]");
    } finally { h.workspace.dispose(); }
  });

  it.each(["scroll", "layout"] as const)("activates the visible workflow agent inline via %s dispatch after scrolling", route => {
    const h = harness(160, [], [workflow()]);
    try {
      h.input(RIGHT);
      const scroll = selectedContent(h.tui) as ScrollView;
      const all = scroll.render(100);
      const row = all.findIndex(line => line.includes("worker-4"));
      renderScroll(scroll);
      scroll.scrollTo(row - 1, { disableFollow: true });
      const frame = renderScroll(scroll);
      expect(plain(frame.lines[1] ? [frame.lines[1]] : [])).toContain("worker-4");
      expect((route === "scroll" ? scroll.handleMouse(mouse(28, 1)) : clickLayout(frame, 28, 1))?.handled).toBe(true);
      const inline = selectedContent(h.tui) as Component;
      expect(plain(inline.render(100))).toContain("Activity · worker-4 · unavailable");
      expect(plain(inline.render(100))).not.toContain("assignment 4"); // Never reconstruct native activity from previews.
      expect(plain(inline.render(100))).toContain("[overview]");
      expect(h.input(ESCAPE)?.consume).toBe(true); // Back to browser, not global tree.
      expect(h.workspace.treeFocused).toBe(false);
      expect(selectedContent(h.tui)).toBe(inline);
      expect(node(inline).entries[0].component).toBe(scroll);
      expect(scroll.scrollTop).toBe(row - 1);
    } finally { h.workspace.dispose(); }
  });

  it.each(["scroll", "layout"] as const)("dispatches scrolled disclosures then native tools through %s coordinates", route => {
    const child = record({ sessionFile: "/tmp/private-session.jsonl" });
    child.session!.messages.unshift({ role: "user", content: "Long assignment\n".repeat(30) });
    const h = harness(160, [child]);
    try {
      h.input(RIGHT); h.input(RIGHT); // Details
      let scroll = selectedContent(h.tui) as ScrollView;
      const clickRow = (label: string) => {
        const all = scroll.render(100).map(stripTerminalSequences);
        const row = all.findIndex(line => plain([line]).includes(label));
        expect(row, plain(all)).toBeGreaterThan(0);
        renderScroll(scroll, 100, 3);
        scroll.scrollTo(row - 1, { disableFollow: true });
        const frame = renderScroll(scroll, 100, 3);
        const y = frame.lines.findIndex(line => plain([stripTerminalSequences(line)]).includes(label));
        expect(y).toBeGreaterThanOrEqual(0);
        h.tui.requestRender.mockClear();
        expect((route === "scroll" ? scroll.handleMouse(mouse(2, y, 100, 3)) : clickLayout(frame, 2, y))?.handled).toBe(true);
        expect(h.tui.requestRender).toHaveBeenCalled();
      };
      expect(plain(scroll.render(100))).not.toContain("/tmp/private-session.jsonl");
      clickRow("Technical details");
      expect(plain(scroll.render(100))).toContain("/tmp/private-session.jsonl");
      h.input(RIGHT); // Context
      expect(plain(scroll.render(100))).not.toContain("\nsystem prompt");
      clickRow("System prompt");
      expect(plain(scroll.render(100))).toContain("\nsystem prompt");
      h.input(RIGHT); // Activity — disclosure hit maps must not take native clicks.
      scroll = selectedContent(h.tui) as ScrollView;
      expect(plain(scroll.render(100))).not.toContain("result text");
      clickRow("read 界.ts");
      expect(plain(scroll.render(100))).toContain("result text");
      expect(h.manager.steer).not.toHaveBeenCalled();
      expect(h.manager.abort).not.toHaveBeenCalled();
    } finally { h.workspace.dispose(); }
  });

  it.each(["scroll", "layout"] as const)("selects the visible sidebar detail using %s dispatch at a nonzero offset", route => {
    const h = harness(160, Array.from({ length: 20 }, (_, index) => record({ id: `agent-${index}`, handle: `agent-${index}` })));
    try {
      const sidebar = node(node(node(node(h.tui.layoutRoot).entries[0].component).entries[1].component).entries[0].component).entries[0].component as ScrollView;
      renderScroll(sidebar, 38, 6);
      sidebar.scrollTo(12, { disableFollow: true });
      const frame = renderScroll(sidebar, 38, 6);
      expect(plain([frame.lines[0]])).toContain("@agent-5");
      h.tui.requestRender.mockClear();
      expect((route === "scroll" ? sidebar.handleMouse(mouse(10, 1, 38, 6)) : clickLayout(frame, 10, 1))?.handled).toBe(true);
      expect(h.workspace.steerTarget()).toMatchObject({ kind: "agent", id: "agent-5" });
      expect(h.tui.requestRender).toHaveBeenCalled();
      const top = sidebar.scrollTop;
      expect(sidebar.handleMouse({ ...mouse(10, 1, 38, 6), type: "wheel", button: "none", wheelDelta: 1 })).toBeUndefined();
      expect(sidebar.scrollTop).toBe(top); // Renderer owns wheel routing / overscroll.
    } finally { h.workspace.dispose(); }
  });
});

describe("workspace pane focus routing", () => {
  it.each(["scroll", "document"] as const)("navigates a finished workflow from its real focused %s without F6", focus => {
    const task = workflow();
    task.status = "completed";
    const h = harness(160, [], [task]);
    try {
      h.workspace.selectSidebarLine(2); // Expand Finished.
      h.workspace.selectSidebarLine(3); // Finished workflow.
      const scroll = selectedContent(h.tui) as ScrollView;
      renderScroll(scroll);
      h.tui.focusedComponent = focus === "scroll" ? scroll : scroll.children[0];
      expect(h.input(ESCAPE)?.consume).toBe(true);
      expect(h.input(DOWN)?.consume).toBe(true);
      expect(cursorRow(h)).toContain("worker-0");
      expect(h.input(DOWN)?.consume).toBe(true);
      expect(cursorRow(h)).toContain("worker-1");
      expect(h.input(ENTER)?.consume).toBe(true);
      const preview = selectedContent(h.tui) as ScrollView;
      expect(plain(preview.render(100))).toContain("assignment 1");
      expect(h.workspace.selectMain()).toBe(true);
      expect(selectedContent(h.tui)).toBe(h.nativeTranscript);
      expect(h.input(UP)).toBeUndefined();
      expect(h.input(DOWN)).toBeUndefined();
      expect(h.input(RIGHT)?.consume).toBe(true);
      expect(selectedContent(h.tui)).toBe(preview);
    } finally { h.workspace.dispose(); }
  });

  it.each(["editor", "scroll", "document"] as const)("transfers only owned pane focus across agent scroll containers from %s", focus => {
    const child = record({});
    child.session!.messages.unshift({ role: "user", content: "long assignment\n".repeat(40) });
    const h = harness(160, [child]);
    const editor = { getText: () => "", getCursor: () => ({ line: 0, col: 0 }), setText: vi.fn() };
    try {
      h.nativeTranscript.updateLayout(60, 8, () => {});
      h.nativeTranscript.scrollTo(2, { disableFollow: true });
      h.tui.focusedComponent = focus === "editor" ? editor : focus === "scroll" ? h.nativeTranscript : h.nativeTranscript.children[0];
      h.input(RIGHT);
      const activity = selectedContent(h.tui) as ScrollView;
      expect(h.tui.focusedComponent).toBe(focus === "editor" ? editor : activity);
      renderScroll(activity);
      activity.scrollTo(3, { disableFollow: true });
      if (focus === "document") h.tui.focusedComponent = activity.children[0];
      expect(h.input(RIGHT)?.consume).toBe(true);
      const metadata = selectedContent(h.tui) as ScrollView;
      expect(metadata.followEnd).toBe(false);
      expect(metadata).not.toBe(activity);
      expect(h.tui.focusedComponent).toBe(focus === "editor" ? editor : metadata);
      renderScroll(metadata);
      expect(metadata.scrollTop).toBe(0);
      expect(h.input(DOWN)?.consume).toBe(true);
      expect(metadata.scrollTop).toBe(1);
      expect(activity.scrollTop).toBe(3);
      expect(h.input(UP)?.consume).toBe(true);
      expect(metadata.scrollTop).toBe(0);
      if (focus === "document") h.tui.focusedComponent = metadata.children[0];
      expect(h.input(LEFT)?.consume).toBe(true);
      expect(selectedContent(h.tui)).toBe(activity);
      expect(h.tui.focusedComponent).toBe(focus === "editor" ? editor : activity);
      expect(activity.scrollTop).toBe(3);
      expect(activity.isFollowingEnd).toBe(false);
      h.workspace.selectMain();
      expect(selectedContent(h.tui)).toBe(h.nativeTranscript);
      expect(h.tui.focusedComponent).toBe(focus === "editor" ? editor : h.nativeTranscript);
      expect(h.nativeTranscript.scrollTop).toBe(2);
      expect(h.nativeTranscript.isFollowingEnd).toBe(false);
      expect(h.input(UP)).toBeUndefined();
      expect(h.input(DOWN)).toBeUndefined();
      expect(node(h.tui.layoutRoot).entries[1].component).toBe(node(h.nativeRoot).entries[1].component);
      expect(editor.setText).not.toHaveBeenCalled();
    } finally { h.workspace.dispose(); }
  });

  it("keeps pane focus usable after a clicked tab swaps workflow documents", () => {
    const h = harness(160, [], [workflow()]);
    try {
      h.input(RIGHT);
      const scroll = selectedContent(h.tui) as ScrollView;
      h.tui.focusedComponent = scroll;
      expect(clickTab(scroll, "activity")?.handled).toBe(true);
      expect(h.input(F7)?.consume).toBe(true);
      expect(plain((selectedContent(h.tui) as ScrollView).render(100))).toContain("[results]");
      const results = selectedContent(h.tui) as ScrollView;
      renderScroll(results);
      expect(h.input(DOWN)?.consume).toBe(true);
      expect(results.scrollTop).toBe(1);
      expect(cursorRow(h)).toBeUndefined();
    } finally { h.workspace.dispose(); }
  });

  it("Enter browses agent tabs in both directions, Up/Down scroll, Escape retains selection", () => {
    const child = record({});
    child.session!.messages.unshift({ role: "user", content: "assignment line\n".repeat(40) });
    const h = harness(160, [child]);
    try {
      expect(h.input(F6)?.consume).toBe(true);
      expect(h.input(DOWN)?.consume).toBe(true);
      const selected = cursorRow(h);
      expect(selected).toContain("◐ @general-purpose");
      expect(h.input(ENTER)?.consume).toBe(true);
      const current = () => selectedContent(h.tui) as ScrollView;
      const tabs = ["activity", "details", "context", "details"];
      expect(plain(current().render(100))).toContain(`[${tabs[0]}]`);
      for (const [key, tab] of [[RIGHT, tabs[1]], [RIGHT, tabs[2]], [LEFT, tabs[3]]]) {
        expect(h.input(key)?.consume).toBe(true);
        expect(plain(current().render(100))).toContain(`[${tab}]`);
        expect(cursorRow(h)).toBeUndefined();
      }
      // Wrap in both directions.
      h.input(LEFT);
      expect(plain(current().render(100))).toContain(`[${tabs[0]}]`);
      h.input(LEFT);
      expect(plain(current().render(100))).toContain("[context]");
      h.input(RIGHT);
      expect(plain(current().render(100))).toContain(`[${tabs[0]}]`);
      // Native Activity has enough actual content for a viewport scroll.
      renderScroll(current());
      current().scrollTo(0, { disableFollow: true });
      expect(h.input(DOWN)?.consume).toBe(true);
      expect(current().scrollTop).toBe(1);
      expect(h.input(UP)?.consume).toBe(true);
      expect(current().scrollTop).toBe(0);
      expect(h.input(ESCAPE)?.consume).toBe(true);
      expect(cursorRow(h)).toBe(selected?.replace("◐", "●"));
      expect(h.manager.abort).not.toHaveBeenCalled();
      expect(h.manager.steer).not.toHaveBeenCalled();
    } finally { h.workspace.dispose(); }
  });

  it("browses workflow phases/agents with arrows and Enter, and cycles all tabs with Tab/Shift+Tab", () => {
    const task = stagedWorkflow();
    const h = harness(160, [], [task]);
    try {
      h.workspace.focusTree(); h.input(DOWN); h.input(ENTER);
      const overview = selectedContent(h.tui) as ScrollView;
      const text = () => plain((selectedContent(h.tui) as ScrollView).render(100));
      expect(text()).toContain("Plan · 4 agents");
      expect(text()).toContain("❯ ✔ Plan");
      renderScroll(overview);
      expect(h.input(DOWN)?.consume).toBe(true);
      expect(text()).toContain("Build · 4 agents");
      expect(overview.scrollTop).toBe(0); // Pane selection, not document scrolling.
      expect(h.input(UP)?.consume).toBe(true);
      expect(text()).toContain("Plan · 4 agents");
      expect(h.input(RIGHT)?.consume).toBe(true);
      expect(text()).toContain("❯ ✔ worker-0");
      expect(h.input(DOWN)?.consume).toBe(true);
      expect(text()).toContain("❯ ✔ worker-1");
      expect(h.input(LEFT)?.consume).toBe(true);
      expect(text()).toContain("❯ ✔ Plan");
      expect(h.input(ENTER)?.consume).toBe(true); // Focus agents, not the editor.
      expect(selectedContent(h.tui)).toBe(overview);
      expect(text()).toContain("❯ ✔ worker-1");
      for (const tab of ["activity", "results", "details", "overview"]) {
        expect(h.input("\t")?.consume).toBe(true);
        expect(text()).toContain(`[${tab}]`);
      }
      expect(selectedContent(h.tui)).toBe(overview);
      expect(text()).toContain("❯ ✔ worker-1");
      expect(h.input("\x1b[Z")?.consume).toBe(true);
      expect(text()).toContain("[details]");
      expect(h.input(LEFT)?.consume).toBe(true); // Non-Overview arrows still cycle tabs.
      expect(text()).toContain("[results]");
      expect(h.input(RIGHT)?.consume).toBe(true);
      expect(text()).toContain("[details]");
      expect(h.input("\t")?.consume).toBe(true);
      expect(h.input(ENTER)?.consume).toBe(true);
      expect(text()).toContain("Activity · worker-1 · unavailable");
      expect(text()).toContain("[overview]");
      expect(h.manager.steer).not.toHaveBeenCalled();
      expect(h.manager.abort).not.toHaveBeenCalled();
    } finally { h.workspace.dispose(); }
  });

  it.each(["", "retained draft", " "])("leaves workflow editor keys and completion input alone with draft %j", draft => {
    const h = harness(160, [], [stagedWorkflow()]);
    try {
      h.workspace.selectSidebarLine(2);
      h.setEditorText(draft);
      h.workspace.focusTree(); h.input(ENTER); // Capture the retained draft.
      expect(h.input("x")).toBeUndefined(); // Explicitly enter editor focus.
      const scroll = selectedContent(h.tui) as ScrollView;
      for (const key of [LEFT, RIGHT, UP, DOWN, ENTER, "\t", "\x1b[Z"]) expect(h.input(key)).toBeUndefined();
      expect(h.editorText()).toBe(draft);
      expect(plain(scroll.render(100))).toContain("Plan · 4 agents");
      // Clicking a phase explicitly returns from the composer to browse focus.
      renderScroll(scroll, 100, 30);
      const lines = scroll.render(100);
      const phase = lines.findIndex(line => line.includes("Build"));
      expect(scroll.handleMouse(mouse(6, phase, 100, 30))?.handled).toBe(true);
      expect(h.input(UP)?.consume).toBe(true);
      expect(plain(scroll.render(100))).toContain("Plan · 4 agents");
      expect(h.editorText()).toBe(draft);
      expect(h.ui.setEditorText).not.toHaveBeenCalled();
      h.tui.focusedComponent = new Text("completion menu", 0, 0);
      for (const key of [LEFT, RIGHT, UP, DOWN, ENTER, "\t", "\x1b[Z"]) expect(h.input(key)).toBeUndefined();
    } finally { h.workspace.dispose(); }
  });

  it("consumes Overview Enter even for empty phases without entering the editor", () => {
    const task = createWorkflowTask({ id: "empty", script: "", meta: { phases: [{ title: "First" }, { title: "Next" }] } });
    const h = harness(160, [], [task]);
    try {
      h.workspace.selectSidebarLine(2);
      expect(h.input(ENTER)?.consume).toBe(true);
      expect(h.input(DOWN)?.consume).toBe(true);
      const text = plain((selectedContent(h.tui) as ScrollView).render(100));
      expect(text).toContain("Next · 0 agents");
      expect(text).toContain("No agents yet");
    } finally { h.workspace.dispose(); }
  });

  it.each(["draft", " ", "first\nsecond"])("explicit Enter browses a retained draft %j, typing resumes safe cursor keys", draft => {
    const h = harness();
    try {
      h.workspace.selectSidebarLine(2);
      h.setEditorText(draft);
      h.workspace.selectMain();
      h.input(F6); h.input(ENTER); // Cursor retains the child selected before Main.
      expect(h.editorText()).toBe(draft);
      expect(h.input(RIGHT)?.consume).toBe(true);
      expect(plain((selectedContent(h.tui) as ScrollView).render(100))).toContain("[details]");
      expect(h.editorText()).toBe(draft);
      expect(h.input("X")).toBeUndefined(); // Editor receives this unchanged.
      for (const key of [LEFT, RIGHT, UP, DOWN]) expect(h.input(key)).toBeUndefined();
      expect(plain((selectedContent(h.tui) as ScrollView).render(100))).toContain("[details]");
      expect(h.editorText()).toBe(draft);
      h.setEditorText(""); // Clearing the composer permits browsing again.
      expect(h.input(RIGHT)?.consume).toBe(true);
      expect(plain((selectedContent(h.tui) as ScrollView).render(100))).toContain("[context]");
    } finally { h.workspace.dispose(); }
  });

  it("clicking even the current tab deliberately returns from editing to browse focus", () => {
    const h = harness();
    try {
      h.workspace.selectSidebarLine(2);
      const scroll = selectedContent(h.tui) as ScrollView;
      h.input("x"); h.setEditorText("saved draft");
      renderScroll(scroll); scroll.scrollTo(0, { disableFollow: true });
      expect(clickTab(scroll, "activity")?.handled).toBe(true);
      expect(h.input(RIGHT)?.consume).toBe(true);
      expect(plain((selectedContent(h.tui) as ScrollView).render(100))).toContain("[details]");
      expect(h.editorText()).toBe("saved draft");
    } finally { h.workspace.dispose(); }
  });

  it("does not intercept overlays, selectors, modified/released arrows, drafts, or composition text", () => {
    const h = harness(160, [], [workflow()]);
    try {
      h.input(RIGHT);
      const scroll = selectedContent(h.tui) as ScrollView;
      h.tui.focusedComponent = scroll;
      for (const key of ["\x1b[1;5B", "\x1b[1;2D", "\x1b[57353;1:3u", "界", "\x1b[200~text\x1b[201~"]) expect(h.input(key)).toBeUndefined();
      for (const text of ["draft", " ", "line 1\nline 2", "界"]) {
        h.setEditorText(text);
        for (const key of [UP, DOWN, LEFT, RIGHT]) expect(h.input(key)).toBeUndefined();
        expect(h.editorText()).toBe(text);
      }
      h.setEditorText("");
      const modal = { getText: () => "", setText: vi.fn(), getCursor: () => ({ line: 0, col: 0 }), handleInput: vi.fn() };
      h.tui.focusedComponent = modal;
      Object.assign(h.tui, { hasOverlay: () => true });
      for (const key of [UP, DOWN, LEFT, RIGHT, ENTER, ESCAPE, F7]) expect(h.input(key)).toBeUndefined();
      Object.assign(h.tui, { hasOverlay: () => false });
      h.tui.focusedComponent = new Container(); // Selector/prompt, not our pane.
      for (const key of [UP, DOWN, LEFT, RIGHT, ENTER, ESCAPE, F7]) expect(h.input(key)).toBeUndefined();
      expect(selectedContent(h.tui)).toBe(scroll);
      expect(h.manager.abort).not.toHaveBeenCalled();
      expect(h.ui.setEditorText).not.toHaveBeenCalled();
    } finally { h.workspace.dispose(); }
  });
});
