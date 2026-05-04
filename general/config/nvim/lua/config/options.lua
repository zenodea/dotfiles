vim.g.mapleader = ' '
vim.g.maplocalleader = ' '
vim.g.have_nerd_font = true

local opt = vim.opt

-- Line numbers
opt.number = true
opt.relativenumber = true

-- Tabs and indentation
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.smartindent = true

-- Line wrapping
opt.wrap = false
opt.breakindent = true

-- Search settings
opt.ignorecase = true
opt.smartcase = true
opt.inccommand = 'split'

-- Appearance
opt.termguicolors = true
opt.signcolumn = 'yes'
opt.cursorline = true
opt.scrolloff = 10

-- Behavior
opt.mouse = 'a'
opt.showmode = false
opt.undofile = true
opt.updatetime = 250
opt.timeoutlen = 300
opt.confirm = true

-- Splits
opt.splitright = true
opt.splitbelow = true

-- List chars
opt.list = true
opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

opt.clipboard = 'unnamedplus'

