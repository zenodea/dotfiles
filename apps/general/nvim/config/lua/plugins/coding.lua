return {
  -- Treesitter
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'master', -- frozen legacy branch; the 'main' rewrite drops nvim-treesitter.configs
    build = ':TSUpdate',
    main = 'nvim-treesitter.configs',
    opts = {
      ensure_installed = {
        'nix',
        'lua',
        'python',
        'rust',
        'typescript',
        'tsx',
        'javascript',
        'jsdoc',
        'go',
        'c',
        'cpp',
        'bash',
        'json',
        'jsonc',
        'yaml',
        'toml',
        'markdown',
        'diff',
        'html',
        'luadoc',
        'markdown_inline',
        'query',
        'vim',
        'vimdoc',
        -- the stack at work
        'terraform',
        'hcl',
        'prisma',
        'dockerfile',
        'graphql',
        'sql',
        'http', -- kulala's request buffers
        'regex',
        'gitcommit',
        'git_rebase',
        'gitignore',
      },
      auto_install = true,
      highlight = {
        enable = true,
        additional_vim_regex_highlighting = { 'ruby' },
      },
      indent = {
        enable = true,
        disable = { 'ruby' },
      },
    },
  },

  -- Todo comments
  {
    'folke/todo-comments.nvim',
    event = 'VimEnter',
    dependencies = { 'nvim-lua/plenary.nvim' },
    opts = { signs = true },
  },

  -- mini.nvim lives in plugins/mini.lua (lazy.nvim keeps only one config per plugin)

  -- Gitsigns
  {
    'lewis6991/gitsigns.nvim',
    opts = {
      on_attach = function(bufnr)
        local gitsigns = require 'gitsigns'

        local function map(mode, l, r, opts)
          opts = opts or {}
          opts.buffer = bufnr
          vim.keymap.set(mode, l, r, opts)
        end

        -- Navigation
        map('n', ']c', function()
          if vim.wo.diff then
            vim.cmd.normal { ']c', bang = true }
          else
            gitsigns.nav_hunk 'next'
          end
        end, { desc = 'Jump to next git [c]hange' })

        map('n', '[c', function()
          if vim.wo.diff then
            vim.cmd.normal { '[c', bang = true }
          else
            gitsigns.nav_hunk 'prev'
          end
        end, { desc = 'Jump to previous git [c]hange' })

        -- Actions
        -- visual mode
        map('v', '<leader>hs', function()
          gitsigns.stage_hunk { vim.fn.line '.', vim.fn.line 'v' }
        end, { desc = 'git [s]tage hunk' })
        map('v', '<leader>hr', function()
          gitsigns.reset_hunk { vim.fn.line '.', vim.fn.line 'v' }
        end, { desc = 'git [r]eset hunk' })
        -- normal mode
        map('n', '<leader>hs', gitsigns.stage_hunk, { desc = 'git [s]tage hunk' })
        map('n', '<leader>hr', gitsigns.reset_hunk, { desc = 'git [r]eset hunk' })
        map('n', '<leader>hS', gitsigns.stage_buffer, { desc = 'git [S]tage buffer' })
        map('n', '<leader>hu', gitsigns.undo_stage_hunk, { desc = 'git [u]ndo stage hunk' })
        map('n', '<leader>hR', gitsigns.reset_buffer, { desc = 'git [R]eset buffer' })
        map('n', '<leader>hp', gitsigns.preview_hunk, { desc = 'git [p]review hunk' })
        map('n', '<leader>hb', gitsigns.blame_line, { desc = 'git [b]lame line' })
        map('n', '<leader>hd', gitsigns.diffthis, { desc = 'git [d]iff against index' })
        map('n', '<leader>hD', function()
          gitsigns.diffthis '@'
        end, { desc = 'git [D]iff against last commit' })
        -- Toggles
        map('n', '<leader>tb', gitsigns.toggle_current_line_blame, { desc = '[T]oggle git show [b]lame line' })
        map('n', '<leader>tD', gitsigns.preview_hunk_inline, { desc = '[T]oggle git show [D]eleted' })
      end,
    },
  },
  {
    'zenodea/acp.nvim',
    cmd = { 'Acp', 'AcpNew' },
    opts = {},
  },
  {
    'zenodea/nextedit.nvim',
    dependencies = { 'zbirenbaum/copilot.lua' },
    config = function()
      require('nextedit').setup { provider = 'copilot-nes' }
    end,
  },
  {
    'kdheepak/lazygit.nvim',
    lazy = true,
    cmd = {
      'LazyGit',
      'LazyGitConfig',
      'LazyGitCurrentFile',
      'LazyGitFilter',
      'LazyGitFilterCurrentFile',
    },
    -- optional for floating window border decoration
    dependencies = {
      'nvim-lua/plenary.nvim',
    },
    -- setting the keybinding for LazyGit with 'keys' is recommended in
    -- order to load the plugin when the command is run for the first time
    keys = {
      { '<leader>lg', '<cmd>LazyGit<cr>', desc = 'LazyGit' },
    },
    config = function()
      -- Pressing `e` in lazygit calls back into this nvim (see os.edit in
      -- apps/general/lazygit/config/config.yml) rather than nesting a second
      -- nvim inside the terminal buffer. Two things make a plain `--remote`
      -- unreliable, which is why it routes through here instead:
      --
      --   * lazygit.nvim's on_exit closes the float and then forces focus back
      --     to the pre-lazygit window, so an edit issued too early either
      --     lands in the terminal buffer or gets undone. Wait it out.
      --   * acp.nvim marks its chat/input/sidebar/details windows winfixbuf
      --     (so do neo-tree and friends), and `:edit` against one of those is
      --     a hard error. Pick a window that actually accepts a buffer.
      vim.api.nvim_create_user_command('LazygitEdit', function(opts)
        local line = tonumber(opts.fargs[1]) or 0
        -- lazygit shell-quotes the path, and --remote-send delivers that
        -- quoting as literal keystrokes, so peel it back off.
        local file = table.concat(vim.list_slice(opts.fargs, 2), ' '):gsub('^[\'"](.*)[\'"]$', '%1')

        local function usable(w)
          return vim.api.nvim_win_get_config(w).relative == '' and not vim.wo[w].winfixbuf and vim.bo[vim.api.nvim_win_get_buf(w)].buftype == ''
        end

        local tries = 0
        local function open()
          -- Bounded: lazygit.nvim leaves lazygit_opened set if lazygit exits
          -- non-zero, and a file the user asked for beats waiting forever.
          if vim.g.lazygit_opened == 1 and tries < 50 then
            tries = tries + 1
            return vim.defer_fn(open, 20)
          end
          if not usable(vim.api.nvim_get_current_win()) then
            local target = vim.iter(vim.api.nvim_tabpage_list_wins(0)):find(usable)
            -- No code window in this tab (an acp workspace on its own, say):
            -- make one rather than failing or hijacking a panel.
            if target then
              vim.api.nvim_set_current_win(target)
            else
              vim.cmd 'topleft vsplit'
            end
          end
          vim.cmd.edit(vim.fn.fnameescape(file))
          if line > 0 then
            pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
            vim.cmd 'normal! zz'
          end
        end

        open()
      end, { nargs = '+', desc = 'Open a file handed over by lazygit' })
    end,
  },
}
