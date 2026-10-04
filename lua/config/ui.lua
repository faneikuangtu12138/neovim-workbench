local c = vim.g.workbench_colors
local screenkey = require("screenkey")
local navigation = require("core.navigation")

local function lsp_status()
  local names = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    if client.name ~= "ruff" then
      table.insert(
        names,
        ({ basedpyright = "Python", lua_ls = "Lua", perlnavigator = "Perl", tclsp = "Tcl" })[client.name]
          or client.name
      )
    end
  end
  return #names > 0 and (" " .. table.concat(names, "/")) or ""
end

require("bufferline").setup({
  options = {
    mode = "buffers",
    numbers = "ordinal",
    diagnostics = "nvim_lsp",
    separator_style = "thin",
    show_close_icon = false,
    show_buffer_close_icons = true,
    always_show_bufferline = true,
    modified_icon = "●",
    close_icon = "󰅖",
    indicator = { style = "icon", icon = "▎" },
    offsets = {
      { filetype = "neo-tree", text = "  EXPLORER", text_align = "left", separator = true },
    },
    custom_filter = function(buf)
      return vim.bo[buf].buftype == "" and vim.bo[buf].filetype ~= "ministarter"
    end,
    close_command = function(buf)
      require("mini.bufremove").delete(buf, false)
    end,
    right_mouse_command = function(buf)
      require("mini.bufremove").delete(buf, false)
    end,
  },
  highlights = require("catppuccin.special.bufferline").get_theme(),
})
require("config.tabs").setup()

-- The footer uses one shared background. Only mode and position are capsules,
-- so colored rectangles never need to connect through rounded glyphs.
local status_theme = {}
for _, mode in ipairs({ "normal", "insert", "visual", "replace", "command", "terminal", "inactive" }) do
  status_theme[mode] = {
    a = { fg = c.text, bg = c.base },
    b = { fg = c.text, bg = c.base },
    c = { fg = c.muted, bg = c.base },
  }
end

local function mode_color()
  local mode = vim.api.nvim_get_mode().mode:sub(1, 1)
  local accent = ({
    i = c.teal,
    v = c.peach,
    V = c.peach,
    [string.char(22)] = c.peach,
    s = c.peach,
    S = c.peach,
    [string.char(19)] = c.peach,
    R = c.red,
    c = c.peach,
    t = c.teal,
  })[mode] or c.lavender
  return { fg = c.chrome, bg = accent, gui = "bold" }
end

local function position()
  local line, total = vim.fn.line("."), vim.fn.line("$")
  local progress = line == 1 and "Top"
    or line == total and "Bot"
    or string.format("%d%%%%", math.floor(100 * line / total))
  return string.format("%d:%d · %s", line, vim.fn.virtcol("."), progress)
end

local capsule = { left = "", right = "" }

