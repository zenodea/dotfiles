# Ghostty — rendered straight to the live config; nothing to symlink.
# Text and ANSI colours come from the theme file, pushed to 4.5:1; GHOSTTY_THEME fills the rest.

# Nudges $1 toward black (light theme) or white (dark) until it reaches ratio $2 against BG.
readable() {
    awk -v h="$1" -v bg="$BG" -v want="$2" -v light="$([[ "$THEME_APPEARANCE" == light ]] && echo 1 || echo 0)" '
        function lin(c,   x) { x = c / 255; return (x <= 0.04045) ? x / 12.92 : ((x + 0.055) / 1.055) ^ 2.4 }
        function lum(r, g, b) { return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b) }
        function ratio(a, b) { return (a > b) ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05) }
        function hex(s, i) { return index("0123456789abcdef", tolower(substr(s, i, 1))) * 16 + index("0123456789abcdef", tolower(substr(s, i + 1, 1))) - 17 }
        BEGIN {
            r = hex(h, 1); g = hex(h, 3); b = hex(h, 5)
            lbg = lum(hex(bg, 1), hex(bg, 3), hex(bg, 5))
            target = light ? 0 : 255
            for (i = 0; i <= 100; i++) {
                t = i / 100
                nr = r + (target - r) * t; ng = g + (target - g) * t; nb = b + (target - b) * t
                if (ratio(lum(nr, ng, nb), lbg) >= want) break
            }
            printf "%02x%02x%02x", int(nr + 0.5), int(ng + 0.5), int(nb + 0.5)
        }'
}

# Fades $1 toward BG, stopping just above ratio $2 — a quiet grey that still reads.
faded() {
    awk -v fg="$1" -v bg="$BG" -v want="$2" '
        function lin(c,   x) { x = c / 255; return (x <= 0.04045) ? x / 12.92 : ((x + 0.055) / 1.055) ^ 2.4 }
        function lum(r, g, b) { return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b) }
        function ratio(a, b) { return (a > b) ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05) }
        function hex(s, i) { return index("0123456789abcdef", tolower(substr(s, i, 1))) * 16 + index("0123456789abcdef", tolower(substr(s, i + 1, 1))) - 17 }
        BEGIN {
            r1 = hex(fg, 1); g1 = hex(fg, 3); b1 = hex(fg, 5)
            r0 = hex(bg, 1); g0 = hex(bg, 3); b0 = hex(bg, 5)
            lbg = lum(r0, g0, b0)
            t = 1
            for (i = 99; i >= 0; i--) {
                u = i / 100
                if (ratio(lum(r1 * u + r0 * (1 - u), g1 * u + g0 * (1 - u), b1 * u + b0 * (1 - u)), lbg) < want) break
                t = u
            }
            printf "%02x%02x%02x", int(r1 * t + r0 * (1 - t) + 0.5), int(g1 * t + g0 * (1 - t) + 0.5), int(b1 * t + b0 * (1 - t) + 0.5)
        }'
}

# Theme files carry no cyan; halfway between green and blue lands on one.
cyan() {
    printf '%02x%02x%02x' \
        $(((16#${GREEN:0:2} + 16#${BLUE:0:2}) / 2)) \
        $(((16#${GREEN:2:2} + 16#${BLUE:2:2}) / 2)) \
        $(((16#${GREEN:4:2} + 16#${BLUE:4:2}) / 2))
}

palette() {
    local fg red green yellow blue purple teal
    # Light text gets headroom: the wallpaper behind the translucent window costs up to 1:1.
    fg="$(readable "$FG" "$([[ "$THEME_APPEARANCE" == light ]] && echo 5.5 || echo 4.5)")"
    red="$(readable "$RED" 4.5)"
    green="$(readable "$GREEN" 4.5)"
    yellow="$(readable "$YELLOW" 4.5)"
    blue="$(readable "$BLUE" 4.5)"
    purple="$(readable "$PURPLE" 4.5)"
    teal="$(readable "$(cyan)" 4.5)"

    printf 'foreground = #%s\n' "$fg"
    printf 'cursor-color = #%s\n' "$fg"
    printf 'cursor-text = #%s\n' "$BG"
    printf 'selection-background = #%s\n' "$BG_ALT"
    printf 'selection-foreground = #%s\n' "$fg"
    local i c
    i=1
    for c in "$red" "$green" "$yellow" "$blue" "$purple" "$teal"; do
        printf 'palette = %d=#%s\npalette = %d=#%s\n' "$i" "$c" "$((i + 8))" "$c"
        i=$((i + 1))
    done
    # On light palettes "white" is printed as text, so it has to read.
    if [[ "$THEME_APPEARANCE" == light ]]; then
        printf 'palette = 7=#%s\n' "$(faded "$fg" 4.5)"
        printf 'palette = 8=#%s\n' "$(faded "$fg" 3)"
        printf 'palette = 15=#%s\n' "$fg"
    fi
}

render() {
    generate config "$HOME/.config/ghostty/config"
    palette >> "$HOME/.config/ghostty/config"
    local feature
    for feature in ${FONT_FEATURES:-}; do
        printf 'font-feature = %s\n' "$feature" >> "$HOME/.config/ghostty/config"
    done
    copy shaders/cursor_warp.glsl "$HOME/.config/ghostty/shaders/cursor_warp.glsl"
}

reload_linux() {
    pgrep -x ghostty > /dev/null 2>&1 || return 0
    pkill -SIGUSR2 ghostty
    note "reloaded"
}

reload_mac() {
    # Ghostty has handled SIGUSR2 on macOS since 1.2, but pgrep can't find it:
    # the app's kernel proc name is the truncated bundle path ("/Applications/Gh"),
    # not "ghostty". Match on ucomm via ps instead.
    local pids
    pids="$(ps ax -o pid=,ucomm= | awk '$2 == "ghostty" {print $1}')"
    [[ -n "$pids" ]] || return 0
    # shellcheck disable=SC2086
    kill -USR2 $pids 2>/dev/null || true
    note "reloaded"
}
