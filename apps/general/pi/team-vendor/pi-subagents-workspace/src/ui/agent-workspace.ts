import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
  type Component,
  decodeKittyPrintable,
  getKeybindings,
  isKeyRelease,
  Key,
  matchesKey,
  ScrollView,
  stripTerminalSequences,
  type TUI,
  truncateToWidth,
  VStack,
} from "@earendil-works/pi-tui";
import type { AgentManager } from "../agent-manager.js";
import type { AgentRecord } from "../types.js";
import { buildPhaseGroups, collapse, displayState, type WorkflowAgentEntry } from "../workflow/progress.js";
import type { WorkflowTask } from "../workflow/task.js";
import {
  type AgentActivity,
  formatDuration,
  SPINNER,
  type Theme,
} from "./agent-widget.js";
import { AgentWorkspaceDocument, type WorkspaceTab } from "./agent-workspace-document.js";
import { type WorkflowAgentRow, type WorkflowInlineActivation, workflowAgentRowLabel, workflowAgentRowMetadata, workflowAgentRows } from "./workflow-agent-rows.js";
import { WORKFLOW_WORKSPACE_TABS, WorkflowWorkspaceDocument, type WorkflowWorkspaceTab } from "./workflow-workspace-document.js";
import type { GitCommandRunner } from "./workspace-git.js";
import { createAgentScrollView, createSidebarScrollView, sidebarHeading, WORKSPACE_SIDEBAR_COLUMNS, WORKSPACE_WIDE_COLUMNS, WorkspaceLayout, WorkspaceScrollView } from "./workspace-layout.js";
import { RELOAD_MAX_DRAFTS, type ReloadDraft, validateReloadData, type WorkspaceReloadData } from "./workspace-reload-state.js";
import { type WorkspaceRootContext, WorkspaceStatus } from "./workspace-status.js";
import { WorkspaceTodos } from "./workspace-todos.js";

const BRIDGE_WIDGET_KEY = "agent-workspace-bridge";
const TICK_MS = 200;

// Display-only, session-local contract. `agent: null` restores Main metadata;
// absent agent fields mean unknown, never "inherit Main". No session objects
// or usage totals cross the bus. Zentui requests a replay after subscribing.
const EDITOR_VIEW_EVENT = "subagents:editor-view";
const EDITOR_VIEW_REQUEST_EVENT = "subagents:editor-view:request";
type EditorView = {
  version: 1;
  agent: { id: string; modelId?: string; modelName?: string; provider?: string; thinkingLevel?: string } | null;
  placeholder?: string;
};

type WorkspaceSelection = { kind: "main" } | { kind: "agent"; id: string } | { kind: "workflow"; id: string } | { kind: "workflow-agent"; id: string; index: number };

type TreeRow = {
  kind: "main" | "workflow" | "stage" | "agent" | "finished";
  key: string;
  depth: number;
  label: string;
  /** Retained identity also matches a live row's recorded preview after eviction. */
  recordId?: string;
  detail?: string;
  status?: string;
  selection?: WorkspaceSelection;
  /** Present on rows with children: whether the subtree is currently hidden. */
  collapsed?: boolean;
  /** Parent row key for Left navigation. */
  parentKey?: string;
  /** The recorded-preview key this live row replaced, so a cursor on it stays put. */
  previewKey?: string;
};

/** Where an ordinary editor submission goes while the workspace is attached. */
export type SteerTarget =
  | { kind: "main" }
  | { kind: "agent"; id: string; label: string }
  | { kind: "unavailable"; id?: string; label: string; reason: string };

export type AgentWorkspaceUI = {
  setWidget(
    key: string,
    content: undefined | ((tui: TUI, theme: Theme) => Component),
    options?: { placement?: "aboveEditor" | "belowEditor" },
  ): void;
  onTerminalInput(handler: (data: string) => { consume?: boolean; data?: string } | undefined): () => void;
  notify(message: string, type?: "info" | "warning" | "error"): void;
  input(title: string, placeholder?: string): Promise<string | undefined>;
  getEditorText(): string;
  setEditorText(text: string): void;
};

const FINISHED_KEY = "finished";
const isLiveStatus = (status: AgentRecord["status"]) => status === "running" || status === "queued";

export interface AgentWorkspaceOptions {
  manager: AgentManager;
  events?: ExtensionAPI["events"];
  activity: Map<string, AgentActivity>;
  workflows: () => readonly WorkflowTask[];
  onAttachmentChanged: (attached: boolean) => void;
  getRootContext?: () => WorkspaceRootContext | undefined;
  runGit?: GitCommandRunner;
}

function selectionKey(selection: WorkspaceSelection): string {
  return selection.kind === "main" ? "main" : `${selection.kind}:${selection.id}${selection.kind === "workflow-agent" ? `:${selection.index}` : ""}`;
}

/** Draft storage key: Main, or one bucket per inspected agent/workflow. */
function draftKey(selection: WorkspaceSelection): string {
  return selection.kind === "main" ? "main" : `${selection.kind === "workflow-agent" ? "workflow" : selection.kind}:${selection.id}`;
}

function targetName(record: AgentRecord): string {
  const named = record.alias ?? record.handle;
  if (named) return `@${named}`;
  return record.parentAgentId ? `${record.type}:${record.id.slice(0, 8)}` : `@${record.id}`;
}

function rowLabel(text: string): string {
  return stripTerminalSequences(text).replace(/[\x00-\x1f\x7f-\x9f]/g, " ");
}

/** Rendering, mouse hits and cursor scrolling share the same row geometry. */
function sidebarRowHeight(row: TreeRow): number {
  return row.kind !== "stage" && row.detail ? 2 : 1;
}

class WorkspaceSidebar implements Component {
  constructor(private workspace: AgentWorkspace) {}

  render(width: number): string[] {
    return this.workspace.renderSidebar(width);
  }

  handleMouse(event: { type: string; button: string; y: number }): { handled?: boolean; focus?: boolean } | undefined {
    if (event.type !== "click" || event.button !== "left") return undefined;
    return this.workspace.selectSidebarLine(event.y) ? { handled: true, focus: false } : undefined;
  }

  invalidate(): void {}
}

export class AgentWorkspace {
  private ui: AgentWorkspaceUI | undefined;
  private tui: TUI | undefined;
  private theme: Theme = { fg: (_color, text) => text, bold: text => text };
  private layout: WorkspaceLayout;
  private sidebar: WorkspaceSidebar;
  private sidebarScroll: ScrollView;
  private todos: WorkspaceTodos;
  private status: WorkspaceStatus;
  private lastSidebarPaint: string | undefined;
  private enabled = false;
  private attached = false;
  private inputUnsubscribe: (() => void) | undefined;
  private editorViewUnsubscribe: (() => void) | undefined;
  private lastEditorView: string | undefined;
  private timer: ReturnType<typeof setInterval> | undefined;
  private selection: WorkspaceSelection = { kind: "main" };
  private lastInspectorSelection: Exclude<WorkspaceSelection, { kind: "main" }> | undefined;
  private focus: "editor" | "tree" | "browse" | "inline" = "editor";
  private inlineAgents = new Map<string, WorkflowInlineActivation>();
  private editorDraftKey = "main";
  /** Draft at explicit navigation entry; retained text must not imply editing. */
  private navigationDraft = "";

