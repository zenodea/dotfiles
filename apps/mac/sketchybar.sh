# Sketchybar — colors.sh is the palette the bar's items source at startup.

render() {
    generate sketchybar/colors.sh    "$DOTFILES/mac/config/sketchybar/colors.sh"
    generate sketchybar/sketchybarrc "$DOTFILES/mac/config/sketchybar/sketchybarrc"
}

reload() {
    pgrep -x sketchybar > /dev/null 2>&1 || return 0
    sketchybar --reload
    note "reloaded"
}
