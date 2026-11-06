import { useEffect, useState } from "react";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import {
  Action,
  ActionPanel,
  Color,
  Detail,
  environment,
  Icon,
  List,
  showToast,
  Toast,
  showHUD,
  closeMainWindow,
} from "@raycast/api";
import { getCurrentTheme, getThemes, repoRoot, run, wallpaperPreview } from "./lib/dotfiles";

interface State {
  themes: string[];
  current: string;
  loading: boolean;
  error?: string;
}

function themeSource(name: string): string {
  try {
    return readFileSync(`${repoRoot()}/themes/${name}.sh`, "utf8");
  } catch {
    return "";
  }
}

/** Pull the ACCENT color hex out of a theme's palette definition (e.g. ACCENT=ff0000). */
function accentOf(src: string): string | undefined {
  const m = src.match(/^ACCENT=["']?([0-9a-fA-F]{6})/m);
  return m?.[1];
}

/** The theme's wallpaper filename (e.g. WALLPAPER="064-blood-moon-cathedral.png"). */
function wallpaperOf(src: string): string | undefined {
  const m = src.match(/^WALLPAPER=["']?([^"'\s]+)/m);
  return m?.[1];
}

/** Palette colors in file order, e.g. [["BG", "1c1917"], ...]. */
function paletteOf(src: string): [string, string][] {
  return [...src.matchAll(/^([A-Z_]+)=["']?([0-9a-fA-F]{6})["']?\s*$/gm)].map((m) => [m[1], m[2]]);
}

/**
 * Swatch card drawn on the theme's own background, written as an SVG to the
 * extension's support dir so markdown can show it. Rewritten only on change.
 */
function paletteCard(name: string, src: string): string | undefined {
  const colors = paletteOf(src);
  if (colors.length === 0) return undefined;
  const hex = Object.fromEntries(colors);
  const cols = Math.ceil(colors.length / 2);
  const cell = 480 / cols;
  const cells = colors.map(([key, value], i) => {
    const x = (i % cols) * cell + 6;
    const y = Math.floor(i / cols) * 46 + 10;
    return (
      `<rect x="${x}" y="${y}" width="${cell - 12}" height="22" rx="5" fill="#${value}" stroke="#${hex.BORDER ?? value}"/>` +
      `<text x="${x + (cell - 12) / 2}" y="${y + 35}" text-anchor="middle">${key.toLowerCase()}</text>`
    );
  });
  const svg =
    `<svg xmlns="http://www.w3.org/2000/svg" width="480" height="102" viewBox="0 0 480 102">` +
    `<rect width="480" height="102" rx="10" fill="#${hex.BG ?? "000000"}"/>` +
    `<g font-family="-apple-system, sans-serif" font-size="10" fill="#${hex.FG ?? "ffffff"}">${cells.join("")}</g></svg>`;
  const path = `${environment.supportPath}/palette-${name}.svg`;
  try {
    if (readFileSync(path, "utf8") === svg) return path;
  } catch {
    // Not written yet.
  }
  try {
    mkdirSync(environment.supportPath, { recursive: true });
    writeFileSync(path, svg);
    return path;
  } catch {
    return undefined;
  }
}

/**
 * Markdown image of a local file, optionally sized in points. Raycast ignores
 * raycast-height on its own and stretches to the pane width, so pass both.
 */
function image(alt: string, path: string, size?: [number, number]): string {
  const query = size ? `?raycast-width=${size[0]}&raycast-height=${size[1]}` : "";
  return `![${alt}](${encodeURI(`file://${path}`)}${query})`;
}

/**
 * Side pane: wallpaper and swatch card, under the pane's width (Raycast stretches
 * images that only set a height). Both are 352pt wide, keeping
 * the 16:9 preview and 480x102 card aspect ratios.
 */
function detailMarkdown(name: string, src: string, wallpaper?: string): string {
  if (!src) return "_No preview available._";
  const preview = wallpaper ? wallpaperPreview(wallpaper) : undefined;
  const card = paletteCard(name, src);
  return [preview && image(wallpaper ?? "", preview, [352, 198]), card && image("palette", card, [352, 75])]
    .filter(Boolean)
    .join("\n\n");
}

/** Full-window preview: large wallpaper, swatches, and the whole theme file. */
function fullMarkdown(name: string, src: string, wallpaper?: string): string {
  const preview = wallpaper ? wallpaperPreview(wallpaper) : undefined;
  const card = paletteCard(name, src);
  return [
    `# ${name}`,
    preview && image(wallpaper ?? "", preview),
    card && image("palette", card),
    src ? `\`\`\`bash\n${src}\n\`\`\`` : "_No theme file found._",
  ]
    .filter(Boolean)
    .join("\n\n");
}

export default function Command() {
  const [state, setState] = useState<State>({ themes: [], current: "", loading: true });

  async function load() {
    try {
      const [themes, current] = await Promise.all([getThemes(), getCurrentTheme()]);
      setState({ themes, current, loading: false });
    } catch (e) {
      setState({ themes: [], current: "", loading: false, error: String(e) });
    }
  }

  useEffect(() => {
    load();
  }, []);

  useEffect(() => {
    if (state.error) {
      showToast({
        style: Toast.Style.Failure,
        title: "Could not load themes",
        message: state.error,
      });
    }
  }, [state.error]);

  async function switchTheme(name: string) {
    await closeMainWindow();
    const toast = await showToast({ style: Toast.Style.Animated, title: `Switching to ${name}…` });
    try {
      await run(["--theme", name]);
      toast.style = Toast.Style.Success;
      toast.title = `Theme: ${name}`;
      await showHUD(`🎨 ${name}`);
      setState((s) => ({ ...s, current: name }));
    } catch (e) {
      toast.style = Toast.Style.Failure;
      toast.title = "Switch failed";
      toast.message = String(e);
    }
  }

  return (
    <List isLoading={state.loading} searchBarPlaceholder="Search themes…" isShowingDetail>
      {state.themes.map((name) => {
        const isCurrent = name === state.current;
        const isLight = name.endsWith("-light");
        const src = themeSource(name);
        const accent = accentOf(src);
        const wallpaper = wallpaperOf(src);
        return (
          <List.Item
            key={name}
            title={name}
            icon={
              isCurrent
                ? { source: Icon.CheckCircle, tintColor: Color.Green }
                : { source: isLight ? Icon.Sun : Icon.Moon, tintColor: Color.SecondaryText }
            }
            accessories={isCurrent ? [{ tag: { value: "active", color: Color.Green } }] : undefined}
            detail={
              <List.Item.Detail
                markdown={detailMarkdown(name, src, wallpaper)}
                metadata={
                  <List.Item.Detail.Metadata>
                    <List.Item.Detail.Metadata.Label
                      title="Appearance"
                      text={isLight ? "Light" : "Dark"}
                    />
                    {accent ? (
                      <List.Item.Detail.Metadata.Label
                        title="Accent"
                        text={`#${accent}`}
                        icon={{ source: Icon.CircleFilled, tintColor: `#${accent}` }}
                      />
                    ) : null}
                    {wallpaper ? (
                      <List.Item.Detail.Metadata.Label
                        title="Wallpaper"
                        text={wallpaper}
                        icon={Icon.Image}
                      />
                    ) : null}
                    <List.Item.Detail.Metadata.Label
                      title="Status"
                      text={isCurrent ? "Active" : "Available"}
                    />
                  </List.Item.Detail.Metadata>
                }
              />
            }
            actions={
              <ActionPanel>
                <Action
                  title="Switch to Theme"
                  icon={Icon.Brush}
                  onAction={() => switchTheme(name)}
                />
                <Action.Push
                  title="Show Full Preview"
                  icon={Icon.Maximize}
                  shortcut={{ modifiers: ["cmd"], key: "y" }}
                  target={
                    <Detail
                      navigationTitle={name}
                      markdown={fullMarkdown(name, src, wallpaper)}
                      actions={
                        <ActionPanel>
                          <Action
                            title="Switch to Theme"
                            icon={Icon.Brush}
                            onAction={() => switchTheme(name)}
                          />
                        </ActionPanel>
                      }
                    />
                  }
                />
                <Action.CopyToClipboard title="Copy Theme Name" content={name} />
                <Action
                  title="Reload"
                  icon={Icon.ArrowClockwise}
                  shortcut={{ modifiers: ["cmd"], key: "r" }}
                  onAction={load}
                />
              </ActionPanel>
            }
          />
        );
      })}
    </List>
  );
}