  private get treeActive(): boolean { return this.focus === "tree"; }
  /** Cursor identity survives rows shifting under live updates; index is derived. */
  private treeKey = "main";
  private collapsed = new Set<string>([FINISHED_KEY]);
  private drafts = new Map<string, string>();
  /** Plain display projections only, never retained AgentRecords or sessions. */
  private draftViews = new Map<string, Omit<ReloadDraft, "text">>();
  private unavailableKeys = new Set<string>();
  private pendingReload: { data: WorkspaceReloadData; editor: string } | undefined;
  private blockedReload: WorkspaceReloadData | undefined;
  private reloadRestored = false;
  private tab: WorkspaceTab = "activity";
  private workflowTab: WorkflowWorkspaceTab = "overview";
  private workflowProgress = new Map<string, { version: number; length: number; agents: WorkflowAgentEntry[] }>();
  private stopArmedId: string | undefined;
  private steerDialogTargetId: string | undefined;
  private documents = new Map<string, { document: AgentWorkspaceDocument; scroll: ScrollView; metadataScroll: ScrollView }>();
  private workflowDocuments = new Map<string, { document: WorkflowWorkspaceDocument; scroll: ScrollView; inlineScroll: ScrollView; inlineView: Component }>();
  private unavailableDocument: Component = {
    render: width => [truncateToWidth(this.theme.fg("dim", "This view is no longer retained. Select Main explicitly to return; your draft is kept here."), width)],
    invalidate: () => {},
  };

  constructor(private options: AgentWorkspaceOptions) {
    this.sidebar = new WorkspaceSidebar(this);
    this.sidebarScroll = createSidebarScrollView(this.sidebar);
    this.todos = new WorkspaceTodos(options.events);
    const todoScroll = createSidebarScrollView(this.todos);
    this.status = new WorkspaceStatus({
      events: options.events, runGit: options.runGit, getRootContext: options.getRootContext,
      isVisible: () => this.attached && this.layout.isSidebarVisible,
      theme: () => this.theme, onChange: () => this.layout.requestRender(),
    });
    const gitScroll = createSidebarScrollView(this.status.gitSection);
    this.layout = new WorkspaceLayout(this.sidebarScroll, todoScroll, gitScroll);
  }

  get isAttached(): boolean {
    return this.attached;
  }

  /** True while ↑/↓/←/→/Enter/Esc drive the tree cursor instead of the editor. */
  get treeFocused(): boolean {
    return this.attached && this.treeActive;
  }

  setUI(ui: AgentWorkspaceUI): void {
    if (ui === this.ui) return;
    this.detach();
    this.unregisterUI();
    for (const { document } of this.documents.values()) document.dispose();
    for (const { document } of this.workflowDocuments.values()) document.dispose();
    this.documents.clear();
    this.workflowDocuments.clear();
    this.ui = ui;
    this.inputUnsubscribe = ui.onTerminalInput(data => this.handleInput(data));
    if (this.enabled) this.registerBridge();
  }

  setEnabled(enabled: boolean): void {
    if (enabled === this.enabled) return;
    this.enabled = enabled;
    if (!enabled) {
      this.ui?.setWidget(BRIDGE_WIDGET_KEY, undefined);
      this.detach();
      this.stopTimer();
      for (const { document } of this.documents.values()) document.dispose();
      for (const { document } of this.workflowDocuments.values()) document.dispose();
      return;
    }
    this.registerBridge();
    this.ensureTimer();
  }

  refresh(observeStatus = true): void {
    if (!this.enabled || !this.tui) return;
    const before = this.layout.attached;
    if (this.tui.mode === "fullscreen") {
      const records = this.options.manager.listAgents();
      const retained = new Set(records.map(record => record.id));
      for (const record of records) {
        if (record.status === "running" || record.status === "queued") this.agentDocument(record).document.observe();
      }
      for (const [id, cached] of this.documents) {
        if (retained.has(id)) continue;
        cached.document.dispose();
        this.documents.delete(id);
      }
      const workflows = this.options.workflows();
      for (const [key, cached] of this.workflowDocuments) {
        if (!workflows.some(task => key.startsWith(`workflow:${task.id}:`) || key.startsWith(`workflow-agent:${task.id}:`))) {
          cached.document.dispose();
          this.workflowDocuments.delete(key);
        } else cached.document.observe();
      }
    }
    const success = this.layout.sync(this.tui, this.selectedComponent());
    if (!success && before) this.setAttached(false);
    else if (success) this.setAttached(true);
    this.todos.setHost(this.attached ? this.tui : undefined);
    if (this.attached && this.pendingReload) {
      const pending = this.pendingReload;
      this.pendingReload = undefined;
      this.applyReload(pending.data, pending.editor);
    }
    this.publishEditorView();
    if (observeStatus) this.status.refresh();
    const sidebarWidth = this.tui.terminal.columns >= WORKSPACE_WIDE_COLUMNS ? WORKSPACE_SIDEBAR_COLUMNS : this.tui.terminal.columns;
    const sidebarPaint = this.renderSidebar(sidebarWidth).join("\n");
    // Live workflows still animate on the existing tick. An idle workspace
    // does not repaint merely because the status samplers checked their TTL.
    if (before !== this.attached || sidebarPaint !== this.lastSidebarPaint
      || this.options.workflows().some(task => task.status === "running" || task.status === "paused")) this.layout.requestRender();
    this.lastSidebarPaint = sidebarPaint;
  }

  dispose(): void {
    this.ui?.setWidget(BRIDGE_WIDGET_KEY, undefined);
    this.detach();
    this.stopTimer();
    this.unregisterUI();
    for (const { document } of this.documents.values()) document.dispose();
    this.documents.clear();
    for (const { document } of this.workflowDocuments.values()) document.dispose();
    this.workflowDocuments.clear();
    this.workflowProgress.clear();
    this.drafts.clear();
    this.draftViews.clear();
    this.unavailableKeys.clear();
    this.pendingReload = undefined;
    this.blockedReload = undefined;
    this.inlineAgents.clear();
    this.todos.dispose();
    this.status.dispose();
  }

  /** Capture before teardown restores Main and releases the child records. */
  captureReloadState(): WorkspaceReloadData {
    // A cap-refused recovery still owns its original bounded data. The fresh
    // editor remains Main-owned and survives teardown independently.
    const deferred = this.blockedReload ?? this.pendingReload?.data;
    if (deferred) return JSON.parse(JSON.stringify(deferred)) as WorkspaceReloadData;
    const drafts = new Map(this.drafts);
    drafts.set(this.editorDraftKey, this.ui?.getEditorText() ?? drafts.get(this.editorDraftKey) ?? "");
    if (!drafts.has("main")) drafts.set("main", "");
    const data = {
      selected: this.editorDraftKey,
      drafts: [...drafts].map(([key, text]) => ({ ...this.draftView(key), text })),
    };
    validateReloadData(data);
    return data;
  }

  /** Validation precedes mutation; attachment may be delayed by the host layout. */
  restoreReloadState(data: WorkspaceReloadData): void {
    validateReloadData(data);
    if (this.reloadRestored) return;
    this.reloadRestored = true;
    // Copy only validated plain data. Callers cannot mutate a pending replay.
    this.pendingReload = { data: JSON.parse(JSON.stringify(data)) as WorkspaceReloadData, editor: this.ui?.getEditorText() ?? "" };
    this.refresh();
  }

  private applyReload(data: WorkspaceReloadData, editor: string): void {
    const current = this.ui?.getEditorText() ?? "";
    const main = data.drafts.find(draft => draft.key === "main")!;
    // Teardown leaves Main's draft in the editor. New text must stay Main-owned
    // rather than being overwritten or retargeted by a delayed child replay.
    const changed = current !== editor || (current !== "" && current !== main.text);
    const drafts = [...data.drafts];
    if (this.editorDraftKey !== "main" || (changed && main.text !== "" && main.text !== current && drafts.length >= RELOAD_MAX_DRAFTS)) {
      this.blockedReload = data;
      this.ui?.notify("Workspace reload drafts could not be restored safely after the editor changed (128-draft limit). Existing reload data and current text were kept unchanged.", "warning");
      return;
    }
    if (changed && main.text !== "" && main.text !== current) {
      let index = 1;
      while (drafts.some(draft => draft.key === `workflow:reload-main:${index}`)) index++;
      drafts.push({ key: `workflow:reload-main:${index}`, label: "Main (before reload)", text: main.text });
    }
    for (const { text, ...view } of drafts) {
      this.drafts.set(view.key, text);
      if (view.key !== "main") {
        this.draftViews.set(view.key, view);
        this.unavailableKeys.add(view.key);
      }
    }
    if (changed) {
      this.drafts.set("main", current);
      this.ui?.notify("The editor changed during reload. Current text was left unchanged; saved drafts are available in the tree, including Main (before reload) when different.", "warning");
      return;
    }
    this.ui?.setEditorText(this.drafts.get(data.selected) ?? "");
    this.editorDraftKey = data.selected;
    if (data.selected !== "main") {
      const kind = data.selected.startsWith("agent:") ? "agent" : "workflow";
      const selection: Exclude<WorkspaceSelection, { kind: "main" }> = { kind, id: data.selected.slice(kind.length + 1) };
      this.selection = selection;
      this.lastInspectorSelection = selection;
      this.treeKey = selectionKey(this.selection);
      this.focus = "editor";
      this.layout.select(this.selectedComponent());
    }
  }

