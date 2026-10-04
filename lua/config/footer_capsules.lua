local M = {}
local api = vim.api
local builtin = { [""] = "left", [""] = "right" }

local function attributes(groups)
  local result = {}
  for _, name in ipairs(groups) do
    for key, value in pairs(api.nvim_get_hl(0, { name = name, link = false })) do
      result[key] = value
    end
  end
  return result
end

local function palette_key(color)
  local c = vim.g.workbench_colors
  for _, key in ipairs({ "lavender", "teal", "peach", "red", "overlay" }) do
    if color == tonumber(c[key]:sub(2), 16) then
      return key
    end
  end
end

local function glyph(key, side)
  if vim.g.workbench_round_tabs == false then
    return
  end
  local shapes = require("config.shapes")
  return shapes["capsule_" .. key .. "_" .. side] or shapes["edge_capsule_" .. key .. "_" .. side]
end

local function cap_style(key, accent, solid)
  local c = vim.g.workbench_colors
  local name = "WorkbenchFooterCapsule" .. key .. (solid and "Cut" or "Legacy")
  local fg, bg = solid and c.chrome or accent, solid and accent or c.base
  local current = api.nvim_get_hl(0, { name = name, link = false })
  local fg_num = type(fg) == "number" and fg or tonumber(fg:sub(2), 16)
  local bg_num = type(bg) == "number" and bg or tonumber(bg:sub(2), 16)
  if current.fg ~= fg_num or current.bg ~= bg_num or current.nocombine ~= true then
    api.nvim_set_hl(0, name, { fg = fg, bg = bg, nocombine = true })
  end
  return { name }
end

-- Lualine still supplies the text, padding, truncation and ordinary highlights.
-- Its E0B4/E0B6 separator cells are replaced after evaluation so every capsule
-- joins the exact full-height background of its text, with one shared exterior.
function M.decorate(line)
  if type(line) ~= "table" or type(line.str) ~= "string" then
    return line
  end
  local source = line.highlights or {}
  local chunks, highlights, capsules = {}, {}, {}
  local index, start = 1, 0
  local last_groups
  local cache = {}
  local function groups_at(byte)
    local current = index
    while current > 1 and source[current].start > byte do
      current = current - 1
    end
    while source[current + 1] and source[current + 1].start <= byte do
      current = current + 1
    end
    local found = source[current]
    return found and (found.groups or { found.group }) or { "StatusLine" }
  end
  for position, original in line.str:gmatch("()([%z\1-\127\194-\244][\128-\191]*)") do
    local old_start = position - 1
    while source[index + 1] and source[index + 1].start <= old_start do
      index = index + 1
    end
    local item = source[index]
    local groups = item and (item.groups or { item.group }) or { "StatusLine" }
    local character = original
    local side = builtin[character]
    local separator = side
      and item
      and (item.group or groups[#groups]):find("lualine_transitional_", 1, true)
    if separator then
      -- The neighbouring text background is authoritative. A transitional
      -- separator's own foreground can be stale after a mode/theme refresh.
      local body_groups = groups_at(side == "left" and old_start + #original or old_start - 1)
      local signature = table.concat(body_groups, "\0")
      cache[signature] = cache[signature] or attributes(body_groups)
      local accent = cache[signature].bg
      local key = palette_key(accent)
      if key then
        local custom = glyph(key, side)
        character = custom or character
        groups = cap_style(key, accent, custom ~= nil)
        capsules[#capsules + 1] =
          { start = start, side = side, palette = key, custom = custom ~= nil }
      end
    end
    if not last_groups or not vim.deep_equal(last_groups, groups) then
      highlights[#highlights + 1] = { start = start, groups = groups, group = groups[#groups] }
      last_groups = groups
    end
    chunks[#chunks + 1] = character
    start = start + #character
  end
  local result = vim.tbl_extend("force", line, {
    str = table.concat(chunks),
    highlights = highlights,
    capsules = capsules,
  })
  return result
end

return M
