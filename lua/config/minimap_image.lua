-- Sixel transport. Rendering is asynchronous; stale frames never reach the TTY.
local M = {}
local api = vim.api
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))))
local records, serial, worker, flight, queued = {}, 0, nil, nil, nil
local output, stderr, warned, repaint_pending = "", "", false, false
local options = {}
local capable
local frames_sent = 0
local unsupported_warned = false
local requests_sent, shadow_ms = 0, 0

local function tty()
  for _, ui in ipairs(api.nvim_list_uis()) do
    if ui.stdout_tty then
      return true
    end
  end
  return false
end

local function attributes(sequence)
  if type(sequence) ~= "string" or not sequence:match("^\27%[%?[%d;]+c$") then
    return
  end
  capable = false
  for value in sequence:gmatch("%d+") do
    capable = capable or value == "4"
  end
end

local function python()
  if options.python then
    return options.python
  end
  local base = vim.fn.stdpath("data") .. "/workbench-minimap-env"
  local executable = base .. (vim.fn.has("win32") == 1 and "/Scripts/python.exe" or "/bin/python")
  return vim.fn.executable(executable) == 1 and executable or "python3"
end

function M.status()
  local painted = 0
  for _, record in pairs(records) do
    painted = painted + (record.painted and 1 or 0)
  end
  return {
    supported = capable == true and tty(),
    worker = worker,
    error = stderr,
    painted = painted,
    frames_sent = frames_sent,
    pending = flight ~= nil or queued ~= nil,
    code_requests = requests_sent,
    shadow_ms = shadow_ms,
  }
end

local function geometry(win)
  local position = vim.fn.screenpos(win, 1, 1)
  if position.row == 0 or position.col == 0 then
    return
  end
  return {
    x = position.col - 1,
    y = position.row - 1,
    width = api.nvim_win_get_width(win),
    height = api.nvim_win_get_height(win),
  }
end

local function obscured(rect)
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    local config = api.nvim_win_get_config(win)
    if config.relative ~= "" and not config.hide then
      local position = api.nvim_win_get_position(win)
      local border = config.border and #config.border > 0 and 1 or 0
      local x, y = position[2] - border, position[1] - border
      local width = api.nvim_win_get_width(win) + border * 2
      local height = api.nvim_win_get_height(win) + border * 2
      if
        x < rect.x + rect.width
        and x + width > rect.x
        and y < rect.y + rect.height
        and y + height > rect.y
      then
        return true
      end
    end
  end
  return false
end

