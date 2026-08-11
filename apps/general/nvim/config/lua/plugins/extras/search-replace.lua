-- Project-wide search & replace with live ripgrep preview; telescope only
-- finds, it doesn't replace.
return {
  {
    'MagicDuck/grug-far.nvim',
    cmd = 'GrugFar',
    keys = {
      {
        '<leader>sR',
        function()
          require('grug-far').open()
        end,
        desc = '[S]earch & [R]eplace project-wide',
      },
    },
    opts = {},
  },
}
