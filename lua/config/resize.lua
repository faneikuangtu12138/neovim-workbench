local M = {}
local api = vim.api
local drag

-- Geometry comes from the real content windows. Decorative rail windows are
-- deliberately excluded: letting Vim resize those produces a one-way gutter.
function M.boundary()
  local panes = require("config.frame").panes()
  for _, tree in ipairs(panes) do
    if tree.role == "Tree" then
      local closest
      for _, pane in ipairs(panes) do
        local overlaps = math.min(tree.row + tree.height, pane.row + pane.height)
          > math.max(tree.row, pane.row)
        if pane.role == "Editor" and overlaps and pane.col > tree.col then
          if not closest or pane.col < closest.col then
            closest = pane
          end
        end
      end
      if closest then
        return {
          tree = tree,
          editor = closest,
          first = tree.col + tree.width,
          last = closest.col - 1,
          top = tree.row,
          bottom = tree.row + tree.height - 1,
        }
      end
    end
  end
end

local function hit(mouse)
  local boundary = M.boundary()
  if not boundary then
    return
  end
  local col, row = mouse.screencol - 1, mouse.screenrow - 1
  if
    col >= boundary.first
    and col <= boundary.last
    and row >= boundary.top
    and row <= boundary.bottom
  then
    return boundary
  end
end

local function remember_width(win)
  local ok, manager = pcall(require, "neo-tree.sources.manager")
  if not ok then
    return
  end
  local state = manager.get_state_for_window(win)
  if state then
    local width = api.nvim_win_get_width(win)
    state.window.width = width
    state.window.last_user_width = width
    -- Keep the source's layout monitor responsible for its tree redraw.
    -- Assigning win_width here would hide the size change from that monitor.
  end
end

function M.handle(action, col)
  if action == "press" then
    local boundary = hit(vim.fn.getmousepos())
    if not boundary then
      return
    end
    drag = {
      win = boundary.tree.win,
      tab = api.nvim_get_current_tabpage(),
      width = api.nvim_win_get_width(boundary.tree.win),
      origin = col,
      focus = api.nvim_get_current_win(),
    }
    return
  end
  local current = drag
  if not current then
    return
  end
  if not api.nvim_win_is_valid(current.win) or current.tab ~= api.nvim_get_current_tabpage() then
    drag = nil
    return
  end
  local boundary = M.boundary()
  if not boundary or boundary.tree.win ~= current.win then
    drag = nil
    return
  end
  local max_width = api.nvim_win_get_width(current.win) + math.max(0, boundary.editor.width - 24)
  local requested =
    math.min(math.max(14, max_width), math.max(14, current.width + col - current.origin))
  if api.nvim_win_get_width(current.win) ~= requested then
    api.nvim_win_set_width(current.win, requested)
    remember_width(current.win)
  end
  if api.nvim_win_is_valid(current.focus) and api.nvim_get_current_win() ~= current.focus then
    api.nvim_set_current_win(current.focus)
  end
  if action == "release" then
    drag = nil
  end
end

local keys = { press = "<LeftMouse>", drag = "<LeftDrag>", release = "<LeftRelease>" }
local function route(action)
  local mouse = vim.fn.getmousepos()
  if (action == "press" and hit(mouse)) or (action ~= "press" and drag) then
    -- Expr mappings may inspect geometry, but window resizing has to run after
    -- textlock has ended. Native events outside the gutter retain Vim behavior.
    return string.format(
      '<Cmd>lua require("config.resize").handle("%s", %d)<CR>',
      action,
      mouse.screencol - 1
    )
  end
  return keys[action]
end

function M.setup()
  for action, key in pairs(keys) do
    vim.keymap.set({ "n", "x", "i" }, key, function()
      return route(action)
    end, { expr = true, silent = true, desc = "Resize sidebar or normal mouse " .. action })
  end
  local group = api.nvim_create_augroup("WorkbenchSidebarResize", { clear = true })
  api.nvim_create_autocmd({ "TabLeave", "VimLeavePre" }, {
    group = group,
    callback = function()
      drag = nil
    end,
  })
end

return M
