-- Day-to-day git lives in gitsigns + lazygit (coding.lua). This adds the
-- review views: side-by-side branch diffs, file history, conflict resolution.
return {
  {
    'sindrets/diffview.nvim',
    cmd = { 'DiffviewOpen', 'DiffviewFileHistory', 'DiffviewClose' },
    keys = {
      { '<leader>gd', '<cmd>DiffviewOpen<cr>', desc = '[G]it [D]iff view' },
      -- --imply-local: the HEAD side shows the working-tree files, so they
      -- are editable and have LSP, instead of read-only revision buffers
      { '<leader>gm', '<cmd>DiffviewOpen origin/main...HEAD --imply-local<cr>', desc = '[G]it diff vs [M]ain' },
      { '<leader>gh', '<cmd>DiffviewFileHistory %<cr>', desc = '[G]it file [H]istory' },
      { '<leader>gq', '<cmd>DiffviewClose<cr>', desc = '[G]it diff [Q]uit' },
    },
    opts = {},
  },
}
