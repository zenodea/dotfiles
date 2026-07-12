# JankyBorders — bordersrc is just a `borders ...` invocation, and running it
# against a live instance updates that instance's options in place.

BORDERSRC="$DOTFILES/mac/config/borders/bordersrc"

render() {
    generate borders/bordersrc "$BORDERSRC"
}

reload() {
    pgrep -x borders > /dev/null 2>&1 || return 0
    bash "$BORDERSRC"
    note "reloaded"
}
