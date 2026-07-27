-- Vaults are read from obsidian.json rather than hardcoded, the same way
-- apps/general/obsidian/app.sh finds them for theming.
local function vaults()
  local candidates = {
    vim.env.HOME .. '/Library/Application Support/obsidian/obsidian.json',
    vim.env.HOME .. '/.config/obsidian/obsidian.json',
    vim.env.HOME .. '/.var/app/md.obsidian.Obsidian/config/obsidian/obsidian.json',
  }

  for _, path in ipairs(candidates) do
    local f = io.open(path, 'r')
    if f then
      local raw = f:read '*a'
      f:close()
      local ok, decoded = pcall(vim.json.decode, raw)
      if ok and type(decoded) == 'table' and decoded.vaults then
        local found = {}
        for _, vault in pairs(decoded.vaults) do
          if vault.path and vim.fn.isdirectory(vault.path) == 1 then
            found[#found + 1] = { name = vim.fn.fnamemodify(vault.path, ':t'), path = vault.path }
          end
        end
        if #found > 0 then
          return found
        end
      end
    end
  end

  return {}
end

return {
  -- epwalsh archived the original in Dec 2024; this is the maintained fork
  {
    'obsidian-nvim/obsidian.nvim',
    version = '*',
    ft = 'markdown',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-telescope/telescope.nvim',
    },
    keys = {
      { '<leader>nf', '<cmd>Obsidian quick_switch<cr>', desc = '[N]ote: [F]ind' },
      { '<leader>ns', '<cmd>Obsidian search<cr>', desc = '[N]ote: [S]earch contents' },
      { '<leader>nn', '<cmd>Obsidian new<cr>', desc = '[N]ote: [N]ew' },
      { '<leader>nb', '<cmd>Obsidian backlinks<cr>', desc = '[N]ote: [B]acklinks' },
      { '<leader>nl', '<cmd>Obsidian links<cr>', desc = '[N]ote: [L]inks in buffer' },
      { '<leader>nt', '<cmd>Obsidian tags<cr>', desc = '[N]ote: [T]ags' },
      { '<leader>nd', '<cmd>Obsidian today<cr>', desc = '[N]ote: To[d]ay' },
      { '<leader>ny', '<cmd>Obsidian yesterday<cr>', desc = '[N]ote: [Y]esterday' },
      { '<leader>nr', '<cmd>Obsidian rename<cr>', desc = '[N]ote: [R]ename (updates backlinks)' },
      { '<leader>np', '<cmd>Obsidian paste_img<cr>', desc = '[N]ote: [P]aste image' },
      { '<leader>no', '<cmd>Obsidian open<cr>', desc = '[N]ote: [O]pen in Obsidian' },
      { '<leader>nx', '<cmd>Obsidian toggle_checkbox<cr>', desc = '[N]ote: Toggle checkbo[x]' },
      -- visual selection becomes a new note, with a link left behind
      { '<leader>ne', ':Obsidian extract_note<cr>', mode = 'v', desc = '[N]ote: [E]xtract selection' },
      { '<leader>nk', ':Obsidian link<cr>', mode = 'v', desc = '[N]ote: Lin[k] selection' },
    },
    opts = function()
      return {
        workspaces = vaults(),

        -- the keymaps above use the new `:Obsidian <subcommand>` form, so the
        -- old :ObsidianQuickSwitch-style commands are dead weight
        legacy_commands = false,

        -- the vault has essentially no frontmatter (1 note in 38), and the
        -- default writes an id/aliases/tags block into every note on save,
        -- which would rewrite the lot on first touch
        frontmatter = { enabled = false },

        -- default is a random zettel id, which would name new notes
        -- 202607271234.md; the vault uses readable titles throughout
        note_id_func = require('obsidian.builtin').title_id,

        notes_subdir = nil,
        new_notes_location = 'current_dir',

        daily_notes = {
          folder = nil,
          -- Obsidian's date syntax, not strftime
          date_format = 'YYYY-MM-DD',
          -- would be written into frontmatter, which is off
          default_tags = {},
        },

        completion = { min_chars = 2 },

        picker = { name = 'telescope.nvim' },

        -- matches the [[Note|Alias]] style already used throughout the vault
        link = {
          style = 'wiki',
          format = 'shortest',
          auto_update = true,
        },

        attachments = { folder = 'Photos' },

        -- obsidian.nvim's own conceal is off in favour of render-markdown
        -- below; both on means they fight over the same regions
        ui = { enable = false },
      }
    end,
  },

  -- In-buffer rendering: headings, lists, code blocks, callouts. Treesitter
  -- based, so it reuses the markdown parser already installed.
  {
    'MeanderingProgrammer/render-markdown.nvim',
    ft = { 'markdown' },
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
      'nvim-tree/nvim-web-devicons',
    },
    keys = {
      { '<leader>nm', '<cmd>RenderMarkdown toggle<cr>', desc = '[N]ote: Toggle [M]arkdown render' },
    },
    opts = {
      -- not in insert mode, so the raw syntax is there while editing the line
      render_modes = { 'n', 'c', 't' },
      anti_conceal = { enabled = true },
      heading = {
        sign = false,
        icons = { '󰲡 ', '󰲣 ', '󰲥 ', '󰲧 ', '󰲩 ', '󰲫 ' },
      },
      code = {
        sign = false,
        width = 'block',
        right_pad = 2,
      },
      checkbox = {
        unchecked = { icon = '󰄱 ' },
        checked = { icon = '󰱒 ' },
      },
    },
  },
}
