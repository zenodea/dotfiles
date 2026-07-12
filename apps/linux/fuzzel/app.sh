# Fuzzel — wholly generated, so like ghostty it renders straight to the live
# path rather than through a symlinked config/. Reads its config on each
# launch; no reload needed.

render() {
    generate fuzzel.ini "$HOME/.config/fuzzel/fuzzel.ini"
}
