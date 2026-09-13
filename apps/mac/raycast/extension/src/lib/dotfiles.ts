import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir, userInfo } from "node:os";
import { promisify } from "node:util";
import { getPreferenceValues } from "@raycast/api";

const execFileAsync = promisify(execFile);

interface Preferences {
  dotfilesBin?: string;
}

/**
 * Resolve the dotfiles CLI. Raycast does not inherit the shell PATH, so we
 * check the user's preference first, then the well-known install locations.
 */
export function resolveBin(): string {
  const { dotfilesBin } = getPreferenceValues<Preferences>();
  const candidates = [
    dotfilesBin,
    `${homedir()}/.local/bin/dotfiles`,
    `${homedir()}/dotfiles/bin/dotfiles`,
    "/usr/local/bin/dotfiles",
    "/opt/homebrew/bin/dotfiles",
  ].filter((c): c is string => Boolean(c && c.trim()));

  for (const c of candidates) {
    if (existsSync(c)) return c;
  }
  // Fall back to the first candidate so the error message is actionable.
  return candidates[0] ?? "dotfiles";
}

/**
 * Build the environment the CLI runs under. Raycast launches commands with a
 * minimal environment, which breaks two reload steps:
 *
 * - PATH omits Homebrew, so `sketchybar` / `borders` are command-not-found and
 *   their reloads fail silently. We prepend the usual bin dirs.
 * - USER is unset, so `sketchybar-msg` aborts with "'env USER' not set!" and
 *   the bar never repaints. We fill it in.
 *
 * (The dotfiles CLI now guards both itself in lib/common.sh, so this is
 * belt-and-suspenders — but it keeps the extension correct on its own.)
 */
function cliEnv(): NodeJS.ProcessEnv {
  const extraPath = [
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/usr/bin",
    "/bin",
    "/usr/sbin",
    "/sbin",
  ];
  const path = [...extraPath, process.env.PATH ?? ""].filter(Boolean).join(":");
  const user = process.env.USER || userInfo().username;

  return { ...process.env, HOME: homedir(), USER: user, PATH: path };
}

/** Run the dotfiles CLI and return trimmed stdout. */
export async function run(args: string[]): Promise<string> {
  const bin = resolveBin();
  const { stdout } = await execFileAsync(bin, args, {
    // Give theme switches (which reload apps) room to finish.
    timeout: 60_000,
    maxBuffer: 8 * 1024 * 1024,
    env: cliEnv(),
  });
  return stdout.trim();
}

/** Parse a plain, one-item-per-line list from a CLI subcommand. */
export async function list(arg: string): Promise<string[]> {
  const out = await run([arg]);
  return out
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean);
}

export const getThemes = () => list("--themes-plain");
export const getFonts = () => list("--fonts-plain");
export const getWallpapers = () => list("--wallpapers-plain");

export async function getCurrentTheme(): Promise<string> {
  try {
    return await run(["--current"]);
  } catch {
    return "";
  }
}

export interface AutoStatus {
  enabled: boolean;
  raw: string;
}

/** Parse `dotfiles --auto status` output. */
export async function getAutoStatus(): Promise<AutoStatus> {
  const raw = await run(["--auto", "status"]);
  const enabled = /auto:\s*on/i.test(raw);
  return { enabled, raw };
}

/** Absolute path to the dotfiles repo root, derived from the binary path. */
export function repoRoot(): string {
  const bin = resolveBin();
  // ~/.local/bin/dotfiles is a symlink; the real repo is ~/dotfiles.
  const guess = `${homedir()}/dotfiles`;
  if (existsSync(guess)) return guess;
  // bin/dotfiles -> repo root is two levels up.
  return bin.replace(/\/bin\/dotfiles$/, "");
}
