-- Run with Workbench active: nvim --headless -i NONE -S tests/minimap.lua
local api = vim.api
local minimap, frame, navigation =
  require("config.minimap"), require("config.frame"), require("core.navigation")
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
local passed = {}
local function check(name, action)
  action()
  passed[#passed + 1] = name
end
local function settle()
  vim.wait(150, function()
    return false
  end, 10)
  frame.refresh()
  minimap.refresh()
end
local function assert_owner(win, buf, cursor)
  assert(api.nvim_get_current_win() == win, "Minimap changed keyboard focus")
  assert(api.nvim_get_current_buf() == buf, "Minimap changed source buffer")
  assert(vim.deep_equal(api.nvim_win_get_cursor(win), cursor), "Minimap moved source cursor")
end
local function pane_for(win)
  for _, pane in ipairs(frame.panes()) do
    if pane.win == win then
      return pane
    end
  end
end

local ok, failure = xpcall(function()
  vim.o.columns, vim.o.lines = 160, 36
  require("mini.starter").open()
  settle()
  local editor = api.nvim_get_current_win()
  check("default off; welcome/tree toggle waits for editable content", function()
    assert(not minimap.is_enabled() and not minimap.window())
    navigation.focus_tree()
    vim.cmd.MinimapOpen()
    settle()
    assert(vim.bo.filetype == "neo-tree" and minimap.is_enabled() and not minimap.window())
    navigation.return_editor()
  end)
  vim.cmd.edit(vim.fn.fnameescape(temporary .. "/first.v"))
  editor = api.nvim_get_current_win()
  local source = {}
  for i = 1, 300 do
    source[i] = i % 5 == 0 and "" or ("    assign signal_" .. i .. " = input_data;")
  end
  api.nvim_buf_set_lines(0, 0, -1, false, source)
  vim.cmd.write()
  api.nvim_win_set_cursor(editor, { 150, 4 })
  local buf, cursor = api.nvim_get_current_buf(), api.nvim_win_get_cursor(editor)
  settle()
  check("reserved width; one continuous editor outline and header", function()
    local win = assert(minimap.window(), "No minimap")
    assert(vim.w[win].workbench_role == "minimap" and frame.is_frame(win))
    assert(api.nvim_win_get_width(win) == minimap.config.width)
    assert(api.nvim_win_get_config(win).relative == "", "Map must reserve native layout space")
    local anchor, width = minimap.span(editor)
    assert(anchor == win and width == api.nvim_win_get_width(editor) + minimap.config.width + 1)
    local pane = assert(pane_for(editor))
    assert(pane.width == width and pane.right == pane.col + width + 1)
    assert(require("config.tabs").model(editor).width == width + 3)
    assert(api.nvim_win_get_position(win)[1] == pane.row)
    assert(api.nvim_win_get_height(win) == api.nvim_win_get_height(editor))
    assert_owner(editor, buf, cursor)
  end)
  check("scroll position, diagnostics and edits refresh the map", function()
    local target = api.nvim_win_get_buf(minimap.window())
    local lines = api.nvim_buf_get_lines(target, 0, -1, false)
    assert(table.concat(lines):find("[^ ]"), "Only blank map content")
    local diag_ns = api.nvim_create_namespace("WorkbenchMinimapRegressionDiagnostics")
    vim.diagnostic.set(diag_ns, buf, {
      { lnum = 120, col = 0, severity = vim.diagnostic.severity.WARN, message = "test warning" },
      { lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = "outside slice" },
    })
    minimap.refresh()
    local namespaces = api.nvim_get_namespaces()
    local marks = api.nvim_buf_get_extmarks(
      target,
      namespaces.WorkbenchMinimapContent,
      0,
      -1,
      { details = true }
    )
    assert(
      #marks == 1 and marks[1][4].virt_text[1][2] == "DiagnosticWarn",
      "A diagnostic outside the code slice was clamped onto its edge"
    )
    api.nvim_feedkeys(api.nvim_replace_termcodes("<Space>ud", true, false, true), "xt", false)
    assert(not vim.diagnostic.is_enabled({ bufnr = buf }))
    marks = api.nvim_buf_get_extmarks(target, namespaces.WorkbenchMinimapContent, 0, -1, {})
    assert(#marks == 0, "Disabling diagnostics left a stale minimap warning")
    api.nvim_feedkeys(api.nvim_replace_termcodes("<Space>ud", true, false, true), "xt", false)
    assert(vim.diagnostic.is_enabled({ bufnr = buf }))
    marks = api.nvim_buf_get_extmarks(target, namespaces.WorkbenchMinimapContent, 0, -1, {})
    assert(#marks == 1, "Re-enabling diagnostics did not restore the minimap marker")
    vim.diagnostic.enable(false, { bufnr = buf, ns_id = diag_ns })
    minimap.refresh()
    marks = api.nvim_buf_get_extmarks(target, namespaces.WorkbenchMinimapContent, 0, -1, {})
    assert(#marks == 0, "Minimap includes diagnostics from a disabled namespace")
    vim.diagnostic.enable(true, { bufnr = buf, ns_id = diag_ns })
    local before = api.nvim_buf_get_lines(target, 0, -1, false)
    api.nvim_buf_set_lines(buf, 0, -1, false, { "module short;", "endmodule" })
    settle()
    assert(not vim.deep_equal(before, api.nvim_buf_get_lines(target, 0, -1, false)))
    assert(api.nvim_get_current_buf() == buf and vim.bo[buf].modified, "Map swallowed an edit")
    vim.cmd.write()
    vim.diagnostic.reset(diag_ns, buf)
  end)
  check(
    "long code preview scrolls at fixed density and refreshes syntax after theme changes",
    function()
      local lines = {}
      for index = 1, 400 do
        lines[index] = index <= 200 and "wire a;" or "        assign b = 1'b1;"
      end
      api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      api.nvim_win_set_cursor(editor, { 1, 0 })
      vim.cmd("normal! zz")
      settle()
      local target = api.nvim_win_get_buf(minimap.window())
      local top = api.nvim_buf_get_lines(target, 0, -1, false)
      api.nvim_win_set_cursor(editor, { 400, 0 })
      vim.cmd("normal! zz")
      settle()
      local bottom = api.nvim_buf_get_lines(target, 0, -1, false)
      assert(
        #top == #bottom and not vim.deep_equal(top, bottom),
        "Long preview was squeezed to fit"
      )
      vim.cmd.colorscheme("catppuccin")
      settle()
      local marks = api.nvim_buf_get_extmarks(
        target,
        api.nvim_get_namespaces().WorkbenchMinimapSyntax,
        0,
        -1,
        { details = true }
      )
      local colors = {}
      for _, mark in ipairs(marks) do
        local name = mark[4].hl_group
        local hl = api.nvim_get_hl(0, { name = name, link = false })
        if hl.fg then
          colors[hl.fg] = true
        end
      end
      assert(vim.tbl_count(colors) >= 2, "Theme reload erased minimap syntax colours")
      assert_owner(editor, buf, { 400, 0 })
      api.nvim_buf_set_lines(buf, 0, -1, false, { "module short;", "endmodule" })
      vim.cmd.write()
      settle()
    end
  )
  check("tree and Ctrl-w navigation skip minimap after save", function()
    navigation.focus_tree()
    settle()
    assert(vim.bo.filetype == "neo-tree" and minimap.window())
    frame.move("l")
    assert(api.nvim_get_current_win() == editor)
    frame.move("l")
    assert(api.nvim_get_current_win() == editor, "Right focus entered minimap")
    api.nvim_feedkeys(api.nvim_replace_termcodes("<C-w>w", true, false, true), "xt", false)
    assert(vim.bo.filetype == "neo-tree")
    api.nvim_feedkeys(api.nvim_replace_termcodes("<C-w>w", true, false, true), "xt", false)
    assert(api.nvim_get_current_win() == editor)
  end)
  check("toggle shortcut and commands restore the original editor width", function()
    local mapping = vim.fn.maparg("<Space>uv", "n", false, true)
    assert(mapping.rhs == "<cmd>MinimapToggle<CR>")
    local old = minimap.window()
    local width = select(2, minimap.span(editor))
    vim.cmd.MinimapToggle()
    settle()
    assert(not minimap.is_enabled() and not minimap.window() and not api.nvim_win_is_valid(old))
    assert(api.nvim_win_get_width(editor) == width, "Map width was not reclaimed")
    vim.cmd.MinimapOpen()
    vim.cmd.MinimapOpen()
    settle()
    local number = 0
    for _, win in ipairs(api.nvim_list_wins()) do
      if vim.w[win].workbench_role == "minimap" then
        number = number + 1
      end
    end
    assert(number == 1, "Opening twice created duplicate maps")
  end)
  check("narrow editor hides map and larger editor restores it", function()
    local current, current_buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
    local current_cursor = api.nvim_win_get_cursor(current)
    vim.o.columns = 60
    settle()
    assert(minimap.is_enabled() and not minimap.window())
    vim.o.columns = 160
    settle()
    assert(minimap.window())
    assert_owner(current, current_buf, current_cursor)
  end)
  check("minimap follows file tabs and the focused editor split", function()
    vim.cmd.edit(vim.fn.fnameescape(temporary .. "/second.sv"))
    api.nvim_buf_set_lines(0, 0, -1, false, { "module second;", "    logic ready;", "endmodule" })
    vim.cmd.write()
    settle()
    local target = api.nvim_win_get_buf(minimap.window())
    assert(#api.nvim_buf_get_lines(target, 0, -1, false) <= 2)
    navigation.toggle_tree_visibility()
    vim.cmd.vsplit()
    local other = api.nvim_get_current_win()
    settle()
    assert(minimap.span(other) == minimap.window())
    assert(minimap.span(editor) == editor)
    assert(api.nvim_get_current_win() == other)
    vim.cmd.close()
    settle()
    assert(minimap.span(editor) == minimap.window(), "Closing source left orphaned map")
  end)
  check("large buffers retain a proportional scrollbar without encoding", function()
    local limit = minimap.config.max_lines
    minimap.config.max_lines = 2
    api.nvim_buf_set_lines(0, 0, -1, false, source)
    settle()
    local target = api.nvim_win_get_buf(minimap.window())
    assert(not table.concat(api.nvim_buf_get_lines(target, 0, -1, false)):find("[^ ]"))
    api.nvim_win_set_cursor(0, { 150, 0 })
    minimap.refresh()
    local marks = api.nvim_buf_get_extmarks(
      target,
      api.nvim_get_namespaces().WorkbenchMinimapView,
      0,
      -1,
      { details = true }
    )
    local found
    for _, mark in ipairs(marks) do
      if mark[4].priority == 20 then
        assert(mark[2] > 0 and mark[2] < api.nvim_win_get_height(minimap.window()) - 1)
        found = true
      end
    end
    assert(found, "No middle-of-file cursor marker")
    minimap.config.max_lines = limit
    vim.bo.modified = false
  end)
  check("tab pages isolate visibility and clean up closed maps", function()
    local old_tab, old_map = api.nvim_get_current_tabpage(), minimap.window()
    vim.cmd.tabnew()
    settle()
    assert(not minimap.is_enabled() and not minimap.window())
    vim.cmd.MinimapOpen()
    settle()
    assert(minimap.window())
    local closed = minimap.window()
    vim.cmd.tabclose()
    settle()
    assert(not api.nvim_win_is_valid(closed))
    assert(api.nvim_get_current_tabpage() == old_tab and minimap.window() == old_map)
    vim.cmd.MinimapClose()
    settle()
    assert(not minimap.window())
  end)
  assert(vim.v.errmsg == "", vim.v.errmsg)
end, debug.traceback)

vim.fn.delete(temporary, "rf")
if not ok then
  io.stderr:write("FAIL: " .. tostring(failure) .. "\n")
  vim.cmd("cquit 1")
else
  io.stdout:write(vim.json.encode({ ok = true, checks = #passed, passed = passed }) .. "\n")
  vim.cmd("qa!")
end
