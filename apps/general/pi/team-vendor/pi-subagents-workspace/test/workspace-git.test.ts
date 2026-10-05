import { execFile, execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import { type GitCommandRunner, GitWorkspaceTracker, parseGitNumstat, parseGitStatus } from "../src/ui/workspace-git.js";

const OID = "a".repeat(40);
const headers = (extra = "", oid = OID, branch = "main") => `# branch.oid ${oid}\0# branch.head ${branch}\0${extra}`;
const ordinary = (path: string, xy = ".M") => `1 ${xy} N... 100644 100644 100644 ${OID} ${OID} ${path}\0`;
const renamed = (path: string, oldPath: string, xy = "R.") => `2 ${xy} N... 100644 100644 100644 ${OID} ${OID} R100 ${path}\0${oldPath}\0`;
const result = (stdout = "", stderr = "", code = 0, killed = false) => ({ stdout, stderr, code, killed });
const trackers: GitWorkspaceTracker[] = [];
const roots: string[] = [];

function tracker(run: GitCommandRunner, onChange = vi.fn()): GitWorkspaceTracker {
  const value = new GitWorkspaceTracker(run, onChange);
  trackers.push(value);
  return value;
}

async function settle(value: GitWorkspaceTracker): Promise<void> {
  await vi.waitFor(() => expect(value.snapshot?.state).not.toBe("loading"));
}

function deferredRunner() {
  const pending: Array<{
    args: string[];
    signal: AbortSignal;
    resolve: (value: Awaited<ReturnType<GitCommandRunner>>) => void;
    reject: (error: Error) => void;
  }> = [];
  const run = vi.fn<GitCommandRunner>((args, signal) => new Promise((resolve, reject) => {
    pending.push({ args, signal, resolve, reject });
  }));
  return { run, pending };
}

// All writes, staging, commits and branch operations below are fixture setup
// confined to fresh temp repos. The actual tracker runner only issues reads.
const env = {
  ...process.env,
  GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null", LC_ALL: "C",
  GIT_AUTHOR_NAME: "Workspace Test", GIT_AUTHOR_EMAIL: "test@example.invalid",
  GIT_COMMITTER_NAME: "Workspace Test", GIT_COMMITTER_EMAIL: "test@example.invalid",
};
function git(cwd: string, ...args: string[]): string {
  return execFileSync("git", ["-C", cwd, ...args], { env, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], timeout: 5000 });
}
function repo(): string {
  const cwd = mkdtempSync(join(tmpdir(), "pi-workspace-git-"));
  roots.push(cwd);
  git(cwd, "init", "-b", "main");
  git(cwd, "config", "core.autocrlf", "false");
  return cwd;
}
function commit(cwd: string, paths: string[]): void {
  git(cwd, "add", "--", ...paths);
  git(cwd, "commit", "-m", "fixture");
}
const realRunner: GitCommandRunner = (args, signal) => new Promise((resolve, reject) => {
  execFile("git", args, { env, signal, encoding: "utf8", timeout: 5000, maxBuffer: 8 * 1024 * 1024 }, (error, stdout, stderr) => {
    if (error && typeof error.code !== "number") { reject(error); return; }
    resolve({ stdout, stderr, code: error?.code ?? 0, killed: error?.killed ?? false });
  });
});
async function readRepo(cwd: string) {
  const value = tracker(realRunner);
  value.refresh(cwd);
  await settle(value);
  expect(value.snapshot?.state).toBe("ready");
  return value.snapshot!;
}

afterEach(() => {
  for (const value of trackers.splice(0)) value.dispose();
  for (const cwd of roots.splice(0)) rmSync(cwd, { recursive: true, force: true });
});

