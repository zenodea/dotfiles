import { type Component, HStack, ScrollView, type TuiMouseEvent, truncateToWidth, VStack, visibleWidth } from "@earendil-works/pi-tui";

const VIEWPORT_TUI = Symbol.for("@earendil-works/pi-tui/viewport");
const LAYOUT_NODE = Symbol.for("@earendil-works/pi-tui/layout-node");

export const WORKSPACE_WIDE_COLUMNS = 120;
export const WORKSPACE_SIDEBAR_COLUMNS = 38;

type LayoutEntry = {
  component: Component;
  basis?: number | "auto";
  grow?: number;
  shrink?: number;
  minSize?: number;
  maxSize?: number;
  visible?: (viewport: { width: number; height: number }) => boolean;
};

type StackNode = {
  type: "vstack" | "hstack";
  entries: readonly LayoutEntry[];
  gap: number;
  align: "stretch" | "start" | "center" | "end";
};

type ScrollNode = {
  type: "scroll";
  component: Component;
  state: { primary: boolean };
};

type RuntimeViewportTui = {
  mode: string;
  terminal: { columns: number; rows: number };
  layoutRoot?: Component;
  setLayoutRoot(component: Component | undefined): void;
  requestRender(): void;
  getFocusedComponent?(): Component | null;
  focusedComponent?: unknown;
  setFocus?(component: Component | null): void;
  [VIEWPORT_TUI]?: true;
};

function layoutNode(component: Component): StackNode | ScrollNode | undefined {
  try {
    const candidate = component as Component & { [LAYOUT_NODE]?: () => StackNode | ScrollNode };
    return candidate[LAYOUT_NODE]?.();
  } catch {
    return undefined;
  }
}

/** Read the stable UI proxy without assuming its current renderer mode. */
function runtimeTui(value: unknown): RuntimeViewportTui | undefined {
  if (!value || typeof value !== "object") return undefined;
  const candidate = value as Partial<RuntimeViewportTui>;
  if (
    typeof candidate.mode !== "string"
    || typeof candidate.setLayoutRoot !== "function"
    || typeof candidate.requestRender !== "function"
    || !candidate.terminal
  ) return undefined;
  return candidate as RuntimeViewportTui;
}

function isFullscreenViewport(tui: RuntimeViewportTui): boolean {
  return tui.mode === "fullscreen" && tui[VIEWPORT_TUI] === true;
}

/**
 * Shape-guarded adapter around pi 0.85's fullscreen chat layout.
 *
 * The stable UI object is a proxy whose renderer/root can change underneath it.
 * `sync` therefore validates mode and root before every mutation. A transition
 * forgets stale roots instead of restoring them into the replacement renderer.
 */
export class WorkspaceLayout {
  private tui: RuntimeViewportTui | undefined;
  private nativeRoot: Component | undefined;
  private workspaceRoot: Component | undefined;
  private nativeTranscript: Component | undefined;
  private transcriptEntry: LayoutEntry | undefined;
  private dockEntry: LayoutEntry | undefined;
  private rootOptions: Pick<StackNode, "gap" | "align"> | undefined;
  private selectedDocument: Component | undefined;
  private drawerOpen = false;
  private installedWide: boolean | undefined;

  constructor(private sidebar: Component, private todos?: Component, private git?: Component) {}

  get attached(): boolean {
    return this.workspaceRoot !== undefined;
  }

  get isDrawerOpen(): boolean {
    return this.drawerOpen;
  }

  /** Only the installed root can authorize passive sidebar observations. */
  get isSidebarVisible(): boolean {
    return this.attached && this.tui !== undefined && isFullscreenViewport(this.tui)
      && this.tui.layoutRoot === this.workspaceRoot && (this.installedWide === true || this.drawerOpen);
  }

