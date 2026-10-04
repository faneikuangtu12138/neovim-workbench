local M = {}
local bank = require("config.shape_bank")
local panes = require("config.pane_bank")
local edges = require("config.edge_bank")
local enabled = vim.g.workbench_round_tabs ~= false

-- Every corner is an inverse stencil. Its native cell background supplies
-- the full-height surface. All four stencils are only used in tabline row 0.
function M.set_height(value)
  local height = math.floor((tonumber(value) or 1.42) * 100 + 0.5)
  M.height = height / 100
  for name, cp in pairs(edges[height] or edges[142]) do
    M["edge_" .. name] = enabled and vim.fn.nr2char(cp)
      or (
        name:find("mark") and ""
        or name:find("left") and "│"
        or name:find("right") and "│"
        or "─"
      )
  end
  local glyphs = bank[height] or bank[142]
  for name, cp in pairs(panes[height] or panes[142]) do
    M["pane_" .. name] = enabled and vim.fn.nr2char(cp)
      or ({
        cut_top_left = "╭",
        cut_top_right = "╮",
        cut_bottom_left = "╰",
        cut_bottom_right = "╯",
        stroke_top_left = "╭",
        stroke_top_right = "╮",
        stroke_bottom_left = "╰",
        stroke_bottom_right = "╯",
        stroke_vertical = "│",
        stroke_top = "─",
        stroke_bottom = "─",
        stroke_horizontal = "─",
      })[name]
  end
  for index, name in ipairs({ "top_left", "top_right", "join_left", "join_right" }) do
    M[name] = enabled and vim.fn.nr2char(glyphs[index]) or " "
  end
end

-- A configured default never overwrites the cache written by :UiLineHeight.
local cached_height = tonumber(vim.g.workbench_line_height) or 1.42
local cache = vim.g.workbench_ui_state or (vim.fn.stdpath("state") .. "/workbench-ui.json")
if vim.fn.filereadable(cache) == 1 then
  local ok, settings = pcall(vim.json.decode, table.concat(vim.fn.readfile(cache), "\n"))
  if ok and type(settings) == "table" then
    cached_height = tonumber(settings.height) or cached_height
  end
end
M.set_height(cached_height)
return M
