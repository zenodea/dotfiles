import { createEventBus } from "@earendil-works/pi-coding-agent";
import { getKeybindings, KeybindingsManager, ScrollView, setKeybindings, stripTerminalSequences, Text, type TUI, visibleWidth } from "@earendil-works/pi-tui";
import { describe, expect, it, vi } from "vitest";
import type { AgentRecord } from "../src/types.js";
import { WorkspaceAwareComponent } from "../src/ui/agent-workspace.js";
import { createWorkflowTask, updateWorkflowProgressBatch } from "../src/workflow/task.js";

import { cursorRow, DOWN, ENTER, ESCAPE, F6, F7, F8, F9, harness, LEFT, markedRow, node, plain, RIGHT, record, selectedContent, UP } from "./agent-workspace-metadata-harness.js";

// Real SGR markers keep styling assertions detectable without adding cells.
function styleSidebar(h: ReturnType<typeof harness>): void {
  const ui = { ...h.ui, setWidget: vi.fn(h.ui.setWidget) };
  h.workspace.setUI(ui);
  const factory = ui.setWidget.mock.calls.at(-1)?.[1];
  if (typeof factory !== "function") throw new Error("Missing bridge factory");
  const colors: Record<string, number> = { text: 97, accent: 36, muted: 37, dim: 90, success: 32, warning: 33, error: 31 };
  factory(h.tui as unknown as TUI, {
    fg: (color, text) => `\x1b[${colors[color]}m${text}\x1b[39m`,
    bold: text => `\x1b[1m${text}\x1b[22m`,
  });
}

function filledLabels(h: ReturnType<typeof harness>): string[] {
  return plain(h.workspace.renderSidebar(160)).split("\n").filter(line => line.includes("●")).map(line => line.slice(line.indexOf("●") + 2));
}

