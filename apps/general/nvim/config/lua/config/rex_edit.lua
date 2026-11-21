local M = {}
local uv = vim.uv or vim.loop

local function registration(block)
  local scope = (vim.env.REX_SERVER or '') .. '\n' .. (vim.env.REX_SESSION or '') .. '\n' .. block
  return vim.fn.stdpath('state') .. '/rex-edit/' .. vim.fn.sha256(scope) .. '.json'
end

local function read(path)
  local ok, data = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(path), '\n')) end)
  return ok and type(data) == 'table' and data or nil
end

function M.setup()
  -- shortcut: one editor per Rex block; add tmux-pane routing if nested-editor reuse is needed.
  if not vim.env.REX_SESSION or not vim.env.REX_BLOCK or vim.env.NVIM or vim.env.TMUX or vim.v.servername == '' then return end
  local path = registration(vim.env.REX_BLOCK)
  local directory = vim.fn.fnamemodify(path, ':h')
  vim.fn.mkdir(directory, 'p', 448)
  assert(uv.fs_chmod(directory, 448)) -- user-private socket registry
  local socket = vim.v.servername
  local temporary = path .. '.' .. vim.fn.getpid()
  vim.fn.writefile({ vim.json.encode({ socket = socket }) }, temporary)
  assert(uv.fs_rename(temporary, path))
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = vim.api.nvim_create_augroup('rex-editor-registration', { clear = true }),
    callback = function()
      local current = read(path)
      if current and current.socket == socket then vim.fn.delete(path) end
    end,
  })
end

function M.info()
  local file = vim.bo.buftype == '' and vim.api.nvim_buf_get_name(0) or ''
  local cwd = vim.fn.getcwd()
  return { root = vim.fn.resolve(vim.fs.root(file ~= '' and file or cwd, '.git') or cwd), block = vim.env.REX_BLOCK }
end

function M.open(file, line)
  local function usable(win)
    return vim.api.nvim_win_get_config(win).relative == '' and not vim.wo[win].winfixbuf
      and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == ''
  end
  local tries = 0
  local function open()
    -- lazygit.nvim restores its old window on exit; do not let it undo this handoff.
    if vim.g.lazygit_opened == 1 and tries < 50 then
      tries = tries + 1
      return vim.defer_fn(open, 20)
    end
    if not usable(vim.api.nvim_get_current_win()) then
      local target
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if usable(win) then target = win; break end
      end
      if target then vim.api.nvim_set_current_win(target) else vim.cmd 'topleft vsplit' end
    end
    local buffer = vim.fn.bufadd(file)
    if vim.api.nvim_get_current_buf() ~= buffer then
      if vim.bo.modified and not vim.o.hidden then vim.cmd 'split' end
      vim.api.nvim_win_set_buf(0, buffer)
    end
    if line and line > 0 then
      vim.api.nvim_win_set_cursor(0, { math.min(line, vim.api.nvim_buf_line_count(0)), 0 })
      vim.cmd 'normal! zz'
    end
  end
  open()
  return true
end

local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 2500 }):wait()
  if result.code ~= 0 then return nil, vim.trim(result.stderr ~= '' and result.stderr or 'command timed out') end
  return result.stdout
end

local function remote(socket, code, args)
  local expr = 'json_encode(luaeval(' .. vim.fn.string('(function() ' .. code .. ' end)()') .. ', json_decode(' .. vim.fn.string(vim.json.encode(args or {})) .. ')))'
  local text, err = run({ vim.v.progpath, '--server', socket, '--remote-expr', expr })
  if not text then return nil, err end
  local ok, data = pcall(vim.json.decode, text)
  if not ok then return nil, 'Invalid response from Neovim' end
  return data
end

function M.cli(args)
  local line = 0
  if args[1] and args[1]:match('^%+%d+$') then line = tonumber(table.remove(args, 1):sub(2)) end
  local literal = args[1] == '--'
  if literal then table.remove(args, 1) end
  if #args ~= 1 or (not literal and args[1]:sub(1, 1) == '-') then
    io.stderr:write('Usage: rex-edit [+LINE] [--] FILE\n')
    return 1
  end
  local file = vim.fn.fnamemodify(args[1], ':p')
  local root = vim.fn.resolve(vim.fs.root(file, '.git') or vim.fs.root(vim.fn.getcwd(), '.git') or vim.fn.getcwd())
  local text, err = run({ 'rex', '--timeout', '2s', 'block', 'ls', '-s', vim.env.REX_SESSION, '--json' })
  if not text then io.stderr:write('rex-edit: ' .. err .. '\n'); return 1 end
  local blocks = vim.json.decode(text).blocks
  local editors, window = {}, nil
  for _, block in ipairs(blocks) do
    if block.block_id == vim.env.REX_BLOCK then window = block.window_id end
    local record = read(registration(block.block_id))
    if block.window_id and record and type(record.socket) == 'string' and record.socket:sub(1, 1) == '/' then
      local connected, channel = pcall(vim.fn.sockconnect, 'pipe', record.socket, { rpc = true })
      if connected and channel > 0 then
        vim.fn.chanclose(channel)
        local info, rpc_err = remote(record.socket, 'return require("config.rex_edit").info()')
        if not info then io.stderr:write('rex-edit: ' .. rpc_err .. '\n'); return 1 end
        if info.block == block.block_id and info.root == root then
          editors[#editors + 1] = { block = block.block_id, window = block.window_id, socket = record.socket }
        end
      end
    end
  end
  if #editors == 0 then return 2 end -- the shell wrapper starts a normal, blocking Neovim
  local same_tab = {}
  for _, editor in ipairs(editors) do
    if editor.window == window then same_tab[#same_tab + 1] = editor end
  end
  if #same_tab > 0 then editors = same_tab end
  local editor = editors[1]
  if #editors > 1 then
    for index, candidate in ipairs(editors) do io.write(index .. ': ' .. candidate.block .. '\n') end
    io.write('Editor number (Enter cancels): ')
    io.flush()
    editor = editors[tonumber(io.read('*l')) or 0]
    if not editor then return 1 end
  end
  local opened, open_err = remote(editor.socket, 'local file, line = unpack(_A); return require("config.rex_edit").open(file, line)', { file, line })
  if not opened then io.stderr:write('rex-edit: ' .. (open_err or 'Could not open file') .. '\n'); return 1 end
  local focused, focus_err = run({ 'rex', '--timeout', '2s', 'do', '-s', vim.env.REX_SESSION, '-b', vim.env.REX_BLOCK, '-e', [[
    local view, err = rex.session.view{}
    if not view then error(err, 0) end
    for _, window in ipairs(view.windows) do
      for _, layer in ipairs(window.layers) do
        if layer.kind == 'floating' then
          local source, target = false, false
          for _, block in ipairs(layer.blocks) do
            source = source or block.block_id == rex.block_id
            target = target or block.block_id == rex.args.block
          end
          if source and not target then
            local _, hide_err = rex.session.set_layer_state{ layer_id = layer.layer_id, state = 'minimized' }
            if hide_err then error(hide_err, 0) end
          end
        end
      end
    end
    local result, focus_err = rex.session.focus_block{ block_id = rex.args.block }
    if not result then error(focus_err, 0) end
    return result
  ]], '--args', vim.json.encode({ block = editor.block }), '--json' })
  if not focused then io.stderr:write('rex-edit: file opened, but focus failed: ' .. focus_err .. '\n'); return 1 end
  return 0
end

return M
