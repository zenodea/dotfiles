# Sketchybar — colors.sh is the palette the bar's items source at startup.

render() {
    generate colors.sh    config/colors.sh
    generate sketchybarrc config/sketchybarrc
}

reload() {
    pgrep -x sketchybar > /dev/null 2>&1 || return 0
    sketchybar --reload
    note "reloaded"
}
