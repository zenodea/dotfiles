-- Render real images in the terminal via the kitty graphics protocol
return {
  {
    'folke/snacks.nvim',
    priority = 1000,
    lazy = false,
    init = function()
      if vim.env.TERM_PROGRAM == 'rex' and not vim.env.SNACKS_GHOSTTY then
        vim.env.SNACKS_GHOSTTY = '1'
      end
    end,
    opts = {
      image = {
        enabled = true,
      },
    },
  },
}
