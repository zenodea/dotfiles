# Hyprland — the compositor config and the lockscreen share a palette. Both
# point at ~/.config/current-wallpaper, which the wallpaper app writes first.

render() {
    generate hypr/hyprland.conf "$DOTFILES/linux/config/hypr/hyprland.conf"
    generate hypr/hyprlock.conf "$DOTFILES/linux/config/hypr/hyprlock.conf"
}

reload() {
    have hyprctl || return 0
    hyprctl monitors &> /dev/null || return 0
    hyprctl reload
    note "reloaded"
}
