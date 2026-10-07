local M = {}
local api = vim.api
local shapes = require("config.shapes")
local layouts, targets = {}, {}

local function escaped(text)
  return (text:gsub("%%", "%%%%"))
end
local function crop(text, maximum)
  if vim.fn.strdisplaywidth(text) <= maximum then
    return text
  end
  local result = ""
  for char in text:gmatch("[\1-\127\194-\244][\128-\191]*") do
    if vim.fn.strdisplaywidth(result .. char) > maximum - 1 then
      break
    end
    result = result .. char
  end
  return result .. "…"
end
local function edge(weight, kind)
  return shapes["edge_" .. weight .. "_" .. kind]
end
local function face(name, text)
  return "%#" .. name .. "#" .. escaped(text)
end
local function weight(win)
  return require("config.frame").focused_window() == win and "active" or "normal"
end
-- Selection opens a tab into the editor; focus independently controls the
-- weight of that shared outline. Dim selected tabs must remain open below.
local function marked(text, roof, bottom)
  local parts = {}
  for char in text:gmatch("[\1-\127\194-\244][\128-\191]*") do
    local wide = vim.fn.strdisplaywidth(char) == 2
    if wide and require("core.settings").get().geometry_images then
      -- Keep wide text in its native fallback font. Ghostty cannot shape the
      -- custom zero-width marks and CJK glyphs as one font run.
      -- geometry_image supplies these strokes without marking the TUI text.
      parts[#parts + 1] = char
    else
      parts[#parts + 1] = char
        .. (roof and edge(roof, wide and "wide_roof_mark" or "roof_mark") or "")
        .. (bottom and edge(bottom, wide and "wide_mark" or "mark") or "")
    end
  end
  return table.concat(parts)
end
local function welcome(win)
  return vim.bo[api.nvim_win_get_buf(win)].filetype == "ministarter"
end
local function title(win)
  local buf = api.nvim_win_get_buf(win)
  local name = vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ":t")
  if vim.bo[buf].buftype == "terminal" then
    return "TERMINAL"
  end
  if vim.bo[buf].buftype == "quickfix" then
    return "QUICKFIX"
  end
  return name ~= "" and name or "New file"
end
local function layout(win, budget, primary)
  local current = api.nvim_win_get_buf(win)
  local state = require("bufferline.state")
  local tabs, active_index = {}, nil
  if primary then
    for _, component in ipairs(state.components or {}) do
      local element = component:as_element()
      if
        element
        and api.nvim_buf_is_valid(element.id)
        and vim.bo[element.id].buftype == ""
        and vim.bo[element.id].filetype ~= "ministarter"
      then
        local name =
          crop(element.name ~= "" and element.name or "New file", budget < 65 and 14 or 22)
        local icon = require("nvim-web-devicons").get_icon(
          name,
          vim.fn.fnamemodify(name, ":e"),
          { default = true }
        )
        if state.is_picking then
          icon = element.letter or icon
        end
        local label = " " .. icon .. "  " .. name .. " "
        if vim.bo[element.id].modified then
          label = label .. "● "
        end
        if vim.bo[element.id].readonly then
          label = label .. " "
        end
        tabs[#tabs + 1] = { id = element.id, label = label }
        if element.id == current then
          active_index = #tabs
        end
      end
    end
  end
  if not active_index then
    tabs[#tabs + 1] =
      { id = current, label = "  " .. crop(title(win), math.max(1, budget - 6)) .. " " }
    active_index = #tabs
  end
  for _, tab in ipairs(tabs) do
    tab.active = tab.id == current
    tab.width = vim.fn.strdisplaywidth(tab.label) + 2
  end
  local selected = tabs[active_index]
  if selected.width + 4 > budget then
    selected.label = crop(selected.label, math.max(1, budget - 6))
    selected.width = vim.fn.strdisplaywidth(selected.label) + 2
  end
  local function cost(first, last)
    local used = 2 + (last - first) + 1 + (tabs[last].active and 1 or 0)
    for index = first, last do
      used = used + tabs[index].width
    end
    return used
  end
  local first, last = active_index, active_index
  while first > 1 and cost(first - 1, last) <= budget do
    first = first - 1
  end
  while last < #tabs and cost(first, last + 1) <= budget do
    last = last + 1
  end
  local visible, column = {}, 2
  for index = first, last do
    local tab = tabs[index]
    tab.left, tab.right = column, column + tab.width - 1
    column = column + tab.width + (index < last and 1 or 0)
    visible[#visible + 1] = tab
  end
  return {
    tabs = visible,
    used = cost(first, last),
    width = budget,
    first_selected = first == active_index,
  }
end

function M.prepare()
  pcall(_G.nvim_bufferline)
  local panes = require("config.frame").panes()
  local editor = require("core.navigation").editor_window()
  local primary
  for _, pane in ipairs(panes) do
    if pane.row == 1 and pane.role == "Editor" then
      primary = primary or pane.win
      if pane.win == editor then
        primary = editor
        break
      end
    end
  end
  M.tab_win = primary
  layouts = {}
  for _, pane in ipairs(panes) do
    if pane.row == 1 and pane.role == "Editor" and not welcome(pane.win) then
      -- Include the native separator and left rail in the header budget. The
      -- first selected tab can then share the pane's outermost vertical edge.
      layouts[pane.win] = layout(pane.win, pane.width + 3, pane.win == primary)
    end
  end
  return panes
end
function M.first_selected(win)
  return layouts[win] and layouts[win].first_selected or false
end
function M.model(win)
  return layouts[win]
end
local function label_row(win, data)
  local body = weight(win)
  local first, last = data.tabs[1], data.tabs[#data.tabs]
  local parts = {
    face(
      first.active and "WorkbenchEditorFill" or "WorkbenchChrome",
      first.active and edge(body, "top_left") or " "
    ),
    face(
      first.active and "WorkbenchEditorFill" or "WorkbenchTabInactive",
      first.active and edge(body, "top") or marked(edge("normal", "top_left"), nil, body)
    ),
  }
  for index, tab in ipairs(data.tabs) do
    local hl = tab.active and "WorkbenchTabActive" or "WorkbenchTabInactive"
    local roof, bottom = tab.active and body or "normal", not tab.active and body or nil
    local target = win * 100000 + tab.id
    targets[target] = { win = win, buf = tab.id }
    parts[#parts + 1] = "%"
      .. target
      .. "@v:lua.WorkbenchTabTargetClick@"
      .. face(hl, marked(tab.label, roof, bottom))
      .. "%T%"
      .. target
      .. "@v:lua.WorkbenchTabTargetClose@"
      .. face(hl, marked("󰅖 ", roof, bottom))
      .. "%T"
    local next_tab = data.tabs[index + 1]
    if next_tab then
      local transition = (tab.active and "a" or "i") .. (next_tab.active and "a" or "i")
      parts[#parts + 1] = face("WorkbenchChrome", shapes["edge_seam_" .. body .. "_" .. transition])
    end
  end
  if last.active then
    parts[#parts + 1] = face(
      "WorkbenchEditorFill",
      body == "active" and edge(body, "cap_right") or shapes.edge_selected_normal_cap_right
    ) .. face("WorkbenchEditorFill", edge(body, "join_right"))
  else
    parts[#parts + 1] = face("WorkbenchTabInactive", marked(edge("normal", "cap_right"), nil, body))
  end
  parts[#parts + 1] =
    face("WorkbenchChrome", string.rep(edge(body, "bottom"), math.max(0, data.width - data.used)))
  return table.concat(parts)
end
function M.header(win)
  local width = api.nvim_win_get_width(win)
  if welcome(win) then
    local label = crop("  F O R G E  /  W O R K S P A C E", width)
    return face("WorkbenchEditorTitle", label)
      .. face(
        "WorkbenchEditorFill",
        string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(label)))
      )
  end
  local data = layouts[win] or layout(win, width + 3, win == M.tab_win)
  return label_row(win, data)
end
local function explorer(win, width, roofline)
  local state = require("neo-tree.sources.manager").get_state_for_window(win)
  local label = width >= 26 and " 󰉋 EXPLORER " or " 󰉋 "
  local buttons, used = {}, 0
  local roof = roofline and weight(win) or nil
  for index, item in ipairs({
    { "filesystem", "󰉓", "Files" },
    { "buffers", "󰈙", "Bufs" },
    { "git_status", "", "Git" },
  }) do
    local active = state and state.name == item[1]
    local text = " " .. item[2] .. (width >= 40 and (" " .. item[3]) or "") .. " "
    used = used + vim.fn.strdisplaywidth(text)
    buttons[#buttons + 1] = "%"
      .. index
      .. "@v:lua.WorkbenchTreeSource@"
      .. face(active and "WorkbenchTreeTitle" or "NeoTreeTabInactive", marked(text, roof))
      .. "%T"
  end
  local padding = string.rep(" ", math.max(0, width - used - vim.fn.strdisplaywidth(label)))
  return face("WorkbenchTreeTitle", marked(label, roof))
    .. face("WorkbenchTreeFill", marked(padding, roof))
    .. table.concat(buttons)
end
function M.render()
  local panes = M.prepare()
  targets = {}
  local parts, column = {}, 0
  M.active_bounds = nil
  for _, pane in ipairs(panes) do
    if pane.row == 1 then
      local body = weight(pane.win)
      parts[#parts + 1] = face("WorkbenchChrome", string.rep(" ", math.max(0, pane.left - column)))
      if pane.role == "Tree" then
        parts[#parts + 1] = face("WorkbenchTreeFill", edge(body, "top_left") .. edge(body, "top"))
          .. explorer(pane.win, pane.width, true)
          .. face("WorkbenchTreeFill", edge(body, "top") .. edge(body, "top_right"))
      elseif welcome(pane.win) then
        parts[#parts + 1] = face(
          "WorkbenchEditorFill",
          edge(body, "top_left")
            .. string.rep(edge(body, "top"), pane.right - pane.left - 1)
            .. edge(body, "top_right")
        )
      else
        local data = layouts[pane.win]
        parts[#parts + 1] = label_row(pane.win, data) .. face("WorkbenchChrome", " ")
        if pane.win == M.tab_win then
          for _, tab in ipairs(data.tabs) do
            if tab.active then
              M.active_bounds = { left = tab.left, right = tab.right, win = pane.win }
            end
          end
        end
      end
      column = pane.right + 1
    end
  end
  parts[#parts + 1] = face("WorkbenchChrome", string.rep(" ", math.max(0, vim.o.columns - column)))
  return table.concat(parts)
end
function M.setup()
  _G.WorkbenchTabs = M.render
  _G.WorkbenchPaneHeader = function()
    return M.header(vim.g.statusline_winid or api.nvim_get_current_win())
  end
  _G.WorkbenchLowerHeader = function()
    local win = vim.g.statusline_winid or api.nvim_get_current_win()
    local width, body = api.nvim_win_get_width(win), weight(win)
    local label = "  " .. crop(title(win), math.max(1, width - 4)) .. "  "
    return face("WorkbenchEditorTitle", marked(label, body))
      .. face(
        "WorkbenchEditorFill",
        string.rep(edge(body, "top"), math.max(0, width - vim.fn.strdisplaywidth(label)))
      )
  end
  _G.WorkbenchExplorerHeader = function()
    local win = vim.g.statusline_winid or api.nvim_get_current_win()
    return explorer(win, api.nvim_win_get_width(win), false)
  end
  _G.WorkbenchTreeSource = function(index)
    local source = ({ "filesystem", "buffers", "git_status" })[index]
    if source == "filesystem" then
      require("core.navigation").focus_tree()
    else
      require("neo-tree.command").execute({
        source = source,
        action = "focus",
        reveal = false,
        dir = require("core.navigation").project_root(),
      })
    end
  end
  _G.WorkbenchTabTargetClick = function(key, _, button)
    local target = targets[key]
    if
      not target
      or not api.nvim_buf_is_valid(target.buf)
      or not api.nvim_win_is_valid(target.win)
    then
      return
    end
    if button == "m" or button == "r" then
      require("mini.bufremove").delete(target.buf, false)
    else
      api.nvim_set_current_win(target.win)
      api.nvim_set_current_buf(target.buf)
    end
    require("config.frame").refresh()
    vim.cmd.redrawtabline()
  end
  _G.WorkbenchTabTargetClose = function(key)
    local target = targets[key]
    if target and api.nvim_buf_is_valid(target.buf) then
      require("mini.bufremove").delete(target.buf, false)
    end
    require("config.frame").refresh()
    vim.cmd.redrawtabline()
  end
  _G.WorkbenchTabClick = function(buf, _, button)
    if not api.nvim_buf_is_valid(buf) then
      return
    end
    if button == "m" or button == "r" then
      require("mini.bufremove").delete(buf, false)
    else
      if M.tab_win and api.nvim_win_is_valid(M.tab_win) then
        api.nvim_set_current_win(M.tab_win)
      else
        require("core.navigation").return_editor()
      end
      api.nvim_set_current_buf(buf)
    end
    require("config.frame").refresh()
    vim.cmd.redrawtabline()
  end
  _G.WorkbenchTabClose = function(buf)
    if api.nvim_buf_is_valid(buf) then
      require("mini.bufremove").delete(buf, false)
    end
    require("config.frame").refresh()
    vim.cmd.redrawtabline()
  end
  api.nvim_create_autocmd({ "BufEnter", "BufModifiedSet", "WinEnter" }, {
    group = api.nvim_create_augroup("WorkbenchTabs", { clear = true }),
    callback = function()
      vim.cmd.redrawtabline()
      vim.cmd.redrawstatus()
    end,
  })
  api.nvim_create_autocmd("User", {
    group = "WorkbenchTabs",
    pattern = "MiniStarterOpened",
    callback = function()
      vim.o.showtabline = 2
    end,
  })
  vim.o.showtabline = 2
  vim.o.tabline = "%!v:lua.WorkbenchTabs()"
end
return M
