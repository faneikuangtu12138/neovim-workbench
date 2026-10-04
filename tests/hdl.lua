-- Run with Workbench active and Verible installed:
-- NVIM_APPNAME=neovim-workbench nvim --headless -i NONE -S tests/hdl.lua
-- Uses real LSP diagnostics/code actions and Blink completion sources.
-- If Icarus is available, also compile expanded snippets with -g2001.
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
local passed = {}
local function check(name, callback)
  vim.v.errmsg = ""
  callback()
  assert(vim.v.errmsg == "", name .. ": " .. vim.v.errmsg)
  passed[#passed + 1] = name
end

local function open(path, lines)
  if lines then
    vim.fn.writefile(lines, path)
  end
  vim.cmd.edit(vim.fn.fnameescape(path))
  return vim.api.nvim_get_current_buf()
end

local function client_for(buf, name)
  assert(
    vim.wait(8000, function()
      local clients = vim.lsp.get_clients({ bufnr = buf })
      return #clients == 1 and clients[1].name == name and clients[1].initialized
    end, 20),
    "Expected exactly one " .. name .. " client on " .. vim.api.nvim_buf_get_name(buf)
  )
  return vim.lsp.get_clients({ bufnr = buf })[1]
end

local function diagnostics(buf, client)
  local response, err = client:request_sync("textDocument/diagnostic", {
    textDocument = { uri = vim.uri_from_bufnr(buf) },
  }, 5000, buf)
  assert(response and not response.err, vim.inspect(err or response))
  assert(response.result.kind == "full", "Expected a full diagnostic report")
  return response.result.items
end

local function has_rule(items, code)
  for _, item in ipairs(items) do
    if item.code == code or item.message:find("[" .. code .. "]", 1, true) then
      return true
    end
  end
  return false
end

local function completions(id)
  -- Use the actual configured source, including its options and registry.
  local source = require("blink.cmp.sources.lib").get_provider_by_id(id).module
  local response
  source:get_completions({
    id = 1,
    mode = "default",
    bufnr = vim.api.nvim_get_current_buf(),
    cursor = { 1, 0 },
    bounds = { start_col = 1, length = 0 },
    get_line = function()
      return ""
    end,
  }, function(result)
    response = result
  end)
  assert(
    vim.wait(3000, function()
      return response ~= nil
    end, 10),
    "Completion source timed out: " .. id
  )
  return response.items
end

local function snippet(items, label)
  local matches = vim.tbl_filter(function(item)
    return item.label == label
  end, items)
  assert(#matches == 1, "Expected one snippet for " .. label .. ", got " .. #matches)
  return matches[1].insertText
end

local function contains(items, label)
  return vim.iter(items):any(function(item)
    return item.label == label
  end)
end

local ok, failure = xpcall(function()
  assert(vim.g.mapleader == " ", "Workbench must be the active configuration")
  assert(vim.fn.executable("verible-verilog-ls") == 1, "Install Verible with :MasonInstall verible")
  local hdl = require("config.hdl")
  -- Explicit project rules must not reintroduce SV prescriptions into .v.
  local rules = vim.deepcopy(hdl.verilog_disabled_rules)
  rules[#rules + 1] = "line-length=length:72"
  vim.fn.writefile(rules, temporary .. "/.rules.verible_lint")
  vim.fn.writefile({ "legacy.v", "legacy.sv" }, temporary .. "/verible.filelist")
  local legacy = {
    "module legacy #(parameter integer DisableCapture = 0)(input wire a, output reg q);",
    "    parameter WIDTH = 8;",
    "    localparam integer COUNT_WIDTH = 8;",
    "    localparam [2:0] C_IDLE = 3'd0;",
    "    parameter disable_capture = 0;",
    "    `define legacy_value 1",
    "    reg [7:0] memory [0:3];",
    "    function [7:0] increment;",
    "        input [7:0] value;",
    "        begin",
    "            increment = value + 1;",
    "        end",
    "    endfunction",
    "    task show_value;",
    "        input [7:0] value;",
    "        begin",
    '            $display("%d", value);',
    "        end",
    "    endtask",
    "    integer sample;",
    "    initial begin",
    "        sample = $random;",
    "    end",
    "    genvar g;",
    "    generate",
    "        for (g = 0; g < WIDTH; g = g + 1) begin : bits",
    "            wire unused;",
    "        end",
    "    endgenerate",
    "    always @* begin",
    "        q = a;",
    "    end",
    "    wire " .. string.rep("x", 72) .. ";",
    "endmodule",
  }
  local v = open(temporary .. "/legacy.v", legacy)
  local v_client = client_for(v, "verible_verilog")
  local sv = open(temporary .. "/legacy.sv", legacy)
  local sv_client = client_for(sv, "verible")
  local v_diags, sv_diags = diagnostics(v, v_client), diagnostics(sv, sv_client)

  check("mixed project uses independent Verilog and SV clients", function()
    assert(v_client.id ~= sv_client.id, "Different language rules share a client")
    assert(v_client.root_dir == sv_client.root_dir, "Fixture must share one project root")
    for _, ext in ipairs({ "vh", "svh" }) do
      local buf = open(temporary .. "/header." .. ext, { "`define HDL_VALUE 1" })
      local verilog = ext == "vh"
      assert(vim.bo[buf].filetype == (verilog and "verilog" or "systemverilog"))
      assert(
        client_for(buf, verilog and "verible_verilog" or "verible").id
          == (verilog and v_client.id or sv_client.id)
      )
    end
  end)

  check("legal Verilog has no SV migration or naming diagnostics", function()
    for _, rule in ipairs(hdl.verilog_disabled_rules) do
      assert(not has_rule(v_diags, rule), "Verilog still reports " .. rule)
    end
    for _, diagnostic in ipairs(v_diags) do
      assert(diagnostic.severity ~= 1, "Valid Verilog produced an error: " .. diagnostic.message)
    end
    assert(
      has_rule(v_diags, "line-length"),
      "Unrelated project lint rule was lost: " .. vim.inspect(v_diags)
    )
  end)

  check("SystemVerilog retains its style diagnostics", function()
    for _, rule in ipairs({
      "always-comb",
      "explicit-function-lifetime",
      "explicit-task-lifetime",
      "legacy-genvar-declaration",
    }) do
      assert(has_rule(sv_diags, rule), "SystemVerilog lost " .. rule)
    end
    for _, rule in ipairs({
      "parameter-name-style",
      "macro-name-style",
      "generate-label-prefix",
      "positive-meaning-parameter-name",
    }) do
      assert(
        has_rule(sv_diags, rule),
        "SV fixture did not exercise naming rule: " .. rule .. " / " .. vim.inspect(sv_diags)
      )
    end
  end)

  check("module naming does not constrain Verilog source filenames", function()
    local body = { "module actual_module;", "endmodule" }
    local vb = open(temporary .. "/different_name.v", body)
    assert(not has_rule(diagnostics(vb, client_for(vb, "verible_verilog")), "module-filename"))
    local svb = open(temporary .. "/different_name.sv", body)
    assert(has_rule(diagnostics(svb, client_for(svb, "verible")), "module-filename"))
  end)

  check("Verilog code actions do not replace always with always_comb", function()
    local function actions(buf, client, diags)
      local result, err = client:request_sync("textDocument/codeAction", {
        textDocument = { uri = vim.uri_from_bufnr(buf) },
        range = { start = { line = 29, character = 0 }, ["end"] = { line = 31, character = 7 } },
        context = { diagnostics = diags },
      }, 5000, buf)
      assert(result and not result.err, vim.inspect(err or result))
      return vim.json.encode(result.result)
    end
    assert(not actions(v, v_client, v_diags):find("always_comb", 1, true))
    assert(actions(sv, sv_client, sv_diags):find("always_comb", 1, true), "SV autofix missing")
  end)

  check("Verilog syntax errors remain visible", function()
    local broken =
      open(temporary .. "/broken.v", { "module broken;", "    assign q = ;", "endmodule" })
    local diags = diagnostics(broken, client_for(broken, "verible_verilog"))
    assert(
      vim.iter(diags):any(function(item)
        return item.severity == 1
      end),
      "Broken Verilog did not produce a syntax error"
    )
  end)

  check("opening SV before Verilog also keeps clients separate", function()
    local reverse = temporary .. "/reverse"
    vim.fn.mkdir(reverse, "p")
    vim.fn.writefile({}, reverse .. "/verible.filelist")
    local sv_first = open(reverse .. "/first.sv", { "module first;", "endmodule" })
    local sv_first_client = client_for(sv_first, "verible")
    local v_second = open(reverse .. "/second.v", { "module second;", "endmodule" })
    assert(client_for(v_second, "verible_verilog").id ~= sv_first_client.id)
  end)

  vim.api.nvim_set_current_buf(v)
  local v_snippets = completions("snippets")
  check("Verilog snippets exclude SV and expand classic syntax", function()
    assert(snippet(v_snippets, "comb"):find("always @*", 1, true))
    assert(snippet(v_snippets, "for"):find("integer", 1, true))
    assert(snippet(v_snippets, "fun"):find("function [", 1, true))
    assert(snippet(v_snippets, "task"):find("endtask", 1, true))
    for _, item in ipairs(v_snippets) do
      for _, token in ipairs({
        "always_comb",
        "always_ff",
        "logic",
        "typedef",
        "void",
        "int",
        "struct",
        "enum",
      }) do
        assert(
          not item.insertText:match("%f[%w_]" .. token .. "%f[^%w_]"),
          "SV token in Verilog snippet: " .. item.label .. " / " .. token
        )
      end
    end
  end)

  check("SystemVerilog and Python keep their own upstream snippets", function()
    vim.api.nvim_set_current_buf(sv)
    assert(snippet(completions("snippets"), "comb"):find("always_comb", 1, true))
    open(temporary .. "/snippets.py", { "" })
    assert(#completions("snippets") > 0, "Python snippets were disabled")
    vim.api.nvim_set_current_buf(v)
  end)

  check("visible .sv words do not leak into .v completion and vice versa", function()
    vim.api.nvim_set_current_buf(v)
    local editor = vim.api.nvim_get_current_win()
    vim.api.nvim_buf_set_lines(v, 0, -1, false, { "verilog_only_signal", "" })
    vim.api.nvim_buf_set_lines(sv, 0, -1, false, { "always_comb logic sv_only_signal", "" })
    vim.cmd("vsplit")
    local other = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(other, sv)
    vim.api.nvim_set_current_win(editor)
    vim.api.nvim_win_set_cursor(editor, { 2, 0 })
    local items = completions("buffer")
    assert(contains(items, "verilog_only_signal"), "Own Verilog symbol missing")
    for _, label in ipairs({ "always_comb", "logic", "sv_only_signal" }) do
      assert(not contains(items, label), "SV word leaked into Verilog: " .. label)
    end
    vim.api.nvim_set_current_win(other)
    vim.api.nvim_win_set_cursor(other, { 2, 0 })
    items = completions("buffer")
    assert(contains(items, "sv_only_signal"), "Own SV symbol missing")
    assert(not contains(items, "verilog_only_signal"), "Verilog word leaked into SV")
    vim.api.nvim_win_close(other, true)
  end)

  if vim.fn.executable("iverilog") == 1 then
    check("expanded Verilog templates compile as Verilog-2001", function()
      local expanded = {}
      for _, prefix in ipairs({ "comb", "seq", "for", "fun", "task", "genfor" }) do
        local buf = open(temporary .. "/expand_" .. prefix .. ".v", { "" })
        vim.snippet.expand(snippet(v_snippets, prefix))
        expanded[prefix] = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        vim.snippet.stop()
        vim.api.nvim_feedkeys(
          vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
          "xt",
          false
        )
        vim.bo[buf].modified = false
      end
      local lines = {
        "module expanded(input wire clk, input wire rst_n, input wire d, output reg q);",
        "parameter WIDTH = 8;",
        "integer count;",
      }
      for _, prefix in ipairs({ "comb", "seq", "fun", "task", "genfor" }) do
        -- Empty combinational block needs a statement for Icarus's @* inference.
        local body = expanded[prefix]
        if prefix == "comb" then
          body[2] = "    q = d;"
        end
        vim.list_extend(lines, body)
      end
      lines[#lines + 1] = "initial begin"
      vim.list_extend(lines, expanded["for"])
      lines[#lines + 1] = "end"
      lines[#lines + 1] = "endmodule"
      local path = temporary .. "/expanded.v"
      vim.fn.writefile(lines, path)
      local result = vim.system({ "iverilog", "-g2001", "-tnull", path }, { text = true }):wait()
      assert(result.code == 0, result.stderr)
    end)
  else
    io.stdout:write("SKIP: Icarus snippet compilation (iverilog unavailable)\n")
  end
end, debug.traceback)

vim.fn.delete(temporary, "rf")
if not ok then
  io.stderr:write("FAIL: " .. tostring(failure) .. "\n")
  vim.cmd("cquit 1")
else
  io.stdout:write(vim.json.encode({ ok = true, checks = #passed, passed = passed }) .. "\n")
  vim.cmd("qa!")
end
