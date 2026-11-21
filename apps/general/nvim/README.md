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

## Rex integration (both presets, no new dependencies)

`config/rex.lua` and `config/rex_edit.lua` use the installed `rex` and `nvim`
CLIs. Nothing else is installed and no background bridge service runs.

### Navigation

`Ctrl-h/j/k/l` moves between Neovim windows, then into a Rex pane at an edge.
Outside Neovim these keys navigate Rex panes; a nested tmux retains its keys.
Embedded Neovim terminals leave terminal-input mode before moving. Navigation
stops at the outside edge instead of wrapping. Existing `Ctrl-a` pane shortcuts
and non-Rex tmux/herdr navigation remain available.

### Send context to Pi

| Key (normal or visual mode) | Action |
| --- | --- |
| `Space a s` | Paste the current line / selected lines and their file/range into Pi |
| `Space a c` | Ask for a question/comment, then paste it with that code |
| `Space a r` | Paste just the file/range reference |

Equivalent commands: `:[range]RexSend [question]`, `:[range]RexAsk`, and
`:[range]RexRef`. Visual selections send whole lines, including unsaved text
(marked as such). A sole Pi in the same Rex tab is preferred; otherwise a sole
Pi in the session is used, or a picker asks. Targets are checked again before
sending; stale processes, open permission/question prompts, and programs that
do not support bracketed paste are refused. Terminal control bytes are stripped.

**Nothing is submitted automatically.** The Pi pane takes focus so you can
check the message and press Enter yourself. There is no persistent review store
or automatic agent editing.

### Open in the existing editor

```sh
rex-edit file.lua
rex-edit +42 -- 'file with spaces.lua'
e +42 file.lua                       # shortcut in a new zsh shell
```

A Neovim started in Rex registers its existing Unix socket in a user-private
`stdpath('state')/rex-edit/` directory. The opener considers only live editors
in the same Rex server/session and project, prefers the same tab, and asks if
several still match. Registration is removed on normal exit; dead sockets are
ignored. Run the command on the machine where the editor and files live.
Nested tmux editors are not registered: several tmux panes share one Rex block,
so registering them would choose the last editor arbitrarily.

The opener preserves unsaved buffers and avoids replacing fixed/floating
panels. With no matching editor, it starts a normal blocking Neovim. `$EDITOR`
and blocking commit-message editing are deliberately unchanged.

`e` in a Rex Lazygit popup uses the same opener. The popup is minimized, not
killed; `Ctrl-a Shift-l` restores that same Lazygit. The existing callback for
Lazygit inside Neovim also remains available.

After installing/syncing these dotfiles, reload Rex with `rex config reload`.
Start a new Neovim for socket registration and a new shell for the `e` shortcut.

### Tests

From the repository root:

```sh
nvim --headless -u NONE -l apps/general/nvim/tests/rex.lua
python3 apps/general/nvim/tests/integration.py
```

The second test uses Python's standard library and a disposable Rex server,
Neovim instances, a fake Pi, and the installed Lazygit. It never uses the user's
running sessions or sends messages to a real agent.

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
