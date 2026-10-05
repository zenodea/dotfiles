/** Optional, session-scoped pi-background integration. No package import or global registry. */
import { open } from "node:fs/promises";
import type { ExtensionAPI, ExtensionContext, ToolDefinition } from "@earendil-works/pi-coding-agent";
import { Type } from "@sinclair/typebox";
import type { AgentRecord } from "./types.js";

export type BackgroundEndReason = "child_terminal" | "child_disposed" | "root_reload" | "root_shutdown";
export type BackgroundAction = "start" | "list" | "status" | "read" | "stop";
export interface BackgroundProfile {
  toolAllowed: boolean;
  readOnly: boolean;
  enforcementAvailable: boolean;
  allowedActions: readonly BackgroundAction[];
}
export interface BackgroundInvocation {
  origin: { leafEntryId: string; toolCallId: string };
  cwd: string;
  shell: { executable: string; args: string[] };
  env: Record<string, string>;
}
export interface BackgroundCapability {
  execute(input: unknown, invocation?: BackgroundInvocation, signal?: AbortSignal): Promise<unknown>;
}
export interface BackgroundChildHandle {
  capability?: BackgroundCapability;
  state(): unknown;
  revoke(reason: BackgroundEndReason): Promise<unknown>;
}
export interface BackgroundDeliveryState {
  eligible(origin: BackgroundInvocation["origin"]): boolean;
  persistedEventIds(): Promise<readonly string[]>;
  settled(): boolean;
}
export interface BackgroundConnection {
  grantDescendant(parentId: string | undefined, childId: string, actions: readonly ("list" | "status" | "read" | "stop")[]): BackgroundCapability;
  register(record: AgentRecord, profile: BackgroundProfile, delivery: BackgroundDeliveryState): BackgroundChildHandle;
  dispose(reason: "root_reload" | "root_shutdown"): Promise<unknown>;
}
export interface BackgroundHostOffer {
  version: 1;
  sessionManager: ExtensionContext["sessionManager"];
  /** Opaque runtime token. Never serialized, never accepted from a tool. */
  attachment: object;
  connect(factory: (manager: { getRecord(id: string): AgentRecord | undefined }) => BackgroundConnection): () => Promise<void>;
}
export interface BackgroundAgentBinding {
  sessionCreated(): void;
  createTool(profile: BackgroundProfile, invocation: (toolCallId: string) => BackgroundInvocation, commandPrefix?: string): ToolDefinition | undefined;
  revoke(reason: BackgroundEndReason): Promise<void>;
}
export interface BackgroundHost {
  readonly rootSessionId: string;
  capture(record: AgentRecord): BackgroundAgentBinding;
  /** Explicit trusted host grant, using exact records, not model-selected ownership. */
  grantDescendant(parent: AgentRecord | undefined, child: AgentRecord, actions: readonly ("list" | "status" | "read" | "stop")[]): BackgroundCapability;
  dispose(reason: "root_reload" | "root_shutdown"): Promise<void>;
}

export const BACKGROUND_HOST_READY = "pi-background:subagents:v1:ready";
export const BACKGROUND_HOST_REQUEST = "pi-background:subagents:v1:request";

/** The file, not the volatile session tree, is the evidence for persistence. */
async function readPersistedEventIds(record: AgentRecord): Promise<readonly string[]> {
  const manager = record.session?.sessionManager;
  const path = manager?.getSessionFile();
  if (!manager || !path) return [];
  const handle = await open(path, "r");
  try {
    const stat = await handle.stat();
    // Refuse oversized histories instead of allocating an unbounded receipt scan.
    if (!stat.isFile() || stat.size > 16 * 1024 * 1024) return [];
    const data = await handle.readFile({ encoding: "utf8" });
    const lines = data.split("\n");
    const header = JSON.parse(lines.shift() ?? "null") as { type?: string; id?: string } | null;
    if (header?.type !== "session" || header.id !== manager.getSessionId()) return [];
    const ids = new Set<string>();
    for (const line of lines) {
      if (!line.trim()) continue;
      let entry: { type?: string; customType?: string; details?: { eventIds?: unknown } };
      try { entry = JSON.parse(line); } catch { break; } // incomplete final append is not a receipt
      if (entry.type !== "custom_message" || entry.customType !== "background:event") continue;
      const values = entry.details?.eventIds;
      if (Array.isArray(values)) for (const id of values) if (typeof id === "string") ids.add(id);
    }
    return [...ids];
  } finally {
    await handle.close();
  }
}

