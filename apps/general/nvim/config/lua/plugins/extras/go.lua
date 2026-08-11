-- gopls (gofumpt, staticcheck) is configured in lsp.lua.
return {
  -- Struct tags, interface impl stubs, iferr — the gopls-adjacent chores
  {
    'olexsmir/gopher.nvim',
    ft = 'go',
    dependencies = { 'nvim-lua/plenary.nvim', 'nvim-treesitter/nvim-treesitter' },
    build = function()
      vim.cmd.GoInstallDeps()
    end,
    opts = {},
  },

  -- Delve integration for nvim-dap; needs dlv on PATH
  -- (go install github.com/go-delve/delve/cmd/dlv@latest)
  {
    'leoluz/nvim-dap-go',
    ft = 'go',
    dependencies = { 'mfussenegger/nvim-dap' },
    opts = {},
  },
}
