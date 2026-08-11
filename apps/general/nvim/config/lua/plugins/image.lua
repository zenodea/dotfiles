-- Render real images in the terminal via the kitty graphics protocol
return {
  {
    'folke/snacks.nvim',
    priority = 1000,
    lazy = false,
    opts = {
      image = {
        enabled = true,
      },
    },
  },
}
