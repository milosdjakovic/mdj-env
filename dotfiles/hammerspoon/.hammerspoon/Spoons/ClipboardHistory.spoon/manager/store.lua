--- Persistence and the media lifecycle.
---
--- Owns the in-memory history list and everything on disk under the cache dir:
--- the JSON store, saved images (full, thumbnail, and a downscaled preview), and
--- file snapshots. Readers hand it a raw entry via add(); it persists any media,
--- dedupes, trims to the cap, and saves. removeFiles is the garbage collector,
--- run whenever an entry leaves history, so disk stays bounded by the count cap.
---
--- Entry shapes on disk:
---   text / url  { kind, ts, title, preview, text, _key }
---   image       { kind, ts, title, preview, full, thumb, prev, w, h }
---   file        { kind, ts, title, preview, files = { {path, stored, isDir,
---                 prev}, ... }, _key }
--- Every shape also carries an optional sourceApp, the bundle id of the app
--- frontmost when the copy happened, which the ui turns into the row icon.
--- The files array is always used, so one file and many files are uniform. A
--- raw entry from a reader instead carries _img (an hs.image to save) or _paths
--- (original paths to snapshot); add() turns those into the fields above.

local S = {}

local SCHEMA = 2 -- bump to reset an incompatible on-disk store rather than migrate

local cfg = nil -- injected config, see configure
local util = nil
local history = {} -- newest first

--------------------------------------------------------------------------------
-- Disk helpers
--------------------------------------------------------------------------------

local function ensureDirs()
  for _, d in ipairs({ cfg.cacheParent, cfg.dataDir, cfg.thumbDir, cfg.filesDir }) do
    if not hs.fs.attributes(d) then
      hs.fs.mkdir(d)
    end
  end
end

local function newId()
  return tostring(os.time()) .. "-" .. tostring(math.random(100000))
end

local function save()
  -- Wrap in a schema envelope so a future format change resets cleanly. Pretty
  -- printed and replacing the existing file.
  hs.json.write({ schema = SCHEMA, items = history }, cfg.storePath, true, true)
end

-- Copy a file in bounded chunks, so a big file neither loads whole into memory
-- nor needs shell quoting. Bounded by maxFileSnapshot, checked before calling.
local function copyFile(src, dest)
  local i = io.open(src, "rb")
  if not i then return false end
  local o = io.open(dest, "wb")
  if not o then
    i:close()
    return false
  end
  while true do
    local chunk = i:read(256 * 1024)
    if not chunk then break end
    o:write(chunk)
  end
  i:close()
  o:close()
  return true
end

-- Write a downscaled PNG. setSize on a copy genuinely shrinks the saved file
-- (unlike encodeAsURLString, which ignores it), so the preview loads a small
-- image and encodes cheaply. Works from an hs.image or a source path.
local function writeScaled(imgOrPath, dest, edge)
  local img = type(imgOrPath) == "string" and hs.image.imageFromPath(imgOrPath) or imgOrPath
  if not img then return false end
  local ok = img:copy():setSize({ w = edge, h = edge }):saveToFile(dest)
  return ok and true or false
end

--------------------------------------------------------------------------------
-- Media persistence
--------------------------------------------------------------------------------

-- Full-res image for faithful paste, a thumbnail for the row, and a downscaled
-- preview for the pane. Only paths are ever kept in memory.
local function saveImage(img)
  local id = newId()
  local full = cfg.dataDir .. "/img-" .. id .. ".png"
  local thumb = cfg.thumbDir .. "/thumb-" .. id .. ".png"
  local prev = cfg.dataDir .. "/prev-" .. id .. ".png"
  img:saveToFile(full)
  writeScaled(img, thumb, cfg.thumbEdge)
  writeScaled(img, prev, cfg.previewEdge)
  return { full = full, thumb = thumb, prev = prev }
end