/** Bound only from root session_start; constructor performs no I/O or command execution. */
export function registerBackgroundHost(
  pi: Pick<ExtensionAPI, "events">,
  ctx: ExtensionContext,
  manager: { getRecord(id: string): AgentRecord | undefined },
): BackgroundHost {
  const sessionManager = ctx.sessionManager;
  const rootSessionId = sessionManager.getSessionId();
  const attachment = Object.freeze({});
  const bindings = new Set<BackgroundAgentBinding>();
  const cleanupFailures: string[] = [];
  let cleanupFailureCount = 0;
  let connection: BackgroundConnection | undefined;
  let connected = false;
  let closed = false;
  let shutdown: Promise<void> | undefined;
  const offer: BackgroundHostOffer = Object.freeze({
    version: 1,
    sessionManager,
    attachment,
    connect(factory: (manager: { getRecord(id: string): AgentRecord | undefined }) => BackgroundConnection) {
      if (closed || connected || ctx.sessionManager !== sessionManager || sessionManager.getSessionId() !== rootSessionId) {
        throw new Error("Background host runtime unavailable or already attached");
      }
      connection = factory(manager);
      connected = true;
      return () => host.dispose("root_shutdown");
    },
  });
  const unsubscribe = pi.events.on(BACKGROUND_HOST_REQUEST, (data) => {
    const request = data as { version?: unknown; accept?: unknown } | null;
    if (!closed && request?.version === 1 && typeof request.accept === "function") request.accept(offer);
  });
  const host: BackgroundHost = {
    rootSessionId,
    grantDescendant(parent, child, actions) {
      if (closed || !connection || manager.getRecord(child.id) !== child
        || (parent && manager.getRecord(parent.id) !== parent)) throw new Error("Background descendant unavailable");
      return connection.grantDescendant(parent?.id, child.id, actions);
    },
    capture(record) {
      let revoked = false;
      let handle: BackgroundChildHandle | undefined;
      let registered = false;
      let cleanup: Promise<void> | undefined;
      let session = record.session;
      const live = () => {
        if (closed || revoked) return false;
        if (manager.getRecord(record.id) !== record || record.rootSessionId !== rootSessionId
          || (session && session !== record.session)
          || (record.status !== "queued" && record.status !== "running")) {
          revoked = true;
          return false;
        }
        session ??= record.session;
        return true;
      };
      const delivery: BackgroundDeliveryState = {
        eligible(origin) {
          if (!live() || record.status !== "running" || !record.session?.isStreaming) return false;
          const branch = record.session.sessionManager.getBranch();
          return origin.leafEntryId === "session-root" || branch.some(entry => entry.id === origin.leafEntryId);
        },
        async persistedEventIds() {
          if (!live() || !record.session) return [];
          const ids = await readPersistedEventIds(record);
          return live() ? ids : [];
        },
        // There is no independently wakeable idle-child state in this manager.
        // A nonstreaming running record may be between prompt resolution and termination.
        settled: () => false,
      };
      const binding: BackgroundAgentBinding = {
        sessionCreated() {
          session ??= record.session;
          handle?.state(); // latch the library's exact first session too
        },
        createTool(profile, invocation, commandPrefix) {
          if (!live() || registered || !connection) return undefined;
          registered = true;
          handle = connection.register(record, profile, delivery);
          const capability = handle.capability;
          if (!profile.toolAllowed || !profile.enforcementAvailable || !capability) return undefined;
          return {
            name: "background",
            label: "Background",
            description: profile.readOnly
              ? "Observe only this agent's background jobs (list/status/read)."
              : "Start, observe or stop this agent's session-scoped background jobs. Start requires execution authorization.",
            parameters: Type.Object({
              action: Type.String({ description: profile.allowedActions.join(", ") }),
              name: Type.Optional(Type.String()), command: Type.Optional(Type.String()),
              cwd: Type.Optional(Type.String()), timeoutMs: Type.Optional(Type.Number()),
              lifetime: Type.Optional(Type.String()), notify: Type.Optional(Type.String()),
              delivery: Type.Optional(Type.String()), jobId: Type.Optional(Type.String()),
              cursor: Type.Optional(Type.String()), limit: Type.Optional(Type.Number()),
              stream: Type.Optional(Type.String()), maxLines: Type.Optional(Type.Number()),
              maxBytes: Type.Optional(Type.Number()),
            }, { additionalProperties: false }),
            async execute(toolCallId, params, signal) {
              if (!live()) throw new Error("Background child capability revoked");
              const input = params as Record<string, unknown>;
              const request = commandPrefix && input.action === "start" && typeof input.command === "string"
                ? { ...input, command: `${commandPrefix}\n${input.command}` } : params;
              const result = await capability.execute(request, invocation(toolCallId), signal);
              return { content: [{ type: "text", text: JSON.stringify(result) }], details: result };
            },
          };
        },
        revoke(reason) {
          revoked = true; // synchronous fence even when the runner has not registered yet
          if (!cleanup) {
            cleanup = Promise.resolve(handle?.revoke(reason)).then(() => {});
            void cleanup.then(() => {
              bindings.delete(binding);
            }, (error: unknown) => {
              bindings.delete(binding);
              const message = (error instanceof Error ? error.message : String(error)).slice(0, 2048);
              record.backgroundCleanupError = message;
              cleanupFailureCount++;
              if (cleanupFailures.length < 32) cleanupFailures.push(message);
            });
          }
          return cleanup;
        },
      };
      bindings.add(binding);
      return binding;
    },
    dispose(reason) {
      if (shutdown) return shutdown;
      closed = true;
      unsubscribe();
      const tasks = [...bindings].map(binding => binding.revoke(reason));
      if (connection) tasks.push(Promise.resolve(connection.dispose(reason)).then(() => {}));
      shutdown = Promise.allSettled(tasks).then(results => {
        const errors = results.flatMap(result => result.status === "rejected" ? [String(result.reason).slice(0, 2048)] : []);
        if (errors.length || cleanupFailureCount) {
          throw new AggregateError([...cleanupFailures, ...errors].map(message => new Error(message)),
            `Background child cleanup failed (${cleanupFailureCount} binding failures; up to 32 details retained)`);
        }
      });
      return shutdown;
    },
  };
  pi.events.emit(BACKGROUND_HOST_READY, offer);
  return host;
}
