import { stripTerminalSequences } from "@earendil-works/pi-tui";
import type { AgentRecord } from "../types.js";
import { displayState, type WorkflowAgentEntry, type WorkflowDisplayState } from "../workflow/progress.js";

/** Display-only membership; `call` always refers to an actual workflow call. */
export type WorkflowAgentRow =
  | { kind: "call"; key: string; call: WorkflowAgentEntry; recordId?: string; record?: AgentRecord; depth: 0 }
  | { kind: "descendant"; key: string; call: WorkflowAgentEntry; recordId: string; record: AgentRecord; parentRecordId: string; ancestorIds: readonly string[]; depth: number };

/** Expand collapsed calls without creating progress entries or changing accounting. */
export function workflowAgentRows(
  calls: readonly WorkflowAgentEntry[],
  records: readonly AgentRecord[],
): WorkflowAgentRow[] {
  const byId = new Map(records.map(record => [record.id, record]));
  const children = new Map<string, AgentRecord[]>();
  for (const record of byId.values()) {
    if (!record.parentAgentId) continue;
    const siblings = children.get(record.parentAgentId) ?? [];
    siblings.push(record);
    children.set(record.parentAgentId, siblings);
  }
  for (const siblings of children.values()) {
    siblings.sort((a, b) => a.startedAt - b.startedAt || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  }

  // Resuming a record can produce another real call. Attribute its descendants
  // to the latest call, while retaining every direct call's historical row.
  const latestCall = new Map<string, WorkflowAgentEntry>();
  for (const call of calls) {
    if (!call.recordId) continue;
    const previous = latestCall.get(call.recordId);
    if (!previous || previous.index < call.index) latestCall.set(call.recordId, call);
  }
  const seen = new Set(latestCall.keys());
  const rows: WorkflowAgentRow[] = [];
  for (const call of calls) {
    rows.push({ kind: "call", key: `call:${call.index}`, call, recordId: call.recordId,
      record: call.recordId ? byId.get(call.recordId) : undefined, depth: 0 });
    if (!call.recordId || latestCall.get(call.recordId) !== call) continue;
    const rootId = call.recordId;

    // Iterative traversal keeps malformed cycles and deep trees bounded. A record
    // with its own direct call belongs to that row, not a duplicate nested row.
    const pending = [...(children.get(call.recordId) ?? [])].reverse().map(record => ({ record, depth: 1, ancestorIds: [rootId] }));
    while (pending.length) {
      const item = pending.pop();
      if (!item || seen.has(item.record.id)) continue;
      const { record, depth, ancestorIds } = item;
      seen.add(record.id);
      rows.push({ kind: "descendant", key: `record:${record.id}`, call, recordId: record.id,
        record, parentRecordId: record.parentAgentId!, ancestorIds, depth });
      for (const child of [...(children.get(record.id) ?? [])].reverse()) {
        pending.push({ record: child, depth: depth + 1, ancestorIds: [...ancestorIds, record.id] });
      }
    }
  }
  return rows;
}

/** A display identity is not a workflow call or a lifecycle-control argument. */
export interface WorkflowInlineActivation {
  key: string;
  recordId?: string;
  callIndex: number;
  rootRecordId?: string;
  ancestorIds: readonly string[];
  label: string;
  modelId?: string;
  model?: string;
  thinking?: string;
}

export function workflowAgentRowLabel(row: WorkflowAgentRow): string {
  const record = row.record;
  const named = record?.alias ?? record?.handle;
  const text = row.kind === "call" ? row.call.label : named ? `@${named}` : `${row.record.type}:${row.recordId.slice(0, 8)}`;
  return stripTerminalSequences(text).replace(/[\x00-\x1f\x7f-\x9f]/g, " ").replace(/\s+/g, " ").trim();
}

/** Never borrow the planner's requested/effective model for a descendant. */
export function workflowAgentRowMetadata(row: WorkflowAgentRow): Pick<WorkflowInlineActivation, "modelId" | "model" | "thinking"> {
  const model = row.record?.session?.model;
  const invocation = row.record?.invocation;
  const call = row.kind === "call" ? row.call : undefined;
  return {
    modelId: model ? `${model.provider}/${model.id}` : invocation?.modelId ?? call?.modelId,
    model: model?.name ?? invocation?.modelName ?? call?.model,
    thinking: row.record?.session?.thinkingLevel ?? invocation?.thinking ?? call?.thinking,
  };
}

export function workflowAgentRowState(row: WorkflowAgentRow, active: boolean): WorkflowDisplayState {
  if (row.kind === "call") return displayState(row.call, active);
  switch (row.record.status) {
    case "running": return "running";
    case "queued": return "queued";
    case "completed": case "steered": return "done";
    case "error": return "failed";
    default: return "interrupted";
  }
}