describe("AgentWorkspace", () => {
  it("keeps selection precedence over lifecycle glyphs for Main, workflows, previews and agents", () => {
    const statuses = ["running", "queued", "completed", "error", "stopped", "steered", "aborted"] as const;
    const tasks = (["running", "completed"] as const).map(status => {
      const task = createWorkflowTask({ id: `circles-${status}`, script: "", meta: { name: status } });
      task.status = status;
      return task;
    });
    updateWorkflowProgressBatch(tasks[0], [
      { type: "workflow_agent", index: 0, label: "Recorded queued", state: "start", queuedAt: Date.now() },
      { type: "workflow_agent", index: 1, label: "Recorded failed", state: "error" },
    ]);
    const records = statuses.map(status => record({ id: status, handle: status, status, description: `Assignment ${status}` }));
    const h = harness(160, records, tasks);
    try {
      styleSidebar(h);
      h.workspace.selectSidebarLine(h.workspace.renderSidebar(160).findIndex(line => line.includes("Finished")));
      const labels = ["Main", "Workflow running", "Workflow completed", "Recorded queued", "Recorded failed", ...statuses.map(status => `@${status}`)];
      const initial = h.workspace.renderSidebar(160);
      expect(filledLabels(h)).toEqual(["Main"]);
      const glyphs = new Map([
        ["Main", "○"], ["Workflow running", "◐"], ["Workflow completed", "✓"],
        ["Recorded queued", "◐"], ["Recorded failed", "○"],
        ...statuses.map(status => [`@${status}`, status === "completed" ? "✓" : status === "running" || status === "queued" ? "◐" : "○"]),
      ]);
      for (const label of labels) {
        const row = initial.find(line => stripTerminalSequences(line).endsWith(label));
        expect(plain([row!])).toContain(`${label === "Main" ? "●" : glyphs.get(label)} ${label}`);
      }
      expect(plain(initial)).toContain("queued · recorded preview");
      expect(plain(initial)).toContain("failed · recorded preview");
      for (const status of statuses) expect(plain(initial)).toContain(`${status} ·`);
      for (const label of labels) {
        const before = h.workspace.renderSidebar(160);
        const row = before.findIndex(line => stripTerminalSequences(line).endsWith(label));
        expect(row).toBeGreaterThan(0);
        expect(h.workspace.selectSidebarLine(row)).toBe(true);
        const after = h.workspace.renderSidebar(160);
        expect(after).toHaveLength(initial.length);
        expect(filledLabels(h)).toEqual([label]);
        for (const other of labels) {
          const otherRow = after.find(line => stripTerminalSequences(line).endsWith(other));
          expect(plain([otherRow!])).toContain(`${other === label ? "●" : glyphs.get(other)} ${other}`);
        }
        expect(after[row]).toContain(`\x1b[97m\x1b[1m${label}\x1b[22m\x1b[39m`);
        expect(after[row]).toContain("\x1b[36m●\x1b[39m");
      }
      expect(h.manager.steer).not.toHaveBeenCalled();
      expect(h.manager.abort).not.toHaveBeenCalled();
    } finally { h.workspace.dispose(); }
  });

  it("keeps the active circle and bright label on the viewed identity while the tree cursor moves until Enter", () => {
    const h = harness(160, [record({}), record({ id: "other", handle: "other", status: "queued" })]);
    try {
      styleSidebar(h);
      h.setEditorText("Main draft");
      h.workspace.focusTree(); h.input(DOWN);
      expect(cursorRow(h)).toContain("◐ @general-purpose");
      expect(filledLabels(h)).toEqual(["Main"]);
      expect(h.workspace.renderSidebar(160)[2]).toContain("\x1b[37m@general-purpose\x1b[39m");
      expect(h.workspace.steerTarget()).toEqual({ kind: "main" });
      expect(h.editorText()).toBe("Main draft");
      h.input(ENTER);
      expect(filledLabels(h)).toEqual(["@general-purpose"]);
      expect(h.workspace.renderSidebar(160)[1]).toContain("\x1b[37m\x1b[1mMain");
      expect(h.workspace.steerTarget()).toMatchObject({ kind: "agent", id: "top" });
      h.setEditorText("agent draft"); h.workspace.focusTree(); h.input(DOWN);
      expect(cursorRow(h)).toContain("◐ @other");
      expect(filledLabels(h)).toEqual(["@general-purpose"]);
      expect(h.workspace.renderSidebar(160)[2]).toContain("\x1b[97m\x1b[1m@general-purpose");
      expect(h.workspace.renderSidebar(160)[4]).toContain("\x1b[37m@other\x1b[39m");
      expect(h.workspace.steerTarget()).toMatchObject({ kind: "agent", id: "top" });
      expect(h.editorText()).toBe("agent draft");
      h.input(ENTER);
      expect(filledLabels(h)).toEqual(["@other"]);
      expect(h.workspace.steerTarget()).toMatchObject({ kind: "agent", id: "other" });
      expect(h.editorText()).toBe("");
      h.workspace.selectMain();
      expect(filledLabels(h)).toEqual(["Main"]);
      expect(h.editorText()).toBe("Main draft");
    } finally { h.workspace.dispose(); }
  });

  it.each(["running", "completed"] as const)("distinguishes %s workflow headers, compact stages and inactive agent rows", status => {
    const task = createWorkflowTask({ id: "hierarchy", script: "", meta: { name: "Release", phases: [{ title: "Plan" }, { title: "Build" }, { title: "Verify" }] } });
    updateWorkflowProgressBatch(task, [
      { type: "workflow_phase", index: 0, title: "Plan" },
      { type: "workflow_agent", index: 0, label: "Saved planner", state: "done", phaseIndex: 0 },
      { type: "workflow_phase", index: 1, title: "Build" },
      { type: "workflow_agent", index: 1, label: "Build worker", state: status === "running" ? "start" : "done", phaseIndex: 1, recordId: "builder" },
    ]);
    task.status = status;
    const h = harness(160, [record({ id: "builder", workflowId: task.id, status })], [task]);
    try {
      styleSidebar(h);
      if (status === "completed") h.workspace.selectSidebarLine(2); // Finished expands, not the workflow.
      let lines = h.workspace.renderSidebar(100);
      const root = lines.findIndex(line => line.includes("Workflow Release"));
      expect(lines[root]).toContain(`▾ ${status === "running" ? "\x1b[36m◐" : "\x1b[32m✓"}\x1b[39m \x1b[36m\x1b[1mWorkflow Release\x1b[22m\x1b[39m`);
      expect(lines[root]).not.toMatch(/[›●]/); // Header weight is independent of selection/status.
      expect(lines[root + 1]).toContain(`${status} · ${task.doneCount}/2 agents`);
      expect(lines[root + 1]).toContain("\x1b[90m");
      expect(lines[1]).toContain("\x1b[1mMain\x1b[22m");
      expect(lines[1]).toContain("\x1b[36m●\x1b[39m");
      expect(filledLabels(h)).toEqual(["Main"]);
      if (status === "completed") {
        expect(lines[2]).toContain("\x1b[1m▾ Finished (1)\x1b[22m");
        expect(lines[2]).not.toContain("\x1b[36m");
      }
      const plan = lines.findIndex(line => line.includes("Plan"));
      expect(lines[plan]).toContain("\x1b[37m▾ Plan\x1b[39m\x1b[90m · 1/1\x1b[39m");
      expect(lines[plan]).not.toMatch(/[○✓●]|\x1b\[1m/);
      expect(lines[plan + 1]).toContain("\x1b[32m✓\x1b[39m \x1b[37mSaved planner\x1b[39m");
      expect(lines[plan + 1]).not.toContain("\x1b[1m");
      expect(lines[plan + 2]).toContain("done · recorded preview");
      expect(lines.find(line => line.includes("Verify"))).toContain("\x1b[37mVerify\x1b[39m\x1b[90m · 0/0\x1b[39m");
      expect(lines.join("\n")).not.toMatch(/@Saved planner|@Build worker/);

      const agent = lines.findIndex(line => line.includes("Build worker"));
      h.workspace.selectSidebarLine(agent + 1); // Secondary agent line remains selectable.
      lines = h.workspace.renderSidebar(100);
      expect(lines[agent]).toContain("\x1b[1m\x1b[36m›\x1b[39m\x1b[22m");
      expect(lines[agent]).toContain("\x1b[36m●\x1b[39m \x1b[97m\x1b[1mBuild worker");
      expect(filledLabels(h)).toEqual(["Build worker"]);
      expect(lines[root]).toContain("\x1b[36m\x1b[1mWorkflow Release");
      h.workspace.focusTree(); h.input(UP); // The Build stage, not another workflow header.
      const stage = h.workspace.renderSidebar(100).find(line => line.includes("Build\x1b"));
      expect(stage).toContain("\x1b[1m\x1b[36m›\x1b[39m\x1b[22m");
      expect(stage).toContain("\x1b[37m▾ Build\x1b[39m");
      expect(stage?.match(/\x1b\[1m/g)).toHaveLength(1); // A cursor stage stays quieter than its workflow.
      expect(stage).not.toMatch(/[○●]/);
      expect(filledLabels(h)).toEqual(["Build worker"]);
      h.input(ENTER); // A stage opens its owning workflow, not a new identity.
      expect(filledLabels(h)).toEqual(["Workflow Release"]);

      h.workspace.selectSidebarLine(root);
      h.workspace.focusTree(); h.input(LEFT);
      lines = h.workspace.renderSidebar(100);
      expect(lines[root]).toContain("▸ \x1b[36m●\x1b[39m \x1b[97m\x1b[1mWorkflow Release");
      expect(lines[root + 1]).toContain(`${status} · ${task.doneCount}/2 agents`);
      expect(lines.join("\n")).not.toContain("Saved planner");
      h.input(RIGHT);
      expect(h.workspace.renderSidebar(100).join("\n")).toContain("Saved planner");
    } finally { h.workspace.dispose(); }
  });

  it("keeps mixed sidebar rows width-safe and strips raw label controls without changing their data", () => {
    const unsafe = "界\x1b[31mRED\x1b[0m\nline\tend\x07\x00\x7f\x9b";
    const task = createWorkflowTask({ id: "safe-labels", script: "", meta: { name: unsafe, phases: [{ title: unsafe }, { title: "Next" }] } });
    updateWorkflowProgressBatch(task, [
      { type: "workflow_phase", index: 0, title: unsafe },
      { type: "workflow_agent", index: 0, label: unsafe, state: "done", phaseIndex: 0, recordId: "safe-child" },
    ]);
    const child = record({ id: "safe-child", workflowId: task.id, description: unsafe, status: "completed" });
    const h = harness(80, [child], [task]);
    try {
      styleSidebar(h);
      h.workspace.focusTree();
      const height = h.workspace.renderSidebar(160).length;
      for (const width of [0, 1, 2, 3, 8, 16, 24, 38, 80, 160]) {
        const lines = h.workspace.renderSidebar(width);
        expect(lines).toHaveLength(height); // No wrapping or width-dependent hit geometry.
        for (const line of lines) {
          expect(visibleWidth(line)).toBeLessThanOrEqual(width);
          expect(stripTerminalSequences(line)).not.toMatch(/[\x00-\x1f\x7f-\x9f]/);
          expect(line).not.toContain("\x1b[31m"); // Raw name color cannot escape into the theme.
        }
      }
      expect(stripTerminalSequences(h.workspace.renderSidebar(160).join("\n"))).toContain("界RED line end");
      expect(task.workflowName).toBe(unsafe);
      expect(task.meta?.phases?.[0].title).toBe(unsafe);
      expect(child.description).toBe(unsafe);
    } finally { h.workspace.dispose(); }
  });

  it.each(["agent", "workflow"] as const)("routes configured native shortcuts only to viewed %s Activity, leaving Main, metadata and modal input alone", target => {
    const previous = getKeybindings();
    const bindings = new KeybindingsManager({
      "app.tools.expand": { defaultKeys: "ctrl+o" },
      "app.thinking.toggle": { defaultKeys: "ctrl+t" },
    }, { "app.tools.expand": "ctrl+e", "app.thinking.toggle": "ctrl+g" });
    setKeybindings(bindings);
    const child = record({});
    child.session!.settingsManager.setHideThinkingBlock(true);
    const assistant = child.session!.messages.find(message => message.role === "assistant")!;
    if (assistant.role !== "assistant") throw new Error("Missing assistant fixture");
    assistant.content.unshift({ type: "thinking", thinking: "child private reasoning" });
    const task = createWorkflowTask({ id: "native-keys", script: "", meta: { name: "Native keys" } });
    updateWorkflowProgressBatch(task, [{ type: "workflow_agent", index: 0, label: "Native child", state: "start", recordId: child.id }]);
    if (target === "workflow") child.workflowId = task.id;
    const h = harness(160, [child], target === "workflow" ? [task] : []);
    const keys = ["\x05", "\x07"];
    try {
      for (const key of keys) expect(h.input(key)).toBeUndefined(); // Main owns its bindings.
      h.input(RIGHT);
      if (target === "workflow") {
        for (const key of keys) expect(h.input(key)).toBeUndefined(); // Overview.
        h.input("\t");
      }
      let scroll = selectedContent(h.tui) as ScrollView;
      const body = () => stripTerminalSequences(scroll.render(100).join("\n"));
      expect(body()).toContain("[activity]");
      expect(body()).not.toContain("result text");
      expect(body()).not.toContain("child private reasoning");
      expect(h.input("\x0f")).toBeUndefined(); // Old defaults must not be hard-coded.
      expect(h.input("\x14")).toBeUndefined();
      expect(h.input(keys[0])?.consume).toBe(true);
      expect(body()).toContain("result text");
      expect(h.input(keys[1])?.consume).toBe(true);
      expect(body()).toContain("child private reasoning");
      expect(child.session!.settingsManager.getHideThinkingBlock()).toBe(true);
      expect(h.workspace.renderBridge(160)).toEqual([]);

      h.tui.focusedComponent = new Text("selector", 0, 0);
      for (const key of keys) expect(h.input(key)).toBeUndefined();
      h.tui.focusedComponent = scroll;
      h.tui.hasOverlay = () => true;
      for (const key of keys) expect(h.input(key)).toBeUndefined();
      h.tui.hasOverlay = () => false;
      for (const tab of target === "agent" ? ["details", "context"] : ["results", "details", "overview"]) {
        expect(h.input(RIGHT)?.consume).toBe(true);
        scroll = selectedContent(h.tui) as ScrollView;
        expect(body()).toContain(`[${tab}]`);
        for (const key of keys) expect(h.input(key)).toBeUndefined();
      }
      h.input(target === "workflow" ? "\t" : RIGHT);
      scroll = selectedContent(h.tui) as ScrollView;
      expect(body()).toContain("[activity]");
      for (const key of keys) expect(h.input(key)?.consume).toBe(true);
      expect(body()).not.toContain("result text");
      expect(body()).not.toContain("child private reasoning");
      h.workspace.selectMain();
      for (const key of keys) expect(h.input(key)).toBeUndefined();
      expect(selectedContent(h.tui)).toBe(h.nativeTranscript);
      expect(h.manager.steer).not.toHaveBeenCalled();
      expect(h.manager.abort).not.toHaveBeenCalled();
    } finally { h.workspace.dispose(); setKeybindings(previous); }
  });
  it("removes idle help and Main placeholder rows without losing routing or stop confirmation", () => {
    const h = harness();
    expect(h.workspace.renderBridge(160)).toEqual([]);
    const lines = h.workspace.renderSidebar(160);
    expect(lines).toHaveLength(4); // Heading, Main, agent, useful activity detail.
    expect(lines.join("\n")).not.toMatch(/F6 focus|native transcript|Main keeps|empty prompt/);
    expect(h.workspace.selectSidebarLine(0)).toBe(false);
    expect(h.workspace.selectSidebarLine(-1)).toBe(false);
    expect(h.workspace.selectSidebarLine(4)).toBe(false);
    expect(h.workspace.selectSidebarLine(3)).toBe(true); // Detail opens its agent.
    expect(selectedContent(h.tui)).not.toBe(h.nativeTranscript);
    expect(h.workspace.renderBridge(160)).toEqual([]); // No persistent routing/help row while viewing.
    expect(h.workspace.composerPlaceholder()).toBe("Steer @general-purpose");
    h.input("\x1b[20~");
    expect(h.workspace.renderBridge(160).join("\n")).toContain("Press stop again to STOP");
    expect(h.workspace.renderBridge(160).join("\n")).not.toMatch(/F[4-9]\b/);
    h.input("x");
    expect(h.workspace.renderBridge(160)).toEqual([]);
    h.workspace.selectSidebarLine(1);
    expect(selectedContent(h.tui)).toBe(h.nativeTranscript);
    expect(h.workspace.renderBridge(160)).toEqual([]);
    h.workspace.dispose();
  });

  it("maps compact Finished rows and nested labels to the correct selection", () => {
    const h = harness(160, [record({}), record({ id: "done", status: "completed", completedAt: Date.now() })]);
    let lines = h.workspace.renderSidebar(100);
    expect(h.workspace.selectSidebarLine(lines.findIndex(line => line.includes("Finished (1)")))).toBe(true);
    lines = h.workspace.renderSidebar(100);
    const finishedDetail = lines.findIndex(line => line.includes("completed"));
    expect(h.workspace.selectSidebarLine(finishedDetail)).toBe(true);
    expect(h.workspace.renderBridge(160)).toEqual([]);
    expect(h.workspace.composerPlaceholder()).toBe("@general-purpose it has completed · select Main");
    expect(h.workspace.steerTarget()).toEqual({ kind: "unavailable", id: "done", label: "@general-purpose", reason: "it has completed" });
    h.workspace.dispose();
  });

  it("invalidates cached workflow colors when the stable theme proxy changes", () => {
    const task = createWorkflowTask({ id: "wf_theme", script: "", meta: { name: "theme-test" } });
    task.value = "A result";
    const h = harness(160, [], [task]);
    h.input("\x1b[C");
    const scroll = selectedContent(h.tui) as ScrollView;
    const resultLine = () => scroll.render(100).find(line => line.includes("Result available"));
    expect(resultLine()).toBe("Result available · open results");
    h.setThemeColor("\x1b[35m");
    expect(resultLine()).toBe("Result available · open results");
    h.bridge?.invalidate();
    expect(resultLine()).toContain("\x1b[35mResult available");
    expect(selectedContent(h.tui)).toBe(scroll);
    h.workspace.dispose();
  });

  it("opens workflow tabs at the top, retains their separate scroll positions, and returns with arrows", () => {
    const task = createWorkflowTask({ id: "wf_test", script: "", meta: { name: "workflow-test", description: "Test workflow" } });
    task.value = "line\n".repeat(50);
    const h = harness(160, [], [task]);
    h.input("\x1b[C");
    const overview = selectedContent(h.tui) as ScrollView;
    expect(overview.render(100).join("\n")).toContain("[overview]");
    expect(overview.isFollowingEnd).toBe(false);
    h.input("\x1b[18~"); // Activity
    h.input("\x1b[18~"); // Results
    const results = selectedContent(h.tui) as ScrollView;
    expect(results.render(100).join("\n")).toContain("[results]");
    results.updateLayout(100, 5, () => {});
    results.scrollTo(8, { disableFollow: true });
    h.workspace.selectMain(); h.input("\x1b[C");
    expect(selectedContent(h.tui)).toBe(results);
    expect(results.scrollTop).toBe(8);
    h.input("\x1b[18~"); // Details
    h.input("\x1b[18~"); // Overview
    expect(selectedContent(h.tui)).toBe(overview);
    expect(overview.scrollTop).toBe(0);
    h.workspace.dispose();
  });

  it("keeps evicted workflow agents inspectable, then upgrades a queued preview to its live record", () => {
    const task = createWorkflowTask({ id: "wf_test", script: "", meta: { name: "workflow-test" } });
    const saved = { type: "workflow_agent" as const, index: 0, label: "saved-worker", state: "done" as const, promptPreview: "Recorded assignment", resultPreview: "Recorded result", recordId: "old" };
    updateWorkflowProgressBatch(task, [saved]);
    const records: AgentRecord[] = [];
    const h = harness(160, records, [task]);
    h.input("\x1b[C"); // Workflow
    h.input(ESCAPE); h.input(DOWN); h.input(ENTER); // Saved agent
    const preview = selectedContent(h.tui) as ScrollView;
    expect(preview.render(100).join("\n")).toContain("Recorded result");
    expect(filledLabels(h)).toEqual(["saved-worker"]);
    h.input("\x1b[19~"); h.input("\x1b[20~");
    expect(h.manager.steer).not.toHaveBeenCalled();
    expect(h.manager.abort).not.toHaveBeenCalled();
    h.workspace.selectMain(); h.input("\x1b[C");
    expect(selectedContent(h.tui)).toBe(preview);
    records.push(record({ id: "old", workflowId: task.id }));
    h.workspace.refresh();
    expect(selectedContent(h.tui)).not.toBe(preview);
    expect(h.workspace.steerTarget()).toEqual({ kind: "agent", id: "old", label: "saved-worker" });
    expect(h.workspace.composerPlaceholder()).toBe("Steer saved-worker");
    expect(h.workspace.renderSidebar(100).join("\n").match(/saved-worker/g)).toHaveLength(1);
    expect(filledLabels(h)).toEqual(["saved-worker"]);
    records.length = 0; h.workspace.refresh(); // The same record's preview keeps its circle.
    expect(filledLabels(h)).toEqual(["saved-worker"]);
    expect(h.workspace.steerTarget()).toMatchObject({ kind: "unavailable", id: "old" });
    h.workspace.dispose();
  });

  it("returns explicitly to Main and retains the last agent's tab and scroll", () => {
    const h = harness();
    expect(h.input("\x1b[C")?.consume).toBe(true);
    const activity = selectedContent(h.tui) as ScrollView;
    expect(activity).not.toBe(h.nativeTranscript);
    h.input("\x1b[18~"); // Details
    const child = selectedContent(h.tui) as ScrollView;
    expect(child).not.toBe(activity);
    child.updateLayout(40, 5, () => {});
    child.scrollTo(3, { disableFollow: true });

    expect(h.workspace.selectMain()).toBe(true);
    expect(selectedContent(h.tui)).toBe(h.nativeTranscript);
    expect(h.input("\x1b[D")).toBeUndefined();
    expect(h.input("\x1b[C")?.consume).toBe(true);
    expect(selectedContent(h.tui)).toBe(child);
    expect(child.scrollTop).toBe(3);
    expect(child.isFollowingEnd).toBe(false);
    expect(child.render(100).join("\n")).toContain("[details]");
    expect(h.manager.steer).not.toHaveBeenCalled();
    expect(h.manager.abort).not.toHaveBeenCalled();
    h.workspace.dispose();
  });

  it.each([80, 160])("opens tree rows with Right and returns to Main with Left at %i columns", columns => {
    const h = harness(columns, [record({}), record({ id: "child", parentAgentId: "top", handle: undefined })]);
    h.input("\x1b[C"); // First agent
    h.input(ESCAPE); // Tree, focused on that agent
    h.input("\x1b[B"); // Nested child
    expect(h.input("\x1b[C")?.consume).toBe(true);
    expect(h.workspace.steerTarget()).toMatchObject({ kind: "agent", id: "child" });
    h.input(ESCAPE); // Open tree/drawer again, cursor on the nested child
    expect(h.input("\x1b[D")?.consume).toBe(true); // Climb to the parent row
    expect(markedRow(h)).toContain("@general-purpose");
    expect(selectedContent(h.tui)).not.toBe(h.nativeTranscript);
    expect(h.input("\x1b[D")?.consume).toBe(true); // Collapse the parent
    expect(plain(h.workspace.renderSidebar(60))).not.toContain("general-purpose:child");
    expect(h.input("\x1b[D")?.consume).toBe(true); // Depth 0: back to Main
    expect(selectedContent(h.tui)).toBe(h.nativeTranscript);
    const entries = node(node(h.tui.layoutRoot).entries[0].component).entries;
    if (columns < 120) {
      expect(entries[0].visible?.({ width: columns, height: 40 })).toBe(true);
      expect(entries[1].visible?.({ width: columns, height: 40 })).toBe(false);
    }
    h.workspace.dispose();
  });

  it.each(["draft", " ", "line 1\nline 2"])("preserves both arrows in a non-empty draft: %j", draft => {
    const h = harness();
    h.workspace.selectSidebarLine(2);
    const child = selectedContent(h.tui);
    vi.mocked(h.ui.getEditorText).mockReturnValue(draft);
    for (const key of ["\x1b[D", "\x1b[C", "\x1b[1;5D", "\x1b[1;5C"]) expect(h.input(key)).toBeUndefined();
    expect(selectedContent(h.tui)).toBe(child);
    h.workspace.focusTree(); // Deliberate navigation also works with retained drafts.
    expect(h.input(ENTER)?.consume).toBe(true);
    expect(h.input(RIGHT)?.consume).toBe(true);
    expect(h.ui.getEditorText()).toBe(draft);
    h.workspace.dispose();
  });

  it("leaves modified arrows and another component's arrow keys alone", () => {
    const h = harness();
    for (const key of ["\x1b[1;5D", "\x1b[1;5C", "\x1b[1;2D", "\x1b[1;2C"]) expect(h.input(key)).toBeUndefined();
    h.tui.focusedComponent = { handleInput: () => {} };
    expect(h.input("\x1b[D")).toBeUndefined();
    expect(h.input("\x1b[C")).toBeUndefined();
    expect(selectedContent(h.tui)).toBe(h.nativeTranscript);
    h.workspace.dispose();
  });

  it("returns to a retained finished agent, but never to an evicted agent", () => {
    const records = [record({})];
    const h = harness(160, records);
    h.input("\x1b[C");
    const first = selectedContent(h.tui);
    h.workspace.selectMain();
    records[0].status = "completed";
    h.input("\x1b[C");
    expect(selectedContent(h.tui)).toBe(first);
    h.workspace.selectMain();
    records.splice(0, 1, record({ id: "replacement", handle: "replacement" }));
    h.workspace.refresh();
    h.input("\x1b[C");
    expect(selectedContent(h.tui)).not.toBe(first);
    expect(h.workspace.steerTarget()).toMatchObject({ kind: "agent", id: "replacement", label: "@replacement" });
    h.workspace.dispose();
  });

  it("shows the tree when Right has no agent to open", () => {
    const h = harness(80, []);
    expect(h.input("\x1b[C")?.consume).toBe(true);
    expect(h.workspace.renderSidebar(80).join("\n")).toContain("›");
    expect(h.workspace.renderSidebar(80).join("\n")).not.toContain("→/Enter open");
    expect(h.input("\x1b[D")?.consume).toBe(true);
    expect(selectedContent(h.tui)).toBe(h.nativeTranscript);
    h.workspace.dispose();
  });

  it("does not schedule frames from the bridge render path or rescan sidebar session usage", () => {
    const agent = record({});
    const stats = vi.spyOn(agent.session!, "getSessionStats");
    const h = harness(160, [agent]);
    h.tui.requestRender.mockClear();
    for (let i = 0; i < 30; i++) {
      h.bridge?.render(160);
      h.workspace.renderSidebar(38);
    }
    expect(h.tui.requestRender).not.toHaveBeenCalled();
    expect(stats).not.toHaveBeenCalled();
    h.workspace.dispose();
  });

  it("does not submit a pending steer after the workspace is disabled", async () => {
    const h = harness();
    let finish!: (value: string) => void;
    vi.mocked(h.ui.input).mockImplementation(() => new Promise(resolve => { finish = resolve; }));
    h.workspace.selectSidebarLine(2);
    h.input("\x1b[19~");
    h.workspace.setEnabled(false);
    finish("stale steer");
    await Promise.resolve();
    expect(h.manager.steer).not.toHaveBeenCalled();
    h.workspace.dispose();
  });

  it("renders Main, nested agents, and a collapsed Finished section with Unicode-safe widths", () => {
    const records = [
      record({ id: "top", description: "Parent 界" }),
      record({ id: "nested", handle: undefined, parentAgentId: "top", description: "Nested 子" }),
      record({ id: "done", status: "completed", completedAt: Date.now(), description: "Finished ✓" }),
    ];
    const h = harness(160, records);
    const lines = h.workspace.renderSidebar(38);
    const output = lines.join("\n");

    expect(output).toContain("Main");
    expect(output).toContain("Parent 界");
    expect(output).toContain("Nested 子");
    expect(output).toContain("Finished (1)");
    expect(output).not.toContain("Finished ✓");
    for (const line of lines) expect(visibleWidth(line)).toBeLessThanOrEqual(38);
    h.workspace.dispose();
  });

  it("selects a child without replacing Main's session/editor and restores Main", () => {
    const h = harness();
    expect(selectedContent(h.tui)).toBe(h.nativeTranscript);

    expect(h.workspace.selectSidebarLine(2)).toBe(true);
    const child = selectedContent(h.tui);
    expect(child).not.toBe(h.nativeTranscript);

    expect(h.workspace.selectSidebarLine(1)).toBe(true);
    expect(selectedContent(h.tui)).toBe(h.nativeTranscript);
    // The dock remains the host's exact object throughout; selection only swaps
    // the transcript slot in the workspace root.
    expect(node(h.tui.layoutRoot).entries[1].component).toBe(node(h.nativeRoot).entries[1].component);
    h.workspace.dispose();
  });

  it("retains each agent ScrollView and paused follow state across selection changes", () => {
    const h = harness();
    h.workspace.selectSidebarLine(2);
    const child = selectedContent(h.tui) as ScrollView;
    child.updateLayout(30, 5, () => {});
    child.scrollTo(3, { disableFollow: true });
    expect(child.isFollowingEnd).toBe(false);

    h.workspace.selectSidebarLine(1);
    h.workspace.selectSidebarLine(2);

    expect(selectedContent(h.tui)).toBe(child);
    expect(child.scrollTop).toBe(3);
    expect(child.isFollowingEnd).toBe(false);
    h.workspace.dispose();
  });

  it.each([true, false])("keeps native Activity follow/history unchanged across static metadata tabs (following=%s)", following => {
    const h = harness();
    try {
      h.input(RIGHT);
      const activity = selectedContent(h.tui) as ScrollView;
      activity.updateLayout(60, 8, () => {});
      if (!following) activity.scrollTo(3, { disableFollow: true });
      const top = activity.scrollTop;
      expect(activity.followEnd).toBe(true);
      expect(activity.isFollowingEnd).toBe(following);
      h.input(RIGHT);
      const metadata = selectedContent(h.tui) as ScrollView;
      expect(metadata).not.toBe(activity);
      expect(metadata.followEnd).toBe(false);
      metadata.updateLayout(40, 8, () => {});
      metadata.scrollTo(4);
      h.input(RIGHT);
      expect(selectedContent(h.tui)).toBe(metadata);
      expect(metadata.render(100).join("\n")).toContain("[context]");
      expect(metadata.scrollTop).toBe(0);
      expect(metadata.followEnd).toBe(false);
      expect(activity.scrollTop).toBe(top);
      expect(activity.isFollowingEnd).toBe(following);
      h.input(RIGHT);
      expect(selectedContent(h.tui)).toBe(activity);
      expect(activity.render(100).join("\n")).toContain("[activity]");
      expect(activity.scrollTop).toBe(top);
      expect(activity.isFollowingEnd).toBe(following);
    } finally { h.workspace.dispose(); }
  });

  it("preserves editor keys and uses F8/F9 only against the explicitly selected target", async () => {
    const h = harness();
    h.workspace.selectSidebarLine(2);

    expect(h.input("x")).toBeUndefined();
    expect(h.input("1")).toBeUndefined();
    expect(h.input("\r")).toBeUndefined();
    expect(h.manager.steer).not.toHaveBeenCalled();
    expect(h.manager.abort).not.toHaveBeenCalled();

    expect(h.input("\x1b[19~")?.consume).toBe(true); // F8
    await vi.waitFor(() => expect(h.manager.steer).toHaveBeenCalledWith("top", "go left"));

    expect(h.input("\x1b[20~")?.consume).toBe(true); // F9
    expect(h.manager.abort).not.toHaveBeenCalled();
    expect(h.workspace.renderBridge(100).join("\n")).toContain("Press stop again to STOP @general-purpose");
    expect(h.input("\x1b[20~")?.consume).toBe(true);
    expect(h.manager.abort).toHaveBeenCalledTimes(1);
    expect(h.manager.abort).toHaveBeenCalledWith("top");
    h.workspace.dispose();
  });

  it("opens the full-width narrow drawer with F6 and closes it after selection", () => {
    const h = harness(80);
    h.input("\x1b[17~");
    let entries = node(node(h.tui.layoutRoot).entries[0].component).entries;
    expect(entries[0].visible?.({ width: 80, height: 40 })).toBe(false);
    expect(entries[1].visible?.({ width: 80, height: 40 })).toBe(true);

    h.input("\x1b[B");
    h.input("\r");
    entries = node(node(h.tui.layoutRoot).entries[0].component).entries;
    expect(entries[0].visible?.({ width: 80, height: 40 })).toBe(true);
    expect(entries[1].visible?.({ width: 80, height: 40 })).toBe(false);
    h.workspace.dispose();
  });

  it("returns with Escape to navigate workflow stages without F6", () => {
    const task = createWorkflowTask({ id: "wf_nav", script: "", meta: { name: "nav", phases: [{ title: "Plan" }, { title: "Build" }] } });
    updateWorkflowProgressBatch(task, [
      { type: "workflow_phase", index: 0, title: "Plan" },
      { type: "workflow_agent", index: 0, label: "planner", state: "done", phaseIndex: 0, phaseTitle: "Plan", recordId: "planner" },
      { type: "workflow_phase", index: 1, title: "Build" },
      { type: "workflow_agent", index: 1, label: "builder", state: "start", phaseIndex: 1, phaseTitle: "Build", recordId: "builder" },
    ]);
    const records = [
      record({ id: "planner", handle: "planner", workflowId: task.id, status: "completed", completedAt: Date.now() }),
      record({ id: "builder", handle: "builder", workflowId: task.id }),
    ];
    const h = harness(160, records, [task]);
    expect(h.input(RIGHT)?.consume).toBe(true); // Workflow overview
    expect(h.workspace.renderBridge(160)).toEqual([]);
    expect(h.workspace.composerPlaceholder()).toBe("Workflow select an agent to steer · select Main");
    expect(h.input(ESCAPE)?.consume).toBe(true);
    expect(h.input(DOWN)?.consume).toBe(true); // Move to the first stage
    expect(cursorRow(h)).toContain("Plan");
    h.input(DOWN);
    expect(cursorRow(h)).toContain("planner");
    h.input(DOWN);
    expect(cursorRow(h)).toContain("Build");
    expect(h.input(LEFT)?.consume).toBe(true); // Collapse the Build stage
    expect(plain(h.workspace.renderSidebar(60))).not.toContain("builder");
    h.input(RIGHT); // Expand it again
    h.input(DOWN);
    expect(cursorRow(h)).toContain("builder");
    expect(h.input(ENTER)?.consume).toBe(true); // Open the live agent in the main pane
    expect(h.workspace.steerTarget()).toEqual({ kind: "agent", id: "builder", label: "builder" });
    expect(selectedContent(h.tui)).not.toBe(h.nativeTranscript);
    expect(cursorRow(h)).toBeUndefined(); // Cursor hides once a row is opened
    expect(h.manager.steer).not.toHaveBeenCalled();
    h.workspace.dispose();
  });

  it("keeps the cursor on the same agent when a preview row upgrades to its live record", () => {
    const task = createWorkflowTask({ id: "wf_live", script: "", meta: { name: "live" } });
    updateWorkflowProgressBatch(task, [
      { type: "workflow_agent", index: 0, label: "first", state: "done", recordId: "gone" },
      { type: "workflow_agent", index: 1, label: "second", state: "start", queuedAt: Date.now(), recordId: "second" },
    ]);
    const records: AgentRecord[] = [];
    const h = harness(160, records, [task]);
    h.input(RIGHT); h.input(ESCAPE); h.input(DOWN); h.input(DOWN);
    expect(cursorRow(h)).toContain("second");
    records.push(record({ id: "second", handle: "second", workflowId: task.id }));
    h.workspace.refresh();
    expect(cursorRow(h)).toContain("second");
    h.input(UP);
    expect(cursorRow(h)).toContain("first");
    h.input(DOWN);
    h.input(ENTER);
    expect(h.workspace.steerTarget()).toEqual({ kind: "agent", id: "second", label: "second" });
    h.workspace.dispose();
  });

  it("uses Escape for the narrow tree drawer without leaving the inspected agent", () => {
    const h = harness(80, [record({}), record({ id: "other", handle: "other" })]);
    h.input(RIGHT);
    const child = selectedContent(h.tui);
    expect(h.input(DOWN)?.consume).toBe(true);
    expect(cursorRow(h)).toBeUndefined();
    expect(h.input(ESCAPE)?.consume).toBe(true);
    let entries = node(node(h.tui.layoutRoot).entries[0].component).entries;
    expect(entries[1].visible?.({ width: 80, height: 40 })).toBe(true);
    expect(cursorRow(h)).toContain("@general-purpose");
    expect(h.input(ESCAPE)?.consume).toBe(true);
    entries = node(node(h.tui.layoutRoot).entries[0].component).entries;
    expect(entries[0].visible?.({ width: 80, height: 40 })).toBe(true);
    expect(selectedContent(h.tui)).toBe(child);
    expect(h.manager.abort).not.toHaveBeenCalled();
    h.workspace.dispose();
  });

  it("hands Up/Down back to the editor once the draft has text and leaves Main history alone", () => {
    const h = harness(80, [record({}), record({ id: "other", handle: "other" })]);
    expect(h.input(UP)).toBeUndefined();
    expect(h.input(DOWN)).toBeUndefined();
    h.input(RIGHT);
    h.input(ESCAPE);
    expect(cursorRow(h)).toBeDefined();
    h.setEditorText("typing");
    expect(h.input(DOWN)).toBeUndefined();
    expect(cursorRow(h)).toBeUndefined();
    const entries = node(node(h.tui.layoutRoot).entries[0].component).entries;
    expect(entries[0].visible?.({ width: 80, height: 40 })).toBe(true); // Drawer closed for typing
    expect(h.input(ENTER)).toBeUndefined();
    h.workspace.dispose();
  });

  it("keeps separate Main and agent drafts across selection changes", () => {
    const h = harness(160, [record({}), record({ id: "other", handle: "other" })]);
    h.setEditorText("main draft");
    h.workspace.selectSidebarLine(2); // Mouse: switching with a non-empty prompt
    expect(h.editorText()).toBe("");
    h.setEditorText("for the agent");
    h.workspace.selectSidebarLine(1);
    expect(h.editorText()).toBe("main draft");
    h.workspace.selectSidebarLine(2);
    expect(h.editorText()).toBe("for the agent");
    h.workspace.selectSidebarLine(4);
    expect(h.editorText()).toBe("");
    expect(h.ui.setEditorText).toHaveBeenCalledTimes(4);
    h.workspace.dispose();
  });

  it("restores Main on disable and retains the child's draft across re-enabling", () => {
    const events = createEventBus();
    const editorView = vi.fn();
    events.on("subagents:editor-view", editorView);
    const h = harness(160, [record({})], [], events);
    h.setEditorText("saved Main draft");
    h.workspace.selectSidebarLine(2);
    h.setEditorText("unsent child draft");
    h.workspace.focusTree();
    h.workspace.setEnabled(false);
    expect(h.editorText()).toBe("saved Main draft");
    expect(h.tui.layoutRoot).toBe(h.nativeRoot);
    expect(h.workspace.steerTarget()).toEqual({ kind: "main" });
    expect(markedRow(h)).toContain("Main");
    expect(h.workspace.treeFocused).toBe(false);
    expect(editorView).toHaveBeenLastCalledWith({ version: 1, agent: null });
    editorView.mockClear();
    events.emit("subagents:editor-view:request", {});
    expect(editorView).not.toHaveBeenCalled();

    h.setEditorText("edited while off");
    h.workspace.setEnabled(true);
    h.workspace.refresh();
    expect(selectedContent(h.tui)).toBe(h.nativeTranscript);
    expect(h.workspace.steerTarget()).toEqual({ kind: "main" });
    expect(h.editorText()).toBe("edited while off");
    expect(editorView).toHaveBeenLastCalledWith({ version: 1, agent: null, placeholder: undefined });
    h.workspace.focusTree();
    expect(cursorRow(h)).toContain("Main");
    h.workspace.selectSidebarLine(2);
    expect(h.editorText()).toBe("unsent child draft");
    expect(h.workspace.steerTarget()).toMatchObject({ kind: "agent", id: "top" });
    h.workspace.selectMain();
    expect(h.editorText()).toBe("edited while off");
    h.workspace.dispose();
  });

  it.each([false, true])("restores the old UI's Main draft without replacing a new UI's draft (disabled=%s)", disabled => {
    const h = harness();
    h.setEditorText("old Main draft");
    h.workspace.selectSidebarLine(2);
    h.setEditorText("child draft");
    if (disabled) h.workspace.setEnabled(false);
    let editorText = "new UI Main draft";
    const nextUI = {
      ...h.ui,
      setWidget: vi.fn(h.ui.setWidget),
      getEditorText: vi.fn(() => editorText),
      setEditorText: vi.fn((text: string) => { editorText = text; }),
    };
    h.workspace.setUI(nextUI);
    expect(h.editorText()).toBe("old Main draft");
    expect(nextUI.setEditorText).not.toHaveBeenCalled();
    expect(h.unsubscribe).toHaveBeenCalledOnce();
    expect(h.workspace.steerTarget()).toEqual({ kind: "main" });
    if (disabled) h.workspace.setEnabled(true);
    const factory = nextUI.setWidget.mock.calls.at(-1)?.[1];
    if (typeof factory !== "function") throw new Error("Missing bridge factory");
    factory(h.tui as unknown as TUI, { fg: (_color, text) => text, bold: text => text });
    expect(selectedContent(h.tui)).toBe(h.nativeTranscript);
    expect(h.workspace.steerTarget()).toEqual({ kind: "main" });
    h.workspace.selectSidebarLine(2);
    expect(editorText).toBe("child draft");
    h.workspace.dispose();
    expect(editorText).toBe("new UI Main draft");
    expect(h.workspace.holdDraft("cannot restore after disposal")).toBe(false);
  });

  it("keeps an evicted agent's target/draft unavailable until explicit Main selection", () => {
    const records = [record({})];
    const h = harness(160, records);
    h.setEditorText("saved Main draft");
    h.workspace.selectSidebarLine(2);
    h.setEditorText("unsent child draft");
    records.splice(0, 1);
    h.workspace.refresh();
    expect(selectedContent(h.tui)).not.toBe(h.nativeTranscript);
    expect((selectedContent(h.tui) as Text).render(160).join("\n")).toContain("no longer retained");
    expect(h.workspace.steerTarget()).toMatchObject({ kind: "unavailable", label: "top" });
    expect(h.workspace.composerPlaceholder()).toContain("no longer retained");
    expect(filledLabels(h)).toEqual([]);
    h.workspace.focusTree();
    expect(cursorRow(h)).toContain("○ Main"); // Cursor fallback is not activation.
    expect(filledLabels(h)).toEqual([]);
    expect(h.editorText()).toBe("unsent child draft");
    h.workspace.refresh();
    expect(h.workspace.steerTarget().kind).toBe("unavailable");
    expect(h.ui.notify).not.toHaveBeenCalled();
    h.workspace.selectMain();
    expect(h.editorText()).toBe("saved Main draft");
    expect(h.workspace.steerTarget()).toEqual({ kind: "main" });
    h.workspace.dispose();
  });

  it("does not retarget a removed workflow's draft during refresh", () => {
    const workflows = [createWorkflowTask({ id: "removed", script: "", meta: { name: "removed" } })];
    const h = harness(160, [], workflows);
    h.setEditorText("Main draft");
    h.workspace.selectSidebarLine(2);
    h.setEditorText("workflow draft");
    workflows.splice(0, 1);
    h.workspace.refresh();
    expect(selectedContent(h.tui)).not.toBe(h.nativeTranscript);
    expect(h.workspace.steerTarget().kind).toBe("unavailable");
    expect(h.editorText()).toBe("workflow draft");
    expect(filledLabels(h)).toEqual([]);
    h.workspace.selectMain();
    expect(filledLabels(h)).toEqual(["Main"]);
    expect(h.editorText()).toBe("Main draft");
    h.workspace.dispose();
  });

  it("holds input on workflow views/previews and routes to Main only when detached", () => {
    const task = createWorkflowTask({ id: "wf_route", script: "", meta: { name: "route" } });
    updateWorkflowProgressBatch(task, [{ type: "workflow_agent", index: 0, label: "saved", state: "done", recordId: "old" }]);
    const h = harness(160, [], [task]);
    h.input(RIGHT);
    expect(h.workspace.steerTarget()).toMatchObject({ kind: "unavailable", label: "Workflow" });
    h.input(ESCAPE); h.input(DOWN); h.input(ENTER);
    expect(h.workspace.renderBridge(160)).toEqual([]);
    expect(h.workspace.steerTarget()).toMatchObject({ kind: "unavailable", label: "Workflow" });
    h.workspace.setEnabled(false);
    expect(h.workspace.steerTarget()).toEqual({ kind: "main" });
    h.workspace.dispose();
  });

  it("holdDraft reports restoration without rewriting identical text or clobbering newer edits", () => {
    const h = harness();
    expect(h.workspace.holdDraft("kept")).toBe(true);
    expect(h.editorText()).toBe("kept");
    expect(h.ui.setEditorText).toHaveBeenCalledTimes(1);
    expect(h.workspace.holdDraft("kept")).toBe(true);
    expect(h.ui.setEditorText).toHaveBeenCalledTimes(1);
    for (const newer of ["new draft", " ", "line 1\nline 2"]) {
      h.setEditorText(newer);
      expect(h.workspace.holdDraft("kept")).toBe(false);
      expect(h.editorText()).toBe(newer);
      expect(h.ui.setEditorText).toHaveBeenCalledTimes(1);
    }
    h.workspace.dispose();
  });

  it("keeps the F6 toggle, F8 dialog steer, and click-to-open fallbacks working", async () => {
    const h = harness(160);
    expect(h.input(F6)?.consume).toBe(true);
    expect(cursorRow(h)).toContain("Main");
    expect(h.input(F6)?.consume).toBe(true);
    expect(cursorRow(h)).toBeUndefined();
    h.workspace.selectSidebarLine(2);
    expect(h.input(F8)?.consume).toBe(true);
    await vi.waitFor(() => expect(h.manager.steer).toHaveBeenCalledWith("top", "go left"));
    expect(h.input(F7)?.consume).toBe(true);
    expect(h.input(F9)?.consume).toBe(true);
    h.workspace.dispose();
  });

  it("disposes the input/timer and restores the native layout", () => {
    const h = harness();
    expect(h.tui.layoutRoot).not.toBe(h.nativeRoot);

    h.workspace.dispose();

    expect(h.tui.layoutRoot).toBe(h.nativeRoot);
    expect(h.unsubscribe).toHaveBeenCalledOnce();
    expect(h.attachment).toHaveBeenLastCalledWith(false);
  });
});

describe("WorkspaceAwareComponent", () => {
  it("hides and restores an already-mounted row without mutating its component", () => {
    let hidden = false;
    const source = new Text("payload stays", 0, 0);
    const live = new WorkspaceAwareComponent(() => hidden, source);
    const visible = live.render(80);
    expect(visible.join("\n")).toContain("payload stays");
    hidden = true;
    expect(live.render(80)).toEqual([]);
    hidden = false;
    expect(live.render(80)).toEqual(visible);
  });
});
