local starter = require("mini.starter")
local geometry = {}

local logo = {
  "███████╗ ██████╗ ██████╗  ██████╗ ███████╗",
  "██╔════╝██╔═══██╗██╔══██╗██╔════╝ ██╔════╝",
  "█████╗  ██║   ██║██████╔╝██║  ███╗█████╗  ",
  "██╔══╝  ██║   ██║██╔══██╗██║   ██║██╔══╝  ",
  "██║     ╚██████╔╝██║  ██║╚██████╔╝███████╗",
  "╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝",
}

local function unit(text, kind, hl)
  return { string = text, type = kind or "empty", hl = hl }
end

local function width(line)
  local strings = vim.tbl_map(function(x)
    return x.string
  end, line)
  return vim.fn.strdisplaywidth(table.concat(strings))
end

local function append(target, source)
  for _, part in ipairs(source) do
    target[#target + 1] = part
  end
end

-- Keep padding as separate content units: item names, queries, highlighting,
-- and byte-based cursor positions are calculated by mini.starter afterwards.
local function center_line(line, target_width)
  local pad = math.max(0, math.floor((target_width - width(line)) / 2))
  if width(line) > 0 then
    table.insert(line, 1, unit(string.rep(" ", pad)))
  end
  return line
end

local function dashboard_layout(content, buf)
  -- Starter sets its filetype with noautocmd, so FileType exclusions do not
  -- run here. Disable editor scope guides explicitly on the welcome buffer.
  vim.b[buf].miniindentscope_disable = true
  if _G.MiniIndentscope then
    MiniIndentscope.undraw()
  end
  local win = vim.fn.bufwinid(buf)
  if win < 0 then
    return content
  end
  local win_width = vim.api.nvim_win_get_width(win)
  local win_height = vim.api.nvim_win_get_height(win)
  geometry[buf] = { width = win_width, height = win_height }
  local header, footer, groups = {}, {}, {}
  local group_order = {}

  for _, line in ipairs(content) do
    local first = line[1]
    if first.type == "header" then
      first.string = first.string:gsub("%s+$", "")
      header[#header + 1] = line
    elseif first.type == "footer" then
      footer[#footer + 1] = line
    else
      for _, part in ipairs(line) do
        if part.type == "item" then
          local section = part.item.section
          if not groups[section] then
            groups[section] = {}
            group_order[#group_order + 1] = section
          end
          groups[section][#groups[section] + 1] = line
        end
      end
    end
  end

  if win_height < 30 or win_width < 46 then
    header = {
      { unit("F O R G E", "header", "MiniStarterHeader") },
      { unit("NEOVIM  /  ENGINEERING WORKBENCH", "header", "MiniStarterFooter") },
    }
  end
  if win_width < 60 then
    footer = {
      {
        unit(
          win_width < 40 and "C/C++ · Python · RTL · Scripts"
            or "C/C++ · Python · Verilog/SV · Scripts",
          "footer",
          "MiniStarterFooter"
        ),
      },
      { unit("Enter: open · ↑/↓: select", "footer", "MiniStarterFooter") },
    }
  end
  if win_width < 34 then
    header[2] = { unit("NEOVIM / WORKBENCH", "header", "MiniStarterFooter") }
  end

  local menu_width = 0
  for _, section in ipairs(group_order) do
    menu_width = math.max(menu_width, vim.fn.strdisplaywidth(section) + 4)
    for _, line in ipairs(groups[section]) do
      menu_width = math.max(menu_width, width(line))
    end
  end
  local inner_width = menu_width + 4

  local function card(section)
    local title = "  " .. section:upper() .. "  "
    local remaining = inner_width - vim.fn.strdisplaywidth(title)
    local left = math.floor(remaining / 2)
    local right = remaining - left
    local card_lines = {
      {
        unit("╭" .. string.rep("─", left), "border", "WorkbenchDashboardBorder"),
        unit(title, "section", "MiniStarterSection"),
        unit(string.rep("─", right) .. "╮", "border", "WorkbenchDashboardBorder"),
      },
    }
    local max_rows = #groups[section]
    for row = 1, max_rows do
      local item_line = groups[section][row] or { unit("") }
      local line = { unit("│", "border", "WorkbenchDashboardBorder"), unit(" ") }
      append(line, item_line)
      line[#line + 1] = unit(string.rep(" ", inner_width - width(item_line) - 1))
      line[#line + 1] = unit("│", "border", "WorkbenchDashboardBorder")
      card_lines[#card_lines + 1] = line
    end
    card_lines[#card_lines + 1] = {
      unit("╰" .. string.rep("─", inner_width) .. "╯", "border", "WorkbenchDashboardBorder"),
    }
    return card_lines
  end

  local cards = vim.tbl_map(card, group_order)
  local card_width, gap = inner_width + 2, 4
  local menu = {}
  if #cards == 2 and 2 * card_width + gap <= win_width - 4 then
    -- Equalize side-by-side cards; stacked cards keep their natural height.
    local card_rows = math.max(#cards[1], #cards[2])
    for _, section_card in ipairs(cards) do
      while #section_card < card_rows do
        table.insert(section_card, #section_card, {
          unit("│", "border", "WorkbenchDashboardBorder"),
          unit(string.rep(" ", inner_width)),
          unit("│", "border", "WorkbenchDashboardBorder"),
        })
      end
    end
    for row = 1, card_rows do
      local line = {}
      append(line, cards[1][row])
      line[#line + 1] = unit(string.rep(" ", gap))
      append(line, cards[2][row])
      menu[#menu + 1] = line
    end
  else
    for index, section_card in ipairs(cards) do
      if index > 1 then
        menu[#menu + 1] = { unit("") }
      end
      append(menu, section_card)
    end
  end
  if #menu > win_height then
    -- A short, narrow split cannot contain both stacked cards. Keep the
    -- actionable items and let the pane's own border provide the outline.
    menu = {}
    for _, section in ipairs(group_order) do
      append(menu, groups[section])
    end
  end

  local result = {}
  for _, line in ipairs(header) do
    result[#result + 1] = line
  end
  result[#result + 1] = { unit("") }
  for _, line in ipairs(menu) do
    result[#result + 1] = line
  end
  result[#result + 1] = { unit("") }
  for _, line in ipairs(footer) do
    result[#result + 1] = line
  end
  -- On short split panes, keep all actions and remove decorative spacing first.
  while #result > win_height do
    local removed = false
    for index = #result, 1, -1 do
      if width(result[index]) == 0 then
        table.remove(result, index)
        removed = true
        break
      end
    end
    if not removed then
      for _, kind in ipairs({ "footer", "header" }) do
        for index = #result, 1, -1 do
          if
            vim.tbl_contains(
              vim.tbl_map(function(part)
                return part.type
              end, result[index]),
              kind
            )
          then
            table.remove(result, index)
            removed = true
            break
          end
        end
        if removed then
          break
        end
      end
      if not removed then
        break
      end
    end
  end
  -- Measure after shortening the content; removed footer/header widths must
  -- not leave a stale horizontal offset on a small split.
  local target_width = 0
  for _, line in ipairs(result) do
    target_width = math.max(target_width, width(line))
  end
  for _, line in ipairs(result) do
    center_line(line, target_width)
  end
  return result
end

starter.setup({
  evaluate_single = false,
  header = table.concat(
    vim.list_extend(vim.deepcopy(logo), { "", "N E O V I M  /  E N G I N E E R I N G" }),
    "\n"
  ),
  items = {
    {
      name = "Find file",
      action = "lua require('telescope.builtin').find_files({ cwd = require('core.navigation').project_root() })",
      section = "Workspace",
    },
    {
      name = "Search text",
      action = "lua require('telescope.builtin').live_grep({ cwd = require('core.navigation').project_root() })",
      section = "Workspace",
    },
    {
      name = "Explorer",
      action = "lua require('core.navigation').focus_tree()",
      section = "Workspace",
    },
    { name = "New file", action = "enew | startinsert", section = "Workspace" },
    { name = "Recent files", action = "Telescope oldfiles", section = "Workspace" },
    {
      name = "Configuration",
      action = "lua require('telescope.builtin').find_files({ cwd = vim.fn.stdpath('config') })",
      section = "Setup",
    },
    { name = "Language tools", action = "Mason", section = "Setup" },
    { name = "Health check", action = "DevTools", section = "Setup" },
    { name = "Quit", action = "qa", section = "Setup" },
  },
  content_hooks = {
    starter.gen_hook.adding_bullet("  "),
    dashboard_layout,
    starter.gen_hook.aligning("center", "center"),
  },
  footer = "C / C++   ·   Python   ·   Verilog / SV   ·   Scripting\nEnter: open   ·   ↑ / ↓: select   ·   Space: commands",
})

-- mini.starter handles VimResized, but creating or resizing a sidebar changes
-- the editor window without changing the terminal size. Rebuild its content
-- only after the split layout has settled, using the actual dashboard window.
local pending = false
local function refresh_resized()
  if pending then
    return
  end
  pending = true
  vim.schedule(function()
    pending = false
    if vim.v.exiting ~= vim.NIL then
      return
    end
    local visited = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buf = vim.api.nvim_win_get_buf(win)
      if not visited[buf] and vim.bo[buf].filetype == "ministarter" then
        visited[buf] = true
        local dimensions = geometry[buf]
        local width_now = vim.api.nvim_win_get_width(win)
        local height_now = vim.api.nvim_win_get_height(win)
        if not dimensions or dimensions.width ~= width_now or dimensions.height ~= height_now then
          -- Refresh updates item coordinates, so remember the selected action
          -- and use Starter's public navigation API to select it again.
          local cursor = vim.api.nvim_win_get_cursor(win)
          local selected
          for _, item in ipairs(starter.content_to_items(starter.get_content(buf))) do
            if vim.deep_equal(item._cursorpos, cursor) then
              selected = { name = item.name, section = item.section }
              break
            end
          end
          starter.refresh(buf)
          if selected then
            local items = starter.content_to_items(starter.get_content(buf))
            for _, item in ipairs(items) do
              if item.name == selected.name and item.section == selected.section then
                for _ = 1, #items do
                  if vim.deep_equal(vim.api.nvim_win_get_cursor(win), item._cursorpos) then
                    break
                  end
                  starter.update_current_item("next", buf)
                end
                break
              end
            end
          end
        end
      end
    end
  end)
end

local group = vim.api.nvim_create_augroup("WorkbenchDashboardLayout", { clear = true })
vim.api.nvim_create_autocmd({ "WinResized", "WinEnter", "WinClosed", "BufWinEnter", "TabEnter" }, {
  group = group,
  callback = refresh_resized,
})
vim.api.nvim_create_autocmd("BufWipeout", {
  group = group,
  callback = function(event)
    geometry[event.buf] = nil
  end,
})
