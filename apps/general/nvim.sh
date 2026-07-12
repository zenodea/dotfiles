# Neovim — the colorscheme plugin spec is regenerated per theme. Nvim has no
# reload hook here; a running instance keeps its old palette until restarted.

render() {
    generate nvim/colorscheme.lua "$DOTFILES/general/config/nvim/lua/plugins/colorscheme.lua"
    note "restart nvim to pick up the new palette"
}