describe("Git NUL parsers", () => {
  it("preserves literal paths, rename sources and binary rows", () => {
    const path = " space\tline\n\u001b[31m name ";
    const oldPath = "old\n? path\tname";
    expect(parseGitNumstat(`12\t3\t${path}\0-\t-\timage.bin\x000\t0\t\0${oldPath}\0new\tname\0`)).toEqual([
      { path, added: 12, removed: 3, binary: false },
      { path: "image.bin", added: null, removed: null, binary: true },
      { path: "new\tname", oldPath, added: 0, removed: 0, binary: false },
    ]);
    expect(parseGitStatus(headers("# branch.upstream origin/main\0# branch.ab +12 -4\0# future value\0")
      + ordinary(path, "MM") + renamed("new\tname", oldPath) + "? literal\\name\0? a\nb\0")).toEqual({
      oid: OID, branch: "main", ahead: 12, behind: 4, untracked: 2,
      files: [
        { path, status: "MM", added: null, removed: null, binary: false },
        { path: "new\tname", oldPath, status: "R.", added: null, removed: null, binary: false },
        { path: "literal\\name", status: "?", added: null, removed: null, binary: false },
        { path: "a\nb", status: "?", added: null, removed: null, binary: false },
      ],
    });
  });

  it("handles detached, unborn, no upstream and unmerged records", () => {
    expect(parseGitStatus(headers("", "(initial)", "topic"))).toMatchObject({ oid: "(initial)", branch: "topic", ahead: undefined, behind: undefined });
    expect(parseGitStatus(headers("", OID, "(detached)"))).toMatchObject({ branch: "(detached)", ahead: undefined });
    expect(parseGitStatus(headers("# branch.ab +3 -2\0"))).toMatchObject({ ahead: undefined, behind: undefined });
    expect(parseGitStatus(headers("# branch.upstream origin/main\0"))).toMatchObject({ ahead: undefined, behind: undefined });
    const conflict = `u UU N... 100644 100644 100644 100644 ${OID} ${OID} ${OID} merge\nconflict\0`;
    expect(parseGitStatus(headers() + conflict).files).toEqual([
      { path: "merge\nconflict", status: "UU", added: null, removed: null, binary: false },
    ]);
    expect(parseGitNumstat("")).toEqual([]);
  });

  it.each([
    "1\t2\ttruncated", "1\t2\t\0missing-destination\0", "-\t2\tx\0", "x\t1\tx\0",
    "9007199254740992\t0\tx\0", "1\t0\t\0\0destination\0", "\0",
  ])("rejects malformed or truncated numstat: %j", output => {
    expect(() => parseGitNumstat(output)).toThrow();
  });

  it.each([
    "", headers().slice(0, -1), headers() + "? \0", headers() + "1 .M incomplete\0",
    headers() + renamed("new", "old").replace("old\0", ""), headers() + "unexpected\0",
    headers("# branch.ab +NaN -2\0"), headers("", "broken"), headers() + ordinary("x", "XX"),
  ])("rejects malformed status rather than fabricating clean: %j", output => {
    expect(() => parseGitStatus(output)).toThrow();
  });
});

