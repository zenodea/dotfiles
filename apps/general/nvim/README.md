# nvim

Lua config, lazy.nvim, one plugin file per concern.

```
config/
    init.lua                 bootstrap: config.* then lazy with plugins/*
    lua/config/              options, keymaps, autocmds
    lua/plugins/             one spec file per area (see below)
    lua/dotfiles/theme.lua   generated palette (gitignored)
templates/theme.lua          rendered by switch-theme → lua/dotfiles/theme.lua
```

## Theming

`switch-theme` renders `templates/theme.lua` into `lua/dotfiles/theme.lua`
(data only, gitignored). `plugins/mini.lua` applies it via mini.base16 and
file-watches it, so a theme switch re-themes running instances — that's why
`app.sh` has no `reload()`.

## Plugins

| file | holds |
|---|---|
| `mini.lua` | all mini.* (ai, surround, comment, base16 theming + watcher) |
| `treesitter.lua` | nvim-treesitter (`main`), highlighting, parser auto-install |
| `git.lua` | gitsigns, lazygit |
| `coding.lua` | todo-comments, acp, nextedit |
| `completion.lua` | blink.cmp, LuaSnip, lazydev |
| `lsp.lua` | lspconfig, mason, conform, trouble, typescript-tools, fidget |
| `navigation.lua` | telescope, neo-tree, harpoon, tmux-navigator, flash, neoscroll |
| `debug.lua` | DAP, neotest |
| `obsidian.lua` | obsidian.nvim, render-markdown |
| `tools.lua` | dadbod, kulala |
| `ui.lua` | lualine, noice, which-key, notify |

## Presets

`.nvim-preset` at the repo root names the preset to load. No file, or an
empty one, loads `all`.

| preset | loads |
|---|---|
| `all` | every file in `plugins/` and `plugins/extras/` |
| `minimal` | mini, treesitter, navigation, git, ui, image: highlighting, theme, neo-tree, telescope, lazygit, inline images; no LSP, completion or debugging |

Presets are lists of plugin modules in `lua/config/preset.lua`; add one there.
Each preset other than `all` pins its plugins in its own
`lazy-lock.<preset>.json`, because lazy rewrites a lockfile with only the
plugins it loaded.

## Treesitter

Parsers build with the `tree-sitter` CLI (`tree-sitter-cli` package) and a C
compiler. Opening a filetype with no parser installs one, then highlights the
buffer. Without the CLI, nvim warns once per session and highlights only what
is already installed.

## Conventions

- mini.nvim is spec'd only in `mini.lua`: lazy.nvim merges duplicate specs but
  keeps a single config function per plugin.
- `<C-d>`/`<C-u>` stay instant (no neoscroll) so the ghostty cursor-trail
  shader fires on them.
