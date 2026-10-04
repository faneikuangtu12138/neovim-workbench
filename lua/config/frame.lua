local M = {}
local api = vim.api
local states, previous, focused = {}, {}, {}
local busy, pending = false, false

function M.is_frame(win)
  return win
    and api.nvim_win_is_valid(win)
    and vim.bo[api.nvim_win_get_buf(win)].filetype == "workbench-frame"
end
local function ordinary(win, tab)
  return win
    and api.nvim_win_is_valid(win)
    and not M.is_frame(win)
    and api.nvim_win_get_config(win).relative == ""
    and api.nvim_win_get_tabpage(win) == tab
end
local function content_windows(tab)
  return vim.tbl_filter(function(win)
    return ordinary(win, tab)
  end, api.nvim_tabpage_list_wins(tab))
end
local function role(win)
  return vim.bo[api.nvim_win_get_buf(win)].filetype == "neo-tree" and "Tree" or "Editor"
end
-- Remember only actual pane focus. Statusline evaluation can temporarily
-- enter another window through nvim_win_call without any focus event.
function M.focused_window(tab)
  tab = tab or api.nvim_get_current_tabpage()
  if ordinary(focused[tab], tab) then
    return focused[tab]
  end
  local current = api.nvim_get_current_win()
  focused[tab] = ordinary(current, tab) and current
    or (ordinary(previous[tab], tab) and previous[tab])
    or content_windows(tab)[1]
  return focused[tab]
end
local function remember_focus()
  local win, tab = api.nvim_get_current_win(), api.nvim_get_current_tabpage()
  if ordinary(win, tab) then
    focused[tab] = win
  end
end
local function edge(win, name)
  local weight = M.focused_window(api.nvim_win_get_tabpage(win)) == win and "active" or "normal"
  return require("config.shapes")["edge_" .. weight .. "_" .. name]
end
local function scratch()
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "workbench-frame"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  return buf
end
local function lines(win, value)
  local buf = api.nvim_win_get_buf(win)
  if vim.deep_equal(api.nvim_buf_get_lines(buf, 0, -1, false), value) then
    return
  end
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, value)
  vim.bo[buf].modifiable = false
end
local function rail(win, side)
  return api.nvim_open_win(scratch(), false, {
    split = side,
    win = win,
    width = 1,
    focusable = false,
    mouse = false,
    noautocmd = true,
  })
end
local function close_state(state)
  for _, item in pairs(state) do
    if type(item) == "number" and M.is_frame(item) then
      pcall(api.nvim_win_close, item, true)
    end
  end
end
local function configure(railwin, win, side)
  local r, p = role(win), api.nvim_win_get_position(win)
  local special = r == "Editor"
    and p[1] == 1
    and vim.bo[api.nvim_win_get_buf(win)].filetype ~= "ministarter"
  local compact = special or (r == "Tree" and p[1] == 1)
  local wh = "Normal:Workbench"
    .. r
    .. "Fill,NormalNC:Workbench"
    .. r
    .. "Fill,EndOfBuffer:Workbench"
    .. r
    .. "Fill,WinSeparator:Workbench"
    .. (side == "left" and r .. "Fill" or "Chrome")
    .. ",StatusLine:Workbench"
    .. (side == "left" and r .. "Fill" or "Chrome")
    .. ",StatusLineNC:Workbench"
    .. (side == "left" and r .. "Fill" or "Chrome")
  local options = {
    winfixwidth = true,
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    statuscolumn = "",
    wrap = false,
    list = false,
    cursorline = false,
    cursorcolumn = false,
    spell = false,
    foldenable = false,
    winhighlight = wh,
    winbar = compact and "" or ("%#Workbench" .. r .. "Fill#" .. (p[1] > 1 and edge(
      win,
      "top_" .. side
    ) or edge(win, side))),
    statusline = "%#Workbench"
      .. r
      .. "Fill#"
      .. edge(win, "bottom_" .. side)
      .. (side == "right" and "%#WorkbenchChrome#" or "")
      .. "%=",
    fillchars = "eob: ,vert: ,stl:"
      .. (side == "left" and edge(win, "bottom") or " ")
      .. ",stlnc:"
      .. (side == "left" and edge(win, "bottom") or " "),
  }
  for name, value in pairs(options) do
    if vim.wo[railwin][name] ~= value then
      vim.wo[railwin][name] = value
    end
  end
  local rows = {}
  for index = 1, math.max(1, api.nvim_win_get_height(win) - (compact and 0 or 1)) do
    -- An inactive first tab is inset one header cell, so its left side meets
    -- the editor's rounded roof. A selected first tab owns the outer corner
    -- itself and continues into a straight body rail without a second bend.
    local rounded = side == "right" or not require("config.tabs").first_selected(win)
    rows[index] = special and index == 1 and rounded and edge(win, "body_top_" .. side)
      or edge(win, side)
  end
  lines(railwin, rows)
  api.nvim_win_set_cursor(railwin, { 1, 0 })
