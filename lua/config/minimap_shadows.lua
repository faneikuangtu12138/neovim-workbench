-- Independent viewport/selection layer. No Python, fonts or code parsing.
local M = {}

local function round(value)
  return math.floor(value + 0.5)
end

function M.rectangles(model, rendered, advance)
  local width, height = model.pixel_width, model.pixel_height
  local step = model.cell_height / rendered.resolution
  local origin = rendered.offset * rendered.resolution
  if rendered.large then
    step, origin = height / math.max(1, model.count), 0
  end
  local result = {}
  local function add(first, last, color, left, right)
    local top, bottom = round((first - 1 - origin) * step), round((last - origin) * step)
    if rendered.large and first >= 1 and first <= model.count then
      bottom = math.max(top + 1, bottom)
    end
    top, bottom = math.max(0, top), math.min(height, bottom)
    left, right = math.max(0, left or 0), math.min(width, right or width)
    if bottom > top and right > left then
      result[#result + 1] = { left, top, right, bottom, color }
    end
  end
  add(model.viewport[1], model.viewport[2], 0)
  local selection = model.selection
  local padding = math.max(2, round(model.cell_width * 0.55))
  if not selection then
    add(model.cursor, model.cursor, 1)
  elseif selection.kind == "line" then
    add(selection.first, selection.last, 1)
  elseif selection.kind == "block" then
    add(
      selection.first,
      selection.last,
      1,
      math.floor(padding + selection.start_col * advance),
      math.ceil(padding + selection.end_col * advance)
    )
  else
    local left = math.floor(padding + selection.start_col * advance)
    local right = math.ceil(padding + selection.end_col * advance)
    if selection.first == selection.last then
      add(selection.first, selection.last, 1, left, right)
    else
      add(selection.first, selection.first, 1, left)
      if selection.last > selection.first + 1 then
        add(selection.first + 1, selection.last - 1, 1)
      end
      add(selection.last, selection.last, 1, 0, right)
    end
  end
  return result
end

function M.tile(rectangles, row, model)
  local top = (row - 1) * model.cell_height
  local height = math.min(model.cell_height, model.pixel_height - top)
  local clipped, key = {}, { model.view_background, model.active_background }
  for _, rectangle in ipairs(rectangles) do
    local first, last = math.max(top, rectangle[2]), math.min(top + height, rectangle[4])
    if first < last then
      local rect = { rectangle[1], first - top, rectangle[3], last - top, rectangle[5] }
      clipped[#clipped + 1] = rect
      vim.list_extend(key, rect)
    end
  end
  local signature = table.concat(key, ":")
  if #clipped == 0 then
    return signature, ""
  end
  local sequence = { "\27P0;1q", string.format('"1;1;%d;%d', model.pixel_width, height) }
  for index, color in ipairs({ model.view_background, model.active_background }) do
    sequence[#sequence + 1] = string.format(
      "#%d;2;%d;%d;%d",
      index - 1,
      round(math.floor(color / 65536) * 100 / 255),
      round((math.floor(color / 256) % 256) * 100 / 255),
      round((color % 256) * 100 / 255)
    )
  end
  local function run(amount, char)
    return amount >= 4 and ("!" .. amount .. char) or string.rep(char, amount)
  end
  -- Rectangles are composited in order: viewport, then caret/selection.
  for band = 0, height - 1, 6 do
    for _, rect in ipairs(clipped) do
      local first, last = math.max(band, rect[2]), math.min(band + 6, rect[4], height)
      if first < last then
        local mask = 2 ^ (last - band) - 2 ^ (first - band)
        sequence[#sequence + 1] = "#"
          .. rect[5]
          .. run(rect[1], "?")
          .. run(rect[3] - rect[1], string.char(63 + mask))
          .. "$"
      end
    end
    if band + 6 < height then
      sequence[#sequence + 1] = "-"
    end
  end
  sequence[#sequence + 1] = "\27\\"
  return signature, table.concat(sequence)
end

return M
