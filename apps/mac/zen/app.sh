# Zen applies the stylesheet live through loader/config.js. Without the loader
# (first install, or a Zen update replaced the app) render colors, then request
# a normal quit and reopen only when necessary. Never force-kill or launch a
# closed browser.
ZEN_READY=0
ZEN_RESTART="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/zen/restart-needed"
ZEN_APP="${ZEN_APP:-/Applications/Zen.app}"

zen_running() { pgrep -x zen >/dev/null 2>&1; }

# Zen updates replace the app bundle and drop the loader; put it back. It runs
# from the next startup, so this render may still restart once.
install_loader() {
    local resources="$ZEN_APP/Contents/Resources" file
    [[ -d "$resources" ]] || return 0
    for file in config.js defaults/pref/config-prefs.js; do
        cmp -s "$APP_DIR/loader/$file" "$resources/$file" && continue
        if ! mkdir -p "$(dirname "$resources/$file")" ||
            ! cp "$APP_DIR/loader/$file" "$resources/$file"; then
            skip "could not install the Zen live loader; theme changes need a restart"
            return 0
        fi
        note "installed Zen live loader: $file"
    done
}

render() {
    if ! have python3; then
        skip "Zen theme needs python3"
        return
    fi
    install_loader
    local result
    result="$(python3 "$APP_DIR/configure.py")" || return
    if [[ "$result" == no-profile ]]; then
        skip "no Zen profile found"
        return
    fi
    ZEN_READY=1
    case "$result" in
        live) note "Zen stylesheet applied live" ;;
        changed) note "Zen stylesheet changed (loaded on next startup)" ;;
        *) note "Zen stylesheet $result" ;;
    esac
}

restarting() {
    [[ "$ZEN_READY" == 1 && -f "$ZEN_RESTART" ]] && zen_running
}

reload() {
    [[ "$ZEN_READY" == 1 && -f "$ZEN_RESTART" ]] || return 0
    if ! zen_running; then
        rm -f -- "$ZEN_RESTART"
        return 0
    fi
    # Do not target a disposable test or a different concurrently open profile.
    local instances
    instances="$(pgrep -x zen | wc -l | tr -d ' ')"
    if [[ "$instances" != 1 ]]; then
        rm -f -- "$ZEN_RESTART"
        skip "multiple Zen instances; restart Zen manually to load the stylesheet"
        return 0
    fi
    # Normal quit respects browser prompts. Never escalate to SIGTERM/SIGKILL.
    if ! osascript <<'APPLESCRIPT'
with timeout of 10 seconds
    tell application id "app.zen-browser.zen" to quit
end timeout
APPLESCRIPT
    then
        rm -f -- "$ZEN_RESTART"
        skip "Zen quit was cancelled or unavailable; stylesheet saved for next startup"
        return 0
    fi
    local i
    for ((i = 0; i < 40; i++)); do
        if ! zen_running; then
            open -a "$ZEN_APP" || return
            rm -f -- "$ZEN_RESTART"
            note "restarted Zen with the new theme"
            return 0
        fi
        sleep 0.25
    done
    rm -f -- "$ZEN_RESTART"
    skip "Zen stayed open; restart manually when convenient"
}
