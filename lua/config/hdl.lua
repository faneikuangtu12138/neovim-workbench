-- Keep Verilog-2001 editing independent from SystemVerilog conventions.
local M = {}

-- Verible parses both languages, but these rules prescribe SV replacements
-- for legal Verilog declarations, arrays, generate regions and system calls.
-- Command-line overrides are applied after the project's .rules.verible_lint.
M.verilog_disabled_rules = {
  "always-comb",
  "explicit-function-lifetime",
  "explicit-task-lifetime",
  "explicit-function-task-parameter-type",
  "explicit-parameter-storage-type",
  "unpacked-dimensions-range-ordering",
  "legacy-genvar-declaration",
  "legacy-generate-region",
  "v2001-generate-begin",
  "invalid-system-task-function",
}

function M.verilog_rules()
  return table.concat(
    vim.tbl_map(function(rule)
      return "-" .. rule
    end, M.verilog_disabled_rules),
    ","
  )
end

function M.filter_snippets(filetype, path)
  -- Upstream's Verilog collection includes SV-only int/void/typedef snippets.
  -- Keep our Verilog snippets, upstream SV snippets and every other language.
  return filetype ~= "verilog"
    or not path:gsub("\\", "/"):match("/friendly%-snippets/snippets/verilog%.json$")
end

function M.completion_buffers()
  local filetype = vim.bo.filetype
  local hdl = filetype == "verilog" or filetype == "systemverilog"
  local buffers = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if
      (hdl and vim.bo[buf].buftype == "" and vim.bo[buf].filetype == filetype)
      or (not hdl and vim.bo[buf].buftype ~= "nofile")
    then
      buffers[#buffers + 1] = buf
    end
  end
  return buffers
end

return M
