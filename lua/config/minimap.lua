local M = {}
local api = vim.api
local states = {}
local content_ns = api.nvim_create_namespace("WorkbenchMinimapContent")
local view_ns = api.nvim_create_namespace("WorkbenchMinimapView")
local pending, busy = false, false
local timer, last_grid

-- A native companion split reserves space instead of covering source text.
-- It shares its owner's outer frame and is skipped by pane navigation.
M.config = {
  width = 14,
  min_editor_width = 48,
  min_height = 6,
  max_lines = 20000,
  max_bytes = 1024 * 1024,
  max_columns = 240,
  refresh_ms = 80,
}

local function valid(win)
  return type(win) == "number" and api.nvim_win_is_valid(win)
end

local function stop_if_idle()
  if not timer or timer:is_closing() then
    return
  end
  for tab, state in pairs(states) do
    if state.enabled and api.nvim_tabpage_is_valid(tab) then
      return
    end
  end
  timer:stop()
end

local function editor(win)
  if not valid(win) or api.nvim_win_get_config(win).relative ~= "" then
    return false
  end
  local buf = api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype == "" and vim.bo[buf].filetype ~= "ministarter"
end

function M.window(tab)
  local state = states[tab or api.nvim_get_current_tabpage()]
  return state and valid(state.win) and state.win or nil
end

function M.is_enabled(tab)
  local state = states[tab or api.nvim_get_current_tabpage()]
  return state ~= nil and state.enabled == true
end

-- Public geometry contract used by the frame, tabs and resize grip. The
-- minimap is inside the editor outline, not a second editor/file tab.
function M.span(win)
  local state = valid(win) and states[api.nvim_win_get_tabpage(win)] or nil
  local width = valid(win) and api.nvim_win_get_width(win) or 0
  if state and state.source == win and valid(state.win) then
    local p, q = api.nvim_win_get_position(win), api.nvim_win_get_position(state.win)
    if q[1] == p[1] and q[2] == p[2] + width + 1 then
      return state.win, width + 1 + api.nvim_win_get_width(state.win)
    end
  end
  return win, width
end

local function detach(state)
  local win = state.win
  state.win, state.encoded = nil, nil
  if valid(win) then
    pcall(api.nvim_win_close, win, true)
    return true
  end
  return false
end

local function configure(state)
  local win = state.win
  local weight = require("config.frame").focused_window() == state.source and "active" or "normal"
  local shapes = require("config.shapes")
  local border = shapes["edge_" .. weight .. "_bottom"]
  local options = {
    winfixwidth = true,
    winfixbuf = true,
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    statuscolumn = "",
    colorcolumn = "",
    wrap = false,
    list = false,
    cursorline = false,
    cursorcolumn = false,
    spell = false,
    foldenable = false,
    scrolloff = 0,
    sidescrolloff = 0,
    winbar = vim.wo[state.source].winbar ~= ""
        and ("%#WorkbenchEditorFill#" .. shapes["edge_" .. weight .. "_top"] .. "%=")
      or "",
    statusline = "%#WorkbenchEditorFill#" .. border .. "%=",
    fillchars = "eob: ,vert: ,stl:" .. border .. ",stlnc:" .. border,
    winhighlight = "Normal:WorkbenchMinimap,NormalNC:WorkbenchMinimap,EndOfBuffer:WorkbenchMinimap,"
      .. "WinSeparator:WorkbenchEditorFill,StatusLine:WorkbenchEditorFill,StatusLineNC:WorkbenchEditorFill,"
      .. "WinBar:WorkbenchEditorFill,WinBarNC:WorkbenchEditorFill",
  }
  for name, value in pairs(options) do
    if vim.wo[win][name] ~= value then
      vim.wo[win][name] = value
    end
  end
end