  private draftView(key: string): Omit<ReloadDraft, "text"> {
    if (this.unavailableKeys.has(key)) return this.draftViews.get(key)!;
    const record = key.startsWith("agent:") ? this.options.manager.getRecord(key.slice(6)) : undefined;
    const inline = this.inlineAgent();
    const activeInline = inline && key === this.editorDraftKey ? inline : undefined;
    const model = record?.session?.model;
    const canonical = record?.invocation?.modelId ?? activeInline?.modelId;
    const slash = canonical?.indexOf("/") ?? -1;
    const old = this.draftViews.get(key);
    const task = key.startsWith("workflow:") ? this.options.workflows().find(task => key === `workflow:${task.id}`) : undefined;
    return {
      key,
      label: rowLabel(activeInline?.label ?? (record ? this.workflowLabel(record) ?? targetName(record) : task?.workflowName ?? old?.label ?? (key === "main" ? "Main" : key))),
      modelId: model?.id ?? (slash >= 0 ? canonical?.slice(slash + 1) : canonical) ?? old?.modelId,
      modelName: model?.name ?? record?.invocation?.modelName ?? activeInline?.model ?? old?.modelName,
      provider: model?.provider ?? (slash >= 0 ? canonical?.slice(0, slash) : undefined) ?? old?.provider,
      thinkingLevel: record?.session?.thinkingLevel ?? record?.invocation?.thinking ?? activeInline?.thinking ?? old?.thinkingLevel,
    };
  }

  renderSidebar(width: number): string[] {
    const theme = this.theme;
    const rows = this.treeRows();
    const selection = this.selection;
    const selected = selectionKey(selection);
    const inline = this.inlineAgent();
    // Activation, not navigation or liveness, owns the circle. An unavailable
    // child keeps its exact identity; never substitute its workflow or planner.
    const activeRow = rows.find(row => selection.kind === "workflow" && inline
      ? row.kind === "agent" && (inline.recordId !== undefined
        ? row.recordId === inline.recordId
        : row.key === `workflow-agent:${selection.id}:${inline.callIndex}` && row.recordId === undefined)
      : row.key === selected || row.previewKey === selected || (selection.kind === "agent" && row.recordId === selection.id));
    const cursor = this.treeActive ? this.treeIndex(rows) : -1;
    const lines = [sidebarHeading(theme.bold(" Agents"), width)];
    for (let index = 0; index < rows.length; index++) {
      const row = rows[index];
      const active = row === activeRow;
      const marker = (this.treeActive ? index === cursor : active) ? theme.bold(theme.fg("accent", "›")) : " ";
      const circle = active ? theme.fg("accent", "●")
        : row.status === "completed" || row.status === "done" ? theme.fg("success", "✓")
          : row.status === "running" || row.status === "queued" || row.status === "paused" ? theme.fg("accent", "◐") : theme.fg("dim", "○");
      const indent = "  ".repeat(row.depth);
      const disclosure = row.collapsed === undefined ? "" : `${row.collapsed ? "▸" : "▾"} `;
      const label = rowLabel(row.label);
      let text: string;
      if (row.kind === "workflow") {
        text = `${marker} ${indent}${disclosure}${circle} ${theme.fg(active ? "text" : "accent", theme.bold(label))}`;
      } else if (row.kind === "stage") {
        text = `${marker} ${indent}${theme.fg("muted", `${disclosure}${label}`)}${row.detail ? theme.fg("dim", ` · ${rowLabel(row.detail)}`) : ""}`;
      } else if (row.kind === "agent") {
        const branch = row.depth > 0 ? `${"  ".repeat(row.depth - 1)}└─ ` : "";
        text = `${marker} ${branch}${disclosure}${circle} ${active ? theme.fg("text", theme.bold(label)) : theme.fg("muted", label)}`;
      } else if (row.kind === "main") {
        text = `${marker} ${circle} ${theme.fg(active ? "text" : "muted", theme.bold(label))}`;
      } else {
        text = `${marker} ${theme.bold(`${disclosure}${label}`)}`;
      }
      lines.push(text);
      if (sidebarRowHeight(row) === 2) {
        lines.push(theme.fg("dim", `  ${indent}${row.kind === "workflow" ? "  " : ""}${rowLabel(row.detail!)}`));
      }
    }
    // Reset both edges; the native compositor pads the rest of each tree row.
    return lines.map(line => `\x1b[0m${truncateToWidth(line, width)}\x1b[0m`);
  }

  selectSidebarLine(line: number): boolean {
    const rows = this.treeRows();
    let top = 1; // The single Agents heading is not selectable.
    for (let index = 0; index < rows.length; index++) {
      const height = sidebarRowHeight(rows[index]);
      if (line >= top && line < top + height) {
        this.treeKey = rows[index].key;
        this.activateTreeRow(rows[index]);
        this.layout.requestRender();
        return true;
      }
      top += height;
    }
    return false;
  }

  /**
   * Where an ordinary editor submission should go right now. `agent` names a
   * live record that the caller must steer through the manager; `unavailable`
   * means the viewed agent can no longer accept input and the submission must
   * be held rather than silently sent to Main.
   */
  steerTarget(): SteerTarget {
    if (!this.enabled || !this.attached || this.selection.kind === "main") return { kind: "main" };
    const saved = this.unavailableKeys.has(this.editorDraftKey) ? this.draftViews.get(this.editorDraftKey) : undefined;
    if (saved) return { kind: "unavailable", id: this.selection.id, label: saved.label, reason: "is unavailable after reload" };
    const inline = this.inlineAgent();
    if (inline) {
      const record = this.inlineRecord();
      if (!record) return { kind: "unavailable", id: inline.recordId, label: inline.label, reason: "it is no longer retained" };
      if (isLiveStatus(record.status)) return { kind: "agent", id: record.id, label: inline.label };
      return { kind: "unavailable", id: record.id, label: inline.label,
        reason: `it has ${record.status === "completed" ? "completed" : record.status === "error" ? "failed" : record.status}` };
    }
    if (this.selection.kind !== "agent") {
      const workflowId = this.selection.id;
      const retained = this.options.workflows().some(task => task.id === workflowId);
      return { kind: "unavailable", label: "Workflow", reason: retained ? "select an agent to steer" : "it is no longer retained" };
    }
    const record = this.options.manager.getRecord(this.selection.id);
    if (!record) return { kind: "unavailable", id: this.selection.id, label: this.selection.id, reason: "it is no longer retained" };
    const label = this.workflowLabel(record) ?? targetName(record);
    if (isLiveStatus(record.status)) return { kind: "agent", id: record.id, label };
    return { kind: "unavailable", id: record.id, label, reason: `it has ${record.status === "completed" ? "completed" : record.status === "error" ? "failed" : record.status}` };
  }

  /** Restore unsent text only into an empty editor; never replace a newer draft. */
  holdDraft(text: string): boolean {
    if (!this.ui) return false;
    const current = this.ui.getEditorText();
    if (current === text) return true;
    if (current !== "") return false;
    this.ui.setEditorText(text);
    return true;
  }

