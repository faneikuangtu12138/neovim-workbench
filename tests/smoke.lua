-- Run with this repository installed as the active Neovim configuration:
-- NVIM_APPNAME=neovim-workbench nvim --headless -i NONE -S tests/smoke.lua
-- Uses only temporary demo files; does not change terminal settings or tools.
local passed = {}
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
local original_input = vim.ui.input
local function check(name, callback)
  callback()
  passed[#passed + 1] = name
end

local ok, error = xpcall(function()
  check("configuration and commands", function()
    assert(vim.g.mapleader == " ", "Workbench configuration is not active")
    for _, command in ipairs({
      "DevTools",
      "LspRefresh",
      "Format",
      "TSInstallWorkbench",
      "TermToggle",
      "BuildResults",
      "UiLineHeight",
    }) do
      assert(vim.fn.exists(":" .. command) == 2, "Missing command: " .. command)
    end
  end)

  check("all installed plugins match lock revisions", function()
    local path = vim.fn.stdpath("config") .. "/nvim-pack-lock.json"
    local lock = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
    local count = 0
    for _, plugin in ipairs(vim.pack.get(nil, { info = false })) do
      if plugin.active then
        local expected = lock.plugins[plugin.spec.name]
        assert(
          expected and expected.rev == plugin.rev,
          "Plugin revision differs from lock: " .. plugin.spec.name
        )
        count = count + 1
      end
    end
    assert(count > 0 and count == vim.tbl_count(lock.plugins), "Not all locked plugins are active")
  end)

  check("manual geometry height does not require terminal integration", function()
    local options = require("core.settings").get().terminal_ui
    local enabled, state = options.enabled, options.state
    local shapes = require("config.shapes")
    local previous = shapes.height
    options.enabled, options.state = false, temporary .. "/geometry.json"
    local success, failure = pcall(function()
      vim.cmd("UiLineHeight 1.48")
      local cache = vim.json.decode(table.concat(vim.fn.readfile(options.state), "\n"))
      assert(
        shapes.height == 1.48 and cache.height == 1.48,
        "Geometry height or cache was not synchronized"
      )
    end)
    options.enabled, options.state = enabled, state
    shapes.set_height(previous)
    assert(success, failure)
  end)

  local files = {
    { "demo.c", "c", 4, true },
    { "demo.cpp", "cpp", 4, true },
    { "demo.py", "python", 4, true },
    { "demo.v", "verilog", 4, true },
    { "demo.sv", "systemverilog", 4, true },
    { "demo.pl", "perl", 4, true },
    { "demo.tcl", "tcl", 2, true },
    { "demo.sdc", "tcl", 2, true },
    { "demo.lua", "lua", 2, true },
    { "demo.mk", "make", 8, false },
  }
  for _, file in ipairs(files) do
    check(file[1] .. " filetype and real Tab input", function()
      vim.cmd.edit(vim.fn.fnameescape(temporary .. "/" .. file[1]))
      assert(vim.bo.filetype == file[2], "Unexpected filetype: " .. vim.bo.filetype)
      assert(
        vim.bo.tabstop == file[3] and vim.fn.shiftwidth() == file[3],
        file[1]
          .. ": unexpected tabstop="
          .. vim.bo.tabstop
          .. ", effective shiftwidth="
          .. vim.fn.shiftwidth()
      )
      assert(vim.bo.expandtab == file[4], "Unexpected expandtab")
      local keys = vim.api.nvim_replace_termcodes("i<Tab><Esc>", true, false, true)
      vim.api.nvim_feedkeys(keys, "xt", false)
      local expected = file[4] and string.rep(" ", file[3]) or "\t"
      assert(
        vim.api.nvim_get_current_line() == expected,
        "Tab did not insert the expected indentation"
      )
      vim.bo.modified = false
    end)
  end

  check("RTL snippet expansion", function()
    vim.cmd.edit(vim.fn.fnameescape(temporary .. "/snippet.sv"))
    local path = vim.fn.stdpath("config") .. "/snippets/systemverilog.json"
    local snippets = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
    vim.snippet.expand(table.concat(snippets["Sequential logic"].body, "\n"))
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    assert(lines[2]:match("^    if"), "Snippet's first level is not four spaces")
    assert(lines[3]:match("^        "), "Snippet's nested level is not eight spaces")
    vim.snippet.stop()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "xt", false)
    vim.bo.modified = false
  end)

  check("saved new file and repeated tree/editor focus", function()
    local path = temporary .. "/saved.sv"
    vim.cmd.edit(vim.fn.fnameescape(path))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "module saved;", "endmodule" })
    vim.cmd.write()
    local editor = vim.api.nvim_get_current_win()
    local cwd = vim.fn.getcwd()
    vim.ui.input = function()
      error("Tree requested interactive input when focusing an ordinary file")
    end
    local navigation = require("core.navigation")
    for _ = 1, 2 do
      navigation.toggle_tree_focus()
      assert(
        vim.wait(2000, function()
          return vim.bo.filetype == "neo-tree"
        end, 20),
        "Tree did not receive focus"
      )
      navigation.toggle_tree_focus()
      assert(vim.api.nvim_get_current_win() == editor, "Did not return to the saved file's editor")
      assert(vim.fn.getcwd() == cwd, "Tree changed global cwd")
    end
  end)
end, debug.traceback)

vim.ui.input = original_input
-- Neovim created this unique directory; only remove that known temporary tree.
if temporary ~= "" and vim.fn.isdirectory(temporary) == 1 then
  vim.fn.delete(temporary, "rf")
end
if not ok then
  io.stderr:write("FAIL: " .. tostring(error) .. "\n")
  vim.cmd("cquit 1")
else
  io.stdout:write(vim.json.encode({ ok = true, checks = #passed, passed = passed }) .. "\n")
  vim.cmd("qa!")
end
