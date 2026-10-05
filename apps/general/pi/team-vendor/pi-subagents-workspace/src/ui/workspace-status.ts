import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { type Component, stripTerminalSequences, type TuiMouseEvent, type TuiMouseEventResult, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import type { Theme } from "./agent-widget.js";
import { type GitCommandRunner, type GitWorkspaceSnapshot, GitWorkspaceTracker } from "./workspace-git.js";
import { sidebarHeading, sidebarLine } from "./workspace-layout.js";

export const BACKGROUND_SIDEBAR_REQUEST = "background:sidebar:request:v1";
const REFRESH_MS = 3000;
const JOB_LIMIT = 100;
const JOB_STATES = ["starting", "running", "stopping", "stopped", "exited", "failed", "timed_out", "lost", "cancelled"] as const;
export type BackgroundJob = {
  jobId: string;
  name: string;
  state: typeof JOB_STATES[number];
  createdAt: number;
  startedAt?: number;
  endedAt?: number;
  exitCode?: number | null;
  signal?: string | null;
  stopReason?: string;
};
export type BackgroundSnapshot = {
  state: "idle" | "ready" | "unavailable";
  jobs: readonly BackgroundJob[];
  hasMore: boolean;
  error?: string;
};
export type BackgroundSidebarProvider = { read(): Promise<BackgroundSnapshot> };
export type WorkspaceRootContext = { cwd: string; sessionManager: object };

/** Data is terminal text, not ANSI, hyperlinks, bidi commands, or extra rows. */
export function statusText(text: string): string {
  return stripTerminalSequences(text).replace(/[\x00-\x1f\x7f-\x9f\u2028\u2029\u202a-\u202e\u2066-\u2069]/g, " ");
}

function finiteTime(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0;
}

/** Copy the small v1 data contract; never retain donor objects or capabilities. */
function copyBackground(value: unknown): BackgroundSnapshot {
  if (!value || typeof value !== "object") throw new Error("Invalid background snapshot");
  const data = value as Partial<BackgroundSnapshot>;
  if (!["idle", "ready", "unavailable"].includes(data.state ?? "") || !Array.isArray(data.jobs) || typeof data.hasMore !== "boolean") {
    throw new Error("Invalid background snapshot");
  }
  if (data.error !== undefined && typeof data.error !== "string") throw new Error("Invalid background error");
  if (data.state === "unavailable") return { state: "unavailable", jobs: [], hasMore: false, error: statusText(data.error ?? "Observation unavailable").slice(0, 512) };
  if (data.state === "idle" && data.jobs.length) throw new Error("Invalid idle background snapshot");
  const jobs = data.jobs.slice(0, JOB_LIMIT).map((item: unknown): BackgroundJob => {
    if (!item || typeof item !== "object") throw new Error("Invalid background job");
    const job = item as BackgroundJob;
    if (typeof job.jobId !== "string" || typeof job.name !== "string" || !JOB_STATES.includes(job.state)
      || !finiteTime(job.createdAt) || (job.startedAt !== undefined && !finiteTime(job.startedAt))
      || (job.endedAt !== undefined && !finiteTime(job.endedAt))
      || (job.exitCode !== undefined && job.exitCode !== null && !Number.isSafeInteger(job.exitCode))
      || (job.signal !== undefined && job.signal !== null && typeof job.signal !== "string")
      || (job.stopReason !== undefined && typeof job.stopReason !== "string")) throw new Error("Invalid background job");
    return {
      jobId: statusText(job.jobId).slice(0, 512), name: statusText(job.name).slice(0, 1024), state: job.state,
      createdAt: job.createdAt, startedAt: job.startedAt, endedAt: job.endedAt, exitCode: job.exitCode,
      signal: typeof job.signal === "string" ? statusText(job.signal).slice(0, 128) : job.signal,
      stopReason: job.stopReason === undefined ? undefined : statusText(job.stopReason).slice(0, 512),
    };
  });
  return { state: data.state as "idle" | "ready", jobs, hasMore: data.hasMore || data.jobs.length > JOB_LIMIT };
}

/** Passive discovery/read only. There is deliberately no background package import. */
export class BackgroundWorkspaceTracker {
  private current: BackgroundSnapshot | undefined;
  private root: WorkspaceRootContext | undefined;
  private generation = 0;
  private lastRefresh: number | undefined;
  private inFlight = false;
  private disposed = false;

  constructor(private events: ExtensionAPI["events"] | undefined, private onChange: () => void,
    private isCurrent: (root: WorkspaceRootContext) => boolean = () => true) {}

  get snapshot(): BackgroundSnapshot | undefined { return this.current; }

  refresh(root: WorkspaceRootContext, now = Date.now()): void {
    if (this.disposed) return;
    if (this.root?.sessionManager !== root.sessionManager || this.root.cwd !== root.cwd) {
      this.pause();
      this.root = { ...root };
    }
    if (this.inFlight || (this.lastRefresh !== undefined && now >= this.lastRefresh && now - this.lastRefresh < REFRESH_MS)) return;
    this.lastRefresh = now;
    const generation = this.generation;
    let provider: BackgroundSidebarProvider | undefined;
    let accepting = true;
    try {
      // Offers are synchronous and exact-owner-scoped. Re-discover every TTL so
      // late extension loading, unload, or a revoked provider cannot leave jobs.
      this.events?.emit(BACKGROUND_SIDEBAR_REQUEST, { sessionManager: root.sessionManager, respond: (offer: unknown) => {
        if (!accepting || provider || !offer || typeof offer !== "object") return;
        if (typeof (offer as BackgroundSidebarProvider).read === "function") provider = offer as BackgroundSidebarProvider;
      } });
    } catch {
      if (generation === this.generation && this.isCurrent(root)) this.setSnapshot({ state: "unavailable", jobs: [], hasMore: false, error: "Background discovery failed" });
      return;
    } finally { accepting = false; }
    if (generation !== this.generation || !this.isCurrent(root)) return;
    if (!provider) { this.setSnapshot(undefined); return; }
    this.inFlight = true;
    void this.read(provider, root, generation);
  }

  pause(): void {
    this.generation++;
    this.root = undefined;
    this.lastRefresh = undefined;
    // A provider read cannot be cancelled through v1. Keep its slot occupied
    // until settlement, even when its result has already been fenced out.
    this.setSnapshot(undefined);
  }

  dispose(): void { this.disposed = true; this.pause(); }

  private setSnapshot(snapshot: BackgroundSnapshot | undefined): void {
    if (JSON.stringify(snapshot) === JSON.stringify(this.current)) return;
    this.current = snapshot;
    this.onChange();
  }

  private async read(provider: BackgroundSidebarProvider, root: WorkspaceRootContext, generation: number): Promise<void> {
    let snapshot: BackgroundSnapshot;
    try { snapshot = copyBackground(await provider.read()); }
    catch { snapshot = { state: "unavailable", jobs: [], hasMore: false, error: "Background observation failed" }; }
    this.inFlight = false;
    if (this.disposed || generation !== this.generation) return;
    if (!this.isCurrent(root)) { this.pause(); return; }
    this.setSnapshot(snapshot);
  }
}

type StatusSection = "background" | "git";
type StatusRow = { text: string; section?: StatusSection; color?: "dim" | "muted" | "warning" };

/** Pure row projection, shared by paint and header hit geometry. */
export function workspaceStatusRows(background: BackgroundSnapshot | undefined, git: GitWorkspaceSnapshot | undefined,
  collapsed: ReadonlySet<string> = new Set(), now = Date.now(), section?: StatusSection): StatusRow[] {
  const rows: StatusRow[] = [];
  if (section !== "git") {
    rows.push({ section: "background", text: ` ${collapsed.has("background") ? "▸" : "▾"} Background${!background || background.state === "unavailable" ? "" : ` (${background.jobs.length}${background.hasMore ? "+" : ""})`}` });
    if (!collapsed.has("background")) {
      if (background?.state === "unavailable") rows.push({ text: `   Unavailable · ${statusText(background.error ?? "Observation unavailable")}`, color: "warning" });
      for (const job of background?.jobs ?? []) {
        const live = job.state === "starting" || job.state === "running" || job.state === "stopping";
        const glyph = live ? "◐" : job.state === "exited" && job.exitCode === 0 ? "✓" : "○";
        rows.push({ text: `   ${glyph} ${statusText(job.name || job.jobId)}`, color: "muted" });
        const end = job.endedAt ?? (live ? now : undefined);
        const seconds = end === undefined ? undefined : Math.max(0, Math.floor((end - (job.startedAt ?? job.createdAt)) / 1000));
        const elapsed = seconds === undefined ? "—" : seconds < 60 ? `${seconds}s` : `${Math.floor(seconds / 60)}m${seconds % 60}s`;
        const state = job.state === "lost" ? "lost (unverified)" : job.state;
        rows.push({ text: `   ${state} · ${elapsed}${job.exitCode != null ? ` · exit ${job.exitCode}` : ""}`, color: job.state === "lost" ? "warning" : "dim" });
      }
      if (background?.hasMore) rows.push({ text: "   More in /background", color: "dim" });
    }
  }
  if (section !== "background") {
    // One line: branch and counts. The file list lives in `git status`, not here.
    const parts = [" Git"];
    if (git?.state === "ready") {
      const changed = git.files.filter(file => file.status !== "?" && file.status !== "??").length;
      parts.push(statusText(git.branch ?? "—"));
      if (changed) parts.push(`${changed} changed`);
      if (git.untracked) parts.push(`${git.untracked} new`);
      if (!changed && !git.untracked) parts.push("clean");
      if (git.ahead) parts.push(`↑${git.ahead}`);
    } else if (git?.state === "unavailable") parts.push(`unavailable · ${statusText(git.error ?? "Git could not be read")}`);
    rows.push({ section: "git", text: parts.join(" · ") });
  }
  return rows;
}

export interface WorkspaceStatusOptions {
  events?: ExtensionAPI["events"];
  runGit?: GitCommandRunner;
  getRootContext?: () => WorkspaceRootContext | undefined;
  isVisible: () => boolean;
  theme: () => Theme;
  onChange: () => void;
}

/** Shared passive observation lifecycle with independently mounted sections. */
export class WorkspaceStatus {
  readonly backgroundSection = this.section("background");
  readonly gitSection = this.section("git");
  private background: BackgroundWorkspaceTracker;
  private git: GitWorkspaceTracker | undefined;
  private root: WorkspaceRootContext | undefined;
  private collapsed = new Set<string>();
  private hits = new Map<StatusSection, number>();
  private lastPaint = "";
  private paintedTheme: unknown;
  private now = 0;
  private disposed = false;

  constructor(private options: WorkspaceStatusOptions) {
    this.background = new BackgroundWorkspaceTracker(options.events, () => this.changed(), root => this.isCurrent(root));
    if (options.runGit) this.git = new GitWorkspaceTracker(options.runGit, () => this.changed());
  }

  private isCurrent(root: WorkspaceRootContext): boolean {
    const current = this.options.getRootContext?.();
    return !this.disposed && this.options.isVisible() && current?.cwd === root.cwd && current.sessionManager === root.sessionManager;
  }

  /** Called by the existing host tick, never by construction or rendering. */
  refresh(now = Date.now()): void {
    if (this.disposed) return;
    const root = this.options.isVisible() ? this.options.getRootContext?.() : undefined;
    if (!root) { this.pause(); return; }
    if (root.cwd !== this.root?.cwd || root.sessionManager !== this.root?.sessionManager) {
      this.pause();
      this.root = { ...root };
    }
    this.now = now;
    this.background.refresh(root, now);
    this.git?.refresh(root.cwd, now);
    this.changed();
  }

  pause(): void {
    this.root = undefined;
    this.background.pause();
    this.git?.pause();
    this.hits.clear();
    this.lastPaint = "";
  }

  private changed(): void {
    if (!this.root) return;
    if (!this.isCurrent(this.root)) { this.pause(); return; }
    const signature = JSON.stringify(workspaceStatusRows(this.background.snapshot, this.git?.snapshot, this.collapsed, this.now));
    if (signature === this.lastPaint) return;
    this.lastPaint = signature;
    this.options.onChange();
  }

  private section(section: StatusSection): Component {
    return {
      render: width => this.renderSection(section, width),
      handleMouse: event => this.handleMouse(section, event),
      invalidate: () => {},
    };
  }

  private painted = new Map<string, { key: string; lines: string[]; hit: number | undefined }>();

  private renderSection(section: StatusSection, width: number): string[] {
    if (width <= 0) { this.hits.delete(section); return []; }
    const theme = this.options.theme();
    // Every frame asks for every row (a dirty repo is hundreds), so repaint only
    // when something a row depends on moved. `lastPaint` is the row signature
    // `changed()` keeps; the heading and the body ask at different widths.
    const key = `${this.root ? 1 : 0}:${this.lastPaint}`;
    const slot = `${section}:${width}`;
    const cached = this.painted.get(slot);
    if (cached && cached.key === key && this.paintedTheme === theme) {
      if (cached.hit === undefined) this.hits.delete(section);
      else this.hits.set(section, cached.hit);
      return cached.lines;
    }
    if (this.paintedTheme !== theme) { this.painted.clear(); this.paintedTheme = theme; }
    this.hits.delete(section);
    const lines = workspaceStatusRows(this.root ? this.background.snapshot : undefined, this.root ? this.git?.snapshot : undefined,
      this.collapsed, this.now, section).map(row => {
      const text = visibleWidth(row.text) > width ? truncateToWidth(row.text, width) : row.text;
      if (row.section) this.hits.set(section, visibleWidth(text));
      return row.section ? sidebarHeading(theme.bold(text), width) : sidebarLine(theme.fg(row.color ?? "muted", text), width);
    });
    // One slot per width, so the heading's ask does not evict the body's.
    if (this.painted.size > 16) this.painted.clear();
    this.painted.set(slot, { key, lines, hit: this.hits.get(section) });
    return lines;
  }

  private handleMouse(section: StatusSection, event: TuiMouseEvent): TuiMouseEventResult | undefined {
    if ((event.type !== "click" && event.type !== "press") || event.button !== "left" || event.y !== 0) return undefined;
    const width = this.hits.get(section);
    if (width === undefined || event.x < 0 || event.x >= width) return undefined;
    // Capture the header gesture rather than invoking native word selection
    // on a fast second click. Collapse still happens only on click/release.
    if (event.type === "press") return { handled: true, focus: false, render: false };
    if (this.collapsed.has(section)) this.collapsed.delete(section);
    else this.collapsed.add(section);
    this.changed();
    return { handled: true, focus: false };
  }

  dispose(): void { this.disposed = true; this.pause(); this.background.dispose(); this.git?.dispose(); }
}
