return {
  -- Debugger. The case for it here is NestJS: attaching to a running server
  -- and stepping through a request handler or a queue consumer, rather than
  -- reading a stack trace after the fact.
  {
    'mfussenegger/nvim-dap',
    dependencies = {
      { 'rcarriga/nvim-dap-ui', dependencies = { 'nvim-neotest/nvim-nio' } },
      { 'theHamsta/nvim-dap-virtual-text', opts = {} },
    },
    keys = {
      { '<F5>', function() require('dap').continue() end, desc = 'Debug: Start/Continue' },
      { '<F10>', function() require('dap').step_over() end, desc = 'Debug: Step Over' },
      { '<F11>', function() require('dap').step_into() end, desc = 'Debug: Step Into' },
      { '<F12>', function() require('dap').step_out() end, desc = 'Debug: Step Out' },
      -- <leader>d is taken by delete-without-yank, which is an operator and
      -- would make every <leader>d<motion> wait on a timeout
      { '<leader>Db', function() require('dap').toggle_breakpoint() end, desc = '[D]ebug: Toggle [B]reakpoint' },
      {
        '<leader>DB',
        function()
          require('dap').set_breakpoint(vim.fn.input 'Breakpoint condition: ')
        end,
        desc = '[D]ebug: Conditional [B]reakpoint',
      },
      { '<leader>Dc', function() require('dap').continue() end, desc = '[D]ebug: [C]ontinue' },
      { '<leader>Dr', function() require('dap').repl.toggle() end, desc = '[D]ebug: Toggle [R]EPL' },
      { '<leader>Dl', function() require('dap').run_last() end, desc = '[D]ebug: Run [L]ast' },
      { '<leader>Dt', function() require('dap').terminate() end, desc = '[D]ebug: [T]erminate' },
      { '<leader>Du', function() require('dapui').toggle() end, desc = '[D]ebug: Toggle [U]I' },
      {
        '<leader>De',
        function()
          require('dapui').eval(nil, { enter = true })
        end,
        mode = { 'n', 'v' },
        desc = '[D]ebug: [E]valuate',
      },
    },
    config = function()
      local dap = require 'dap'
      local dapui = require 'dapui'

      dapui.setup {
        layouts = {
          {
            elements = {
              { id = 'scopes', size = 0.35 },
              { id = 'breakpoints', size = 0.15 },
              { id = 'stacks', size = 0.25 },
              { id = 'watches', size = 0.25 },
            },
            position = 'left',
            size = 45,
          },
          {
            elements = {
              { id = 'repl', size = 0.5 },
              { id = 'console', size = 0.5 },
            },
            position = 'bottom',
            size = 12,
          },
        },
      }

      dap.listeners.after.event_initialized['dapui_config'] = dapui.open
      dap.listeners.before.event_terminated['dapui_config'] = dapui.close
      dap.listeners.before.event_exited['dapui_config'] = dapui.close

      vim.fn.sign_define('DapBreakpoint', { text = '●', texthl = 'DiagnosticError' })
      vim.fn.sign_define('DapBreakpointCondition', { text = '◐', texthl = 'DiagnosticWarn' })
      vim.fn.sign_define('DapStopped', { text = '▶', texthl = 'DiagnosticInfo' })

      -- nvim-dap-vscode-js is archived, so the adapter is wired to mason's
      -- js-debug-adapter directly
      dap.adapters['pwa-node'] = {
        type = 'server',
        host = '127.0.0.1',
        port = '${port}',
        executable = {
          command = 'js-debug-adapter',
          args = { '${port}' },
        },
      }

      local skip = { '<node_internals>/**', '**/node_modules/**' }

      for _, ft in ipairs { 'javascript', 'typescript', 'javascriptreact', 'typescriptreact' } do
        dap.configurations[ft] = {
          {
            -- `nest start --debug` listens on 9229; this is the everyday one
            type = 'pwa-node',
            request = 'attach',
            name = 'Attach to :9229 (nest start --debug)',
            address = '127.0.0.1',
            port = 9229,
            cwd = '${workspaceFolder}',
            localRoot = '${workspaceFolder}',
            remoteRoot = '${workspaceFolder}',
            sourceMaps = true,
            skipFiles = skip,
            restart = true,
          },
          {
            -- for a service in docker compose, published with
            -- `node --inspect=0.0.0.0:9229`
            type = 'pwa-node',
            request = 'attach',
            name = 'Attach to container (:9229, /usr/src/app)',
            address = '127.0.0.1',
            port = 9229,
            cwd = '${workspaceFolder}',
            localRoot = '${workspaceFolder}',
            remoteRoot = '/usr/src/app',
            sourceMaps = true,
            skipFiles = skip,
            restart = true,
          },
          {
            type = 'pwa-node',
            request = 'attach',
            name = 'Attach to process...',
            processId = require('dap.utils').pick_process,
            cwd = '${workspaceFolder}',
            sourceMaps = true,
            skipFiles = skip,
          },
          {
            type = 'pwa-node',
            request = 'launch',
            name = 'Launch current file (tsx)',
            program = '${file}',
            runtimeExecutable = 'npx',
            runtimeArgs = { 'tsx' },
            cwd = '${workspaceFolder}',
            sourceMaps = true,
            skipFiles = skip,
            console = 'integratedTerminal',
          },
        }
      end
    end,
  },

  -- Run the test under the cursor. Nest generates a spec alongside every
  -- service, so this gets used constantly.
  {
    'nvim-neotest/neotest',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-neotest/nvim-nio',
      'antoinemadec/FixCursorHold.nvim',
      'nvim-treesitter/nvim-treesitter',
      'nvim-neotest/neotest-jest',
      'marilari88/neotest-vitest',
      'mfussenegger/nvim-dap',
    },
    keys = {
      {
        '<leader>Tt',
        function()
          require('neotest').run.run()
        end,
        desc = '[T]est: Run nearest',
      },
      {
        '<leader>Tf',
        function()
          require('neotest').run.run(vim.fn.expand '%')
        end,
        desc = '[T]est: Run [F]ile',
      },
      {
        '<leader>Td',
        function()
          require('neotest').run.run { strategy = 'dap' }
        end,
        desc = '[T]est: [D]ebug nearest',
      },
      {
        '<leader>Ts',
        function()
          require('neotest').summary.toggle()
        end,
        desc = '[T]est: Toggle [S]ummary',
      },
      {
        '<leader>To',
        function()
          require('neotest').output_panel.toggle()
        end,
        desc = '[T]est: [O]utput panel',
      },
      {
        '<leader>TS',
        function()
          require('neotest').run.stop()
        end,
        desc = '[T]est: [S]top',
      },
    },
    config = function()
      require('neotest').setup {
        adapters = {
          require 'neotest-jest' {
            -- Nest's default test script; jestCommand is what neotest shells
            -- out with, so it has to resolve from the package root
            jestCommand = 'npm test --',
            jestConfigFile = function(file)
              -- a Nest monorepo keeps jest config in each package.json
              local util = require 'lspconfig.util'
              local root = util.root_pattern 'package.json'(file)
              return root and (root .. '/package.json') or nil
            end,
            cwd = function(file)
              local util = require 'lspconfig.util'
              return util.root_pattern 'package.json'(file) or vim.fn.getcwd()
            end,
          },
          require 'neotest-vitest',
        },
      }
    end,
  },
}
