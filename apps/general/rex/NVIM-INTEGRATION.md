# Rex ↔ Neovim: integration investigation

**Implementation follow-up:** navigation, Pi context sending, and editor reuse are now implemented locally without new dependencies. See the [usage and test instructions](../nvim/README.md#rex-integration-both-presets-no-new-dependencies). The findings below are the pre-implementation investigation snapshot.

Investigated 2026-11-16. Recommendation: keep Rex responsible for the workspace and Neovim responsible for editing. Start with navigation; add editor-to-agent context only after that feels right. No configuration or existing terminal layout was changed during this investigation.

## Your current setup

| Finding | Local source |
| --- | --- |
| Neovim uses the `minimal` preset, with navigation, Git, UI and images but not the coding/quickask/debug modules. | [preset selection](../../../.nvim-preset), [preset definitions](../nvim/config/lua/config/preset.lua) |
| `Ctrl-h/j/k/l` already moves between Neovim windows, with tmux integration and a custom herdr edge handoff. No Rex branch exists. | [navigation.lua](../nvim/config/lua/plugins/navigation.lua), [keymaps.lua](../nvim/config/lua/config/keymaps.lua) |
| Rex uses `Ctrl-a` prefix navigation and `Ctrl-Alt-h/j/k/l`; its comments explicitly reserve bare Ctrl keys for applications. | [init.lua](init.lua) |
| Rex already opens Lazygit/Yazi popups in the focused foreground process's cwd. | [init.lua](init.lua) |
| Lazygit launched inside Neovim can open a file back in that editor through `$NVIM` and `:LazygitEdit`. A separately launched Rex popup has no corresponding editor-socket handoff in this config. | [Lazygit config](../lazygit/config/config.yml), [Git plugin](../nvim/config/lua/plugins/git.lua), [Rex popup implementation](init.lua) |
| Neovim already follows the dotfiles palette and enables the system clipboard; Snacks also has a Rex-specific image compatibility hook. | [mini.lua](../nvim/config/lua/plugins/mini.lua), [options.lua](../nvim/config/lua/config/options.lua), [image.lua](../nvim/config/lua/plugins/image.lua) |

Live observations: Neovim **0.12.6**; Rex **0.0.1794347992-g99caa8**, API revision 13; connected client **Renux 0.1.0** on this Linux machine. No existing Neovim process was found during the initial process check, so no live user editor was probed.

`rex -C zenodea-framework actions --json` returned an empty action list. This means actions are not advertised, **not** that Renux implements no client actions. The local Renux source handles `client_perform_requested` and has an action dispatcher, gated by its remote-control setting. Prefer server-side methods for portable integration; test any client-specific behavior explicitly. Sources: `/home/zeno-marengo/Documents/renux/src/rex/server.zig` (`handlePerform`) and `src/app/app.zig` (`performInner`). Source checkout and installed executable were not verified to be the same revision.

## Ranked opportunities

### 1. Shared navigation — smallest useful first step

**Experience:** `Ctrl-l` first moves right inside Neovim. At its rightmost split, it moves into the Rex pane on the right. The same rule applies in each direction. Keep the existing `Ctrl-a` shortcuts as a fallback.

**Smallest implementation:** extend the existing tmux/herdr navigation function with a Rex branch, preserving the old environments. For the full two-way experience, add matching program-aware Rex bindings: pass the keys through when Neovim owns the pane; otherwise focus a Rex neighbor. A Neovim-only edge handoff is a smaller first slice and leaves shell key behavior unchanged.

The installed server exposes `session.focus_direction` with `direction = left|right|up|down` and `wrap=false`. The CLI equivalent is `rex focus -s SESSION DIRECTION`. No Mac remote-control action is needed. The server method starts from the **currently focused block in the active window**, not a supplied origin block, so asynchronous focus changes are an edge case. Moving focus also ends zoom. [R1, R2]

Existing implementations worth borrowing from rather than inventing a protocol:

- [wassimk/rex-navigator.nvim](https://github.com/wassimk/rex-navigator.nvim): paired Rex/Neovim navigation; uses server focus methods and defaults to no wrapping. Its [Rex source](https://raw.githubusercontent.com/wassimk/rex-navigator.nvim/main/rex/rex-navigator.lua) was reviewed. Its foreground-process detection does not inspect Neovim ancestors for embedded `:terminal` shells.
- [tenfyzhong/rex.nvim](https://github.com/tenfyzhong/rex.nvim): supports normal/terminal-mode mappings and detects Neovim ancestors on the Rex side. Its [Rex bridge](https://github.com/tenfyzhong/rex.nvim/blob/4660750c185f53e35d06caed7207b009e90dbc95/rex/navigation.lua) and [Neovim module](https://github.com/tenfyzhong/rex.nvim/blob/4660750c185f53e35d06caed7207b009e90dbc95/lua/rex/init.lua) were reviewed. It also reloads unmodified file buffers on window entry—an extra behavior this setup does not necessarily need.

**Decision:** prefer extending the local bridge for the basic handoff; use a paired plugin only if its additional behavior is wanted. Do not install two navigation owners for the same keys. Any full shared-key setup must respect shell/application shortcuts, nested tmux precedence, terminal mode, and your existing resize mode. Plugin behavior has not been live-tested in Renux.

### 2. Send file/line context and review comments to Pi — biggest workflow upgrade

**Experience:** select code, attach `src/example.ts:12-20` to the Pi input in another Rex pane, then type a question. Or add comments to selected code and send the comments together, without manually copying filenames or snippets.

[crierr/rex-relay.nvim](https://github.com/crierr/rex-relay.nvim) already documents this workflow, including Pi, same-tab preference, an agent picker, and separate paste versus submit commands. `:Relay ref` sends a path/range without submitting; `:Relay comment` records comments; `:Relay send` pastes them; `:Relay submit` additionally presses Enter. This is a context bridge, not an embedded AI chat UI. It would fit the minimal preset without enabling the full coding stack. [P1]

The [Rex adapter source](https://github.com/crierr/rex-relay.nvim/blob/72742f0a8443de225bf47355490359331087874f/lua/rex-relay/rex.lua) uses block listing, program status, process cwd, bracketed paste, and block focus. The installed Rex APIs expose these primitives. A read-only query of this session's Pi pane returned `app=pi`, `state=working`, confirming the identity information is actually present here. This verifies a prerequisite, **not** end-to-end plugin delivery. A new plugin spec must also be included by the minimal preset (or placed in an already imported concern), with the minimal lockfile updated; simply creating another `plugins/*.lua` file would not enable it here.

**Cautions from source:** discovery accepts a pane with a status `app`, rather than checking a strict agent allowlist; commands wait synchronously without an explicit timeout; submit uses a 300 ms delayed Enter. Start with paste-only delivery, explicitly select/check the target, and do not assume arbitrary status-reporting programs are safe destinations. Comments are in memory only. The default `<leader>a` maps would overlap the optional quickask module if that module is enabled later. [P1]

For a deeper review workflow, [paul-enz/reviewr.nvim](https://github.com/paul-enz/reviewr.nvim) documents diff scopes, line comments, Rex agent delivery including Pi, and an agent-turn view. It is broader than a simple context relay; do not install both by default. Its README, not its full implementation, was reviewed. [P2]

### 3. “Open in my existing Neovim” — remove duplicate editors

**Experience:** `e file.ts` in a sibling Rex shell, or `e` in the Rex Lazygit popup, opens the file in the project's existing editor and focuses its Rex pane. File-and-line references can use the same bridge later.

Neovim already supports `--listen`, `--server`, `--remote`, `--remote-expr`, and structured MessagePack-RPC. A temporary isolated instance of the **installed** Neovim successfully opened a filename containing spaces via `--remote` and jumped to line 2 through `--remote-expr`. No extra dependency was necessary. [N1, N2]

The missing component is **routing**: Rex has a block ID, but no documented built-in registry mapping that ID to Neovim's socket. `$NVIM` is available to children launched by Neovim, not automatically to independent sibling panes or Rex-created popups. A small private per-editor registration could map server/session/block/project to `vim.v.servername`; an opener would validate the endpoint, open the file and focus the known Rex block separately. Multiple editors need explicit selection, not a global “last editor wins” socket. [N2, N3, R1]

Reuse the existing `:LazygitEdit` window-selection logic rather than replacing a Neo-tree/fixed-buffer panel. Do not route file names by interpolating them into Ex keystrokes; prefer argv/structured RPC data and deliberate file/line parsing. Protect sockets with a user-private directory; do not expose an unauthenticated TCP listener. [N2]

**Limit:** Neovim does not implement the `--remote-wait` variants, so globally replacing `$EDITOR` would break programs that must wait for editing, such as commit-message editors. Keep blocking editing separate. Remote Rex hosts need editor paths/sockets valid on that host. This registration/opener is a proposal, not implemented. [N1]

### 4. Run commands beside the editor — useful if this is a frequent action

**Experience:** run/re-run tests or selected code in a dedicated Rex pane, retaining the editor and output instead of opening another Neovim terminal.

[oligot/rex-runner.nvim](https://github.com/oligot/rex-runner.nvim) documents a reusable scratch pane, command/line/selection sending, file-path sending and attaching to an existing pane. Its README was reviewed; it was not installed. Do not send selected text to an arbitrary shell as part of an agent-context shortcut. [P3]

For a single test command, a local mapping invoking the installed CLI may be smaller than a plugin. The supported shape is:

```sh
# Illustration only; not executed during this investigation.
rex split -s "$REX_SESSION" -b "$REX_BLOCK" \
  --split=below --ratio 25 --focus=false --keep-open \
  -c /absolute/project --label Tests --shell=none -- npm test
```

The CLI supports JSON IDs, waiting for child exit and explicit cwd. Preserve/reuse the returned block ID instead of repeatedly making panes. The server's terminal `child_exited` event refers to the terminal's initial process, not every command typed into an existing shell. [R2, R3]

Importing failures into Neovim's quickfix list would be **additional glue**: retain raw output, parse it using the relevant error format, and send structured quickfix entries to the editor. None of the runner capabilities checked here establishes an automatic quickfix bridge. [N2]

## Lower-priority ideas and things to avoid

- **File/modified-state titles:** feasible using Neovim title options or Rex's explicit block-label API. Program status OSC 7501 is a separate structured status channel; it does not automatically rename a pane. Renux source reads status records and terminal titles, but presentation of an editor-specific report has not been tested. Avoid reporting ordinary editing as constantly “working” or every diagnostic as an attention-demanding agent error. [R1, R4]
- **Richer status:** OSC 7501 supports `app`, states, progress, title/message and hierarchical records. Reports replace the entire record and lifecycle cleanup matters. It has no dedicated editor-socket field; do not turn status text into trusted executable routing data. [R4]
- **More theme integration:** already largely solved by the shared dotfiles palette; adding another theme owner is unnecessary.
- **Clipboard rewrite:** already configured for the system clipboard. Neovim has an OSC 52 provider for remote use, but copy support is not proof of clipboard-read support. Rex's `clipboard_read` reads cached copies written by terminal programs, not arbitrary OS clipboard contents. No clipboard contents were read or overwritten during this investigation. [N4, R1]
- **Permanent event daemon:** unnecessary for navigation or one-shot task launching. If later needed, `rex.on` works in a running `rex do` script, **not** in `init.lua`; it needs lifecycle management. [R3]
- **Turning every Neovim split into a Rex pane:** a much larger frontend/state-synchronization project than these workflow improvements justify.

## Verification and implementation boundaries

Verified live: versions, current client/session metadata, advertised actions, focus/split API schemas, Pi program-status reporting, CLI options, Neovim remote opening and line positioning in a disposable process. Read: local dotfiles, relevant Renux source, official Rex/Neovim docs, plugin READMEs and the navigation/relay sources cited above.

Not verified: end-to-end smart navigation on Renux, plugin installation/tests, actual delivery to a user's agent, RPC routing between sibling panes, client title presentation, remote-machine behavior or bidirectional OSC 52 clipboard support. Existing user changes in the working tree were left alone. This note is the only repository file created by the investigation.

Suggested acceptance check for the first implementation: two ordinary Neovim splits next to a Rex shell; move inside the editor, out across the boundary, and back; check outer edges do not wrap, retain `Ctrl-a` fallback bindings, and confirm non-Rex/tmux/herdr mappings still work. If full shared keys are enabled, also check shell and embedded-terminal behavior.

## Primary sources

- **R1:** Installed server self-documentation: `rex api describe session.focus_direction --json`, `session.new_split`, `session.set_block_label`, `com.superlogical.terminal.program_status`, `com.superlogical.terminal.process`, `com.superlogical.terminal.pwd`, and `com.superlogical.terminal.clipboard_read`. Discovery: `rex api list`, `rex client ls --json`, `rex -C zenodea-framework actions --json`. [Official Server API](https://www.superlogical.com/rex/docs/automate/server-api.md).
- **R2:** Installed `rex focus --help`, `rex split --help`, `rex version`; [official CLI guide](https://www.superlogical.com/rex/docs/automate/cli.md) and [CLI reference](https://www.superlogical.com/rex/docs/reference/cli.md).
- **R3:** [Lua Events](https://www.superlogical.com/rex/docs/automate/lua-events.md) and [events reference](https://www.superlogical.com/rex/docs/reference/events.md).
- **R4:** [Program Status Protocol](https://www.superlogical.com/rex/docs/build/program-status.md).
- **N1:** Installed `/usr/share/nvim/runtime/doc/remote.txt`; [upstream remote help](https://github.com/neovim/neovim/blob/master/runtime/doc/remote.txt).
- **N2:** [Neovim API/RPC and security notes](https://github.com/neovim/neovim/blob/master/runtime/doc/api.txt).
- **N3:** [Neovim startup/environment help](https://github.com/neovim/neovim/blob/master/runtime/doc/starting.txt), `$NVIM`; [builtin help](https://github.com/neovim/neovim/blob/master/runtime/doc/builtin.txt), `serverstart()`; [v:servername](https://github.com/neovim/neovim/blob/master/runtime/doc/vvars.txt).
- **N4:** Installed `/usr/share/nvim/runtime/doc/provider.txt`; [upstream clipboard help](https://github.com/neovim/neovim/blob/master/runtime/doc/provider.txt).
- **P1:** [rex-relay.nvim README](https://github.com/crierr/rex-relay.nvim) and [reviewed Rex adapter](https://github.com/crierr/rex-relay.nvim/blob/72742f0a8443de225bf47355490359331087874f/lua/rex-relay/rex.lua).
- **P2:** [reviewr.nvim README](https://github.com/paul-enz/reviewr.nvim).
- **P3:** [rex-runner.nvim README](https://github.com/oligot/rex-runner.nvim).
