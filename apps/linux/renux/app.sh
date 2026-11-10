# Renux — a GTK client for Rex. It reads Ghostty theme files, so render writes
# one from the ghostty config (general apps run first, so it is already
# rendered) and points settings.ini at it, with the font and the opacity.
# Renux watches both files and recolors itself, so there is nothing to reload.

RENUX_DIR="$HOME/.config/renux"
RENUX_THEME="$RENUX_DIR/themes/dotfiles"
RENUX_SETTINGS="$RENUX_DIR/settings.ini"
GHOSTTY_THEMES="/usr/share/ghostty/themes"

# Sets KEY=VALUE pairs in the [renux] group of settings.ini and leaves every
# other line alone: the file is Renux's own, and holds what its Settings wrote.
set_keys() {
    local tmp="$RENUX_SETTINGS.tmp"
    [[ -f "$RENUX_SETTINGS" ]] || printf '[renux]\n' > "$RENUX_SETTINGS"
    awk -v pairs="$(printf '%s\034' "$@")" '
        BEGIN {
            # A unit separator between pairs: awk takes no newline in -v.
            n = split(pairs, lines, "\034") - 1
            for (i = 1; i <= n; i++) {
                eq = index(lines[i], "=")
                key = substr(lines[i], 1, eq - 1)
                order[i] = key; value[key] = substr(lines[i], eq + 1)
            }
        }
        function flush(   i) {
            for (i = 1; i <= n; i++) if (!(order[i] in done)) { print order[i] "=" value[order[i]]; done[order[i]] = 1 }
        }
        /^\[/ {
            if (inside) flush()
            inside = ($0 == "[renux]")
            if (inside) seen = 1
            print; next
        }
        inside {
            eq = index($0, "=")
            key = (eq > 0) ? substr($0, 1, eq - 1) : ""
            if (key in value) { if (!(key in done)) { print key "=" value[key]; done[key] = 1 }; next }
        }
        { print }
        END {
            if (inside) flush()
            else if (!seen) { print "[renux]"; flush() }
        }' "$RENUX_SETTINGS" > "$tmp" && mv "$tmp" "$RENUX_SETTINGS"
}

render() {
    have renux || [[ -x "$HOME/.local/bin/renux" ]] || {
        skip "Renux not installed"
        return
    }
    mkdir -p "$(dirname "$RENUX_THEME")"
    # Ghostty's own theme fills the slots the theme file has no colour for
    # (palette 0 and 8, mostly); the rendered config's colours come after and win.
    {
        [[ -f "$GHOSTTY_THEMES/$GHOSTTY_THEME" ]] && cat "$GHOSTTY_THEMES/$GHOSTTY_THEME"
        grep -E '^(background|foreground|cursor-color|palette) *=' "$HOME/.config/ghostty/config"
        # Renux takes its accent (the active pane border, among others) from the cursor.
        printf 'cursor-color = #%s\n' "$ACCENT"
    } > "$RENUX_THEME"
    note "wrote: $(pretty "$RENUX_THEME")"
    # Hyprland blurs what shows through, as it does for ghostty.
    set_keys \
        "theme=file:$RENUX_THEME" \
        "font=$FONT_MONO_FAMILY $FONT_SIZE" \
        "window-opacity=$OPACITY" \
        "terminal-opacity=$OPACITY" \
        "blur=true"
    note "font: $FONT_MONO_FAMILY $FONT_SIZE"
}
