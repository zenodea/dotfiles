# Alfred — the theme goes into Alfred's preferences bundle, whose location is
# recorded in prefs.json (it may live in a synced folder, so it can't be
# hardcoded). Selecting it is a separate, machine-local plist.

PREFS=""
LOCALHASH=""

find_prefs() {
    local json="$HOME/Library/Application Support/Alfred/prefs.json"
    [[ -f "$json" ]] || return 1

    IFS=$'\t' read -r PREFS LOCALHASH <<< "$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get('current', ''), d.get('localhash', ''), sep='\t')" "$json" 2>/dev/null)"

    [[ -n "$PREFS" && -d "$PREFS" ]]
}

render() {
    if ! find_prefs; then
        skip "Alfred not installed"
        return 0
    fi
    # Custom themes live at the bundle root (like workflows/), NOT under
    # preferences/appearance/ — Alfred silently ignores themes placed there.
    generate theme.json "$PREFS/themes/theme.custom.dotfiles.$THEME_NAME/theme.json"
}

# AppleScript's "set theme" silently no-ops when Alfred is following the macOS
# appearance, so the theme is selected by writing the appearance prefs directly.
reload() {
    [[ -n "$PREFS" && -n "$LOCALHASH" ]] || return 0

    local plist="$PREFS/preferences/local/$LOCALHASH/appearance/prefs.plist"
    local uid="theme.custom.dotfiles.$THEME_NAME"
    mkdir -p "$(dirname "$plist")"
    [[ -f "$plist" ]] || plutil -create xml1 "$plist"
    plutil -replace theme         -string "$uid" "$plist"
    plutil -replace darkthemeuid  -string "$uid" "$plist"
    plutil -replace lightthemeuid -string "$uid" "$plist"

    # Hide the Alfred hat logo on the search window (a synced appearance option)
    local options="$PREFS/preferences/appearance/options/prefs.plist"
    mkdir -p "$(dirname "$options")"
    [[ -f "$options" ]] || plutil -create xml1 "$options"
    plutil -replace hidehat -bool true "$options"

    # Alfred only reads these at launch; it's a background app, so the restart
    # is invisible.
    if pgrep -x Alfred > /dev/null 2>&1; then
        osascript -e 'tell application id "com.runningwithcrayons.Alfred" to quit' > /dev/null 2>&1
        sleep 1
        open -a "Alfred 5" 2>/dev/null || open -a Alfred
        note "reloaded"
    fi
}
