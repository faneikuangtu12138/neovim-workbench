require("mini.pairs").setup({ modes = { insert = true, command = false, terminal = false } })
require("mini.surround").setup()
require("mini.ai").setup({ n_lines = 300 })
require("mini.bufremove").setup()
require("mini.trailspace").setup()
require("mini.indentscope").setup({
  symbol = "│",
  draw = { delay = 100, animation = require("mini.indentscope").gen_animation.none() },
  options = { try_as_border = true },
})
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("WorkbenchScope", { clear = true }),
  pattern = {
    "neo-tree",
    "ministarter",
    "help",
    "terminal",
    "qf",
    "mason",
    "notify",
    "TelescopePrompt",
  },
  callback = function()
    vim.b.miniindentscope_disable = true
  end,
})
