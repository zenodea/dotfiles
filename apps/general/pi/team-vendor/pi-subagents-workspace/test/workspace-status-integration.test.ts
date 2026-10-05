import { type ExtensionContext, SessionManager } from "@earendil-works/pi-coding-agent";
import { type Component, ScrollView, stripTerminalSequences, type Terminal, Text, type TUI, TuiAltScreen, VStack, visibleWidth } from "@earendil-works/pi-tui";
import { getScrollViewBox, renderLayoutFrame } from "@earendil-works/pi-tui/dist/layout.js";
import { extractAnsiCode, getActiveBackgroundAnsi } from "@earendil-works/pi-tui/dist/utils.js";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import subagentsExtension from "../src/index.js";
import type { Theme } from "../src/ui/agent-widget.js";
import { AgentWorkspace } from "../src/ui/agent-workspace.js";
import { BACKGROUND_SIDEBAR_REQUEST, type BackgroundSidebarProvider, type BackgroundSnapshot } from "../src/ui/workspace-status.js";
import { TODO_PANEL_HOST, type TodoPanelHost, WorkspaceTodos } from "../src/ui/workspace-todos.js";
import { createWorkflowTask, updateWorkflowProgressBatch } from "../src/workflow/task.js";
import { DOWN, ENTER, harness, node, plain, record } from "./agent-workspace-metadata-harness.js";
import { ctx, type Hermetic, hermeticDir, makePi } from "./helpers/boot-extension.js";

let isolation: Hermetic | undefined;
let cleanup: (() => Promise<void>) | undefined;
beforeEach(() => { vi.useFakeTimers(); vi.setSystemTime(65000); });
afterEach(async () => {
  await cleanup?.(); cleanup = undefined;
  vi.useRealTimers(); vi.restoreAllMocks(); isolation?.restore(); isolation = undefined;
});
const settle = async () => { for (let i = 0; i < 20; i++) await Promise.resolve(); };
const theme: Theme = { fg: (_color, text) => text, bold: text => text };

