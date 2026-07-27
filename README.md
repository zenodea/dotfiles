# dotfiles

Personal configs for Linux and macOS, with a live theme system.

## Install

```sh
git clone --recurse-submodules https://github.com/zenodea/dotfiles_nixless
./install.sh
```

Symlinks the configs and the `dotfiles` CLI, then renders the active theme.
Existing files are backed up as `<file>.bak`. If you cloned without
`--recurse-submodules`, `install.sh` checks out the wallpapers submodule for
you.

## Layout

Everything for one app lives in one directory:

```
apps/<general|mac|linux>/<name>/
    app.sh        how to render + reload it
    templates/    its themed configs
    config/       its static config → symlinked to ~/.config/<name>

home/<general|mac|linux>/    mirrors $HOME (.zshrc, scripts/, …)
themes/<name>.sh             the palettes
wallpapers/                  submodule → github.com/zenodea/wallpapers
```

`general/` applies everywhere, `mac/` and `linux/` only on that OS. Apps with
no `app.sh` (lazygit, yazi, aerospace) are static config that just gets
symlinked; apps with no `config/` (ghostty, borders, fuzzel) are wholly
generated and render straight to `~/.config`.

## Theme switching

```sh
dotfiles --theme <name>     # switch everything, live (tab-completes)
dotfiles --pick             # interactive picker
dotfiles --random           # surprise me
dotfiles --list             # available themes
```

A switch regenerates every app's config from its templates and reloads it live.

Themed: hyprland · waybar · fuzzel · rofi · vifm · sketchybar · borders ·
Alfred · Raycast · ghostty · nvim · zed · Firefox · Obsidian · wallpaper

## Light / dark

```sh
dotfiles --auto on          # follow the system's light/dark setting
dotfiles --auto off
dotfiles --auto             # status
```

A theme is light or dark by virtue of its background's brightness — nothing
declares it, and the terminal opacity and Zed base theme follow from that too.
A *pair* is one name plus a suffix: `gruvbox` is the dark half, `gruvbox-light`
the light one. `--auto on` tracks the pair the active theme belongs to and
refuses if the other half doesn't exist.

All twelve themes are paired. To add another, drop a `<name>-light.sh` next to
the dark one; it's picked up with no further wiring.

On macOS the system is the schedule — set Appearance to **Auto** in System
Settings and you inherit real sunrise/sunset, plus manual ⌃-click toggles. A
launchd agent polls once a minute and only re-renders when the answer changed.
Linux has no such setting, so the boundaries come from the clock (07:00/19:00,
override with `DOTFILES_DAY_START` / `DOTFILES_DAY_END`) on a systemd user
timer. `--auto on` installs the agent or timer; `--auto off` removes it.

Picking a theme by hand while auto is on wins until light/dark next flips — so
a mid-afternoon `dotfiles --theme dracula` isn't undone a minute later. If the
theme you pick is itself paired, auto rebases onto it.

A light half inherits the dark half's `WALLPAPER`, so the desktop stays put
across a flip. Give it its own `WALLPAPER=` to override that.

`MUTED` — comments, placeholders, line numbers, inactive labels — is derived
rather than declared: `FG` is faded toward `BG` only as far as the 4.5:1
body-text contrast floor allows, so muted text stays as quiet as it can be
without going unreadable. This used to reuse `BORDER`, which is tuned to sit
*close* to `BG` so dividers stay quiet, and on a light palette that left
comments around 1.2–1.9:1 against the background. A theme can set `MUTED=`
itself to reclaim its upstream comment hue; the derivation is then skipped.

One note on what auto mode deliberately does *not* do: on macOS it never writes
the system appearance (`apps/mac/appearance/` skips while auto is on). Setting
Light or Dark explicitly is what turns Auto *off*, so doing it would disable the
schedule being followed.

### Adding an app

Drop a directory in `apps/<general|mac|linux>/<name>/` with an `app.sh`:

```sh
render() {                          # paths are relative to this app's dir
    generate config "$HOME/.config/ghostty/config"
}

reload() {                          # poke the running app (optional)
    pgrep -x ghostty > /dev/null 2>&1 || return 0
    pkill -SIGUSR2 ghostty
    note "reloaded"
}
```

`generate <template> <dest>` reads from the app's own `templates/`; `<dest>` is
absolute for a live path, or relative to the app dir (i.e. `config/…`) for
something symlinked into `~/.config`. A `general/` app whose reload differs per
OS defines `reload_mac` and `reload_linux` instead of `reload`.

`switch-theme` sources each `app.sh` in its own subshell with the palette
exported (`$BG`, `$ACCENT`, `$ACCENT_RGB`, `$THEME_APPEARANCE`, …) and
`generate`/`copy`/`note`/`skip`/`have` available. An app that only pokes the
system (`mac/appearance`, `linux/gtk`) can define `reload` and skip `render`.
An app that fails is reported and skipped; the rest still run. Pass
`--no-reload` to render without touching running apps.

## Other commands

```sh
dotfiles --wallpaper <name|random>   # wallpaper only
dotfiles --update                    # git pull + re-apply theme
dotfiles --doctor                    # check symlinks, deps, drift
dotfiles --save [msg]                # add + commit + push
dotfiles --sync                      # re-run install.sh
dotfiles --current                   # print the active theme
```

## Alfred (macOS)

`apps/mac/alfred/workflows/dotfiles/` is an Alfred workflow wrapping the CLI.
`install.sh` symlinks it into Alfred's workflow folder, so editing it in the
repo edits the installed workflow — restart Alfred once after the first install.

Type `dotfiles` in Alfred, then:

| | |
|---|---|
| `theme <name>` | switch theme (⇥ to drill into the list) |
| `wallpaper <name>` | wallpaper only, `random` included |
| `random` | random theme |
| `update` / `sync` / `doctor` | output shown in Large Type |
| `save` | commit + push the repo |

## Notes

- After switching themes on one machine, run `dotfiles --update` on the
  other to pull and live-reload it there.
- Raycast needs Pro and one ⏎ in its popup; everything else is automatic.
- The rendered configs are gitignored — only the palette, the templates and
  `.current-theme` are tracked, so switching themes doesn't dirty the repo.
  `install.sh` renders them, which is why a fresh clone must run it first.
- `.auto-theme` (which pair auto mode tracks) is tracked too, so both machines
  agree; `install.sh` reinstalls the agent/timer when it's present. The pin
  that holds a manual pick is machine-local and gitignored.
- Auto mode rewrites `.current-theme` twice a day, so the repo goes dirty on
  its own — `--doctor` will say so, and `--save` clears it.