-- Called before frame layout, including synchronous handling of tiny grids.
function M.sync()
  if busy or vim.v.exiting ~= vim.NIL then
    return false
  end
  last_grid = { vim.o.columns, vim.o.lines }
  for tab in pairs(states) do
    if not api.nvim_tabpage_is_valid(tab) then
      states[tab] = nil
    end
  end
  stop_if_idle()
  local tab = api.nvim_get_current_tabpage()
  local state = states[tab]
  if not state or not state.enabled then
    return false
  end
  busy = true
  local source = api.nvim_get_current_win()
  if not editor(source) then
    source = require("core.navigation").editor_window()
  end
  local changed = false
  if state.source ~= source then
    changed = detach(state)
    state.source = source
  end
  local available = editor(source) and select(2, M.span(source)) or 0
  local enough_room = vim.o.columns >= 24
    and vim.o.lines >= 8
    and available >= M.config.min_editor_width + M.config.width + 1
    and api.nvim_win_get_height(source) >= M.config.min_height
  if not enough_room then
    changed = detach(state) or changed
  elseif not valid(state.win) then
    local buf = api.nvim_create_buf(false, true)
    -- Reuse the decoration filetype so all existing focus/footer predicates
    -- exclude this buffer. A separate role identifies the minimap itself.
    vim.bo[buf].filetype = "workbench-frame"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].undolevels = -1
    state.win = api.nvim_open_win(buf, false, {
      split = "right",
      win = source,
      width = M.config.width,
      focusable = false,
      mouse = false,
      noautocmd = true,
    })
    vim.w[state.win].workbench_role = "minimap"
    changed = true
  end
  if valid(state.win) then
    if api.nvim_win_get_width(state.win) ~= M.config.width then
      api.nvim_win_set_width(state.win, M.config.width)
      changed = true
    end
    configure(state)
  end
  busy = false
  return changed
end

local function row_for(state, line)
  local scaled = math.min(state.count, state.height * state.resolution) / state.count
  return math.min(state.rows, math.floor(math.floor((line - 1) * scaled) / state.resolution) + 1)
    - 1
end

function M.paint()
  local state = states[api.nvim_get_current_tabpage()]
  if not state or not valid(state.win) or not editor(state.source) then
    return
  end
  configure(state)
  local buf = api.nvim_win_get_buf(state.source)
  local target = api.nvim_win_get_buf(state.win)
  local height, width = api.nvim_win_get_height(state.win), api.nvim_win_get_width(state.win)
  local count, tick = api.nvim_buf_line_count(buf), api.nvim_buf_get_changedtick(buf)
  local key = { buf, tick, height, width }
  if not vim.deep_equal(state.encoded, key) then
    local lines
    local large = count > M.config.max_lines
      or api.nvim_buf_get_offset(buf, count) > M.config.max_bytes
    if large then
      -- Keep a useful proportional scrollbar without encoding huge files.
      lines = vim.fn["repeat"]({ string.rep(" ", width) }, height)
    else
      local source = api.nvim_buf_get_lines(buf, 0, -1, false)
      for index, text in ipairs(source) do
        source[index] = vim.fn
          .strcharpart(text, 0, M.config.max_columns)
          :gsub("\t", string.rep(" ", vim.bo[buf].tabstop))
      end
      lines = require("mini.map").encode_strings(source, {
        n_rows = height,
        n_cols = width - 3,
        symbols = require("mini.map").gen_encode_symbols.block("2x2"),
      })
      for index, text in ipairs(lines) do
        lines[index] = "   "
          .. text
          .. string.rep(" ", math.max(0, width - 3 - vim.fn.strdisplaywidth(text)))
      end
    end
    vim.bo[target].modifiable = true
    api.nvim_buf_set_lines(target, 0, -1, false, lines)
    vim.bo[target].modified = false
    vim.bo[target].modifiable = false
    state.encoded, state.count, state.height, state.rows = key, count, height, #lines
    state.resolution = large and 1 or 2
  end
  api.nvim_buf_clear_namespace(target, content_ns, 0, -1)
  local diagnostics, visible_namespaces = {}, {}
  if vim.diagnostic.is_enabled({ bufnr = buf }) then
    for _, item in ipairs(vim.diagnostic.get(buf)) do
      local namespace = item.namespace
      if namespace and visible_namespaces[namespace] == nil then
        visible_namespaces[namespace] =
          vim.diagnostic.is_enabled({ bufnr = buf, ns_id = namespace })
      end
      if not namespace or visible_namespaces[namespace] then
        local row = row_for(state, item.lnum + 1)
        diagnostics[row] = math.min(diagnostics[row] or 4, item.severity)
      end
    end
  end
  for row, severity in pairs(diagnostics) do
    api.nvim_buf_set_extmark(target, content_ns, row, 0, {
      virt_text = { { "●", "Diagnostic" .. ({ "Error", "Warn", "Info", "Hint" })[severity] } },
      virt_text_pos = "overlay",
      virt_text_win_col = 1,
      priority = 30,
    })
  end
  api.nvim_buf_clear_namespace(target, view_ns, 0, -1)
  local first, last = unpack(api.nvim_win_call(state.source, function()
    return { vim.fn.line("w0"), vim.fn.line("w$") }
  end))
  for row = row_for(state, first), row_for(state, last) do
    api.nvim_buf_set_extmark(target, view_ns, row, 0, {
      line_hl_group = "WorkbenchMinimapView",
      virt_text = { { "┃", "WorkbenchMinimapScrollbar" } },
      virt_text_pos = "overlay",
      priority = 10,
    })
  end
  api.nvim_buf_set_extmark(
    target,
    view_ns,
    row_for(state, api.nvim_win_get_cursor(state.source)[1]),
    0,
    {
      virt_text = { { "▸", "WorkbenchMinimapCursor" } },
      virt_text_pos = "overlay",
      priority = 20,
    }
  )
  api.nvim_win_set_cursor(state.win, { 1, 0 })
