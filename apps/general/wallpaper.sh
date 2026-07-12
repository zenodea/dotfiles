# Wallpaper — the theme names one; it's copied to a stable path so configs
# (hyprlock, hyprland) never have to embed a machine-specific path.
#
# Runs before hypr/ because general/ apps are rendered first, so the stable
# copy is in place by the time hyprland reloads.

SOURCE="$DOTFILES/Wallpapers/${WALLPAPER:-}"

render() {
    if [[ -z "${WALLPAPER:-}" || ! -f "$SOURCE" ]]; then
        skip "theme sets no wallpaper"
        return 0
    fi
    cp "$SOURCE" "$HOME/.config/current-wallpaper"
    note "wrote: $(pretty "$HOME/.config/current-wallpaper") ($WALLPAPER)"
}

reload_linux() {
    [[ -f "$SOURCE" ]] || return 0
    pgrep -x awww-daemon > /dev/null 2>&1 || return 0
    awww img "$SOURCE" --transition-type wipe --transition-duration 1 --transition-fps 60
    note "wallpaper: $WALLPAPER"
}

reload_mac() {
    [[ -f "$SOURCE" ]] || return 0
    # Point at the source file, not the stable copy: macOS caches the desktop
    # picture by path, so re-setting the same path with new bytes is a no-op.
    if osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"$SOURCE\"" > /dev/null 2>&1; then
        note "wallpaper: $WALLPAPER"
    fi
}
