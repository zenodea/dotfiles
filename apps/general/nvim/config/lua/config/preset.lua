local presets = {
  all = { 'plugins', 'plugins.extras' },
  minimal = { 'plugins.mini', 'plugins.treesitter', 'plugins.navigation', 'plugins.git', 'plugins.ui', 'plugins.image' },
}

local root = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.stdpath 'config'), ':h:h:h:h')
local ok, lines = pcall(vim.fn.readfile, root .. '/.nvim-preset', '', 1)
local name = ok and vim.trim(lines[1] or '') or ''

if name == '' then
  name = 'all'
elseif not presets[name] then
  local known = vim.tbl_keys(presets)
  table.sort(known)
  vim.notify(('Unknown nvim preset "%s", loading all. Known: %s'):format(name, table.concat(known, ', ')), vim.log.levels.WARN)
  name = 'all'
end

return {
  name = name,
  spec = vim.tbl_map(function(mod)
    return { import = mod }
  end, presets[name]),
  lockfile = name ~= 'all' and vim.fn.stdpath 'config' .. '/lazy-lock.' .. name .. '.json' or nil,
}
