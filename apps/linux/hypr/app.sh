# Hyprland — the compositor config and the lockscreen share a palette. Both
# point at ~/.config/current-wallpaper, which the wallpaper app writes first.

render() {
    generate hyprland.conf config/hyprland.conf
    generate hyprlock.conf config/hyprlock.conf
}

reload() {
    have hyprctl || return 0
    hyprctl monitors &> /dev/null || return 0
    hyprctl reload
    note "reloaded"
}
