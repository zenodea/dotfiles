-- html, cssls, tailwindcss and emmet_language_server live in lsp.lua;
-- prettier formats both via conform.
return {
  -- Render color values (#hex, rgb(), tailwind classes) inline
  {
    'catgoose/nvim-colorizer.lua',
    ft = { 'css', 'scss', 'html', 'javascript', 'javascriptreact', 'typescript', 'typescriptreact', 'lua' },
    opts = {
      user_default_options = {
        css = true,
        tailwind = true,
      },
    },
  },
}
