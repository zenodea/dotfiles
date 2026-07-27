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
        -- top-level plugin options, not `settings` — nesting them made the
        -- monorepo root detection below a no-op
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
      'b0o/schemastore.nvim',
      'towolf/vim-helm', -- helm filetype detection, which nvim has no builtin for
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

          if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight, event.buf) then
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

          if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint, event.buf) then
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

      -- captured before vim.lsp.config() overwrites it below, otherwise our
      -- on_attach would resolve to itself and recurse
      local eslint_on_attach = vim.lsp.config.eslint.on_attach

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
                library = { vim.env.VIMRUNTIME },
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
          -- the stock config already resolves eslint configs per-package in a
          -- monorepo; only the fix-on-save hook is ours
          on_attach = function(client, bufnr)
            if eslint_on_attach then
              eslint_on_attach(client, bufnr)
            end
            vim.api.nvim_create_autocmd('BufWritePre', {
              buffer = bufnr,
              command = 'LspEslintFixAll',
            })
          end,
        },

        jsonls = {
          settings = {
            json = {
              schemas = require('schemastore').json.schemas(),
              validate = { enable = true },
            },
          },
        },

        -- Kubernetes manifests are just YAML until something tells the server
        -- what they are; without a schema they get no validation at all.
        yamlls = {
          settings = {
            yaml = {
              -- SchemaStore.nvim supplies the catalogue, so the server's own
              -- fetcher is turned off to avoid the two disagreeing
              schemaStore = { enable = false, url = '' },
              schemas = vim.tbl_extend('force', require('schemastore').yaml.schemas(), {
                -- "kubernetes" is a magic URI resolved against the schemas
                -- bundled with yaml-language-server
                kubernetes = {
                  'k8s/**/*.yaml',
                  'kubernetes/**/*.yaml',
                  'manifests/**/*.yaml',
                  '*-deployment.yaml',
                  '*-service.yaml',
                  '*-configmap.yaml',
                  '*-ingress.yaml',
                },
              }),
              validate = true,
              -- the server flags non-alphabetical keys by default, which is
              -- noise in a manifest where order is meaningful to a reader
              keyOrdering = false,
            },
          },
        },

        helm_ls = {
          settings = {
            ['helm-ls'] = {
              yamlls = { path = 'yaml-language-server' },
            },
          },
        },

        terraformls = {
          -- upstream's on_attach calls vim.lsp.codelens.enable, which only
          -- exists on 0.12; on 0.11 it throws on every terraform buffer
          on_attach = function(_, bufnr)
            if vim.lsp.codelens.enable then
              vim.lsp.codelens.enable(true, { bufnr = bufnr })
            end
          end,
        },
        tflint = {},
        prismals = {},
        dockerls = {},
        docker_compose_language_service = {},

        rust_analyzer = {},
        pyright = {},
        tailwindcss = {},
        cssls = {},
        clangd = {},
      }

      -- mason-lspconfig v2 dropped `handlers`, so servers are registered with
      -- nvim 0.11's native vim.lsp.config and enabled explicitly here.
      vim.lsp.config('*', {
        capabilities = require('blink.cmp').get_lsp_capabilities(),
      })

      for name, config in pairs(servers) do
        vim.lsp.config(name, config)
      end

      local ensure_installed = vim.tbl_keys(servers)
      vim.list_extend(ensure_installed, {
        'stylua',
        'prettier',
        'prettierd',
        'eslint_d',
        -- nvim-dap is lazy-loaded, and mason-tool-installer.setup replaces its
        -- list rather than appending, so the adapter is requested here
        'js-debug-adapter',
      })

      require('mason-tool-installer').setup { ensure_installed = ensure_installed }

      require('mason-lspconfig').setup {
        ensure_installed = {},
        automatic_installation = false,
        automatic_enable = false,
      }

      vim.lsp.enable(vim.tbl_keys(servers))
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
        yaml = { 'prettierd', 'prettier', stop_after_first = true },
        graphql = { 'prettierd', 'prettier', stop_after_first = true },
        terraform = { 'terraform_fmt' },
        hcl = { 'terraform_fmt' },
        ['terraform-vars'] = { 'terraform_fmt' },
        -- prisma has no standalone formatter; prismals handles it and
        -- lsp_format = 'fallback' above picks that up
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
