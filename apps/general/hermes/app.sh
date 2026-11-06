#!/usr/bin/env bash
# Hermes watches display.skin and the active skin file, so reload only publishes
# the staged palette. It never starts, stops, or restarts Hermes.
HERMES_PALETTE_STAGED=0

hermes_status_message() {
    case "$1" in
        no-config)       printf '%s' "no Hermes config found" ;;
        no-installation) printf '%s' "Hermes installation not found" ;;
        no-parser)       printf '%s' "Hermes YAML parser not found" ;;
        no-stage)        printf '%s' "no staged Hermes palette found" ;;
        *)               printf '%s' "Hermes palette unavailable" ;;
    esac
}

render() {
    if ! have node; then
        skip "Hermes palette needs Node.js"
        return
    fi

    local result reason count
    result="$(node "$APP_DIR/configure.cjs" stage)"
    case "$result" in
        staged:*)
            count="${result#staged:}"
            HERMES_PALETTE_STAGED=1
            note "staged Hermes palette for $count config(s)"
            ;;
        skip:*)
            reason="${result#skip:}"
            skip "$(hermes_status_message "$reason")"
            ;;
        *)
            echo "Hermes theme error: unexpected stage result" >&2
            return 1
            ;;
    esac
}

reload() {
    [[ "$HERMES_PALETTE_STAGED" == 1 ]] || return 0

    local result reason details count
    result="$(node "$APP_DIR/configure.cjs" publish)"
    case "$result" in
        published:*)
            details="${result#published:}"
            count="${details%%:*}"
            note "published Hermes palette for $count config(s); native watcher handles live updates"
            ;;
        skip:*)
            reason="${result#skip:}"
            skip "$(hermes_status_message "$reason")"
            ;;
        *)
            echo "Hermes theme error: unexpected publish result" >&2
            return 1
            ;;
    esac
}
