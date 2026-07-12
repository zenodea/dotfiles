# Rofi — reads its theme fresh on every launch, so there's nothing to reload.
# current.rasi is the one config.rasi imports; the others are standalone menus.

render() {
    local themes="$DOTFILES/linux/config/rofi/themes"
    generate rofi/theme.rasi        "$themes/current.rasi"
    generate rofi/power-menu.rasi   "$themes/power-menu.rasi"
    generate rofi/theme-picker.rasi "$themes/theme-picker.rasi"
}
