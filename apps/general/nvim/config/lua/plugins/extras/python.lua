-- pyright (types) + ruff (lint/format/imports) are configured in lsp.lua.
return {
  -- debugpy integration for nvim-dap (debugpy installed via mason)
  {
    'mfussenegger/nvim-dap-python',
    ft = 'python',
    dependencies = { 'mfussenegger/nvim-dap' },
    config = function()
      require('dap-python').setup(vim.fn.stdpath 'data' .. '/mason/packages/debugpy/venv/bin/python')
    end,
  },

  -- Pick the venv the LSP and dap should use; needs fd on PATH
  {
    'linux-cultist/venv-selector.nvim',
    branch = 'regexp',
    dependencies = { 'neovim/nvim-lspconfig', 'nvim-telescope/telescope.nvim' },
    ft = 'python',
    cmd = 'VenvSelect',
    keys = {
      { '<leader>vs', '<cmd>VenvSelect<cr>', ft = 'python', desc = '[V]env [S]elect' },
    },
    opts = {},
  },
}
