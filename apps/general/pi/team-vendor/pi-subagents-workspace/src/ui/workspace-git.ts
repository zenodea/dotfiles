/** Read-only Git sampling. Call refresh from the host tick, never from render. */
export interface GitFileChange {
  /** Repository-relative paths, verbatim (including whitespace/control characters). */
  path: string;
  oldPath?: string;
  /** Porcelain v2 XY status, or ? for an untracked file. */
  status: string;
  added: number | null;
  removed: number | null;
  /** True only when Git explicitly reports binary numstat. */
  binary: boolean;
}

export interface GitWorkspaceSnapshot {
  cwd: string;
  state: "loading" | "ready" | "not-repository" | "unavailable";
  branch?: string;
  ahead?: number;
  behind?: number;
  untracked: number;
  files: readonly GitFileChange[];
  error?: string;
}

/**
 * Invoke git directly with argv, not a shell. The host must honor signal and
 * enforce a timeout (e.g. pi.exec("git", args, { signal, timeout: 5000 })).
 * This module bounds accepted output, not the runner's in-flight buffering;
 * pi.exec currently has no streaming/maxBuffer option. Never truncate success.
 */
export type GitCommandRunner = (args: string[], signal: AbortSignal) => Promise<{
  stdout: string;
  stderr: string;
  code: number;
  killed: boolean;
}>;

const REFRESH_MS = 3000;
const MAX_OUTPUT_BYTES = 4 * 1024 * 1024;
const MAX_ERROR_BYTES = 64 * 1024;

type GitStatus = {
  oid: string;
  branch: string;
  ahead?: number;
  behind?: number;
  untracked: number;
  files: GitFileChange[];
};

type GitNumstat = Pick<GitFileChange, "path" | "oldPath" | "added" | "removed" | "binary">;

function nulRecords(output: string): string[] {
  if (output === "") return [];
  if (!output.endsWith("\0")) throw new Error("Incomplete NUL-delimited Git output");
  return output.slice(0, -1).split("\0");
}

function count(value: string): number {
  if (!/^\d+$/.test(value) || !Number.isSafeInteger(Number(value))) throw new Error("Invalid Git count");
  return Number(value);
}

/** Split only the fixed metadata prefix: a filename is not whitespace-delimited. */
function statusFields(record: string, fields: number): string[] {
  const result: string[] = [];
  let start = 0;
  for (let i = 0; i < fields; i++) {
    const end = record.indexOf(" ", start);
    if (end <= start) throw new Error("Invalid Git status record");
    result.push(record.slice(start, end));
    start = end + 1;
  }
  result.push(record.slice(start));
  if (!result[fields] || !/^[.MTADRCU]{2}$/.test(result[1])) throw new Error("Invalid Git status path or XY status");
  return result;
}

/** Parse porcelain v2 --branch --untracked-files=all -z, without unquoting paths. */
export function parseGitStatus(output: string): GitStatus {
  const records = nulRecords(output);
  const files: GitFileChange[] = [];
  let oid: string | undefined;
  let branch: string | undefined;
  let upstream = false;
  let ahead: number | undefined;
  let behind: number | undefined;
  let untracked = 0;
  for (let i = 0; i < records.length; i++) {
    const record = records[i];
    if (record.startsWith("# ")) {
      if (record.startsWith("# branch.oid ")) oid = record.slice(13);
      else if (record.startsWith("# branch.head ")) branch = record.slice(14);
      else if (record.startsWith("# branch.upstream ")) upstream = record.length > 18;
      else if (record.startsWith("# branch.ab ")) {
        const match = /^# branch\.ab \+(\d+) -(\d+)$/.exec(record);
        if (!match) throw new Error("Invalid Git ahead/behind header");
        ahead = count(match[1]);
        behind = count(match[2]);
      }
      // Porcelain v2 explicitly allows future/unknown headers.
      continue;
    }
    let path: string;
    let oldPath: string | undefined;
    let status: string;
    if (record.startsWith("? ")) {
      path = record.slice(2);
      status = "?";
      untracked++;
    } else if (record.startsWith("1 ") || record.startsWith("2 ") || record.startsWith("u ")) {
      const fields = statusFields(record, record[0] === "1" ? 8 : record[0] === "2" ? 9 : 10);
      path = fields[fields.length - 1];
      status = fields[1];
      if (record[0] === "2") {
        oldPath = records[++i];
        if (!oldPath) throw new Error("Missing Git rename source");
      }
    } else {
      throw new Error("Unknown Git status record");
    }
    if (!path) throw new Error("Missing Git status path");
    files.push({ path, ...(oldPath === undefined ? {} : { oldPath }), status, added: null, removed: null, binary: false });
  }
  if (!oid || !/^(?:[0-9a-f]{40}|[0-9a-f]{64}|\(initial\))$/.test(oid) || !branch) {
    throw new Error("Missing or invalid Git branch headers");
  }
  return { oid, branch, ahead: upstream ? ahead : undefined, behind: upstream ? behind : undefined, untracked, files };
}

