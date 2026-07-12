# dotfiles

Personal configs for Linux and macOS, with a live theme system.

## Install

```sh
./install.sh
```

Symlinks configs (`general/` always, `linux/` or `mac/` per OS) and the
`dotfiles` CLI. Existing files are backed up as `<file>.bak`.

## Theme switching

```sh
dotfiles --theme <name>     # switch everything, live (tab-completes)
dotfiles --pick             # interactive picker
dotfiles --random           # surprise me
dotfiles --list             # available themes
```

Palettes live in `themes/<name>.sh`, app configs in `templates/`.
A switch regenerates the configs and reloads running apps.

Themed: hyprland · waybar · fuzzel · rofi · vifm · sketchybar · borders ·
Alfred · Raycast · ghostty · nvim · zed · Firefox · Obsidian · wallpaper

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

`mac/alfred/dotfiles/` is an Alfred workflow wrapping the CLI. `install.sh`
symlinks it into Alfred's workflow folder, so editing it in the repo edits the
installed workflow — restart Alfred once after the first install.

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
