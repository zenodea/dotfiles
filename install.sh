#!/usr/bin/env bash
# install.sh — symlink configs into place, then render the active theme.
#
# Layout:
#   apps/<general|mac|linux>/<name>/config/  → $HOME/.config/<name>
#   home/<general|mac|linux>/<path>          → $HOME/<path>
#
# general/ applies everywhere; mac/ and linux/ only on that OS.
#
# Pass --check to report what's linked without changing anything (dotfiles
# --doctor uses this, so the two can't drift).

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname -s)" in
    Darwin) PLATFORM="mac"   ;;
    Linux)  PLATFORM="linux" ;;
    *)      echo "Unsupported OS: $(uname -s)"; exit 1 ;;
esac

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

# Set by --check callers to count results; no-ops otherwise.
type ok   > /dev/null 2>&1 || ok()   { echo "  ✓ $1"; }
type warn > /dev/null 2>&1 || warn() { echo "  ! $1"; }
type bad  > /dev/null 2>&1 || bad()  { echo "  ✗ $1"; }

link() {
    local src="$1" dst="$2"

    if [ "$CHECK" = 1 ]; then
        if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
            ok "$dst"
        elif [ -L "$dst" ]; then
            warn "$dst → $(readlink "$dst") (expected $src)"
        elif [ -e "$dst" ]; then
            warn "$dst exists but is not a symlink"
        else
            bad "$dst missing (run: dotfiles --sync)"
        fi
        return 0
    fi

    mkdir -p "$(dirname "$dst")"
    if [ -L "$dst" ]; then
        rm "$dst"
    elif [ -e "$dst" ]; then
        echo "  backing up: $dst → $dst.bak"
        mv "$dst" "$dst.bak"
    fi
    ln -s "$src" "$dst"
    echo "  linked: $dst"
}

# apps/<platform>/<name>/config → ~/.config/<name>
# An app with no config/ is either wholly generated (ghostty, borders, fuzzel
# render straight to ~/.config) or has nothing to link.
link_apps() {
    local dir="$1" app
    [ -d "$DOTFILES_DIR/apps/$dir" ] || return 0
    for app in "$DOTFILES_DIR/apps/$dir"/*/; do
        [ -d "$app/config" ] || continue
        link "${app%/}/config" "$HOME/.config/$(basename "$app")"
    done
}

# home/<platform>/<path> → ~/<path>   (the tree mirrors $HOME exactly)
link_home() {
    local dir="$DOTFILES_DIR/home/$1" entry
    [ -d "$dir" ] || return 0
    for entry in "$dir"/* "$dir"/.[!.]*; do
        [ -e "$entry" ] || continue
        link "$entry" "$HOME/$(basename "$entry")"
    done
}

# Alfred reads workflows straight from its prefs bundle, so a symlink keeps the
# workflow in the repo and live-editable. Restart Alfred to pick up new ones.
link_alfred_workflows() {
    local src="$DOTFILES_DIR/apps/mac/alfred/workflows"
    local prefs="$HOME/Library/Application Support/Alfred/Alfred.alfredpreferences/workflows"
    local wf
    [ -d "$src" ] && [ -d "$prefs" ] || return 0
    for wf in "$src"/*/; do
        [ -d "$wf" ] || continue
        link "${wf%/}" "$prefs/user.workflow.$(basename "$wf")"
    done
}

link_all() {
    link_apps general
    link_apps "$PLATFORM"
    link_home general
    link_home "$PLATFORM"
    [ "$PLATFORM" = "mac" ] && link_alfred_workflows
    link "$DOTFILES_DIR/bin/dotfiles" "$HOME/.local/bin/dotfiles"
}

# --check is a library call from `dotfiles --doctor`; it prints and returns.
if [ "$CHECK" = 1 ]; then
    link_all
    return 0 2> /dev/null || exit 0
fi

link_all

# The themed configs are gitignored — they're rendered from templates/ — so a
# fresh clone has none until a theme is applied. Do that now.
THEME="$(cat "$DOTFILES_DIR/.current-theme" 2>/dev/null || true)"
if [ -z "$THEME" ]; then
    THEME="$(basename "$(ls "$DOTFILES_DIR"/themes/*.sh | head -1)" .sh)"
fi
"$DOTFILES_DIR/switch-theme.sh" "$THEME"

echo "Done."
