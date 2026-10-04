local hdl = require("config.hdl")

require("blink.cmp").setup({
  enabled = function()
    if vim.bo.buftype ~= "" or vim.b.large_file then
      return false
    end
    local stat = vim.uv.fs_stat(vim.api.nvim_buf_get_name(0))
    return not (stat and stat.size > 1024 * 1024) and vim.api.nvim_buf_line_count(0) <= 20000
  end,
  keymap = {
    preset = "default",
    ["<CR>"] = { "accept", "fallback" },
    ["<Tab>"] = { "snippet_forward", "fallback" },
    ["<S-Tab>"] = { "snippet_backward", "fallback" },
  },
  appearance = { nerd_font_variant = "mono" },
  fuzzy = { implementation = "lua" },
  completion = {
    list = { selection = { preselect = false, auto_insert = false } },
    accept = { auto_brackets = { enabled = false } },
    menu = {
      border = "rounded",
      draw = {
        columns = { { "kind_icon" }, { "label", "label_description", gap = 1 }, { "source_name" } },
      },
    },
    documentation = { auto_show = true, auto_show_delay_ms = 250, window = { border = "rounded" } },
  },
  sources = {
    default = { "lsp", "path", "snippets", "buffer" },
    providers = {
      snippets = { opts = { filter_snippets = hdl.filter_snippets } },
      buffer = { opts = { get_bufnrs = hdl.completion_buffers } },
    },
  },
  snippets = { preset = "default" },
  signature = { enabled = true, window = { border = "rounded" } },
  cmdline = { enabled = false },
})
