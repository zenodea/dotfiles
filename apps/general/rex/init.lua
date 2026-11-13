-- Rex key bindings, laid out like herdr's [keys]: C-a prefix, - and _ to split,
-- C-a h/j/k/l to move. Bare ctrl+h/j/k/l stay with zsh and nvim.
-- Rex doesn't watch this file: C-a r (or `rex config reload`) after editing.

local terminal = "com.superlogical.terminal"
local shell = terminal .. ".shell"

-- The focused pane's working directory, so popups and agents open where you are.
local function cwd()
  local p = rex.block.call(terminal, "process", {})
  return p and p.foreground and p.foreground.cwd or nil
end

local function program(command)
  return { flavor = shell, label = command[1], options = { command = command, cwd = cwd() } }
end

-- tmux display-popup: a floating pane, gone when the program exits.
local function popup(ctx, args)
  local s = args.size or 0.9
  local _, err = rex.session.new_layer{
    bounds = { (1 - s) / 2, (1 - s) / 2, s, s },
    focus = true,
    layout = { block = program(args.command) },
  }
  if err ~= nil then error(err, 0) end
end

-- Client actions run in the app, not here, so ask the app to perform them.
local function perform(ctx, action, args)
  local _, err = rex.call("client.perform", {
    client_id = ctx.client_id,
    session_id = ctx.session_id,
    block_id = ctx.block_id,
    action = action,
    args = args,
    timeout_ms = 2000,
  })
  return err
end

-- Agents get a tab rather than a popup: a tab keeps running when you leave it.
-- The app has to show the tab itself, or nothing sizes it and it stays 80x24.
local function agent_tab(ctx, args)
  local w, err = rex.session.new_window{ layout = rex.layout.block(program(args.command)) }
  if err ~= nil then error(err, 0) end
  err = perform(ctx, "session.select", { session_id = ctx.session_id, window_id = w.window_id })
  if err ~= nil then error(err, 0) end
end

rex.action{ name = "popup", title = "Open Popup", args = { command = "array", size = "number?" }, run = popup }
rex.action{ name = "agent_tab", title = "Open Agent Tab", args = { command = "array" }, run = agent_tab }

-- Prefix --------------------------------------------------------------------

local function prefix(key, action, args)
  rex.bind("ctrl+a>" .. key, action, args)
end

prefix("ctrl+a", "pane.send_key", { key = "ctrl+a" })

-- Panes ---------------------------------------------------------------------

-- splits: - side by side, _ stacked
prefix("-", "pane.split", { direction = "right" })
prefix("shift+-", "pane.split", { direction = "down" })

for key, dir in pairs{ h = "left", j = "down", k = "up", l = "right" } do
  prefix(key, "pane.focus", { direction = dir })
  prefix("ctrl+" .. key, "pane.focus", { direction = dir })
  prefix(dir, "pane.focus", { direction = dir })
  prefix("ctrl+" .. dir, "pane.resize", { direction = dir })
  rex.bind("ctrl+alt+" .. key, "pane.focus", { direction = dir })
end
-- ctrl+o and ctrl+tab too, for ctrl still held after C-a: without a binding,
-- ctrl+tab falls through to the app's Show Next Tab menu item.
for _, key in ipairs{ "o", "tab", "ctrl+o", "ctrl+tab" } do
  prefix(key, "pane.focus_next")
end

prefix("x", "pane.close")
prefix("z", "pane.zoom")
prefix("f", "pane.zoom")
prefix("=", "pane.balance")
prefix("[", "client.find.open")

-- Resize mode: h/j/k/l or arrows, shift for big steps, Escape or Enter to leave.
rex.mode("resize", { exclusive = true })
prefix("shift+r", "client.mode.enter", { name = "resize" })
for key, dir in pairs{ h = "left", j = "down", k = "up", l = "right",
                       left = "left", down = "down", up = "up", right = "right" } do
  rex.bind("resize/" .. key, "pane.resize", { direction = dir })
  rex.bind("resize/shift+" .. key, "pane.resize", { direction = dir, amount = 15 })
end
rex.bind("resize/=", "pane.balance")
rex.bind("resize/enter", "client.mode.exit")

-- Tabs ----------------------------------------------------------------------

prefix("c", "client.tab.new")
prefix("ctrl+n", "client.tab.new")
prefix("n", "client.tab.next")
prefix("shift+n", "client.tab.previous")
prefix(",", "client.tab.rename")
prefix("shift+7", "client.tab.close") -- &
prefix("shift+x", "client.tab.close")
for i = 1, 9 do
  prefix(tostring(i), "client.tab.goto", { index = i })
end

-- Sessions ------------------------------------------------------------------

prefix("ctrl+shift+n", "session.new")
prefix("s", "session.switch")
prefix("w", "session.switch")
prefix("shift+4", "session.rename") -- $
prefix("shift+9", "session.previous") -- (
prefix("shift+0", "session.next") -- )

prefix("r", "client.config.reload")
prefix("b", "client.sidebar.toggle")
prefix("shift+f", "client.fullscreen.toggle") -- Renux: full screen mode
prefix("shift+o", "client.overview.toggle") -- Renux: overview of every tab
prefix("i", "client.sidebar.activity.toggle")

-- Programs ------------------------------------------------------------------

prefix("y", "popup", { command = { "yazi" } })
prefix("shift+l", "popup", { command = { "lazygit" } })
prefix("p", "popup", { command = { "lodestar", "settings" }, size = 0.6 })
prefix("shift+p", "popup", { command = { "lodestar", "sidebar" }, size = 0.6 })
prefix("a", "agent_tab", { command = { "claude" } })
prefix("shift+a", "agent_tab", { command = { "codex" } })
pcall(dofile, os.getenv("HOME") .. "/.config/rex/compy.lua")
