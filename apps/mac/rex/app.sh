# Rex.app — a Ghostty-based terminal that imports Ghostty theme files but keeps
# its own theme store, so render writes a theme file and reload imports it.
# Mac apps run after general ones, so the ghostty config is already rendered.

REX_THEME="$HOME/.config/rex/themes/dotfiles.ghostty"
GHOSTTY_THEMES="/Applications/Ghostty.app/Contents/Resources/ghostty/themes"

source "$APPS_DIR/general/rex/lib.sh"

render() {
    rex_bin > /dev/null || {
        skip "Rex not installed"
        return
    }
    # init.lua, with the key bindings, is general/rex's to link.
    mkdir -p "$(dirname "$REX_THEME")"
    # Ghostty's own theme fills the slots the theme file has no colour for
    # (palette 0 and 8, mostly); the rendered config's colours come after and win.
    # Rex keeps the first cursor-color it reads, not the last like Ghostty, so
    # drop the earlier ones and write only the accent.
    {
        [[ -f "$GHOSTTY_THEMES/$GHOSTTY_THEME" ]] && grep -v -E '^cursor-color *=' "$GHOSTTY_THEMES/$GHOSTTY_THEME"
        grep -E '^(background|foreground|cursor-text|selection-background|selection-foreground|palette) *=' \
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
    local rex out apps ids id
    rex="$(rex_bin)" || return 0
    # Don't start the server just to theme it: no app connected, nothing to reload.
    apps="$("$rex" --autostart=false --timeout 3s client ls --json 2> /dev/null)" || return 0
    # Other apps can share the server (Compy on a phone, say), and an untargeted
    # import is then refused as ambiguous, so send it to each Rex.app by its ID.
    # The theme file is on this Mac, so only this Mac's apps (local socket).
    local rex_apps='.clients[] | select(.info.kind == "app" and .info.name == "Rex" and .principal.transport == "unix")'
    jq -e "$rex_apps" <<< "$apps" > /dev/null || return 0
    # The server keeps an app that dropped off listed (connection_state "lost"),
    # and an import sent to it fails, so say so instead of skipping quietly.
    ids="$(jq -r "$rex_apps | select(.connection_state == \"connected\") | .client_id" <<< "$apps")"
    if [[ -z "$ids" ]]; then
        skip "Rex.app lost its server connection; restart Rex, then run: dotfiles --sync"
        return 0
    fi
    while IFS= read -r id; do
        if ! out="$("$rex" --autostart=false --timeout 5s -C "$id" do client.theme.import path="$REX_THEME" 2>&1)"; then
            case "$out" in
                *"not accepting actions"*) skip "turn on Remote Control in Rex Settings → Rex Server" ;;
                *) skip "import failed: $out" ;;
            esac
            return 0
        fi
    done <<< "$ids"
    note "reloaded"
}
