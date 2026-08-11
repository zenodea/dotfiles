-- clangd is enabled in lsp.lua; treesitter c/cpp parsers in coding.lua.
return {
  -- clangd extras: AST view, symbol info, switch source/header
  {
    'p00f/clangd_extensions.nvim',
    ft = { 'c', 'cpp' },
    opts = {},
  },

  -- Configure/build/run/debug CMake projects (uses nvim-dap from debug.lua)
  {
    'Civitasv/cmake-tools.nvim',
    ft = { 'c', 'cpp', 'cmake' },
    dependencies = { 'nvim-lua/plenary.nvim' },
    opts = {},
  },
}
