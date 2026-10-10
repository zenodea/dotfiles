import { isDeepStrictEqual } from "node:util";
import type { AssistantMessage } from "@earendil-works/pi-ai";
import {
  type AgentSession,
  type AgentSessionEvent,
  AssistantMessageComponent,
  BashExecutionComponent,
  BranchSummaryMessageComponent,
  CompactionSummaryMessageComponent,
  CustomMessageComponent,
  createBashToolDefinition,
  createEditToolDefinition,
  createFindToolDefinition,
  createGrepToolDefinition,
  createLsToolDefinition,
  createPowerShellToolDefinition,
  createReadToolDefinition,
  createWriteToolDefinition,
  getMarkdownTheme,
  type MarkdownTransformer,
  parseSkillBlock,
  SkillInvocationMessageComponent,
  ToolExecutionComponent,
  UserMessageComponent,
} from "@earendil-works/pi-coding-agent";
import { type Component, Container, getCapabilities, type MarkdownTheme, Spacer, stripTerminalSequences, Text, type TUI, type TuiMouseEvent, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import type { AgentRecord } from "../types.js";

type Message = AgentSession["messages"][number];
type ToolResult = Parameters<ToolExecutionComponent["updateResult"]>[0];
type Expandable = Component & { setExpanded(expanded: boolean): void };

const builtinDefinitions = {
  bash: createBashToolDefinition,
  powershell: createPowerShellToolDefinition,
  read: createReadToolDefinition,
  edit: createEditToolDefinition,
  write: createWriteToolDefinition,
  find: createFindToolDefinition,
  grep: createGrepToolDefinition,
  ls: createLsToolDefinition,
};

/** Local presentation objects, never an event-bus payload. Sort by timestamp,
 * then agent attribution and order when merging independent activity adapters.
 * Call getEntries(viewportWidth) before rendering entries in a workflow pane. */
export interface NativeActivityEntry {
  readonly key: string;
  readonly timestamp: number;
  readonly order: number;
  readonly component: Component;
}

type Entry = { key: string; timestamp: number; order: number; component: Component };
type MessageView = {
  key: string;
  message?: Message;
  streaming: boolean;
  dirty: boolean;
  entries: Entry[];
  assistants: Map<number, { entry: Entry; signature: string }>;
};
type ToolView = {
  entry: Entry & { component: ToolExecutionComponent };
  args: unknown;
  started: boolean;
  argsComplete: boolean;
  result?: ToolResult;
  partial: boolean;
  fromEvent: boolean;
};

/** Native Main transcript components over a retained child session. Does not
 * execute tools, change session settings, read transcript files, or own keys.
 * sync() detects late attachment/replacement; dispose() permanently detaches. */
export class NativeAgentActivity implements Component {
  private session?: AgentSession;
  private unsubscribe?: () => void;
  private disposed = false;
  private generation = 0;
  private sequence = 0;
  private identities = new WeakMap<Message, MessageView>();
  private views = new Set<MessageView>();
  private liveView?: MessageView;
  private tools = new Map<string, ToolView>();
  private entries: Entry[] = [];
  private container = new Container();
  private empty = new Text("Waiting for the agent session…", 1, 1);
  private dirty = true;
  private history?: AgentSession["messages"];
  private historyLength = -1;
  private historyFirst?: Message;
  private historyLast?: Message;
  private stream?: Message;
  private expanded = false;
  private hideThinking = false;
  private thinkingChosen = false;
  private markdownTheme?: MarkdownTheme;
  private transformers: readonly MarkdownTransformer[] = [];
  private outputPad = 1;
  private imageWidth = 60;
  private showImages = false;

  constructor(private record: AgentRecord, private readonly ui: TUI, private readonly onChange: () => void) {
    this.sync();
  }

  setRecord(record: AgentRecord): void {
    if (this.disposed) return;
    if (record.id !== this.record.id) {
      this.detach();
      this.thinkingChosen = false;
      this.expanded = false;
    }
    this.record = record;
    this.sync();
    this.onChange();
  }

  /** In-memory reconciliation only. Safe to call on manager progress ticks. */
  sync(): void {
    if (this.disposed) return;
    if (this.session !== this.record.session) {
      this.detach();
      this.session = this.record.session;
      this.generation++;
      if (this.session) {
        const settings = this.session.settingsManager;
        if (!this.thinkingChosen) this.hideThinking = settings.getHideThinkingBlock();
        this.markdownTheme = { ...getMarkdownTheme(), codeBlockIndent: settings.getCodeBlockIndent() };
        this.transformers = this.session.extensionRunner.getMarkdownTransformers();
        this.outputPad = settings.getOutputPad();
        this.configureImages(this.ui.terminal.columns);
        this.unsubscribe = this.session.subscribe(event => this.onEvent(event));
      }
    }
    const session = this.session;
    if (!session) {
      this.empty.setText(this.record.status === "queued" || this.record.status === "running"
        ? "Waiting for the agent session…"
        : "Agent session unavailable; native activity cannot be reconstructed from a result preview.");
      return;
    }
    const messages = session.messages;
    const stream = session.state.streamingMessage;
    if (!this.dirty && this.history === messages && this.historyLength === messages.length
      && this.historyFirst === messages[0] && this.historyLast === messages.at(-1) && this.stream === stream) return;
    // Compaction/replacement can remove the calls behind event-only tool rows.
    if (this.history && (messages.length < this.historyLength || (this.historyFirst && messages[0] !== this.historyFirst))) {
      for (const tool of this.tools.values()) tool.fromEvent = false;
    }
    this.history = messages;
    this.historyLength = messages.length;
    this.historyFirst = messages[0];
    this.historyLast = messages.at(-1);
    this.stream = stream;
    this.dirty = false;
    const entries: Entry[] = [];
    const seen = new Set<MessageView>();
    const usedTools = new Set<string>();
    const append = (message: Message, streaming: boolean): void => {
      if (message.role === "toolResult") {
        const tool = this.tool(message.toolCallId, message.toolName, {}, message.timestamp);
        this.applyResult(tool, message, false);
        tool.fromEvent = false;
        if (!usedTools.has(message.toolCallId)) entries.push(tool.entry);
        usedTools.add(message.toolCallId);
        return;
      }
      const view = this.view(message, streaming);
      if (seen.has(view)) return; // Some hosts retain the last partial until after message_end.
      seen.add(view);
      this.updateView(view, message, streaming);
      entries.push(...view.entries);
      if (message.role === "assistant") for (const block of message.content) {
        if (block.type === "toolCall") usedTools.add(block.id);
      }
    };
    for (const message of messages) append(message, false);
    if (stream) append(stream, true);
    else this.liveView = undefined;
    for (const [id, tool] of this.tools) {
      if (!usedTools.has(id)) {
        if (tool.fromEvent) entries.push(tool.entry);
        else this.tools.delete(id);
      }
    }
    for (const view of this.views) if (!seen.has(view)) this.views.delete(view);
    for (let i = 0; i < entries.length; i++) entries[i].order = i;
    if (entries.length !== this.entries.length || entries.some((entry, i) => entry !== this.entries[i])) {
      this.entries = entries;
      this.container.clear();
      for (const entry of entries) this.container.addChild(entry.component);
    }
  }

  getEntries(viewportWidth = this.ui.terminal.columns): readonly NativeActivityEntry[] {
    this.sync();
    this.configureImages(viewportWidth);
    return this.entries;
  }

  render(width: number): string[] {
    if (this.disposed || width <= 0) return [];
    this.getEntries(width);
    if (this.entries.length === 0) {
      if (this.session) this.empty.setText("No displayable messages in the agent session yet.");
      return this.empty.render(width).map(line => truncateToWidth(line, width));
    }
    // Native renderers own their caches and asynchronous invalidations. Do not
    // cache their rendered lines: custom renderers may requestRender directly.
    // This runs over the whole transcript every frame, and truncateToWidth is
    // ~30x the cost of measuring, so only pay for it on lines that overflow.
    return this.container.render(width).map(line => visibleWidth(line) > width ? truncateToWidth(line, width) : line);
  }

  handleMouse(event: TuiMouseEvent): ReturnType<Container["handleMouse"]> {
    if (this.disposed) return undefined;
    const result = this.container.handleMouse(event);
    if (result?.handled) this.onChange();
    return result;
  }

  setExpanded(expanded: boolean): void {
    this.expanded = expanded;
    for (const view of this.views) for (const entry of view.entries) {
      if (!(entry.component instanceof ToolExecutionComponent) && "setExpanded" in entry.component) {
        (entry.component as Expandable).setExpanded(expanded);
      }
    }
    for (const tool of this.tools.values()) tool.entry.component.setExpanded(expanded);
    this.onChange();
  }

  toggleExpanded(): void { this.setExpanded(!this.expanded); }

  setHideThinking(hide: boolean): void {
    this.hideThinking = hide;
    this.thinkingChosen = true;
    for (const view of this.views) for (const part of view.assistants.values()) {
      (part.entry.component as AssistantMessageComponent).setHideThinkingBlock(hide);
    }
    this.onChange();
  }

  toggleThinking(): void { this.setHideThinking(!this.hideThinking); }

  invalidate(): void { this.container.invalidate(); this.empty.invalidate(); }

  dispose(): void {
    this.disposed = true;
    this.detach();
  }

  private detach(): void {
    this.unsubscribe?.();
    this.unsubscribe = undefined;
    this.session = undefined;
    this.identities = new WeakMap();
    this.views.clear();
    this.liveView = undefined;
    this.tools.clear();
    this.entries = [];
    this.container.clear();
    this.history = undefined;
    this.historyLength = -1;
    this.historyFirst = undefined;
    this.historyLast = undefined;
    this.stream = undefined;
    this.dirty = true;
  }

  private view(message: Message, streaming: boolean): MessageView {
    let view = this.identities.get(message);
    if (!view) {
      view = streaming && this.liveView?.message?.role === message.role ? this.liveView : {
        key: JSON.stringify([this.record.id, this.generation, ++this.sequence]),
        streaming,
        dirty: true,
        entries: [],
        assistants: new Map(),
      };
      this.identities.set(message, view);
    }
    if (streaming) this.liveView = view;
    this.views.add(view);
    return view;
  }

  private updateView(view: MessageView, message: Message, streaming: boolean): void {
    if (view.message === message && view.streaming === streaming && !view.dirty) return;
    view.message = message;
    view.streaming = streaming;
    view.dirty = false;
    const timestamp = message.timestamp ?? this.record.startedAt;
    const entry = (component: Component, suffix = ""): Entry => ({ key: view.key + suffix, timestamp, order: 0, component });
    if (message.role === "assistant") {
      const entries: Entry[] = [];
      const toolMarker = message.content.find(block => block.type === "toolCall");
      const parts = new Set<number>();
      let start = 0;
      const assistantPart = (end: number): void => {
        const content = message.content.slice(start, end).map(block => block.type === "text"
          ? { ...block, text: stripTerminalSequences(block.text) }
          : block.type === "thinking" ? { ...block, thinking: stripTerminalSequences(block.thinking) } : block);
        // A tool marker is deliberately retained: native assistant components
        // suppress duplicate abort/error chrome when the tool row owns it.
        if (toolMarker) content.push(toolMarker);
        const projected: AssistantMessage = toolMarker ? { ...message, content,
          stopReason: end === message.content.length ? message.stopReason : "toolUse" }
          : { ...message, content, errorMessage: message.stopReason === "aborted" ? this.abortMessage() : message.errorMessage };
        const signature = JSON.stringify([content, projected.stopReason, projected.errorMessage, streaming]);
        let part = view.assistants.get(start);
        if (!part) {
          part = { entry: entry(new AssistantMessageComponent(undefined, this.hideThinking, this.markdownTheme,
            undefined, this.outputPad, this.transformers), `:assistant:${start}`), signature: "" };
          view.assistants.set(start, part);
        }
        if (part.signature !== signature) {
          (part.entry.component as AssistantMessageComponent).updateContent(projected, streaming);
          part.signature = signature;
        }
        parts.add(start);
        entries.push(part.entry);
      };
      for (let i = 0; i < message.content.length; i++) {
        const block = message.content[i];
        if (block.type !== "toolCall") continue;
        if (i > start) assistantPart(i);
        const tool = this.tool(block.id, block.name, block.arguments, timestamp);
        if (tool.args !== block.arguments || streaming) {
          tool.args = block.arguments;
          tool.entry.component.updateArgs(block.arguments);
        }
        if (!streaming && (message.stopReason === "error" || message.stopReason === "aborted") && !tool.result) {
          this.applyResult(tool, { content: [{ type: "text", text: message.stopReason === "aborted"
            ? this.abortMessage() : message.errorMessage || "Error" }], isError: true }, false);
        }
        entries.push(tool.entry);
        start = i + 1;
      }
      if (start < message.content.length || !toolMarker || message.stopReason === "length") assistantPart(message.content.length);
      for (const index of view.assistants.keys()) if (!parts.has(index)) view.assistants.delete(index);
      view.entries = entries;
      return;
    }
    let component: Component | undefined;
    switch (message.role) {
      case "user": {
        const text = stripTerminalSequences(typeof message.content === "string" ? message.content
          : message.content.filter(block => block.type === "text").map(block => block.text).join(""));
        if (!text) break; // Main also renders only text from user messages.
        const skill = parseSkillBlock(text);
        if (!skill) component = new UserMessageComponent(text, this.markdownTheme, this.outputPad, this.transformers);
        else {
          const group = new Container();
          const invocation = new SkillInvocationMessageComponent(skill, this.markdownTheme);
          invocation.setExpanded(this.expanded);
          group.addChild(invocation);
          if (skill.userMessage) {
            group.addChild(new Spacer(1));
            group.addChild(new UserMessageComponent(skill.userMessage, this.markdownTheme, this.outputPad, this.transformers));
          }
          component = Object.assign(group, { setExpanded: (expanded: boolean) => invocation.setExpanded(expanded) });
        }
        break;
      }
      case "custom":
        if (message.display) component = new CustomMessageComponent(message,
          this.session?.extensionRunner.getMessageRenderer(message.customType), this.markdownTheme, this.outputPad);
        break;
      case "compactionSummary": component = new CompactionSummaryMessageComponent(message, this.markdownTheme); break;
      case "branchSummary": component = new BranchSummaryMessageComponent(message, this.markdownTheme); break;
      case "bashExecution": {
        const bash = new BashExecutionComponent(message.command, this.ui, message.excludeFromContext);
        if (message.output) bash.appendOutput(message.output);
        bash.setComplete(message.exitCode, message.cancelled, undefined, message.fullOutputPath);
        component = bash;
        break;
      }
    }
    if (component && "setExpanded" in component) (component as Expandable).setExpanded(this.expanded);
    view.entries = component ? [entry(component)] : [];
  }

  private tool(id: string, name: string, args: unknown, timestamp: number): ToolView {
    const existing = this.tools.get(id);
    if (existing) return existing;
    const session = this.session!;
    const cwd = session.sessionManager.getCwd();
    const definition = session.getToolDefinition(name);
    // Same per-slot native inheritance as Main, through public factories only.
    const builtin = Object.hasOwn(builtinDefinitions, name) && (!definition?.renderCall || !definition?.renderResult)
      ? builtinDefinitions[name as keyof typeof builtinDefinitions](cwd) : undefined;
    const base = builtin ? { ...definition, renderCall: definition?.renderCall ?? builtin.renderCall,
      renderResult: definition?.renderResult ?? builtin.renderResult } : definition;
    const runner = session.extensionRunner as { resolveToolRenderers?: (toolName: string, next: () => typeof base) => typeof base } | undefined;
    const renderers = runner?.resolveToolRenderers?.(name, () => base) ?? base;
    const component = new ToolExecutionComponent(name, id, args, { showImages: this.showImages, imageWidthCells: this.imageWidth },
      renderers, this.ui, cwd);
    component.setExpanded(this.expanded);
    const tool: ToolView = { entry: { key: JSON.stringify([this.record.id, this.generation, "tool", id]), timestamp, order: 0, component },
      args, started: false, argsComplete: false, partial: true, fromEvent: false };
    this.tools.set(id, tool);
    return tool;
  }

  private applyResult(tool: ToolView, result: ToolResult, partial: boolean): void {
    const normalized: ToolResult = { content: result.content, details: result.details, isError: result.isError };
    if (tool.partial === partial && isDeepStrictEqual(tool.result, normalized)) return;
    tool.result = normalized;
    tool.partial = partial;
    tool.entry.component.updateResult(normalized, partial);
  }

  private abortMessage(): string {
    const attempt = this.session?.retryAttempt ?? 0;
    return attempt > 0 ? `Aborted after ${attempt} retry attempt${attempt > 1 ? "s" : ""}` : "Operation aborted";
  }

  private onEvent(event: AgentSessionEvent): void {
    if (this.disposed) return;
    if (event.type === "message_start" || event.type === "message_update" || event.type === "message_end") {
      if (event.type !== "message_start" && this.liveView?.message?.role === event.message.role) {
        this.identities.set(event.message, this.liveView);
      }
      const view = this.identities.get(event.message);
      if (view) view.dirty = true;
    }
    this.dirty = true;
    this.sync();
    if (event.type === "message_end" && event.message.role === "assistant"
      && event.message.stopReason !== "aborted" && event.message.stopReason !== "error") {
      for (const block of event.message.content) if (block.type === "toolCall") {
        const tool = this.tools.get(block.id);
        if (tool && !tool.argsComplete && !tool.result) {
          tool.argsComplete = true;
          // Native edit preview may perform async IO here, on the live event,
          // never while replaying/rendering historical transcript messages.
          tool.entry.component.setArgsComplete();
        }
      }
    }
    if (event.type === "tool_execution_start" || event.type === "tool_execution_update" || event.type === "tool_execution_end") {
      const tool = this.tool(event.toolCallId, event.toolName, "args" in event ? event.args : {}, Date.now());
      tool.fromEvent = true;
      if ("args" in event && tool.args !== event.args) {
        tool.args = event.args;
        tool.entry.component.updateArgs(event.args);
      }
      if (!tool.started) { tool.started = true; tool.entry.component.markExecutionStarted(); }
      if (event.type === "tool_execution_update") this.applyResult(tool, { ...event.partialResult, isError: false }, true);
      if (event.type === "tool_execution_end") this.applyResult(tool, { ...event.result, isError: event.isError }, false);
      this.dirty = true;
      this.sync();
    }
    this.onChange();
  }

  private configureImages(width: number): void {
    if (!this.session) return;
    const settings = this.session.settingsManager;
    const imageWidth = Math.max(1, Math.min(settings.getImageWidthCells(), Math.floor(width) - 2));
    const showImages = settings.getShowImages() && !!getCapabilities().images;
    if (imageWidth === this.imageWidth && showImages === this.showImages) return;
    this.imageWidth = imageWidth;
    this.showImages = showImages;
    for (const tool of this.tools.values()) {
      tool.entry.component.setImageWidthCells(imageWidth);
      tool.entry.component.setShowImages(showImages);
    }
  }
}
