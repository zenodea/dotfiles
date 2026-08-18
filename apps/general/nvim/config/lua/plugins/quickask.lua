return {
  -- Quick ask agent a question.
  {
    'zenodea/quickask.nvim',
    name = 'quickask.nvim',
    event = 'VeryLazy',
    opts = {
      keymaps = {
        ask = '<leader>aa', -- ask (or follow-up while the window is open); visual: ask about selection
        ask_cursor = '<leader>ak', -- "what is <word under cursor>?" — zero typing
        actions = '<leader>aA', -- canned-question menu over selection / current line
      },
      agent = {
        env = { ANTHROPIC_MODEL = 'haiku' },
      },
    },
  },
}
