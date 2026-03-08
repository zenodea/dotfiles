return {
  -- LSP Configuration
  {
    'folke/lazydev.nvim',
    ft = 'lua',
    opts = {
      library = {
        { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
      },
    },
  },

  -- TypeScript Tools (optimized for large projects)
  {
    'pmizio/typescript-tools.nvim',
    dependencies = { 'nvim-lua/plenary.nvim', 'neovim/nvim-lspconfig' },
    ft = { 'typescript', 'typescriptreact', 'javascript', 'javascriptreact' },
    config = function()
      require('typescript-tools').setup {
        on_attach = function(client, bufnr)
          client.server_capabilities.semanticTokensProvider = nil
        end,
        handlers = {
          ['textDocument/hover'] = vim.lsp.with(vim.lsp.handlers.hover, {
            silent = true,
          }),
        },
        settings = {
          tsserver_max_memory = 8192,
          complete_function_calls = true,
          include_completions_with_insert_text = true,
          code_lens = 'off',
          tsserver_file_preferences = {
            includePackageJsonAutoImports = 'auto',
            includeCompletionsForModuleExports = true,
            includeCompletionsWithInsertText = true,
            allowIncompleteCompletions = false,
            includeInlayParameterNameHints = 'literals',
            includeInlayParameterNameHintsWhenArgumentMatchesName = false,
            includeInlayFunctionParameterTypeHints = false,
            includeInlayVariableTypeHints = false,
            includeInlayPropertyDeclarationTypeHints = false,
            includeInlayFunctionLikeReturnTypeHints = false,
            includeInlayEnumMemberValueHints = false,
            allowRenameOfImportPath = false,
            allowTextChangesInNewFiles = true,
            disableSuggestions = false,
            quotePreference = 'single',
            displayPartsForJSDoc = false,
            generateReturnInDocTemplate = false,
          },
          tsserver_format_options = {
            allowIncompleteCompletions = false,
            allowRenameOfImportPath = false,
          },
          tsserver_plugins = {
            '@styled/typescript-styled-plugin',
          },
          root_dir = function(fname)
            local util = require 'lspconfig.util'
            return util.root_pattern(
              'package.json',
              'tsconfig.json',
              'jsconfig.json',
              '.git',
              'lerna.json',
              'nx.json',
              'turbo.json',
              'pnpm-workspace.yaml',
              'yarn.lock',
              'pnpm-lock.yaml'
            )(fname)
          end,
          single_file_support = false,
        },
      }
    end,
  },

  {
    'neovim/nvim-lspconfig',
    dependencies = {
      { 'mason-org/mason.nvim', opts = {} },
      'mason-org/mason-lspconfig.nvim',
      'WhoIsSethDaniel/mason-tool-installer.nvim',
      { 'j-hui/fidget.nvim', opts = {} },
      'saghen/blink.cmp',
    },
    config = function()
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
        callback = function(event)
          local map = function(keys, func, desc, mode)
            mode = mode or 'n'
            vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
          end

          map('gd', require('telescope.builtin').lsp_definitions, '[G]oto [D]efinition')
          map('K', vim.lsp.buf.hover, 'Hover Documentation')
          map('gi', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')
          map('<C-k>', vim.lsp.buf.signature_help, 'Signature Help')
          map('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
          map('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction', { 'n', 'x' })
          map('gr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')

          -- TypeScript Tools keymaps
          map('<leader>to', '<cmd>TSToolsOrganizeImports<cr>', '[T]ypeScript [O]rganize Imports')
          map('<leader>ts', '<cmd>TSToolsSortImports<cr>', '[T]ypeScript [S]ort Imports')
          map('<leader>tr', '<cmd>TSToolsRemoveUnusedImports<cr>', '[T]ypeScript [R]emove Unused Imports')
          map('<leader>ta', '<cmd>TSToolsAddMissingImports<cr>', '[T]ypeScript [A]dd Missing Imports')
          map('<leader>tf', '<cmd>TSToolsFixAll<cr>', '[T]ypeScript [F]ix All')
          map('<leader>ti', '<cmd>TSToolsGoToSourceDefinition<cr>', '[T]ypeScript Go to Source [I]mplementation')
          map('<leader>tR', '<cmd>TSToolsRenameFile<cr>', '[T]ypeScript [R]ename File')
          map('<leader>tF', '<cmd>TSToolsFileReferences<cr>', '[T]ypeScript [F]ile References')

          map('<leader>f', function()
            require('conform').format { async = true, lsp_format = 'fallback' }
          end, '[F]ormat buffer')

          map('grn', vim.lsp.buf.rename, '[R]e[n]ame')
          map('gra', vim.lsp.buf.code_action, '[G]oto Code [A]ction', { 'n', 'x' })
          map('grr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')
          map('gri', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')
          map('grd', require('telescope.builtin').lsp_definitions, '[G]oto [D]efinition')
          map('grD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')
          map('gO', require('telescope.builtin').lsp_document_symbols, 'Open Document Symbols')
          map('gW', require('telescope.builtin').lsp_dynamic_workspace_symbols, 'Open Workspace Symbols')
          map('grt', require('telescope.builtin').lsp_type_definitions, '[G]oto [T]ype Definition')

          map('<leader>zig', '<cmd>LspRestart<cr>', 'LSP Restart')

          local client = vim.lsp.get_client_by_id(event.data.client_id)

          if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight, { bufnr = event.buf }) then
            local highlight_augroup = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
            vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.document_highlight,
            })

            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.clear_references,
            })

            vim.api.nvim_create_autocmd('LspDetach', {
              group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
              callback = function(event2)
                vim.lsp.buf.clear_references()
                vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buffer = event2.buf }
              end,
            })
          end

          if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint, { bufnr = event.buf }) then
            map('<leader>th', function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
            end, '[T]oggle Inlay [H]ints')
          end
        end,
      })

      vim.diagnostic.config {
        severity_sort = true,
        float = {
          border = 'rounded',
          source = 'if_many',
          header = '',
          prefix = '',
          focusable = false,
        },
        underline = true,
        update_in_insert = false,
        signs = vim.g.have_nerd_font and {
          text = {
            [vim.diagnostic.severity.ERROR] = '●',
            [vim.diagnostic.severity.WARN] = '●',
            [vim.diagnostic.severity.INFO] = '●',
            [vim.diagnostic.severity.HINT] = '●',
          },
        } or {},
        virtual_text = {
          severity = { min = vim.diagnostic.severity.WARN },
          source = 'if_many',
          prefix = '●',
          spacing = 4,
        },
      }

      local capabilities = require('blink.cmp').get_lsp_capabilities()

      local servers = {
        lua_ls = {
          settings = {
            Lua = {
              completion = {
                callSnippet = 'Replace',
              },
              runtime = { version = 'LuaJIT' },
              diagnostics = { globals = { 'vim' } },
              workspace = {
                library = {
                  vim.env.VIMRUNTIME,
                  '${pkgs.lua}/lib',
                  '${pkgs.vimPlugins.plenary-nvim}',
                },
              },
              telemetry = { enable = false },
            },
          },
        },

        eslint = {
          settings = {
            workingDirectories = { mode = 'auto' },
            format = { enable = true },
            codeActionOnSave = {
              enable = true,
              mode = 'all',
            },
            experimental = {
              useFlatConfig = true,
            },
            useESLintClass = true,
            run = 'onType',
          },
          root_dir = function(fname)
            local util = require 'lspconfig.util'
            return util.root_pattern(
              '.eslintrc',
              '.eslintrc.js',
              '.eslintrc.json',
              '.eslintrc.yaml',
              '.eslintrc.yml',
              'eslint.config.js',
              'eslint.config.mjs',
              'package.json'
            )(fname)
          end,
          on_attach = function(client, bufnr)
            vim.api.nvim_create_autocmd('BufWritePre', {
              buffer = bufnr,
              callback = function()
                vim.lsp.buf.code_action {
                  filter = function(action)
                    return action.kind == 'source.fixAll.eslint'
                  end,
                  apply = true,
                }
              end,
            })
          end,
        },

        rust_analyzer = { enable = true },
        pyright = { enable = true },
        jsonls = { enable = true },
        tailwindcss = { enable = true },
        cssls = { enable = true },
        clangd = { enable = true },
      }

      local ensure_installed = vim.tbl_keys(servers or {})
      vim.list_extend(ensure_installed, {
        'stylua',
        'prettier',
        'prettierd',
        'eslint_d',
      })

      require('mason-tool-installer').setup { ensure_installed = ensure_installed }

      require('mason-lspconfig').setup {
        ensure_installed = {},
        automatic_installation = false,
        handlers = {
          function(server_name)
            local server = servers[server_name] or {}
            server.capabilities = vim.tbl_deep_extend('force', {}, capabilities, server.capabilities or {})
            require('lspconfig')[server_name].setup(server)
          end,
        },
      }
    end,
  },

  -- Formatting
  {
    'stevearc/conform.nvim',
    event = { 'BufWritePre' },
    cmd = { 'ConformInfo' },
    keys = {
      {
        '<leader>f',
        function()
          require('conform').format { async = true, lsp_format = 'fallback' }
        end,
        mode = '',
        desc = '[F]ormat buffer',
      },
    },
    opts = {
      notify_on_error = false,
      format_on_save = function(bufnr)
        local disable_filetypes = { c = true, cpp = true }
        if disable_filetypes[vim.bo[bufnr].filetype] then
          return nil
        else
          return {
            timeout_ms = 500,
            lsp_format = 'fallback',
          }
        end
      end,
      formatters_by_ft = {
        lua = { 'stylua' },
        typescript = { 'prettierd', 'prettier', stop_after_first = true },
        typescriptreact = { 'prettierd', 'prettier', stop_after_first = true },
        javascript = { 'prettierd', 'prettier', stop_after_first = true },
        javascriptreact = { 'prettierd', 'prettier', stop_after_first = true },
        json = { 'prettierd', 'prettier', stop_after_first = true },
        css = { 'prettierd', 'prettier', stop_after_first = true },
        scss = { 'prettierd', 'prettier', stop_after_first = true },
        html = { 'prettierd', 'prettier', stop_after_first = true },
        markdown = { 'prettierd', 'prettier', stop_after_first = true },
      },
    },
  },

  {
    'folke/trouble.nvim',
    opts = {},
    cmd = 'Trouble',
    keys = {
      {
        '<leader>xx',
        '<cmd>Trouble diagnostics toggle<cr>',
        desc = 'Diagnostics (Trouble)',
      },
      {
        '<leader>xX',
        '<cmd>Trouble diagnostics toggle filter.buf=0<cr>',
        desc = 'Buffer Diagnostics (Trouble)',
      },
      {
        '<leader>cs',
        '<cmd>Trouble symbols toggle focus=false<cr>',
        desc = 'Symbols (Trouble)',
      },
      {
        '<leader>cl',
        '<cmd>Trouble lsp toggle focus=false win.position=right<cr>',
        desc = 'LSP Definitions / references / ... (Trouble)',
      },
      {
        '<leader>xL',
        '<cmd>Trouble loclist toggle<cr>',
        desc = 'Location List (Trouble)',
      },
      {
        '<leader>xQ',
        '<cmd>Trouble qflist toggle<cr>',
        desc = 'Quickfix List (Trouble)',
      },
    },
  },
}

