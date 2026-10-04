local function map(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { desc = desc, silent = true })
end
local navigation = require("core.navigation")
local function picker(name, opts)
  return function()
    require("telescope.builtin")[name](
      vim.tbl_extend("force", { cwd = navigation.project_root() }, opts or {})
    )
  end
end

map("n", "<Esc>", "<cmd>nohlsearch<CR>", "Clear Search Highlight")
map("n", "<leader>w", "<cmd>write<CR>", "Save File")
map({ "n", "i", "v" }, "<C-s>", "<cmd>write<CR>", "Save File")
map("n", "<leader>q", "<cmd>quit<CR>", "Quit Window")
map("n", "<leader>e", navigation.toggle_tree_focus, "Switch Explorer / Editor")
map("n", "<leader>E", navigation.focus_tree, "Reveal Current File")
map("n", "<leader>ue", navigation.toggle_tree_visibility, "Toggle Explorer Visibility")

map("n", "<leader>ff", picker("find_files"), "Find Project File")
map("n", "<leader>fg", picker("live_grep"), "Find Project Text")
map("n", "<leader>fb", picker("buffers"), "Find Buffer")
map("n", "<leader>fr", picker("oldfiles"), "Recent Files")
map("n", "<leader>fh", picker("help_tags"), "Help")
map(
  "n",
  "<leader>fc",
  picker("find_files", { cwd = vim.fn.stdpath("config") }),
  "Find Configuration File"
)
map("n", "<leader>fF", function()
  require("telescope.builtin").find_files({ cwd = vim.fn.getcwd() })
end, "Find File in Current Directory")
map("n", "<leader>sw", picker("grep_string"), "Search Word")
map("n", "<leader>ss", picker("lsp_document_symbols"), "Document Symbols")
map("n", "<leader>sk", picker("keymaps"), "Search Keymaps")
map("n", "<leader>sr", picker("resume"), "Resume Last Search")

map("n", "<S-h>", "<cmd>bprevious<CR>", "Previous Buffer")
map("n", "<S-l>", "<cmd>bnext<CR>", "Next Buffer")
map("n", "[b", "<cmd>bprevious<CR>", "Previous Buffer")
map("n", "]b", "<cmd>bnext<CR>", "Next Buffer")
map("n", "<leader>bd", function()
  require("mini.bufremove").delete(0, false)
end, "Close Buffer (Keep Layout)")
map("n", "<leader>bp", "<cmd>BufferLinePick<CR>", "Pick Buffer")
map("n", "<leader>bn", "<cmd>enew<CR>", "New Empty Buffer")

for key, direction in pairs({ h = "h", j = "j", k = "k", l = "l" }) do
  map("n", "<C-" .. key .. ">", function()
    require("config.frame").move(direction)
  end, "Window " .. ({ h = "Left", j = "Down", k = "Up", l = "Right" })[key])
  map("t", "<C-" .. key .. ">", function()
    vim.cmd.stopinsert()
    require("config.frame").move(direction)
  end, "Move from Terminal")
end
map("n", "<leader>|", "<cmd>vsplit<CR>", "Split Right")
map("n", "<leader>-", "<cmd>split<CR>", "Split Below")
map("n", "<C-Up>", "<cmd>resize +2<CR>", "Increase Height")
map("n", "<C-Down>", "<cmd>resize -2<CR>", "Decrease Height")
map("n", "<C-Left>", "<cmd>vertical resize -2<CR>", "Decrease Width")
map("n", "<C-Right>", "<cmd>vertical resize +2<CR>", "Increase Width")
map("v", "<", "<gv", "Indent Left")
map("v", ">", ">gv", "Indent Right")
vim.keymap.set(
  "n",
  "j",
  "v:count == 0 ? 'gj' : 'j'",
  { expr = true, silent = true, desc = "Move Down" }
)
vim.keymap.set(
  "n",
  "k",
  "v:count == 0 ? 'gk' : 'k'",
  { expr = true, silent = true, desc = "Move Up" }
)

map("n", "<leader>tt", "<cmd>TermToggle<CR>", "Toggle Project Terminal")
map("n", "<leader>tm", "<cmd>Build<CR>", "Build Project (Enter Command)")
map("n", "<leader>gg", picker("git_status"), "Git Status")
map("n", "<leader>xx", function()
  vim.diagnostic.setqflist()
end, "Project Diagnostics")
map("n", "<leader>xd", picker("diagnostics", { bufnr = 0 }), "Buffer Diagnostics")
map("n", "<leader>xq", function()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "quickfix" then
      vim.cmd.cclose()
      return
    end
  end
  vim.cmd.copen()
end, "Toggle Quickfix")
map("n", "]q", function()
  pcall(vim.cmd.cnext)
end, "Next Quickfix Item")
map("n", "[q", function()
  pcall(vim.cmd.cprevious)
end, "Previous Quickfix Item")

map("n", "<leader>uk", function()
  require("screenkey").toggle_statusline_component()
  require("lualine").refresh({ place = { "statusline" } })
end, "Toggle Key Display")
map("n", "<leader>uv", "<cmd>MinimapToggle<CR>", "Toggle Code Minimap")
map("n", "<leader>uw", function()
  vim.wo.wrap = not vim.wo.wrap
end, "Toggle Line Wrap")
map("n", "<leader>ud", function()
  vim.diagnostic.enable(not vim.diagnostic.is_enabled({ bufnr = 0 }), { bufnr = 0 })
  -- enable() changes visibility without emitting DiagnosticChanged.
  require("config.minimap").refresh()
end, "Toggle Buffer Diagnostics")
map("n", "<leader>ui", "<cmd>DevTools<CR>", "Inspect Development Tools")
map("n", "<leader>um", "<cmd>Mason<CR>", "Manage Language Tools")
map("n", "<leader>uh", function()
  vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = 0 }), { bufnr = 0 })
end, "Toggle Inlay Hints")
map("n", "<leader>?", function()
  require("which-key").show({ global = false })
end, "Show Keymaps")
