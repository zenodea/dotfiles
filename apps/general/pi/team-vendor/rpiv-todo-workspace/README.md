# @juicesharp/rpiv-todo

[![npm version](https://img.shields.io/npm/v/@juicesharp/rpiv-todo.svg)](https://www.npmjs.com/package/@juicesharp/rpiv-todo)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

<div align="center">
  <a href="https://github.com/juicesharp/rpiv-mono/tree/main/packages/rpiv-todo">
    <img src="https://raw.githubusercontent.com/juicesharp/rpiv-mono/main/packages/rpiv-todo/docs/cover.png" alt="rpiv-todo — a persistent todo overlay for Pi Agent, showing a task panel with completed, in-progress, and pending rows" width="50%">
  </a>
</div>

> Local presentation override: Todos appears only in the fullscreen workspace's
> bounded sidebar, with a clickable collapse heading and no visible shortcut hint.
> The native above-editor strip stays hidden, including in regular mode and when
> the workspace is detached. Use `/todos` there. Task state, replay, and configured
> shortcuts are unchanged; upstream above-editor placement described below does
> not apply to this local UI.

Give the model a task list you can see. `rpiv-todo` adds a `todo` tool, a
`/todos` command, and a live panel above the editor to
[Pi Agent](https://github.com/badlogic/pi-mono), so you always know what the
agent is doing now, what it finished, and what is queued. The list is rebuilt
from the conversation itself, so it survives `/reload` and compaction — useful
on long research → design → implement sessions.

## Install

```sh
pi install npm:@juicesharp/rpiv-todo
```

Restart your Pi session.

## Quick start

Run `/todos` after the restart to confirm the extension is loaded. On a fresh
session it prints:

```
No todos yet. Ask the agent to add some!
```

Then ask for something with several steps — "add a repository layer with tests,
and track it as todos". The model calls `todo` and the panel appears above your
input box, updating as work moves:

![Todo overlay panel: a Todos (2/7) heading above two struck-through completed rows, one in-progress row with its activity label, and four pending rows](https://raw.githubusercontent.com/juicesharp/rpiv-mono/main/packages/rpiv-todo/docs/overlay.jpg)

Click the sidebar heading in fullscreen mode to collapse the panel to one
summary line and expand it again. The heading shows `▸`/`▾` without a shortcut
hint. The configured collapse key remains active (upstream default
`ctrl+shift+t`); this installation starts collapsed. Run `/todos` at any time
to print the full list grouped by status.

## Agent workspace integration (local fork)

This local copy retains a UI-only bridge to the companion `pi-subagents-workspace` package. Its fullscreen workspace renders the donor's live component in the existing bounded, independently scrollable sidebar area and forwards heading clicks to collapse or expand it without stealing editor focus. Disabling or detaching the workspace, a rejected/stale host offer, and regular mode leave native above-editor placement hidden.

There is no replacement status row or shortcut hint. Task inspection also remains available on demand through `/todos`; this presentation change does not edit user configuration.

The bridge does not copy task state, change tool responses, or patch Pi's widget API. `/todos`, replay, dependencies, completion fading, localization, and the collapse shortcut retain their existing behavior. The installed upstream npm package remains untouched.

The team installer loads `~/.pi/agent/team-vendor/rpiv-todo-workspace` **instead of** `npm:@juicesharp/rpiv-todo`; do not load both. The originating installation reported offline Pi 0.85.1/Zentui checks, but those artifacts are not included in this export. See the team repository README for installation and verification limits.

## What you get

- **The plan stays on screen.** A panel above the editor shows every task with a
  status glyph, the label of whatever is in progress, and a `Todos (done/total)`
  heading — you never have to ask the agent where it is.
- **Tasks survive `/reload` and compaction.** Each tool call carries the full
  post-mutation snapshot, and the list is replayed from the session branch. No
  disk writes, nothing to lose.
- **Finished work gets out of the way.** Completed rows stay visible for the rest
  of the turn, then drop at the start of the next one; the panel disappears
  entirely when the list empties.
- **The overlay never eats your terminal.** Past the row budget it drops
  completed tasks first, truncates unfinished ones last, and tells you what it
  hid with `+3 more (2 completed, 1 pending)`.
- **The agent can sequence work, not just list it.** `blockedBy` dependencies are
  validated before anything is written — dangling ids, deleted dependencies,
  self-blocks, and cycles are all rejected.
- **Parallel sessions stay separate.** Task state is keyed by session, so a
  detached or child session can neither read nor overwrite the foreground list.
- **Localized UI, no setup required.** Nine locales ship with the package and
  activate when [`@juicesharp/rpiv-i18n`](https://www.npmjs.com/package/@juicesharp/rpiv-i18n)
  is installed; without it, everything falls back to English.

## Configuration

Optional. Create `~/.config/rpiv-todo/config.json` (or
`$XDG_CONFIG_HOME/rpiv-todo/config.json` if you set that variable):

```json
{
  "maxWidgetLines": 8,
  "collapseKey": "alt+t"
}
```

| Setting | What it does | Default |
| --- | --- | --- |
| `maxWidgetLines` | Content rows the overlay may use, heading included. Minimum `3`. Applies on the next repaint. Pi's tool-output expansion mode shows all tasks. | `12` |
| `startCollapsed` | Start with only the summary heading. Only boolean `true` enables it. Needs `/reload`. | `false` |
| `collapseKey` | Key that collapses and expands the panel, in Pi keybinding form (`alt+o`, `ctrl+shift+t`). Set `"off"` to register no shortcut. Needs `/reload` to rebind. | `"ctrl+shift+t"` |
| `guidance` | Replaces the built-in instructions the extension gives the model about when and how to use the todo list. Needs `/reload`. | _(built-ins)_ |

A missing or malformed file falls back to these defaults. `rpiv-todo` only reads
this file — it never writes one. Full semantics:
[Configuration](https://github.com/juicesharp/rpiv-mono/blob/main/packages/rpiv-todo/docs/configuration.md).

## Reference

- [`todo` tool reference](https://github.com/juicesharp/rpiv-mono/blob/main/packages/rpiv-todo/docs/tool-schema.md)
  — every `todo` parameter, the status machine, the response envelope, and the
  exact error strings.
- [Configuration](https://github.com/juicesharp/rpiv-mono/blob/main/packages/rpiv-todo/docs/configuration.md)
  — config file resolution, option validation rules, and the accepted keybinding
  grammar.
- [Overlay and `/todos`](https://github.com/juicesharp/rpiv-mono/blob/main/packages/rpiv-todo/docs/overlay.md)
  — overlay lifecycle, glyphs, overflow behavior, `/todos` output, and
  localization.

## Requirements

- A Pi Agent host. No API key, no model selection, no native dependencies.
- An interactive session for the panel and `/todos`. Headless runs still get the
  `todo` tool; nothing is rendered.
- [`@juicesharp/rpiv-i18n`](https://www.npmjs.com/package/@juicesharp/rpiv-i18n)
  is an optional peer — install it for a localized UI, skip it for English.

## Related

- [`@juicesharp/rpiv-i18n`](https://www.npmjs.com/package/@juicesharp/rpiv-i18n)
  ([source](https://github.com/juicesharp/rpiv-mono/tree/main/packages/rpiv-i18n))
  — localizes this extension's UI chrome and adds a `/languages` picker.
- [`@juicesharp/rpiv-pi`](https://www.npmjs.com/package/@juicesharp/rpiv-pi)
  ([source](https://github.com/juicesharp/rpiv-mono/tree/main/packages/rpiv-pi))
  — the umbrella package that installs this extension alongside its siblings.

## License

MIT — see [LICENSE](https://github.com/juicesharp/rpiv-mono/blob/main/packages/rpiv-todo/LICENSE).