local function draw(rect, color, sixel)
  -- Save/restore cursor, attributes and DECSDM. Position is body-only; rounded
  -- tabs, rails and footer remain outside the image rectangle.
  local erase = {
    "\27[?2026s\27[?2026h\27[?80s\27[?80l\27" .. "7",
    string.format(
      "\27[48;2;%d;%d;%dm",
      math.floor(color / 65536),
      math.floor(color / 256) % 256,
      color % 256
    ),
  }
  -- Only this blank native rectangle is erased, keeping the exact theme base
  -- colour behind transparent Sixel pixels and removing old selection shadows.
  for row = rect.y, rect.y + rect.height - 1 do
    erase[#erase + 1] = string.format("\27[%d;%dH\27[%dX", row + 1, rect.x + 1, rect.width)
  end
  erase[#erase + 1] = string.format("\27[%d;%dH", rect.y + 1, rect.x + 1)
    .. (sixel or "")
    .. "\27"
    .. "8\27[?80r\27[?2026r"
  api.nvim_ui_send(table.concat(erase))
end

local function erase(record)
  if not record or not record.painted then
    return
  end
  record.painted = false
  if capable ~= true or not tty() then
    return
  end
  if not api.nvim_win_is_valid(record.win) then
    -- The native window has already closed: redraw the new layout instead of
    -- erasing stale coordinates that could now contain another editor.
    vim.cmd("redraw!")
    return
  end
  if api.nvim_win_get_tabpage(record.win) == api.nvim_get_current_tabpage() then
    local rect = geometry(record.win)
    if rect then
      draw(rect, record.model.background)
    end
  end
end

local function send(record, dirty)
  local started = vim.uv.hrtime()
  local win = record.win
  if
    not api.nvim_win_is_valid(win)
    or api.nvim_win_get_tabpage(win) ~= api.nvim_get_current_tabpage()
    or records[win] ~= record
    or capable ~= true
    or not tty()
  then
    return
  end
  local rect = geometry(win)
  if not rect or rect.width ~= record.rect.width or rect.height ~= record.rect.height then
    return
  end
  if obscured(rect) then
    if record.painted then
      record.painted = false
      -- Let Neovim redraw both the blank panel and the overlapping float.
      vim.cmd("redraw!")
    end
    return
  end
  local model = record.model
  local shadows = require("config.minimap_shadows")
  local rectangles = shadows.rectangles(model, record.rendered or model, model.char_width)
  local moved = not vim.deep_equal(record.painted_rect, rect)
  local sequence = {
    "\27[?2026s\27[?2026h\27[?80s\27[?80l\27" .. "7",
    string.format(
      "\27[48;2;%d;%d;%dm",
      math.floor(model.background / 65536),
      math.floor(model.background / 256) % 256,
      model.background % 256
    ),
  }
  local count = 0
  record.hashes = record.hashes or {}
  for row = 1, rect.height do
    local key, shade = shadows.tile(rectangles, row, model)
    key = key .. ":" .. (record.ink_version or 0) .. ":" .. model.background
    if
      moved
      or not record.painted
      or record.hashes[row] ~= key
      or dirty == true
      or (dirty and dirty[row])
    then
      local position = string.format("\27[%d;%dH", rect.y + row, rect.x + 1)
      sequence[#sequence + 1] = position .. string.format("\27[%dX", rect.width) .. shade
      if record.tiles and record.tiles[row] then
        sequence[#sequence + 1] = position .. record.tiles[row]
      end
      record.hashes[row] = key
      count = count + 1
    end
  end
  shadow_ms = (vim.uv.hrtime() - started) / 1000000
  if count == 0 then
    return
  end
  sequence[#sequence + 1] = "\27" .. "8\27[?80r\27[?2026r"
  api.nvim_ui_send(table.concat(sequence))
  frames_sent = frames_sent + 1
  record.painted = true
  record.painted_rect = rect
end

local function dispatch(request)
  flight = request
  requests_sent = requests_sent + 1
  vim.fn.chansend(worker, vim.json.encode({ id = request.id, model = request.model }) .. "\n")
end

local function response(line)
  local ok, result = pcall(vim.json.decode, line)
  if not ok or not flight or result.id ~= flight.id then
    return
  end
  local request = flight
  flight = nil
  local record = records[request.win]
  if record and record.request_id == request.id then
    if result.error then
      stderr = result.error
    else
      record.tiles, record.rendered = result.tiles, request.model
      record.ink_version = (record.ink_version or 0) + 1
      send(record)
    end
  end
  if queued and worker then
    local next_request = queued
    queued = nil
    local next_record = records[next_request.win]
    if next_record and next_record.request_id == next_request.id then
      dispatch(next_request)
    end
  end
end

local function start()
  if worker then
    return true
  end
  output, stderr = "", ""
  local job
  job = vim.fn.jobstart({ python(), root .. "/scripts/minimap-render.py", "--worker" }, {
    on_stdout = function(_, data)
      if worker ~= job then
        return
      end
      output = output .. data[1]
      for index = 2, #data do
        if output ~= "" then
          response(output)
        end
        output = data[index]
      end
    end,
    on_stderr = function(_, data)
      if worker == job then
        stderr = (stderr .. table.concat(data, "\n")):sub(-2000)
      end
    end,
    on_exit = function(_, code)
      if worker ~= job then
        return
      end
      worker, flight, queued = nil, nil, nil
      if code ~= 0 and not warned and vim.v.exiting == vim.NIL then
        warned = true
        vim.notify(
          "Minimap renderer unavailable. Run :MinimapSetup to install Pillow.\n" .. stderr,
          vim.log.levels.WARN
        )
      end
    end,
  })
  if job <= 0 then
    stderr = "Cannot start minimap Python renderer"
    return false
  end
  worker = job
  return true
end

function M.update(win, model)
  local rect = geometry(win)
  if not rect then
    return
  end
  -- Windows Terminal uses virtual Sixel cells of 10x20 pixels, independently
  -- of physical DPI, font face and line height (Microsoft SixelParser).
  model.cell_width, model.cell_height = options.cell_width or 10, options.cell_height or 20
  model.pixel_width = rect.width * model.cell_width
  model.pixel_height = rect.height * model.cell_height
  model.font = options.font or (root .. "/fonts/ForgeMonoGeometry6NF-Regular.ttf")
  model.char_width = options.char_width or 2
  local previous = records[win]
  local same = previous ~= nil
  if same then
    local old = previous.model
    for _, name in ipairs({
      "characters",
      "offset",
      "resolution",
      "count",
      "source_buf",
      "changedtick",
      "large",
      "pixel_width",
      "pixel_height",
      "font",
      "char_width",
      "background",
    }) do
      if old[name] ~= model[name] then
        same = false
        break
      end
    end
    same = same and vim.deep_equal(old.diagnostics, model.diagnostics)
  end
  local record = previous or { win = win }
  if
    record.rendered
    and (
      record.rendered.pixel_width ~= model.pixel_width
      or record.rendered.pixel_height ~= model.pixel_height
      or record.rendered.source_buf ~= model.source_buf
      or record.rendered.resolution ~= model.resolution
      or record.rendered.char_width ~= model.char_width
    )
  then
    record.tiles, record.rendered, record.hashes = nil, nil, nil
  end
  record.model, record.rect = model, rect
  records[win] = record
  -- Cursor, viewport and selections repaint immediately using cached ink.
  -- They never queue a Python request or discard an in-flight code render.
  send(record)
  if same then
    return
  end
  serial = serial + 1
  record.request_id = serial
  local request = { id = serial, win = win, model = model }
  if capable ~= true or not tty() or not start() then
    return
  end
  if flight then
    queued = request
  else
    dispatch(request)
  end
end

function M.snapshot(win)
  return records[win] and vim.deepcopy(records[win].model) or nil
end

function M.clear(win)
  erase(records[win])
  records[win] = nil
  if next(records) == nil and worker then
    local job = worker
    worker, flight, queued = nil, nil, nil
    vim.fn.jobstop(job)
  end
end

function M.setup(opts)
  options = opts or {}
  attributes(vim.v.termresponse)
  local group = api.nvim_create_augroup("WorkbenchMinimapImage", { clear = true })
  api.nvim_create_autocmd("TabLeave", {
    group = group,
    callback = function()
      for _, record in pairs(records) do
        erase(record)
      end
    end,
  })
  api.nvim_create_autocmd("TermResponse", {
    group = group,
    callback = function(event)
      attributes(event.data.sequence)
      if capable then
        vim.schedule(function()
          require("config.minimap").refresh()
        end)
      elseif capable == false and tty() and require("config.minimap").is_enabled() then
        vim.schedule(function()
          M.query()
          require("config.minimap").close()
        end)
      end
    end,
  })
  api.nvim_create_autocmd({ "WinClosed", "VimLeavePre" }, {
    group = group,
    callback = function(event)
      if event.event == "WinClosed" then
        M.clear(tonumber(event.match))
      else
        records = {}
        M.clear(0)
      end
    end,
  })
  local ns = api.nvim_create_namespace("WorkbenchMinimapImage")
  local dirty = {}
  api.nvim_set_decoration_provider(ns, {
    on_win = function(_, win)
      return records[win] ~= nil
    end,
    on_line = function(_, win, _, row)
      dirty[win] = dirty[win] or {}
      dirty[win][row + 1] = true
    end,
    on_end = function()
      if not repaint_pending and next(records) ~= nil and capable and tty() then
        repaint_pending = true
        vim.schedule(function()
          repaint_pending = false
          local changed = dirty
          dirty = {}
          for win, record in pairs(records) do
            local rect = api.nvim_win_is_valid(win) and geometry(win) or nil
            if rect then
              local hidden = obscured(rect)
              if
                changed[win]
                or (hidden and record.painted)
                or (not hidden and not record.painted)
              then
                send(record, changed[win])
              end
            end
          end
        end)
      end
    end,
  })
  api.nvim_create_user_command("MinimapSetup", function()
    local base = vim.fn.stdpath("data") .. "/workbench-minimap-env"
    local interpreter = vim.fn.has("win32") == 1 and "python" or "python3"
    vim.system({ interpreter, "-m", "venv", base }, {}, function(result)
      if result.code ~= 0 then
        vim.schedule(function()
          vim.notify(result.stderr, vim.log.levels.ERROR)
        end)
        return
      end
      local executable = base
        .. (vim.fn.has("win32") == 1 and "/Scripts/python.exe" or "/bin/python")
      vim.system({ executable, "-m", "pip", "install", "Pillow>=12,<13" }, {}, function(installed)
        vim.schedule(function()
          warned = false
          if installed.code == 0 then
            records = {}
            M.clear(0)
            require("config.minimap").refresh()
            vim.notify("Minimap font renderer ready")
          else
            vim.notify(installed.stderr, vim.log.levels.ERROR)
          end
        end)
      end)
    end)
  end, { desc = "Install the minimap font renderer in an isolated Python environment" })
end

function M.query()
  if tty() and capable == false then
    if not unsupported_warned then
      unsupported_warned = true
      vim.notify(
        "Small-font minimap needs a Sixel terminal (Windows Terminal 1.22+)",
        vim.log.levels.WARN
      )
    end
    return false
  end
  if tty() and capable == nil then
    api.nvim_ui_send("\27[c")
  end
  return true
end

return M
