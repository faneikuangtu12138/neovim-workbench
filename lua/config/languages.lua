-- Native Neovim LSP; server defaults come from nvim-lspconfig's lsp/*.lua.
local M = {}

-- Keep both Mason and independently installed user tools discoverable.
local paths = {
  vim.fn.stdpath("data") .. "/mason/bin",
  vim.fn.expand("~/.local/bin"),
  vim.fn.expand("~/.local/share/nvim-tools/bin"),
  vim.env.PATH or "",
}
vim.env.PATH = table.concat(paths, vim.fn.has("win32") == 1 and ";" or ":")

vim.filetype.add({
  extension = {
    v = "verilog",
    vh = "verilog",
    sv = "systemverilog",
    svh = "systemverilog",
    sdc = "tcl",
    xdc = "tcl",
    upf = "tcl",
    itcl = "tcl",
    mk = "make",
  },
  filename = { Makefile = "make", makefile = "make", GNUmakefile = "make" },
})

local group = vim.api.nvim_create_augroup("WorkbenchLanguages", { clear = true })

vim.diagnostic.config({
  severity_sort = true,
  update_in_insert = false,
  underline = true,
  virtual_text = {
    spacing = 2,
    prefix = "●",
    severity = { min = vim.diagnostic.severity.WARN },
  },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "",
      [vim.diagnostic.severity.WARN] = "",
      [vim.diagnostic.severity.INFO] = "",
      [vim.diagnostic.severity.HINT] = "󰌵",
    },
  },
  float = { border = "rounded", source = "if_many", header = "", prefix = "" },
})

local capabilities = vim.lsp.protocol.make_client_capabilities()
local has_blink, blink = pcall(require, "blink.cmp")
if has_blink then
  capabilities = blink.get_lsp_capabilities(capabilities)
end
vim.lsp.config("*", { capabilities = capabilities })

vim.lsp.config("clangd", {
  cmd = {
    "clangd",
    "--background-index",
    "--clang-tidy",
    "--completion-style=detailed",
    "--header-insertion=never",
  },
})
vim.lsp.config("basedpyright", {
  settings = {
    basedpyright = {
      disableOrganizeImports = true,
      analysis = {
        diagnosticMode = "openFilesOnly",
        -- Project pyproject.toml / pyrightconfig.json can override this.
        typeCheckingMode = "standard",
      },
    },
  },
})
vim.lsp.config("ruff", {
  on_attach = function(client)
    -- basedpyright owns Python hover/completion; Ruff owns lint and fixes.
    client.server_capabilities.hoverProvider = false
  end,
})
vim.lsp.config("verible", {
  cmd = { "verible-verilog-ls", "--rules_config_search" },
  filetypes = { "verilog", "systemverilog" },
  root_markers = { "verible.filelist", ".git" },
})
vim.lsp.config("perlnavigator", {
  settings = { perlnavigator = { perlPath = "perl", enableWarnings = true } },
})
vim.lsp.config("tclsp", {
  cmd = { "tclsp" },
  filetypes = { "tcl", "sdc", "xdc", "upf" },
  root_markers = { "tclint.toml", ".tclint", "pyproject.toml", ".git" },
})
vim.lsp.config("lua_ls", {
  on_init = function(client)
    local folder = client.workspace_folders and client.workspace_folders[1]
    local root = folder and folder.name
    -- Preserve settings declared by an ordinary Lua project.
    if
      root
      and root ~= vim.fn.stdpath("config")
      and (vim.uv.fs_stat(root .. "/.luarc.json") or vim.uv.fs_stat(root .. "/.luarc.jsonc"))
    then
      return
    end
    client.config.settings.Lua = vim.tbl_deep_extend("force", client.config.settings.Lua or {}, {
      runtime = { version = "LuaJIT", path = { "lua/?.lua", "lua/?/init.lua" } },
      diagnostics = { globals = { "vim" } },
      workspace = { checkThirdParty = false, library = { vim.env.VIMRUNTIME } },
    })
  end,
  settings = { Lua = { telemetry = { enable = false } } },
})

local servers = {
  { name = "clangd", executable = "clangd", filetypes = { "c", "cpp", "objc", "objcpp", "cuda" } },
  { name = "basedpyright", executable = "basedpyright-langserver", filetypes = { "python" } },
  { name = "ruff", executable = "ruff", filetypes = { "python" } },
  {
    name = "verible",
    executable = "verible-verilog-ls",
    filetypes = { "verilog", "systemverilog" },
  },
  { name = "perlnavigator", executable = "perlnavigator", filetypes = { "perl" } },
  { name = "tclsp", executable = "tclsp", filetypes = { "tcl", "sdc", "xdc", "upf" } },
  { name = "lua_ls", executable = "lua-language-server", filetypes = { "lua" } },
}

local function is_large(bufnr)
  if vim.b[bufnr].large_file then
    return true
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  local stat = path ~= "" and vim.uv.fs_stat(path) or nil
  return (stat and stat.size > 1024 * 1024) or vim.api.nvim_buf_line_count(bufnr) > 20000
end

-- A globally enabled server still sees later buffers. Gate root resolution as
-- well as first activation so large logs/netlists never start an LSP client.
for _, server in ipairs(servers) do
  local defaults = vim.lsp.config[server.name]
  local root_dir = defaults.root_dir
  local root_markers = defaults.root_markers
  vim.lsp.config(server.name, {
    root_dir = function(bufnr, on_dir)
      if is_large(bufnr) then
        return
      end
      if type(root_dir) == "function" then
        return root_dir(bufnr, on_dir)
      end
      local root = type(root_dir) == "string" and root_dir
        or (root_markers and vim.fs.root(bufnr, root_markers))
      -- Keep ordinary standalone files useful, without requiring Git.
      on_dir(root or vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr)))
    end,
  })
