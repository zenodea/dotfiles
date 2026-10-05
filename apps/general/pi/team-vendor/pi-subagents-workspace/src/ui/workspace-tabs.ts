import { type TuiMouseEvent, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

export type WorkspaceClick = Pick<TuiMouseEvent, "type" | "button" | "x" | "y">;

/** Hit ranges come from the same styled, clipped line that is painted. */
export class WorkspaceTabs<T extends string> {
  private row = -1;
  private hits: { tab: T; start: number; end: number }[] = [];

  render(width: number, row: number, tabs: readonly T[], label: (tab: T) => string, separator = "  "): string {
    this.row = row;
    this.hits = [];
    let line = "";
    for (const tab of tabs) {
      if (line) line += separator;
      const start = visibleWidth(line);
      line += label(tab);
      this.hits.push({ tab, start, end: visibleWidth(line) });
    }
    // Keep the truncation marker out of the hit map, including tiny widths.
    const ellipsis = "...";
    const end = visibleWidth(line) > width ? Math.max(0, width - visibleWidth(ellipsis)) : width;
    this.hits = this.hits.map(hit => ({ ...hit, end: Math.min(hit.end, end) })).filter(hit => hit.start < hit.end);
    return truncateToWidth(line, width, ellipsis);
  }

  hit(event: WorkspaceClick): T | undefined {
    if (event.type !== "click" || event.button !== "left" || event.y !== this.row) return undefined;
    return this.hits.find(hit => event.x >= hit.start && event.x < hit.end)?.tab;
  }

  clear(): void {
    this.row = -1;
    this.hits = [];
  }
}
