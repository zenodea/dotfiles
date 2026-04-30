return {
  {
    '${NVIM_PLUGIN}',
    lazy = false,
    priority = 1000,
    config = function()
      vim.cmd.colorscheme '${NVIM_COLORSCHEME}'
    end,
  },
}
