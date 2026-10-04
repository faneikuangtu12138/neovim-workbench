require("notify").setup({
  stages = "fade",
  timeout = 2500,
  render = "compact",
  background_colour = vim.g.workbench_colors.base,
  max_width = 70,
  max_height = 12,
})
vim.notify = require("notify")

local function completion_row()
  -- Nui percentages depend on the popup's height. An absolute row keeps the
  -- completion border below the one-line command box even for long menus.
  return math.floor((vim.o.lines - 1) * 0.18) + 4
end

local function completion_height()
  return math.max(1, math.min(15, vim.o.lines - completion_row() - 3))
end

require("noice").setup({
  cmdline = {
    enabled = true,
    view = "cmdline_popup",
    format = {
      cmdline = { pattern = "^:", icon = "", lang = "vim" },
      search_down = { kind = "search", pattern = "^/", icon = " ", lang = "regex" },
      search_up = { kind = "search", pattern = "^%?", icon = " ", lang = "regex" },
    },
  },
  lsp = {
    progress = { enabled = false },
    signature = { enabled = false }, -- Blink handles signature help.
    override = {
      ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
      ["vim.lsp.util.stylize_markdown"] = true,
    },
  },
  presets = {
    bottom_search = false,
    command_palette = true,
    long_message_to_split = true,
    lsp_doc_border = true,
  },
  views = {
    cmdline_popup = {
      position = { row = "18%", col = "50%" },
      size = { width = 60, height = "auto" },
      border = { style = "rounded", padding = { 0, 1 } },
    },
    popupmenu = {
      relative = "editor",
      position = { row = "26%", col = "50%" },
      size = { width = 60, height = 10 },
      border = { style = "rounded", padding = { 0, 1 } },
    },
    cmdline_popupmenu = {
      relative = "editor",
      position = { row = completion_row(), col = "50%" },
      size = { width = 60, height = "auto", max_height = completion_height() },
      border = { style = "rounded", padding = { 0, 1 } },
      win_options = {
        winhighlight = {
          Normal = "NoicePopupmenu",
          FloatBorder = "NoicePopupmenuBorder",
          CursorLine = "NoicePopupmenuSelected",
          PmenuMatch = "NoicePopupmenuMatch",
        },
      },
    },
  },
  routes = {
    { filter = { event = "msg_show", kind = "", find = "written" }, opts = { skip = true } },
    { filter = { event = "msg_show", find = "search hit BOTTOM" }, opts = { skip = true } },
    { filter = { event = "msg_show", find = "search hit TOP" }, opts = { skip = true } },
  },
})

vim.api.nvim_create_autocmd({ "UIEnter", "VimResized", "CmdlineEnter" }, {
  group = vim.api.nvim_create_augroup("WorkbenchCommandGeometry", { clear = true }),
  callback = function(event)
    local menu = require("noice.config").options.views.cmdline_popupmenu
    menu.position.row = completion_row()
    menu.size.max_height = completion_height()
    if event.event == "VimResized" then
      -- Reflow both boxes together without changing the input or selection.
      local cmdline = package.loaded["noice.ui.cmdline"]
      local popup = package.loaded["noice.ui.popupmenu"]
      if cmdline and cmdline.win() then
        vim.schedule(function()
          if cmdline.win() then
            cmdline.update()
            require("noice.message.router").update()
          end
          if popup and popup.backend and popup.state.visible and popup.state.grid == -1 then
            popup.backend.on_show(popup.state)
          end
        end)
      end
    end
  end,
})
