# JankyBorders — bordersrc is entirely generated, so there's no static config
# to symlink; like ghostty it renders straight to the live path. Running it
# against a live instance updates that instance's options in place.

BORDERSRC="$HOME/.config/borders/bordersrc"

render() {
    generate bordersrc "$BORDERSRC"
}

reload() {
    pgrep -x borders > /dev/null 2>&1 || return 0
    bash "$BORDERSRC"
    note "reloaded"
}
