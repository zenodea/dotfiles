import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { stripTerminalSequences, type TuiMouseEvent, visibleWidth } from "@earendil-works/pi-tui";
import { describe, expect, it, vi } from "vitest";
import type { GitWorkspaceSnapshot } from "../src/ui/workspace-git.js";
import {
  BACKGROUND_SIDEBAR_REQUEST, type BackgroundJob, type BackgroundSidebarProvider, type BackgroundSnapshot,
  BackgroundWorkspaceTracker, statusText, type WorkspaceRootContext, WorkspaceStatus, workspaceStatusRows,
} from "../src/ui/workspace-status.js";

const root: WorkspaceRootContext = { cwd: "/root", sessionManager: {} };
const theme = { fg: (_color: string, text: string) => `\x1b[36m${text}\x1b[39m`, bold: (text: string) => `\x1b[1m${text}\x1b[22m` };
const job = (state: BackgroundJob["state"] = "running", extra: Partial<BackgroundJob> = {}): BackgroundJob => ({
  jobId: "job-1", name: "compile", state, createdAt: 1000, startedAt: 2000, ...extra,
});
const ready = (jobs: BackgroundJob[] = [job()]): BackgroundSnapshot => ({ state: "ready", jobs, hasMore: false });
function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (error: Error) => void;
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
const settle = async () => { for (let i = 0; i < 12; i++) await Promise.resolve(); };
function bus(offer?: BackgroundSidebarProvider) {
  let provider = offer;
  const emit = vi.fn((name: string, payload: unknown) => {
    if (name === BACKGROUND_SIDEBAR_REQUEST && provider) (payload as { respond(offer: unknown): void }).respond(provider);
  });
  return { events: { emit, on: vi.fn(() => () => {}) } satisfies ExtensionAPI["events"], emit,
    offer: (next?: BackgroundSidebarProvider) => { provider = next; } };
}
const git: GitWorkspaceSnapshot = { cwd: "/root", state: "ready", branch: "main", ahead: 4, untracked: 1, files: [
  { path: "src/new.ts", oldPath: "src/old.ts", status: "R.", added: 7, removed: 3, binary: false },
  { path: "picture.png", status: ".M", added: null, removed: null, binary: true },
  { path: "draft.txt", status: "?", added: null, removed: null, binary: false },
] };
const renderStatus = (status: WorkspaceStatus, width: number) => [...status.backgroundSection.render(width), ...status.gitSection.render(width)];
const plain = (background?: BackgroundSnapshot, snapshot?: GitWorkspaceSnapshot) => workspaceStatusRows(background, snapshot, new Set(), 65000).map(row => row.text).join("\n");