/** Parse --numstat -z; rename records use an empty path followed by old/new NUL fields. */
export function parseGitNumstat(output: string): GitNumstat[] {
  const records = nulRecords(output);
  const files: GitNumstat[] = [];
  for (let i = 0; i < records.length; i++) {
    const match = /^(\d+|-)\t(\d+|-)\t([\s\S]*)$/.exec(records[i]);
    if (!match || (match[1] === "-") !== (match[2] === "-")) throw new Error("Invalid Git numstat record");
    let path = match[3];
    let oldPath: string | undefined;
    if (!path) {
      oldPath = records[++i];
      path = records[++i];
      if (!oldPath || !path) throw new Error("Missing Git numstat rename path");
    }
    const binary = match[1] === "-";
    files.push({
      path, ...(oldPath === undefined ? {} : { oldPath }),
      added: binary ? null : count(match[1]), removed: binary ? null : count(match[2]), binary,
    });
  }
  return files;
}

/**
 * Status describes index/worktree changes; numstat describes their NET difference
 * against the HEAD captured by status (never the sum of two independent diffs).
 * A staged change undone in the worktree therefore has a real 0/0 net delta.
 */
function withNumstat(files: GitFileChange[], stats: GitNumstat[]): GitFileChange[] {
  const byPath = new Map<string, GitNumstat>();
  for (const stat of stats) {
    if (byPath.has(stat.path)) throw new Error("Ambiguous duplicate Git numstat path");
    byPath.set(stat.path, stat);
  }
  const trackedPaths = new Set(files.filter(file => file.status !== "?").map(file => file.path));
  const claimed = new Set<string>();
  const result = files.map(file => {
    if (file.status === "?") return file;
    let stat = byPath.get(file.path);
    // A staged rename whose destination was deleted is a HEAD deletion of the
    // source; a heavily rewritten rename can instead become separate D/A rows.
    const source = file.oldPath && byPath.get(file.oldPath);
    if (source && source !== stat && !trackedPaths.has(source.path)) {
      claimed.add(source.path);
      stat = stat ? {
        ...stat,
        added: stat.added === null || source.added === null ? null : stat.added + source.added,
        removed: stat.removed === null || source.removed === null ? null : stat.removed + source.removed,
        binary: stat.binary || source.binary,
      } : source;
    }
    if (stat) claimed.add(file.path);
    // Conflicts do not have a unique baseline for a useful line summary.
    if (file.status.includes("U") || file.status === "AA" || file.status === "DD") return { ...file, binary: stat?.binary ?? false };
    return {
      ...file,
      ...(stat?.oldPath === undefined ? {} : { oldPath: stat.oldPath }),
      added: stat ? stat.added : 0,
      removed: stat ? stat.removed : 0,
      binary: stat?.binary ?? false,
    };
  });
  // A repository can change between the two read-only commands. Do not invent
  // a status or quietly drop net changes that the status sample did not see.
  if (stats.some(stat => !claimed.has(stat.path))) throw new Error("Git changed while reading status; retrying on the next refresh");
  return result;
}

export class GitWorkspaceTracker {
  private current: GitWorkspaceSnapshot | undefined;
  private controller: AbortController | undefined;
  private generation = 0;
  private lastRefresh: number | undefined;
  private disposed = false;

  constructor(private readonly run: GitCommandRunner, private readonly onChange: () => void) {}

