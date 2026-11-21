local path = vim.fn.fnamemodify(arg[0], ':h') .. '/rex_edit.lua'
local ok, status = pcall(function() return dofile(path).cli(vim.list_slice(arg)) end)
if not ok then io.stderr:write('rex-edit: ' .. tostring(status) .. '\n') end
os.exit(ok and status or 1)
