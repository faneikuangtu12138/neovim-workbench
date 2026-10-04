-- nvim-treesitter main: use native highlighting/folding APIs, not configs.setup.
local M = {}
local treesitter = require("nvim-treesitter")
treesitter.setup({ install_dir = vim.fn.stdpath("data") .. "/site" })

M.parsers = {
  "c",
  "cpp",
  "python",
  "systemverilog",
  "perl",
  "tcl",
  "make",
  "lua",
  "vim",
  "vimdoc",
  "query",
  "bash",
  "json",
  "yaml",
  "markdown",
  "markdown_inline",
}
vim.treesitter.language.register("systemverilog", { "verilog", "systemverilog" })

local filetypes = {
  c = true,
  cpp = true,
  python = true,
  verilog = true,
  systemverilog = true,
  perl = true,
  tcl = true,
  make = true,
  lua = true,
  vim = true,
  help = true,
  query = true,
  sh = true,
  bash = true,
  json = true,
  yaml = true,
  markdown = true,
}

function M.is_large(bufnr)
  if vim.b[bufnr].large_file then
    return true
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  local stat = path ~= "" and vim.uv.fs_stat(path) or nil
  return (stat and stat.size > 1024 * 1024) or vim.api.nvim_buf_line_count(bufnr) > 20000
end

function M.start(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if M.is_large(bufnr) then
    pcall(vim.treesitter.stop, bufnr)
    for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
      vim.wo[win].foldmethod = "manual"
    end
    return
  end
  if not filetypes[vim.bo[bufnr].filetype] then
    return
  end
  -- An absent parser leaves Neovim's built-in syntax/indent functioning.
  local ok = pcall(vim.treesitter.start, bufnr)
  if not ok then
    return
  end
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    vim.wo[win].foldmethod = "expr"
    vim.wo[win].foldexpr = "v:lua.vim.treesitter.foldexpr()"
    if not vim.w[win].workbench_ts_folds then
      vim.wo[win].foldlevel = 99
      vim.w[win].workbench_ts_folds = true
    end
  end
  -- Keep built-in filetype indentation, especially for HDL, Perl and Make.
end

local group = vim.api.nvim_create_augroup("WorkbenchTreesitter", { clear = true })
vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
  group = group,
  callback = function(event)
    M.start(event.buf)
  end,
})

vim.api.nvim_create_user_command("TSInstallWorkbench", function()
  if vim.fn.executable("tree-sitter") ~= 1 then
    vim.notify("Install tree-sitter-cli >= 0.26.1 before installing parsers.", vim.log.levels.WARN)
    return
  end
  -- Explicitly requested download; startup never installs or updates parsers.
  local task = treesitter.install(M.parsers)
  task:await(function(err)
    vim.schedule(function()
      if err then
        vim.notify("Parser installation failed: " .. tostring(err), vim.log.levels.ERROR)
        return
      end
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
          M.start(buf)
        end
      end
    end)
  end)
end, { desc = "Install parsers for this workbench (manual network operation)" })
return M
