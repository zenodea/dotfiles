local keymap = vim.keymap.set

-- Clear highlights on search when pressing <Esc> in normal mode
keymap('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Diagnostic keymaps
keymap('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })

-- Exit terminal mode
keymap('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

-- Window navigation (will be overridden by tmux-navigator if installed)
keymap('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
keymap('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
keymap('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
keymap('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

-- Move lines in visual mode
keymap('v', 'J', ":m '>+1<CR>gv=gv")
keymap('v', 'K', ":m '<-2<CR>gv=gv")

-- Join lines and center
keymap('n', 'J', 'mzJ`z')

-- Half page jumping with centering
keymap('n', '<C-d>', '<C-d>zz')
keymap('n', '<C-u>', '<C-u>zz')

-- Auto-indent paragraph
keymap('n', '=ap', "ma=ap'a")

-- Paste without yanking in visual mode
keymap('x', '<leader>p', '"_dP')

-- System clipboard yank
keymap({ 'n', 'v' }, '<leader>y', '"+y')
keymap('n', '<leader>Y', '"+Y')

-- Delete without yanking
keymap({ 'n', 'v' }, '<leader>d', '"_d')

-- Ctrl+C as Escape
keymap('i', '<C-c>', '<Esc>')

-- Disable Q
keymap('n', 'Q', '<nop>')

-- Make file executable
keymap('n', '<leader>cx', '<cmd>!chmod +x %<CR>', { silent = true })

-- Neo-tree keymap for reveal current file
keymap('n', '<leader>E', function()
  vim.cmd 'Neotree filesystem reveal left'
end, { desc = 'Reveal current file in Neo-tree', silent = true })

-- Location list and quickfix navigation
keymap('n', '<leader>k', '<cmd>lnext<CR>zz', { desc = 'Next location list item' })
keymap('n', '<leader>j', '<cmd>lprev<CR>zz', { desc = 'Previous location list item' })

