local function selected_node_id(state)
  if not state.tree or not state.winid or not vim.api.nvim_win_is_valid(state.winid) then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(state.winid)[1]
  local node = state.tree:get_node(row)
  return node and node:get_id() or nil
end

local function rounded_name(config, node, state, available_width)
  local result = require("neo-tree.sources.common.components").name(config, node, state)
  if node:get_depth() == 1 and node.type == "directory" then
    result.text = vim.fn.fnamemodify(node:get_id(), ":t") .. "/"
  end
  -- Leave room for both rounded ends and the diagnostic / Git indicators.
  local max_label = math.max(1, (available_width or 80) - 8)
  if vim.fn.strdisplaywidth(result.text) > max_label then
    result.text = require("neo-tree.utils").truncate_by_cell(
      result.text,
      math.max(0, max_label - 1)
    ) .. "…"
  end
  -- Read the completed selection snapshot. Querying the tree's row lookup
  -- during component rendering would cache partially rebuilt node heights.
  if node:get_id() ~= state._workbench_capsule_rendered_id then
    -- Reserve the same width on every row so names do not shift on selection.
    result.text = "  " .. result.text .. "  "
    return result
  end
  return {
    { text = "", highlight = "WorkbenchTreeSelectionCap" },
    { text = " " .. result.text .. " ", highlight = "WorkbenchTreeSelection" },
    { text = "", highlight = "WorkbenchTreeSelectionCap" },
  }
end

-- Resolve selection only after the full Nui tree is rendered. WinEnter can
-- occur while Neo-tree is still constructing its rows; querying row lookup
-- there would cache unfinished node heights. Coalesce movement and initial
-- renders, and skip repaint when the completed selection has not changed.
local function refresh_capsule(state)
  if not state or state._workbench_capsule_pending then
    return
  end
  state._workbench_capsule_pending = true
  vim.defer_fn(function()
    state._workbench_capsule_pending = false
    if state._workbench_capsule_rendering then
      return
    end
    if not state.tree or not state.winid or not vim.api.nvim_win_is_valid(state.winid) then
      return
    end
    if vim.api.nvim_win_get_buf(state.winid) ~= state.bufnr then
      return
    end
    local current_id = selected_node_id(state)
    if current_id == state._workbench_capsule_rendered_id then
      return
    end
    state._workbench_capsule_rendered_id = current_id
    local renderer = require("neo-tree.ui.renderer")
    renderer.position.save(state, true)
    renderer.redraw(state)
  end, 16)
end

local capsule_group = vim.api.nvim_create_augroup("WorkbenchTreeCapsule", { clear = true })
vim.api.nvim_create_autocmd({ "CursorMoved", "WinEnter", "BufEnter" }, {
  group = capsule_group,
  callback = function()
    if vim.bo.filetype == "neo-tree" then
      refresh_capsule(require("neo-tree.sources.manager").get_state_for_window())
    end
  end,
})

require("neo-tree").setup({
  event_handlers = {
    {
      event = "before_render",
      handler = function(state)
        state._workbench_capsule_rendering = true
      end,
    },
    {
      event = "after_render",
      handler = function(state)
        state._workbench_capsule_rendering = false
        refresh_capsule(state)
      end,
    },
  },
  close_if_last_window = true,
  popup_border_style = "rounded",
  enable_git_status = true,
  enable_diagnostics = true,
  open_files_in_last_window = true,
  open_files_do_not_replace_types = {
    "terminal",
    "qf",
    "help",
    "mason",
    "notify",
    "workbench-frame",
  },
  sources = { "filesystem", "buffers", "git_status" },
  source_selector = {
    winbar = false,
    statusline = false,
    tabs_layout = "equal",
    content_layout = "center",
    show_separator_on_edge = true,
    separator = { left = "", right = "" },
    separator_active = { left = "", right = "" },
    sources = {
      { source = "filesystem", display_name = "󰉓 Files" },
      { source = "buffers", display_name = "󰈙 Bufs" },
      { source = "git_status", display_name = " Git" },
    },
  },
  filesystem = {
    bind_to_cwd = false,
    components = {
      name = rounded_name,
    },
    follow_current_file = { enabled = true, leave_dirs_open = true },
    hijack_netrw_behavior = "open_default",
    use_libuv_file_watcher = true,
    filtered_items = {
      visible = false,
      hide_dotfiles = false,
      hide_gitignored = true,
      never_show = { ".git", "node_modules", "__pycache__", ".venv" },
    },
  },
  buffers = { bind_to_cwd = false, components = { name = rounded_name } },
  git_status = { components = { name = rounded_name } },
  window = {
    position = "left",
    width = 34,
    mappings = {
      ["<space>"] = "none",
      ["<CR>"] = "open",
      ["l"] = "open",
      ["h"] = "close_node",
      ["a"] = { "add", config = { show_path = "relative" } },
      ["A"] = { "add_directory", config = { show_path = "relative" } },
      ["P"] = { "toggle_preview", config = { use_float = true } },
      ["<Tab>"] = function()
        require("core.navigation").return_editor()
      end,
    },
  },
  default_component_configs = {
    indent = {
      indent_size = 2,
      with_markers = true,
      indent_marker = "│",
      last_indent_marker = "╰",
      expander_collapsed = "",
      expander_expanded = "",
    },
    name = { use_git_status_colors = false, highlight_opened_files = true },
    icon = { folder_closed = "", folder_open = "", folder_empty = "󰜌" },
    git_status = {
      symbols = {
        added = "✚",
        modified = "",
        deleted = "✖",
        renamed = "󰁕",
        untracked = "",
        ignored = "",
        unstaged = "󰄱",
        staged = "",
        conflict = "",
      },
    },
  },
})
