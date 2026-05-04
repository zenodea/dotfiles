require 'config.options'
require 'config.keymaps'
require 'config.autocmds'

-- Install `lazy.nvim` plugin manager
local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
  local out = vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath }
  if vim.v.shell_error ~= 0 then
    error('Error cloning lazy.nvim:\n' .. out)
  end
end
vim.opt.rtp:prepend(lazypath)
vim.lsp.config('tsgo', {
  cmd = { 'tsgo', '--lsp', '--stdio' },
  filetypes = {
    'javascript',

    'javascriptreact',

    'javascript.jsx',

    'typescript',

    'typescriptreact',

    'typescript.tsx',
  },

  root_markers = {

    'tsconfig.json',

    'jsconfig.json',

    'package.json',

    '.git',

    'tsconfig.base.json',
  },
})

-- Configure and install plugins
require('lazy').setup('plugins', {
  ui = {
    icons = vim.g.have_nerd_font and {} or {
      cmd = '⌘',
      config = '🛠',
      event = '📅',
      ft = '📂',
      init = '⚙',
      keys = '🗝',
      plugin = '🔌',
      runtime = '💻',
      require = '🌙',
      source = '📄',
      start = '🚀',
      task = '📌',
      lazy = '💤 ',
    },
  },
})
