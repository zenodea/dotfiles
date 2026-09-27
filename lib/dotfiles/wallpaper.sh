# shellcheck shell=bash
# wallpaper listing and switching; sourced by bin/dotfiles

WALLPAPERS_DIR="$DOTFILES/wallpapers/full-size"

wallpaper_names() {
    for f in "$WALLPAPERS_DIR"/*; do
        [ -f "$f" ] && basename "$f"
    done
}

set_wallpaper() {
    local wp="$1"
    # Keep the stable copy in sync (hyprlock/hyprland configs point at it)
    cp "$wp" "$HOME/.config/current-wallpaper" 2>/dev/null || true
    basename "$wp" > "$DOTFILES/.current-wallpaper"
    case "$PLATFORM" in
        linux)
            if pgrep -x awww-daemon > /dev/null 2>&1; then
                awww img "$wp" --transition-type wipe --transition-duration 1 --transition-fps 60
            else
                echo "Error: awww-daemon is not running" >&2
                return 1
            fi
            ;;
        mac)
            osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"$wp\""
            ;;
        *)
            echo "Error: unsupported platform" >&2
            return 1
            ;;
    esac
    echo "wallpaper: $(basename "$wp")"
}

cmd_wallpaper() {
    local arg="$1"

    if [[ -z "$arg" ]]; then
        echo "Usage: dotfiles --wallpaper <name|random>"
        echo ""
        echo "Available wallpapers:"
        wallpaper_names | sed 's/^/  /'
        return 0
    fi

    local wp
    if [[ "$arg" == "random" ]]; then
        local names=()
        while IFS= read -r line; do names+=("$line"); done < <(wallpaper_names)
        if [[ ${#names[@]} -eq 0 ]]; then
            echo "Error: no wallpapers found in $WALLPAPERS_DIR" >&2
            return 1
        fi
        wp="$WALLPAPERS_DIR/${names[RANDOM % ${#names[@]}]}"
    elif [[ -f "$WALLPAPERS_DIR/$arg" ]]; then
        wp="$WALLPAPERS_DIR/$arg"
    elif [[ -f "$arg" ]]; then
        wp="$(cd "$(dirname "$arg")" && pwd)/$(basename "$arg")"
    else
        echo "Error: wallpaper '$arg' not found (in $WALLPAPERS_DIR or as a path)" >&2
        return 1
    fi

    set_wallpaper "$wp"
    echo "Note: the next theme switch resets the wallpaper to the theme's own."
}
