# GTK / xdg-desktop-portal color-scheme — what GTK4 and libadwaita apps read to
# decide whether to draw themselves light or dark. Unlike macOS's setting this
# is a hint we own outright, not a schedule to defer to, so auto mode ignores it.

reload() {
    have gsettings || { skip "gsettings not found"; return 0; }

    local scheme="prefer-dark"
    [[ "$THEME_APPEARANCE" == "light" ]] && scheme="prefer-light"

    gsettings set org.gnome.desktop.interface color-scheme "$scheme" 2>/dev/null || {
        skip "could not set color-scheme"
        return 0
    }
    note "color-scheme: $scheme"
}
