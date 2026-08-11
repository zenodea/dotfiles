-- Core Nest support lives elsewhere: attach/debug configs in debug.lua,
-- neotest-jest in debug.lua, kulala .http client in tools.lua.
return {
  -- Project-wide type check without leaving the editor; tsserver only
  -- diagnoses open buffers, which hides breakage across a Nest monorepo.
  {
    'dmmulroy/tsc.nvim',
    cmd = { 'TSC', 'TSCOpen', 'TSCClose' },
    keys = {
      { '<leader>tc', '<cmd>TSC<cr>', desc = '[T]ypeScript [C]heck project' },
    },
    opts = {
      use_trouble_qflist = true,
      flags = {
        watch = false,
      },
    },
  },
}