async function boot(columns = 160, mode = "fullscreen") {
  isolation = hermeticDir({ settings: { workspaceEnabled: true, schedulingEnabled: false, outputTranscript: false } });
  const b = makePi();
  const handlers = new Map<string, Set<(value: unknown) => void>>();
  b.pi.events.on.mockImplementation((name: string, handler: (value: unknown) => void) => {
    const listeners = handlers.get(name) ?? new Set(); handlers.set(name, listeners); listeners.add(handler);
    return () => listeners.delete(handler);
  });
  b.pi.events.emit.mockImplementation((name: string, value: unknown) => { for (const handler of handlers.get(name) ?? []) handler(value); });
  let owner: object;
  let answer: BackgroundSnapshot = { state: "ready", jobs: Array.from({ length: 12 }, (_, i) => ({ jobId: `job-${i}`, name: `root job ${i}`, state: "running", createdAt: 1000 })), hasMore: false };
  const read = vi.fn<BackgroundSidebarProvider["read"]>(async () => answer);
  b.pi.events.on(BACKGROUND_SIDEBAR_REQUEST, (value: unknown) => {
    const request = value as { sessionManager: object; respond(provider: BackgroundSidebarProvider): void };
    // Fake exporter reproduces the strict exact-owner contract, not a global list.
    if (request.sessionManager === owner) request.respond({ read });
  });
  let todoOffer: TodoPanelHost | undefined;
  b.pi.events.on(TODO_PANEL_HOST, (value: unknown) => {
    todoOffer = value as TodoPanelHost;
    todoOffer.mount?.(() => new Text("Todos\n○ pending\n◐ working\n✓ complete", 0, 0));
  });
  b.pi.exec.mockImplementation(async (_command: string, args: string[]) => ({
    stdout: args.includes("status") ? "# branch.oid (initial)\0# branch.head main\0? scratch.txt\0" : "", stderr: "", code: 0, killed: false,
  }));
  const enabled = vi.spyOn(AgentWorkspace.prototype, "setEnabled");
  subagentsExtension(b.pi);
  const workspace = enabled.mock.contexts[0];
  expect(workspace).toBeInstanceOf(AgentWorkspace);
  expect(b.pi.exec).not.toHaveBeenCalled(); expect(read).not.toHaveBeenCalled();
  let input!: (data: string) => void;
  const terminal: Terminal = {
    columns, rows: 30, kittyProtocolActive: false,
    start: handler => { input = handler; }, stop: () => {}, drainInput: async () => {},
    write: () => {}, moveBy: () => {}, hideCursor: () => {}, showCursor: () => {}, clearLine: () => {}, clearFromCursor: () => {},
    clearScreen: () => {}, setTitle: () => {}, setProgress: () => {},
  };
  const tui = new TuiAltScreen(terminal);
  Object.assign(tui, { mode });
  let draft = "Main draft";
  const editor: Component & { getText(): string; getCursor(): { line: number; col: number }; setText(text: string): void } = {
    render: () => [draft], invalidate: () => {}, getText: () => draft, getCursor: () => ({ line: 0, col: 0 }), setText: text => { draft = text; },
    handleInput: data => { if (/^[a-z]$/.test(data)) draft += data; },
  };
  const transcript = new ScrollView(new Text("native transcript\n".repeat(50), 0, 0), { primary: true, follow: "end" });
  const dock = new VStack([editor]);
  const nativeRoot = new VStack([{ component: transcript, basis: 0, grow: 1, minSize: 1 }, { component: dock, basis: "auto", minSize: 1 }]);
  tui.setLayoutRoot(nativeRoot); tui.start(); tui.setFocus(editor);
  let bridge: Component | undefined;
  const ui = {
    setWidget: vi.fn((key: string, content: unknown) => {
      if (key === "agent-workspace-bridge") bridge = typeof content === "function" ? (content as (tui: TUI, theme: Theme) => Component)(tui as unknown as TUI, theme) : undefined;
    }),
    onTerminalInput: (handler: (data: string) => { consume?: boolean } | undefined) => tui.addInputListener(handler),
    notify: vi.fn(), input: vi.fn(), setStatus: vi.fn(), addAutocompleteProvider: vi.fn(),
    getEditorText: () => draft, setEditorText: vi.fn((text: string) => { draft = text; }),
  };
  const sessionManager = SessionManager.inMemory(isolation.dir); owner = sessionManager;
  const context: ExtensionContext = ctx({ hasUI: true, ui, sessionManager });
  cleanup = async () => { await b.lifecycle.get("session_shutdown")({ reason: "quit" }, context); tui.stop(); };
  await b.lifecycle.get("session_start")({ reason: "new" }, context);
  expect(b.pi.exec).not.toHaveBeenCalled(); expect(read).not.toHaveBeenCalled(); // Mount/factory is I/O-free.
  const parts = () => {
    const entries = node(node(node(tui.layoutRoot!).entries[0].component).entries[1].component).entries;
    const scrolls = entries.map(entry => node(entry.component).entries[0].component as ScrollView);
    return { tree: scrolls[0], background: scrolls[1], git: scrolls[2], todos: scrolls[3] };
  };
  const frame = () => renderLayoutFrame(tui.layoutRoot!, terminal.columns, terminal.rows, () => tui.requestRender());
  return { ...b, workspace, tui, terminal, transcript, nativeRoot, dock, editor, ui, context, read, parts, frame,
    input: (data: string) => input(data), draft: () => draft, bridge: () => bridge,
    todoOffer: () => todoOffer, setAnswer: (next: BackgroundSnapshot) => { answer = next; },
    changeOwner: (next: object) => { owner = next; } };
}