end
local function float(state, key, row, col, text, width, height, highlight)
  local win = state[key]
  local config = {
    relative = "editor",
    row = row,
    col = col,
    width = width or 1,
    height = height or 1,
    border = "none",
    focusable = false,
    mouse = false,
    zindex = 20,
    style = "minimal",
  }
  if not M.is_frame(win) then
    config.noautocmd = true
    win = api.nvim_open_win(scratch(), false, config)
    state[key] = win
  else
    api.nvim_win_set_config(win, config)
  end
  lines(win, type(text) == "table" and text or { text })
  vim.wo[win].winbar = ""
  vim.wo[win].statusline = ""
  vim.wo[win].winhighlight = "Normal:" .. highlight .. ",NormalNC:" .. highlight
end
function M.panes()
  local panes, tab = {}, api.nvim_get_current_tabpage()
  for win, state in pairs(states) do
    if ordinary(win, tab) and M.is_frame(state.left) and M.is_frame(state.right) then
      local p = api.nvim_win_get_position(win)
      panes[#panes + 1] = {
        win = win,
        row = p[1],
        col = p[2],
        width = api.nvim_win_get_width(win),
        height = api.nvim_win_get_height(win),
        left = api.nvim_win_get_position(state.left)[2],
        right = api.nvim_win_get_position(state.right)[2],
        role = role(win),
        focused = M.focused_window(tab) == win,
      }
    end
  end
  table.sort(panes, function(a, b)
    return a.row == b.row and a.left < b.left or a.row < b.row
  end)
  return panes
