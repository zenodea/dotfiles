# Dotfiles — Raycast Extension

A Raycast front-end for the `dotfiles` CLI in this repo. Switch themes and
fonts, set wallpapers, toggle auto light/dark, and run maintenance without
touching a terminal.

## Commands

| Command                    | Mode    | What it does                                                                                                  |
| -------------------------- | ------- | ------------------------------------------------------------------------------------------------------------- |
| **Search Themes**          | view    | Browse themes with a live preview of the palette; Enter switches (`dotfiles -t`). The active theme is marked. |
| **Search Fonts**           | view    | Browse fonts; Enter switches (`dotfiles -f`).                                                                 |
| **Set Wallpaper**          | view    | Thumbnail grid of `wallpapers/`; Enter sets it (`dotfiles -w`). Includes a Random tile.                       |
| **Random Theme**           | no-view | Switches to a random theme (`dotfiles -r`).                                                                   |
| **Toggle Auto Light/Dark** | no-view | Flips auto light/dark mode (`dotfiles --auto on/off`).                                                        |
| **Dotfiles Maintenance**   | view    | Run Update, Doctor, Save, Sync, and toggle auto — output shown inline.                                        |

## How it talks to the CLI

Everything shells out to the `dotfiles` binary via
[`src/lib/dotfiles.ts`](src/lib/dotfiles.ts). Raycast does not inherit your
shell `PATH`, so the binary is resolved in this order:

1. The **Dotfiles Binary** preference (if set)
2. `~/.local/bin/dotfiles` (the symlink `install.sh` creates)
3. `~/dotfiles/bin/dotfiles`
4. `/usr/local/bin/dotfiles`, `/opt/homebrew/bin/dotfiles`

Lists come from the machine-readable subcommands (`--themes-plain`,
`--fonts-plain`, `--wallpapers-plain`, `--current`, `--auto status`).

## Development

```bash
cd apps/mac/raycast/extension
npm install
npm run dev        # ray develop — loads the extension into Raycast live
npm run typecheck  # tsc --noEmit
npm run lint       # ray lint
npm run build      # ray build
```

`npm run dev` imports the extension into your local Raycast in development mode;
no publishing to the Raycast Store is required. Leave `ray develop` running and
edits hot-reload.

## Notes

- Theme switches reload running apps (sketchybar, terminals, etc.), so they take
  a second or two — a toast/HUD confirms completion.
- Wallpaper thumbnails point directly at the files in `../../../wallpapers/`.
- A theme switch behaves exactly as it does from the terminal: it changes the
  wallpaper, and flips system Light/Dark when auto mode is off (auto mode drives
  appearance itself). Setting the wallpaper/appearance uses `osascript`, so the
  first time you'll get a one-time macOS prompt — grant Raycast access under
  System Settings → Privacy & Security → Automation → **Raycast → System
  Events**, and it never asks again.

## Troubleshooting

### "sketchybar / borders / the bar didn't recolor"

Raycast launches commands with a minimal environment: `PATH` omits Homebrew (so
`sketchybar` / `borders` are command-not-found) and `USER` is unset (so
`sketchybar-msg` aborts with `'env USER' not set!`). Both would make the bar
stay on stale colors. The dotfiles CLI now guards `PATH` and `USER` itself in
`lib/common.sh`, and the extension also sets them before invoking the CLI, so
all reload steps resolve regardless of how it's launched.