  /** Validate the current renderer, attach if possible, and select a document. */
  sync(tuiValue: unknown, document?: Component): boolean {
    const tui = runtimeTui(tuiValue);
    if (!tui) {
      this.forget();
      return false;
    }

    if (this.tui && this.tui !== tui) this.detach();

    if (this.workspaceRoot && this.tui === tui) {
      // Never restore a stale fullscreen root into a regular/reloaded renderer.
      if (!isFullscreenViewport(tui) || tui.layoutRoot !== this.workspaceRoot) {
        this.forget();
      } else {
        this.select(document);
        if (!this.workspaceRoot) return false;
        const wide = tui.terminal.columns >= WORKSPACE_WIDE_COLUMNS;
        // A transient root-write failure leaves the last successfully installed
        // workspace intact; retry on the next sync rather than exposing a split
        // ownership state.
        if (wide !== this.installedWide) this.installRoot();
        return true;
      }
    }

    if (!isFullscreenViewport(tui)) return false;
    const root = tui.layoutRoot;
    if (!root) return false;
    const rootNode = layoutNode(root);
    // Exactly two: accepting extras and rebuilding only two silently discards
    // host-owned layout regions.
    if (!rootNode || rootNode.type !== "vstack" || rootNode.entries.length !== 2) return false;
    const transcriptEntry = rootNode.entries[0];
    const transcriptNode = layoutNode(transcriptEntry.component);
    if (!transcriptNode || transcriptNode.type !== "scroll" || transcriptNode.state.primary !== true) return false;
    const dockEntry = rootNode.entries[1];
    if (!layoutNode(dockEntry.component)) return false;

    this.tui = tui;
    this.nativeRoot = root;
    this.nativeTranscript = transcriptEntry.component;
    this.transcriptEntry = transcriptEntry;
    this.dockEntry = dockEntry;
    this.rootOptions = { gap: rootNode.gap, align: rootNode.align };
    this.selectedDocument = document ?? transcriptEntry.component;
    if (!this.installRoot()) {
      this.forget();
      return false;
    }
    return true;
  }

  /** Backward-compatible name used by focused adapter tests. */
  attach(tuiValue: unknown, document?: Component): boolean {
    return this.sync(tuiValue, document);
  }

  /** Select Main by passing undefined; its exact native ScrollView is reused. */
  select(document?: Component): void {
    if (!this.attached) return;
    const next = document ?? this.nativeTranscript;
    if (!next || next === this.selectedDocument) return;
    const previous = this.selectedDocument;
    const tui = this.tui;
    const focused = tui?.getFocusedComponent ? tui.getFocusedComponent() : tui?.focusedComponent;
    const transferFocus = paneHasFocus(previous, focused);
    this.selectedDocument = next;
    if (!this.installRoot()) this.selectedDocument = previous;
    else if (transferFocus) tui?.setFocus?.(next);
  }

  /** Only the currently mounted primary pane/tree, never an arbitrary scroll view. */
  ownsFocus(focused: unknown): boolean {
    return this.attached && (paneHasFocus(this.selectedDocument, focused) || paneHasFocus(this.sidebar, focused));
  }

  /** Restore the actual host editor when typing leaves a focused inline pane. */
  focusEditor(): void {
    const find = (component: Component): Component | undefined => {
      const candidate = component as Component & { getText?: unknown; getCursor?: unknown; setText?: unknown; children?: Component[] };
      if (typeof candidate.getText === "function" && typeof candidate.getCursor === "function" && typeof candidate.setText === "function") return component;
      const node = layoutNode(component);
      const children = node?.type === "scroll" ? [node.component] : node?.entries.map(entry => entry.component) ?? candidate.children ?? [];
      for (const child of children) {
        const editor = find(child);
        if (editor) return editor;
      }
      return undefined;
    };
    const editor = this.dockEntry && find(this.dockEntry.component);
    if (editor) this.tui?.setFocus?.(editor);
  }

  setDrawerOpen(open: boolean): void {
    if (this.drawerOpen === open) return;
    const previous = this.drawerOpen;
    this.drawerOpen = open;
    if (this.attached && !this.installRoot()) this.drawerOpen = previous;
  }

  requestRender(): void {
    this.tui?.requestRender();
  }

  /** Explicit off/shutdown: restore only the exact fullscreen root we own. */
  detach(): void {
    const tui = this.tui;
    const nativeRoot = this.nativeRoot;
    if (
      tui
      && nativeRoot
      && isFullscreenViewport(tui)
      && tui.layoutRoot === this.workspaceRoot
    ) {
      try {
        tui.setLayoutRoot(nativeRoot);
      } catch {
        // UI teardown is best-effort; never replace another renderer's root.
      }
    }
    this.forget();
  }