end

function M.activate(bufnr, refresh)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= "" or is_large(bufnr) then
    return
  end
  local filetype = vim.bo[bufnr].filetype
  local names = {}
  for _, server in ipairs(servers) do
    if
      vim.tbl_contains(server.filetypes, filetype)
      and vim.fn.executable(server.executable) == 1
      and (refresh or not vim.lsp.is_enabled(server.name))
    then
      table.insert(names, server.name)
    end
  end
  if #names > 0 then
    vim.lsp.enable(names)
  end
end

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  callback = function(event)
    -- No warning or attempted server launch when tools are absent.
    M.activate(event.buf)
  end,
})

vim.api.nvim_create_autocmd("LspAttach", {
  group = group,
  callback = function(event)
    local client = vim.lsp.get_client_by_id(event.data.client_id)
    if not client then
      return
    end
    local function map(lhs, rhs, description, mode)
      vim.keymap.set(mode or "n", lhs, rhs, { buffer = event.buf, desc = description })
    end
    local function lsp_map(method, lhs, rhs, description, mode)
      if client:supports_method(method, event.buf) then
        map(lhs, rhs, description, mode)
      end
    end
    lsp_map("textDocument/definition", "gd", vim.lsp.buf.definition, "Go to definition")
    lsp_map("textDocument/references", "gr", vim.lsp.buf.references, "Find references")
    lsp_map("textDocument/implementation", "gI", vim.lsp.buf.implementation, "Go to implementation")
    lsp_map(
      "textDocument/typeDefinition",
      "gy",
      vim.lsp.buf.type_definition,
      "Go to type definition"
    )
    lsp_map("textDocument/hover", "K", vim.lsp.buf.hover, "Documentation")
    lsp_map("textDocument/rename", "<leader>cr", vim.lsp.buf.rename, "Rename symbol")
    lsp_map(
      "textDocument/codeAction",
      "<leader>ca",
      vim.lsp.buf.code_action,
      "Code action",
      { "n", "v" }
    )
    map("<leader>cd", vim.diagnostic.open_float, "Line diagnostics")
    lsp_map(
      "textDocument/signatureHelp",
      "<leader>cs",
      vim.lsp.buf.signature_help,
      "Signature help"
    )
    lsp_map("textDocument/inlayHint", "<leader>uh", function()
      local filter = { bufnr = event.buf }
      vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled(filter), filter)
    end, "Toggle inlay hints")
  end,
})

vim.keymap.set("n", "[d", function()
  vim.diagnostic.jump({ count = -1, float = true })
end, { desc = "Previous diagnostic" })
vim.keymap.set("n", "]d", function()
  vim.diagnostic.jump({ count = 1, float = true })
end, { desc = "Next diagnostic" })
vim.keymap.set("n", "<leader>cl", "<cmd>checkhealth vim.lsp<cr>", { desc = "LSP health" })

vim.api.nvim_create_user_command("LspRefresh", function()
  M.activate(nil, true)
end, { desc = "Recheck installed language servers" })

local tools = {
  { "C/C++ LSP", "clangd" },
  { "C/C++ format", "clang-format" },
  { "Python LSP", "basedpyright-langserver" },
  { "Python lint/format", "ruff" },
  { "Verilog/SV LSP", "verible-verilog-ls" },
  { "Verilog/SV format", "verible-verilog-format" },
  { "HDL project lint", "verilator" },
  { "Perl LSP", "perlnavigator" },
  { "Perl format", "perltidy" },
  { "Perl lint", "perlcritic" },
  { "Tcl LSP", "tclsp" },
  { "Tcl format", "tclfmt" },
  { "Lua LSP", "lua-language-server" },
  { "Lua format", "stylua" },
  { "Tree-sitter CLI", "tree-sitter" },
  { "Project search", "rg" },
  { "Compilation database", "bear" },
}

function M.show_tools()
  local lines = {
    "Development tools",
    "",
    "Missing tools are skipped quietly. :Mason opens the tool installer.",
    "",
  }
  for _, tool in ipairs(tools) do
    local path = vim.fn.exepath(tool[2])
    table.insert(
      lines,
      string.format("%-22s %s", tool[1], path ~= "" and path or ("MISSING: " .. tool[2]))
    )
  end
  vim.list_extend(lines, {
    "",
    "C/C++: generate compile_commands.json with CMake or bear -- make.",
    "SV: use verible.filelist; run full-project checks with your simulator.",
    "Tcl: install tclint (provides tclsp and tclfmt).",
    "",
    "Press q or Esc to close.",
  })
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  local width = math.max(20, math.min(90, vim.o.columns - 6))
  local height = math.max(3, math.min(#lines, vim.o.lines - 6))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    border = "rounded",
    title = " Toolchain ",
    title_pos = "center",
    style = "minimal",
  })
  vim.wo[win].wrap = false
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.keymap.set("n", "q", close, { buffer = buf, desc = "Close tool inventory" })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, desc = "Close tool inventory" })
end

vim.api.nvim_create_user_command(
  "DevTools",
  M.show_tools,
  { desc = "Inspect language tooling without startup warnings" }
)
return M
