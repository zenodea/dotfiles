# Shared by install.sh, switch-theme and bin/dotfiles.
# Expects $DOTFILES to be set to the repo root before sourcing.

case "$(uname -s)" in
    Darwin) PLATFORM="mac"   ;;
    Linux)  PLATFORM="linux" ;;
    *)      echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

theme_names() {
    local f
    for f in "$DOTFILES/themes"/*.sh; do
        basename "$f" .sh
    done
}

current_theme() {
    cat "$DOTFILES/.current-theme" 2>/dev/null || true
}