describe("GitWorkspaceTracker lifecycle", () => {
  it("does no initial I/O, coalesces in-flight refreshes and throttles to 3 seconds", async () => {
    const { run, pending } = deferredRunner();
    const changed = vi.fn();
    const value = tracker(run, changed);
    expect(value.snapshot).toBeUndefined();
    expect(run).not.toHaveBeenCalled();
    value.refresh("/repo with spaces", 100);
    expect(value.snapshot).toEqual({ cwd: "/repo with spaces", state: "loading", files: [], untracked: 0 });
    expect(changed).toHaveBeenCalledTimes(1);
    value.refresh("/repo with spaces", 200);
    value.refresh("/repo with spaces", 4000);
    expect(run).toHaveBeenCalledTimes(1);
    expect(pending[0].args).toEqual(["--no-optional-locks", "--no-lazy-fetch", "-C", "/repo with spaces", "-c", "core.fsmonitor=false", "status", "--porcelain=v2", "--branch", "--ahead-behind", "--untracked-files=all", "-z", "--renames", "--ignore-submodules=none"]);
    pending[0].resolve(result(headers() + ordinary("a")));
    await vi.waitFor(() => expect(pending).toHaveLength(2));
    value.refresh("/repo with spaces", 5000);
    expect(run).toHaveBeenCalledTimes(2);
    expect(pending[1].signal).toBe(pending[0].signal);
    expect(pending[1].args).toEqual(["--no-optional-locks", "--no-lazy-fetch", "-C", "/repo with spaces", "-c", "core.fsmonitor=false", "diff", "--numstat", "-z", "--no-ext-diff", "--no-textconv", "--no-color", "--no-relative", "--find-renames", "--ignore-submodules=none", OID, "--"]);
    pending[1].resolve(result("2\t1\ta\0"));
    await settle(value);
    expect(value.snapshot?.files[0]).toMatchObject({ added: 2, removed: 1 });
    expect(changed).toHaveBeenCalledTimes(2);
    value.refresh("/repo with spaces", 3099);
    expect(run).toHaveBeenCalledTimes(2);
    value.refresh("/repo with spaces", 3100);
    expect(run).toHaveBeenCalledTimes(3);
    expect(value.snapshot?.state).toBe("ready"); // no loading flicker for TTL reads
  });

  it("aborts cwd changes and generation-fences late status and diff completions", async () => {
    const { run, pending } = deferredRunner();
    const changed = vi.fn();
    const value = tracker(run, changed);
    value.refresh("/old", 0);
    value.refresh("/new", 1);
    expect(pending[0].signal.aborted).toBe(true);
    pending[0].resolve(result(headers() + ordinary("stale")));
    pending[1].resolve(result(headers() + ordinary("new")));
    await vi.waitFor(() => expect(pending).toHaveLength(3));
    expect(pending[2].args).toContain("/new");
    value.refresh("/latest", 2);
    expect(pending[2].signal.aborted).toBe(true);
    pending[3].resolve(result(headers("", "(initial)", "latest")));
    await settle(value);
    const current = value.snapshot;
    pending[2].resolve(result("5\t5\tnew\0"));
    await new Promise(resolve => setImmediate(resolve));
    expect(value.snapshot).toBe(current);
    expect(value.snapshot).toMatchObject({ cwd: "/latest", branch: "latest", files: [] });
    expect(changed).toHaveBeenCalledTimes(4);
    value.refresh("/latest", 100);
    expect(pending).toHaveLength(4); // old completion cannot clear current throttle
  });

  it("pause clears and permits immediate resume; dispose permanently stops", async () => {
    const { run, pending } = deferredRunner();
    const changed = vi.fn();
    const value = tracker(run, changed);
    value.refresh("/repo", 0);
    value.pause();
    expect(pending[0].signal.aborted).toBe(true);
    expect(value.snapshot).toBeUndefined();
    value.pause();
    expect(changed).toHaveBeenCalledTimes(2);
    value.refresh("/repo", 1);
    expect(pending).toHaveLength(2);
    pending[0].reject(new Error("late rejection"));
    pending[1].resolve(result(headers("", "(initial)")));
    await settle(value);
    expect(value.snapshot?.state).toBe("ready");
    value.refresh("/repo", 3001);
    value.dispose();
    expect(pending[2].signal.aborted).toBe(true);
    const notifications = changed.mock.calls.length;
    value.refresh("/other", 9000);
    pending[2].resolve(result(headers()));
    await new Promise(resolve => setImmediate(resolve));
    expect(run).toHaveBeenCalledTimes(3);
    expect(value.snapshot).toBeUndefined();
    expect(changed).toHaveBeenCalledTimes(notifications);
  });

  it("handles synchronous detach in onChange before launching I/O", () => {
    const run = vi.fn<GitCommandRunner>();
    const value = tracker(run, vi.fn(() => value.pause()));
    value.refresh("/repo");
    expect(run).not.toHaveBeenCalled();
    expect(value.snapshot).toBeUndefined();
  });

  it("resamples after clock rollback and retries errors only after TTL", async () => {
    const run = vi.fn<GitCommandRunner>().mockResolvedValue(result("", "permission denied", 128));
    const value = tracker(run);
    value.refresh("/repo", 5000);
    await settle(value);
    expect(value.snapshot).toMatchObject({ state: "unavailable", error: "permission denied", files: [] });
    value.refresh("/repo", 7999);
    expect(run).toHaveBeenCalledTimes(1);
    run.mockResolvedValue(result(headers("", "(initial)")));
    value.refresh("/repo", 4999);
    await vi.waitFor(() => expect(value.snapshot?.state).toBe("ready"));
    expect(run).toHaveBeenCalledTimes(2);
  });

  it.each([
    [result("", "fatal: not a git repository (or any of the parent directories): .git\n", 128), "not-repository"],
    [result("", "fatal: not a git repository (or any parent up to mount point /)\n", 128), "not-repository"],
    [result("", "fatal: not a git repository: /broken/.git\n", 128), "unavailable"],
    [result("", "fatal: detected dubious ownership in repository", 128), "unavailable"],
    [result("", "fatal: cannot change to /missing", 128), "unavailable"],
    [result("", "fatal: this operation must be run in a work tree", 128), "unavailable"],
    [result(headers(), "", 0, true), "unavailable"],
    [result("", "", 0), "unavailable"],
    [result("x".repeat(4 * 1024 * 1024 + 1)), "unavailable"],
    [result(headers(), "x".repeat(64 * 1024 + 1)), "unavailable"],
  ] as const)("classifies status failures (%#) without false clean", async (response, state) => {
    const run = vi.fn<GitCommandRunner>().mockResolvedValue(response);
    const value = tracker(run);
    value.refresh("/repo");
    await settle(value);
    expect(value.snapshot).toMatchObject({ state, files: [], untracked: 0 });
    expect(run).toHaveBeenCalledTimes(1);
    if (state === "unavailable") expect(value.snapshot?.error).toBeTruthy();
  });

  it("reports rejected/missing Git and failed diffs instead of stale clean data", async () => {
    const run = vi.fn<GitCommandRunner>().mockRejectedValueOnce(new Error("spawn git ENOENT"));
    const value = tracker(run);
    value.refresh("/repo", 0);
    await settle(value);
    expect(value.snapshot).toMatchObject({ state: "unavailable", error: "spawn git ENOENT" });
    run.mockResolvedValueOnce(result(headers() + ordinary("x"))).mockResolvedValueOnce(result("", "diff failure", 1));
    value.refresh("/repo", 3000);
    await vi.waitFor(() => expect(value.snapshot?.error).toBe("diff failure"));
    expect(value.snapshot?.state).toBe("unavailable");
  });

  it("uses zero only for a known HEAD net cancellation, not unborn or untracked files", async () => {
    const run = vi.fn<GitCommandRunner>().mockResolvedValueOnce(result(headers() + ordinary("cancelled", "MM") + "? unknown\0")).mockResolvedValueOnce(result());
    const value = tracker(run);
    value.refresh("/repo", 0);
    await settle(value);
    expect(value.snapshot?.files).toEqual([
      { path: "cancelled", status: "MM", added: 0, removed: 0, binary: false },
      { path: "unknown", status: "?", added: null, removed: null, binary: false },
    ]);
    run.mockResolvedValueOnce(result(headers("", "(initial)") + ordinary("new", "AM")));
    value.refresh("/repo", 3000);
    await vi.waitFor(() => expect(value.snapshot?.files[0].path).toBe("new"));
    expect(value.snapshot?.files[0]).toMatchObject({ added: null, removed: null });
    expect(run).toHaveBeenCalledTimes(3); // no HEAD diff for unborn repos
  });

  it.each(["1\t2\tunexpected\0", "1\t2\tknown", "0\t0\tknown\x000\t0\tknown\0"])(
    "rejects mismatched/truncated/duplicate diffs (%#)", async diff => {
      const run = vi.fn<GitCommandRunner>().mockResolvedValueOnce(result(headers() + ordinary("known"))).mockResolvedValueOnce(result(diff));
      const value = tracker(run);
      value.refresh("/repo");
      await settle(value);
      expect(value.snapshot?.state).toBe("unavailable");
    },
  );
});

