# Firefox — userChrome/userContent live in the default profile's chrome/ dir,
# and the prefs that enable them live in user.js. Firefox reads all three only
# at startup, so it's restarted, but only if something actually changed.

PROFILE=""

find_profile() {
    local base=""
    if [[ -f "$HOME/.mozilla/firefox/profiles.ini" ]]; then
        base="$HOME/.mozilla/firefox"
    elif [[ -f "$HOME/Library/Application Support/Firefox/profiles.ini" ]]; then
        base="$HOME/Library/Application Support/Firefox"
    else
        return 1
    fi

    local rel
    rel=$(awk '/^\[Install/{found=1; next} found && /^Default=/{sub(/^Default=/, ""); print; exit}' \
        "$base/profiles.ini" 2>/dev/null)
    [[ -n "$rel" && -d "$base/$rel" ]] || return 1

    PROFILE="$base/$rel"
}

state() {
    cat "$PROFILE/chrome/userChrome.css" \
        "$PROFILE/chrome/userContent.css" \
        "$PROFILE/user.js" 2>/dev/null | cksum
}

set_pref() {
    local key="$1" val="$2" userjs="$PROFILE/user.js"
    if grep -q "\"$key\"" "$userjs" 2>/dev/null; then
        # -i.bak works with both GNU and BSD sed; bare -i doesn't
        sed -i.bak "s|user_pref(\"$key\",.*);|user_pref(\"$key\", $val);|" "$userjs"
        rm -f "$userjs.bak"
    else
        echo "user_pref(\"$key\", $val);" >> "$userjs"
    fi
}

CHANGED=0

render() {
    if ! find_profile; then
        skip "no Firefox profile found"
        return 0
    fi

    local before
    before="$(state)"

    generate userChrome.css  "$PROFILE/chrome/userChrome.css"
    generate userContent.css "$PROFILE/chrome/userContent.css"

    set_pref "toolkit.legacyUserProfileCustomizations.stylesheets" "true"
    set_pref "ui.systemUsesDarkTheme"                              "1"
    set_pref "layout.css.prefers-color-scheme.content-override"    "0"
    set_pref "browser.theme.content-theme"                         "0"
    set_pref "browser.theme.toolbar-theme"                         "0"
    set_pref "browser.startup.page"                                "3"
    note "wrote: user.js (userChrome + dark mode + session restore)"

    [[ "$(state)" != "$before" ]] && CHANGED=1
    return 0
}

restarting() {
    [[ -n "$PROFILE" && "$CHANGED" == 1 ]] && pgrep -x firefox > /dev/null 2>&1
}

reload_linux() {
    restarting || return 0
    pkill -x firefox
    sleep 1
    firefox &> /dev/null &
    note "restarted"
}

reload_mac() {
    restarting || return 0
    pkill -x firefox
    sleep 1
    open -a Firefox
    note "restarted"
}
