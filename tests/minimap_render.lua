-- Run with the complete configuration: nvim --headless -i NONE -S this file.
local api = vim.api
local renderer = require("config.minimap_render")
local checks = {}
local buffers = {}
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
local function encode(buf, options)
  return renderer.encode(
    buf,
    vim.tbl_extend("force", {
      width = 20,
      height = 30,
      offset = 0,
      column_scale = 1,
      max_columns = 120,
      source_win = api.nvim_get_current_win(),
    }, options or {})
  )
end
local function palette(spans)
  local result = {}
  for _, span in ipairs(spans) do
    if span.group ~= "WorkbenchMinimap" then
      local hl = api.nvim_get_hl(0, { name = span.group, link = false })
      assert(hl.fg and not hl.bg and not hl.italic and not hl.bold)
      result[hl.fg] = true
    end
  end
  return vim.tbl_count(result)
end

local ok, failure = xpcall(function()
  check("fixed 2x4 dots preserve all four source lines and horizontal spaces", function()
    local buf = source({ "a", " b", "a", " b" })
    local lines = encode(buf, { width = 3 })
    assert(lines[1] == vim.fn.nr2char(0x2800 + 1 + 16 + 4 + 128) .. "  ")
    assert(#lines == 1 and vim.fn.strdisplaywidth(lines[1]) == 3)
    api.nvim_buf_set_lines(buf, 0, -1, false, { "a", "", "", "", "", "b" })
    lines = encode(buf, { width = 3 })
    assert(#lines == 2 and lines[1] == vim.fn.nr2char(0x2801) .. "  ")
    assert(lines[2] == vim.fn.nr2char(0x2802) .. "  ")
  end)
  check("short content is not stretched to panel width or height", function()
    local buf = source({ "a" })
    local narrow = encode(buf, { width = 5, height = 6 })
    local wide = encode(buf, { width = 35, height = 60 })
    assert(#wide == 1 and wide[1]:sub(1, #narrow[1]) == narrow[1])
    assert(wide[1] == vim.fn.nr2char(0x2801) .. string.rep(" ", 34))
  end)
  check("TAB aligns to stops after text; variable stops are respected", function()
    local buf = source({ "a\tb" })
    local with_tab = encode(buf)
    api.nvim_buf_set_lines(buf, 0, -1, false, { "a   b" })
    assert(vim.deep_equal(with_tab, encode(buf)))
    api.nvim_buf_set_lines(buf, 0, -1, false, { "a\tb\tc\td" })
    vim.bo[buf].vartabstop = "3,5"
    with_tab = encode(buf)
    api.nvim_buf_set_lines(buf, 0, -1, false, { "a  b    c    d" })
    assert(vim.deep_equal(with_tab, encode(buf)))
  end)
  check("UTF-8 wide and combining characters use display columns", function()
    local buf = source({ "中é🙂 x" })
    local wide = encode(buf)
    api.nvim_buf_set_lines(buf, 0, -1, false, { "aaaaa x" })
    assert(vim.deep_equal(wide, encode(buf)))
    api.nvim_buf_set_lines(buf, 0, -1, false, { "a b" })
    local whitespace = encode(buf)
    api.nvim_buf_set_lines(buf, 0, -1, false, { "a b" })
    assert(vim.deep_equal(whitespace, encode(buf)))
  end)
  check("long files scroll a fixed-density slice rather than squeezing ink", function()
    local lines = {}
    for row = 1, 400 do
      lines[row] = row <= 200 and "a" or "  b"
    end
    local buf = source(lines)
    local top = renderer.region(400, 10, 1, 36)
    local bottom = renderer.region(400, 10, 365, 400)
    assert(top == 0 and bottom == 90, "Preview omitted the start/end of the document")
    local preview_top = encode(buf, { offset = top, height = 10 })
    local preview_bottom = encode(buf, { offset = bottom, height = 10 })
    assert(#preview_top == 10 and #preview_bottom == 10)
    assert(preview_top[1] ~= preview_bottom[1])
    assert(renderer.region(8, 30, 1, 8) == 0)
  end)
  check("folded viewport still keeps the actual source cursor in the slice", function()
    for _, cursor in ipairs({ 1, 40, 1000, 2000 }) do
      local offset, rows = renderer.region(2000, 30, 1, 2000, cursor)
      local row = math.floor((cursor - 1) / 4) - offset
      assert(row >= 0 and row < rows, "Cursor is absent from the code slice")
    end
  end)
  check("very long lines are clipped before building codepoint tables", function()
    local buf = source({ string.rep("a", 200000) })
    local lines, spans = encode(buf, { width = 10, max_columns = 7 })
    api.nvim_buf_set_lines(buf, 0, -1, false, { string.rep("a", 7) })
    assert(vim.deep_equal(lines, encode(buf, { width = 10, max_columns = 7 })))
    for _, span in ipairs(spans) do
      assert(span.start >= 0 and span.finish <= #lines[span.row + 1])
    end
  end)
  check("Tree-sitter syntax colours work for HDL, C/C++, Python, Perl, Tcl and Make", function()
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
      local _, spans = encode(buf)
      assert(palette(spans) >= 2, "No syntax colour variation: " .. example[1])
    end
  end)
  check("injected Python retains its syntax colours inside Markdown", function()
    local buf = source({ "```python", "def example(x):", "    return x + 42", "```" }, "markdown")
    vim.bo[buf].syntax = ""
    vim.cmd("syntax clear")
    local _, spans = encode(buf)
    assert(palette(spans) >= 2, "Injected code lost its colours")
  end)
  check("missing parser falls back to built-in syntax without errors", function()
    local buf = source({ "hello plain" }, "workbench-minimap-test")
    vim.cmd("syntax clear")
    vim.cmd("syntax match MinimapFallback /hello/")
    api.nvim_set_hl(0, "MinimapFallback", { fg = "#ee99a0", italic = true })
    local _, spans = encode(buf)
    assert(palette(spans) >= 1)
    local found = false
    for _, span in ipairs(spans) do
      found = found or api.nvim_get_hl(0, { name = span.group, link = false }).fg == 0xee99a0
    end
    assert(found, "Fallback syntax colour missing")
  end)
  check("colour cache can follow a changed theme without copying background/style", function()
    local buf = source({ "hello" }, "workbench-minimap-test")
    vim.cmd("syntax clear")
    vim.cmd("syntax match MinimapFallback /hello/")
    api.nvim_set_hl(0, "MinimapFallback", { fg = "#8aadf4", bg = "#000000", bold = true })
    renderer.reset_colors()
    local _, spans = encode(buf)
    assert(palette(spans) == 1)
    assert(api.nvim_get_hl(0, { name = spans[1].group, link = false }).fg == 0x8aadf4)
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
