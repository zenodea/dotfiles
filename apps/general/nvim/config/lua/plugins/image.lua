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
      -- While snacks converts a picture it clears the buffer to show progress, which marks
      -- it modified, so quitting asked to save. An image buffer has nothing to save.
      vim.api.nvim_create_autocmd('FileType', {
        pattern = 'image',
        callback = function(ev)
          vim.bo[ev.buf].buftype = 'nofile'
        end,
      })
    end,
    opts = {
      image = {
        enabled = true,
      },
    },
  },
}
