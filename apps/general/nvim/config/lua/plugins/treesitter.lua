local ensure = {
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
  'yaml',
  'toml',
  'markdown',
  'diff',
  'html',
  'css',
  'luadoc',
  'markdown_inline',
  'query',
  'vim',
  'vimdoc',
  'terraform',
  'hcl',
  'prisma',
  'dockerfile',
  'graphql',
  'sql',
  'http',
  'regex',
  'gitcommit',
  'git_rebase',
  'gitignore',
}

local function start(buf)
  local ok = pcall(vim.treesitter.start, buf)
  if ok then
    vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  end
  return ok
end

return {
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    lazy = false,
    build = ':TSUpdate',
    config = function()
      local ts = require 'nvim-treesitter'
      local cli = vim.fn.executable 'tree-sitter' == 1
      local available = ts.get_available()
      local warned = false

      if cli then
        ts.install(ensure)
      end

      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('dotfiles-treesitter', { clear = true }),
        callback = function(args)
          local lang = vim.treesitter.language.get_lang(args.match)
          if not lang or not vim.list_contains(available, lang) or vim.list_contains(ts.get_installed 'parsers', lang) then
            start(args.buf)
          elseif not cli then
            if not start(args.buf) and not warned then
              warned = true
              vim.notify('No tree-sitter CLI, so no highlighting for ' .. lang .. '. Install tree-sitter-cli.', vim.log.levels.WARN)
            end
          else
            ts.install(lang):await(function()
              vim.schedule(function()
                if vim.api.nvim_buf_is_valid(args.buf) then
                  start(args.buf)
                end
              end)
            end)
          end
        end,
      })
    end,
  },
}
