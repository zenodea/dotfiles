return {
  {
    'nvim-mini/mini.nvim',
    lazy = false,
    priority = 1000,
    config = function()
      require('mini.base16').setup {
        palette = {
          base00 = '#282a36',
          base01 = '#343746',
          base02 = '#44475a',
          base03 = '#6272a4',
          base04 = '#f8f8f2',
          base05 = '#f8f8f2',
          base06 = '#ffffff',
          base07 = '#ffffff',
          base08 = '#ff5555',
          base09 = '#ffb86c',
          base0A = '#f1fa8c',
          base0B = '#50fa7b',
          base0C = '#bd93f9',
          base0D = '#8be9fd',
          base0E = '#ff79c6',
          base0F = '#ffb86c',
        },
        use_cterm = true,
      }
      vim.cmd 'hi Normal guibg=NONE | hi NormalNC guibg=NONE | hi SignColumn guibg=NONE | hi EndOfBuffer guibg=NONE'
    end,
  },
}
