local M = {}

local function validate(value)
  local height = tonumber(value)
  if not height or height < 1.42 or height > 1.65 then
    return nil, "行高范围为 1.42–1.65，例如 :UiLineHeight 1.48"
  end
  if math.abs(height * 100 - math.floor(height * 100 + 0.5)) > 0.000001 then
    return nil, "行高按 0.01 的步长调整，例如 1.42、1.48、1.55、1.60"
  end
  return string.format("%.2f", height)
end

local function manual_height(opts, height)
  local shapes = require("config.shapes")
  if not height then
    vim.notify(
      string.format(
        "当前几何行高 %.2f。请手动调整终端行高，再用 :UiLineHeight 1.48 同步几何字形和缓存。",
        shapes.height
      ),
      vim.log.levels.INFO
    )
    return
  end
  local path = vim.fn.expand(opts.state or (vim.fn.stdpath("state") .. "/workbench-ui.json"))
  local cache = {}
  if vim.fn.filereadable(path) == 1 then
    local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
    if ok and type(decoded) == "table" then
      cache = decoded
    end
  end
  cache.height = tonumber(height)
  cache.source = "manual"
  cache.updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
  local temporary = path .. ".tmp-" .. vim.uv.os_getpid() .. "-" .. tostring(vim.uv.hrtime())
  local ok, error = pcall(function()
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    assert(vim.fn.writefile({ vim.json.encode(cache) }, temporary) == 0, "cache write failed")
    local renamed, reason = vim.uv.fs_rename(temporary, path)
    assert(renamed, reason)
  end)
  if not ok then
    pcall(vim.fn.delete, temporary)
  end
  shapes.set_height(tonumber(height))
  require("config.frame").refresh()
  vim.cmd.redrawtabline()
  vim.notify(
    "几何行高已同步为 "
      .. height
      .. "；请在终端中手动设置相同行高。"
      .. (ok and " 本地缓存已保存。" or (" 缓存写入失败：" .. tostring(error))),
    ok and vim.log.levels.INFO or vim.log.levels.WARN
  )
end

function M.setup(opts)
  opts = opts or {}
  vim.api.nvim_create_user_command("UiLineHeight", function(command)
    local height
    if command.args ~= "" then
      local error
      height, error = validate(command.args)
      if not height then
        vim.notify(error, vim.log.levels.WARN, { title = "FORGE · 行高" })
        return
      end
    end
    local in_wsl = vim.env.WSL_DISTRO_NAME ~= nil or vim.env.WSL_INTEROP ~= nil
    if opts.enabled == false or not in_wsl or (not vim.env.WT_SESSION and not opts.settings) then
      manual_height(opts, height)
      return
    end
    local python = opts.python or "python3"
    if type(python) ~= "string" or vim.fn.executable(python) ~= 1 then
      vim.notify(
        "找不到 Python 后台程序；请在 local.lua 设置 terminal_ui.python。",
        vim.log.levels.ERROR
      )
      return
    end
    local argv = {
      python,
      vim.fs.joinpath(vim.fn.stdpath("config"), "scripts", "terminal-ui.py"),
      "--profile",
      opts.profile or "Fedora",
      "--state",
      opts.state or (vim.fn.stdpath("state") .. "/workbench-ui.json"),
      "--backup-dir",
      opts.backup_dir or (vim.fn.stdpath("state") .. "/terminal-ui-backups"),
    }
    if opts.guid and opts.guid ~= "" then
      vim.list_extend(argv, { "--guid", opts.guid })
    end
    if opts.settings then
      vim.list_extend(argv, { "--settings", opts.settings })
    end
    if height then
      vim.list_extend(argv, { "--set", height })
    end
    local ok, error = pcall(vim.system, argv, { text = true }, function(process)
      vim.schedule(function()
        local decoded, result = pcall(vim.json.decode, process.stdout or "")
        if process.code ~= 0 or not decoded or type(result) ~= "table" or not result.ok then
          local message = decoded and type(result) == "table" and result.error
            or process.stderr
            or "无法读取 Windows Terminal 设置"
          if message == "" then
            message = "无法读取 Windows Terminal 设置"
          end
          vim.notify(message, vim.log.levels.ERROR, { title = "FORGE · 行高" })
          return
        end
        local shapes = require("config.shapes")
        shapes.set_height(tonumber(result.height))
        require("config.frame").refresh()
        vim.cmd.redrawtabline()
        local current = result.height and string.format("%.2f", result.height)
          or tostring(result.cellHeight)
        local profile = tostring(result.profile or opts.profile or "Windows Terminal")
        local message = height
            and (profile .. " 行高已设为 " .. current .. "，Windows Terminal 会自动刷新。")
          or (
            profile
            .. " 当前行高："
            .. current
            .. " × 字号。几何模式建议 1.42–1.65。"
          )
        if result.source == "natural" then
          message = message .. " 当前使用字体自然行高。"
        elseif result.source == "defaults" then
          message = message .. " 当前继承 profiles.defaults。"
        end
        if result.warning then
          message = message .. "\n" .. result.warning
        end
        vim.notify(message, result.warning and vim.log.levels.WARN or vim.log.levels.INFO, {
          title = "FORGE · 行高",
        })
      end)
    end)
    if not ok then
      vim.notify("无法启动行高后台：" .. tostring(error), vim.log.levels.ERROR)
    end
  end, {
    nargs = "?",
    desc = "WSL/Windows Terminal 行高；其他终端请手动设置",
    complete = function(lead)
      return vim.tbl_filter(function(value)
        return value:sub(1, #lead) == lead
      end, { "1.42", "1.48", "1.55", "1.60" })
    end,
  })
end

return M
