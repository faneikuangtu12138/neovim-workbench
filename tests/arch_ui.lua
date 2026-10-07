-- Real-terminal regressions. Run in a new Ghostty/Console window only.
-- WORKBENCH_UI_RESULT=/path/report.json nvim -i NONE -S tests/arch_ui.lua
local api = vim.api
local result = { checks = {}, responses = {} }
local temporary = vim.fn.tempname()
local destination = vim.env.WORKBENCH_UI_RESULT or (temporary .. "-result.json")
local send = api.nvim_ui_send
api.nvim_ui_send = function(sequence)
  -- Keep terminal error responses visible to this test.
  return send((sequence:gsub("q=2", "q=1")))
end
api.nvim_create_autocmd("TermResponse", {
  callback = function(ev)
    if ev.data.sequence:match("^\27_G") then
      result.responses[#result.responses + 1] = ev.data.sequence
    end
  end,
})
local function wait_for(predicate, label)
  assert(vim.wait(5000, predicate, 20), label)
end
local function check(name, action)
  action()
  result.checks[#result.checks + 1] = name
end
local thread
local function pause(ms)
  vim.defer_fn(function()
    local ok, failure = coroutine.resume(thread)
    assert(ok, failure)
  end, ms)
  coroutine.yield()
end
local function run()
  local ok, failure = xpcall(function()
    vim.fn.mkdir(temporary, "p")
    local lines = {}
    for i = 1, 60 do
      vim.list_extend(
        lines,
        { "wire value_" .. i .. " = 1'b0;", "// Source text with syntax colour", "" }
      )
    end
    vim.fn.writefile(lines, temporary .. "/first.v")
    vim.fn.writefile(lines, temporary .. "/second_中文.sv")
    vim.cmd.edit(vim.fn.fnameescape(temporary .. "/first.v"))
    vim.cmd.badd(vim.fn.fnameescape(temporary .. "/second_中文.sv"))
    local editor, first = api.nvim_get_current_win(), api.nvim_get_current_buf()
    local second = vim.fn.bufnr(temporary .. "/second_中文.sv")
    local navigation, frame = require("core.navigation"), require("config.frame")
    local chrome, image, map =
      require("config.geometry_image"), require("config.minimap_image"), require("config.minimap")
    local kitty = vim.env.TERM_PROGRAM == "ghostty"
    local function settle_chrome()
      frame.refresh()
      vim.cmd("redraw!")
      if kitty then
        wait_for(function()
          return chrome.status().visible and not chrome.status().pending
        end, vim.inspect(chrome.status()))
      end
    end
    check("first and second tab; tree/editor focus after save", function()
      navigation.focus_tree()
      wait_for(function()
        return vim.bo.filetype == "neo-tree"
      end, "tree focus")
      pause(180)
      assert(vim.bo.filetype == "neo-tree", "deferred update stole tree focus")
      navigation.return_editor()
      api.nvim_set_current_win(editor)
      vim.cmd.write()
      for _, buf in ipairs({ first, second, first, second }) do
        api.nvim_set_current_buf(buf)
        settle_chrome()
        navigation.focus_tree()
        settle_chrome()
        pause(180)
        assert(vim.bo.filetype == "neo-tree", "tab update stole tree focus")
        navigation.return_editor()
        settle_chrome()
      end
      api.nvim_set_current_buf(first)
      assert(require("config.tabs").model(editor).first_selected)
    end)
    if kitty then
      check("Chinese tab text stays native while its border uses wide strokes", function()
        api.nvim_set_current_buf(second)
        settle_chrome()
        local header = api.nvim_eval_statusline(require("config.tabs").header(editor), {
          winid = editor,
          maxwidth = vim.o.columns,
        }).str
        assert(header:find("中文", 1, true), "Chinese tab text contains font shaping marks")
        local found = 0
        for _, cell in ipairs(chrome.snapshot().cells) do
          if
            cell.row == 0 and (cell.text:find("中", 1, true) or cell.text:find("文", 1, true))
          then
            assert(cell.width == 2, "Chinese border width")
            assert(cell.text:find(require("config.shapes").edge_active_wide_roof_mark, 1, true))
            found = found + 1
          end
        end
        assert(found == 2, "Missing Chinese tab border strokes")
        api.nvim_set_current_buf(first)
        settle_chrome()
      end)
    end
    check("sidebar drags wider and narrower without stealing focus", function()
      settle_chrome()
      local boundary = assert(require("config.resize").boundary())
      local tree, original = boundary.tree.win, api.nvim_win_get_width(boundary.tree.win)
      local col, row = boundary.first, boundary.top + 4
      api.nvim_input_mouse("left", "press", "", 0, row, col)
      pause(100)
      api.nvim_input_mouse("left", "drag", "", 0, row, col + 5)
      pause(100)
      assert(api.nvim_win_get_width(tree) > original, "tree did not widen")
      api.nvim_input_mouse("left", "drag", "", 0, row, col - 5)
      pause(100)
      assert(api.nvim_win_get_width(tree) < original, "tree did not narrow")
      api.nvim_input_mouse("left", "release", "", 0, row, col)
      pause(100)
      api.nvim_win_set_width(tree, original)
      settle_chrome()
      assert(api.nvim_get_current_win() == editor, "drag stole focus")
    end)
    check("mouse tab switches, insert Escape and command-line Escape stay responsive", function()
      local function input(keys)
        api.nvim_input(keys)
        pause(90)
      end
      for iteration = 1, 12 do
        api.nvim_set_current_win(editor)
        input("i")
        assert(api.nvim_get_mode().mode:sub(1, 1) == "i", "insert input was lost")
        input("<Esc>")
        assert(api.nvim_get_mode().mode == "n", "Escape did not leave insert mode")
        local wanted = iteration % 2 == 0 and first or second
        settle_chrome()
        local pane
        for _, item in ipairs(frame.panes()) do
          if item.win == editor then
            pane = item
          end
        end
        local tab
        for _, item in ipairs(require("config.tabs").model(editor).tabs) do
          if item.id == wanted then
            tab = item
          end
        end
        assert(tab, "target tab is not visible")
        api.nvim_input_mouse("left", "press", "", 0, 0, pane.left + tab.left + 1)
        pause(90)
        api.nvim_input_mouse("left", "release", "", 0, 0, pane.left + tab.left + 1)
        pause(90)
        assert(api.nvim_get_current_buf() == wanted, "tab click selected wrong buffer")
        assert(api.nvim_get_current_win() == editor, "tab click focused decoration")
        input("<Esc>")
        assert(api.nvim_get_mode().mode == "n", "normal Escape changed mode")
        input(":")
        assert(api.nvim_get_mode().mode == "c", "colon did not open command line")
        assert(vim.fn.getcmdtype() == ":", "wrong command line")
        local cmdline = require("noice.ui.cmdline")
        assert(cmdline.win() and api.nvim_win_is_valid(cmdline.win()), "command popup is invisible")
        input("<Esc>")
        assert(api.nvim_get_mode().mode == "n", "Escape did not cancel command line")
        assert(api.nvim_get_current_win() == editor, "popup stole editor focus")
      end
      api.nvim_set_current_buf(first)
      settle_chrome()
    end)
    if kitty then
      check("Kitty backend uses measured physical pixels and real glyphs", function()
        map.open()
        wait_for(function()
          return image.status().painted > 0 and not image.status().pending
        end, vim.inspect(image.status()))
        local cw, ch = require("config.minimap_kitty").cell_size()
        local model = map.snapshot()
        assert(image.status().protocol == "kitty")
        assert(cw and model.cell_width == cw and model.cell_height == ch, "unmeasured pixel size")
        assert(#model.characters > 0, "missing source glyphs")
        result.pixel_size = { cw, ch }
        vim.wait(700)
      end)
      check("character, line, block selection; 30 updates reuse code ink", function()
        wait_for(function()
          return not image.status().pending
        end, "renderer busy")
        local requests = image.status().code_requests
        for _, pair in ipairs({ { "v", "char" }, { "V", "line" }, { "\22", "block" } }) do
          api.nvim_win_set_cursor(editor, { 2, 1 })
          vim.cmd("normal! " .. pair[1])
          api.nvim_win_set_cursor(editor, { 5, 6 })
          map.refresh()
          assert(map.snapshot().selection.kind == pair[2], pair[2] .. " selection")
          vim.cmd("normal! \27")
        end
        for i = 1, 30 do
          api.nvim_win_set_cursor(editor, { 2 + i % 4, 1 })
          vim.cmd("normal! V")
          api.nvim_win_set_cursor(editor, { 7, 6 })
          map.refresh()
          vim.wait(15)
          vim.cmd("normal! \27")
        end
        assert(image.status().code_requests == requests, "selection rerasterized source")
        result.selection_status = image.status()
      end)
      check("floating dialog hides images and dismissing it restores them", function()
        local buf = api.nvim_create_buf(false, true)
        local col = vim.o.columns - 20
        local floating = api.nvim_open_win(
          buf,
          false,
          { relative = "editor", row = 0, col = col, width = 18, height = 10, style = "minimal" }
        )
        api.nvim_buf_set_lines(buf, 0, -1, false, { "Dialog over border and minimap" })
        map.refresh()
        vim.cmd("redraw!")
        wait_for(function()
          return image.status().painted == 0 and not chrome.status().pending
        end, "float overlap")
        for _, cell in ipairs(chrome.snapshot().cells) do
          assert(
            not (cell.row < 10 and cell.col >= col and cell.col < col + 18),
            "chrome painted over dialog"
          )
        end
        api.nvim_win_close(floating, true)
        map.refresh()
        settle_chrome()
        wait_for(function()
          return image.status().painted > 0
        end, "minimap not restored")
      end)
      check("close/reopen and narrow/restore release and recreate graphics", function()
        map.close()
        assert(image.status().painted == 0 and not image.status().worker)
        map.open()
        wait_for(function()
          return image.status().painted > 0 and not image.status().pending
        end, "reopen")
        local columns = vim.o.columns
        vim.o.columns = 55
        map.refresh()
        assert(not map.window(), "narrow map did not detach")
        vim.o.columns = columns
        map.refresh()
        wait_for(function()
          return map.window() and image.status().painted > 0 and not image.status().pending
        end, "restore width")
        map.close()
        settle_chrome()
      end)
      result.chrome = chrome.status()
    else
      check("unsupported terminal closes panel and reports capability accurately", function()
        map.open()
        wait_for(function()
          return not map.is_enabled()
        end, "empty unsupported panel remained")
        assert(not image.status().supported and not map.window())
        result.minimap = image.status()
      end)
    end
    vim.wait(250)
    for _, sequence in ipairs(result.responses) do
      assert(not sequence:match(";[A-Z][A-Z_]+:"), "terminal rejected image: " .. sequence)
    end
    assert(not chrome.status().error, chrome.status().error)
  end, debug.traceback)
  result.ok, result.error, result.terminal = ok, failure, vim.env.TERM_PROGRAM
  vim.fn.writefile({ vim.json.encode(result) }, destination)
  vim.fn.delete(temporary, "rf")
  vim.cmd("qa!")
end
thread = coroutine.create(run)
vim.defer_fn(function()
  local ok, failure = coroutine.resume(thread)
  assert(ok, failure)
end, 500)
