# shellcheck shell=bash
# update and save; sourced by bin/dotfiles

cmd_update() {
    echo "==> Pulling latest dotfiles..."
    git -C "$DOTFILES" pull --ff-only
    git -C "$DOTFILES" submodule update --init wallpapers

    local theme
    theme="$(current_theme)"
    if [[ -n "$theme" ]]; then
        echo ""
        "$DOTFILES/bin/switch-theme" "$theme"
    else
        echo "No .current-theme found; skipping theme re-apply."
    fi
}

cmd_save() {
    local msg="${1:-chore: update dotfiles}"
    git -C "$DOTFILES" add -A
    if git -C "$DOTFILES" diff --cached --quiet; then
        echo "Nothing to commit."
    else
        git -C "$DOTFILES" commit -m "$msg"
    fi
    if git -C "$DOTFILES" remote | grep -q .; then
        git -C "$DOTFILES" push
    else
        echo "No git remote configured; skipped push."
    fi
}