require("lualine").setup({
  options = {
    theme = status_theme,
    globalstatus = false,
    component_separators = "",
    section_separators = "",
    disabled_filetypes = {
      statusline = { "workbench-frame", "neo-tree" },
      winbar = {
        "neo-tree",
        "ministarter",
        "terminal",
        "qf",
        "help",
        "mason",
        "notify",
        "workbench-frame",
      },
    },
  },
  sections = {
    lualine_a = {
      { "mode", icon = "", color = mode_color, separator = capsule },
    },
    lualine_b = {
      { "branch", icon = "" },
      { "diff", symbols = { added = "+", modified = "~", removed = "-" } },
    },
    lualine_c = {
      {
        "filename",
        path = 1,
        fmt = function(path)
          if vim.bo.buftype == "quickfix" then
            local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
            local list = info.loclist == 1 and vim.fn.getloclist(0, { title = 1 })
              or vim.fn.getqflist({ title = 1 })
            return ((list.title ~= "" and list.title or "Quickfix"):gsub("%%", "%%%%"))
          end
          if vim.bo.filetype == "neo-tree" then
            return "Explorer · " .. vim.fn.fnamemodify(navigation.project_root(), ":t")
          end
          return path
        end,
        symbols = { modified = " ●", readonly = " ", unnamed = "[New File]" },
      },
    },
    lualine_x = {
      { "diagnostics", symbols = { error = " ", warn = " ", info = " ", hint = "󰌵 " } },
      { lsp_status, color = { fg = c.teal } },
      function()
        return (screenkey.get_keys():gsub("%%", "%%%%"))
      end,
      "encoding",
      "fileformat",
    },
    lualine_y = { { "filetype", colored = true } },
    lualine_z = {
      { position, color = { fg = c.text, bg = c.overlay }, separator = capsule },
    },
  },
  winbar = {},
  inactive_winbar = {},
  inactive_sections = {
    lualine_c = { { "filename", path = 1, color = { fg = c.muted, bg = c.base } } },
    lualine_x = {
      function()
        return (screenkey.get_keys():gsub("%%", "%%%%"))
      end,
      "encoding",
      "filetype",
    },
  },
  extensions = {
    {
      filetypes = { "neo-tree" },
      sections = {
        lualine_c = {
          {
            function()
              return "󰉋 " .. vim.fn.fnamemodify(navigation.project_root(), ":t")
            end,
            color = { fg = c.muted, bg = c.sidebar },
            padding = 1,
          },
        },
      },
      inactive_sections = {
        lualine_c = {
          {
            function()
              return "󰉋 " .. vim.fn.fnamemodify(navigation.project_root(), ":t")
            end,
            color = { fg = c.muted, bg = c.sidebar },
            padding = 1,
          },
        },
      },
    },
    {
      filetypes = { "ministarter" },
      sections = {
        lualine_a = {
          {
            function()
              return " FORGE"
            end,
            color = mode_color,
            separator = capsule,
          },
        },
        lualine_c = {
          function()
            return vim.fn.fnamemodify(vim.fn.getcwd(), ":~")
          end,
        },
        lualine_x = {
          function()
            return "Neovim " .. tostring(vim.version())
          end,
        },
        lualine_z = {
          {
            function()
              return os.date("%H:%M")
            end,
            color = { fg = c.text, bg = c.overlay },
            separator = capsule,
          },
        },
      },
    },
  },
})

-- Pane statuslines belong to the outline; Lualine only formats the final footer.
require("lualine").hide({ place = { "statusline" } })
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("WorkbenchFooterTheme", { clear = true }),
  callback = function()
    vim.schedule(function()
      require("lualine").hide({ place = { "statusline" } })
      require("config.frame").refresh()
    end)
  end,
})

require("which-key").setup({ preset = "modern", delay = 350, win = { border = "rounded" } })
require("which-key").add({
  { "<leader>b", group = "Buffers" },
  { "<leader>c", group = "Code" },
  { "<leader>f", group = "Find" },
  { "<leader>g", group = "Git" },
  { "<leader>u", group = "UI / Tools" },
  { "<leader>x", group = "Diagnostics" },
  { "<leader>t", group = "Terminal / Build" },
  { "<leader>s", group = "Search" },
})

require("gitsigns").setup({
  signs = {
    add = { text = "▎" },
    change = { text = "▎" },
    delete = { text = "" },
    topdelete = { text = "" },
    changedelete = { text = "▎" },
    untracked = { text = "▎" },
  },
  current_line_blame = false,
  on_attach = function(buf)
    local gs = require("gitsigns")
    local map = function(key, fn, desc)
      vim.keymap.set("n", key, fn, { buffer = buf, desc = desc })
    end
    map("]h", function()
      gs.nav_hunk("next")
    end, "Next Git Hunk")
    map("[h", function()
      gs.nav_hunk("prev")
    end, "Previous Git Hunk")
    map("<leader>gp", gs.preview_hunk, "Preview Git Hunk")
    map("<leader>gs", gs.stage_hunk, "Stage Git Hunk")
    map("<leader>gr", gs.reset_hunk, "Reset Git Hunk")
    map("<leader>gb", gs.blame_line, "Blame Line")
  end,
})

screenkey.setup({
  clear_after = 2,
  compress_after = 3,
  group_mappings = true,
  show_leader = true,
  disable = { modes = { "i", "c" }, buftypes = { "terminal" }, filetypes = { "ministarter" } },
  win_opts = { width = 24 },
})
if screenkey.is_active() then
  screenkey.toggle()
end
if not screenkey.statusline_component_is_active() then
  screenkey.toggle_statusline_component()
end
vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("ScreenkeyStatusline", { clear = true }),
  pattern = { "ScreenkeyUpdated", "ScreenkeyCleared" },
  callback = function()
    vim.schedule(function()
      require("config.footer").refresh()
    end)
  end,
})