describe("GitWorkspaceTracker real test-owned repositories", () => {
  it("reports staged + unstaged NET deltas, deletes, binary, weird paths and individual untracked counts", async () => {
    const cwd = repo();
    const weird = "space\ttab\nline\u001b[31m.txt";
    writeFileSync(join(cwd, "both.txt"), "first\nsecond\nthird\n");
    writeFileSync(join(cwd, "cancelled.txt"), "original\n");
    writeFileSync(join(cwd, "delete.txt"), "one\ntwo\n");
    writeFileSync(join(cwd, "image.bin"), Buffer.from([0, 1, 2]));
    writeFileSync(join(cwd, weird), "old\n");
    commit(cwd, ["both.txt", "cancelled.txt", "delete.txt", "image.bin", weird]);
    writeFileSync(join(cwd, "both.txt"), "first\nstaged\nthird\n");
    writeFileSync(join(cwd, "cancelled.txt"), "staged\n");
    git(cwd, "add", "--", "both.txt", "cancelled.txt");
    writeFileSync(join(cwd, "both.txt"), "first\nfinal\nthird\nextra\n");
    writeFileSync(join(cwd, "cancelled.txt"), "original\n");
    rmSync(join(cwd, "delete.txt"));
    writeFileSync(join(cwd, "image.bin"), Buffer.from([0, 4, 5, 6]));
    writeFileSync(join(cwd, weird), "new\nextra\n");
    mkdirSync(join(cwd, "untracked"));
    writeFileSync(join(cwd, "untracked", "one"), "never read\n");
    writeFileSync(join(cwd, "untracked", "two\nlines"), "never read\n");
    const indexBefore = readFileSync(join(cwd, ".git", "index"));
    // Run from a subdirectory with diff.relative configured: all paths must
    // still be repository-relative and include files outside this subdirectory.
    git(cwd, "config", "diff.relative", "true");
    const snapshot = await readRepo(join(cwd, "untracked"));
    expect(snapshot).toMatchObject({ branch: "main", ahead: undefined, behind: undefined, untracked: 2 });
    expect(snapshot.files).toEqual(expect.arrayContaining([
      { path: "both.txt", status: "MM", added: 2, removed: 1, binary: false },
      { path: "cancelled.txt", status: "MM", added: 0, removed: 0, binary: false },
      { path: "delete.txt", status: ".D", added: 0, removed: 2, binary: false },
      { path: "image.bin", status: ".M", added: null, removed: null, binary: true },
      { path: weird, status: ".M", added: 2, removed: 1, binary: false },
      { path: "untracked/one", status: "?", added: null, removed: null, binary: false },
      { path: "untracked/two\nlines", status: "?", added: null, removed: null, binary: false },
    ]));
    expect(snapshot.files).toHaveLength(7);
    expect(readFileSync(join(cwd, ".git", "index"))).toEqual(indexBefore);
  });

  it("preserves staged rename sources, destination edits, and a deleted renamed destination", async () => {
    const cwd = repo();
    writeFileSync(join(cwd, "old\tname"), "one\ntwo\nthree\nfour\nfive\n");
    commit(cwd, ["old\tname"]);
    git(cwd, "mv", "--", "old\tname", "new\nname");
    writeFileSync(join(cwd, "new\nname"), "one\ntwo\nthree\nfour\nfive\nsix\n");
    expect((await readRepo(cwd)).files).toEqual([
      { path: "new\nname", oldPath: "old\tname", status: "RM", added: 1, removed: 0, binary: false },
    ]);
    rmSync(join(cwd, "new\nname"));
    expect((await readRepo(cwd)).files).toEqual([
      { path: "new\nname", oldPath: "old\tname", status: "RD", added: 0, removed: 5, binary: false },
    ]);
  });

  it("combines D/A stats when a staged rename is rewritten beyond net rename detection", async () => {
    const cwd = repo();
    writeFileSync(join(cwd, "old"), "one\ntwo\nthree\n");
    commit(cwd, ["old"]);
    git(cwd, "mv", "--", "old", "new");
    writeFileSync(join(cwd, "new"), "unrelated\nreplacement\n");
    expect((await readRepo(cwd)).files).toEqual([
      { path: "new", oldPath: "old", status: "RM", added: 2, removed: 3, binary: false },
    ]);
  });

  it("keeps a tracked deletion and same-path untracked replacement distinct", async () => {
    const cwd = repo();
    writeFileSync(join(cwd, "same"), "committed\n");
    commit(cwd, ["same"]);
    git(cwd, "rm", "--", "same");
    writeFileSync(join(cwd, "same"), "not in index\n");
    expect((await readRepo(cwd)).files).toEqual([
      { path: "same", status: "D.", added: 0, removed: 1, binary: false },
      { path: "same", status: "?", added: null, removed: null, binary: false },
    ]);
  });

  it("reports empty and dirty unborn repositories with honest null stats", async () => {
    const cwd = repo();
    expect(await readRepo(cwd)).toMatchObject({ branch: "main", ahead: undefined, untracked: 0, files: [] });
    writeFileSync(join(cwd, "added"), "staged\n");
    git(cwd, "add", "--", "added");
    writeFileSync(join(cwd, "added"), "working\nextra\n");
    writeFileSync(join(cwd, "untracked"), Buffer.from([0, 1, 2]));
    expect((await readRepo(cwd)).files).toEqual([
      { path: "added", status: "AM", added: null, removed: null, binary: false },
      { path: "untracked", status: "?", added: null, removed: null, binary: false },
    ]);
  });

  it("reads ahead/behind from local refs without fetching and supports detached HEAD", async () => {
    const cwd = repo();
    writeFileSync(join(cwd, "base"), "base\n");
    commit(cwd, ["base"]);
    git(cwd, "branch", "upstream");
    git(cwd, "branch", "--set-upstream-to=upstream", "main");
    git(cwd, "config", "status.aheadBehind", "false");
    expect(await readRepo(cwd)).toMatchObject({ ahead: 0, behind: 0 });
    writeFileSync(join(cwd, "ahead"), "ahead\n");
    commit(cwd, ["ahead"]);
    expect(await readRepo(cwd)).toMatchObject({ ahead: 1, behind: 0 });
    git(cwd, "switch", "upstream");
    writeFileSync(join(cwd, "behind"), "behind\n");
    commit(cwd, ["behind"]);
    git(cwd, "switch", "main");
    expect(await readRepo(cwd)).toMatchObject({ ahead: 1, behind: 1 });
    git(cwd, "checkout", "--detach", "HEAD");
    writeFileSync(join(cwd, "base"), "edited\n");
    expect(await readRepo(cwd)).toMatchObject({ branch: "(detached)", ahead: undefined, behind: undefined,
      files: [{ path: "base", status: ".M", added: 1, removed: 1, binary: false }] });
  });

  it("does not invoke configured external diff or textconv programs", async () => {
    const cwd = repo();
    writeFileSync(join(cwd, ".gitattributes"), "*.txt diff=forbidden\n");
    writeFileSync(join(cwd, "file.txt"), "old\n");
    commit(cwd, [".gitattributes", "file.txt"]);
    git(cwd, "config", "diff.external", "this-program-must-not-run");
    git(cwd, "config", "diff.forbidden.textconv", "this-program-must-not-run");
    writeFileSync(join(cwd, "file.txt"), "new\n");
    expect((await readRepo(cwd)).files).toEqual([
      { path: "file.txt", status: ".M", added: 1, removed: 1, binary: false },
    ]);
  });

  it("reports real unmerged paths with unknown stats", async () => {
    const cwd = repo();
    writeFileSync(join(cwd, "conflict"), "base\n");
    commit(cwd, ["conflict"]);
    git(cwd, "branch", "other");
    writeFileSync(join(cwd, "conflict"), "main\n");
    commit(cwd, ["conflict"]);
    git(cwd, "switch", "other");
    writeFileSync(join(cwd, "conflict"), "other\n");
    commit(cwd, ["conflict"]);
    expect(() => git(cwd, "merge", "main")).toThrow();
    expect((await readRepo(cwd)).files).toEqual([
      { path: "conflict", status: "UU", added: null, removed: null, binary: false },
    ]);
  });

  it("fails closed for a missing promisor object instead of lazy-fetching it", async () => {
    const source = repo();
    const cwd = repo();
    for (const dir of [source, cwd]) {
      writeFileSync(join(dir, "file"), "original\n");
      commit(dir, ["file"]);
    }
    const blob = git(cwd, "rev-parse", "HEAD:file").trim();
    const object = join(cwd, ".git", "objects", blob.slice(0, 2), blob.slice(2));
    git(cwd, "config", "remote.origin.url", source);
    git(cwd, "config", "remote.origin.promisor", "true");
    git(cwd, "config", "extensions.partialClone", "origin");
    writeFileSync(join(cwd, "file"), "edited\n");
    rmSync(object);
    const value = tracker(realRunner);
    value.refresh(cwd);
    await settle(value);
    expect(value.snapshot?.state).toBe("unavailable");
    expect(existsSync(object)).toBe(false);
    expect(readFileSync(join(cwd, "file"), "utf8")).toBe("edited\n");
    expect(git(cwd, "count-objects", "-v")).toContain("in-pack: 0");
  });

  it("distinguishes an actual nonrepo from broken metadata and missing cwd", async () => {
    const cwd = repo();
    renameSync(join(cwd, ".git"), join(cwd, "saved-metadata"));
    const value = tracker(realRunner);
    value.refresh(cwd, 0);
    await settle(value);
    expect(value.snapshot?.state).toBe("not-repository");
    writeFileSync(join(cwd, ".git"), "gitdir: /nonexistent/workspace-git-test-dir\n");
    value.refresh(cwd, 3000);
    await vi.waitFor(() => expect(value.snapshot?.state).toBe("unavailable"));
    value.refresh(join(cwd, "missing"), 3001);
    await settle(value);
    expect(value.snapshot?.state).toBe("unavailable");
  });
});
