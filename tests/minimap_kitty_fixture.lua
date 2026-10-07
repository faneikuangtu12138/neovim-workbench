local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
package.path = root .. "/lua/?.lua;" .. package.path
local kitty = require("config.minimap_kitty")
local shadows = require("config.minimap_shadows")
local cases = vim.json.decode(table.concat(vim.fn.readfile(arg[1]), "\n"))
local results = {}
for _, model in ipairs(cases) do
  local rectangles, tiles = shadows.rectangles(model, model, model.char_width), {}
  for row = 1, model.pixel_height / model.cell_height do
    local _, encode = kitty.shade(rectangles, row, model)
    local data, compressed = encode()
    tiles[#tiles + 1] = { data = data, compressed = compressed }
  end
  results[#results + 1] = tiles
end
io.stdout:write(vim.json.encode(results))
