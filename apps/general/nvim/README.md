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
| `coding.lua` | treesitter, todo-comments, gitsigns, lazygit, acp, nextedit |
| `completion.lua` | blink.cmp, LuaSnip, lazydev |
| `lsp.lua` | lspconfig, mason, conform, trouble, typescript-tools, fidget |
| `navigation.lua` | telescope, neo-tree, harpoon, tmux-navigator, flash, neoscroll |
| `debug.lua` | DAP, neotest |
| `obsidian.lua` | obsidian.nvim, render-markdown |
| `tools.lua` | dadbod, kulala |
| `ui.lua` | lualine, noice, which-key, notify |

## Conventions

- mini.nvim is spec'd only in `mini.lua`: lazy.nvim merges duplicate specs but
  keeps a single config function per plugin.
- `<C-d>`/`<C-u>` stay instant (no neoscroll) so the ghostty cursor-trail
  shader fires on them.
