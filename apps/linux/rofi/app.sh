# Rofi — reads its theme fresh on every launch, so there's nothing to reload.
# current.rasi is the one config.rasi imports; the others are standalone menus.

render() {
    generate theme.rasi        config/themes/current.rasi
    generate power-menu.rasi   config/themes/power-menu.rasi
    generate theme-picker.rasi config/themes/theme-picker.rasi
}
