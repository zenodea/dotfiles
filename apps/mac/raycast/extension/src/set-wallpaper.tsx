import { useEffect, useState } from "react";
import { existsSync } from "node:fs";
import {
  Action,
  ActionPanel,
  Grid,
  Icon,
  showToast,
  Toast,
  showHUD,
  closeMainWindow,
} from "@raycast/api";
import { getWallpapers, repoRoot, run } from "./lib/dotfiles";

interface State {
  wallpapers: string[];
  loading: boolean;
  error?: string;
}

export default function Command() {
  const [state, setState] = useState<State>({ wallpapers: [], loading: true });
  const dir = `${repoRoot()}/wallpapers`;

  async function load() {
    try {
      const wallpapers = await getWallpapers();
      setState({ wallpapers, loading: false });
    } catch (e) {
      setState({ wallpapers: [], loading: false, error: String(e) });
    }
  }

  useEffect(() => {
    load();
  }, []);

  useEffect(() => {
    if (state.error) {
      showToast({
        style: Toast.Style.Failure,
        title: "Could not load wallpapers",
        message: state.error,
      });
    }
  }, [state.error]);

  async function setWallpaper(name: string) {
    await closeMainWindow();
    const toast = await showToast({ style: Toast.Style.Animated, title: `Setting ${name}…` });
    try {
      await run(["--wallpaper", name]);
      toast.style = Toast.Style.Success;
      toast.title = "Wallpaper set";
      await showHUD(`🖼️ ${name}`);
    } catch (e) {
      toast.style = Toast.Style.Failure;
      toast.title = "Failed";
      toast.message = String(e);
    }
  }

  async function setRandom() {
    await closeMainWindow();
    const toast = await showToast({ style: Toast.Style.Animated, title: "Setting random…" });
    try {
      await run(["--wallpaper", "random"]);
      toast.style = Toast.Style.Success;
      toast.title = "Wallpaper set";
      await showHUD("🖼️ random");
    } catch (e) {
      toast.style = Toast.Style.Failure;
      toast.title = "Failed";
      toast.message = String(e);
    }
  }

  return (
    <Grid
      isLoading={state.loading}
      columns={4}
      inset={Grid.Inset.Small}
      searchBarPlaceholder="Search wallpapers…"
    >
      <Grid.Item
        content={{ source: Icon.Shuffle }}
        title="Random"
        actions={
          <ActionPanel>
            <Action title="Set Random Wallpaper" icon={Icon.Shuffle} onAction={setRandom} />
          </ActionPanel>
        }
      />
      {state.wallpapers.map((name) => {
        const path = `${dir}/${name}`;
        const content = existsSync(path) ? path : Icon.Image;
        return (
          <Grid.Item
            key={name}
            content={content}
            title={name}
            actions={
              <ActionPanel>
                <Action
                  title="Set Wallpaper"
                  icon={Icon.Image}
                  onAction={() => setWallpaper(name)}
                />
                <Action.CopyToClipboard title="Copy Filename" content={name} />
                <Action.ShowInFinder path={path} />
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
    </Grid>
  );
}
