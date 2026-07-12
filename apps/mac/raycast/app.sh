# Raycast — themes are imported via deeplink; Theme Studio needs one keypress
# to actually apply. The JSON is also written out so it can be imported by hand.
#
# Color order per ray.so: bg, bgSecondary, text, selection, loader,
# red, orange, yellow, green, blue, purple, magenta

render() {
    generate theme.json theme.json
}

reload() {
    [[ -d "/Applications/Raycast.app" || -d "$HOME/Applications/Raycast.app" ]] || return 0
    open "raycast://theme?version=1&name=${THEME_NAME}&appearance=${THEME_APPEARANCE}&colors=%23${BG},%23${SURFACE},%23${FG},%23${ACCENT},%23${ACCENT},%23${RED},%23${ORANGE},%23${YELLOW},%23${GREEN},%23${BLUE},%23${PURPLE},%23${PURPLE}"
    note "import opened — press ⏎ in Raycast to apply"
}