  private forget(): void {
    this.tui = undefined;
    this.nativeRoot = undefined;
    this.workspaceRoot = undefined;
    this.nativeTranscript = undefined;
    this.transcriptEntry = undefined;
    this.dockEntry = undefined;
    this.rootOptions = undefined;
    this.selectedDocument = undefined;
    this.drawerOpen = false;
    this.installedWide = undefined;
  }

  private installRoot(): boolean {
    const tui = this.tui;
    const document = this.selectedDocument;
    const transcript = this.transcriptEntry;
    const dock = this.dockEntry;
    const rootOptions = this.rootOptions;
    if (!tui || !document || !transcript || !dock || !rootOptions || !isFullscreenViewport(tui)) return false;

    const wide = tui.terminal.columns >= WORKSPACE_WIDE_COLUMNS;
    // Reserve all three slots independently of content, providers and collapse.
    // The first two get fixed heights from the terminal size and only the
    // last one flexes, so a dock that grows or shrinks (working indicator,
    // queued message, taller editor) never moves a heading.
    const sidebar = new SidebarStack(([
      [this.sidebar, "Agents"],
      [this.git, "Git"],
      [this.todos, "Todos"],
    ] as const).map(([component, label]) => ({
      component: new SidebarSection(component, label, () => tui.terminal.rows),
      basis: 0,
      grow: 1,
      shrink: 1,
      minSize: 1,
    })), () => tui.terminal.rows);
    const contentRow = wide
      ? new HStack([
        { component: document, basis: 0, grow: 1, shrink: 1, minSize: 1 },
        {
          component: sidebar,
          basis: WORKSPACE_SIDEBAR_COLUMNS,
          grow: 0,
          shrink: 1,
          minSize: 24,
          maxSize: WORKSPACE_SIDEBAR_COLUMNS,
        },
      ], { gap: 1 })
      : new HStack([
        {
          component: document,
          basis: 0,
          grow: 1,
          shrink: 1,
          minSize: 1,
          visible: () => !this.drawerOpen,
        },
        {
          component: sidebar,
          basis: 0,
          grow: 1,
          shrink: 1,
          minSize: 1,
          visible: () => this.drawerOpen,
        },
      ]);
    const nextRoot = new VStack([
      { ...transcript, component: contentRow },
      { ...dock, component: dock.component },
    ], rootOptions);
    try {
      tui.setLayoutRoot(nextRoot);
      this.workspaceRoot = nextRoot;
      this.installedWide = wide;
      return true;
    } catch {
      return false;
    }
  }
}

/** Reset and fill every cell, including the remainder of a short content row. */
export function sidebarLine(text: string, width: number): string {
  if (text === "") return `\x1b[0m\x1b[0m${" ".repeat(Math.max(0, width))}`;
  // Measuring is far cheaper than truncating; most rows already fit.
  const fits = visibleWidth(text);
  const line = fits > width ? truncateToWidth(text, width) : text;
  return `\x1b[0m${line}\x1b[0m${" ".repeat(Math.max(0, width - (fits > width ? visibleWidth(line) : fits)))}`;
}

/** A one-row label/rule without extra helper text or vertical padding. */
export function sidebarHeading(text: string, width: number): string {
  const remaining = width - visibleWidth(text);
  return sidebarLine(remaining > 0 ? `${text} ${"─".repeat(remaining - 1)}` : text, width);
}

/** Rows the dock takes at rest: spacer, three-row editor, footer. */
const SIDEBAR_DOCK_ROWS = 5;
/** Rows for every section but the last, given the sidebar's resting height. Git is its one-line summary plus a blank row. */
const SIDEBAR_SIZES: ((height: number) => number)[] = [height => Math.floor(height * 2 / 5), () => 2];

/** A VStack whose leading sections are sized from the terminal, not from the space left over. */
class SidebarStack extends VStack {
  private sized: { rows: number; node: StackNode } | undefined;

  constructor(entries: LayoutEntry[], private rows: () => number) {
    super(entries);
  }

  [LAYOUT_NODE](): StackNode {
    const node = (VStack.prototype as unknown as { [LAYOUT_NODE](): StackNode })[LAYOUT_NODE].call(this);
    const rows = this.rows();
    // Keep entry identity stable between frames; rebuild only on resize.
    if (this.sized?.rows !== rows || this.sized.node.entries.length !== node.entries.length) {
      const height = Math.max(node.entries.length, rows - SIDEBAR_DOCK_ROWS);
      this.sized = { rows, node: { ...node, entries: node.entries.map((entry, index) => {
        const size = SIDEBAR_SIZES[index];
        return size === undefined ? entry : { ...entry, basis: Math.max(1, size(height)), grow: 0 };
      }) } };
    }
    return this.sized.node;
  }
}

