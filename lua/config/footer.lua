local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("WorkbenchNativeFooter")
local states = {}
local busy, pending, installed = false, false, false
local timer

local function valid(win)
  return type(win) == "number" and api.nvim_win_is_valid(win)
end

function M.is_window(win)
  return valid(win) and vim.w[win].workbench_role == "footer"
end

local function owner_window(win, tab)
  if not valid(win) or api.nvim_win_get_tabpage(win) ~= tab then
    return false
  end
  local ft = vim.bo[api.nvim_win_get_buf(win)].filetype
  return api.nvim_win_get_config(win).relative == ""
    and ft ~= "workbench-frame"
    and ft ~= "neo-tree"
end

local function owner(state, tab)
  local current = api.nvim_get_current_win()
  if owner_window(current, tab) then
    state.owner = current
  end
  if not owner_window(state.owner, tab) then
    state.owner = nil
    for _, win in ipairs(api.nvim_tabpage_list_wins(tab)) do
      if owner_window(win, tab) then
        state.owner = win
        break
      end
    end
  end
  return state.owner
end

local function configure(win)
  local options = {
    winbar = "",
    statusline = "",
    winfixheight = true,
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
    scrolloff = 0,
    sidescrolloff = 0,
    spell = false,
    foldenable = false,
    fillchars = "eob: ",
    winhighlight = "Normal:WorkbenchChrome,NormalNC:WorkbenchChrome,EndOfBuffer:WorkbenchChrome",
  }
  for name, value in pairs(options) do
    if vim.wo[win][name] ~= value then
      vim.wo[win][name] = value
    end
  end
  vim.w[win].workbench_role = "footer"
end

local function scratch()
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "workbench-frame"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].undolevels = -1
  api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
  vim.bo[buf].modifiable = false
  return buf
end

local function remove_state(tab)
  local state = states[tab]
  states[tab] = nil
  if state and M.is_window(state.win) then
    pcall(api.nvim_win_close, state.win, true)
  end
end

function M.remove(tab)
  local was_busy = busy
  busy = true
  remove_state(tab or api.nvim_get_current_tabpage())
  busy = was_busy
end

local function schedule()
  if busy or pending or vim.v.exiting ~= vim.NIL then
    return
  end
  pending = true
  vim.schedule(function()
    pending = false
    M.refresh()
  end)
end

local function install()
  if installed then
    return
  end
  installed = true
  local group = api.nvim_create_augroup("WorkbenchNativeFooter", { clear = true })
  api.nvim_create_autocmd({
    "WinEnter",
    "BufEnter",
    "BufModifiedSet",
    "CursorMoved",
    "CursorMovedI",
    "TextChanged",
    "TextChangedI",
    "ModeChanged",
    "LspAttach",
    "LspDetach",
    "DiagnosticChanged",
    "TabEnter",
    "VimResized",
    "WinResized",
    "ColorScheme",
  }, { group = group, callback = schedule })
  api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "ScreenkeyUpdated", "ScreenkeyCleared", "GitSignsUpdate" },
    callback = schedule,
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
  timer = vim.uv.new_timer()
  timer:start(1000, 1000, vim.schedule_wrap(schedule))
end

function M.ensure()
  if busy or vim.v.exiting ~= vim.NIL then
    return
  end
  install()
  local compact = vim.o.lines < 8 or vim.o.columns < 24
  local frame = package.loaded["config.frame"]
  -- Neovim can defer VimResized while a Visual selection is active. The
  -- existing footer timer observes layout transitions without mode changes.
  if type(frame) == "table" and frame.compact ~= compact then
    vim.schedule(frame.refresh)
  end
  local tab = api.nvim_get_current_tabpage()
  if compact then
    M.remove()
    vim.o.laststatus = 2
    return
  end
  busy = true
  local ok, result = pcall(function()
    for old_tab in pairs(states) do
      if not api.nvim_tabpage_is_valid(old_tab) then
        states[old_tab] = nil
      end
    end
    local state = states[tab] or {}
    states[tab] = state
    owner(state, tab)
    if not M.is_window(state.win) then
      state.win = api.nvim_open_win(scratch(), false, {
        split = "below",
        win = -1,
        height = 1,
        focusable = false,
        mouse = false,
        noautocmd = true,
      })
      state.rendered = nil
      vim.w[state.win].workbench_role = "footer"
    end
    -- Only the last window loses its statusline. Every pane above this
    -- full-width footer keeps a native statusline row for its bottom border.
    if vim.o.laststatus ~= 0 then
      vim.o.laststatus = 0
    end
    configure(state.win)
    local p = api.nvim_win_get_position(state.win)
    local final_row = vim.o.lines - vim.o.cmdheight - 1
    if p[1] ~= final_row or p[2] ~= 0 or api.nvim_win_get_width(state.win) ~= vim.o.columns then
      api.nvim_win_set_config(state.win, { split = "below", win = -1, height = 1 })
    end
    if api.nvim_win_get_height(state.win) ~= 1 then
      api.nvim_win_set_height(state.win, 1)
    end
    return state.win
  end)
  busy = false
  if ok then
    return result
  end
  -- Very small layouts can temporarily reject a split. Keep their native
  -- statuslines available and retry after the next layout change.
  M.remove()
  vim.o.laststatus = 2
end

local function fallback()
  local text = " FORGE · " .. vim.fn.fnamemodify(vim.fn.getcwd(), ":~")
  local width = vim.o.columns
  while vim.fn.strdisplaywidth(text) > width do
    text = vim.fn.strcharpart(text, 0, vim.fn.strchars(text) - 1)
  end
  return {
    str = text .. string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(text))),
    highlights = {},
  }
end

local function render(state, tab)
  local win = owner(state, tab)
  local line
  local lualine = package.loaded["lualine"]
  if win and lualine and lualine.statusline then
    local ok, value = pcall(api.nvim_win_call, win, function()
      local expression = lualine.statusline(true)
      if expression and expression ~= "" then
        return api.nvim_eval_statusline(expression, {
          winid = win,
          maxwidth = vim.o.columns,
          highlights = true,
          fillchar = " ",
        })
      end
    end)
    if ok then
      line = value
    end
  end
  line = type(line) == "table" and line or fallback()
  line.highlights = line.highlights or {}
  line = require("config.footer_capsules").decorate(line)
  if
    state.rendered
    and state.rendered.str == line.str
    and vim.deep_equal(state.rendered.highlights, line.highlights)
  then
    return
  end
  local buf = api.nvim_win_get_buf(state.win)
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, { line.str })
  vim.bo[buf].modified = false
  vim.bo[buf].modifiable = false
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for index, item in ipairs(line.highlights) do
    local finish = line.highlights[index + 1] and line.highlights[index + 1].start or #line.str
    if finish > item.start and (item.groups or item.group) then
      api.nvim_buf_set_extmark(buf, ns, 0, item.start, {
        end_row = 0,
        end_col = finish,
        hl_group = item.groups or item.group,
        priority = 150,
      })
    end
  end
  state.rendered = { str = line.str, highlights = line.highlights }
end

function M.refresh()
  if busy or vim.v.exiting ~= vim.NIL then
    return
  end
  local win = M.ensure()
  if not win then
    return
  end
  local tab = api.nvim_get_current_tabpage()
  local state = states[tab]
  if not state or not M.is_window(state.win) then
    return
  end
  busy = true
  pcall(render, state, tab)
  busy = false
end

return M
