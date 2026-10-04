local M = {}

function M.setup()
  vim.filetype.add({
    extension = {
      sv = "systemverilog",
      svh = "systemverilog",
      vh = "verilog",
      sdc = "tcl",
      xdc = "tcl",
    },
  })

  local in_wsl = vim.env.WSL_DISTRO_NAME ~= nil or vim.env.WSL_INTEROP ~= nil
  if in_wsl and vim.fn.executable("win32yank.exe") == 1 then
    vim.g.clipboard = {
      name = "WSL Windows clipboard",
      copy = {
        ["+"] = { "win32yank.exe", "-i", "--crlf" },
        ["*"] = { "win32yank.exe", "-i", "--crlf" },
      },
      paste = {
        ["+"] = { "win32yank.exe", "-o", "--lf" },
        ["*"] = { "win32yank.exe", "-o", "--lf" },
      },
      cache_enabled = 0,
    }
    vim.opt.clipboard = "unnamedplus"
  end

  local group = vim.api.nvim_create_augroup("EditorWorkflow", { clear = true })
  vim.api.nvim_create_autocmd("TextYankPost", {
    group = group,
    callback = function()
      vim.hl.on_yank({ timeout = 160 })
    end,
  })
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = group,
    callback = function(event)
      if vim.api.nvim_get_current_buf() ~= event.buf or vim.bo[event.buf].buftype ~= "" then
        return
      end
      local ft = vim.bo[event.buf].filetype
      if ft == "gitcommit" or ft == "gitrebase" then
        return
      end
      local mark = vim.api.nvim_buf_get_mark(event.buf, '"')
      local count = vim.api.nvim_buf_line_count(event.buf)
      if mark[1] > 0 and mark[1] <= count then
        local text = vim.api.nvim_buf_get_lines(event.buf, mark[1] - 1, mark[1], false)[1] or ""
        vim.api.nvim_win_set_cursor(0, { mark[1], math.min(mark[2], #text) })
      end
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "c", "cpp", "python", "perl", "verilog", "systemverilog" },
    callback = function(event)
      vim.bo[event.buf].expandtab = true
      vim.bo[event.buf].tabstop = 4
      vim.bo[event.buf].shiftwidth = 4
      vim.bo[event.buf].softtabstop = 4
    end,
  })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "lua", "tcl" },
    callback = function(event)
      vim.bo[event.buf].expandtab = true
      vim.bo[event.buf].tabstop = 2
      vim.bo[event.buf].shiftwidth = 2
      vim.bo[event.buf].softtabstop = 2
    end,
  })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "make",
    callback = function(event)
      -- Make recipes require actual tabs. Keep the runtime ftplugin's behavior.
      vim.bo[event.buf].expandtab = false
      vim.bo[event.buf].tabstop = 8
      vim.bo[event.buf].softtabstop = 0
      vim.bo[event.buf].shiftwidth = 0
    end,
  })
end

return M
