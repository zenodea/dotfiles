import { useEffect, useState } from "react";
import { readFileSync } from "node:fs";
import {
  Action,
  ActionPanel,
  Color,
  Icon,
  List,
  showToast,
  Toast,
  showHUD,
  closeMainWindow,
} from "@raycast/api";
import { getCurrentTheme, getThemes, repoRoot, run } from "./lib/dotfiles";

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
                markdown={src ? `\`\`\`bash\n${src}\n\`\`\`` : "_No preview available._"}
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