end
function M.refresh()
  pending = false
  if busy or vim.v.exiting ~= vim.NIL then
    return
  end
  local tab, windows =
    api.nvim_get_current_tabpage(), content_windows(api.nvim_get_current_tabpage())
  if #windows == 0 then
    return
  end
  busy = true
  if vim.o.columns < 24 or vim.o.lines < 8 then
    M.compact = true
    -- Reclaim decoration columns in tiny views, rather than leaving old
    -- rails behind while the footer has already fallen back to native UI.
    local ok, err = pcall(function()
      for win, state in pairs(states) do
        if not api.nvim_win_is_valid(win) or api.nvim_win_get_tabpage(win) == tab then
          close_state(state)
          states[win] = nil
        end
      end
      vim.o.showtabline = 0
      require("config.footer").ensure()
      for _, win in ipairs(windows) do
        if api.nvim_win_is_valid(win) then
          local r = role(win)
          vim.wo[win].winbar = ""
          vim.wo[win].statusline = "%#Workbench"
            .. r
            .. "Fill# "
            .. (r == "Tree" and "EXPLORER" or "%f")
            .. "%=%l:%c "
          local fc = vim.wo[win].fillchars
          for kind, value in pairs({ vert = "│", stl = " ", stlnc = " " }) do
            if fc:find(kind .. ":", 1, true) then
              fc = fc:gsub(kind .. ":[^,]+", kind .. ":" .. value)
            else
              fc = fc .. (fc == "" and "" or ",") .. kind .. ":" .. value
            end
          end
          vim.wo[win].fillchars = fc
        end
      end
      -- A fixed-width tree can consume almost every remaining column after
      -- shrinking. Reflow the content before Neovim paints the narrow grid;
      -- restoring winfixwidth keeps normal sidebar resizing behavior intact.
      local fixed = {}
      for _, win in ipairs(windows) do
        if api.nvim_win_is_valid(win) then
          fixed[win] = vim.wo[win].winfixwidth
          vim.wo[win].winfixwidth = false
        end
      end
      local equalized, reason = pcall(vim.cmd, "wincmd =")
      for win, value in pairs(fixed) do
        if api.nvim_win_is_valid(win) then
          vim.wo[win].winfixwidth = value
        end
      end
      if not equalized then
        error(reason)
      end
    end)
    busy = false
    if not ok then
      vim.notify("Compact layout: " .. tostring(err), vim.log.levels.WARN)
    end
    return
  end
  M.compact = false
  if vim.o.showtabline ~= 2 then
    vim.o.showtabline = 2
  end
  local minwidth = vim.o.winminwidth
  vim.o.winminwidth = 1
  local ok, err = pcall(function()
    require("config.footer").ensure()
    for win, state in pairs(states) do
      if not api.nvim_win_is_valid(win) then
        close_state(state)
        states[win] = nil
      end
    end
    for _, win in ipairs(windows) do
      local state = states[win] or {}
      states[win] = state
      for _, side in ipairs({ "left", "right" }) do
        if not M.is_frame(state[side]) then
          state[side] = rail(win, side)
        end
        local p, q = api.nvim_win_get_position(win), api.nvim_win_get_position(state[side])
        local expected = side == "left" and p[2] - 2 or p[2] + api.nvim_win_get_width(win) + 1
        if
          q[1] ~= p[1]
          or q[2] ~= expected
          or api.nvim_win_get_height(state[side]) ~= api.nvim_win_get_height(win)
        then
          api.nvim_win_set_config(state[side], { split = side, win = win, width = 1 })
        end
        if api.nvim_win_get_width(state[side]) ~= 1 then
          api.nvim_win_set_width(state[side], 1)
        end
      end
    end
    -- Finish all native splits before calculating header budgets and corners.
    require("config.tabs").prepare()
    for _, win in ipairs(windows) do
      local state = states[win]
      for _, side in ipairs({ "left", "right" }) do
        configure(state[side], win, side)
      end
      local r, p = role(win), api.nvim_win_get_position(win)
      local wh = vim.wo[win].winhighlight
      for _, group in ipairs({ "WinSeparator", "StatusLine", "StatusLineNC" }) do
        wh = wh:gsub(",?" .. group .. ":[^,]+", "")
      end
      vim.wo[win].winhighlight = wh
        .. (wh == "" and "" or ",")
        .. "WinSeparator:Workbench"
        .. r
        .. "Fill,StatusLine:Workbench"
        .. r
        .. "Fill,StatusLineNC:Workbench"
        .. r
        .. "Fill"
      local fc = vim.wo[win].fillchars
      for kind, value in pairs({
        vert = " ",
        stl = edge(win, "bottom"),
        stlnc = edge(win, "bottom"),
      }) do
        if fc:find(kind .. ":", 1, true) then
          fc = fc:gsub(kind .. ":[^,]+", kind .. ":" .. value)
        else
          fc = fc .. (fc == "" and "" or ",") .. kind .. ":" .. value
        end
      end
      vim.wo[win].fillchars = fc
      vim.wo[win].statusline = "%#Workbench" .. r .. "Fill#" .. edge(win, "bottom") .. "%="
      vim.wo[win].winbar = r == "Tree" and (p[1] == 1 and "" or "%!v:lua.WorkbenchExplorerHeader()")
        or (
          p[1] == 1
            and (vim.bo[api.nvim_win_get_buf(win)].filetype == "ministarter" and "%!v:lua.WorkbenchPaneHeader()" or "")
          or "%!v:lua.WorkbenchLowerHeader()"
        )
      local topedge = p[1] > 1 and edge(win, "top") or nil
      for _, side in ipairs({ "left", "right" }) do
        local key = "bridge_" .. side
        if topedge then
          float(
            state,
            key,
            p[1],
            side == "left" and p[2] - 1 or p[2] + api.nvim_win_get_width(win),
            topedge,
            1,
            1,
            "Workbench" .. r .. "Fill"
          )
        elseif M.is_frame(state[key]) then
          api.nvim_win_close(state[key], true)
          state[key] = nil
        end
      end
    end
    local boundary = require("config.resize").boundary()
    for win, state in pairs(states) do
      if ordinary(win, tab) then
        if boundary and boundary.tree.win == win then
          local col = math.floor((boundary.first + boundary.last) / 2)
          float(
            state,
            "grip",
            math.floor((boundary.top + boundary.bottom) / 2),
            col,
            "⋮",
            1,
            1,
            "WorkbenchDividerGrip"
          )
        elseif M.is_frame(state.grip) then
          api.nvim_win_close(state.grip, true)
          state.grip = nil
        end
      end
    end
    vim.cmd.redrawtabline()
    require("config.footer").refresh()
  end)
  vim.o.winminwidth = minwidth
  busy = false
  if not ok then
    vim.notify("Pane border: " .. tostring(err), vim.log.levels.WARN)
  end
end
local function schedule()
  if busy or pending then
    return
  end
  pending = true
  vim.schedule(M.refresh)
end
function M.move(direction)
  local current = api.nvim_get_current_win()
  local p = api.nvim_win_get_position(current)
  local w, h = api.nvim_win_get_width(current), api.nvim_win_get_height(current)
  local cx, cy = p[2] + w / 2, p[1] + h / 2
  local best, score
  for _, win in ipairs(content_windows(api.nvim_get_current_tabpage())) do
    if win ~= current then
      local q = api.nvim_win_get_position(win)
      local dx = q[2] + api.nvim_win_get_width(win) / 2 - cx
      local dy = q[1] + api.nvim_win_get_height(win) / 2 - cy
      local tw, th = api.nvim_win_get_width(win), api.nvim_win_get_height(win)
      local horizontal = direction == "h" or direction == "l"
      local main, cross = horizontal and dx or dy, horizontal and dy or dx
      local overlap = horizontal and (math.min(p[1] + h, q[1] + th) - math.max(p[1], q[1]))
        or (math.min(p[2] + w, q[2] + tw) - math.max(p[2], q[2]))
      local beyond = (direction == "h" and q[2] + tw <= p[2])
        or (direction == "l" and q[2] >= p[2] + w)
        or (direction == "k" and q[1] + th <= p[1])
        or (direction == "j" and q[1] >= p[1] + h)
      if beyond and overlap > 0 then
        local candidate = math.abs(main) + math.abs(cross) * 4
        if not score or candidate < score then
          best, score = win, candidate
        end
      end
    end
  end
  if best then
    api.nvim_set_current_win(best)
  end
