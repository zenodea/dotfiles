return {
  -- Telescope fuzzy finder
  {
    'nvim-telescope/telescope.nvim',
    event = 'VimEnter',
    dependencies = {
      'nvim-lua/plenary.nvim',
      {
        'nvim-telescope/telescope-fzf-native.nvim',
        build = 'make',
        cond = function()
          return vim.fn.executable 'make' == 1
        end,
      },
      { 'nvim-telescope/telescope-ui-select.nvim' },
      { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
    },
    config = function()
      require('telescope').setup {
        defaults = {
          file_ignore_patterns = { 'node_modules', '.git' },
          mappings = {
            i = {
              ['<C-j>'] = require('telescope.actions').move_selection_next,
              ['<C-k>'] = require('telescope.actions').move_selection_previous,
            },
            n = {
              ['j'] = require('telescope.actions').move_selection_next,
              ['k'] = require('telescope.actions').move_selection_previous,
            },
          },
        },
        extensions = {
          ['ui-select'] = {
            require('telescope.themes').get_dropdown(),
          },
        },
      }

      pcall(require('telescope').load_extension, 'fzf')
      pcall(require('telescope').load_extension, 'ui-select')

      local builtin = require 'telescope.builtin'
      vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = '[F]ind [F]iles' })
      vim.keymap.set('n', '<leader>fg', builtin.live_grep, { desc = '[F]ind by [G]rep' })
      vim.keymap.set('n', '<leader>fb', builtin.buffers, { desc = '[F]ind [B]uffers' })
      vim.keymap.set('n', '<leader>fh', builtin.help_tags, { desc = '[F]ind [H]elp' })

      vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = '[S]earch [H]elp' })
      vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[S]earch [K]eymaps' })
      vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = '[S]earch [F]iles' })
      vim.keymap.set('n', '<leader>ss', builtin.builtin, { desc = '[S]earch [S]elect Telescope' })
      vim.keymap.set('n', '<leader>sw', builtin.grep_string, { desc = '[S]earch current [W]ord' })
      vim.keymap.set('n', '<leader>sg', builtin.live_grep, { desc = '[S]earch by [G]rep' })
      vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[S]earch [D]iagnostics' })
      vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[S]earch [R]esume' })
      vim.keymap.set('n', '<leader>sg', builtin.git_status, { desc = '[S]earch [G]it status' })
      vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = '[S]earch Recent Files ("." for repeat)' })
      vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Find existing buffers' })

      vim.keymap.set('n', '<leader>/', function()
        builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
          winblend = 10,
          previewer = false,
        })
      end, { desc = '[/] Fuzzily search in current buffer' })

      vim.keymap.set('n', '<leader>s/', function()
        builtin.live_grep {
          grep_open_files = true,
          prompt_title = 'Live Grep in Open Files',
        }
      end, { desc = '[S]earch [/] in Open Files' })

      vim.keymap.set('n', '<leader>sn', function()
        builtin.find_files { cwd = vim.fn.stdpath 'config' }
      end, { desc = '[S]earch [N]eovim files' })
    end,
  },

  -- Neo-tree file explorer
  {
    'nvim-neo-tree/neo-tree.nvim',
    version = '*',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-tree/nvim-web-devicons',
      'MunifTanjim/nui.nvim',
    },
    cmd = 'Neotree',
    keys = {
      { '<leader>e', '<cmd>Neotree filesystem toggle left<cr>', desc = 'NeoTree toggle', silent = true },
      { '<leader>o', '<cmd>Neotree filesystem focus left<cr>', desc = 'NeoTree focus', silent = true },
    },
    opts = {
      close_if_last_window = false,
      popup_border_style = 'rounded',
      enable_git_status = true,
      enable_diagnostics = true,
      default_component_configs = {
        container = {
          enable_character_fade = true,
        },
        indent = {
          indent_size = 2,
          padding = 1,
          with_markers = true,
          indent_marker = '│',
          last_indent_marker = '└',
          highlight = 'NeoTreeIndentMarker',
        },
        icon = {
          folder_closed = '󰉋',
          folder_open = '󰝰',
          folder_empty = '󰉖',
          default = '*',
        },
        git_status = {
          symbols = {
            added = '',
            modified = '',
            deleted = '✖',
            renamed = '󰁕',
            untracked = '',
            ignored = '',
            unstaged = '󰄱',
            staged = '',
            conflict = '',
          },
        },
      },
      window = {
        position = 'left',
        width = 40,
        mapping_options = {
          noremap = true,
          nowait = true,
        },
        mappings = {
          ['<space>'] = {
            'toggle_node',
            nowait = false,
          },
          ['<2-LeftMouse>'] = 'open',
          ['<cr>'] = 'open',
          ['<esc>'] = 'cancel',
          ['S'] = 'open_split',
          ['s'] = 'open_vsplit',
          ['t'] = 'open_tabnew',
          ['a'] = 'add',
          ['A'] = 'add_directory',
          ['d'] = 'delete',
          ['r'] = 'rename',
          ['y'] = 'copy_to_clipboard',
          ['x'] = 'cut_to_clipboard',
          ['p'] = 'paste_from_clipboard',
          ['c'] = 'copy',
          ['m'] = 'move',
          ['q'] = 'close_window',
          ['R'] = 'refresh',
          ['?'] = 'show_help',
        },
      },
      filesystem = {
        filtered_items = {
          visible = false,
          hide_dotfiles = true,
          hide_gitignored = true,
          hide_hidden = true,
        },
        follow_current_file = {
          enabled = false,
          leave_dirs_open = false,
        },
        group_empty_dirs = false,
        hijack_netrw_behavior = 'open_default',
        use_libuv_file_watcher = false,
        window = {
          mappings = {
            ['<bs>'] = 'navigate_up',
            ['.'] = 'set_root',
            ['H'] = 'toggle_hidden',
            ['/'] = 'fuzzy_finder',
            ['D'] = 'fuzzy_finder_directory',
            ['#'] = 'fuzzy_sorter',
            ['f'] = 'filter_on_submit',
            ['<c-x>'] = 'clear_filter',
            ['[g'] = 'prev_git_modified',
            [']g'] = 'next_git_modified',
          },
        },
      },
    },
  },

  -- Harpoon for quick file navigation
  {
    'ThePrimeagen/harpoon',
    branch = 'harpoon2',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      local harpoon = require 'harpoon'
      harpoon:setup()

      vim.keymap.set('n', '<leader>ha', function()
        harpoon:list():add()
      end, { desc = 'Harpoon: Add file' })
      vim.keymap.set('n', '<leader>hh', function()
        harpoon.ui:toggle_quick_menu(harpoon:list())
      end, { desc = 'Harpoon: Toggle menu' })

      vim.keymap.set('n', '<leader>h1', function()
        harpoon:list():select(1)
      end, { desc = 'Harpoon: Go to file 1' })
      vim.keymap.set('n', '<leader>h2', function()
        harpoon:list():select(2)
      end, { desc = 'Harpoon: Go to file 2' })
      vim.keymap.set('n', '<leader>h3', function()
        harpoon:list():select(3)
      end, { desc = 'Harpoon: Go to file 3' })
      vim.keymap.set('n', '<leader>h4', function()
        harpoon:list():select(4)
      end, { desc = 'Harpoon: Go to file 4' })

      vim.keymap.set('n', '<leader>hn', function()
        harpoon:list():next()
      end, { desc = 'Harpoon: Next file' })
      vim.keymap.set('n', '<leader>hp', function()
        harpoon:list():prev()
      end, { desc = 'Harpoon: Previous file' })

      vim.keymap.set('n', '<C-1>', function()
        harpoon:list():select(1)
      end, { desc = 'Harpoon: Go to file 1' })
      vim.keymap.set('n', '<C-2>', function()
        harpoon:list():select(2)
      end, { desc = 'Harpoon: Go to file 2' })
      vim.keymap.set('n', '<C-3>', function()
        harpoon:list():select(3)
      end, { desc = 'Harpoon: Go to file 3' })
      vim.keymap.set('n', '<C-4>', function()
        harpoon:list():select(4)
      end, { desc = 'Harpoon: Go to file 4' })
    end,
  },

  -- Tmux navigator
  {
    'christoomey/vim-tmux-navigator',
    cmd = {
      'TmuxNavigateLeft',
      'TmuxNavigateDown',
      'TmuxNavigateUp',
      'TmuxNavigateRight',
      'TmuxNavigatePrevious',
    },
    keys = {
      { '<c-h>', '<cmd>TmuxNavigateLeft<cr>' },
      { '<c-j>', '<cmd>TmuxNavigateDown<cr>' },
      { '<c-k>', '<cmd>TmuxNavigateUp<cr>' },
      { '<c-l>', '<cmd>TmuxNavigateRight<cr>' },
      { '<c-\\>', '<cmd>TmuxNavigatePrevious<cr>' },
    },
  },
  {
    'folke/flash.nvim',
    event = 'VeryLazy',
    ---@type Flash.Config
    opts = {
      modes = {
        char = {
          enabled = true,
          -- This replaces f/F/t/T
          jump_labels = true,
        },
      },
    },
  -- stylua: ignore
  keys = {
    -- Normal Flash jump
    { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },

    -- Replace f / F / t / T
    { "f", mode = { "n", "x", "o" }, function() require("flash").jump({ mode = "char" }) end, desc = "Flash f" },
    { "F", mode = { "n", "x", "o" }, function() require("flash").jump({ mode = "char", backwards = true }) end, desc = "Flash F" },
    { "t", mode = { "n", "x", "o" }, function() require("flash").jump({ mode = "char", jump = { inclusive = false } }) end, desc = "Flash t" },
    { "T", mode = { "n", "x", "o" }, function() require("flash").jump({ mode = "char", backwards = true, jump = { inclusive = false } }) end, desc = "Flash T" },
  },
  },
}
