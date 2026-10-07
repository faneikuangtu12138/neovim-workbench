-- nvim --clean --headless -l tests/terminal_settings.lua
local path = debug.getinfo(1, "S").source:sub(2)
local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(path, ":p")))
package.path = root .. "/lua/?.lua;" .. package.path
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
local stdpath, uname, program = vim.fn.stdpath, vim.uv.os_uname, vim.env.TERM_PROGRAM
vim.fn.stdpath = function(kind)
  return kind == "config" and temporary or stdpath(kind)
end
local cases = {
  { "Linux", "ghostty", false, nil, false },
  { "Linux", "ghostty", true, nil, true },
  { "Linux", "kgx", true, nil, false },
  { "Linux", "Windows_Terminal", true, nil, false },
  { "Darwin", "ghostty", true, nil, false },
  { "Linux", "ghostty", true, false, false },
  { "Linux", "kgx", true, true, true },
}
local ok, failure = xpcall(function()
  for _, case in ipairs(cases) do
    vim.uv.os_uname = function()
      return { sysname = case[1] }
    end
    vim.env.TERM_PROGRAM = case[2]
    local options = { round_tabs = case[3], line_height = 1.42 }
    options.geometry_images = case[4]
    vim.fn.writefile(
      vim.split("return " .. vim.inspect(options), "\n", { plain = true }),
      temporary .. "/local.lua"
    )
    local values = require("core.settings").setup()
    assert(values.geometry_images == case[5], vim.inspect(case))
    assert(values.line_height == 1.42 and values.round_tabs == case[3])
  end
end, debug.traceback)
vim.fn.stdpath, vim.uv.os_uname, vim.env.TERM_PROGRAM = stdpath, uname, program
vim.fn.delete(temporary, "rf")
assert(ok, failure)
print("Passed 7 terminal adaptation cases; identical preferences, automatic renderer")
vim.cmd("qa!")
