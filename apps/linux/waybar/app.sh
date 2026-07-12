# Waybar — only the stylesheet is themed; the module layout is hand-written.

render() {
    generate style.css config/style.css
}

reload() {
    pgrep -x waybar > /dev/null 2>&1 || return 0
    killall -SIGUSR2 waybar
    note "reloaded"
}