  private registerBridge(): void {
    if (!this.ui || !this.enabled) return;
    this.ui.setWidget(BRIDGE_WIDGET_KEY, (tui, theme) => {
      this.tui = tui;
      this.theme = theme;
      this.refresh(false); // Factories attach UI only; observations begin on the host tick.
      return {
        // Never request another frame from render: that creates an idle redraw
        // loop. Session events and the bounded progress timer drive updates.
        render: (width: number) => this.attached ? this.renderBridge(width) : [],
        invalidate: () => {
          this.theme = theme;
          for (const { document } of this.documents.values()) document.invalidate();
          for (const { document } of this.workflowDocuments.values()) document.invalidate();
        },
      };
    }, { placement: "aboveEditor" });
    this.ensureTimer();
  }

  private ensureTimer(): void {
    if (!this.timer) this.timer = setInterval(() => this.refresh(), TICK_MS);
  }

  private stopTimer(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = undefined;
  }

  private unregisterUI(): void {
    this.todos.setHost();
    this.inputUnsubscribe?.();
    this.inputUnsubscribe = undefined;
    this.ui = undefined;
    this.tui = undefined;
  }

  private detach(): void {
    if (this.inlineAgent()) this.layout.focusEditor();
    // Relinquishing the editor makes it Main-owned again. Save the inspector's
    // draft before restoring Main, including when setUI replaces the old UI.
    this.swapDraft({ kind: "main" });
    this.selection = { kind: "main" };
    this.treeKey = "main";
    this.todos.setHost();
    this.status.pause();
    this.lastSidebarPaint = undefined;
    this.layout.detach();
    this.setAttached(false);
    this.focus = "editor";
    this.steerDialogTargetId = undefined;
    this.stopArmedId = undefined;
  }

  private setAttached(attached: boolean): void {
    if (this.attached === attached) return;
    this.attached = attached;
    this.editorViewUnsubscribe?.();
    this.editorViewUnsubscribe = attached
      ? this.options.events?.on(EDITOR_VIEW_REQUEST_EVENT, () => this.publishEditorView(true))
      : undefined;
    this.publishEditorView(true);
    this.options.onAttachmentChanged(attached);
  }

  private selectedComponent(): Component | undefined {
    if (this.selection.kind === "main") return undefined;
    if (this.unavailableKeys.has(draftKey(this.selection))) return this.unavailableDocument;
    if (this.selection.kind === "workflow" || this.selection.kind === "workflow-agent") {
      const workflowId = this.selection.id;
      const task = this.options.workflows().find(item => item.id === workflowId);
      if (!task) return this.unavailableDocument;
      const agentIndex = this.selection.kind === "workflow-agent" ? this.selection.index : undefined;
      if (agentIndex !== undefined) {
        const entry = this.workflowAgents(task).find(agent => agent.index === agentIndex);
        const record = entry?.recordId ? this.options.manager.getRecord(entry.recordId) : undefined;
        if (record) {
          this.selection = { kind: "agent", id: record.id };
          this.lastInspectorSelection = this.selection;
          const cached = this.agentDocument(record);
          return this.tab === "activity" ? cached.scroll : cached.metadataScroll;
        }
      }
      const key = `${selectionKey(this.selection)}${agentIndex === undefined ? `:${this.workflowTab}` : ""}`;
      let cached = this.workflowDocuments.get(key);
      if (!cached) {
        const tab = this.workflowTab;
        const document = new WorkflowWorkspaceDocument({
          task,
          agentIndex,
          theme: () => this.theme,
          tab: () => tab,
          onTabChange: next => this.selectWorkflowTab(next),
          onBrowse: () => this.leaveTree(),
          onActivate: row => this.activateInlineAgent(task, row),
          records: () => this.options.manager.listAgents(),
          inlineAgent: () => this.inlineAgents.get(task.id),
          inlineRecord: () => this.inlineRecord(task.id),
          onInlineFocus: () => this.focusInline(),
          spinnerFrame: () => Math.floor(Date.now() / TICK_MS) % SPINNER.length,
          openAgent: entry => this.openWorkflowAgent(task, entry),
          openWorkflow: () => this.openSelection({ kind: "workflow", id: task.id }, false),
          tui: this.tui,
          resolveRecord: id => this.options.manager.getRecord(id),
          onChange: () => this.layout.requestRender(),
        });
        const scroll = new WorkspaceScrollView(document, { follow: "none", primary: tab !== "overview" || agentIndex !== undefined, overscroll: "contain", scrollbar: "auto" });
        const inlineScroll = createAgentScrollView(document.inlineActivity);
        const inlineView = new VStack([
          { component: scroll, basis: "auto", grow: 0, shrink: 1, minSize: 1 },
          { component: document.inlineHeader, basis: "auto", shrink: 0 },
          { component: inlineScroll, basis: 0, grow: 1, shrink: 0, minSize: 1 },
        ]);
        cached = { document, scroll, inlineScroll, inlineView };
        this.workflowDocuments.set(key, cached);
      }
      return agentIndex === undefined && this.workflowTab === "overview" && this.inlineAgents.has(task.id) ? cached.inlineView : cached.scroll;
    }
    const record = this.options.manager.getRecord(this.selection.id);
    // Eviction is not navigation. Keep the unavailable target and its draft
    // selected until the user explicitly chooses Main (and its saved draft).
    if (!record) return this.unavailableDocument;
    const cached = this.agentDocument(record);
    return this.tab === "activity" ? cached.scroll : cached.metadataScroll;
  }

  private workflowAgents(task: WorkflowTask): WorkflowAgentEntry[] {
    let cached = this.workflowProgress.get(task.id);
    if (!cached || cached.version !== task.progressVersion || cached.length !== task.workflowProgress.length) {
      cached = { version: task.progressVersion, length: task.workflowProgress.length, agents: collapse(task.workflowProgress).agents };
      this.workflowProgress.set(task.id, cached);
    }
    return cached.agents;
  }

  /** Explicit activation survives cursor movement, tab suspension, and record eviction. */
  private inlineAgent(selection = this.selection, tab = this.workflowTab): WorkflowInlineActivation | undefined {
    return selection.kind === "workflow" && tab === "overview" ? this.inlineAgents.get(selection.id) : undefined;
  }

  private inlineRecord(workflowId = this.selection.kind === "workflow" ? this.selection.id : undefined): AgentRecord | undefined {
    if (!workflowId) return undefined;
    const entry = this.inlineAgents.get(workflowId);
    const task = this.options.workflows().find(item => item.id === workflowId);
    if (!entry?.recordId || !task) return undefined;
    const records = this.options.manager.listAgents();
    const row = workflowAgentRows(this.workflowAgents(task), records).find(item => item.key === entry.key);
    if (!row || row.recordId !== entry.recordId || row.call.index !== entry.callIndex || row.call.recordId !== entry.rootRecordId) return undefined;
    const ancestors = row.kind === "descendant" ? row.ancestorIds : [];
    if (ancestors.length !== entry.ancestorIds.length || ancestors.some((id, index) => id !== entry.ancestorIds[index]
      || !records.some(record => record.id === id))) return undefined;
    return row.record;
  }

  private activateInlineAgent(task: WorkflowTask, row: WorkflowAgentRow): void {
    if (this.selection.kind !== "workflow" || this.selection.id !== task.id || this.workflowTab !== "overview") return;
    const previous = this.inlineAgents.get(task.id);
    this.inlineAgents.set(task.id, { key: row.key, recordId: row.recordId, callIndex: row.call.index,
      rootRecordId: row.call.recordId, ancestorIds: row.kind === "descendant" ? [...row.ancestorIds] : [],
      label: workflowAgentRowLabel(row), ...workflowAgentRowMetadata(row) });
    this.swapDraft(this.selection);
    this.layout.select(this.selectedComponent());
    const cached = this.workflowDocuments.get(`workflow:${task.id}:overview`);
    cached?.document.observe();
    if (previous?.recordId !== row.recordId || previous?.key !== row.key) cached?.inlineScroll.scrollToEnd();
    this.focusInline();
    this.publishEditorView();
  }

