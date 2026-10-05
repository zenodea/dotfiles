import type { AgentSession } from "@earendil-works/pi-coding-agent";
import {
  type Component,
  stripTerminalSequences,
  type TUI,
  type TuiMouseEvent,
  type TuiMouseEventResult,
  truncateToWidth,
  wrapTextWithAnsi,
} from "@earendil-works/pi-tui";
import { extractText } from "../context.js";
import type { AgentRecord } from "../types.js";
import { getLifetimeCost, getLifetimeTotal } from "../usage.js";
import { collapse } from "../workflow/progress.js";
import type { WorkflowTask } from "../workflow/task.js";
import { type AgentActivity, buildInvocationTags, formatCost, formatDuration, type Theme } from "./agent-widget.js";
import { InspectorBody } from "./inspector-presentation.js";
import { NativeAgentActivity } from "./native-agent-activity.js";
import { formatCompactTokens } from "./workflow-card.js";
import { type WorkspaceClick, WorkspaceTabs } from "./workspace-tabs.js";

export type WorkspaceTab = "activity" | "details" | "context";

type BodyCache = {
  tab: WorkspaceTab;
  width: number;
  theme: Theme;
  key: string;
  body: InspectorBody;
};

function clean(value: string): string {
  return stripTerminalSequences(value).replaceAll("\u0000", "");
}

function wrap(text: string, width: number): string[] {
  if (width <= 0) return [];
  return wrapTextWithAnsi(clean(text), width).map(line => truncateToWidth(line, width));
}

function modelLabel(session: AgentSession | undefined, record: AgentRecord): string | undefined {
  const model = session?.model;
  if (model) return `${model.provider}/${model.id}`;
  const { modelId, modelName } = buildInvocationTags(record.invocation);
  return modelName ?? modelId;
}

function recordedPrompt(session: AgentSession | undefined): string | undefined {
  if (!session) return undefined;
  for (const message of session.messages) {
    if (message.role !== "user") continue;
    const text = typeof message.content === "string" ? message.content : extractText(message.content);
    if (text.trim()) return text;
  }
  return undefined;
}

type RecordedTask = { id: string; subject?: string; status?: string; blockedBy: string[] };

function recordedTasks(session: AgentSession | undefined): RecordedTask[] {
  if (!session) return [];
  const tasks = new Map<string, RecordedTask>();
  const visit = (value: unknown): void => {
    if (!value || typeof value !== "object") return;
    if (Array.isArray(value)) {
      for (const item of value) visit(item);
      return;
    }
    const object = value as Record<string, unknown>;
    if ((typeof object.id === "string" || typeof object.id === "number") && Array.isArray(object.blockedBy)) {
      const id = String(object.id);
      tasks.set(id, {
        id,
        subject: typeof object.subject === "string" ? object.subject : undefined,
        status: typeof object.status === "string" ? object.status : undefined,
        blockedBy: object.blockedBy.map(String),
      });
    }
    for (const child of Object.values(object)) visit(child);
  };
  for (const message of session.messages) {
    if (message.role === "toolResult" && message.toolName === "todo") visit(message.details);
    if (message.role !== "assistant") continue;
    for (const block of message.content) {
      if (block.type !== "toolCall" || block.name !== "todo") continue;
      visit(block.arguments);
    }
  }
  return [...tasks.values()];
}

/** Retained, revision-cached document for a single child AgentSession. */
export class AgentWorkspaceDocument implements Component {
  private session: AgentSession | undefined;
  private historyRevision = 0;
  private native?: NativeAgentActivity;
  private bodyCache = new Map<WorkspaceTab, BodyCache>();
  private headerHeight = 0;
  private renderedBody?: InspectorBody;
  private bodyBuilds = 0;
  private tabs = new WorkspaceTabs<WorkspaceTab>();
  private expanded = new Set<string>();

  constructor(
    private record: AgentRecord,
    _activity: () => AgentActivity | undefined,
    private tab: () => WorkspaceTab,
    private theme: () => Theme,
    private workflow: () => WorkflowTask | undefined,
    private requestRender: () => void,
    private displayName?: () => string | undefined,
    private onTabChange?: (tab: WorkspaceTab) => void,
    private tui?: TUI,
  ) {}

