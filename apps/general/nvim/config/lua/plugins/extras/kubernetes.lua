-- Manifest/schema/helm support lives in lsp.lua (yamlls kubernetes schemas,
-- helm_ls, vim-helm). This adds a cluster UI on top of kubectl.
return {
  {
    'ramilito/kubectl.nvim',
    keys = {
      {
        '<leader>K',
        function()
          require('kubectl').toggle()
        end,
        desc = '[K]ubectl UI',
      },
    },
    opts = {},
  },
}