end

function M.cycle(step)
  local windows = content_windows(api.nvim_get_current_tabpage())
  table.sort(windows)
  if #windows == 0 then
    return
  end
  local current, index = api.nvim_get_current_win(), 1
  for position, win in ipairs(windows) do
    if win == current then
      index = position
      break
    end
  end
  local count = vim.v.count
  api.nvim_set_current_win(
    windows[count > 0 and math.min(count, #windows) or ((index - 1 + step) % #windows + 1)]
  )
end

local function remove(tab)
  busy = true
  for win, state in pairs(states) do
    if not api.nvim_win_is_valid(win) or api.nvim_win_get_tabpage(win) == tab then
      close_state(state)
      states[win] = nil
    end
  end
  busy = false
end

function M.setup()
  require("config.footer").ensure()
  require("config.resize").setup()
  local group = api.nvim_create_augroup("WorkbenchNativeFrame", { clear = true })
  api.nvim_create_autocmd("WinLeave", {
    group = group,
    callback = function()
      local win, tab = api.nvim_get_current_win(), api.nvim_get_current_tabpage()
      if ordinary(win, tab) then
        previous[tab] = win
      end
    end,
  })
  api.nvim_create_autocmd({ "WinEnter", "TabEnter" }, {
    group = group,
    callback = function()
      if busy then
        return
      end
      local win, tab = api.nvim_get_current_win(), api.nvim_get_current_tabpage()
      if M.is_frame(win) then
        local target = previous[tab]
        if not ordinary(target, tab) then
          target = content_windows(tab)[1]
        end
        if target then
          api.nvim_set_current_win(target)
        end
      end
      remember_focus()
      schedule()
    end,
  })
  api.nvim_create_autocmd("QuitPre", {
    group = group,
    callback = function()
      require("config.footer").remove()
      remove(api.nvim_get_current_tabpage())
      schedule()
    end,
  })
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(event)
      if busy then
        return
      end
      local win = tonumber(event.match)
      if states[win] then
        local tab = api.nvim_get_current_tabpage()
        if #content_windows(tab) == 1 then
          if #api.nvim_list_tabpages() > 1 then
            vim.schedule(function()
              if api.nvim_tabpage_is_valid(tab) then
                remove(tab)
                require("config.footer").remove(tab)
              end
              schedule()
            end)
          else
            require("config.footer").remove()
            remove(tab)
          end
        else
          -- :tabclose/:only may already be iterating the native windows.
          -- Mutating that list here can abort it with E445, even when no
          -- content is modified. Clean orphaned rails after the close ends.
          local state = states[win]
          states[win] = nil
          vim.schedule(function()
            local was_busy = busy
            busy = true
            close_state(state)
            busy = was_busy
            schedule()
          end)
        end
      end
      schedule()
    end,
  })
  api.nvim_create_autocmd({
    "VimEnter",
    "UIEnter",
    "BufWinEnter",
    "BufEnter",
    "BufModifiedSet",
    "WinNew",
    "TabEnter",
    "VimResized",
    "WinResized",
    "ColorScheme",
  }, {
    group = group,
    callback = function(event)
      if
        (event.event == "VimResized" or event.event == "WinResized")
        and (vim.o.columns < 24 or vim.o.lines < 8)
      then
        -- Tiny native grids must be made valid before the next redraw.
        M.refresh()
      else
        schedule()
      end
    end,
  })
  for _, direction in ipairs({ "h", "j", "k", "l" }) do
    vim.keymap.set("n", "<C-w>" .. direction, function()
      M.move(direction)
    end, { desc = "Focus pane " .. direction })
  end
  vim.keymap.set("n", "<C-w>w", function()
    M.cycle(1)
  end, { desc = "Next pane" })
  vim.keymap.set("n", "<C-w><C-w>", function()
    M.cycle(1)
  end, { desc = "Next pane" })
  vim.keymap.set("n", "<C-w>W", function()
    M.cycle(-1)
  end, { desc = "Previous pane" })
  remember_focus()
  schedule()
end

return M
