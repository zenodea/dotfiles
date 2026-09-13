import { showHUD, showToast, Toast } from "@raycast/api";
import { getCurrentTheme, run } from "./lib/dotfiles";

export default async function Command() {
  try {
    await run(["--random"]);
    const current = await getCurrentTheme();
    await showHUD(`🎲 ${current || "theme switched"}`);
  } catch (e) {
    await showToast({
      style: Toast.Style.Failure,
      title: "Random theme failed",
      message: String(e),
    });
  }
}
