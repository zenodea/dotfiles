import { type Component, Container, stripTerminalSequences, type TUI, type TuiMouseEvent, type TuiMouseEventResult, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import type { AgentRecord } from "../types.js";
import { collapse, displayState, elapsedMs, formatDuration, type WorkflowAgentEntry, type WorkflowDisplayState } from "../workflow/progress.js";
import type { WorkflowTask } from "../workflow/task.js";
import type { Theme } from "./agent-widget.js";
import { InspectorBody } from "./inspector-presentation.js";
import { type NativeActivityEntry, NativeAgentActivity } from "./native-agent-activity.js";
import { type WorkflowAgentRow, type WorkflowInlineActivation, workflowAgentRowLabel, workflowAgentRowMetadata, workflowAgentRowState, workflowAgentRows } from "./workflow-agent-rows.js";
import { agentStatSegments, formatCompactTokens, formatModel, formatThinking, styleWorkflowCardLines } from "./workflow-card.js";
import { resolveWorkflowDialog, rightAlign } from "./workflow-dialog.js";
import { type WorkflowOverviewHit, type WorkflowOverviewPane, type WorkflowOverviewView, workflowOverviewPanes } from "./workflow-overview-panes.js";
import { type WorkspaceClick, WorkspaceTabs } from "./workspace-tabs.js";

export type WorkflowWorkspaceTab = "overview" | "activity" | "results" | "details";
export const WORKFLOW_WORKSPACE_TABS: readonly WorkflowWorkspaceTab[] = ["overview", "activity", "results", "details"];

const MAX_TEXT = 16_000;
const MAX_EVENTS = 120;
const clean = (text: string) => stripTerminalSequences(text).replaceAll("\u0000", "");
const singleLine = (text: string) => clean(text).replace(/\s+/g, " ").trim();

function json(value: unknown): string {
  try { return JSON.stringify(value, null, 2) ?? String(value); }
  catch { return "[Value cannot be serialized]"; }
}

function badge(state: string, theme: Theme): string {
  if (state === "done" || state === "completed") return theme.fg("success", "✓");
  if (state === "failed" || state === "error") return theme.fg("error", "✗");
  if (state === "running") return theme.fg("accent", "●");
  if (state === "blocked" || state === "paused" || state === "queued") return theme.fg("warning", "◦");
  if (state === "not-started" || state === "skipped") return theme.fg("dim", "○");
  return theme.fg("dim", "■");
}

interface Options {
  task: WorkflowTask;
  theme: () => Theme;
  tab: () => WorkflowWorkspaceTab;
  openAgent: (entry: WorkflowAgentEntry) => void;
  openWorkflow: () => void;
  onTabChange?: (tab: WorkflowWorkspaceTab) => void;
  onBrowse?: () => void;
  onActivate?: (row: WorkflowAgentRow) => void;
  inlineAgent?: () => WorkflowInlineActivation | undefined;
  records?: () => readonly AgentRecord[];
  inlineRecord?: () => AgentRecord | undefined;
  onInlineFocus?: () => void;
  spinnerFrame?: () => number;
  agentIndex?: number;
  tui?: TUI;
  resolveRecord?: (id: string) => AgentRecord | undefined;
  onChange?: () => void;
}

type Body = { inspector: InspectorBody; key: unknown[]; lines: string[]; hits: Map<number, WorkflowAgentEntry>; agents: WorkflowAgentEntry[]; overviewHits: WorkflowOverviewHit[]; resultRow?: number };

/** Quiet, retained workflow overview and recorded-agent drilldown. */
export class WorkflowWorkspaceDocument implements Component {
  private body: Body | undefined;
  private headerHeight = 0;
  private builds = 0;
  private tabs = new WorkspaceTabs<WorkflowWorkspaceTab>();
  private width = 0;
  private nativeOffset = 0;
  private nativeRows = new Container();
  private activities = new Map<string, { record: AgentRecord; session: AgentRecord["session"]; activity: NativeAgentActivity }>();
  private nativeEntries = new Map<string, { label: string; attributed: boolean; component: Component }>();
  private activityRevision = 0;
  private overviewAssociations = new Map<string, string>();
  private inlineFocusTarget?: { id: string; component: Component };
  private expanded = false;
  private disclosures = new Set<string>();
  private hideThinking?: boolean;
  private selectedPhase = 0;
  private selectedAgent = 0;
  private selectedAgentKey?: string;
  private pane: WorkflowOverviewPane = "phases";

  constructor(private options: Options) {}

  get bodyBuildCount(): number { return this.builds; }

  /** Separate layout children: the compact browser never joins transcript scrollback. */
  readonly inlineHeader: Component = {
    render: width => {
      const entry = this.options.inlineAgent?.();
      if (!entry || width <= 0) return [];
      const record = this.options.inlineRecord?.();
      const status = record ? record.status : "unavailable";
      return [truncateToWidth(this.options.theme().bold(`Activity · ${singleLine(entry.label)} · ${status}`), width)];
    },
    handleMouse: event => {
      if (event.type !== "click" || event.button !== "left") return undefined;
      this.options.onInlineFocus?.();
      return { handled: true, focus: false };
    },
    invalidate: () => {},
  };

  readonly inlineActivity: Component = {
    render: width => {
      if (width <= 0) return [];
      this.observe();
      const record = this.options.inlineRecord?.();
      const activity = record && this.activities.get(record.id)?.activity;
      this.nativeRows.clear();
      if (!activity) return [truncateToWidth(this.options.theme().fg("dim",
        "Agent unavailable · native activity is not retained. Draft kept; select another agent or Main."), width)];
      this.nativeRows.addChild(activity);
      return this.nativeRows.render(width);
    },
    handleMouse: event => {
      if ((event.type === "press" || event.type === "click") && event.button === "left") this.options.onInlineFocus?.();
      const record = this.options.inlineRecord?.();
      if (!record || !this.activities.has(record.id)) return undefined;
      const result = this.nativeRows.handleMouse(event);
      if (result?.focus) this.inlineFocusTarget = { id: record.id, component: result.focusTarget ?? result.target.component };
      return result;
    },
    invalidate: () => { for (const { activity } of this.activities.values()) activity.invalidate(); },
  };

  ownsInlineFocus(focused: unknown): boolean {
    // Keep Escape/typing recoverable after the activated record loses ancestry.
    return this.inlineFocusTarget?.component === focused && this.inlineFocusTarget?.id === this.options.inlineAgent?.()?.recordId;
  }

  render(width: number): string[] {
    this.width = width;
    this.headerHeight = 0;
    this.nativeOffset = 0;
    this.tabs.clear();
    if (width <= 0) return [];
    const { task, agentIndex } = this.options;
    const theme = this.options.theme();
    const tab = this.options.tab();
    this.observe();
    const overview = this.isOverview() ? this.resolveOverview() : undefined;
    const animation = overview?.visibleRows.some(row => workflowAgentRowState(row, this.active()) === "running")
      ? this.options.spinnerFrame?.() ?? 0 : undefined;
    const membership = overview && JSON.stringify(overview.visibleRows.map(row => [row.key, row.call.index, row.call.recordId,
      row.depth, row.kind === "descendant" ? row.ancestorIds : [], workflowAgentRowLabel(row), workflowAgentRowMetadata(row),
      row.record?.status, row.record?.description]));
    const key = [membership, this.selectedAgentKey, animation, this.activityRevision, width, theme, tab, task.progressVersion, task.workflowProgress.length, task.status, task.value, task.error, task.meta, task.args, task.scriptPath, task.journalPath, task.resumedFrom, task.replayedCount, this.selectedPhase, this.selectedAgent, this.pane];
    if (!this.body || key.some((value, index) => !Object.is(value, this.body?.key[index]))) {
      this.body = this.build(width, theme, tab, key, overview);
      this.builds++;
    }
    const agents = this.body.agents;
    const failed = agents.filter(agent => displayState(agent, this.active()) === "failed").length;
    const name = singleLine(task.workflowName ?? task.meta?.name ?? "Workflow");
    const elapsed = formatDuration(elapsedMs(task, task.pausedAt ?? Date.now()));
    const title = agentIndex === undefined ? `${badge(task.status, theme)} ${theme.bold(name)}` : theme.fg("accent", `‹ ${name} · back to workflow`);
    const metrics = [
      failed ? `${failed} failed` : "",
      elapsed,
      task.totalTokens > 0 ? `${formatCompactTokens(task.totalTokens)} tokens` : "",
      task.totalToolCalls > 0 ? `${task.totalToolCalls} tool calls` : "",
    ].filter(Boolean).join(" · ");
    const header = overview ? [theme.bold(name), ...styleWorkflowCardLines([rightAlign(
      [{ text: singleLine(task.meta?.description ?? ""), color: "dim" }],
      [{ text: `${agents.filter(agent => agent.state === "done").length}/${Math.max(task.agentCount, agents.length)} ${overview.hasDescendants ? "calls" : "agents"} · ${elapsed}`, color: "dim" }], width,
    )], theme)] : tab === "activity" && agentIndex === undefined ? [theme.bold(name)] : [title, theme.fg("dim", metrics)];
    if (agentIndex === undefined) {
      if (!overview && tab !== "activity" && task.meta?.description) header.push(theme.fg("muted", singleLine(task.meta.description)));
      header.push("");
      header.push(this.tabs.render(width, header.length, WORKFLOW_WORKSPACE_TABS,
        item => item === tab ? theme.bold(theme.fg("accent", `[${item}]`)) : theme.fg("dim", item)));
    }
    header.push(theme.fg("dim", "─".repeat(width)), "");
    this.headerHeight = header.length;
    this.nativeOffset = this.headerHeight + this.body.lines.length;
    const native = tab === "activity" && agentIndex === undefined ? this.renderNativeActivity(width, agents) : [];
    return [...header.map(line => truncateToWidth(line, width)), ...this.body.lines, ...native];
  }

  handleMouse(event: WorkspaceClick | TuiMouseEvent): TuiMouseEventResult | undefined {
    if (event.x < 0 || event.x >= this.width || event.y < 0) return undefined;
    const tab = this.tabs.hit(event);
    if (tab && this.options.onTabChange) {
      this.options.onTabChange(tab);
      this.options.onChange?.();
      return { handled: true, focus: false };
    }
    if (this.body?.inspector.toggle({ ...event, y: event.y - this.headerHeight })) {
      this.body = undefined;
      this.options.onChange?.();
      return { handled: true, focus: false };
    }
    if (this.options.tab() === "activity" && this.options.agentIndex === undefined && this.nativeOffset > 0
      && event.y >= this.nativeOffset && "width" in event) {
      return this.nativeRows.handleMouse({ ...event, y: event.y - this.nativeOffset,
        height: Math.max(0, event.height - this.nativeOffset) });
    }
    if (event.type !== "click" || event.button !== "left") return undefined;
    if (this.options.agentIndex !== undefined && event.y === 0) {
      this.options.openWorkflow();
      return { handled: true, focus: false };
    }
    if (this.isOverview()) {
      const y = event.y - this.headerHeight;
      if (this.body?.resultRow === y && this.options.onTabChange) {
        this.options.onTabChange("results");
        this.options.onChange?.();
        return { handled: true, focus: false };
      }
      const hit = this.body?.overviewHits.find(hit => hit.y === y && event.x >= hit.start && event.x < hit.end);
      if (!hit) return undefined;
      this.options.onBrowse?.();
      this.pane = hit.pane;
      if (hit.pane === "phases") {
        if (this.selectedPhase !== hit.index) { this.selectedAgent = 0; this.selectedAgentKey = undefined; }
        this.selectedPhase = hit.index;
      } else { this.selectedAgent = hit.index; this.selectedAgentKey = hit.key; }
      const view = this.resolveOverview();
      if (hit.pane === "agents" && view.selectedRow) this.options.onActivate?.(view.selectedRow);
      this.options.onChange?.();
      return { handled: true, focus: false };
    }
    const entry = this.body?.hits.get(event.y - this.headerHeight);
    if (!entry) return undefined;
    this.options.openAgent(entry);
    return { handled: true, focus: false };
  }

  private isOverview(): boolean { return this.options.tab() === "overview" && this.options.agentIndex === undefined; }

  private agentRows(): WorkflowAgentRow[] {
    const calls = collapse(this.options.task.workflowProgress).agents;
    const records = this.options.records?.() ?? calls.flatMap(call => {
      const record = call.recordId && this.options.resolveRecord?.(call.recordId);
      return record ? [record] : [];
    });
    return workflowAgentRows(calls, records);
  }

  private resolveOverview(): WorkflowOverviewView {
    const { task } = this.options;
    const view = resolveWorkflowDialog({ task, meta: task.meta, progress: task.workflowProgress,
      state: { selectedPhase: this.selectedPhase, selectedAgent: this.selectedAgent, level: "phases", filter: "all", promptExpanded: false } });
    this.selectedPhase = view.clampedPhase;
    const calls = new Set(view.visibleAgents.map(call => call.index));
    const allRows = this.agentRows();
    const visibleRows = allRows.filter(row => calls.has(row.call.index));
    if (this.selectedAgentKey === undefined) this.selectedAgentKey = visibleRows[0]?.key;
    const selected = visibleRows.findIndex(row => row.key === this.selectedAgentKey);
    if (selected >= 0) this.selectedAgent = selected;
    // A removed highlighted row has no replacement target until explicit navigation.
    const clampedAgent = Math.max(0, Math.min(this.selectedAgent, visibleRows.length - 1));
    return { ...view, visibleRows, hasDescendants: allRows.some(row => row.kind === "descendant"), clampedAgent,
      selectedRow: selected >= 0 ? visibleRows[selected] : undefined };
  }

  moveSelection(direction: "up" | "down"): boolean {
    if (!this.isOverview()) return false;
    const view = this.resolveOverview();
    const delta = direction === "up" ? -1 : 1;
    const index = this.pane === "phases" ? this.selectedPhase : this.selectedAgent;
    const count = this.pane === "phases" ? view.groups.length : view.visibleRows.length;
    const next = Math.max(0, Math.min(count - 1, index + delta));
    if (next === index && (this.pane === "phases" || view.selectedRow)) return false;
    if (this.pane === "phases") { this.selectedPhase = next; this.selectedAgent = 0; this.selectedAgentKey = undefined; }
    else { this.selectedAgent = next; this.selectedAgentKey = view.visibleRows[next]?.key; }
    this.options.onChange?.();
    return true;
  }

  switchPane(direction: "left" | "right"): boolean {
    if (!this.isOverview()) return false;
    const next = direction === "left" ? "phases" : "agents";
    if (next === this.pane || (next === "agents" && this.resolveOverview().visibleRows.length === 0)) return false;
    this.pane = next;
    this.options.onChange?.();
    return true;
  }

  activate(): boolean {
    if (!this.isOverview()) return false;
    if (this.pane === "phases") return this.switchPane("right");
    const entry = this.resolveOverview().selectedRow;
    if (!entry) return false;
    this.options.onActivate?.(entry);
    return true;
  }

  invalidate(): void {
    this.body = undefined;
    this.tabs.clear();
    this.width = 0;
    this.nativeOffset = 0;
    this.nativeEntries.clear();
    for (const { activity } of this.activities.values()) activity.invalidate();
  }

  /** Also called while another tab is selected, to release evicted sessions. */
  observe(): void {
    if (this.options.agentIndex !== undefined || !this.options.tui) return;
    const retained = new Set<string>();
    const entries = collapse(this.options.task.workflowProgress).agents;
    // Retain local presentation state only while the same ancestry owns it.
    const rows = this.isOverview() ? this.agentRows() : [];
    const present = new Set(rows.flatMap(row => row.record ? [row.record.id] : []));
    const associations = new Map(rows.flatMap(row => row.recordId && (row.kind === "call" || row.ancestorIds.every(id => present.has(id)))
      ? [[row.recordId, JSON.stringify(row.kind === "call" ? ["call", row.recordId] : [row.call.index, row.call.recordId, row.ancestorIds])]] : []));
    for (const [id, previous] of this.overviewAssociations) if (associations.get(id) !== previous) {
      this.activities.get(id)?.activity.dispose();
      this.activities.delete(id);
      this.overviewAssociations.delete(id);
      this.activityRevision++;
    }
    const records = this.isOverview() ? [this.options.inlineRecord?.(), ...rows.filter(row =>
      row.recordId && this.activities.has(row.recordId)).map(row => row.record)]
      : this.options.tab() === "activity" ? entries.map(entry =>
        entry.recordId ? this.options.resolveRecord?.(entry.recordId) : undefined) : [];
    for (const record of records) {
      if (!record || retained.has(record.id)) continue;
      retained.add(record.id);
      let cached = this.activities.get(record.id);
      if (!cached) {
        const activity = new NativeAgentActivity(record, this.options.tui, () => this.options.onChange?.());
        activity.setExpanded(this.expanded);
        if (this.hideThinking !== undefined) activity.setHideThinking(this.hideThinking);
        cached = { record, session: record.session, activity };
        this.activities.set(record.id, cached);
        const association = associations.get(record.id);
        if (association !== undefined) this.overviewAssociations.set(record.id, association);
        this.activityRevision++;
      } else if (cached.record !== record || cached.session !== record.session) {
        cached.activity.setRecord(record);
        cached.record = record;
        cached.session = record.session;
        this.activityRevision++;
      }
      cached.activity.sync();
    }
    for (const [id, cached] of this.activities) if (!retained.has(id)) {
      cached.activity.dispose();
      this.activities.delete(id);
      this.overviewAssociations.delete(id);
      this.activityRevision++;
    }
  }

  toggleExpanded(): void {
    if (this.isOverview()) {
      const record = this.options.inlineRecord?.();
      if (record) this.activities.get(record.id)?.activity.toggleExpanded();
      return;
    }
    this.expanded = !this.expanded;
    for (const { activity } of this.activities.values()) activity.setExpanded(this.expanded);
    this.options.onChange?.();
  }

  toggleThinking(): void {
    if (this.isOverview()) {
      const record = this.options.inlineRecord?.();
      if (record) this.activities.get(record.id)?.activity.toggleThinking();
      return;
    }
    const first = this.activities.values().next().value;
    this.hideThinking = !(this.hideThinking ?? first?.record.session?.settingsManager.getHideThinkingBlock() ?? false);
    for (const { activity } of this.activities.values()) activity.setHideThinking(this.hideThinking);
    this.options.onChange?.();
  }

  dispose(): void {
    for (const { activity } of this.activities.values()) activity.dispose();
    this.activities.clear();
    this.overviewAssociations.clear();
    this.nativeEntries.clear();
    this.nativeRows.clear();
  }

  private renderNativeActivity(width: number, agents: WorkflowAgentEntry[]): string[] {
    const ordered: { entry: NativeActivityEntry; agent: WorkflowAgentEntry }[] = [];
    const seen = new Set<string>();
    for (const agent of agents) {
      if (!agent.recordId || seen.has(agent.recordId)) continue;
      seen.add(agent.recordId);
      const activity = this.activities.get(agent.recordId)?.activity;
      if (activity) for (const entry of activity.getEntries(width)) ordered.push({ entry, agent });
    }
    ordered.sort((a, b) => a.entry.timestamp - b.entry.timestamp || a.agent.index - b.agent.index || a.entry.order - b.entry.order);
    const keys = new Set<string>();
    this.nativeRows.clear();
    let previousSource: string | undefined;
    for (const { entry, agent } of ordered) {
      keys.add(entry.key);
      const label = singleLine(agent.label);
      const source = agent.recordId;
      const attributed = source !== previousSource;
      previousSource = source;
      const headerHeight = attributed ? 1 : 0;
      let cached = this.nativeEntries.get(entry.key);
      if (!cached || cached.label !== label || cached.attributed !== attributed) {
        // This wrapper supplies attribution only; the body and mouse behavior
        // remain the exact native component, including capture/focus metadata.
        const component: Component = {
          render: viewport => [...(attributed ? [truncateToWidth(this.options.theme().fg("dim", label), viewport)] : []),
            ...entry.component.render(viewport).map(line => truncateToWidth(line, viewport))],
          handleMouse: event => {
            if (attributed && event.y === 0 && event.type === "click" && event.button === "left") {
              this.options.openAgent(agent);
              return { handled: true, focus: false };
            }
            return event.y >= headerHeight ? entry.component.handleMouse?.({ ...event, y: event.y - headerHeight,
              height: event.height - headerHeight }) : undefined;
          },
          invalidate: () => entry.component.invalidate(),
        };
        cached = { label, attributed, component };
        this.nativeEntries.set(entry.key, cached);
      }
      this.nativeRows.addChild(cached.component);
    }
    for (const key of this.nativeEntries.keys()) if (!keys.has(key)) this.nativeEntries.delete(key);
    return this.nativeRows.render(width);
  }

  private active(): boolean { return this.options.task.status === "running" || this.options.task.status === "paused"; }

  private build(width: number, theme: Theme, tab: WorkflowWorkspaceTab, key: unknown[], overview?: WorkflowOverviewView): Body {
    const { task, agentIndex } = this.options;
    const { agents } = collapse(task.workflowProgress);
    const inspector = new InspectorBody(width, theme, this.disclosures);
    const lines = inspector.lines;
    const hits = new Map<number, WorkflowAgentEntry>();
    let overviewHits: WorkflowOverviewHit[] = [];
    let resultRow: number | undefined;
    const heading = (text: string) => {
      if (agentIndex !== undefined || tab === "details") inspector.heading(text);
      else lines.push(theme.bold(text));
    };
    const text = (value: string, markdown = false) => {
      const safe = clean(value);
      const bounded = safe.slice(0, MAX_TEXT);
      inspector.text(bounded, markdown);
      if (safe.length > MAX_TEXT) lines.push(theme.fg("dim", `… preview limited to ${MAX_TEXT.toLocaleString()} characters`));
    };
    const state = (entry: WorkflowAgentEntry): WorkflowDisplayState => displayState(entry, this.active());
    const agentRow = (entry: WorkflowAgentEntry, prefix = "  ") => {
      const labelWidth = Math.min(36, Math.max(10, Math.floor(width * 0.4)));
      const label = truncateToWidth(singleLine(entry.label), labelWidth);
      const details = [state(entry), ...agentStatSegments(entry), entry.cached ? "replayed" : ""].filter(Boolean).join(" · ");
      hits.set(lines.length, entry);
      lines.push(`${theme.fg("dim", prefix)}${badge(state(entry), theme)} ${theme.bold(label)}${" ".repeat(Math.max(1, labelWidth - visibleWidth(label) + 2))}${theme.fg("dim", singleLine(details))}`);
    };

    if (agentIndex !== undefined) {
      const entry = agents.find(agent => agent.index === agentIndex);
      if (!entry) text("This agent is no longer present in the recorded workflow progress.");
      else {
        heading(`${badge(state(entry), theme)} ${singleLine(entry.label)}`);
        inspector.fields([["Status", state(entry)], ["Model", formatModel(entry)], ["Thinking", formatThinking(entry)]]);
        inspector.fields([["Phase", entry.phaseTitle], ["Tokens", entry.tokens === undefined ? undefined : formatCompactTokens(entry.tokens)],
          ["Tools", entry.toolCalls?.toString()], ["Time", entry.durationMs === undefined ? undefined : formatDuration(entry.durationMs)]]);
        lines.push(theme.fg("dim", entry.cached ? "Recorded preview · replayed call" : "Recorded preview"));
        if (entry.promptPreview) { heading("Assignment"); text(entry.promptPreview, true); }
        if (entry.error) { heading("Error"); text(entry.error, true); }
        if (entry.resultPreview) { heading("Result"); text(entry.resultPreview, true); }
        inspector.disclosure("Technical details", () => {
          inspector.fields([["Workflow ID", task.id]]);
          inspector.fields([["Agent ID", entry.recordId], ["Call", String(entry.index)]]);
          inspector.fields([["Model", entry.modelId], ["Isolation", entry.isolation]]);
          if (entry.attempt) inspector.fields([["Attempt", String(entry.attempt)], ["Reason", entry.lastAttemptReason]]);
        });
      }
    } else if (overview) {
      const panes = workflowOverviewPanes(overview, this.pane, width, task.pausedAt ?? Date.now(), this.options.spinnerFrame?.() ?? 0);
      overviewHits = panes.hits;
      lines.push(...styleWorkflowCardLines(panes.lines, theme), "");
      if (task.error) { heading(theme.fg("error", "Run failed")); text(task.error); }
      else if (task.value !== undefined) {
        resultRow = lines.length;
        lines.push(theme.fg("accent", "Result available · open results"));
      }
    } else if (tab === "activity") {
      // Native child conversations only. Lifecycle events and log() notes stay
      // accessible in Details diagnostics, never as a transcript preamble.
    } else if (tab === "results") {
      if (task.error) { heading(theme.fg("error", "Run error")); text(task.error); lines.push(""); }
      if (task.value !== undefined) {
        heading("Workflow result");
        text(typeof task.value === "string" ? task.value : `\`\`\`json\n${json(task.value)}\n\`\`\``, true);
        lines.push("");
      } else text(this.active() ? "Run in progress · completed agent results appear below." : "The script returned no value. Recorded agent results are shown below.");
      for (const entry of agents.filter(agent => agent.resultPreview || agent.error)) {
        lines.push("");
        agentRow(entry, "");
        text(entry.error ?? entry.resultPreview ?? "", true);
        lines.push(theme.fg("dim", "Recorded preview · click the agent to inspect"));
      }
    } else {
      inspector.fields([["Status", task.status], ["Replayed", task.replayedCount ? `${task.replayedCount} calls` : undefined]]);
      if (task.error) { heading("Error"); text(task.error, true); }
      if (task.meta?.phases?.length) {
        heading("Plan");
        for (const phase of task.meta.phases) text(`• ${phase.title}${phase.detail ? ` — ${phase.detail}` : ""}`);
      }
      if (task.args !== undefined && task.args !== null && json(task.args) !== "{}" && json(task.args) !== "[]") {
        heading("Arguments"); text(`\`\`\`json\n${json(task.args)}\n\`\`\``, true);
      }
      inspector.disclosure("Technical details", () => {
        for (const [label, value] of [["Run ID", task.id], ["Script", task.scriptPath], ["Journal", task.journalPath], ["Resumed from", task.resumedFrom]]) {
          if (value) inspector.fields([[label!, value]]);
        }
      });
      if (task.workflowProgress.length) inspector.disclosure("Diagnostics", () => {
        inspector.fields([["Events", `${task.workflowProgress.length} · recorded order`]]);
        if (task.workflowProgress.length > MAX_EVENTS) text(`Latest ${MAX_EVENTS} events`);
        for (const event of task.workflowProgress.slice(-MAX_EVENTS)) text(json(event));
      });
    }
    return { inspector, key, agents, hits, overviewHits, resultRow, lines: lines.map(line => truncateToWidth(line, width)) };
  }
}
