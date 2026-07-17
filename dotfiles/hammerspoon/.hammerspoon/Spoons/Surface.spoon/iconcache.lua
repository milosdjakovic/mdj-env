--- Disk backed icon cache for the webview surfaces.
---
--- A webview cannot take an hs.image, it needs bytes it can render, and encoding
--- a PNG from an hs.image is synchronous on the main thread, so the cost is paid
--- once and persisted. Each icon is written to a PNG named by a caller supplied
--- key in a dedicated folder, encoded from the live image only when the file is
--- missing. Rows are served a data URI built by reading that small PNG back and
--- base64 encoding it, which skips the expensive PNG encode on every open and is
--- memoized in memory per session so a key is read at most once per launch.
---
--- The folder is its own manifest, so there is no companion index file to drift.
--- reconcile takes the live set of keys and deletes any PNG whose key is gone,
--- then reports which live keys have no file yet, and warm encodes those a few
--- per timer tick so the reconcile never blocks the main thread.
---
--- This module is generic in its key. The app icon consumer keys by bundle id;
--- anything else with a stable key and an image provider can reuse it. Glyph
--- drawn action icons and country flags stay in memory, they are a tiny fixed
--- set with nothing to persist, so they do not belong here.

local M = {}

local dir = nil          -- the cache folder, injected via configure
local uriMemo = {}       -- key -> data URI string (or false when the file is absent)
local warmTimer = nil    -- the running chunked warm timer, if any

-- A key becomes a file name. Bundle ids are dotted but filesystem safe; a slash
-- is the only character that would break a path, so it is the only one replaced.
local function fileFor(key)
  return dir .. "/" .. tostring(key):gsub("/", "_") .. ".png"
end

--- M.configure(opts) - opts.dir is the cache folder, created if missing.
function M.configure(opts)
  opts = opts or {}
  dir = opts.dir
  if dir then
    hs.fs.mkdir(dir) -- no op if it already exists
  end
  return M
end

--- M.has(key) - is this key already encoded on disk.
function M.has(key)
  if not dir then return false end
  return hs.fs.attributes(fileFor(key), "mode") == "file"
end

--- M.store(key, image) - encode image to the key's PNG if absent, returning the
--- path or nil. Drops any stale memo so the next read rebuilds the data URI.
function M.store(key, image)
  if not dir or not image then return nil end
  local path = fileFor(key)
  if hs.fs.attributes(path, "mode") ~= "file" then
    if not image:saveToFile(path) then return nil end
    uriMemo[key] = nil
  end
  return path
end

--- M.dataURI(key) - a data URI for the key's PNG, or nil when there is no file.
--- Reads the small pre-encoded PNG and base64s it, which is cheap next to
--- encoding from an hs.image, and memoizes the result for the session. A missing
--- file memoizes false so a cold key is stat-ed at most once.
function M.dataURI(key)
  local hit = uriMemo[key]
  if hit ~= nil then return hit or nil end
  if not dir then return nil end
  local path = fileFor(key)
  local f = io.open(path, "rb")
  if not f then
    uriMemo[key] = false
    return nil
  end
  local bytes = f:read("*a")
  f:close()
  local uri = "data:image/png;base64," .. hs.base64.encode(bytes)
  uriMemo[key] = uri
  return uri
end

--- M.reconcile(liveKeys) - liveKeys is a set, key -> truthy, of every key that
--- should exist. Delete the PNG for any key no longer live, then return a list of
--- live keys that have no file yet, so the caller can warm them. The folder is
--- the manifest, so this is a pure directory diff with no separate index.
function M.reconcile(liveKeys)
  local missing = {}
  if not dir then return missing end
  liveKeys = liveKeys or {}

  -- Prune files whose key is gone. The name maps back to a key by dropping .png,
  -- which is exact for keys with no slash and safe for the replaced ones, since a
  -- pruned file only needs to not match any live key.
  for file in hs.fs.dir(dir) do
    if file:sub(-4) == ".png" then
      local key = file:sub(1, -5)
      if not liveKeys[key] then
        os.remove(dir .. "/" .. file)
        uriMemo[key] = nil
      end
    end
  end

  -- Report live keys that still have no file.
  for key in pairs(liveKeys) do
    if not M.has(key) then
      missing[#missing + 1] = key
    end
  end
  return missing
end

--- M.warm(keys, provider, opts) - encode each key's icon a few per tick so the
--- main thread is never blocked. provider(key) returns the hs.image to store, or
--- nil to skip. opts.perTick (default 8) and opts.interval (default 0.05) pace it.
--- A new warm cancels any running one, since a reload rebuilds the live set.
function M.warm(keys, provider, opts)
  opts = opts or {}
  local perTick = opts.perTick or 8
  local interval = opts.interval or 0.05
  if warmTimer then warmTimer:stop(); warmTimer = nil end
  if not dir or not keys or #keys == 0 then return end

  local i = 1
  warmTimer = hs.timer.doEvery(interval, function()
    local stop = math.min(i + perTick - 1, #keys)
    for j = i, stop do
      local key = keys[j]
      if not M.has(key) then
        local img = provider(key)
        if img then M.store(key, img) end
      end
    end
    i = stop + 1
    if i > #keys then
      warmTimer:stop()
      warmTimer = nil
    end
  end)
end

--- M.forget(key) - drop a key's memo so its next read reloads (rarely needed;
--- store already clears on rewrite). Exposed for tests.
function M.forget(key)
  uriMemo[key] = nil
end

return M
