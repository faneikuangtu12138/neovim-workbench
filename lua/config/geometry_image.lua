-- Render the existing geometry via Kitty when terminal COLR rendering fails.
-- Neovim still owns layout, text, focus, hit testing and all window navigation.
local M = {}
local api, transport = vim.api, require("config.minimap_kitty")
local root = vim.fn.stdpath("config")
local worker, flight, queued, latest, last_model, visible
local serial, output, pending = 0, "", false
local frames, scan_ms, warned = 0, 0, false
local image_id = 2200000000 + vim.fn.getpid()
local glyphs = {}
for _, name in ipairs({ "shape_bank", "pane_bank", "edge_bank" }) do
  for _, bank in pairs(require("config." .. name)) do
    for _, cp in pairs(bank) do
      glyphs[cp] = true
    end
  end
end
local function command(value)
  return "\27_G" .. value .. "\27\\"
end
local function hide()
  if visible then
    api.nvim_ui_send(command("a=d,d=I,i=" .. image_id .. ",q=2"))
    visible = false
  end
end
local function dispatch(request)
  flight = request
  vim.fn.chansend(worker, vim.json.encode(request) .. "\n")
end
local function renderer_error(message)
  M.error = message
  if not warned and vim.v.exiting == vim.NIL then
    warned = true
    vim.schedule(function()
      vim.notify("Workbench chrome renderer: " .. message, vim.log.levels.WARN)
    end)
  end
end
local function start()
  if worker then
    return true
  end
  output = ""
  local job
  job = vim.fn.jobstart({ "python3", root .. "/scripts/geometry-render.py" }, {
    on_stdout = function(_, data)
      if worker ~= job then
        return
      end
      output = output .. data[1]
      for i = 2, #data do
        local ok, response = pcall(vim.json.decode, output)
        if ok and flight and response.id == flight.id then
          local request = flight
          flight = nil
          if response.error then
            renderer_error(response.error)
          elseif latest == response.id and vim.v.exiting == vim.NIL then
            local model = request.model
            local sequence = transport.upload(
              image_id,
              response.png,
              100,
              model.columns * model.cell_width,
              model.rows * model.cell_height
            )
            sequence = sequence
              .. "\27[1;1H"
              .. command(
                string.format(
                  "a=p,i=%d,p=1,c=%d,r=%d,C=1,z=5,q=2",
                  image_id,
                  model.columns,
                  model.rows
                )
              )
            api.nvim_ui_send("\27[?2026h\27" .. "7" .. sequence .. "\27" .. "8\27[?2026l")
            visible = true
            frames = frames + 1
          end
          if queued then
            local next_request = queued
            queued = nil
            dispatch(next_request)
          end
        end
        output = data[i]
      end
    end,
    on_stderr = function(_, data)
      if worker == job then
        M.error = ((M.error or "") .. table.concat(data, "\n")):sub(-2000)
      end
    end,
    on_exit = function(_, code)
      if worker ~= job then
        return
      end
      worker, flight, queued = nil, nil, nil
      if code ~= 0 then
        renderer_error(M.error or ("worker exited with code " .. code))
      end
    end,
  })
  if job <= 0 then
    renderer_error("Cannot start Python chrome renderer")
    return false
  end
  worker = job
  return true
end