describe("workspace status rows", () => {
  it("summarizes Git on one line: branch, changed and new counts, commits ahead, and no file rows", () => {
    expect(plain(undefined, git)).toBe(" ▾ Background\n Git · main · 2 changed · 1 new · ↑4");
    expect(plain(undefined, { ...git, ahead: undefined })).toBe(" ▾ Background\n Git · main · 2 changed · 1 new");
    expect(plain(undefined, { ...git, ahead: 0 })).not.toContain("↑");
  });

  it("keeps empty/loading/absent sections header-only and retains unavailable errors", () => {
    expect(plain()).toBe(" ▾ Background\n Git");
    expect(plain({ state: "idle", jobs: [], hasMore: false })).toBe(" ▾ Background (0)\n Git");
    expect(plain({ state: "unavailable", jobs: [], hasMore: false, error: "offline" })).toContain("Unavailable · offline");
    expect(plain(undefined, { ...git, files: [], untracked: 0 })).toBe(" ▾ Background\n Git · main · clean · ↑4");
    for (const state of ["loading", "not-repository"] as const) expect(plain(undefined, { ...git, state })).toBe(" ▾ Background\n Git");
    expect(plain(undefined, { ...git, state: "unavailable", error: "git missing" })).toContain("Git · unavailable · git missing");
    expect(plain(ready(), git)).not.toMatch(/full browser|No background jobs|Not a Git repository|Clean working tree|Loading Git/);
  });

  it("renders each terminal state honestly, freezes known elapsed, and gives lost an unverified warning", () => {
    for (const state of ["starting", "running", "stopping"] as const) {
      expect(plain(ready([job(state)]))).toContain(`◐ compile\n   ${state} · 1m3s`);
    }
    for (const state of ["stopped", "exited", "failed", "timed_out", "lost", "cancelled"] as const) {
      const text = plain(ready([job(state, { endedAt: 5000, exitCode: state === "exited" ? 0 : 2 })]));
      expect(text).toContain(state === "lost" ? "lost (unverified) · 3s · exit 2" : `${state} · 3s · exit ${state === "exited" ? 0 : 2}`);
      expect(text).toContain(state === "exited" ? "✓ compile" : "○ compile");
      expect(text).not.toContain("/background");
    }
    expect(plain(ready([job("lost")]))).toContain("lost (unverified) · —");
    expect(plain(ready([job("exited", { exitCode: 1 })]))).not.toContain("✓");
    expect(plain({ ...ready(), hasMore: true })).toContain("More in /background");
  });

  it("removes terminal commands, OSC hyperlinks, C0/C1 and bidi controls without adding rows", () => {
    const unsafe = "a\x1b[2J\x1b]8;;https://bad\x07b\x1b]8;;\x07\n\r\t\x00\x9b\u202e界";
    const safe = statusText(unsafe);
    expect(safe).toBe("ab      界");
    const text = plain(ready([job("running", { name: unsafe })]), { ...git, branch: unsafe, files: [{ ...git.files[0], path: unsafe, oldPath: unsafe }] });
    expect(text).not.toMatch(/[\x00-\x09\x0b-\x1f\x7f-\x9f\u202e]/);
    expect(text).not.toContain("https:");
  });

  it.each([1, 24, 38, 80])("renders the real component within %i columns and has no render-time I/O", async width => {
    const read = vi.fn(async () => ready([job("running", { name: "\x1b[2J界".repeat(80) })]));
    const b = bus({ read });
    const runGit = vi.fn(async () => ({ stdout: "# branch.oid (initial)\0# branch.head long-界-branch\0? path\n\x1b[2J界\0", stderr: "", code: 0, killed: false }));
    const status = new WorkspaceStatus({ events: b.events, runGit, getRootContext: () => root, isVisible: () => true, theme: () => theme, onChange: vi.fn() });
    expect(renderStatus(status, width)).toHaveLength(2);
    expect(read).not.toHaveBeenCalled(); expect(runGit).not.toHaveBeenCalled();
    status.refresh(65000); await settle();
    const lines = renderStatus(status, width);
    expect(lines.length).toBeGreaterThan(3);
    expect(lines.every(line => visibleWidth(line) <= width && !stripTerminalSequences(line).includes("\n"))).toBe(true);
    const calls = [read.mock.calls.length, runGit.mock.calls.length];
    renderStatus(status, width); status.backgroundSection.invalidate(); status.gitSection.invalidate(); renderStatus(status, width);
    expect([read.mock.calls.length, runGit.mock.calls.length]).toEqual(calls);
    status.dispose();
  });
});

