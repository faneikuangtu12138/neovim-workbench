-- Run without user config/plugins: nvim --clean --headless -l tests/portability.lua
local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(source, ":p")))
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary .. "/config", "p")
local passed = 0
local function check(condition, message)
  assert(condition, message)
  passed = passed + 1
end
local function same(actual, expected, message)
  check(vim.deep_equal(actual, expected), message .. ": " .. vim.inspect(actual))
end
local original_stdpath, original_has = vim.fn.stdpath, vim.fn.has
vim.fn.stdpath = function(kind)
  if kind == "config" then
    return temporary .. "/config"
  end
  return original_stdpath(kind)
end
local messages = {}
vim.notify = function(message)
  messages[#messages + 1] = message
end

-- Exercise the actual language bootstrap prefix under both PATH conventions.
local language_source = table.concat(vim.fn.readfile(root .. "/lua/config/languages.lua"), "\n")
local bootstrap = language_source:match("^(.-)vim%.filetype%.add")
local original_path = vim.env.PATH
for _, windows in ipairs({ false, true }) do
  vim.env.PATH = windows and [[C:\Windows;C:\Tools]] or "/usr/bin:/bin"
  local inherited = vim.env.PATH
  vim.fn.has = function(feature)
    return feature == "win32" and (windows and 1 or 0) or original_has(feature)
  end
  assert(loadstring(bootstrap))()
  local separator = windows and ";" or ":"
  check(vim.env.PATH:sub(-#inherited) == inherited, "inherited PATH lost")
  check(
    vim.env.PATH:find("/mason/bin" .. separator, 1, true) ~= nil,
    "platform PATH separator wrong"
  )
end
vim.fn.has, vim.env.PATH = original_has, original_path

-- Capture argv from the real terminal module; no external builds are run.
package.loaded["core.navigation"] = {
  project_root = function()
    return temporary
  end,
  editor_window = function()
    return vim.api.nvim_get_current_win()
  end,
  return_editor = function() end,
}
local original_system, original_input = vim.system, vim.ui.input
local shell_cases = {
  { "/bin/sh", "-c", { "/bin/sh", "-c", "echo test" } },
  { "/bin/bash -l", "-c", { "/bin/bash", "-l", "-c", "echo test" } },
  { "cmd.exe", "/s /c", { "cmd.exe", "/s", "/c", "echo test" } },
  {
    "pwsh",
    "-NoLogo -NoProfile -Command",
    { "pwsh", "-NoLogo", "-NoProfile", "-Command", "echo test" },
  },
  {
    [["C:\Program Files\PowerShell\7\pwsh.exe" -NoLogo]],
    "-Command",
    { [[C:\Program Files\PowerShell\7\pwsh.exe]], "-NoLogo", "-Command", "echo test" },
  },
  {
    [["/tmp/shell with spaces" --login]],
    [["-c"]],
    { "/tmp/shell with spaces", "--login", "-c", "echo test" },
  },
}
for _, case in ipairs(shell_cases) do
  vim.o.shell, vim.o.shellcmdflag = case[1], case[2]
  local captured, captured_cwd
  vim.system = function(argv, opts)
    captured, captured_cwd = argv, opts.cwd
    return {}
  end
  vim.ui.input = function(_, callback)
    callback("echo test")
  end
  package.loaded["config.terminal"] = nil
  require("config.terminal").build()
  same(captured, case[3], "shell argv")
  check(captured_cwd == temporary, "build cwd changed")
end
vim.system, vim.ui.input = original_system, original_input

local telescope_options
package.loaded.telescope = {
  setup = function(options)
    telescope_options = options
  end,
}
require("config.telescope")
for index, directory in ipairs({ ".git", "node_modules", ".venv", "__pycache__" }) do
  local pattern = telescope_options.defaults.file_ignore_patterns[index]
  check(("project/" .. directory .. "/file"):find(pattern) ~= nil, "Unix ignore failed")
  check(("project\\" .. directory .. "\\file"):find(pattern) ~= nil, "Windows ignore failed")
  check(("project/" .. directory .. "-keep/file"):find(pattern) == nil, "ignore overmatches")
end

local settings = require("core.settings")
check(settings.setup().round_tabs == false, "public default must use standard glyphs")
check(require("config.shapes").height == 1.42, "default geometry height changed")
local cache = temporary .. "/custom-state/workbench-ui.json"
vim.fn.writefile({
  "return { round_tabs=true, line_height=1.55, terminal_ui={state=" .. vim.inspect(cache) .. "} }",
}, temporary .. "/config/local.lua")
settings.setup()
package.loaded["config.shapes"] = nil
local shapes = require("config.shapes")
check(vim.g.workbench_round_tabs == true and shapes.height == 1.55, "local geometry opt-in failed")
vim.fn.mkdir(vim.fs.dirname(cache), "p")
vim.fn.writefile({ vim.json.encode({ height = 1.48, keep = 7 }) }, cache)
package.loaded["config.shapes"] = nil
shapes = require("config.shapes")
check(shapes.height == 1.48, "custom cache must override configured default")

local prior_wsl, prior_interop, prior_wt =
  vim.env.WSL_DISTRO_NAME, vim.env.WSL_INTEROP, vim.env.WT_SESSION
vim.env.WSL_DISTRO_NAME, vim.env.WSL_INTEROP, vim.env.WT_SESSION = nil, nil, nil
local refreshed, spawned = 0, 0
package.loaded["config.frame"] = {
  refresh = function()
    refreshed = refreshed + 1
  end,
}
vim.system = function()
  spawned = spawned + 1
  return {}
end
local appearance = require("config.appearance")
appearance.setup({ state = cache })
vim.cmd("UiLineHeight 1.60")
check(
  shapes.height == 1.60 and refreshed == 1 and spawned == 0,
  "manual geometry update invoked backend or missed refresh"
)
local stored = vim.json.decode(table.concat(vim.fn.readfile(cache), "\n"))
check(stored.height == 1.60 and stored.keep == 7, "manual cache update lost data")
local prior_bytes = table.concat(vim.fn.readfile(cache), "\n")
vim.cmd("UiLineHeight")
check(
  table.concat(vim.fn.readfile(cache), "\n") == prior_bytes and spawned == 0,
  "manual query wrote cache"
)
vim.cmd("UiLineHeight 1.77")
check(shapes.height == 1.60 and spawned == 0, "invalid height changed geometry")
vim.api.nvim_del_user_command("UiLineHeight")
vim.env.WSL_DISTRO_NAME, vim.env.WT_SESSION = "test", "test"
appearance.setup({ enabled = false, state = cache })
vim.cmd("UiLineHeight 1.59")
check(
  shapes.height == 1.59 and spawned == 0,
  "disabled backend must still support local geometry sync"
)
vim.api.nvim_del_user_command("UiLineHeight")
local backend_argv
vim.system = function(argv)
  backend_argv = argv
  spawned = spawned + 1
  return {}
end
appearance.setup({ profile = "Demo", settings = temporary .. "/settings.json", state = cache })
vim.cmd("UiLineHeight")
check(spawned == 1 and backend_argv ~= nil, "WSL/WT backend did not start")
check(not vim.tbl_contains(backend_argv, "--guid"), "a host GUID leaked into defaults")
check(
  vim.tbl_contains(backend_argv, "Demo") and vim.tbl_contains(backend_argv, "--settings"),
  "profile/settings options were ignored"
)
vim.api.nvim_del_user_command("UiLineHeight")
vim.env.WSL_DISTRO_NAME, vim.env.WSL_INTEROP, vim.env.WT_SESSION =
  prior_wsl, prior_interop, prior_wt
vim.system = original_system

-- Inspect actual Conform options, with HOME rules behind an explicit empty XDG.
local formatter_options
package.loaded.conform = {
  setup = function(options)
    formatter_options = options
  end,
  list_formatters = function()
    return {}
  end,
}
require("config.formatting")
local prior_home, prior_xdg = vim.env.HOME, vim.env.XDG_CONFIG_HOME
vim.env.HOME, vim.env.XDG_CONFIG_HOME = temporary .. "/home", temporary .. "/xdg"
vim.fn.mkdir(temporary .. "/home/.config", "p")
vim.fn.mkdir(temporary .. "/xdg", "p")
vim.fn.writefile(
  { 'indent_type = "Spaces"', "indent_width = 5" },
  temporary .. "/home/.config/stylua.toml"
)
local args =
  formatter_options.formatters.stylua.prepend_args(nil, { buf = 0, dirname = temporary .. "/src" })
same(args, {}, "HOME StyLua rules lost behind XDG_CONFIG_HOME")
vim.env.HOME, vim.env.XDG_CONFIG_HOME = prior_home, prior_xdg

print(
  "Passed " .. passed .. " portability configuration checks (OS/shell argv branches are simulated)"
)
vim.cmd("qa!")
