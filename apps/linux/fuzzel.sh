# Fuzzel — reads its config on each launch; no reload needed.

render() {
    generate fuzzel/fuzzel.ini "$DOTFILES/linux/config/fuzzel/fuzzel.ini"
}
