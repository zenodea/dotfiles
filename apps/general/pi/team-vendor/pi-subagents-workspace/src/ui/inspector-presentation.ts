import { Markdown, type MarkdownTheme, stripTerminalSequences, truncateToWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui";
import type { Theme } from "./agent-widget.js";
import { type WorkspaceClick, WorkspaceTabs } from "./workspace-tabs.js";

export function cleanInspectorText(text: string): string {
  return stripTerminalSequences(text).replaceAll("\u0000", "");
}

export function markdownTheme(theme: Theme): MarkdownTheme {
  return {
    heading: theme.bold,
    link: text => theme.fg("accent", text),
    linkUrl: text => theme.fg("dim", text),
    code: text => theme.fg("accent", text),
    codeBlock: text => text,
    codeBlockBorder: text => theme.fg("dim", text),
    quote: text => text,
    quoteBorder: text => theme.fg("dim", text),
    hr: text => theme.fg("dim", text),
    listBullet: text => theme.fg("accent", text),
    bold: theme.bold,
    italic: text => text,
    strikethrough: text => text,
    underline: text => text,
  };
}

/** Metadata only: native Activity never passes through this presentation layer. */
export class InspectorBody {
  readonly lines: string[] = [];
  private disclosures: WorkspaceTabs<string>[] = [];

  constructor(private width: number, private theme: Theme, private expanded: Set<string>) {}

  heading(label: string): void {
    if (this.lines.length && this.lines.at(-1) !== "") this.lines.push("");
    this.lines.push(truncateToWidth(this.theme.bold(this.theme.fg("accent", cleanInspectorText(label))), this.width));
  }

  text(value: string, markdown = false): void {
    const safe = cleanInspectorText(value);
    const lines = markdown
      ? new Markdown(safe, 0, 0, markdownTheme(this.theme)).render(this.width)
      : wrapTextWithAnsi(safe, this.width);
    this.lines.push(...lines.map(line => truncateToWidth(line, this.width)));
  }

  /** Pack short fields together; wrap naturally at narrow terminal widths. */
  fields(fields: readonly (readonly [string, string | undefined])[]): void {
    const text = fields.filter(([, value]) => value !== undefined && value.trim() !== "")
      .map(([label, value]) => `${this.theme.fg("muted", `${cleanInspectorText(label).replace(/[\r\n\t]/g, " ")} `)}${cleanInspectorText(value!).replace(/[\r\n\t]/g, " ")}`)
      .join(this.theme.fg("dim", "  ·  "));
    if (text) this.lines.push(...wrapTextWithAnsi(text, this.width).map(line => truncateToWidth(line, this.width)));
  }

  disclosure(label: string, content: () => void): void {
    if (this.lines.length && this.lines.at(-1) !== "") this.lines.push("");
    const tabs = new WorkspaceTabs<string>();
    this.lines.push(tabs.render(this.width, this.lines.length, [label], name =>
      this.theme.fg("muted", `${this.expanded.has(name) ? "▾" : "▸"} ${name}`)));
    this.disclosures.push(tabs);
    if (this.expanded.has(label)) { this.lines.push(""); content(); }
  }

  /** Coordinates are body-local, after the document subtracts its header. */
  toggle(event: WorkspaceClick): boolean {
    for (const disclosure of this.disclosures) {
      const label = disclosure.hit(event);
      if (!label) continue;
      if (this.expanded.has(label)) this.expanded.delete(label);
      else this.expanded.add(label);
      return true;
    }
    return false;
  }
}
