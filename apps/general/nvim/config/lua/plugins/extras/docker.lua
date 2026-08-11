-- dockerls + docker_compose_language_service live in lsp.lua. This is the
-- lazygit-equivalent TUI; needs the lazydocker binary (brew install lazydocker).
return {
  {
    'crnvl96/lazydocker.nvim',
    keys = {
      {
        '<leader>ld',
        function()
          require('lazydocker').toggle()
        end,
        desc = '[L]azy[D]ocker',
      },
    },
    opts = {},
  },
}