describe("mounted real extension status integration", () => {
  it("wires root context/events and pi.exec with argv/signal/timeout, without render/factory work", async () => {
    const b = await boot();
    const sections = Object.values(b.parts());
    const initial = b.frame();
    const before = sections.map(scroll => getScrollViewBox(initial, scroll)!.parent!.rect);
    b.workspace.refresh();
    const loading = b.frame();
    expect(sections.map(scroll => getScrollViewBox(loading, scroll)!.parent!.rect)).toEqual(before);
    await settle();
    const ready = b.frame();
    expect(sections.map(scroll => getScrollViewBox(ready, scroll)!.parent!.rect)).toEqual(before);
    expect(b.read).toHaveBeenCalledTimes(1);
    const request = b.pi.events.emit.mock.calls.find(([name]: [string]) => name === BACKGROUND_SIDEBAR_REQUEST)[1];
    expect(Object.keys(request).sort()).toEqual(["respond", "sessionManager"]);
    expect(request.sessionManager).toBe(b.context.sessionManager);
    expect(b.pi.exec).toHaveBeenCalledWith("git", expect.arrayContaining(["-C", b.context.cwd, "status", "--porcelain=v2"]), { signal: expect.any(AbortSignal), timeout: 5000 });
    const parts = b.parts();
    expect(parts.background.children[0]).not.toBe(parts.git.children[0]);
    expect(parts.todos.children[0]).toBeInstanceOf(WorkspaceTodos);
    expect(plain(parts.background.render(38))).toContain("root job 0");
    expect(plain(parts.git.render(38))).toContain("ahead — · untracked 1");
    expect(plain(parts.git.render(38))).toContain("? scratch.txt");
    const requests = b.pi.exec.mock.calls.length;
    b.frame(); b.bridge()?.render(160); b.tui.renderNow(); b.frame();
    expect(b.pi.exec).toHaveBeenCalledTimes(requests); expect(b.read).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(2800);
    expect(b.pi.exec).toHaveBeenCalledTimes(requests); expect(b.read).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(200);
    expect(b.pi.exec).toHaveBeenCalledTimes(requests + 1); expect(b.read).toHaveBeenCalledTimes(2);
    expect(b.ui.setEditorText).not.toHaveBeenCalled(); expect(b.draft()).toBe("Main draft");
  });

  it.each([80, 160])("routes real status mouse/wheel independently of tree, drafts and transcript at %i columns", async columns => {
    const b = await boot(columns);
    b.pi.exec.mockResolvedValue({ stdout: `# branch.oid (initial)\0# branch.head main\0? scratch.txt\0${Array.from({ length: 12 }, (_, i) => `? extra-${i}\0`).join("")}`, stderr: "", code: 0, killed: false });
    if (columns < 120) b.workspace.focusTree();
    b.workspace.refresh(); await settle();
    const { tree, background, git, todos } = b.parts();
    b.tui.renderNow();
    const beforeTree = tree.render(columns < 120 ? columns : 38);
    const beforeTop = tree.scrollTop; const beforeTranscript = b.transcript.scrollTop;
    const bounds = () => {
      const frame = b.frame();
      return [tree, background, git, todos].map(scroll => getScrollViewBox(frame, scroll)!.parent!.rect);
    };
    const initialBounds = bounds();
    const box = getScrollViewBox(b.frame(), background)!;
    expect(box.rect.height).toBeGreaterThan(0);
    expect(todos.viewportHeight).toBeGreaterThan(0);
    const x = box.rect.x + 4; const y = box.rect.y;
    b.input(`\x1b[<0;${x + 1};${y + 1}M`); b.input(`\x1b[<0;${x + 1};${y + 1}m`);
    expect(background.render(38).map(stripTerminalSequences)[0]).toContain("▸ Background");
    expect(bounds()).toEqual(initialBounds);
    expect(b.tui.getFocusedComponent()).toBe(b.editor);
    b.tui.renderNow();
    b.input(`\x1b[<0;${x + 1};${y + 1}M`); b.input(`\x1b[<0;${x + 1};${y + 1}m`);
    b.tui.renderNow();
    b.input(`\x1b[<65;${x + 1};${y + 2}M`);
    expect(background.scrollTop).toBeGreaterThan(0);
    expect(git.scrollTop).toBe(0);
    background.scrollToStart(); b.tui.renderNow();
    b.input(`\x1b[<64;${x + 1};${y + 2}M`); // Boundary wheel must not fall through to the primary pane.
    expect(background.scrollTop).toBe(0);
    expect(tree.scrollTop).toBe(beforeTop); expect(b.transcript.scrollTop).toBe(beforeTranscript);
    const width = columns < 120 ? columns : 38;
    const gitY = getScrollViewBox(b.frame(), git)!.rect.y;
    b.tui.renderNow();
    b.input(`\x1b[<65;${x + 1};${gitY + 2}M`);
    expect(git.scrollTop).toBeGreaterThan(0);
    expect(background.scrollTop).toBe(0); expect(tree.scrollTop).toBe(beforeTop); expect(todos.scrollTop).toBe(0);
    expect(b.transcript.scrollTop).toBe(beforeTranscript);
    git.scrollToEnd(); b.tui.renderNow();
    const gitEnd = git.scrollTop;
    b.input(`\x1b[<65;${x + 1};${gitY + 2}M`);
    expect(git.scrollTop).toBe(gitEnd); expect(background.scrollTop).toBe(0);
    expect(b.transcript.scrollTop).toBe(beforeTranscript);
    git.scrollToStart(); b.tui.renderNow();
    b.input(`\x1b[<0;${x + 1};${gitY + 1}M`); b.input(`\x1b[<0;${x + 1};${gitY + 1}m`);
    expect(plain(git.render(width))).toContain("▸ Git");
    expect(plain(git.render(width))).not.toContain("scratch.txt");
    expect(plain(git.render(width))).toContain("ahead — · untracked 13");
    expect(bounds()).toEqual(initialBounds);
    // Wheel over collapsed section slack is still section-owned.
    b.tui.renderNow();
    b.input(`\x1b[<65;${x + 1};${gitY + initialBounds[2].height}M`);
    expect(git.scrollTop).toBe(0); expect(background.scrollTop).toBe(0);
    expect(b.transcript.scrollTop).toBe(beforeTranscript);
    expect(tree.render(columns < 120 ? columns : 38)).toEqual(beforeTree);
    expect(b.workspace.steerTarget()).toEqual({ kind: "main" });
    expect(b.draft()).toBe("Main draft"); expect(b.ui.setEditorText).not.toHaveBeenCalled();
    expect(b.tui.getFocusedComponent()).toBe(b.editor);
    b.input("x"); expect(b.draft()).toBe("Main draftx");
    expect(b.pi.exec.mock.calls.every(([command]: [string]) => command === "git")).toBe(true);
  });

  it("resets all sidebar cells beside a transcript background, with no blank scrollback", async () => {
    const b = await boot();
    (b.transcript.children[0] as Text).setText("\x1b[41mtranscript\n".repeat(50));
    for (const populated of [false, true]) {
      if (populated) { b.workspace.refresh(); await settle(); }
      const frame = b.frame();
      for (const scroll of Object.values(b.parts())) {
        const box = getScrollViewBox(frame, scroll)!;
        const slot = box.parent!.rect;
        for (let y = slot.y; y < slot.y + slot.height; y++) {
          expect(frame.lines[y]).toContain("\x1b[41m"); // Test actually paints a colored transcript.
          // Inspect the actual SGR state BEFORE each cell; ANSI slice helpers
          // append resets, which would hide the very bleed this test detects.
          const line = frame.lines[y];
          let styles = "";
          for (let index = 0, x = 0; index < line.length;) {
            const ansi = extractAnsiCode(line, index);
            if (ansi) { styles += ansi.code; index += ansi.length; continue; }
            const char = String.fromCodePoint(line.codePointAt(index)!);
            if (x >= slot.x && x < slot.x + slot.width) expect(getActiveBackgroundAnsi(styles)).toBe("");
            x += visibleWidth(char);
            index += char.length;
          }
        }
      }
      if (!populated) {
        expect(b.parts().tree.render(38)).toHaveLength(2);
        expect(b.parts().background.render(38)).toHaveLength(1);
        expect(b.parts().git.render(38)).toHaveLength(1);
      }
    }
  });

  it("pauses closed narrow drawers, resumes wide/open, and releases readers and Todo leases on detach", async () => {
    const b = await boot(80);
    b.workspace.refresh(); await settle(); expect(b.read).not.toHaveBeenCalled(); expect(b.pi.exec).not.toHaveBeenCalled();
    b.workspace.focusTree(); await settle(); expect(b.read).toHaveBeenCalledTimes(1);
    b.workspace.selectMain(); await vi.advanceTimersByTimeAsync(6000);
    expect(b.read).toHaveBeenCalledTimes(1); expect(plain(b.parts().background.render(80))).not.toContain("root job");
    b.terminal.columns = 160; b.workspace.refresh(); await settle(); expect(b.read).toHaveBeenCalledTimes(2);
    const lease = b.todoOffer();
    b.workspace.setEnabled(false); await vi.advanceTimersByTimeAsync(6000);
    expect(b.read).toHaveBeenCalledTimes(2); expect(b.tui.layoutRoot).toBe(b.nativeRoot);
    expect(lease?.mount?.(() => new Text("stale", 0, 0))).toBe(false);
    b.workspace.setEnabled(true); b.workspace.refresh(); await settle(); expect(b.read).toHaveBeenCalledTimes(3);
    b.tui.setLayoutRoot(new VStack([new Text("unsupported", 0, 0)])); b.workspace.refresh(); await settle();
    await vi.advanceTimersByTimeAsync(6000); expect(b.read).toHaveBeenCalledTimes(3); expect(b.workspace.isAttached).toBe(false);
  });

  it("does not request idle repaint frames from the host tick or unchanged samples", async () => {
    const b = await boot();
    b.setAnswer({ state: "idle", jobs: [], hasMore: false });
    b.workspace.refresh(); await settle(); b.tui.renderNow();
    const repaint = vi.spyOn(b.tui, "requestRender");
    await vi.advanceTimersByTimeAsync(6200);
    expect(b.read).toHaveBeenCalledTimes(3);
    expect(repaint).not.toHaveBeenCalled();
    expect(b.draft()).toBe("Main draft");
  });

  it("does not sample unsupported/nonfullscreen mounts", async () => {
    const b = await boot(160, "regular");
    b.workspace.refresh(); await vi.advanceTimersByTimeAsync(6000);
    expect(b.workspace.isAttached).toBe(false); expect(b.pi.exec).not.toHaveBeenCalled(); expect(b.read).not.toHaveBeenCalled();
    Object.assign(b.tui, { mode: "fullscreen" }); b.workspace.refresh(); await settle(); expect(b.read).toHaveBeenCalledTimes(1);
    Object.assign(b.tui, { mode: "regular" }); b.workspace.refresh(); await vi.advanceTimersByTimeAsync(6000);
    expect(b.read).toHaveBeenCalledTimes(1);
  });

  it("fences session switches, expired providers, and late results through actual lifecycle handlers", async () => {
    const b = await boot();
    let resolve!: (value: BackgroundSnapshot) => void;
    b.read.mockImplementationOnce(() => new Promise(done => { resolve = done; }));
    b.workspace.refresh(); await settle();
    await b.lifecycle.get("session_before_switch")({ type: "session_before_switch" }, b.context);
    const old = b.context.sessionManager;
    const next = SessionManager.inMemory(b.context.cwd);
    b.context.sessionManager = next;
    await b.lifecycle.get("session_start")({ reason: "resume" }, b.context);
    resolve({ state: "ready", jobs: [{ jobId: "old", name: "must not leak", state: "running", createdAt: 0 }], hasMore: false }); await settle();
    b.workspace.refresh(); await settle();
    expect(plain(b.parts().background.render(38))).not.toContain("must not leak");
    expect(plain(b.parts().background.render(38))).toContain("Background"); // Reserved header even though exporter still owns the old exact manager.
    expect(plain(b.parts().background.render(38))).not.toContain("root job");
    expect(old).not.toBe(next); b.changeOwner(next);
    await vi.advanceTimersByTimeAsync(3000);
    expect(plain(b.parts().background.render(38))).toContain("root job 0");
    b.setAnswer({ state: "unavailable", jobs: [], hasMore: false, error: "offline" });
    await vi.advanceTimersByTimeAsync(3000);
    expect(plain(b.parts().background.render(38))).toContain("Unavailable · offline");
    expect(plain(b.parts().background.render(38))).not.toContain("root job 0");
    b.workspace.dispose(); const calls = b.read.mock.calls.length;
    await vi.advanceTimersByTimeAsync(6000); expect(b.read).toHaveBeenCalledTimes(calls);
  });
});