describe("passive Background consumer", () => {
  it("discovers only the exact root owner and retries absent/late providers once per TTL", async () => {
    const b = bus(); const changed = vi.fn(); const tracker = new BackgroundWorkspaceTracker(b.events, changed);
    tracker.refresh(root, 0); tracker.refresh(root, 200); tracker.refresh(root, 2999);
    expect(b.emit).toHaveBeenCalledTimes(1); expect(changed).not.toHaveBeenCalled();
    expect(b.emit.mock.calls[0][1]).toMatchObject({ sessionManager: root.sessionManager });
    const read = vi.fn(async () => ready()); b.offer({ read });
    tracker.refresh(root, 3000); await settle();
    expect(read).toHaveBeenCalledTimes(1); expect(tracker.snapshot?.jobs).toHaveLength(1);
    b.offer(); tracker.refresh(root, 6000);
    expect(tracker.snapshot).toBeUndefined();
    expect(changed).toHaveBeenCalledTimes(2);
    tracker.dispose();
  });

  it("accepts synchronous offers only and never falls back to a previous provider", () => {
    let respond!: (offer: unknown) => void;
    const read = vi.fn(async () => ready());
    const events = { emit: (_name: string, payload: unknown) => { respond = (payload as { respond: typeof respond }).respond; }, on: () => () => {} };
    const tracker = new BackgroundWorkspaceTracker(events, vi.fn());
    tracker.refresh(root, 0); respond({ read }); tracker.refresh(root, 200);
    expect(read).not.toHaveBeenCalled(); expect(tracker.snapshot).toBeUndefined();
    tracker.dispose();
  });

  it("coalesces in-flight reads and fences pause/session replacement/disposal without concurrent readers", async () => {
    const first = deferred<BackgroundSnapshot>(); const read = vi.fn(() => first.promise);
    const b = bus({ read }); const tracker = new BackgroundWorkspaceTracker(b.events, vi.fn());
    tracker.refresh(root, 0); tracker.refresh(root, 4000);
    tracker.pause(); const next = { cwd: "/next", sessionManager: {} };
    tracker.refresh(next, 8000);
    expect(read).toHaveBeenCalledTimes(1);
    first.resolve(ready()); await settle(); expect(tracker.snapshot).toBeUndefined();
    const last = deferred<BackgroundSnapshot>(); read.mockReturnValue(last.promise);
    tracker.refresh(next, 8200); expect(read).toHaveBeenCalledTimes(2);
    tracker.dispose(); last.resolve(ready()); await settle();
    tracker.refresh(next, 20000); expect(read).toHaveBeenCalledTimes(2); expect(tracker.snapshot).toBeUndefined();
  });

  it("fences an old owner even if the host has not ticked since its context changed", async () => {
    let current = root; const pending = deferred<BackgroundSnapshot>();
    const tracker = new BackgroundWorkspaceTracker(bus({ read: () => pending.promise }).events, vi.fn(), captured => captured.sessionManager === current.sessionManager);
    tracker.refresh(root, 0); current = { ...root, sessionManager: {} };
    pending.resolve(ready()); await settle(); expect(tracker.snapshot).toBeUndefined();
    tracker.dispose();
  });

  it("clones/sanitizes data, bounds long lists with a hint, and suppresses unchanged notifications", async () => {
    const result = ready(Array.from({ length: 110 }, () => job("running", { name: "safe\nname" })));
    const read = vi.fn(async () => result); const changed = vi.fn();
    const tracker = new BackgroundWorkspaceTracker(bus({ read }).events, changed);
    tracker.refresh(root, 0); await settle();
    expect(tracker.snapshot?.jobs).toHaveLength(100); expect(tracker.snapshot?.hasMore).toBe(true);
    expect(tracker.snapshot?.jobs[0].name).toBe("safe name");
    expect(tracker.snapshot?.jobs[0]).not.toBe(result.jobs[0]);
    tracker.refresh(root, 3000); await settle(); expect(changed).toHaveBeenCalledTimes(1);
    result.jobs[0].name = "mutated";
    expect(tracker.snapshot?.jobs[0].name).toBe("safe name");
    tracker.dispose();
  });

  it.each(["reject", "throw", "invalid", "unavailable"])("clears old jobs on %s rather than reporting an empty success", async failure => {
    const read = vi.fn<BackgroundSidebarProvider["read"]>().mockResolvedValue(ready());
    const tracker = new BackgroundWorkspaceTracker(bus({ read }).events, vi.fn());
    tracker.refresh(root, 0); await settle(); expect(tracker.snapshot?.jobs).toHaveLength(1);
    if (failure === "reject") read.mockRejectedValue(new Error("offline"));
    else if (failure === "throw") read.mockImplementation(() => { throw new Error("offline"); });
    else if (failure === "invalid") read.mockResolvedValue(ready([job("running", { createdAt: Number.NaN })]));
    else read.mockResolvedValue({ ...ready(), state: "unavailable", error: "offline\n\x1b[2J" });
    tracker.refresh(root, 3000); await settle();
    expect(tracker.snapshot).toMatchObject({ state: "unavailable", jobs: [] });
    expect(tracker.snapshot?.error).toBeTruthy();
    tracker.dispose();
  });
});

