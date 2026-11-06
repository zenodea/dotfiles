# Raycast — custom themes are a Pro feature and the raycast://theme deeplink
# always asks to install, so switching never opens it. Raycast set to follow
# the system appearance already tracks light/dark (apps/mac/appearance flips
# it). The palette is still written to theme.json for a manual import.
#
# Color order per ray.so: bg, bgSecondary, text, selection, loader,
# red, orange, yellow, green, blue, purple, magenta

render() {
    generate theme.json theme.json
}