  private focusInline(): void {
    if (!this.inlineAgent()) return;
    this.focus = "inline";
    const scroll = this.workflowDocuments.get(`${selectionKey(this.selection)}:overview`)?.inlineScroll;
    if (scroll) this.tui?.setFocus(scroll);
    this.navigationDraft = this.ui?.getEditorText() ?? "";
    this.setDrawerOpen(false);
    this.layout.requestRender();
  }

  private openWorkflowAgent(task: WorkflowTask, entry: WorkflowAgentEntry): void {
    const record = entry.recordId ? this.options.manager.getRecord(entry.recordId) : undefined;
    this.tab = "activity";
    this.openSelection(record ? { kind: "agent", id: record.id } : { kind: "workflow-agent", id: task.id, index: entry.index }, false);
    this.layout.requestRender();
  }

  private workflowLabel(record: AgentRecord): string | undefined {
    const task = this.options.workflows().find(item => item.id === record.workflowId);
    if (!task) return undefined;
    const entries = this.workflowAgents(task);
    for (let index = entries.length - 1; index >= 0; index--) {
      if (entries[index].recordId === record.id) return entries[index].label;
    }
    return undefined;
  }

  private agentDocument(record: AgentRecord): { document: AgentWorkspaceDocument; scroll: ScrollView; metadataScroll: ScrollView } {
    let cached = this.documents.get(record.id);
    if (!cached) {
      const document = new AgentWorkspaceDocument(
        record,
        () => this.options.activity.get(record.id),
        () => this.tab,
        () => this.theme,
        () => this.options.workflows().find(task => task.id === record.workflowId),
        () => this.layout.requestRender(),
        () => this.workflowLabel(record),
        next => this.selectAgentTab(next),
        this.tui,
      );
      cached = {
        document,
        scroll: createAgentScrollView(document),
        metadataScroll: new WorkspaceScrollView(document, { follow: "none", primary: true, overscroll: "contain", scrollbar: "auto" }),
      };
      this.documents.set(record.id, cached);
    } else cached.document.setRecord(record);
    return cached;
  }

  /** Focus the tree without changing the selected transcript. */
  focusTree(): boolean {
    if (!this.attached) return false;
    this.focus = "tree";
    this.navigationDraft = this.ui?.getEditorText() ?? "";
    this.stopArmedId = undefined;
    if (!this.treeRows().some(row => row.key === this.treeKey)) this.treeKey = selectionKey(this.selection);
    if ((this.tui?.terminal.columns ?? WORKSPACE_WIDE_COLUMNS) < WORKSPACE_WIDE_COLUMNS) {
      this.setDrawerOpen(true);
    }
    this.ensureTreeSelectionVisible();
    this.layout.requestRender();
    return true;
  }

  /** Restore the host's native Main transcript and saved draft, never its session model. */
  selectMain(): boolean {
    if (!this.attached) return false;
    if (this.inlineAgent()) this.layout.focusEditor();
    this.swapDraft({ kind: "main" });
    this.selection = { kind: "main" };
    this.focus = "editor";
    this.stopArmedId = undefined;
    this.setDrawerOpen(false);
    this.layout.select();
    this.publishEditorView();
    this.layout.requestRender();
    return true;
  }

  private setDrawerOpen(open: boolean): void {
    this.layout.setDrawerOpen(open);
    this.status.refresh();
  }

  private leaveTree(): void {
    this.focus = this.selection.kind === "main" ? "editor" : "browse";
    this.navigationDraft = this.ui?.getEditorText() ?? "";
    this.setDrawerOpen(false);
  }

  /**
   * Stash the current target's draft and restore the next target's. Only
   * writes when the text differs, so IME/cursor state is untouched otherwise.
   */
  private swapDraft(next: WorkspaceSelection, tab = this.workflowTab): void {
    const ui = this.ui;
    if (!ui) return;
    const from = this.editorDraftKey;
    const inline = this.inlineAgent(next, tab);
    const to = inline ? inline.recordId ? `agent:${inline.recordId}` : `${selectionKey(next)}:inline:${inline.key}` : draftKey(next);
    this.editorDraftKey = to;
    if (from === to) return;
    const current = ui.getEditorText();
    if (current) {
      this.drafts.set(from, current);
      if (from !== "main" && (this.draftViews.has(from) || this.draftViews.size < RELOAD_MAX_DRAFTS)) this.draftViews.set(from, this.draftView(from));
    } else {
      this.drafts.delete(from);
      if (!this.unavailableKeys.has(from)) this.draftViews.delete(from);
    }
    const restored = this.drafts.get(to) ?? "";
    if (restored !== current) ui.setEditorText(restored);
  }

