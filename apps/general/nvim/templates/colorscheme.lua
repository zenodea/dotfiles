return {
  {
    'nvim-mini/mini.nvim',
    lazy = false,
    priority = 1000,
    config = function()
      require('mini.base16').setup {
        palette = {
          base00 = '#${BG}',
          base01 = '#${SURFACE}',
          base02 = '#${BG_ALT}',
          base03 = '#${BORDER}',
          base04 = '#${FG}',
          base05 = '#${FG}',
          base06 = '#${FG_BRIGHT}',
          base07 = '#${FG_BRIGHT}',
          base08 = '#${RED}',
          base09 = '#${ORANGE}',
          base0A = '#${YELLOW}',
          base0B = '#${GREEN}',
          base0C = '#${ACCENT}',
          base0D = '#${BLUE}',
          base0E = '#${PURPLE}',
          base0F = '#${ORANGE}',
        },
        use_cterm = true,
      }
      vim.cmd 'hi Normal guibg=NONE | hi NormalNC guibg=NONE | hi SignColumn guibg=NONE | hi EndOfBuffer guibg=NONE'
    end,
  },
}
