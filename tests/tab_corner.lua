-- Run with Workbench active: nvim --headless -i NONE -S tests/tab_corner.lua
-- Checks actual tabline text, native rail buffers and focus/resize transitions.
local api = vim.api
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
local passed = {}
local tabs, frame, shapes =
  require("config.tabs"), require("config.frame"), require("config.shapes")
local navigation = require("core.navigation")
local editor, first, second

local function check(name, first_visible_selected, tree_focus)
  if tree_focus then
    navigation.focus_tree()
  else
    api.nvim_set_current_win(editor)
  end
  assert(
    vim.wait(2000, function()
      return (vim.bo.filetype == "neo-tree") == tree_focus
    end, 20),
    "Focus did not move"
  )
  frame.refresh()
  local pane
  for _, item in ipairs(frame.panes()) do
    if item.win == editor then
      pane = item
    end
  end
  assert(pane and pane.row == 1, "Editor must begin directly below tabs")
  local model = tabs.model(editor)
  assert(model.first_selected == first_visible_selected, name .. ": unexpected visible tabs")
  local weight = tree_focus and "normal" or "active"
  local text =
    api.nvim_eval_statusline(tabs.header(editor), { winid = editor, maxwidth = model.width }).str
  if first_visible_selected then
    assert(
      text:sub(1, #shapes["edge_" .. weight .. "_top_left"])
        == shapes["edge_" .. weight .. "_top_left"],
      "Selected first tab lost the outer corner"
    )
  else
    assert(text:sub(1, 1) == " ", "Inactive first tab must leave space for the body's round corner")
    assert(
      text:sub(2, 1 + #shapes.edge_normal_top_left) == shapes.edge_normal_top_left,
      "Inactive first tab's side is not inset to meet the body roof"
    )
  end
  local expected =
    shapes["edge_" .. weight .. (first_visible_selected and "_left" or "_body_top_left")]
  local found
  for _, win in ipairs(api.nvim_list_wins()) do
    if frame.is_frame(win) then
      local position = api.nvim_win_get_position(win)
      if position[1] == 1 and position[2] == pane.left then
        local lines = api.nvim_buf_get_lines(api.nvim_win_get_buf(win), 0, 2, false)
        assert(lines[1] == expected, name .. ": wrong editor corner")
        assert(
          lines[2] == shapes["edge_" .. weight .. "_left"],
          "Rounded corner lost its vertical continuation"
        )
        found = true
      end
    end
  end
  assert(found, "No native left rail")
  assert(model.tabs[1].left == 2, "Tab text shifted while changing the corner")
  assert(vim.v.errmsg == "", vim.v.errmsg)
  passed[#passed + 1] = name
end

local ok, failure = xpcall(function()
  assert(vim.g.mapleader == " ", "Workbench configuration must be active")
  vim.o.columns, vim.o.lines = 160, 32
  vim.cmd.edit(vim.fn.fnameescape(temporary .. "/first.v"))
  first, editor = api.nvim_get_current_buf(), api.nvim_get_current_win()
  vim.cmd.badd(vim.fn.fnameescape(temporary .. "/second.v"))
  second = vim.fn.bufnr(temporary .. "/second.v")
  check("first selected / editor focus", true, false)
  check("first selected / tree focus", true, true)
  api.nvim_set_current_win(editor)
  api.nvim_set_current_buf(second)
  check("second selected / editor focus", false, false)
  check("second selected / tree focus", false, true)
  api.nvim_set_current_win(editor)
  vim.o.columns = 64
  frame.refresh()
  check("cropped tab viewport / only selected tab fits", true, false)
  vim.o.columns = 160
  frame.refresh()
  check("restored viewport / second selected", false, false)
  api.nvim_set_current_buf(first)
  check("switch back to first selected", true, false)
  local settings = require("core.settings").get()
  local original_geometry = settings.geometry_images
  settings.geometry_images = true
  vim.cmd.edit(vim.fn.fnameescape(temporary .. "/second_中文.sv"))
  local text = api.nvim_eval_statusline(tabs.header(editor), { winid = editor, maxwidth = 160 }).str
  assert(
    text:find("中文", 1, true),
    "Wide tab text must remain native and unmarked in image mode"
  )
  settings.geometry_images = original_geometry
  passed[#passed + 1] = "Chinese tab text remains native in image mode"
end, debug.traceback)

vim.fn.delete(temporary, "rf")
if not ok then
  io.stderr:write("FAIL: " .. tostring(failure) .. "\n")
  vim.cmd("cquit 1")
else
  io.stdout:write(vim.json.encode({ ok = true, checks = #passed, passed = passed }) .. "\n")
  vim.cmd("qa!")
end
