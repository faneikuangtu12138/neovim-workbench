local M = {}
local terminals, orphaned = {}, {}
local builds, results, last_command = {}, {}, {}

-- Match Neovim's :help shell-unquoting. Preserve Windows path backslashes,
-- quoted executable paths and fixed arguments in both shell options.
local function shell_words(value)
  local words, current, quoted, started = {}, {}, false, false
  local index = 1
  local function finish()
    if started then
      words[#words + 1] = table.concat(current)
      current, started = {}, false
    end
  end
  while index <= #value do
    local character = value:sub(index, index)
    if quoted and character == "\\" then
      local next_character = value:sub(index + 1, index + 1)
      if next_character == "\\" or next_character == '"' then
        current[#current + 1] = next_character
        index = index + 2
      else
        current[#current + 1] = character
        index = index + 1
      end
      started = true
    elseif character == '"' then
      quoted, started = not quoted, true
      index = index + 1
    elseif not quoted and character:match("%s") then
      finish()
      index = index + 1
    else
      current[#current + 1] = character
      started = true
      index = index + 1
    end
  end
  if quoted then
    error("Unmatched double quote in shell or shellcmdflag")
  end
  finish()
  return words
end

local function shell_command(command)
  local argv = shell_words(vim.o.shell)
  if #argv == 0 then
    error("The shell option is empty")
  end
  if command then
    vim.list_extend(argv, shell_words(vim.o.shellcmdflag))
    argv[#argv + 1] = command
  end
  return argv
end

local function navigation()
  return require("core.navigation")
end

local function project_root()
  local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  for cwd, state in pairs(terminals[vim.api.nvim_get_current_tabpage()] or {}) do
    if state.win == win and state.buf == buf then
      return cwd
    end
  end
  local path = navigation().project_root()
  return vim.uv.fs_realpath(path) or vim.fs.normalize(path)
end

local function visible(state, tab)
  return state
    and state.win
    and vim.api.nvim_win_is_valid(state.win)
    and vim.api.nvim_win_get_tabpage(state.win) == tab
    and vim.api.nvim_win_get_buf(state.win) == state.buf
end

local function alive(state)
  return state
    and vim.api.nvim_buf_is_valid(state.buf)
    and state.job
    and vim.fn.jobwait({ state.job }, 0)[1] == -1
end

local function take_orphan(cwd)
  local pool = orphaned[cwd]
  while pool and #pool > 0 do
    local state = table.remove(pool)
    if alive(state) then
      return state
    end
    if vim.api.nvim_buf_is_valid(state.buf) then
      pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
    end
  end
end

function M.toggle()
  local tab, cwd = vim.api.nvim_get_current_tabpage(), project_root()
  local pool = terminals[tab] or {}
  terminals[tab] = pool
  local state = pool[cwd]
  if visible(state, tab) then
    -- Rails and the footer are native windows too. Always return/create a real
    -- editor before closing a terminal, even when it is the sole content pane.
    navigation().return_editor()
    vim.api.nvim_win_close(state.win, false)
    state.win = nil
    return
  end

  local showing
  for _, candidate in pairs(pool) do
    if visible(candidate, tab) then
      showing = candidate
      break
    end
  end
  if state and not alive(state) then
    if vim.api.nvim_buf_is_valid(state.buf) then
      pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
    end
    state = nil
    pool[cwd] = nil
  end
  state = state or take_orphan(cwd)
  navigation().return_editor()
  local win = showing and showing.win
  if not win then
    local height = math.max(5, math.min(12, math.floor(vim.o.lines * 0.30)))
    -- Do not remember the temporary editor clone as the last editor window.
    vim.cmd("noautocmd botright " .. height .. "split")
    win = vim.api.nvim_get_current_win()
  end
  if state then
    vim.api.nvim_win_set_buf(win, state.buf)
  else
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(win, buf)
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].filetype = "terminal"
    state = { buf = buf, cwd = cwd }
    -- term=true binds the process to the current buffer, not merely the
    -- target of nvim_win_set_buf when reusing another project's visible pane.
    vim.api.nvim_set_current_win(win)
    local ok, job = pcall(function()
      return vim.fn.jobstart(shell_command(), { term = true, cwd = cwd })
    end)
    state.job = ok and job or nil
    if not ok or job <= 0 then
      if showing then
        vim.api.nvim_win_set_buf(win, showing.buf)
      else
        vim.api.nvim_win_close(win, true)
      end
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
      navigation().return_editor()
      vim.notify(
        "Could not start terminal: " .. vim.o.shell .. " · " .. tostring(job),
        vim.log.levels.ERROR
      )
      return
    end
  end
  if showing then
    showing.win = nil
  end
  pool[cwd] = state
  state.win = win
  vim.api.nvim_set_current_win(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].winfixheight = true
  vim.cmd.startinsert()
end

local function list_exists(state)
  return state.qfid and vim.fn.getqflist({ id = state.qfid }).id == state.qfid
end

local function list_contents(state)
  local result = state.result
  local lines = {}
  if result then
    local output = (result.stdout or "") .. "\n" .. (result.stderr or "")
    lines = vim.split(output, "\n", { plain = true, trimempty = true })
  end
  -- The directory stack resolves relative compiler paths without changing cwd.
  table.insert(lines, 1, "__NVIM_BUILD_CWD__" .. state.cwd)
  lines[#lines + 1] = "__NVIM_BUILD_END__" .. state.cwd
  return {
    title = "Build: " .. state.command .. " · " .. vim.fn.fnamemodify(state.cwd, ":~"),
    lines = lines,
    efm = "%D__NVIM_BUILD_CWD__%f,%X__NVIM_BUILD_END__%f," .. state.errorformat,
    context = {
      cwd = state.cwd,
      command = state.command,
      exit_code = result and result.code or vim.NIL,
      running = result == nil,
      origin_tab = state.tab,
    },
  }
end

local function create_list(state)
  vim.fn.setqflist({}, " ", list_contents(state))
  state.qfid = vim.fn.getqflist({ id = 0 }).id
end

local function select_list(state)
  if not list_exists(state) then
    create_list(state)
  else
    local nr = vim.fn.getqflist({ id = state.qfid, nr = 0 }).nr
    vim.cmd("silent chistory " .. nr)
  end
end

local function open_list(state)
  select_list(state)
  local prior = vim.api.nvim_get_current_win()
  vim.cmd("botright copen 10")
  if vim.api.nvim_win_is_valid(prior) then
    vim.api.nvim_set_current_win(prior)
  end
end

function M.show_results()
  local state = results[project_root()]
  if not state then
    vim.notify("No build results for this project yet.", vim.log.levels.INFO)
    return
  end
  open_list(state)
end

local function publish_build(state, result)
  if builds[state.tab] == state then
    builds[state.tab] = nil
  end
  state.result = result
  -- Replacing a stored ID leaves the currently selected list alone. A late
  -- build from another/closed tab must never take over its diagnostics.
  if list_exists(state) then
    local contents = list_contents(state)
    contents.id = state.qfid
    vim.fn.setqflist({}, "r", contents)
  end
  local project = vim.fn.fnamemodify(state.cwd, ":~")
  if result.code ~= 0 then
    vim.notify(
      "Build failed in " .. project .. " (exit " .. result.code .. "). See :BuildResults.",
      vim.log.levels.ERROR
    )
    if
      vim.api.nvim_tabpage_is_valid(state.tab)
      and vim.api.nvim_get_current_tabpage() == state.tab
      and project_root() == state.cwd
    then
      open_list(state)
    end
  else
    vim.notify("Build completed in " .. project .. ": " .. state.command, vim.log.levels.INFO)
  end
end

function M.build(default)
  local tab = vim.api.nvim_get_current_tabpage()
  if builds[tab] then
    vim.notify("A build is already pending or running in this tab.", vim.log.levels.WARN)
    return
  end
  local cwd = project_root()
  local win = navigation().editor_window()
  local buf = win and vim.api.nvim_win_get_buf(win) or vim.api.nvim_get_current_buf()
  local errorformat = vim.bo[buf].errorformat
  if errorformat == "" then
    errorformat = vim.o.errorformat
  end
  local state = { tab = tab, cwd = cwd, errorformat = errorformat }
  builds[tab] = state
  vim.ui.input({
    prompt = "Build in " .. vim.fn.fnamemodify(cwd, ":~") .. ": ",
    default = default and default ~= "" and default or last_command[cwd] or "make",
  }, function(command)
    if not command or vim.trim(command) == "" or not vim.api.nvim_tabpage_is_valid(tab) then
      builds[tab] = nil
      return
    end
    last_command[cwd] = command
    state.command = command
    -- This list is created by the user's explicit start action, not by a
    -- background completion. Store the ID for all subsequent updates.
    create_list(state)
    local ok, process = pcall(function()
      return vim.system(shell_command(command), {
        cwd = cwd,
        text = true,
      }, function(result)
        vim.schedule(function()
          publish_build(state, result)
        end)
      end)
    end)
    if not ok then
      builds[tab] = nil
      state.result = { code = -1, stdout = "", stderr = tostring(process) }
      local contents = list_contents(state)
      contents.id = state.qfid
      vim.fn.setqflist({}, "r", contents)
      results[cwd] = state
      vim.notify(
        "Could not start build in " .. vim.fn.fnamemodify(cwd, ":~") .. ": " .. tostring(process),
        vim.log.levels.ERROR
      )
      return
    end
    state.process = process
    results[cwd] = state
    vim.notify(
      "Building in " .. vim.fn.fnamemodify(cwd, ":~") .. ": " .. command,
      vim.log.levels.INFO
    )
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("TermToggle", M.toggle, { desc = "Toggle project terminal" })
  vim.api.nvim_create_user_command(
    "BuildResults",
    M.show_results,
    { desc = "Show this project's last build output" }
  )
  vim.api.nvim_create_user_command(
    "Build",
    function(opts)
      M.build(opts.args)
    end,
    { nargs = "*", complete = "shellcmd", desc = "Prompt and run an asynchronous project build" }
  )
  vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Terminal normal mode" })
  local group = vim.api.nvim_create_augroup("ProjectTerminal", { clear = true })
  vim.api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = function()
      for tab, pool in pairs(terminals) do
        if not vim.api.nvim_tabpage_is_valid(tab) then
          for cwd, state in pairs(pool) do
            -- Closing a tab hides these buffers. Preserve ongoing shell jobs
            -- for explicit project reuse instead of killing them implicitly.
            state.win = nil
            orphaned[cwd] = orphaned[cwd] or {}
            table.insert(orphaned[cwd], state)
          end
          terminals[tab] = nil
        end
      end
    end,
  })
end

return M
