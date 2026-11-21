-- Runs in Rex's Lua 5.1 VM, not in Neovim.
local terminal = 'com.superlogical.terminal'
local function pi(block)
  local process = rex.block.call(terminal, 'process', { block_id = block })
  local foreground = process and process.foreground
  if not foreground then return end
  local status = rex.block.call(terminal, 'program_status', { block_id = block })
  for _, record in ipairs(status and status.records or {}) do
    local owner = record.owner
    if (record.effective_app or record.app) == 'pi' and owner
      and owner.pid == foreground.pid and owner.name == foreground.name then
      return { block = block, pid = foreground.pid, name = foreground.name,
        cwd = foreground.cwd or '', label = record.msg or 'Pi', state = record.state }
    end
  end
end

if rex.args.block then
  local target = pi(rex.args.block)
  if not target or target.pid ~= rex.args.pid or target.name ~= rex.args.name then
    error('Pi is no longer running in that pane', 0)
  end
  if target.state == 'blocked' then error('Finish Pi\'s open question or permission prompt first', 0) end
  local modes, err = rex.block.call(terminal, 'modes', { block_id = target.block })
  if not modes then error(err, 0) end
  local paste = false
  for _, mode in ipairs(modes.modes or {}) do
    if mode.number == 2004 and mode.set then paste = true end
  end
  if not paste then error('Pi is not accepting bracketed paste; nothing was sent', 0) end
  local text = assert(rex.args.text, 'Missing context')
  if text:find('[%z\1-\8\11-\31\127]') then error('Context contains terminal control characters', 0) end
  local _, write_err = rex.block.call(terminal, 'write', { block_id = target.block, data = '\27[200~' .. text .. '\27[201~' })
  if write_err then error(write_err, 0) end
  local _, focus_err = rex.session.focus_block{ block_id = target.block }
  return { sent = true, focus_error = focus_err }
end

local blocks, err = rex.session.list_blocks{}
if not blocks then error(err, 0) end
local agents = {}
for _, block in ipairs(blocks.blocks) do
  if block.block_id ~= rex.block_id and block.window_id and block.creator_name == terminal then
    local target = pi(block.block_id)
    if target then
      target.window = block.window_id
      agents[#agents + 1] = target
    end
  end
end
return { agents = agents, blocks = blocks.blocks }
