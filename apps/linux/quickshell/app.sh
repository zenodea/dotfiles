render() {
    local state="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/quickshell-theme.json"
    generate theme.json "$state"
    if [ -w /var/lib/greeter-themes ]; then
        cp "$state" "/var/lib/greeter-themes/$USER.json"
    fi
}
