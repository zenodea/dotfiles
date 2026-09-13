import { useEffect, useState } from "react";
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
import { getFonts, run } from "./lib/dotfiles";

interface State {
  fonts: string[];
  current: string;
  loading: boolean;
  error?: string;
}

/** `dotfiles --font` (no arg) lists fonts and marks the active one with "(active)". */
async function loadFonts(): Promise<{ fonts: string[]; current: string }> {
  const [fonts, listing] = await Promise.all([getFonts(), run(["--font"])]);
  const activeLine = listing.split("\n").find((l) => l.includes("(active)"));
  const current = activeLine?.replace(/\(active\)/, "").trim() ?? "";
  return { fonts, current };
}

export default function Command() {
  const [state, setState] = useState<State>({ fonts: [], current: "", loading: true });

  async function load() {
    try {
      const { fonts, current } = await loadFonts();
      setState({ fonts, current, loading: false });
    } catch (e) {
      setState({ fonts: [], current: "", loading: false, error: String(e) });
    }
  }

  useEffect(() => {
    load();
  }, []);

  useEffect(() => {
    if (state.error) {
      showToast({
        style: Toast.Style.Failure,
        title: "Could not load fonts",
        message: state.error,
      });
    }
  }, [state.error]);

  async function switchFont(name: string) {
    await closeMainWindow();
    const toast = await showToast({ style: Toast.Style.Animated, title: `Switching to ${name}…` });
    try {
      await run(["--font", name]);
      toast.style = Toast.Style.Success;
      toast.title = `Font: ${name}`;
      await showHUD(`🔤 ${name}`);
      setState((s) => ({ ...s, current: name }));
    } catch (e) {
      toast.style = Toast.Style.Failure;
      toast.title = "Switch failed";
      toast.message = String(e);
    }
  }

  return (
    <List isLoading={state.loading} searchBarPlaceholder="Search fonts…">
      {state.fonts.map((name) => {
        const isCurrent = name === state.current;
        return (
          <List.Item
            key={name}
            title={name}
            icon={
              isCurrent
                ? { source: Icon.CheckCircle, tintColor: Color.Green }
                : { source: Icon.Text, tintColor: Color.SecondaryText }
            }
            accessories={isCurrent ? [{ tag: { value: "active", color: Color.Green } }] : undefined}
            actions={
              <ActionPanel>
                <Action title="Switch to Font" icon={Icon.Text} onAction={() => switchFont(name)} />
                <Action.CopyToClipboard title="Copy Font Name" content={name} />
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
