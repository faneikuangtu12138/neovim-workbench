-- Called by test_minimap_pixels.py, with an explicit temporary JSON fixture.
local root = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)))
vim.opt.rtp:prepend(root)
local source = assert(io.open(arg[1], "r"))
local cases = vim.json.decode(source:read("*a"))
source:close()
local shadows = require("config.minimap_shadows")
local result = {}
for _, model in ipairs(cases) do
  local rectangles = shadows.rectangles(model, model, model.char_width)
  local tiles = {}
  for row = 1, model.pixel_height / model.cell_height do
    local _, tile = shadows.tile(rectangles, row, model)
    tiles[#tiles + 1] = tile
  end
  result[#result + 1] = tiles
end
io.stdout:write(vim.json.encode(result) .. "\n")
