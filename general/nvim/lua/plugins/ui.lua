return {
  -- Which-key for keybind help
  {
    'folke/which-key.nvim',
    event = 'VimEnter',

    opts = {
      delay = 0,

      win = {
        -- Border style - choose from: "none", "single", "double", "rounded", "solid", "shadow"
        border = 'rounded', -- or try "double", "single", etc.

        -- Position the window on the right side
        row = math.floor(vim.o.lines * 0.8), -- 10% from top
        col = math.floor(vim.o.columns * 0.7), -- 70% from left (right side)

        -- Window dimensions
        width = math.floor(vim.o.columns * 0.40), -- 25% of screen width
        height = math.floor(vim.o.lines * 0.15), -- 80% of screen height

        -- Padding inside the window
        padding = { 1, 1 }, -- top/bottom, left/right

        -- Window options
        wo = {
          winblend = 0, -- transparency (0-100, 0 = opaque)
        },
      },

      -- Layout configuration
      layout = {
        height = { min = 4, max = 5 }, -- min and max height of the columns
        width = { min = 20, max = 20 }, -- min and max width of the columns
        spacing = 3, -- spacing between columns
        align = 'left', -- align columns left, center or right
      },
      icons = {
        mappings = vim.g.have_nerd_font,
        keys = vim.g.have_nerd_font and {} or {
          Up = '<Up> ',
          Down = '<Down> ',
          Left = '<Left> ',
          Right = '<Right> ',
          C = '<C-…> ',
          M = '<M-…> ',
          D = '<D-…> ',
          S = '<S-…> ',
          CR = '<CR> ',
          Esc = '<Esc> ',
          ScrollWheelDown = '<ScrollWheelDown> ',
          ScrollWheelUp = '<ScrollWheelUp> ',
          NL = '<NL> ',
          BS = '<BS> ',
          Space = '<Space> ',
          Tab = '<Tab> ',
          F1 = '<F1>',
          F2 = '<F2>',
          F3 = '<F3>',
          F4 = '<F4>',
          F5 = '<F5>',
          F6 = '<F6>',
          F7 = '<F7>',
          F8 = '<F8>',
          F9 = '<F9>',
          F10 = '<F10>',
          F11 = '<F11>',
          F12 = '<F12>',
        },
      },
      spec = {
        { '<leader>s', group = '[S]earch' },
        { '<leader>t', group = '[T]oggle' },
        { '<leader>h', group = '[H]arpoon / Git [H]unk', mode = { 'n', 'v' } },
        { '<leader>f', group = '[F]ormat' },
        { '<leader>c', group = '[C]ode' },
        { '<leader>r', group = '[R]ename' },
      },
    },
  },

  -- Colorscheme
  {
    'rmehri01/onenord.nvim',
    lazy = false,
    priority = 1000,
    config = function()
      require('onenord').setup {
        theme = 'dark',
        disable = {
          background = true, -- Disable setting the background color
          float_background = true, -- Disable setting the background color for floating windows
          cursorline = false, -- Disable the cursorlinec
          eob_lines = true, -- Hide the end-of-buffer lines
        },
      }
      vim.cmd.colorscheme 'onenord'
    end,
  },

  -- Lualine statusline
  {
    'nvim-lualine/lualine.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    opts = {
      options = {
        icons_enabled = true,
        theme = 'nord',
        component_separators = { left = '', right = '' },
        section_separators = { left = '', right = '' },
        globalstatus = false,
      },
      sections = {
        lualine_a = { 'mode' },
        lualine_b = { 'branch', 'diff', 'diagnostics' },
        lualine_c = {
          {
            'filename',
            file_status = true,
            path = 1,
            shorting_target = 40,
            symbols = {
              modified = '[+]',
              readonly = '[-]',
              unnamed = '[No Name]',
            },
          },
        },
        lualine_x = { 'encoding', 'fileformat', 'filetype' },
        lualine_y = { 'progress' },
        lualine_z = { 'location' },
      },
    },
  },

  -- Nice Command Line and Notifications
  {
    'folke/noice.nvim',
    event = 'VeryLazy',
    dependencies = {
      { 'MunifTanjim/nui.nvim' },
      {
        'rcarriga/nvim-notify',
        config = function()
          require('notify').setup {
            merge_duplicates = true,
            background_colour = '#000000',
            render = 'wrapped-compact',
            style = 'minimal',
            border = 'rounded',
            timeout = 3000,
            max_width = 50,
            max_height = 10,
          }
        end,
      },
    },
    opts = {
      lsp = {
        override = {
          ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
          ['vim.lsp.util.stylize_markdown'] = true,
          ['cmp.entry.get_documentation'] = true,
        },
      },
      presets = {
        bottom_search = false,
        command_palette = false,
        long_message_to_split = true,
        inc_rename = false,
        lsp_doc_border = false,
      },
      views = {
        cmdline_popup = {
          position = {
            row = 2,
            col = '50%',
          },
          size = {
            width = 60,
            height = 'auto',
          },
          win_options = {
            winhighlight = 'NormalFloat:Normal,FloatBorder:Comment',
          },
        },
        notify = {
          replace = true,
          merge = true,
          view = 'notify',
        },
      },
      notify = {
        enabled = true,
        view = 'notify',
        opts = {
          stages = 'fade_in_slide_out',
          timeout = 3000,
          max_height = function()
            return math.floor(vim.o.lines * 0.75)
          end,
          max_width = function()
            return math.floor(vim.o.columns * 0.75)
          end,
          top_down = true,
        },
      },
      routes = {
        {
          filter = {
            event = 'msg_show',
            any = {
              { find = '%d+L, %d+B' },
              { find = '; after #%d+' },
              { find = '; before #%d+' },
            },
          },
          view = 'mini',
        },
        {
          filter = { event = 'msg_show', min_height = 20 },
          view = 'split',
        },
      },
    },
  },
}
