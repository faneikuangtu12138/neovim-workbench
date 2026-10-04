local M = {}
local last_editor = {}

-- Named utility buffers can look like paths (ministarter:/1/1, term://...).
-- Only normal filesystem buffers participate in reveal and project lookup.
local function filesystem_path(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return nil
  end
  if name:match("^%a[%w+.-]*:") and not name:match("^%a:[/\\]") then
    return nil
  end
  return name
end

local function is_editor(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end
  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return false
  end
  local buf = vim.api.nvim_win_get_buf(win)
  return vim.bo[buf].filetype ~= "neo-tree"
    and (vim.bo[buf].buftype == "" or vim.bo[buf].filetype == "ministarter")
end

local function remember_editor()
  local win = vim.api.nvim_get_current_win()
  if is_editor(win) then
    last_editor[vim.api.nvim_get_current_tabpage()] = win
  end
end

function M.editor_window()
  local tab = vim.api.nvim_get_current_tabpage()
  local remembered = last_editor[tab]
  if is_editor(remembered) and vim.api.nvim_win_get_tabpage(remembered) == tab then
    return remembered
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if is_editor(win) then
      last_editor[tab] = win
      return win
    end
  end
end

function M.return_editor()
  local win = M.editor_window()
  if win then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd("rightbelow vnew")
    remember_editor()
  end
end

local function tree_command(toggle)
  remember_editor()
  local tab = vim.api.nvim_get_current_tabpage()
  local origin = last_editor[tab]
  local path = filesystem_path(vim.api.nvim_get_current_buf())
  require("neo-tree.command").execute({
    source = "filesystem",
    position = "left",
    action = "focus",
    toggle = toggle,
    dir = M.project_root(),
    -- Explicit false overrides Neo-tree's follow_current_file default on
    -- dashboards, unnamed buffers, terminals, help and other virtual buffers.
    reveal = path ~= nil,
    reveal_file = path,
  })
  -- A newly created tree split briefly contains the editor buffer before
  -- Neo-tree assigns its own buffer. Keep that transient WinEnter from
  -- replacing the editor that actually opened the sidebar.
  if is_editor(origin) then
    last_editor[tab] = origin
  end
end

function M.focus_tree()
  tree_command(false)
end

function M.toggle_tree_visibility()
  local from_tree = vim.bo.filetype == "neo-tree"
  tree_command(true)
  if from_tree then
    M.return_editor()
  end
end

function M.toggle_tree_focus()
  if vim.bo.filetype == "neo-tree" then
    M.return_editor()
  else
    M.focus_tree()
  end
end

function M.project_root()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "" or vim.bo[buf].filetype == "neo-tree" then
    local win = M.editor_window()
    buf = win and vim.api.nvim_win_get_buf(win) or nil
  end
  local path = filesystem_path(buf)
  local start = path or vim.fn.getcwd()
  local stat = vim.uv.fs_stat(start)
  if not stat or stat.type ~= "directory" then
    start = vim.fs.dirname(start)
  end
  -- New files can name directories that do not exist yet. Search from the
  -- nearest existing parent so terminals/builds always receive a valid cwd.
  while start do
    stat = vim.uv.fs_stat(start)
    if stat and stat.type == "directory" then
      break
    end
    local parent = vim.fs.dirname(start)
    if parent == start then
      start = nil
      break
    end
    start = parent
  end
  start = start or vim.fn.getcwd()
  return vim.fs.root(start, {
    ".git",
    ".clangd",
    "compile_commands.json",
    "compile_flags.txt",
    "Makefile",
    "makefile",
    "GNUmakefile",
    "CMakeLists.txt",
    "pyproject.toml",
    "pyrightconfig.json",
    "ruff.toml",
    ".ruff.toml",
    "setup.py",
    ".perlcriticrc",
    "verible.filelist",
    "tclint.toml",
    ".tclint",
    ".luarc.json",
    ".luarc.jsonc",
    "Cargo.toml",
    "package.json",
  }) or start
end

function M.setup()
  local group = vim.api.nvim_create_augroup("EditorNavigation", { clear = true })
  vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter" }, {
    group = group,
    callback = remember_editor,
  })
  vim.api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = function()
      for tab in pairs(last_editor) do
        if not vim.api.nvim_tabpage_is_valid(tab) then
          last_editor[tab] = nil
        end
      end
    end,
  })
  remember_editor()
end

return M
