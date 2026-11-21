local M = {}
local directions = { h = 'left', j = 'down', k = 'up', l = 'right' }
local scripts = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h')

local function notify(message, level)
  vim.notify('Rex: ' .. message, level or vim.log.levels.ERROR)
end

function M.navigate(key)
  local win = vim.api.nvim_get_current_win()
  vim.cmd('wincmd ' .. key)
  if vim.api.nvim_get_current_win() ~= win then
    return
  end
  vim.system({ 'rex', '--timeout', '2s', 'focus', '-s', vim.env.REX_SESSION, directions[key] }, { text = true, timeout = 2500 }, function(result)
    if result.code ~= 0 then
      vim.schedule(function() notify(vim.trim(result.stderr)) end)
    end
  end)
end

local function pi(args, callback)
  local argv = { 'rex', '--timeout', '2s', 'do', '-s', vim.env.REX_SESSION, '-b', vim.env.REX_BLOCK, scripts .. '/rex_pi.lua', '--json', '--args', '-' }
  vim.system(argv, { text = true, stdin = vim.json.encode(args), timeout = 3000 }, vim.schedule_wrap(function(result)
    if result.code ~= 0 then
      return notify(vim.trim(result.stderr))
    end
    local ok, data = pcall(vim.json.decode, result.stdout)
    if not ok then return notify('Invalid response from rex') end
    callback(data)
  end))
end

function M.send(first, last, question, reference)
  local file = vim.api.nvim_buf_get_name(0)
  if file == '' or vim.bo.buftype ~= '' or file:find('[%c]') then
    return notify('Open a named file buffer first')
  end
  local lines = vim.api.nvim_buf_get_lines(0, first - 1, last, false)
  local modified = vim.bo.modified
  local location = file .. ':' .. first .. (last ~= first and ('-' .. last) or '')
  local function send(comment)
    if comment == nil then return end
    local text = location
    if not reference then
      text = text .. (modified and ' [unsaved buffer]' or '') .. '\n```\n' .. table.concat(lines, '\n') .. '\n```'
    end
    if comment ~= '' then text = text .. '\n\n' .. comment end
    -- Bracketed-paste terminators and other terminal controls are never source text to execute.
    text = text:gsub('[%z\1-\8\11-\31\127]', '')
    pi(vim.empty_dict(), function(data)
      local window
      for _, block in ipairs(data.blocks) do
        if block.block_id == vim.env.REX_BLOCK then window = block.window_id end
      end
      local agents, same_tab = data.agents, {}
      for _, agent in ipairs(agents) do
        if agent.window == window then same_tab[#same_tab + 1] = agent end
      end
      local function deliver(agent)
        if not agent then return end
        pi({ block = agent.block, pid = agent.pid, name = agent.name, text = text }, function(result)
          if result.focus_error then notify('Context pasted, but focus failed: ' .. result.focus_error)
          else notify('Context pasted into Pi; press Enter there to submit', vim.log.levels.INFO) end
        end)
      end
      if #same_tab == 1 then return deliver(same_tab[1]) end
      if #agents == 1 then return deliver(agents[1]) end
      if #agents == 0 then return notify('No live Pi found in this Rex session') end
      vim.ui.select(agents, {
        prompt = 'Send context to Pi',
        format_item = function(agent) return agent.label .. ' · ' .. agent.cwd .. ' · ' .. agent.block end,
      }, deliver)
    end)
  end
  if question == nil then vim.ui.input({ prompt = 'Ask Pi: ' }, send) else send(question) end
end

function M.setup()
  require('config.rex_edit').setup()
  if not vim.env.REX_SESSION or not vim.env.REX_BLOCK then
    return
  end
  if not vim.env.TMUX then
    for key in pairs(directions) do
      vim.keymap.set('t', '<C-' .. key .. '>', '<C-\\><C-n><Cmd>lua require("config.rex").navigate("' .. key .. '")<CR>', { desc = 'Navigate Neovim/Rex ' .. directions[key] })
    end
  end
  vim.api.nvim_create_user_command('RexSend', function(opts) M.send(opts.line1, opts.line2, opts.args) end, { range = true, nargs = '*' })
  vim.api.nvim_create_user_command('RexAsk', function(opts) M.send(opts.line1, opts.line2) end, { range = true })
  vim.api.nvim_create_user_command('RexRef', function(opts) M.send(opts.line1, opts.line2, '', true) end, { range = true })
  for key, command in pairs { s = 'RexSend', c = 'RexAsk', r = 'RexRef' } do
    vim.keymap.set({ 'n', 'x' }, '<leader>a' .. key, ':' .. command .. '<CR>', { desc = command .. ' to Pi' })
  end
end

return M
