# macOS system appearance — flip Light/Dark so Finder, the menu bar and native
# apps match the palette. Nothing to render; this is purely a system poke.

reload() {
    # Setting Light or Dark explicitly is what turns Appearance: Auto off, which
    # under auto mode would disable the very schedule we follow.
    if auto_enabled; then
        skip "auto mode — macOS drives the appearance"
        return 0
    fi

    local dark=false
    [[ "$THEME_APPEARANCE" == "dark" ]] && dark=true

    if osascript -e "tell application \"System Events\" to tell appearance preferences \
        to set dark mode to $dark" > /dev/null 2>&1; then
        note "system appearance: $THEME_APPEARANCE"
    else
        skip "System Events refused (grant Automation access in Privacy & Security)"
    fi
}
