/** A single, text-only handoff between root extension runtimes in this process.
 * Deliberately not appendEntry: unsent drafts must not accumulate forever in an
 * append-only session journal, survive a restart, or be copied by fork/resume.
 * The global slot holds only bounded serialized data, never a ctx/session/UI.
 */
export const WORKSPACE_RELOAD_SLOT = Symbol.for("pi-subagents:workspace-reload:v1");
export const RELOAD_MAX_BYTES = 512 * 1024;
export const RELOAD_MAX_DRAFTS = 128;
export const RELOAD_MAX_TEXT = 64 * 1024;
export const RELOAD_MAX_AGE_MS = 5 * 60 * 1000;

export type ReloadDraft = {
  key: string;
  label: string;
  text: string;
  modelId?: string;
  modelName?: string;
  provider?: string;
  thinkingLevel?: string;
};
export type WorkspaceReloadData = { selected: string; drafts: ReloadDraft[] };
export type ReloadOwner = { sessionId: string; sessionFile: string | null };
type Snapshot = ReloadOwner & WorkspaceReloadData & { version: 1; savedAt: number };
const storage = globalThis as typeof globalThis & { [WORKSPACE_RELOAD_SLOT]?: string };
const fields = ["modelId", "modelName", "provider", "thinkingLevel"] as const;

function plain(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype;
}
function exact(value: Record<string, unknown>, keys: readonly string[]): boolean {
  return Reflect.ownKeys(value).every(key => typeof key === "string" && keys.includes(key));
}
function label(value: unknown, max = 256): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= max && !/[\x00-\x1f\x7f-\x9f]/.test(value);
}
function key(value: unknown): value is string {
  return typeof value === "string" && (value === "main" || /^(agent|workflow):[a-zA-Z0-9_:.-]{1,192}$/.test(value));
}

/** Strict projection boundary; no truncation and no attachment/runtime fields. */
export function validateReloadData(value: unknown): asserts value is WorkspaceReloadData {
  if (!plain(value) || !exact(value, ["selected", "drafts"]) || !key(value.selected)
    || !Array.isArray(value.drafts) || value.drafts.length < 1 || value.drafts.length > RELOAD_MAX_DRAFTS) throw new Error("Invalid workspace reload draft schema or draft count (maximum 128).");
  const keys = new Set<string>();
  for (const draft of value.drafts) {
    if (!plain(draft) || !exact(draft, ["key", "label", "text", ...fields]) || !key(draft.key) || keys.has(draft.key)
      || !label(draft.label) || typeof draft.text !== "string" || draft.text.length > RELOAD_MAX_TEXT
      || fields.some(field => draft[field] !== undefined && !label(draft[field]))) throw new Error("Invalid workspace reload draft or text exceeds 65536 characters; nothing was truncated.");
    keys.add(draft.key);
  }
  if (!keys.has("main") || !keys.has(value.selected)) throw new Error("Workspace reload draft identity is missing.");
  if (Buffer.byteLength(JSON.stringify(value), "utf8") > RELOAD_MAX_BYTES - 8192) throw new Error("Workspace reload drafts exceed the 512 KiB handoff limit; nothing was truncated.");
}

export function saveWorkspaceReload(owner: ReloadOwner, data: WorkspaceReloadData, now = Date.now()): void {
  validateReloadData(data);
  if (!label(owner.sessionId, 192) || (owner.sessionFile !== null && !label(owner.sessionFile, 4096))) throw new Error("Invalid workspace reload owner.");
  const snapshot: Snapshot = { ...owner, ...data, version: 1, savedAt: now };
  // Validate before replacing: a rejected/cap-exceeding save leaves any existing
  // handoff intact, and the caller reports the refusal to the user.
  storage[WORKSPACE_RELOAD_SLOT] = JSON.stringify(snapshot);
}

export function clearWorkspaceReload(): void { delete storage[WORKSPACE_RELOAD_SLOT]; }

/** Consume once, only for the exact root's real reload event. */
export function takeWorkspaceReload(owner: ReloadOwner, reason: string, now = Date.now()): WorkspaceReloadData | undefined {
  const serialized: unknown = storage[WORKSPACE_RELOAD_SLOT];
  clearWorkspaceReload();
  if (reason !== "reload" || serialized === undefined) return undefined;
  if (typeof serialized !== "string" || Buffer.byteLength(serialized, "utf8") > RELOAD_MAX_BYTES) throw new Error("Invalid or oversized workspace reload handoff.");
  const value: unknown = JSON.parse(serialized);
  if (!plain(value) || !exact(value, ["version", "savedAt", "sessionId", "sessionFile", "selected", "drafts"])
    || value.version !== 1 || value.sessionId !== owner.sessionId || value.sessionFile !== owner.sessionFile
    || typeof value.savedAt !== "number" || !Number.isFinite(value.savedAt) || now < value.savedAt || now - value.savedAt > RELOAD_MAX_AGE_MS) throw new Error("Workspace reload handoff is stale or belongs to another session.");
  const data = { selected: value.selected, drafts: value.drafts };
  validateReloadData(data);
  return data;
}