end

function M.refresh()
  if M.sync() then
    require("config.frame").refresh()
  else
    M.paint()
  end
end

function M.open()
  local tab = api.nvim_get_current_tabpage()
  states[tab] = states[tab] or {}
  states[tab].enabled = true
  if not timer then
    timer = vim.uv.new_timer()
  end
  -- VimResized is deferred during Visual mode. Observe only grid changes;
  -- normal content/cursor updates still use coalesced editor events.
  timer:start(
    200,
    200,
    vim.schedule_wrap(function()
      if M.is_enabled() and not vim.deep_equal(last_grid, { vim.o.columns, vim.o.lines }) then
        M.refresh()
      end
    end)
  )
  M.refresh()
end

function M.close()
  local state = states[api.nvim_get_current_tabpage()]
  if state then
    state.enabled = false
    if detach(state) then
      require("config.frame").refresh()
    end
  end
  stop_if_idle()
end

function M.toggle()
  if M.is_enabled() then
    M.close()
  else
    M.open()
  end
end

function M.setup(opts)
  M.config = vim.tbl_extend("force", M.config, opts or {})
  assert(M.config.width >= 6 and M.config.width <= 40, "Minimap width must be 6–40 columns")
  local group = api.nvim_create_augroup("WorkbenchMinimap", { clear = true })
  api.nvim_create_autocmd({
    "WinEnter",
    "BufEnter",
    "TabEnter",
    "WinResized",
    "VimResized",
    "ColorScheme",
    "TextChanged",
    "TextChangedI",
    "CursorMoved",
    "CursorMovedI",
    "WinScrolled",
    "DiagnosticChanged",
    "CmdlineLeave",
  }, {
    group = group,
    callback = function()
      if pending or not M.is_enabled() then
        return
      end
      pending = true
      vim.defer_fn(function()
        pending = false
        if vim.v.exiting == vim.NIL then
          M.refresh()
        end
      end, M.config.refresh_ms)
    end,
  })
  api.nvim_create_autocmd("QuitPre", {
    group = group,
    callback = function()
      local state = states[api.nvim_get_current_tabpage()]
      if state then
        detach(state)
      end
    end,
  })
  api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if timer and not timer:is_closing() then
        timer:stop()
        timer:close()
      end
    end,
  })
  for name, action in pairs({
    MinimapToggle = M.toggle,
    MinimapOpen = M.open,
    MinimapClose = M.close,
  }) do
    api.nvim_create_user_command(name, action, { desc = name:gsub("Minimap", "Minimap ") })
  end
end

return M
