import { stripTerminalSequences } from "@earendil-works/pi-tui";
import { type WorkflowAgentRow, workflowAgentRowLabel, workflowAgentRowMetadata, workflowAgentRowState } from "./workflow-agent-rows.js";
import { clampLine, type WorkflowCardColor, type WorkflowCardLine } from "./workflow-card.js";
import { agentRow, DEFAULT_PANE_BODY_ROWS, dialogRowGlyph, leftPaneWidth, paneFrame, type ResolvedWorkflowDialog, rightAlign, UNICODE_DIALOG_GLYPHS, WORKFLOW_DIALOG_COPY, windowRange } from "./workflow-dialog.js";

export interface WorkflowOverviewView extends Omit<ResolvedWorkflowDialog, "selectedEntry"> {
  visibleRows: WorkflowAgentRow[];
  hasDescendants: boolean;
  selectedRow?: WorkflowAgentRow;
}

export type WorkflowOverviewPane = "phases" | "agents";
export type WorkflowOverviewHit = { y: number; start: number; end: number; pane: WorkflowOverviewPane; index: number; key?: string };

const singleLine = (text: string) => stripTerminalSequences(text).replace(/[\x00-\x1f\x7f-\x9f]/g, " ").replace(/\s+/g, " ").trim();

/** The dialog's frame and agent rows, with workspace-local selection and hits. */
export function workflowOverviewPanes(view: WorkflowOverviewView, pane: WorkflowOverviewPane, width: number, now: number, spinnerFrame = 0): { lines: WorkflowCardLine[]; hits: WorkflowOverviewHit[] } {
  const glyphs = UNICODE_DIALOG_GLYPHS;
  const stacked = width < 48;
  const left = stacked ? width : leftPaneWidth(width);
  const right = stacked ? Math.max(0, width - 2) : width - left - 3;
  const capacity = Math.min(DEFAULT_PANE_BODY_ROWS, Math.max(view.groups.length, view.visibleAgents.length, 3));
  const phases = windowRange(view.clampedPhase, view.groups.length, capacity);
  // Stacked lists previously painted only actual call rows, not the frame's padding.
  const agentCapacity = stacked ? Math.min(capacity, Math.max(1, view.visibleAgents.length)) : capacity;
  const agents = windowRange(view.clampedAgent, view.visibleRows.length, agentCapacity);
  const phaseRows: WorkflowCardLine[] = [];
  const agentRows: WorkflowCardLine[] = [];
  const hits: WorkflowOverviewHit[] = [];
  const digits = String(view.groups.length).length;
  for (let index = phases.start; index < phases.end; index++) {
    const group = view.groups[index];
    const selected = index === view.clampedPhase;
    const color: WorkflowCardColor = selected ? "accent" : group.status === "done" ? "success" : group.status === "failed" ? "error" : "dim";
    const glyph = group.status === "done" ? glyphs.tick : group.status === "failed" ? glyphs.cross : String(index + 1);
    hits.push({ y: phaseRows.length + 1, start: stacked ? 0 : 1, end: stacked ? width : left + 1, pane: "phases", index });
    phaseRows.push(rightAlign([
      { text: " " }, { text: selected && pane === "phases" ? glyphs.pointer : " ", color: "accent" }, { text: " " },
      { text: glyph.padStart(digits), color }, { text: " " }, { text: singleLine(group.title), color },
    ], group.totalCount === 0 ? [] : [{ text: `${group.doneCount}/${group.totalCount} `, color }], left));
  }
  for (let index = agents.start; index < agents.end; index++) {
    const row = view.visibleRows[index];
    hits.push({ y: agentRows.length + (stacked ? phaseRows.length + 2 : 1), start: stacked ? 2 : left + 2,
      end: stacked ? width : width - 1, pane: "agents", index, key: row.key });
    const selected = pane === "agents" && row.key === view.selectedRow?.key;
    if (row.kind === "descendant") {
      const metadata = workflowAgentRowMetadata(row);
      const indent = "  ".repeat(Math.min(row.depth - 1, Math.max(0, Math.floor(right / 6))));
      agentRows.push(clampLine([
        { text: " " }, { text: selected ? glyphs.pointer : " ", color: "accent" },
        { text: ` ${indent}└─ `, color: "dim" }, dialogRowGlyph(workflowAgentRowState(row, view.workflowActive), glyphs, spinnerFrame),
        { text: ` ${workflowAgentRowLabel(row)}`, color: selected ? "accent" : undefined },
        { text: ` ${singleLine(metadata.model ?? metadata.modelId ?? "Unknown model")} · ${row.record.status} · ${singleLine(row.record.description)}`, color: "dim" },
      ], right));
      continue;
    }
    const entry = row.call;
    agentRows.push(agentRow({
      entry: { ...entry, label: singleLine(entry.label), model: entry.model && singleLine(entry.model),
        fallbackModel: entry.fallbackModel && singleLine(entry.fallbackModel), requestedModel: entry.requestedModel && singleLine(entry.requestedModel) },
      selected, compact: false, width: right, glyphs,
      workflowActive: view.workflowActive, spinnerFrame, now,
    }));
  }
  if (agentRows.length === 0) agentRows.push(clampLine([{ text: `   ${WORKFLOW_DIALOG_COPY.noAgents} yet`, color: "dim" }], right));
  const count = view.visibleAgents.length;
  const descendants = view.visibleRows.length - count;
  const title = `${singleLine(view.groups[view.clampedPhase]?.title ?? "Phases")} · ${count} ${descendants ? "call" : "agent"}${count === 1 ? "" : "s"}${descendants ? ` + ${descendants} nested` : ""}`;
  const lines: WorkflowCardLine[] = stacked ? [
    [{ text: "Phases", color: "muted", bold: true }], ...phaseRows,
    [{ text: `  ${title}`, color: "muted", bold: true }], ...agentRows.map(row => [{ text: "  " }, ...row]),
  ] : paneFrame({ leftTitle: "Phases", rightTitle: title, leftRows: phaseRows, rightRows: agentRows, width, bodyRows: capacity, glyphs });
  return { lines: lines.map(line => clampLine(line, width)), hits };
}