  private handleInput(data: string): { consume?: boolean } | undefined {
    if (!this.enabled || !this.attached || isKeyRelease(data) || this.steerDialogTargetId) return undefined;
    // Extension terminal listeners run before whichever UI component owns the
    // keyboard. Only the editor and our mounted panes own workspace shortcuts;
    // selectors, overlays, and another extension's prompt keep their input.
    if (!this.workspaceHasFocus()) return undefined;

    if (matchesKey(data, Key.f6)) {
      if (this.treeActive) this.leaveTree();
      else this.focusTree();
      this.layout.requestRender();
      return { consume: true };
    }

    // ctrl+h/j/k/l stand in for the arrows, as in pi's own lists (keybindings.json).
    const arrow = matchesKey(data, Key.up) || matchesKey(data, "ctrl+k") ? "up"
      : matchesKey(data, Key.down) || matchesKey(data, "ctrl+j") ? "down"
      : matchesKey(data, Key.left) || matchesKey(data, "ctrl+h") ? "left"
      : matchesKey(data, Key.right) || matchesKey(data, "ctrl+l") ? "right" : undefined;
    // An editor-side change (mouse editing, paste, draft restoration) also ends
    // browsing. Explicit Enter/click/F6 captures the retained draft as-is.
    if (this.focus !== "editor" && this.ui?.getEditorText() !== this.navigationDraft) {
      this.leaveTree();
      this.focus = "editor";
      this.layout.focusEditor();
    }
    const composing = decodeKittyPrintable(data) !== undefined || /^[^\x00-\x1f\x7f\x9b]+$/u.test(data)
      || data.startsWith("\x1b[200~") || matchesKey(data, Key.backspace) || matchesKey(data, Key.delete);

    if (this.treeActive) {
      if (matchesKey(data, Key.escape)) this.leaveTree();
      else if (arrow) this.moveCursor(arrow);
      else if (matchesKey(data, Key.enter)) this.activateTreeRow(this.cursorRow());
      else {
        if (composing) {
          this.leaveTree();
          this.focus = "editor";
          if (this.inlineAgent()) this.layout.focusEditor();
          this.layout.requestRender();
        }
        return undefined;
      }
      this.ensureTreeSelectionVisible();
      this.layout.requestRender();
      return { consume: true };
    }

    // Agent-thread browsing still resumes when its composer is cleared.
    // Workflows require explicit browse focus so pane arrows never take editor
    // cursor/history input, even while the workflow's draft is empty.
    if (arrow && this.focus === "editor" && this.selection.kind !== "main" && this.selection.kind !== "workflow" && this.ui?.getEditorText() === "") this.leaveTree();
    if (this.focus === "inline") {
      if (matchesKey(data, Key.escape)) {
        this.leaveTree();
        const browser = this.workflowDocuments.get(`${selectionKey(this.selection)}:overview`)?.scroll;
        if (browser) this.tui?.setFocus(browser);
        this.layout.requestRender();
        return { consume: true };
      }
      if (matchesKey(data, Key.tab) || matchesKey(data, Key.shift(Key.tab))) {
        this.cycleTab(matchesKey(data, Key.tab) ? 1 : -1);
        return { consume: true };
      }
      const scroll = this.workflowDocuments.get(`${selectionKey(this.selection)}:overview`)?.inlineScroll;
      if (arrow || matchesKey(data, Key.pageUp) || matchesKey(data, Key.pageDown) || matchesKey(data, Key.home) || matchesKey(data, Key.end) || matchesKey(data, Key.enter)) {
        if (arrow === "up" || arrow === "down") scroll?.scrollBy(arrow === "up" ? -1 : 1);
        else if (matchesKey(data, Key.pageUp) || matchesKey(data, Key.pageDown)) scroll?.scrollBy((matchesKey(data, Key.pageUp) ? -1 : 1) * Math.max(1, (scroll?.viewportHeight ?? 1) - 1));
        else if (matchesKey(data, Key.home)) scroll?.scrollToStart();
        else if (matchesKey(data, Key.end)) scroll?.scrollToEnd();
        this.layout.requestRender();
        return { consume: true }; // Browse Enter can never submit a retained draft.
      }
      if (composing) { this.focus = "editor"; this.layout.focusEditor(); }
    }
    if (this.focus === "browse") {
      if (matchesKey(data, Key.escape)) {
        this.focusTree();
        return { consume: true };
      }
      if (this.selection.kind === "workflow") {
        if (matchesKey(data, Key.tab) || matchesKey(data, Key.shift(Key.tab))) {
          this.cycleTab(matchesKey(data, Key.tab) ? 1 : -1);
          return { consume: true };
        }
        if (this.workflowTab === "overview" && (arrow || matchesKey(data, Key.enter))) {
          this.selectedComponent(); // Ensure the retained Overview exists before its first render.
          const document = this.workflowDocuments.get(`${selectionKey(this.selection)}:overview`)?.document;
          if (arrow === "left" || arrow === "right") document?.switchPane(arrow);
          else if (arrow) document?.moveSelection(arrow);
          else document?.activate();
          this.stopArmedId = undefined;
          this.layout.requestRender();
          return { consume: true };
        }
      }
      if (arrow) {
        if (arrow === "left" || arrow === "right") this.cycleTab(arrow === "left" ? -1 : 1);
        else {
          const scroll = this.selectedComponent();
          if (scroll instanceof ScrollView) scroll.scrollBy(arrow === "up" ? -1 : 1);
        }
        this.stopArmedId = undefined;
        this.layout.requestRender();
        return { consume: true };
      }
      if (composing || matchesKey(data, Key.enter)) {
        this.focus = "editor";
        if (this.inlineAgent()) this.layout.focusEditor();
      }
    }

    if (arrow === "right" && this.selection.kind === "main" && this.ui?.getEditorText() === "") {
      // Main keeps history and cursor semantics; only empty-prompt Right is a
      // shortcut to the last inspector. Main selection is always explicit.
      const previous = this.lastInspectorSelection;
      const retained = previous?.kind === "agent"
        ? this.options.manager.getRecord(previous.id) !== undefined || this.unavailableKeys.has(draftKey(previous))
        : previous !== undefined && this.options.workflows().some(task => task.id === previous.id);
      const next = retained ? previous : this.treeRows().find(row => row.selection && row.selection.kind !== "main")?.selection;
      if (next) this.openSelection(next, !retained);
      else this.focusTree();
      this.layout.requestRender();
      return { consume: true };
    }

    // Native tool/thinking shortcuts are presentation-local and only claimed
    // by a viewed Activity pane. Main, metadata tabs and dialogs keep theirs.
    const activityDocument = this.selection.kind === "agent" && this.tab === "activity"
      ? this.documents.get(this.selection.id)?.document
      : this.selection.kind === "workflow" && (this.workflowTab === "activity" || this.inlineAgent())
        ? this.workflowDocuments.get(`${selectionKey(this.selection)}:${this.workflowTab}`)?.document
        : undefined;
    if (activityDocument) {
      const keybindings = getKeybindings();
      if (keybindings.matches(data, "app.tools.expand")) {
        activityDocument.toggleExpanded();
        this.stopArmedId = undefined;
        return { consume: true };
      }
      if (keybindings.matches(data, "app.thinking.toggle")) {
        activityDocument.toggleThinking();
        this.stopArmedId = undefined;
        return { consume: true };
      }
    }

    if (this.selection.kind === "workflow" && matchesKey(data, Key.f7)) {
      this.cycleTab(1);
      return { consume: true };
    }

    if (this.selection.kind !== "agent") {
      if (this.stopArmedId) {
        this.stopArmedId = undefined;
        this.layout.requestRender();
      }
      return undefined;
    }
    const record = this.unavailableKeys.has(this.editorDraftKey) ? undefined : this.options.manager.getRecord(this.selection.id);
    if (!record) return undefined;

    if (matchesKey(data, Key.f7)) {
      this.cycleTab(1);
      return { consume: true };
    }
    if (matchesKey(data, Key.f8) && (record.status === "running" || record.status === "queued")) {
      this.stopArmedId = undefined;
      void this.promptSteer(record.id);
      return { consume: true };
    }
    if (matchesKey(data, Key.f9) && (record.status === "running" || record.status === "queued")) {
      if (this.stopArmedId === record.id) {
        this.stopArmedId = undefined;
        const stopped = this.options.manager.abort(record.id);
        this.ui?.notify(
          stopped
            ? `Stopped ${targetName(record)} — ${record.description}.`
            : `Could not stop ${targetName(record)} — it is no longer running.`,
          stopped ? "info" : "warning",
        );
      } else {
        this.stopArmedId = record.id;
      }
      this.layout.requestRender();
      return { consume: true };
    }

    // Ordinary text, digits, x, Enter, Ctrl+C, and editor commands stay with
    // the native editor. The input hook handles steering on submission.
    // They may disarm F9, but are never consumed or transformed here.
    if (this.stopArmedId) {
      this.stopArmedId = undefined;
      this.layout.requestRender();
    }
    return undefined;
  }

  private async promptSteer(targetId: string): Promise<void> {
    const ui = this.ui;
    const record = this.options.manager.getRecord(targetId);
    if (!ui || !record || this.steerDialogTargetId) return;
    this.steerDialogTargetId = targetId;
    this.layout.requestRender();
    try {
      const value = await ui.input(`Steer ${targetName(record)} — ${record.description}`);
      const message = value?.trim();
      if (!message || this.ui !== ui || !this.enabled || !this.attached) return;
      const current = this.options.manager.getRecord(targetId);
      const sent = current !== undefined && this.options.manager.steer(targetId, message);
      ui.notify(
        sent
          ? `Sent to ${targetName(current)} — ${current.description}.`
          : `Could not steer ${targetName(record)} — it is no longer running.`,
        sent ? "info" : "warning",
      );
    } catch (error) {
      if (this.ui === ui) ui.notify(`Could not steer ${targetName(record)}: ${String(error)}`, "warning");
    } finally {
      this.steerDialogTargetId = undefined;
      this.layout.requestRender();
    }
  }

  private cycleTab(direction: -1 | 1): void {
    if (this.selection.kind === "agent") {
      const tabs: readonly WorkspaceTab[] = ["activity", "details", "context"];
      this.selectAgentTab(tabs[(tabs.indexOf(this.tab) + direction + tabs.length) % tabs.length]);
    } else if (this.selection.kind === "workflow") {
      const tabs = WORKFLOW_WORKSPACE_TABS;
      this.selectWorkflowTab(tabs[(tabs.indexOf(this.workflowTab) + direction + tabs.length) % tabs.length]);
    }
  }

  private selectAgentTab(tab: WorkspaceTab): void {
    if (this.selection.kind !== "agent") return;
    this.leaveTree();
    if (tab === this.tab) { this.layout.requestRender(); return; }
    this.tab = tab;
    this.stopArmedId = undefined;
    const scroll = this.selectedComponent();
    // Static metadata starts at its header without suppressing Activity's
    // retained follow/history state or exposing a misleading jump-to-end hint.
    if (tab !== "activity" && scroll instanceof ScrollView) scroll.scrollTo(0);
    this.layout.select(scroll);
    this.layout.requestRender();
  }

