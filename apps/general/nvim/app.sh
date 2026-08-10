# Neovim — the palette renders as data (lua/dotfiles/theme.lua) and the
# mini plugin spec (lua/plugins/mini.lua) watches that file, so a running
# instance re-themes itself. Nothing to poke from out here, hence no reload().

render() {
    generate theme.lua config/lua/dotfiles/theme.lua
}