  setRecord(record: AgentRecord): void {
    if (record === this.record) return;
    this.record = record;
    this.native?.setRecord(record);
    this.historyRevision++;
  }

  /** Subscribe before selection so opening an agent retains its ongoing tool output. */
  observe(): void { this.bindSession(); }

  /** Test/diagnostic surface proving progress ticks reuse finalized bodies. */
  get bodyBuildCount(): number { return this.bodyBuilds; }

  render(width: number): string[] {
    this.tabs.clear();
    this.headerHeight = 0;
    this.renderedBody = undefined;
    if (width <= 0) return [];
    this.bindSession();
    const theme = this.theme();
    const tab = this.tab();
    const named = this.record.alias ?? this.record.handle;
    const target = named ? `@${named}` : this.record.type;
    const header = [theme.bold(clean(this.displayName?.() ?? `${target} — ${this.record.description}`).replace(/[\r\n\t]/g, " "))];
    if (this.record.status !== "running" && this.record.status !== "queued") {
      header.push(theme.fg("dim", `${this.record.status} · ${formatDuration(this.record.startedAt, this.record.completedAt ?? Date.now())}`));
    }
    const tabs = this.tabs.render(width, header.length, ["activity", "details", "context"],
      name => name === tab ? theme.bold(`[${name}]`) : name, theme.fg("dim", "  "));
    header.push(tabs, theme.fg("dim", "─".repeat(Math.max(1, width))));
    const lines = header.map(line => truncateToWidth(line, width));
    this.headerHeight = lines.length;
    if (tab === "activity") {
      lines.push(...(this.native?.render(width) ?? wrap("Native activity requires the host TUI.", width)));
    } else {
      this.renderedBody = this.cachedBody(width, theme, tab);
      lines.push(...this.renderedBody.lines);
    }
    return lines;
  }

  handleMouse(event: WorkspaceClick | TuiMouseEvent): TuiMouseEventResult | undefined {
    const tab = this.tabs.hit(event);
    if (tab && this.onTabChange) {
      this.onTabChange(tab);
      this.requestRender();
      return { handled: true, focus: false };
    }
    if (this.tab() !== "activity" && this.renderedBody?.toggle({ ...event, y: event.y - this.headerHeight })) {
      this.bodyCache.clear();
      this.renderedBody = undefined;
      this.requestRender();
      return { handled: true, focus: false };
    }
    if (this.headerHeight > 0 && this.tab() === "activity" && event.y >= this.headerHeight && "width" in event) {
      return this.native?.handleMouse({ ...event, y: event.y - this.headerHeight,
        height: Math.max(0, event.height - this.headerHeight) });
    }
    return undefined;
  }

  toggleExpanded(): void { this.native?.toggleExpanded(); }
  toggleThinking(): void { this.native?.toggleThinking(); }

  invalidate(): void {
    this.tabs.clear();
    this.headerHeight = 0;
    this.renderedBody = undefined;
    this.bodyCache.clear();
    this.native?.invalidate();
  }

  dispose(): void {
    this.native?.dispose();
    this.native = undefined;
    this.session = undefined;
  }

  private bindSession(): void {
    this.session = this.record.session;
    if (!this.native && this.tui) {
      this.native = new NativeAgentActivity(this.record, this.tui, () => {
        this.historyRevision++;
        this.requestRender();
      });
    }
    this.native?.sync();
  }

  private cachedBody(width: number, theme: Theme, tab: WorkspaceTab): InspectorBody {
    const key = this.dataKey(tab);
    const cached = this.bodyCache.get(tab);
    if (cached && cached.width === width && cached.theme === theme && cached.key === key) return cached.body;
    const body = new InspectorBody(width, theme, this.expanded);
    if (tab === "details") this.detailLines(body);
    else this.contextLines(body);
    this.bodyBuilds++;
    this.bodyCache.set(tab, { tab, width, theme, key, body });
    return body;
  }

