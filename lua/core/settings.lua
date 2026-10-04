local M = {}
local defaults = {
  round_tabs = false,
  terminal_ui = {
    enabled = true,
    profile = "Fedora",
    python = "python3",
  },
}

local function warn(message)
  vim.schedule(function()
    vim.notify(message, vim.log.levels.WARN, { title = "Workbench settings" })
  end)
end

function M.setup()
  local options = {}
  local path = vim.fs.joinpath(vim.fn.stdpath("config"), "local.lua")
  if vim.fn.filereadable(path) == 1 then
    local ok, result = pcall(dofile, path)
    if ok and type(result) == "table" then
      options = result
    else
      warn("local.lua must return a table: " .. tostring(result))
    end
  end
  M.values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), options)
  if type(M.values.round_tabs) ~= "boolean" then
    warn("round_tabs must be true or false; using the standard Nerd Font UI.")
    M.values.round_tabs = false
  end
  local height = tonumber(M.values.line_height)
  if M.values.line_height ~= nil then
    if
      not height
      or height < 1.42
      or height > 1.65
      or math.abs(height * 100 - math.floor(height * 100 + 0.5)) > 0.000001
    then
      warn("line_height must be 1.42–1.65 in steps of 0.01; using the cached/default height.")
      height = nil
    end
  end
  if type(M.values.terminal_ui) ~= "table" then
    warn("terminal_ui must be a table; using the default integration settings.")
    M.values.terminal_ui = vim.deepcopy(defaults.terminal_ui)
  end
  for _, key in ipairs({ "profile", "python", "guid", "settings", "state", "backup_dir" }) do
    local value = M.values.terminal_ui[key]
    if value ~= nil and (type(value) ~= "string" or value == "") then
      warn("terminal_ui." .. key .. " must be a non-empty string; using its default.")
      M.values.terminal_ui[key] = defaults.terminal_ui[key]
    end
  end
  if type(M.values.terminal_ui.enabled) ~= "boolean" then
    warn("terminal_ui.enabled must be true or false; using true.")
    M.values.terminal_ui.enabled = true
  end
  M.values.line_height = height
  vim.g.workbench_round_tabs = M.values.round_tabs
  vim.g.workbench_line_height = height
  vim.g.workbench_ui_state = type(M.values.terminal_ui.state) == "string"
      and vim.fn.expand(M.values.terminal_ui.state)
    or nil
  return M.values
end

function M.get()
  return M.values or M.setup()
end

return M