  private selectWorkflowTab(tab: WorkflowWorkspaceTab): void {
    if (this.selection.kind !== "workflow") return;
    this.leaveTree();
    if (tab === this.workflowTab) { this.layout.requestRender(); return; }
    if (this.inlineAgent()) this.layout.focusEditor();
    this.swapDraft(this.selection, tab);
    this.workflowTab = tab;
    this.navigationDraft = this.ui?.getEditorText() ?? "";
    this.publishEditorView();
    this.stopArmedId = undefined;
    this.layout.select(this.selectedComponent());
    this.layout.requestRender();
  }

  private workspaceHasFocus(): boolean {
    const tui = this.tui as (TUI & { getFocusedComponent?: () => Component | null; focusedComponent?: unknown }) | undefined;
    if (tui?.hasOverlay?.()) return false;
    const focused = tui?.getFocusedComponent ? tui.getFocusedComponent() : tui?.focusedComponent;
    if (focused == null || this.layout.ownsFocus(focused)) return true;
    if (this.inlineAgent() && this.workflowDocuments.get(`${selectionKey(this.selection)}:overview`)?.document.ownsInlineFocus(focused)) return true;
    if (typeof focused !== "object") return false;
    const candidate = focused as { getText?: unknown; getCursor?: unknown; setText?: unknown };
    return typeof candidate.getText === "function"
      && typeof candidate.getCursor === "function"
      && typeof candidate.setText === "function";
  }

  private treeRows(): TreeRow[] {
    const records = this.options.manager.listAgents().slice().sort((a, b) => a.startedAt - b.startedAt);
    const workflows = [...this.options.workflows()].sort((a, b) => a.startTime - b.startTime);
    const activeWorkflow = (task: WorkflowTask) => task.status === "running" || task.status === "paused";
    const rows: TreeRow[] = [{ kind: "main", key: "main", depth: 0, label: "Main", selection: { kind: "main" } }];
    const shown = new Set<string>();
    const workflowRecords = new Set(workflows.flatMap(task => this.workflowAgents(task).flatMap(entry => entry.recordId ? [entry.recordId] : [])));
    const children = new Map<string, AgentRecord[]>();
    for (const record of records) {
      if (!record.parentAgentId) continue;
      const siblings = children.get(record.parentAgentId) ?? [];
      siblings.push(record);
      children.set(record.parentAgentId, siblings);
    }
    // A parent row is collapsible only once it has children; `push` returns
    // whether the caller should emit those children.
    const push = (row: TreeRow, childCount: number): boolean => {
      if (childCount === 0) {
        rows.push(row);
        return false;
      }
      const collapsed = this.collapsed.has(row.key);
      rows.push({ ...row, collapsed });
      return !collapsed;
    };
    const addAgent = (record: AgentRecord, depth: number, parentKey: string | undefined, label = targetName(record), previewKey?: string) => {
      if (shown.has(record.id)) return;
      shown.add(record.id);
      const key = `agent:${record.id}`;
      const kids = children.get(record.id) ?? [];
      const expand = push({
        kind: "agent",
        key,
        depth,
        label,
        detail: `${this.agentRowDetail(record)} · ${record.description}`,
        status: record.status,
        recordId: record.id,
        selection: { kind: "agent", id: record.id },
        parentKey,
        previewKey,
      }, kids.length);
      if (!expand) for (const child of kids) shown.add(child.id);
      else for (const child of kids) addAgent(child, depth + 1, key);
    };
    const addWorkflowEntry = (workflow: WorkflowTask, entry: WorkflowAgentEntry, depth: number, parentKey: string) => {
      const record = entry.recordId ? this.options.manager.getRecord(entry.recordId) : undefined;
      const selection: WorkspaceSelection = { kind: "workflow-agent", id: workflow.id, index: entry.index };
      if (record) {
        addAgent(record, depth, parentKey, entry.label, selectionKey(selection));
        return;
      }
      const state = displayState(entry, activeWorkflow(workflow));
      rows.push({ kind: "agent", key: selectionKey(selection), depth, label: entry.label, recordId: entry.recordId, detail: `${state} · recorded preview`, status: state, selection, parentKey });
    };
    const addWorkflow = (workflow: WorkflowTask, depth: number, parentKey?: string) => {
      const key = `workflow:${workflow.id}`;
      const entries = this.workflowAgents(workflow);
      const groups = buildPhaseGroups(workflow.workflowProgress, workflow.meta?.phases);
      // Records may arrive before their first progress batch. Keep those live
      // children reachable too; the shown set prevents duplicate rows.
      const early = records.filter(item => item.workflowId === workflow.id && !entries.some(entry => entry.recordId === item.id));
      const childCount = entries.length + early.length + (groups.length > 1 ? groups.length : 0);
      const expand = push({
        kind: "workflow",
        key,
        depth,
        label: `Workflow ${workflow.workflowName ?? workflow.id}`,
        detail: `${workflow.status} · ${workflow.doneCount}/${workflow.agentCount} agents`,
        status: workflow.status,
        selection: { kind: "workflow", id: workflow.id },
        parentKey,
      }, childCount);
      if (!expand) {
        for (const entry of entries) if (entry.recordId) shown.add(entry.recordId);
        for (const record of early) shown.add(record.id);
        return;
      }
      if (groups.length > 1) {
        // Stages: one collapsible row per phase, opening the workflow overview.
        groups.forEach((group, index) => {
          const phaseKey = `${key}:phase:${index}`;
          const showAgents = push({
            kind: "stage",
            key: phaseKey,
            depth: depth + 1,
            label: group.title,
            detail: `${group.doneCount}/${group.totalCount}`,
            selection: { kind: "workflow", id: workflow.id },
            parentKey: key,
          }, group.agents.length);
          if (!showAgents) {
            for (const entry of group.agents) if (entry.recordId) shown.add(entry.recordId);
            return;
          }
          for (const entry of group.agents) addWorkflowEntry(workflow, entry, depth + 2, phaseKey);
        });
      } else {
        for (const entry of entries) addWorkflowEntry(workflow, entry, depth + 1, key);
      }
      for (const record of early) addAgent(record, depth + 1, key);
    };

    for (const workflow of workflows.filter(activeWorkflow)) addWorkflow(workflow, 0);
    for (const record of records.filter(item => !item.parentAgentId && !item.workflowId && !workflowRecords.has(item.id) && isLiveStatus(item.status))) addAgent(record, 0, undefined);

    const finishedWorkflows = workflows.filter(task => !activeWorkflow(task));
    const finishedAgents = records.filter(item => !item.parentAgentId && !item.workflowId && !workflowRecords.has(item.id) && !isLiveStatus(item.status));
    const finishedCount = finishedWorkflows.length + finishedAgents.length;
    if (finishedCount > 0 && push({ kind: "finished", key: FINISHED_KEY, depth: 0, label: `Finished (${finishedCount})` }, finishedCount)) {
      for (const workflow of finishedWorkflows) addWorkflow(workflow, 1, FINISHED_KEY);
      for (const record of finishedAgents) addAgent(record, 1, FINISHED_KEY);
    }
    for (const key of this.unavailableKeys) {
      const view = this.draftViews.get(key)!;
      const kind = key.startsWith("agent:") ? "agent" : "workflow";
      // Never resolve a saved label to a newly spawned same-name child.
      rows.push({ kind: "agent", key, depth: 0, label: view.label, detail: "UNAVAILABLE · saved text draft",
        selection: { kind, id: key.slice(kind.length + 1) } });
    }
    return rows;
  }

  private agentRowDetail(record: AgentRecord): string {
    const activity = this.options.activity.get(record.id);
    const parts: string[] = [record.status, formatDuration(record.startedAt, record.completedAt ?? Date.now())];
    if (activity) {
      if (activity.activeTools.size > 0) parts.push(`running ${[...activity.activeTools.values()].join(", ")}`);
      else if (activity.responseText) parts.push("responding");
    }
    return parts.join(" · ");
  }

