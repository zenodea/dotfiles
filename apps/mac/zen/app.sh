# Data-only Zen adapter. Never launches/restarts or installs into a browser.
render() {
    if ! have python3; then
        skip "Zen palette needs python3"
        return
    fi
    python3 "$APP_DIR/palette.py" stage || return
    note "staged Zen palette (active palette unchanged until reload)"
}

reload() {
    if ! have python3; then
        skip "Zen palette needs python3"
        return
    fi
    python3 "$APP_DIR/palette.py" publish || return
    note "published Zen palette (only an explicitly running prototype follows it)"
}
