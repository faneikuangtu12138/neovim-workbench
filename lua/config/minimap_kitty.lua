-- Kitty graphics: cached transparent text over an independently updated shade.
-- Only this module's image IDs are deleted; other terminal images are untouched.
local M = {}
local next_id = 100000000 + (vim.fn.getpid() % 100000) * 10000
local compression
local ok, ffi = pcall(require, "ffi")
if ok then
  pcall(
    ffi.cdef,
    [[
    unsigned long compressBound(unsigned long sourceLen);
    int compress2(unsigned char *dest, unsigned long *destLen,
                  const unsigned char *source, unsigned long sourceLen, int level);
    int ioctl(int fd, unsigned long request, ...);
  ]]
  )
  local loaded, z = pcall(ffi.load, "z")
  if loaded then
    compression = z
  end
end

function M.cell_size()
  -- Read metadata only; never compete with Neovim for terminal input.
  if not ok or vim.uv.os_uname().sysname ~= "Linux" then
    return
  end
  local paths = { "/dev/tty" }
  -- Nvim's TUI may run in a parent process with the core on RPC pipes.
  -- Open only terminal descriptors, and use ioctl without reading input.
  for _, pid in ipairs({ vim.fn.getpid(), vim.uv.os_getppid() }) do
    for fd = 0, 2 do
      local path = string.format("/proc/%d/fd/%d", pid, fd)
      local target = vim.uv.fs_readlink(path)
      if target and (target:match("^/dev/pts/") or target:match("^/dev/tty")) then
        paths[#paths + 1] = path
      end
    end
  end
  for _, path in ipairs(paths) do
    local fd = vim.uv.fs_open(path, "r", 0)
    if fd then
      local size = ffi.new("unsigned short[4]")
      local status = ffi.C.ioctl(fd, 0x5413, size)
      vim.uv.fs_close(fd)
      if status == 0 and size[0] > 0 and size[1] > 0 and size[2] > 0 and size[3] > 0 then
        return math.floor(size[2] / size[1] + 0.5), math.floor(size[3] / size[0] + 0.5)
      end
    end
  end
end

local function command(control, data)
  return "\27_G" .. control .. (data and (";" .. data) or "") .. "\27\\"
end

function M.upload(id, payload, format, width, height, compressed)
  local chunks = {}
  for start = 1, #payload, 4096 do
    local part = payload:sub(start, start + 4095)
    local more = start + 4096 <= #payload and 1 or 0
    local control = "q=2,m=" .. more
    if start == 1 then
      control = string.format("a=t,t=d,f=%d,i=%d,s=%d,v=%d,", format, id, width, height)
        .. (compressed and "o=z," or "")
        .. control
    end
    chunks[#chunks + 1] = command(control, part)
  end
  return table.concat(chunks)
end

local function place(id, rect, row, z)
  return string.format("\27[%d;%dH", rect.y + row, rect.x + 1)
    .. command(string.format("a=p,i=%d,p=1,c=%d,r=1,C=1,z=%d,q=2", id, rect.width, z))
end

local function rgb(color)
  return string.char(math.floor(color / 65536), math.floor(color / 256) % 256, color % 256)
end

-- The shade is opaque RGB. Transparent, anti-aliased ink is a separate PNG.
function M.shade(rectangles, row, model)
  local top, width, height = (row - 1) * model.cell_height, model.pixel_width, model.cell_height
  local clipped, signature =
    {}, { model.background, model.view_background, model.active_background, width, height }
  for _, r in ipairs(rectangles) do
    local first, last = math.max(top, r[2]), math.min(top + height, r[4])
    if first < last then
      local item = { r[1], first - top, r[3], last - top, r[5] }
      clipped[#clipped + 1] = item
      vim.list_extend(signature, item)
    end
  end
  local key = table.concat(signature, ":")
  return key,
    function()
      local rows = {}
      local colors = { rgb(model.view_background), rgb(model.active_background) }
      local base = string.rep(rgb(model.background), width)
      for y = 0, height - 1 do
        local line = base
        for _, r in ipairs(clipped) do
          if y >= r[2] and y < r[4] then
            line = line:sub(1, r[1] * 3)
              .. string.rep(colors[r[5] + 1], r[3] - r[1])
              .. line:sub(r[3] * 3 + 1)
          end
        end
        rows[#rows + 1] = line
      end
      local raw = table.concat(rows)
      if compression then
        local capacity = compression.compressBound(#raw)
        local result, length =
          ffi.new("unsigned char[?]", capacity), ffi.new("unsigned long[1]", capacity)
        if compression.compress2(result, length, raw, #raw, 1) == 0 then
          return vim.base64.encode(ffi.string(result, tonumber(length[0]))), true
        end
      end
      return vim.base64.encode(raw), false
    end
end

function M.hide(record, free)
  local result = {}
  for _, pair in pairs(record.kitty_rows or {}) do
    for _, id in ipairs({ pair.shade, pair.ink }) do
      result[#result + 1] = command(string.format("a=d,d=%s,i=%d,q=2", free and "I" or "i", id))
    end
  end
  if free then
    record.kitty_rows = nil
  end
  record.painted = false
  return table.concat(result)
end

function M.paint(record, rect, rectangles, dirty)
  local model, sequence, count = record.model, {}, 0
  local moved = not vim.deep_equal(record.painted_rect, rect)
  record.kitty_rows = record.kitty_rows or {}
  for row = 1, rect.height do
    local pair = record.kitty_rows[row]
    if not pair then
      next_id = next_id + 2
      pair = { shade = next_id, ink = next_id + 1 }
      record.kitty_rows[row] = pair
    end
    local key, encode = M.shade(rectangles, row, model)
    local shade_changed = pair.key ~= key
    if shade_changed then
      local data, compressed = encode()
      sequence[#sequence + 1] =
        M.upload(pair.shade, data, 24, model.pixel_width, model.cell_height, compressed)
      pair.key = key
    end
    local ink_changed = record.tiles and record.tiles[row] and pair.version ~= record.ink_version
    if ink_changed then
      sequence[#sequence + 1] =
        M.upload(pair.ink, record.tiles[row], 100, model.pixel_width, model.cell_height)
      pair.version = record.ink_version
    end
    if
      shade_changed
      or ink_changed
      or moved
      or not record.painted
      or dirty == true
      or (dirty and dirty[row])
    then
      sequence[#sequence + 1] = place(pair.shade, rect, row, 1)
      if pair.version then
        sequence[#sequence + 1] = place(pair.ink, rect, row, 2)
      end
      count = count + 1
    end
  end
  -- A smaller panel must not retain rows from the previous layout.
  for row, pair in pairs(record.kitty_rows) do
    if row > rect.height then
      for _, id in ipairs({ pair.shade, pair.ink }) do
        sequence[#sequence + 1] = command(string.format("a=d,d=I,i=%d,q=2", id))
      end
      record.kitty_rows[row] = nil
    end
  end
  return table.concat(sequence), count
end

return M
