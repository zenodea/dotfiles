-- Core TS support lives elsewhere: typescript-tools + eslint + prettier in
-- lsp.lua, pwa-node debugging in debug.lua, jest/vitest via neotest.
return {
  -- Dependency versions inline in package.json, with update actions
  {
    'vuki656/package-info.nvim',
    dependencies = { 'MunifTanjim/nui.nvim' },
    event = 'BufRead package.json',
    keys = {
      {
        '<leader>Pt',
        function()
          require('package-info').toggle()
        end,
        desc = '[P]ackage: [T]oggle versions',
      },
      {
        '<leader>Pu',
        function()
          require('package-info').update()
        end,
        desc = '[P]ackage: [U]pdate on line',
      },
      {
        '<leader>Pc',
        function()
          require('package-info').change_version()
        end,
        desc = '[P]ackage: [C]hange version',
      },
    },
    opts = {
      hide_up_to_date = true,
    },
  },
}