describe("sidebar glyph-only presentation", () => {
  it("keeps selected full-circle precedence and exact mixed-height tree hits while showing active/completed glyphs", () => {
    const records = [record({ id: "run", handle: "running" }), record({ id: "done", handle: "completed", status: "completed" }),
      record({ id: "fail", handle: "failed", status: "error" }), record({ id: "stop", handle: "stopped", status: "stopped" })];
    const task = createWorkflowTask({ id: "glyphs", script: "", meta: { name: "Build" } });
    updateWorkflowProgressBatch(task, [{ type: "workflow_agent", index: 0, label: "preview done", state: "done" }]);
    const h = harness(160, records, [task]);
    try {
      let lines = plain(h.workspace.renderSidebar(80)).split("\n");
      expect(lines.find(line => line.includes("Main"))).toContain("●");
      expect(lines.find(line => line.includes("Workflow Build"))).toContain("◐");
      expect(lines.find(line => line.includes("preview done"))).toContain("✓");
      expect(lines.find(line => line.includes("@running"))).toContain("◐");
      const finished = lines.findIndex(line => line.includes("Finished"));
      h.workspace.selectSidebarLine(finished);
      lines = plain(h.workspace.renderSidebar(80)).split("\n");
      expect(lines.find(line => line.includes("@completed"))).toContain("✓");
      expect(lines.find(line => line.includes("@failed"))).toContain("○");
      expect(lines.find(line => line.includes("@stopped"))).toContain("○");
      const completedLine = lines.findIndex(line => line.includes("@completed"));
      h.setEditorText("Main preserved"); h.workspace.selectSidebarLine(completedLine + 1); // Detail line, unchanged hit geometry.
      expect(plain(h.workspace.renderSidebar(80)).split("\n")[completedLine]).toContain("●");
      expect(h.workspace.steerTarget()).toMatchObject({ kind: "unavailable", id: "done" });
      h.setEditorText("child preserved"); h.workspace.focusTree(); h.input(DOWN);
      expect(plain(h.workspace.renderSidebar(80)).split("\n")[completedLine]).toContain("●");
      h.input(ENTER); h.workspace.selectMain(); expect(h.editorText()).toBe("Main preserved");
      h.workspace.selectSidebarLine(completedLine); expect(h.editorText()).toBe("child preserved");
    } finally { h.workspace.dispose(); }
  });
});
