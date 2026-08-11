-- In-editor rendering (render-markdown.nvim) lives in obsidian.lua.
return {
  -- Live browser preview, useful for READMEs going to GitHub
  {
    'iamcco/markdown-preview.nvim',
    cmd = { 'MarkdownPreviewToggle', 'MarkdownPreview', 'MarkdownPreviewStop' },
    ft = { 'markdown' },
    build = function()
      vim.fn['mkdp#util#install']()
    end,
    keys = {
      { '<leader>mp', '<cmd>MarkdownPreviewToggle<cr>', ft = 'markdown', desc = '[M]arkdown [P]review' },
    },
  },
}
