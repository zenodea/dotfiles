# Waybar — only the stylesheet is themed; the module layout is hand-written.

render() {
    generate style.css config/style.css
}

# SIGUSR2 reloads colors but not fonts, so restart from inside the compositor's env.
reload() {
    pgrep -x waybar > /dev/null 2>&1 || return 0
    if have hyprctl && hyprctl monitors &> /dev/null; then
        pkill -x waybar
        hyprctl dispatch exec waybar > /dev/null
        note "restarted"
    else
        killall -SIGUSR2 waybar
        note "reloaded"
    fi
}
