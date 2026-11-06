# Rex — a Ghostty-based terminal that imports Ghostty theme files but keeps
# its own theme store, so render writes a theme file and reload imports it.
# Mac apps run after general ones, so the ghostty config is already rendered.

REX_THEME="$HOME/.config/rex/themes/dotfiles.ghostty"
GHOSTTY_THEMES="/Applications/Ghostty.app/Contents/Resources/ghostty/themes"

rex_bin() {
    if have rex; then
        command -v rex
        return
    fi
    local app
    for app in "/Applications/Rex.app" "/Applications/Rex Beta.app"; do
        [[ -x "$app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex" ]] || continue
        printf '%s' "$app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex"
        return
    done
    return 1
}

render() {
    rex_bin > /dev/null || {
        skip "Rex not installed"
        return
    }
    # ~/.config/rex also holds the rendered theme, so link the file, not the dir.
    mkdir -p "$(dirname "$REX_THEME")"
    link "$APP_DIR/init.lua" "$HOME/.config/rex/init.lua"
    # Ghostty's own theme fills the slots the theme file has no colour for
    # (palette 0 and 8, mostly); the rendered config's colours come after and win.
    {
        [[ -f "$GHOSTTY_THEMES/$GHOSTTY_THEME" ]] && cat "$GHOSTTY_THEMES/$GHOSTTY_THEME"
        grep -E '^(background|foreground|cursor-color|cursor-text|selection-background|selection-foreground|palette) *=' \
            "$HOME/.config/ghostty/config"
        # Rex takes its accent (the active pane border, among others) from the cursor.
        printf 'cursor-color = #%s\n' "$ACCENT"
    } > "$REX_THEME"
    note "wrote: $(pretty "$REX_THEME")"
    # The font lives in Rex's own prefs, copied from Ghostty once on first launch
    # and never again, so set it here; the app picks the change up on its own.
    defaults write com.superlogical.rex Workspace.terminalFontName -string "$FONT_MONO_FAMILY"
    defaults write com.superlogical.rex Workspace.terminalFontPointSize -float "$FONT_SIZE"
    note "font: $FONT_MONO_FAMILY $FONT_SIZE"
}

reload() {
    local rex out
    rex="$(rex_bin)" || return 0
    # Don't start the server just to theme it: no app connected, nothing to reload.
    "$rex" --autostart=false --timeout 3s client ls --json 2> /dev/null |
        grep -q '"kind": "app"' || return 0
    if ! out="$("$rex" --autostart=false --timeout 5s do client.theme.import path="$REX_THEME" 2>&1)"; then
        case "$out" in
            *"not accepting actions"*) skip "turn on Remote Control in Rex Settings → Rex Server" ;;
            *) skip "import failed: $out" ;;
        esac
        return 0
    fi
    note "reloaded"
}
