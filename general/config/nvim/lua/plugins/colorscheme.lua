return {
  {
    'nvim-mini/mini.nvim',
    lazy = false,
    priority = 1000,
    config = function()
      require('mini.base16').setup {
        palette = {
          base00 = '#1e1e2e',
          base01 = '#313244',
          base02 = '#45475a',
          base03 = '#585b70',
          base04 = '#cdd6f4',
          base05 = '#cdd6f4',
          base06 = '#bac2de',
          base07 = '#bac2de',
          base08 = '#f38ba8',
          base09 = '#fab387',
          base0A = '#f9e2af',
          base0B = '#a6e3a1',
          base0C = '#89dceb',
          base0D = '#89b4fa',
          base0E = '#cba6f7',
          base0F = '#fab387',
        },
        use_cterm = true,
      }
      vim.cmd 'hi Normal guibg=NONE | hi NormalNC guibg=NONE | hi SignColumn guibg=NONE | hi EndOfBuffer guibg=NONE'
    end,
  },
}