describe("WorkspaceStatus lifecycle and input", () => {
  it("pauses Git on same-cwd session changes and aborts/discards late results on hide/dispose", async () => {
    let current = root; let visible = true;
    const pending = deferred<{ stdout: string; stderr: string; code: number; killed: boolean }>();
    const run = vi.fn((_args: string[], _signal: AbortSignal) => pending.promise);
    const status = new WorkspaceStatus({ runGit: run, getRootContext: () => current, isVisible: () => visible, theme: () => theme, onChange: vi.fn() });
    status.refresh(0); const signal = run.mock.calls[0][1];
    current = { ...root, sessionManager: {} }; status.refresh(200);
    expect(signal.aborted).toBe(true);
    visible = false; status.refresh(400);
    expect(run.mock.calls[1][1].aborted).toBe(true);
    expect(renderStatus(status, 38)).toHaveLength(2);
    expect(renderStatus(status, 38).map(stripTerminalSequences).join("\n")).not.toMatch(/old|ahead/);
    pending.resolve({ stdout: "# branch.oid (initial)\0# branch.head old\0", stderr: "", code: 0, killed: false }); await settle();
    expect(renderStatus(status, 38)).toHaveLength(2);
    expect(renderStatus(status, 38).map(stripTerminalSequences).join("\n")).not.toMatch(/old|ahead/);
    status.dispose(); visible = true; status.refresh(5000); expect(run).toHaveBeenCalledTimes(2);
  });

  it("collapses independently with focus:false, ignores body/right/wheel, and avoids idle repaints", async () => {
    const b = bus({ read: async () => ready([job("exited", { endedAt: 5000, exitCode: 0 })]) }); const onChange = vi.fn();
    const runGit = vi.fn(async () => ({ stdout: "# branch.oid (initial)\0# branch.head main\0", stderr: "", code: 0, killed: false }));
    const status = new WorkspaceStatus({ events: b.events, runGit, getRootContext: () => root, isVisible: () => true, theme: () => theme, onChange });
    status.refresh(0); await settle();
    const initial = renderStatus(status, 38).map(stripTerminalSequences);
    const event: TuiMouseEvent = { type: "click", button: "left", x: 2, y: 0, width: 38, height: 14, screenX: 2, screenY: 0, alt: false, ctrl: false, shift: false };
    expect(status.backgroundSection.handleMouse?.({ ...event, y: 1 })).toBeUndefined();
    expect(status.backgroundSection.handleMouse?.({ ...event, button: "right" })).toBeUndefined();
    expect(status.backgroundSection.handleMouse?.({ ...event, type: "wheel", button: "none", wheelDelta: 1 })).toBeUndefined();
    expect(status.backgroundSection.handleMouse?.(event)).toEqual({ handled: true, focus: false });
    const collapsed = renderStatus(status, 38).map(stripTerminalSequences);
    expect(collapsed.length).toBe(initial.length - 2); expect(collapsed[0]).toContain("▸ Background"); expect(collapsed.join("\n")).toContain("Git · main · clean");
    expect(status.gitSection.handleMouse?.(event)).toEqual({ handled: true, focus: false });
    expect(renderStatus(status, 38)).toHaveLength(2);
    expect(renderStatus(status, 38).map(stripTerminalSequences).join("\n")).toContain("Git · main · clean");
    onChange.mockClear(); for (let n = 200; n <= 6000; n += 200) status.refresh(n);
    await settle(); expect(onChange).not.toHaveBeenCalled();
    status.dispose();
  });
});