/** A bounded scroller plus painted slack; blank rows never become scrollback. */
class SidebarSection extends VStack {
  constructor(private content: Component | undefined, label: string, rows: () => number) {
    const heading = (content as (Component & { [SIDEBAR_HEADING]?: Component }) | undefined)?.[SIDEBAR_HEADING];
    super([
      ...(heading ? [{ component: heading, basis: "auto" as const, shrink: 0, minSize: 1 }] : []),
      { component: content ?? { render: width => [sidebarHeading(` ${label}`, width)], invalidate: () => {} }, basis: "auto", shrink: 1, minSize: heading ? 0 : 1 },
      { component: { render: width => Array.from({ length: rows() }, () => sidebarLine("", width)), invalidate: () => {} }, basis: 0, grow: 1, minSize: 0 },
    ]);
  }

  override handleMouse(event: TuiMouseEvent): ReturnType<VStack["handleMouse"]> {
    // Pi 0.85 can fall back to the primary transcript at a contain boundary.
    // Consume wheel input over the entire slot, including its painted slack.
    if (event.type !== "wheel") return undefined;
    if (this.content instanceof ScrollView) this.content.scrollBy(event.wheelDelta ?? 0);
    return { handled: true, focus: false, target: {
      component: this, originX: event.screenX - event.x, originY: event.screenY - event.y, width: event.width, height: event.height,
    } };
  }
}

/** Match a pane or its direct document; do not claim descendants of host dialogs. */
function paneHasFocus(pane: Component | undefined, focused: unknown): boolean {
  if (!pane || !focused) return false;
  if (pane === focused) return true;
  const node = layoutNode(pane);
  if (node?.type === "scroll") return paneHasFocus(node.component, focused);
  return node?.entries.some(entry => paneHasFocus(entry.component, focused)) ?? false;
}

/**
 * pi 0.85's ScrollView inherits Container's unscrolled mouse dispatch. Translate
 * only at this viewport boundary. Native layout dispatch reaches the document
 * directly in content coordinates and does not pass through this method first.
 * Leave wheel events unhandled for the renderer's scroll/overscroll routing.
 */
export class WorkspaceScrollView extends ScrollView {
  override handleMouse(event: TuiMouseEvent): ReturnType<ScrollView["handleMouse"]> {
    const width = this.getContentWidth(event.width);
    if (event.type === "wheel" || event.x < 0 || event.x >= width || event.y < 0 || event.y >= event.height) return undefined;
    return super.handleMouse({ ...event, width, y: event.y + this.scrollTop, height: event.height + this.scrollTop });
  }
}

const SIDEBAR_HEADING = Symbol("sidebar-heading");

/**
 * Split a sidebar document into a fixed heading (its row 0) and a ScrollView
 * over the remaining rows, so neither the heading nor the scrollbar's first
 * cell moves with the content. Mouse rows are mapped back to document rows.
 */
export function createSidebarScrollView(document: Component): ScrollView {
  const body = new Proxy(document, {
    get(target, property) {
      if (property === "render") return (width: number): string[] => target.render(width).slice(1);
      const value = Reflect.get(target, property, target);
      if (property === "handleMouse" && typeof value === "function") {
        return (event: TuiMouseEvent) => value.call(target, { ...event, y: event.y + 1 });
      }
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
  const scroll = new WorkspaceScrollView(body, { follow: "none", primary: false, overscroll: "contain", scrollbar: "auto" });
  const heading: Component = {
    render: width => document.render(width).slice(0, 1),
    handleMouse: event => event.y === 0 ? document.handleMouse?.(event) : undefined,
    invalidate: () => {},
  };
  (scroll as ScrollView & { [SIDEBAR_HEADING]?: Component })[SIDEBAR_HEADING] = heading;
  return scroll;
}

/** A retained primary ScrollView for one agent document. */
export function createAgentScrollView(document: Component): ScrollView {
  return new WorkspaceScrollView(document, {
    follow: "end",
    primary: true,
    overscroll: "chain",
    scrollbar: "auto",
  });
}