  private dataKey(tab: WorkspaceTab): string {
    const session = this.session;
    return [
      tab,
      this.historyRevision,
      session?.messages.length,
      session?.systemPrompt,
      this.workflow()?.progressVersion,
      this.workflow()?.workflowName,
      this.record.sessionFile,
      this.record.outputFile,
      JSON.stringify(this.record.invocation),
      this.record.status,
      this.record.completedAt,
      this.record.result,
      this.record.error,
      this.record.pendingSteers?.join("\u0001"),
      session?.getSteeringMessages().join("\u0001"),
      session?.model?.provider,
      session?.model?.id,
      session?.thinkingLevel,
      this.record.lifetimeUsage?.input,
      this.record.lifetimeUsage?.output,
      this.record.lifetimeUsage?.cost,
    ].join("|");
  }

  private detailLines(body: InspectorBody): void {
    const workflow = this.workflow();
    const phase = workflow
      ? collapse(workflow.workflowProgress).agents.find(agent => agent.recordId === this.record.id)
      : undefined;
    const prompt = recordedPrompt(this.session);
    const tasks = recordedTasks(this.session);
    const queued = [...(this.record.pendingSteers ?? []), ...(this.session?.getSteeringMessages() ?? [])].filter(text => text.trim());
    body.fields([["Status", this.record.status], ["Agent", this.record.type]]);
    body.fields([["Workflow", workflow?.workflowName ?? workflow?.meta?.name], ["Phase", phase?.phaseTitle]]);
    if (prompt) { body.heading("Assignment"); body.text(prompt, true); }
    if (this.record.result?.trim()) { body.heading("Result"); body.text(this.record.result, true); }
    if (this.record.error?.trim()) { body.heading("Error"); body.text(this.record.error, true); }
    if (tasks.length) {
      body.heading("Tasks");
      for (const task of tasks) {
        body.fields([[task.subject ?? task.id, task.status ?? "recorded"], ["Blocked by", task.blockedBy.length ? task.blockedBy.join(", ") : undefined]]);
      }
    }
    if (queued.length) {
      body.heading("Queued steers");
      for (const message of queued) body.text(message, true);
    }
    body.disclosure("Technical details", () => {
      // Keep technical values on their own wrapped rows for copying/inspection.
      for (const [label, value] of [
        ["Agent ID", this.record.id], ["Parent ID", this.record.parentAgentId],
        ["Workflow ID", this.record.workflowId], ["Session file", this.record.sessionFile],
        ["Output transcript", this.record.outputFile],
        ["Invocation", this.record.invocation ? JSON.stringify(this.record.invocation, null, 2) : undefined],
      ]) if (value) body.fields([[label!, value]]);
    });
  }

  private contextLines(body: InspectorBody): void {
    const session = this.session;
    const stats = session?.getSessionStats();
    const context = stats?.contextUsage ?? session?.getContextUsage();
    const lifetime = this.record.lifetimeUsage;
    const inherited = this.record.invocation?.inheritContext;
    body.fields([["Model", modelLabel(session, this.record)], ["Thinking", session?.thinkingLevel ?? this.record.invocation?.thinking]]);
    if (inherited !== undefined) body.fields([["Context", inherited ? "Inherited conversation" : "Fresh session"]]);
    const usage = stats?.tokens ?? lifetime;
    if (usage) {
      body.heading("Usage");
      const total = stats?.tokens.total ?? (lifetime ? getLifetimeTotal(lifetime) : 0);
      const cost = stats?.cost ?? (lifetime ? getLifetimeCost(lifetime) : 0);
      body.fields([["Input", formatCompactTokens(usage.input)], ["Output", formatCompactTokens(usage.output)], ["Total", `${formatCompactTokens(total)} tokens`]]);
      if (usage.cacheRead || usage.cacheWrite) body.fields([["Cache", `${formatCompactTokens(usage.cacheRead ?? 0)} read · ${formatCompactTokens(usage.cacheWrite)} write`]]);
      if (context?.tokens != null) body.fields([["Context", `${formatCompactTokens(context.tokens)} / ${formatCompactTokens(context.contextWindow)}${context.percent == null ? "" : ` (${context.percent.toFixed(1)}%)`}`]]);
      if (cost > 0) body.fields([["Cost", formatCost(cost)]]);
    }
    if (session?.systemPrompt?.trim()) body.disclosure("System prompt", () => body.text(session.systemPrompt, true));
  }
}
