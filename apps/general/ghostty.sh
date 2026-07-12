# Ghostty — rendered straight to the live config; nothing to symlink.

render() {
    generate ghostty/config "$HOME/.config/ghostty/config"
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