  /** Resolve the cursor identity to its current index; the nearest row if it left. */
  private treeIndex(rows: TreeRow[]): number {
    const index = rows.findIndex(row => row.key === this.treeKey || row.previewKey === this.treeKey);
    if (index >= 0) {
      this.treeKey = rows[index].key;
      return index;
    }
    // An expired row: fall back to the viewed selection, then to Main.
    const viewed = rows.findIndex(row => row.key === selectionKey(this.selection));
    return viewed >= 0 ? viewed : 0;
  }

  private cursorRow(): TreeRow | undefined {
    const rows = this.treeRows();
    return rows[this.treeIndex(rows)];
  }

  private moveCursor(direction: "up" | "down" | "left" | "right"): void {
    const rows = this.treeRows();
    const index = this.treeIndex(rows);
    const row = rows[index];
    if (!row) return;
    if (direction === "up" || direction === "down") {
      const next = rows[Math.max(0, Math.min(rows.length - 1, index + (direction === "up" ? -1 : 1)))];
      this.treeKey = next.key;
      return;
    }
    if (direction === "right") {
      if (row.collapsed === true) this.setCollapsed(row.key, false);
      else this.activateTreeRow(row);
      return;
    }
    // Left: collapse an expanded parent, else climb, else leave to Main.
    if (row.collapsed === false) this.setCollapsed(row.key, true);
    else if (row.parentKey) this.treeKey = row.parentKey;
    else this.selectMain();
  }

  private setCollapsed(key: string, collapsed: boolean): void {
    if (collapsed) this.collapsed.add(key);
    else this.collapsed.delete(key);
    this.treeKey = key;
  }

  private activateTreeRow(row: TreeRow | undefined): void {
    if (!row) return;
    if (!row.selection) {
      this.setCollapsed(row.key, row.collapsed !== true);
      return;
    }
    this.openSelection(row.selection);
  }

  private openSelection(selection: WorkspaceSelection, resetTab = true): void {
    if (selection.kind === "main") {
      this.selectMain();
      return;
    }
    if (this.inlineAgent()) this.layout.focusEditor();
    this.swapDraft(selection, resetTab ? "overview" : this.workflowTab);
    this.selection = selection;
    this.lastInspectorSelection = selection;
    this.treeKey = selectionKey(selection);
    if (resetTab) {
      this.tab = "activity";
      this.workflowTab = "overview";
    }
    this.stopArmedId = undefined;
    this.layout.select(this.selectedComponent());
    this.leaveTree();
    this.publishEditorView();
    this.layout.requestRender();
  }

  /**
   * Transient confirmation line above the editor. Empty in every ordinary
   * state: the tree marks what is viewed, and the editor's own placeholder and
   * metadata name the steering recipient. Only an armed F9 stop or an open F8
   * dialog needs a row, and only until it resolves.
   */
  renderBridge(width: number): string[] {
    if (this.selection.kind !== "agent") return [];
    const record = this.options.manager.getRecord(this.selection.id);
    if (!record) return [];
    const target = rowLabel(this.workflowLabel(record) ?? targetName(record));
    if (this.steerDialogTargetId === record.id) return [truncateToWidth(this.theme.fg("dim", `Steering ${target}`), width)];
    if (this.stopArmedId !== record.id) return [];
    const cascade = this.activeDescendantCount(record.id);
    const line = `Press stop again to STOP ${target}${cascade > 0 ? ` (+${cascade} descendant${cascade === 1 ? "" : "s"})` : ""} · any other key cancels`;
    return [truncateToWidth(this.theme.fg("warning", line), width)];
  }

  /**
   * Compact composer placeholder naming the steering recipient, or undefined
   * when Main's own placeholder should show. Hosts that expose a placeholder
   * hook render this; nothing else repeats the routing.
   */
  composerPlaceholder(): string | undefined {
    const target = this.steerTarget();
    if (target.kind === "agent") return `Steer ${target.label}`;
    if (target.kind === "unavailable") return `${target.label} ${target.reason} · select Main`;
    return undefined;
  }

  private publishEditorView(force = false): void {
    if (!this.options.events) return;
    const view: EditorView = { version: 1, agent: null };
    if (this.attached) {
      view.placeholder = this.composerPlaceholder();
      const inline = this.inlineAgent();
      if (this.selection.kind === "agent" || inline) {
        const id = inline?.recordId ?? (this.selection.kind === "agent" ? this.selection.id : `${selectionKey(this.selection)}:inline:${inline?.key}`);
        const record = inline ? this.inlineRecord() : this.options.manager.getRecord(id);
        const model = record?.session?.model;
        const invocation = record?.invocation;
        const canonical = invocation?.modelId ?? inline?.modelId;
        const slash = canonical?.indexOf("/") ?? -1;
        view.agent = {
          id,
          modelId: model?.id ?? (slash >= 0 ? canonical?.slice(slash + 1) : canonical),
          modelName: model ? model.name : invocation?.modelName ?? inline?.model,
          provider: model?.provider ?? (slash >= 0 ? canonical?.slice(0, slash) : undefined),
          thinkingLevel: record?.session?.thinkingLevel ?? invocation?.thinking ?? inline?.thinking,
        };
      } else if (this.selection.kind === "workflow-agent") {
        const selection = this.selection;
        const task = this.options.workflows().find(item => item.id === selection.id);
        const entry = task && this.workflowAgents(task).find(item => item.index === selection.index);
        const slash = entry?.modelId?.indexOf("/") ?? -1;
        view.agent = {
          id: selectionKey(selection),
          modelId: slash >= 0 ? entry?.modelId?.slice(slash + 1) : entry?.modelId,
          modelName: entry?.model,
          provider: slash >= 0 ? entry?.modelId?.slice(0, slash) : undefined,
          thinkingLevel: entry?.thinking,
        };
      }
    }
    const saved = this.attached && this.unavailableKeys.has(this.editorDraftKey) ? this.draftViews.get(this.editorDraftKey) : undefined;
    if (saved) view.agent = { id: this.selection.kind === "main" ? "main" : this.selection.id,
      modelId: saved.modelId, modelName: saved.modelName, provider: saved.provider, thinkingLevel: saved.thinkingLevel };
    const serialized = JSON.stringify(view);
    if (!force && serialized === this.lastEditorView) return;
    this.lastEditorView = serialized;
    this.options.events.emit(EDITOR_VIEW_EVENT, view);
  }

  private activeDescendantCount(parentId: string): number {
    let count = 0;
    const visit = (id: string) => {
      for (const record of this.options.manager.listAgents()) {
        if (record.parentAgentId !== id) continue;
        if (record.status === "running" || record.status === "queued") count++;
        visit(record.id);
      }
    };
    visit(parentId);
    return count;
  }

  private ensureTreeSelectionVisible(): void {
    const rows = this.treeRows();
    const index = this.treeIndex(rows);
    const line = 1 + rows.slice(0, index).reduce((height, row) => height + sidebarRowHeight(row), 0);
    const bottom = line + sidebarRowHeight(rows[index]) - 1;
    // The scroll view holds the rows below the heading, so its row 0 is line 1.
    const top = this.sidebarScroll.scrollTop;
    const height = this.sidebarScroll.viewportHeight;
    if (line - 1 < top) this.sidebarScroll.scrollTo(line - 1, { disableFollow: true });
    else if (height > 0 && bottom - 1 >= top + height) {
      this.sidebarScroll.scrollTo(bottom - height, { disableFollow: true });
    }
  }
}

/** Dynamic renderer wrapper used for already-mounted transcript cards. */
export class WorkspaceAwareComponent implements Component {
  constructor(
    private hidden: () => boolean,
    private component: Component,
  ) {}

  render(width: number): string[] {
    return this.hidden() ? [] : this.component.render(width);
  }

  handleInput(data: string): void {
    this.component.handleInput?.(data);
  }

  invalidate(): void {
    this.component.invalidate();
  }

  dispose(): void {
    const disposable = this.component as Component & { dispose?: () => void };
    disposable.dispose?.();
  }
}

export function workspaceAware(hidden: () => boolean, component: Component): Component {
  return new WorkspaceAwareComponent(hidden, component);
}
