return {
  -- HTTP client. Hitting a Nest controller from a .http buffer that lives in
  -- the repo, instead of from Postman state nobody else can see.
  {
    'mistweaverco/kulala.nvim',
    ft = { 'http', 'rest' },
    keys = {
      { '<leader>Rs', function() require('kulala').run() end, desc = '[R]est: [S]end request' },
      { '<leader>Ra', function() require('kulala').run_all() end, desc = '[R]est: Send [A]ll' },
      { '<leader>Rr', function() require('kulala').replay() end, desc = '[R]est: [R]eplay last' },
      { '<leader>Rn', function() require('kulala').jump_next() end, desc = '[R]est: [N]ext request' },
      { '<leader>Rp', function() require('kulala').jump_prev() end, desc = '[R]est: [P]revious request' },
      { '<leader>Rt', function() require('kulala').toggle_view() end, desc = '[R]est: [T]oggle body/headers' },
      { '<leader>Rc', function() require('kulala').copy() end, desc = '[R]est: [C]opy as curl' },
      { '<leader>Re', function() require('kulala').set_selected_env() end, desc = '[R]est: Select [E]nvironment' },
    },
    opts = {
      default_view = 'body',
      default_env = 'dev',
      formatters = {
        json = { 'jq', '.' },
      },
    },
  },

  -- Query the database Prisma sits on top of, without leaving the editor.
  -- Useful for checking what a migration actually did.
  {
    'kristijanhusak/vim-dadbod-ui',
    dependencies = {
      { 'tpope/vim-dadbod', lazy = true },
      { 'kristijanhusak/vim-dadbod-completion', ft = { 'sql', 'mysql', 'plsql' }, lazy = true },
    },
    cmd = { 'DBUI', 'DBUIToggle', 'DBUIAddConnection', 'DBUIFindBuffer' },
    keys = {
      { '<leader>Qq', '<cmd>DBUIToggle<cr>', desc = '[Q]uery: Toggle DBUI' },
      { '<leader>Qa', '<cmd>DBUIAddConnection<cr>', desc = '[Q]uery: [A]dd connection' },
      { '<leader>Qf', '<cmd>DBUIFindBuffer<cr>', desc = '[Q]uery: [F]ind buffer' },
    },
    init = function()
      vim.g.db_ui_use_nerd_fonts = 1
      vim.g.db_ui_show_database_icon = 1
      -- keep saved queries in the repo they belong to rather than one global pile
      vim.g.db_ui_save_location = vim.fn.stdpath 'data' .. '/db_ui'
      vim.g.db_ui_tmp_query_location = vim.fn.stdpath 'data' .. '/db_ui/tmp'
      vim.g.db_ui_execute_on_save = 0
    end,
  },
}
