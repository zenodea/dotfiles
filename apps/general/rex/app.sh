# Rex server config: the key bindings (C-a prefix and the rest) live on the
# server, so every client gets them: Rex.app on the Mac, Renux on Linux.
# Nothing here is themed; the clients are, in mac/rex and linux/renux.

source "$APP_DIR/lib.sh"

render() {
    rex_bin > /dev/null || {
        skip "Rex not installed"
        return
    }
    # ~/.config/rex also holds what the clients write, so link the file, not the dir.
    mkdir -p "$HOME/.config/rex"
    link "$APP_DIR/init.lua" "$HOME/.config/rex/init.lua"
}

reload() {
    local rex
    rex="$(rex_bin)" || return 0
    # Rex doesn't watch init.lua. Don't start a server just to tell it.
    "$rex" --autostart=false --timeout 3s config reload > /dev/null 2>&1 || return 0
    note "reloaded"
}