function M.refresh()
  pending = false
  local started = vim.uv.hrtime()
  if vim.v.exiting ~= vim.NIL then
    return
  end
  local cw, ch = transport.cell_size()
  if not cw or not ch then
    return
  end
  local model =
    { cell_width = cw, cell_height = ch, columns = vim.o.columns, rows = vim.o.lines, cells = {} }
  local occlusions = {}
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    local config = api.nvim_win_get_config(win)
    if config.relative ~= "" and not config.hide and not require("config.frame").is_frame(win) then
      local position = api.nvim_win_get_position(win)
      local border = config.border and #config.border > 0 and 1 or 0
      occlusions[#occlusions + 1] = {
        row = position[1] - border,
        col = position[2] - border,
        height = api.nvim_win_get_height(win) + border * 2,
        width = api.nvim_win_get_width(win) + border * 2,
      }
    end
  end
  local function covered(row, col, width)
    for _, rect in ipairs(occlusions) do
      if
        row >= rect.row
        and row < rect.row + rect.height
        and col < rect.col + rect.width
        and col + width > rect.col
      then
        return true
      end
    end
    return false
  end
  local candidates = {}
  local function add(row, col)
    if row >= 0 and row < vim.o.lines and col >= 0 and col < vim.o.columns then
      candidates[row * vim.o.columns + col] = { row, col }
    end
  end
  for col = 0, vim.o.columns - 1 do
    add(0, col)
  end
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    local ft = vim.bo[api.nvim_win_get_buf(win)].filetype
    if ft == "workbench-frame" or require("config.footer").is_window(win) then
      local p = api.nvim_win_get_position(win)
      for row = p[1], p[1] + api.nvim_win_get_height(win) - 1 do
        for col = p[2], p[2] + api.nvim_win_get_width(win) - 1 do
          add(row, col)
        end
      end
    end
  end
  for _, pane in ipairs(require("config.frame").panes()) do
    for col = pane.left, pane.right do
      add(pane.row - 1, col)
      add(pane.row + pane.height, col)
    end
  end
  local shapes = require("config.shapes")
  local marks = {}
  for _, name in ipairs({ "normal_roof_mark", "active_roof_mark", "normal_mark", "active_mark" }) do
    local wide = name:gsub("roof_mark", "wide_roof_mark")
    if wide == name then
      wide = name:gsub("_mark", "_wide_mark")
    end
    marks[#marks + 1] = { shapes["edge_" .. name], shapes["edge_" .. wide] }
  end
  local function wide_strokes(row, col, width, attrs)
    -- Every label has marked padding beside its text. Borrow that label's
    -- roof/bottom weight while leaving its wide characters unmarked on screen.
    for distance = 1, 24 do
      for _, neighbor in ipairs({ col - distance, col + width - 1 + distance }) do
        if neighbor >= 0 and neighbor < vim.o.columns then
          local cell = api.nvim__inspect_cell(1, row, neighbor)
          if (cell[2] or {}).background == attrs.background then
            local found = {}
            for _, pair in ipairs(marks) do
              if pair[1] and cell[1]:find(pair[1], 1, true) then
                found[#found + 1] = pair[2]
              end
            end
            if #found > 0 then
              return table.concat(found)
            end
          end
        end
      end
    end
    return ""
  end
  for _, key in ipairs(vim.tbl_keys(candidates)) do
    local p = candidates[key]
    local value = api.nvim__inspect_cell(1, p[1], p[2])
    local text, attrs = value[1], value[2] or {}
    local width = math.max(1, vim.fn.strdisplaywidth(text or ""))
    local custom = false
    for _, cp in ipairs(vim.fn.str2list(text or "", true)) do
      custom = custom or glyphs[cp]
    end
    if p[1] == 0 and width == 2 and not custom then
      local strokes = wide_strokes(p[1], p[2], width, attrs)
      text, custom = text .. strokes, strokes ~= ""
    end
    if custom and not covered(p[1], p[2], width) then
      model.cells[#model.cells + 1] = {
        row = p[1],
        col = p[2],
        text = text,
        width = width,
        fg = attrs.foreground or 0xcad3f5,
        bg = attrs.background or 0x24273a,
        bold = attrs.bold == true,
        italic = attrs.italic == true,
      }
    end
  end
  table.sort(model.cells, function(a, b)
    return a.row == b.row and a.col < b.col or a.row < b.row
  end)
  scan_ms = (vim.uv.hrtime() - started) / 1000000
  if vim.deep_equal(last_model, model) then
    return
  end
  last_model = model
  serial = serial + 1
  latest = serial
  -- Remove stale geometry immediately when a dialog obscures or layout moves.
  hide()
  if #model.cells == 0 then
    queued = nil
    return
  end
  if not start() then
    return
  end
  local request = { id = serial, model = model }
  if flight then
    queued = request
  else
    dispatch(request)
  end
end

function M.snapshot()
  return vim.deepcopy(last_model)
end

function M.status()
  return {
    serial = serial,
    visible = visible == true,
    frames = frames,
    scan_ms = scan_ms,
    pending = pending or flight ~= nil or queued ~= nil,
    worker = worker,
    error = M.error,
    cells = last_model and #last_model.cells,
    enabled = require("core.settings").get().geometry_images,
  }
end
function M.setup()
  if not require("core.settings").get().geometry_images or vim.g.workbench_round_tabs == false then
    return
  end
  local attached = false
  local function attach()
    if attached then
      return
    end
    local tty = false
    for _, ui in ipairs(api.nvim_list_uis()) do
      tty = tty or ui.stdout_tty
    end
    if not tty then
      return
    end
    attached = true
    -- Initializes hlstate; redraw before inspecting so existing cells use it.
    api.nvim__inspect_cell(1, 0, 0)
    vim.cmd("redraw!")
    local ns = api.nvim_create_namespace("WorkbenchGeometryImage")
    api.nvim_set_decoration_provider(ns, {
      on_end = function()
        if not pending then
          pending = true
          vim.defer_fn(M.refresh, 20)
        end
      end,
    })
    vim.defer_fn(M.refresh, 50)
    api.nvim_create_autocmd("VimSuspend", {
      callback = function()
        latest = nil
        hide()
      end,
    })
    api.nvim_create_autocmd("VimResume", {
      callback = function()
        last_model = nil
        vim.defer_fn(M.refresh, 100)
      end,
    })
    api.nvim_create_autocmd("VimLeavePre", {
      once = true,
      callback = function()
        hide()
        if worker then
          vim.fn.jobstop(worker)
        end
      end,
    })
  end
  api.nvim_create_autocmd("UIEnter", {
    once = true,
    callback = function()
      vim.defer_fn(attach, 100)
    end,
  })
  vim.defer_fn(attach, 250)
end
return M
