import { showHUD, showToast, Toast } from "@raycast/api";
import { getAutoStatus, run } from "./lib/dotfiles";

export default async function Command() {
  try {
    const { enabled } = await getAutoStatus();
    const next = enabled ? "off" : "on";
    await run(["--auto", next]);
    await showHUD(next === "on" ? "🌗 Auto light/dark: on" : "🌗 Auto light/dark: off");
  } catch (e) {
    await showToast({
      style: Toast.Style.Failure,
      title: "Toggle failed",
      message: String(e),
    });
  }
}