-- Snapshot each copied path into our store so the entry survives the original
-- being deleted or moved, and so paste can always write our own copy. Folders
-- and oversized files are referenced only. Image files also get a downscaled
-- preview so the pane never encodes a full-res image.
local function snapshotFiles(paths)
  local files = {}
  for _, p in ipairs(paths) do
    local attr = hs.fs.attributes(p)
    local el = { path = p }
    if attr and attr.mode == "directory" then
      el.isDir = true
    elseif attr and attr.mode == "file" and (not attr.size or attr.size <= cfg.maxFileSnapshot) then
      local id = newId()
      local ext = p:match("%.([%w]+)$")
      local dest = cfg.filesDir .. "/file-" .. id .. (ext and ("." .. ext) or "")
      if copyFile(p, dest) then
        el.stored = dest
        if util.RENDER_AS_IMAGE[(ext or ""):lower()] then
          local prev = cfg.filesDir .. "/prev-" .. id .. ".png"
          if writeScaled(dest, prev, cfg.previewEdge) then
            el.prev = prev
          end
        end
      end
    end
    files[#files + 1] = el
  end
  return files
end

local function removeFiles(e)
  if not e then return end
  if e.kind == "image" then
    if e.full then os.remove(e.full) end
    if e.thumb then os.remove(e.thumb) end
    if e.prev then os.remove(e.prev) end
  elseif e.kind == "file" then
    for _, el in ipairs(e.files or {}) do
      if el.stored then os.remove(el.stored) end
      if el.prev then os.remove(el.prev) end
    end
  end
end

--------------------------------------------------------------------------------
-- History
--------------------------------------------------------------------------------

-- A stable identity for dedupe: same text, same url, or the same ordered list of
-- file paths. Images have no cheap identity, so they are never deduped. Computed
-- from the raw entry (before media persistence) so a duplicate costs no copy.
local function rawKey(e)
  if e.kind == "text" or e.kind == "url" then
    return e.kind .. "\0" .. (e.text or "")
  end
  if e.kind == "file" then
    return "file\0" .. table.concat(e._paths or {}, "\0")
  end
  return nil
end

local function trim()
  while #history > cfg.maxEntries do
    removeFiles(table.remove(history))
  end
end

--- S.add(entry) -> entry
--- Persist a raw entry from a reader and put it at the front. A duplicate moves
--- the existing entry to the front instead, at no copy cost, and returns it.
function S.add(entry)
  local key = rawKey(entry)
  if key then
    for i = 1, #history do
      if history[i]._key == key then
        local h = table.remove(history, i)
        h.ts = entry.ts -- refresh recency
        h.sourceApp = entry.sourceApp -- and the source, so the icon tracks the latest copy
        table.insert(history, 1, h)
        save()
        return h
      end
    end
  end

  if entry.kind == "image" and entry._img then
    local m = saveImage(entry._img)
    entry.full, entry.thumb, entry.prev = m.full, m.thumb, m.prev
    entry._img = nil
  elseif entry.kind == "file" and entry._paths then
    entry.files = snapshotFiles(entry._paths)
    entry._paths = nil
  end

  entry._key = key
  table.insert(history, 1, entry)
  trim()
  save()
  return entry
end

--- S.moveToFront(entry) - float a used entry to the top.
function S.moveToFront(entry)
  for i = 1, #history do
    if history[i] == entry then
      table.remove(history, i)
      table.insert(history, 1, entry)
      save()
      return
    end
  end
end

--- S.removeEntry(entry) - delete one entry and its media.
function S.removeEntry(entry)
  for i = #history, 1, -1 do
    if history[i] == entry then
      table.remove(history, i)
    end
  end
  removeFiles(entry)
  save()
end

--- S.clear() - wipe history and all media.
function S.clear()
  for _, e in ipairs(history) do
    removeFiles(e)
  end
  history = {}
  save()
end

--- S.all() - the live history list, newest first.
function S.all()
  return history
end

--- S.load() - read history from disk, resetting on a schema mismatch.
function S.load()
  local data = hs.json.read(cfg.storePath)
  if type(data) == "table" and data.schema == SCHEMA and type(data.items) == "table" then
    history = data.items
  else
    history = {}
  end
  return history
end

--- S.configure(c) - inject paths, caps, sizes, and util. Creates the dirs.
function S.configure(c)
  cfg = c
  util = c.util
  ensureDirs()
  return S
end

return S
