-- Run from the repository root: nvim --headless -u NONE -l apps/general/nvim/tests/rex.lua
local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root .. '/apps/general/nvim/config')
local bridge = require 'config.rex'
local system = vim.system
local calls = {}
vim.system = function(argv, opts, callback)
  calls[#calls + 1] = { argv = argv, opts = opts }
  return { wait = function() return { code = 0, stdout = '{}', stderr = '' } end }
end
vim.env.REX_SESSION, vim.env.REX_BLOCK, vim.env.TMUX = 'test-session', 'test-block', nil

vim.cmd 'vsplit'
vim.cmd 'wincmd h'
bridge.navigate 'l'
assert(#calls == 0, 'moving inside Neovim must not call Rex')
bridge.navigate 'l'
assert(vim.deep_equal(calls[1].argv, { 'rex', '--timeout', '2s', 'focus', '-s', 'test-session', 'right' }))
vim.cmd 'only'

local bindings, actions, events, focus, process = {}, {}, {}, nil, { foreground = { name = 'zsh' } }
_G.rex = {
  bind = function(key, action) bindings[key] = action end,
  mode = function() end,
  action = function(action) actions[action.name] = action.run end,
  call = function(method, args)
    assert(method == 'block.event')
    events[#events + 1] = vim.deepcopy(args.event)
    return {}
  end,
  block = { call = function() return process end },
  session = { focus_direction = function(args) focus = args; return {} end },
}
dofile(root .. '/apps/general/rex/init.lua')
local function navigate_action(key) return actions.nvim_navigate({ session_id = 'test-session', block_id = 'test-block' }, { key = key }) end
for key, direction in pairs { h = 'left', j = 'down', k = 'up', l = 'right' } do
  assert(bindings['ctrl+' .. key] == 'nvim_navigate', 'Renux needs a named action, not client.key.forward')
  process, focus = { foreground = { name = 'zsh' } }, nil
  navigate_action(key)
  assert(focus.direction == direction and focus.wrap == false)
  for _, name in ipairs { 'nvim', 'tmux' } do
    for _, p in ipairs { { foreground = { name = name } }, { foreground = { name = 'bash' }, ancestors = { { name = name } } } } do
      process, events, focus = p, {}, nil
      navigate_action(key)
      assert(not focus and #events == 2)
      assert(events[1].payload.key == 'key_' .. key and events[1].payload.mods == 'ctrl')
      assert(events[1].payload.action == 'press' and events[2].payload.action == 'release')
    end
  end
  assert(bindings['ctrl+a>' .. key] == 'pane.focus', 'prefix fallback must remain')
end
process, events = nil, {}
navigate_action('h')
assert(#events == 2, 'inspection failure must forward the application key')
_G.rex = nil

local specs = dofile(root .. '/apps/general/nvim/config/lua/plugins/navigation.lua')
local navigate
for _, spec in ipairs(specs) do
  if spec[1] == 'christoomey/vim-tmux-navigator' then navigate = spec.keys[4][2] end
end
local tmux = false
vim.api.nvim_create_user_command('TmuxNavigateRight', function() tmux = true end, {})
vim.env.TMUX = 'nested'
navigate()
assert(tmux, 'nested tmux must keep precedence over Rex')
vim.env.TMUX, vim.env.REX_SESSION, vim.env.HERDR_PANE_ID = nil, nil, 'herdr-pane'
navigate()
assert(calls[#calls].argv[1] == 'herdr', 'herdr navigation must remain available')
print('PASS: Rex/Neovim navigation, embedded terminals, tmux/herdr precedence and prefix fallback')

local status, foreground = { app = 'pi', state = 'idle', owner = { pid = 42, name = 'node' } }, { pid = 42, name = 'node', cwd = '/project' }
local written, pasted, focused = nil, true, false
_G.rex = {
  args = {}, block_id = 'editor',
  block = { call = function(_, method, args)
    if method == 'process' then return { foreground = foreground } end
    if method == 'program_status' then return { records = { status } } end
    if method == 'modes' then return { modes = { { number = 2004, set = pasted } } } end
    if method == 'write' then written = args.data; return {} end
  end },
  session = {
    list_blocks = function() return { blocks = { { block_id = 'agent', window_id = 'tab', creator_name = 'com.superlogical.terminal' } } } end,
    focus_block = function() focused = true; return {} end,
  },
}
local function pi_script() return dofile(root .. '/apps/general/nvim/config/lua/config/rex_pi.lua') end
assert(#pi_script().agents == 1)
status.app = 'cargo'
assert(#pi_script().agents == 0, 'non-Pi status must not identify an agent')
status.app, status.owner.pid = 'pi', 43
assert(#pi_script().agents == 0, 'stale status must not identify an agent')
status.owner.pid = 42
rex.args = { block = 'agent', pid = 42, name = 'node', text = 'file.lua:2\nselected code' }
assert(pi_script().sent and focused)
assert(written == '\27[200~file.lua:2\nselected code\27[201~', 'paste must not press Enter')
written, foreground.pid = nil, 43
assert(not pcall(pi_script) and written == nil, 'a replaced process must not receive context')
foreground.pid, pasted = 42, false
assert(not pcall(pi_script), 'do not send multiline input without bracketed paste')
pasted, status.state = true, 'blocked'
assert(not pcall(pi_script), 'permission/question prompts must not receive context')
status.state, rex.args.text = 'idle', 'bad\27[201~'
assert(not pcall(pi_script), 'reject terminal-control injection')
_G.rex = nil

vim.env.REX_SESSION, vim.env.REX_BLOCK = 'test-session', 'editor'
vim.api.nvim_buf_set_name(0, '/tmp/rex context.lua')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'first', 'second\27[201~', 'third' })
local notifications, payload = {}, nil
local old_notify, old_select = vim.notify, vim.ui.select
vim.notify = function(message) notifications[#notifications + 1] = message end
vim.system = function(argv, opts, callback)
  assert(opts.stdin:sub(1, 1) == '{', 'Rex requires an object, not an empty JSON array')
  local args = vim.json.decode(opts.stdin)
  if args.block then payload = args end
  local reply = args.block and { sent = true } or {
    agents = { { block = 'agent', window = 'tab', pid = 42, name = 'node' }, { block = 'other', window = 'other-tab' } },
    blocks = { { block_id = 'editor', window_id = 'tab' } },
  }
  callback({ code = 0, stdout = vim.json.encode(reply), stderr = '' })
  return {}
end
bridge.send(2, 3, 'Explain this')
assert(vim.wait(1000, function() return payload ~= nil end))
assert(payload.block == 'agent', 'prefer the sole Pi in this tab')
assert(payload.text:find('/tmp/rex context.lua:2-3', 1, true))
assert(payload.text:find('second[201~\nthird', 1, true) and not payload.text:find('\27', 1, true))
assert(payload.text:find('[unsaved buffer]', 1, true) and payload.text:find('Explain this', 1, true))
payload = nil
bridge.send(1, 1, '', true)
assert(vim.wait(1000, function() return payload ~= nil end))
assert(payload.text == '/tmp/rex context.lua:1', 'reference mode must not include code')
vim.system, vim.notify, vim.ui.select = system, old_notify, old_select
print('PASS: Pi identity, stale-process checks, safe paste, range snapshots and reference delivery')

local edit = require 'config.rex_edit'
local state_home = vim.env.XDG_STATE_HOME
local temporary_state = vim.fn.tempname()
vim.env.XDG_STATE_HOME, vim.env.TMUX = temporary_state, 'nested'
edit.setup()
assert(vim.fn.isdirectory(temporary_state) == 0, 'nested tmux must not overwrite a Rex-block editor registration')
vim.env.XDG_STATE_HOME, vim.env.TMUX = state_home, nil
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local file = directory .. "/file 'quoted' | name.lua"
local other = directory .. '/other.lua'
vim.fn.writefile({ 'one', 'two', 'three' }, file)
vim.fn.writefile({ 'other' }, other)
local unsaved = vim.api.nvim_get_current_buf()
local before = vim.api.nvim_buf_get_lines(unsaved, 0, -1, false)
vim.o.hidden = true
edit.open(file, 99)
assert(vim.api.nvim_buf_get_name(0) == file and vim.fn.line('.') == 3)
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(unsaved, 0, -1, false), before), 'handoff must retain unsaved code')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'not on disk' })
edit.open(file, 1)
assert(vim.api.nvim_get_current_line() == 'not on disk', 'opening the same file must not reload it')
local dirty = vim.api.nvim_get_current_buf()
vim.o.hidden = false
edit.open(other, 1)
assert(vim.fn.win_findbuf(dirty)[1], 'nohidden must keep the dirty buffer visible')
vim.o.hidden = true
vim.bo.buftype = 'nofile'
vim.wo.winfixbuf = true
local sidebar = vim.api.nvim_get_current_win()
edit.open(file, 1)
assert(vim.api.nvim_get_current_win() ~= sidebar and vim.wo[sidebar].winfixbuf, 'fixed panels must not be replaced')
local float_buffer = vim.api.nvim_create_buf(false, true)
local float = vim.api.nvim_open_win(float_buffer, true, { relative = 'editor', row = 1, col = 1, width = 20, height = 3 })
edit.open(file, 1)
assert(vim.api.nvim_get_current_win() ~= float and vim.api.nvim_win_is_valid(float), 'floating panels must not be replaced')
vim.api.nvim_win_close(float, true)
vim.g.lazygit_opened = 1
edit.open(other, 1)
vim.defer_fn(function() vim.g.lazygit_opened = 0 end, 10)
assert(vim.wait(1000, function() return vim.api.nvim_buf_get_name(0) == other end), 'wait for lazygit exit before handing off')
vim.fn.delete(directory, 'rf')
print('PASS: quoted filenames, line clamping, unsaved buffers, fixed/floating panels and lazygit exit delay')
