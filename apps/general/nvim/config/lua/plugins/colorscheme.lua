-- The palette lives in lua/dotfiles/theme.lua, which switch-theme regenerates
-- on every switch. Watching that file is what lets a running nvim follow along:
-- nvim exposes no reload hook to poke from outside, and the alternative —
-- hunting each instance's socket under $TMPDIR and --remote-send'ing into it —
-- is platform-specific and only reaches instances running at the time.

local MODULE = 'dotfiles.theme'

local function apply()
  package.loaded[MODULE] = nil
  local ok, theme = pcall(require, MODULE)
  if not ok then
    return
  end

  require('mini.base16').setup { palette = theme.palette, use_cterm = true }
  vim.cmd 'hi Normal guibg=NONE | hi NormalNC guibg=NONE | hi SignColumn guibg=NONE | hi EndOfBuffer guibg=NONE'

  -- Plugins that paint their own highlights hang off ColorScheme, and setting a
  -- palette in place doesn't fire it.
  vim.api.nvim_exec_autocmds('ColorScheme', { pattern = vim.g.colors_name or '' })
end

-- Re-arm after every event instead of leaving one watch running for the
-- session: the write is an in-place truncate today, but a rename-based one
-- would leave the handle on an unlinked inode and the watch silently dead.
local function watch()
  local path = vim.uv.fs_realpath(vim.fn.stdpath 'config' .. '/lua/dotfiles/theme.lua')
  if not path then
    return
  end

  local handle = vim.uv.new_fs_event()
  if not handle then
    return
  end

  handle:start(path, {}, function()
    handle:stop()
    -- The callback runs on the loop thread, and fires more than once per write.
    -- Deferring gets us back on the main thread and coalesces the burst.
    vim.defer_fn(function()
      apply()
      watch()
    end, 50)
  end)
end

return {
  {
    'nvim-mini/mini.nvim',
    lazy = false,
    priority = 1000,
    config = function()
      apply()
      watch()
    end,
  },
}
