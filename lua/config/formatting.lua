-- Formatting is explicit by default. HDL, Tcl, Perl and Make are never
-- autoformatted, even after toggling the global save-format switch.
local conform = require("conform")
local M = {}
local auto_filetypes = { c = true, cpp = true, python = true, lua = true }
local format_filetypes = {
  c = true,
  cpp = true,
  python = true,
  lua = true,
  verilog = true,
  systemverilog = true,
  perl = true,
  tcl = true,
  sdc = true,
  xdc = true,
  upf = true,
}
vim.g.workbench_autoformat = vim.g.workbench_autoformat or false

local function buffer_indent(ctx)
  local options = vim.bo[ctx.buf]
  return options.shiftwidth > 0 and options.shiftwidth or options.tabstop, options
end

local function find_rule(ctx, names, accept)
  local directory = ctx.dirname
  while directory do
    for _, name in ipairs(names) do
      local path = vim.fs.joinpath(directory, name)
      local stat = vim.uv.fs_stat(path)
      if stat and stat.type == "file" and (not accept or accept(path, name)) then
        return path
      end
    end
    local parent = vim.fs.dirname(directory)
    directory = parent ~= directory and parent or nil
  end
end

local function has_stylua_rule(ctx)
  local names = { ".stylua.toml", "stylua.toml" }
  if find_rule(ctx, names) then
    return true
  end
  -- StyLua also searches its XDG configuration directories after the parents.
  local home_config = vim.fn.expand("~/.config")
  local directories = { home_config, vim.fs.joinpath(home_config, "stylua") }
  local xdg_config = vim.env.XDG_CONFIG_HOME
  if xdg_config and xdg_config ~= "" and xdg_config ~= home_config then
    vim.list_extend(directories, { xdg_config, vim.fs.joinpath(xdg_config, "stylua") })
  end
  for _, directory in ipairs(directories) do
    for _, name in ipairs(names) do
      local stat = vim.uv.fs_stat(vim.fs.joinpath(directory, name))
      if stat and stat.type == "file" then
        return true
      end
    end
  end
  return false
end

local function has_tcl_settings(path, name)
  if name ~= "pyproject.toml" then
    return true
  end
  -- An unrelated Python pyproject must not disable the Tcl indent fallback.
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return false
  end
  local section = ""
  for _, line in ipairs(lines) do
    local header = line:match("^%s*(%[[^%]]+%])")
    if header then
      section = header:gsub("[\"']", ""):gsub("%s+", "")
      if section == "[tool.tclint]" or section:match("^%[tool%.tclint%.") then
        return true
      end
    else
      local assignment = line:gsub("[\"']", "")
      if
        (section == "[tool]" and assignment:match("^%s*tclint%s*[.=]"))
        or (section == "" and assignment:match("^%s*tool%s*%.%s*tclint%s*[.=]"))
      then
        return true
      end
    end
  end
  return false
end

local function tcl_directory(_, ctx)
  -- stdin has no path. Give tclfmt the target directory to find project rules.
  local directory = ctx.dirname
  while directory do
    local stat = vim.uv.fs_stat(directory)
    if stat and stat.type == "directory" then
      return directory
    end
    local parent = vim.fs.dirname(directory)
    directory = parent ~= directory and parent or nil
  end
end

local function has_formatter(bufnr)
  for _, formatter in ipairs(conform.list_formatters(bufnr)) do
    if formatter.available then
      return true
    end
  end
  return false
end

conform.setup({
  notify_on_error = true,
  notify_no_formatters = false,
  formatters_by_ft = {
    c = { "clang_format" },
    cpp = { "clang_format" },
    python = { "ruff_format" },
    lua = { "stylua" },
    verilog = { "verible" },
    systemverilog = { "verible" },
    perl = { "perltidy" },
    tcl = { "tclfmt" },
    sdc = { "tclfmt" },
    xdc = { "tclfmt" },
    upf = { "tclfmt" },
    -- Makefile intentionally has no formatter; preserve recipe tabs.
  },
  formatters = {
    clang_format = {
      prepend_args = function(_, ctx)
        if find_rule(ctx, { ".clang-format", "_clang-format" }) then
          return {}
        end
        local width, options = buffer_indent(ctx)
        local style = string.format(
          "{BasedOnStyle: LLVM, IndentWidth: %d, TabWidth: %d, UseTab: %s}",
          width,
          options.tabstop,
          options.expandtab and "Never" or "ForIndentation"
        )
        return { "--style=" .. style }
      end,
    },
    stylua = {
      prepend_args = function(_, ctx)
        if has_stylua_rule(ctx) then
          return {}
        end
        local width, options = buffer_indent(ctx)
        return {
          "--indent-type",
          options.expandtab and "Spaces" or "Tabs",
          "--indent-width",
          tostring(width),
        }
      end,
    },
    tclfmt = {
      cwd = tcl_directory,
      prepend_args = function(_, ctx)
        if find_rule(ctx, { "tclint.toml", ".tclint", "pyproject.toml" }, has_tcl_settings) then
          return {}
        end
        local width, options = buffer_indent(ctx)
        return { "--indent", options.expandtab and tostring(width) or "tab" }
      end,
    },
    verible = {
      -- Match the buffer's effective indent, including project EditorConfig.
      -- Verible otherwise defaults to two spaces even for a four-space buffer.
      prepend_args = function(_, ctx)
        local options = vim.bo[ctx.buf]
        local width = options.shiftwidth > 0 and options.shiftwidth or options.tabstop
        return { "--indentation_spaces=" .. width }
      end,
    },
  },
  default_format_opts = { lsp_format = "never", timeout_ms = 2000 },
  format_on_save = function(bufnr)
    if
      not vim.g.workbench_autoformat
      or vim.b[bufnr].disable_autoformat
      or not auto_filetypes[vim.bo[bufnr].filetype]
      or vim.bo[bufnr].buftype ~= ""
      or not has_formatter(bufnr)
    then
      return
    end
    return { timeout_ms = 1500, lsp_format = "never" }
  end,
})

function M.format()
  local bufnr = vim.api.nvim_get_current_buf()
  if not format_filetypes[vim.bo[bufnr].filetype] then
    vim.notify(
      "No formatter configured for "
        .. (vim.bo[bufnr].filetype ~= "" and vim.bo[bufnr].filetype or "this buffer"),
      vim.log.levels.INFO
    )
    return
  end
  if not has_formatter(bufnr) then
    vim.notify(
      "Formatter missing. Use :DevTools or :ConformInfo to inspect it.",
      vim.log.levels.WARN
    )
    return
  end
  -- Conform detects a visual selection when invoked by the visual mapping.
  conform.format({ bufnr = bufnr, async = true, lsp_format = "never" })
end

function M.toggle_autoformat()
  vim.g.workbench_autoformat = not vim.g.workbench_autoformat
  vim.notify(
    "Format on save: " .. (vim.g.workbench_autoformat and "ON (C/C++, Python, Lua)" or "OFF")
  )
end

vim.keymap.set({ "n", "v" }, "<leader>cf", M.format, { desc = "Format buffer / selection" })
vim.keymap.set("n", "<leader>uf", M.toggle_autoformat, { desc = "Toggle format on save" })
vim.api.nvim_create_user_command(
  "Format",
  M.format,
  { desc = "Format with the configured external tool" }
)
return M