  get snapshot(): GitWorkspaceSnapshot | undefined { return this.current; }

  refresh(cwd: string, now = Date.now()): void {
    if (this.disposed) return;
    const changedCwd = this.current?.cwd !== cwd;
    if (changedCwd) this.cancel();
    if (this.controller || (this.lastRefresh !== undefined && now >= this.lastRefresh && now - this.lastRefresh < REFRESH_MS)) return;
    const controller = new AbortController();
    this.controller = controller;
    const generation = ++this.generation;
    this.lastRefresh = now;
    if (changedCwd) {
      this.current = { cwd, state: "loading", untracked: 0, files: [] };
      this.onChange();
    }
    // onChange may synchronously detach the workspace.
    if (!controller.signal.aborted) void this.update(cwd, controller.signal, generation);
  }

  pause(): void {
    this.cancel();
    if (this.current !== undefined) {
      this.current = undefined;
      this.onChange();
    }
  }

  dispose(): void {
    this.disposed = true;
    this.pause();
  }

  private cancel(): void {
    this.generation++;
    this.controller?.abort();
    this.controller = undefined;
    this.lastRefresh = undefined;
  }

  private async command(cwd: string, args: string[], signal: AbortSignal) {
    signal.throwIfAborted();
    // Never hydrate missing promisor objects: that would fetch and write even
    // for an otherwise read-only diff. Older Git lacking this flag fails closed.
    const result = await this.run(["--no-optional-locks", "--no-lazy-fetch", "-C", cwd, "-c", "core.fsmonitor=false", ...args], signal);
    signal.throwIfAborted();
    if (Buffer.byteLength(result.stdout, "utf8") > MAX_OUTPUT_BYTES || Buffer.byteLength(result.stderr, "utf8") > MAX_ERROR_BYTES) {
      throw new Error("Git output exceeds the workspace limit");
    }
    if (result.killed) throw new Error("Git command timed out or was killed");
    return result;
  }

  private async read(cwd: string, signal: AbortSignal): Promise<GitWorkspaceSnapshot> {
    const result = await this.command(cwd, ["status", "--porcelain=v2", "--branch", "--ahead-behind", "--untracked-files=all", "-z", "--renames", "--ignore-submodules=none"], signal);
    if (result.code !== 0) {
      // Only the repository-discovery diagnostic proves this is a non-repo.
      // Permission, dubious ownership, missing git/cwd, broken .git, bare repos
      // and unrecognized/localized errors remain unavailable, never clean.
      if (/^fatal: not a git repository \(or any (?:of the parent directories|parent up to mount point [^\n]*)\)/m.test(result.stderr)) {
        return { cwd, state: "not-repository", untracked: 0, files: [] };
      }
      throw new Error(result.stderr.slice(0, 512) || `Git status failed (${result.code})`);
    }
    const status = parseGitStatus(result.stdout);
    let files = status.files;
    // Unborn repositories have no HEAD to compare against. Report status only,
    // with null counts, instead of pretending cached-only stats are a net diff
    // or reading arbitrary untracked files against /dev/null.
    if (status.oid !== "(initial)") {
      const diff = await this.command(cwd, ["diff", "--numstat", "-z", "--no-ext-diff", "--no-textconv", "--no-color", "--no-relative", "--find-renames", "--ignore-submodules=none", status.oid, "--"], signal);
      if (diff.code !== 0) throw new Error(diff.stderr.slice(0, 512) || `Git diff failed (${diff.code})`);
      files = withNumstat(files, parseGitNumstat(diff.stdout));
    }
    return { cwd, state: "ready", branch: status.branch, ahead: status.ahead, behind: status.behind, untracked: status.untracked, files };
  }

  private async update(cwd: string, signal: AbortSignal, generation: number): Promise<void> {
    let snapshot: GitWorkspaceSnapshot;
    try {
      snapshot = await this.read(cwd, signal);
    } catch (error) {
      snapshot = { cwd, state: "unavailable", untracked: 0, files: [], error: (error instanceof Error ? error.message : String(error)).slice(0, 512) };
    }
    if (signal.aborted || generation !== this.generation || this.disposed) return;
    this.controller = undefined;
    this.current = snapshot;
    this.onChange();
  }
}
