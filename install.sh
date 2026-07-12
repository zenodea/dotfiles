#!/usr/bin/env bash
# install.sh — symlink dotfiles to home or ~/.config
#
# Layout:
#   general/            → always linked
#   linux/              → linked on Linux only
#   mac/                → linked on macOS only
#
# Inside each folder:
#   <file>              → $HOME/.<file>
#   config/<name>       → $HOME/.config/<name>

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config"

# Detect OS
case "$(uname -s)" in
    Darwin) PLATFORM="mac"   ;;
    Linux)  PLATFORM="linux" ;;
    *)      echo "Unsupported OS: $(uname -s)"; exit 1 ;;
esac

link() {
    local src="$1"
    local dst="$2"

    mkdir -p "$(dirname "$dst")"

    if [ -L "$dst" ]; then
        echo "  updating: $dst"
        rm "$dst"
    elif [ -e "$dst" ]; then
        echo "  backing up: $dst → $dst.bak"
        mv "$dst" "$dst.bak"
    fi

    ln -s "$src" "$dst"
    echo "  linked: $dst"
}

link_folder() {
    local folder="$1"
    [ -d "$folder" ] || return 0

    echo "==> $folder"

    # Root-level → $HOME/.<name>
    for src in "$folder"/[^.]*; do
        [ -e "$src" ] || continue
        local name="$(basename "$src")"
        case "$name" in
            config|scripts|local|raycast) continue ;;  # raycast: imported via deeplink, nothing to link
            alfred) continue ;;                        # alfred: linked into Alfred's prefs below
            *.sh) continue ;;
        esac
        link "$src" "$HOME/.$name"
    done

    # config/<name> → $HOME/.config/<name>
    if [ -d "$folder/config" ]; then
        for src in "$folder/config"/[^.]*; do
            [ -e "$src" ] || continue
            link "$src" "$CONFIG_DIR/$(basename "$src")"
        done
    fi

    # scripts/ → $HOME/scripts
    if [ -d "$folder/scripts" ]; then
        link "$folder/scripts" "$HOME/scripts"
    fi

    # local/share/<name> → $HOME/.local/share/<name>
    if [ -d "$folder/local/share" ]; then
        for src in "$folder/local/share"/[^.]*; do
            [ -e "$src" ] || continue
            link "$src" "$HOME/.local/share/$(basename "$src")"
        done
    fi
}

# mac/alfred/<name> → Alfred's workflows folder
# Alfred reads workflows straight from these folders, so a symlink keeps the
# workflow in the repo and live-editable. Restart Alfred to pick up new ones.
link_alfred() {
    local folder="$DOTFILES_DIR/mac/alfred"
    local prefs="$HOME/Library/Application Support/Alfred/Alfred.alfredpreferences/workflows"

    [ -d "$folder" ] || return 0
    if [ ! -d "$prefs" ]; then
        echo "==> $folder"
        echo "  skipped: Alfred not installed"
        return 0
    fi

    echo "==> $folder"
    for src in "$folder"/[^.]*; do
        [ -d "$src" ] || continue
        link "$src" "$prefs/user.workflow.$(basename "$src")"
    done
}

link_folder "$DOTFILES_DIR/general"
link_folder "$DOTFILES_DIR/$PLATFORM"
if [ "$PLATFORM" = "mac" ]; then
    link_alfred
fi

# dotfiles CLI → ~/.local/bin
echo "==> $DOTFILES_DIR/bin"
link "$DOTFILES_DIR/bin/dotfiles" "$HOME/.local/bin/dotfiles"

echo "Done."
