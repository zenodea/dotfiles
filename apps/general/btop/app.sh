# btop — the palette renders as a btop theme named "dotfiles" in config/themes,
# which install.sh links into ~/.config/btop. A running btop picks it up when
# restarted (or re-selected in its options menu).

render() {
  generate dotfiles.theme config/themes/dotfiles.theme
}
