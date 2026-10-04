-- Fixed-scale, syntax-coloured Braille: never stretch text into solid blocks.
local M = {}
local api = vim.api
local bit = require("bit")
local dots = { { 1, 8 }, { 2, 16 }, { 4, 32 }, { 64, 128 } }
local highlights = {}

function M.reset_colors()
  highlights = {}
end

local function ink(group)
  if not group or group == "" then
    return "WorkbenchMinimap"
  end
  if highlights[group] then
    return highlights[group]
  end
  local color = api.nvim_get_hl(0, { name = group, link = false }).fg
  if not color then
    highlights[group] = "WorkbenchMinimap"
    return "WorkbenchMinimap"
  end
  local name = string.format("WorkbenchMinimapInk%06x", color)
  -- Foreground only: viewport shading remains visible under syntax colours.
  api.nvim_set_hl(0, name, { fg = color })
  highlights[group] = name
  return name
end

-- Four source lines per terminal cell, with a scrolling slice for long files.
-- The slice follows the editor viewport rather than jumping on every keystroke.
function M.region(count, height, first, last, cursor)
  local total = math.ceil(count / 4)
  local fraction = math.max(0, math.min(1, ((first + last) / 2 - 1) / math.max(1, count - 1)))
  local maximum = math.max(0, total - height)
  local offset = math.floor(maximum * fraction)
  local low, high =
    math.max(0, math.ceil(last / 4) - height), math.min(maximum, math.floor((first - 1) / 4))
  -- Proportional placement alone can cut off the start/end of the document.
  -- Keep the entire visible range whenever it fits inside the code slice.
  if low <= high then
    offset = math.max(low, math.min(high, offset))
  end
  -- Closed folds can make w0..w$ span more source lines than fit. Even then,
  -- the actual cursor must be in the slice, not falsely clamped onto an edge.
  local focus = math.floor(((cursor or math.floor((first + last) / 2)) - 1) / 4)
  offset = math.max(0, math.min(maximum, math.min(focus, math.max(offset, focus - height + 1))))
  return offset, math.min(total - offset, height)
end

-- Byte coordinates refer to the original text. Display columns account for
-- tabs, wide characters and combining marks before any horizontal compression.
local function points(text, tabstop, vartabstop, limit)
  local result, column, byte = {}, 0, 0
  for _, char in ipairs(vim.fn.split(vim.fn.strcharpart(text, 0, limit), "\\zs")) do
    if column >= limit then
      break
    end
    local width = vim.fn.strdisplaywidth(char)
    if char == "\t" then
      local stop = 0
      for _, step in ipairs(vartabstop) do
        stop = stop + step
        if stop > column then
          break
        end
      end
      local step = vartabstop[#vartabstop] or tabstop
      column = stop > column and stop or column + step - ((column - stop) % step)
    else
      if not char:match("^%s+$") and char ~= " " and width > 0 then
        for extra = 0, math.min(width, limit - column) - 1 do
          result[#result + 1] = { column = column + extra, byte = byte, priority = -1 }
        end
      end
      column = column + width
    end
    byte = byte + #char
  end
  return result
end

local function tree_colors(buf, rows, start, finish)
  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if not ok or not parser then
    return false
  end
  local painted = false
  -- Public Tree-sitter queries, including injected languages. A missing parser
  -- or query is a normal fallback, not a startup error or a download request.
  ok = pcall(function()
    parser:parse({ start, finish })
    parser:for_each_tree(function(tree, language)
      local lang = language:lang()
      local query = vim.treesitter.query.get(lang, "highlights")
      if not query then
        return
      end
      local depth, parent = 0, language:parent()
      while parent do
        depth, parent = depth + 1, parent:parent()
      end
      for id, node, metadata in query:iter_captures(tree:root(), buf, start, finish) do
        local capture = metadata[id] or {}
        local range = vim.treesitter.get_range(node, buf, capture)
        local sr, sc, er, ec = range[1], range[2], range[4], range[5]
        local group = "@" .. query.captures[id]
        local specific = group .. "." .. lang
        if api.nvim_get_hl(0, { name = specific, link = false }).fg then
          group = specific
        end
        local priority = depth * 10000 + (tonumber(capture.priority or metadata.priority) or 100)
        for row = math.max(start, sr), math.min(finish - 1, er) do
          local from, to = row == sr and sc or 0, row == er and ec or math.huge
          for _, point in ipairs(rows[row - start + 1] or {}) do
            if point.byte >= from and point.byte < to and point.priority <= priority then
              point.group, point.priority = group, priority
              painted = true
            end
          end
        end
      end
    end)
  end)
  return ok and painted
end

function M.encode(buf, opts)
  local start = opts.offset * 4
  local finish = math.min(api.nvim_buf_line_count(buf), start + opts.height * 4)
  local source = api.nvim_buf_get_lines(buf, start, finish, false)
  local tabstop = vim.bo[buf].tabstop
  local vartabstop = {}
  for value in vim.bo[buf].vartabstop:gmatch("%d+") do
    vartabstop[#vartabstop + 1] = tonumber(value)
  end
  local rows = {}
  local limit = math.min(opts.max_columns, opts.width * 2 * opts.column_scale)
  for index, text in ipairs(source) do
    rows[index] = points(text, tabstop, vartabstop, limit)
  end
  local colored = tree_colors(buf, rows, start, finish)
  if not colored and opts.source_win then
    api.nvim_win_call(opts.source_win, function()
      for index, row in ipairs(rows) do
        for _, point in ipairs(row) do
          point.group = vim.fn.synIDattr(vim.fn.synID(start + index, point.byte + 1, 1), "name")
        end
      end
    end)
  end
  local cells = {}
  for index, row in ipairs(rows) do
    local y = math.floor((index - 1) / 4) + 1
    cells[y] = cells[y] or {}
    for _, point in ipairs(row) do
      local x = math.floor(point.column / opts.column_scale)
      local col = math.floor(x / 2) + 1
      local cell = cells[y][col] or { mask = 0, groups = {} }
      cells[y][col] = cell
      cell.mask = bit.bor(cell.mask, dots[(index - 1) % 4 + 1][x % 2 + 1])
      local group = ink(point.group or "WorkbenchMinimap")
      cell.groups[group] = (cell.groups[group] or 0) + 1
    end
  end
  local lines, spans = {}, {}
  for y = 1, math.max(1, math.ceil(#source / 4)) do
    local chars, previous, run, byte = {}, nil, nil, 0
    for x = 1, opts.width do
      local cell = (cells[y] or {})[x]
      local char = cell and vim.fn.nr2char(0x2800 + cell.mask) or " "
      chars[x] = char
      local group, weight = "WorkbenchMinimap", -1
      if cell then
        -- Sorted ties make syntax colour choice reproducible across refreshes.
        for _, name in ipairs(vim.tbl_keys(cell.groups)) do
          local score = cell.groups[name]
          if score > weight or (score == weight and name < group) then
            group, weight = name, score
          end
        end
      end
      if group ~= previous then
        if run then
          run.finish = byte
        end
        run = { row = y - 1, start = byte, group = group }
        spans[#spans + 1] = run
        previous = group
      end
      byte = byte + #char
    end
    run.finish = byte
    lines[y] = table.concat(chars)
  end
  return lines, spans
end

return M
