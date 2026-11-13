return {
  -- Todo comments
  {
    'folke/todo-comments.nvim',
    event = 'VimEnter',
    dependencies = { 'nvim-lua/plenary.nvim' },
    opts = { signs = true },
  },

  -- mini.nvim lives in plugins/mini.lua (lazy.nvim keeps only one config per plugin)

  {
    'zenodea/acp.nvim',
    cmd = { 'Acp', 'AcpNew' },
    opts = {},
  },
  {
    'zenodea/nextedit.nvim',
    dependencies = { 'zbirenbaum/copilot.lua' },
    config = function()
      require('nextedit').setup { provider = 'copilot-nes' }
    end,
  },
}
