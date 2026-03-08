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
        [ "$name" = "config" ] && continue
        link "$src" "$HOME/.$name"
    done

    # config/<name> → $HOME/.config/<name>
    if [ -d "$folder/config" ]; then
        for src in "$folder/config"/[^.]*; do
            [ -e "$src" ] || continue
            link "$src" "$CONFIG_DIR/$(basename "$src")"
        done
    fi
}

link_folder "$DOTFILES_DIR/general"
link_folder "$DOTFILES_DIR/$PLATFORM"

echo "Done."
