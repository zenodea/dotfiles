# Overlay and `/todos` display

How
[`@juicesharp/rpiv-todo`](https://www.npmjs.com/package/@juicesharp/rpiv-todo)
renders the task list — when the overlay appears, what each glyph means, how
overflow is trimmed, and which strings localize.

> Local presentation override: Todos renders only in the fullscreen workspace's
> bounded sidebar, without a visible shortcut hint. No native above-editor widget
> is mounted in regular mode or when the workspace is detached. `/todos`, tool
> responses, state replay, and configured shortcuts are unchanged.

## When the overlay exists

The local widget mounts into the companion workspace sidebar, never above the
Pi editor. Without an attached workspace, `/todos` remains available on demand.

| Stage | Condition |
| --- | --- |
| Created | At the first session start that has a UI. A headless session never creates it. |
| Registered | Only while at least one overlay-visible task exists. The widget unregisters itself when the list empties, and re-registers when a task reappears. |
| Bound | Only the foreground session's overlay is refreshed. A detached or child session has its own task state and never rebinds or repaints the foreground panel. |
| Disposed | On the foreground session's shutdown. A child session shutting down leaves the overlay alone. |

Task state is partitioned by session id, so parallel sessions cannot read or
overwrite each other's lists. Nothing is written to disk: on session start,
compaction, and session-tree changes, the list is rebuilt by walking the branch
and taking the last `todo` tool result's snapshot, which replaces the whole list
(last-write-wins).

## Local workspace placement bridge

This local fork accepts `agent-workspace:todo-panel:v1` host offers over Pi's extension event bus. An offer carries an opaque `owner` and an optional `mount(factory?)` callback. The factory receives the host TUI and returns this overlay's own live component. A successful mount registers with that host; a rejected/stale offer leaves the widget unregistered. There is no native above-editor fallback. An offer without `mount` releases only a matching owner.

On foreground session start, `agent-workspace:todo-panel-request:v1` discovers an already-attached host. Offers also arrive when the workspace attaches or detaches, so extension load order does not decide placement. Each host lease is attachment-scoped; stale callbacks cannot mount after an off/on or renderer transition. Foreground shutdown releases the panel and the listener. The companion workspace delegates live rendering at the sidebar's available width, mouse input, and invalidation to the leased component. No task state or model-facing messages travel over this UI bridge.

## Anatomy of a row

```
▾ Todos (2/5)
├─ ✓ Create DemoTodo domain entity
├─ ✓ Create IDemoTodoRepository interface
├─ ◐ Create DemoTodoRepository (creating the repository)
├─ ○ Register DI bindings
└─ ○ Add integration tests
```

- **Heading** — `▸ Todos (done/total)` when collapsed, `▾` when expanded, with
  no shortcut hint. Accent color while any task is `pending` or
  `in_progress`; dimmed once everything is completed. Click to toggle in
  fullscreen mode without moving editor focus.
- **Glyphs** — `○` pending, `◐` in_progress, `✓` completed, `✗` deleted.
  Completed and deleted subjects render dim and struck through.
- **activeForm** — appended dim in parentheses, only while the task is
  `in_progress`.
- **Dependencies** — appended as `⛓ #1,#2` when the task has a `blockedBy` set.
- **`#id` prefix** — shown on every row only when at least one visible task
  carries a `blockedBy`. Without a `⛓ #N` anywhere, the per-row ids have nothing
  to point at, so they are omitted.
- **Prefixes** — `├─` on each row, `└─` on the last one. A blank spacer line is
  always appended below the Todo content for panel spacing.

Rows longer than the terminal width are truncated with `…`.

## Overflow

In the local workspace, expanding shows every visible task inside the bounded,
independently scrollable Todo area. Native above-editor placement is disabled
locally. The retained non-panel renderer's
content-row budget is `maxWidgetLines` (default `12`), and the heading counts
against it. When there are more tasks than fit:

1. one row is reserved for the summary line;
2. completed tasks are dropped first, newest first — the oldest completed rows
   are the last completed rows to go;
3. if the unfinished tasks alone still overflow, the tail of that list is
   truncated;
4. the last row becomes `+N more (X completed, Y pending)`.

The local sidebar shows every task when expanded, independently of Pi's
tool-output expansion setting; the host scroll container bounds its height.
See [configuration.md](./configuration.md#maxwidgetlines) for the retained
non-panel budget's floor and reload semantics.

## Completed tasks fading out

A completed task stays on screen for the remainder of the turn in which it was
completed. At the start of the next agent turn, every completed row that has
already been displayed is hidden from later renders. Reloading or compacting the
session resets that tracking, so a fresh session shows the full list again.

## Collapsing

Click the sidebar heading in fullscreen mode or use the configured collapse
shortcut (upstream default `ctrl+shift+t`) to toggle between a single summary
heading and task rows. No shortcut hint or second help row is shown; a trailing
blank spacer remains. Clicks do not steal focus or submit the draft. Hidden
completed rows are not marked as seen.

Rebind or disable the shortcut with `collapseKey`; see
[configuration.md](./configuration.md#collapsekey). `"off"` disables only the
shortcut, not fullscreen heading clicks. Other configured keys still work
without being printed in the heading. The optional `startCollapsed` setting
selects the initial state on `/reload`; this installation starts collapsed.
Regular mode has no panel or mouse capture, so use `/todos` there.

## `/todos`

`/todos` prints the whole list grouped by status, independent of the overlay's
row budget and auto-hiding:

```
2/7 completed · 1 in progress · 4 pending
── Pending ──
  ○ #4 Register DI bindings
  ○ #5 Add integration tests    ⛓ #4
  ○ #6 Wire up the HTTP endpoint
  ○ #7 Update the API docs
── In Progress ──
  ◐ #3 Create DemoTodoRepository (creating the repository)
── Completed ──
  ✓ #1 Create DemoTodo domain entity
  ✓ #2 Create IDemoTodoRepository interface
```

The header omits any count that is zero. Sections appear only when they have
tasks. Tombstoned tasks are never listed.

- With no tasks: `No todos yet. Ask the agent to add some!`
- In a non-interactive session: `/todos requires interactive mode`

## Localization

The overlay heading, the `+N more` summary, the `/todos`
section headers, and the status words all localize through
[`@juicesharp/rpiv-i18n`](https://www.npmjs.com/package/@juicesharp/rpiv-i18n)
when that package is installed. Bundled locales: `de`, `en`, `es`, `fr`, `pt`,
`pt-BR`, `ru`, `uk`, `zh`.

LLM-facing output — the tool response envelope, reducer error messages, and the
schema descriptions — stays English by design.

The SDK is a soft optional peer, loaded through a dynamic import at module init.
When it is absent, every call site returns its inline English literal and the
extension stays online: no warning, no crash. Install it at any time with
`pi install npm:@juicesharp/rpiv-i18n` and restart the session. To add or
override a translation, drop a `locales/<code>.json` file mirroring `en.json` —
see the `@juicesharp/rpiv-i18n` README's "Contributing translations" section.
