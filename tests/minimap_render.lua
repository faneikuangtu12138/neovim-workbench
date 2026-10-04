-- Source-glyph model checks; run with the full Workbench configuration.
local api = vim.api
local renderer = require("config.minimap_render")
local checks, buffers = {}, {}
local function check(name, action)
  action()
  checks[#checks + 1] = name
end
local function source(lines, filetype)
  local buf = api.nvim_create_buf(false, true)
  buffers[#buffers + 1] = buf
  api.nvim_win_set_buf(0, buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].tabstop, vim.bo[buf].vartabstop = 4, ""
  vim.bo[buf].filetype = filetype or ""
  return buf
end
local function document(buf, opts)
  return renderer.document(
    buf,
    vim.tbl_extend("force", {
      height = 30,
      offset = 0,
      resolution = 3,
      max_columns = 120,
      source_win = api.nvim_get_current_win(),
    }, opts or {})
  )
end
local function palette(rows)
  local colors = {}
  for _, row in ipairs(rows) do
    for _, glyph in ipairs(row) do
      assert(type(glyph.char) == "string" and type(glyph.color) == "number")
      colors[glyph.color] = true
    end
  end
  return vim.tbl_count(colors)
end
local ok, failure = xpcall(function()
  check("letters, numbers and punctuation remain actual source glyphs", function()
    local rows = document(source({ "wire a = 42;", "fire a = 42;" }))
    assert(rows[1][1].char == "w" and rows[2][1].char == "f")
    local chars = {}
    for _, glyph in ipairs(rows[1]) do
      chars[#chars + 1] = glyph.char
    end
    assert(table.concat(chars) == "wirea=42;")
  end)
  check("blank lines and horizontal whitespace keep their original positions", function()
    local rows = document(source({ "a  b", "", "    c" }))
    assert(#rows == 3 and #rows[2] == 0)
    assert(rows[1][2].column == 3 and rows[3][1].column == 4)
  end)
  check("TAB and variable TAB stops align after preceding text", function()
    local buf = source({ "a\tb" })
    local first = document(buf)
    api.nvim_buf_set_lines(buf, 0, -1, false, { "a   b" })
    assert(vim.deep_equal(first, document(buf)))
    api.nvim_buf_set_lines(buf, 0, -1, false, { "a\tb\tc\td" })
    vim.bo[buf].vartabstop = "3,5"
    first = document(buf)
    api.nvim_buf_set_lines(buf, 0, -1, false, { "a  b    c    d" })
    assert(vim.deep_equal(first, document(buf)))
  end)
  check("wide and combining UTF-8 glyphs are not duplicated or shifted", function()
    local row = document(source({ "中é🙂 x" }))[1]
    assert(#row == 4 and row[1].char == "中" and row[1].width == 2)
    assert(row[2].char == "é" and row[2].column == 2)
    assert(row[3].char == "🙂" and row[3].column == 3 and row[4].column == 6)
  end)
  check("long files preserve density and retain both document boundaries", function()
    local top = renderer.region(400, 10, 1, 30, 1, 3)
    local bottom = renderer.region(400, 10, 371, 400, 400, 3)
    assert(top == 0 and bottom == math.ceil(400 / 3) - 10)
    assert(renderer.region(8, 30, 1, 8, 1, 3) == 0)
  end)
  check("folded viewport still contains its actual source cursor", function()
    for _, cursor in ipairs({ 1, 40, 1000, 2000 }) do
      local offset, rows = renderer.region(2000, 30, 1, 2000, cursor, 3)
      local y = math.floor((cursor - 1) / 3) - offset
      assert(y >= 0 and y < rows)
    end
  end)
  check("extremely long lines are clipped before building glyph tables", function()
    local buf = source({ string.rep("a", 200000) })
    local rows = document(buf, { max_columns = 7 })
    assert(#rows[1] == 7 and rows[1][7].column == 6)
  end)
  check("real Tree-sitter colours for HDL, C/C++, Python, Perl, Tcl and Make", function()
    local examples = {
      { "verilog", { "module sample;", "  wire a = 1'b1;", "  // reset", "endmodule" } },
      { "systemverilog", { "module sample;", "  logic a = 1'b1;", "  // reset", "endmodule" } },
      { "c", { "int main(void) {", '  const char *s = "hello";', "  return 42;", "}" } },
      { "cpp", { "int main() {", '  const char *s = "hello";', "  return 42;", "}" } },
      { "python", { "def calculate(x):", "    # example", "    return x + 42", "" } },
      { "perl", { "my $value = 42;", "# example", 'print "hello";', "" } },
      { "tcl", { "set value 42", "# example", 'puts "hello"', "" } },
      { "make", { "all: result", '\t@echo "hello"', "# example", "VALUE := 42" } },
    }
    for _, example in ipairs(examples) do
      local buf = source(example[2], example[1])
      assert(vim.treesitter.highlighter.active[buf], "Parser absent: " .. example[1])
      vim.bo[buf].syntax = ""
      vim.cmd("syntax clear")
      assert(palette(document(buf)) >= 2, "Missing colours: " .. example[1])
    end
  end)
  check("injected Python retains its colours inside Markdown", function()
    local buf = source({ "```python", "def example(x):", "    return x + 42", "```" }, "markdown")
    vim.bo[buf].syntax = ""
    vim.cmd("syntax clear")
    assert(palette(document(buf)) >= 2)
  end)
  check("absent parser uses built-in syntax; style/background are not copied", function()
    local buf = source({ "hello plain" }, "workbench-minimap-test")
    vim.cmd("syntax clear")
    vim.cmd("syntax match MinimapFallback /hello/")
    api.nvim_set_hl(0, "MinimapFallback", { fg = "#ee99a0", bg = "#000000", italic = true })
    local rows = document(buf)
    assert(rows[1][1].color == 0xee99a0 and rows[1][1].bg == nil)
  end)
  check("colour cache follows a changed theme", function()
    local buf = source({ "hello" }, "workbench-minimap-test")
    vim.cmd("syntax clear")
    vim.cmd("syntax match MinimapFallback /hello/")
    api.nvim_set_hl(0, "MinimapFallback", { fg = "#8aadf4" })
    renderer.reset_colors()
    assert(document(buf)[1][1].color == 0x8aadf4)
  end)
  assert(vim.v.errmsg == "", vim.v.errmsg)
end, debug.traceback)
for _, buf in ipairs(buffers) do
  pcall(api.nvim_buf_delete, buf, { force = true })
end
if not ok then
  io.stderr:write("FAIL: " .. tostring(failure) .. "\n")
  vim.cmd("cquit 1")
else
  io.stdout:write(vim.json.encode({ ok = true, checks = #checks, passed = checks }) .. "\n")
  vim.cmd("qa!")
end
