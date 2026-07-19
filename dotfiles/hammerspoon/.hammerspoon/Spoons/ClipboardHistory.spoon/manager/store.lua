--- Persistence and the media lifecycle.
---
--- Owns the in-memory history list and everything on disk under the cache dir:
--- the JSON store, saved images (full, thumbnail, and a downscaled preview), and
--- file snapshots. Readers hand it a raw entry via add(); it persists any media,
--- dedupes, trims to the cap, and saves. removeFiles is the garbage collector,
--- run whenever an entry leaves history, so disk stays bounded by the count cap.
---
--- Disk is bounded a second way, by bytes. Whether a file is frozen (a real copy
--- kept in our cache) or linked (only its path remembered) is decided once at
--- capture from its size: at or under maxFileSnapshot it is frozen, over it is
--- linked. That decision never changes on its own. Total frozen bytes are then
--- capped by maxSnapshotBytes; when a new copy pushes over it, enforceBudget drops
--- the oldest frozen bytes first. A file demotes to a link (its copy deleted, its
--- path and preview kept), so it lives on; an image has no original to fall back
--- to, so its whole entry is removed. This is the only thing that changes a copy's
--- frozen/linked state after capture, and the ui shows it as a Linked/Deleted badge.
---
--- The small preview and thumbnail images are produced by the injected preview
--- module, off the main thread, so a large image or video never stalls
--- Hammerspoon. A frozen file's preview is derived from our copy; a linked file's
--- is derived from the original at capture, while it is still there, and kept in
--- our cache, so a Deleted file still shows its thumbnail. A previewable file
--- (raster image, video, pdf, icns) gets a downscaled PNG; a video's preview is a
--- single frame. Generation is async, so the entry is saved at once with the
--- deterministic preview path and the file lands a moment later, which onMediaReady
--- tells the ui to repaint.
---
--- Entry shapes on disk (size is a byte count, stamped at capture):
---   text / url  { kind, ts, title, preview, text, size, chars, _key }
---   image       { kind, ts, title, preview, full, thumb, prev, w, h, size }
---   file        { kind, ts, title, preview, size, files = { {path, size, stored,
---                 isDir, prev}, ... }, _key }
--- A file element carries stored only when frozen; a linked one has just path (and
--- prev when previewable). Every shape also carries an optional sourceApp, the
--- bundle id of the app frontmost when the copy happened, which the ui turns into
--- the row icon. The files array is always used, so one file and many files are
--- uniform. A raw entry from a reader instead carries _img (an hs.image to save) or
--- _paths (original paths to snapshot); add() turns those into the fields above.

local S = {}

local SCHEMA = 2 -- bump to reset an incompatible on-disk store rather than migrate

local cfg = nil -- injected config, see configure
local util = nil
local preview = nil -- injected preview module, see configure
local history = {} -- newest first

-- Tell the ui a just-generated preview or thumbnail landed, so it can repaint the
-- open chooser. A no-op until the composition root injects onMediaReady.
local function mediaReady()
  if cfg and cfg.onMediaReady then
    cfg.onMediaReady()
  end
end

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

--------------------------------------------------------------------------------
-- Media persistence
--------------------------------------------------------------------------------

-- Full-res image for faithful paste, a thumbnail for the row, and a downscaled
-- preview for the pane. The full image is encoded once here (we hold the object,
-- so this is unavoidable); the thumbnail and preview are then derived from that
-- saved file off the main thread by the preview module, so a large copy does not
-- stall Hammerspoon. Only paths are ever kept in memory; the derived files land a
-- moment later and the ui repaints via mediaReady.
local function saveImage(img)
  local id = newId()
  local full = cfg.dataDir .. "/img-" .. id .. ".png"
  local thumb = cfg.thumbDir .. "/thumb-" .. id .. ".png"
  local prev = cfg.dataDir .. "/prev-" .. id .. ".png"
  img:saveToFile(full)
  local attr = hs.fs.attributes(full)
  preview.generate({ path = full, ext = "png", dest = thumb, edge = cfg.thumbEdge }, mediaReady)
  preview.generate({ path = full, ext = "png", dest = prev, edge = cfg.previewEdge }, mediaReady)
  return { full = full, thumb = thumb, prev = prev, size = attr and attr.size or nil }
end

-- Turn each copied path into a file element. A small enough file is frozen, its
-- bytes copied into our cache so the entry survives the original being deleted or
-- moved; a folder or an oversized file is linked, only its path remembered. Either
-- way a previewable file (raster image, video, pdf, icns) gets a small downscaled
-- PNG in our cache, so the pane never encodes a full-res image, a video shows a
-- frame, and a linked file still shows its thumbnail after the original is gone.
-- The preview is generated from our frozen copy when we have one, else from the
-- original, read here at capture while it is guaranteed to exist.
local function snapshotFiles(paths)
  local files = {}
  for _, p in ipairs(paths) do
    local attr = hs.fs.attributes(p)
    local el = { path = p }
    if attr and attr.mode == "directory" then
      el.isDir = true
    elseif attr and attr.mode == "file" then
      el.size = attr.size
      local ext = (p:match("%.([%w]+)$") or ""):lower()
      -- Decide freeze vs link once, from size. Below the cap we copy the bytes and
      -- prefer that durable copy as the preview source; above it we keep only the
      -- link and read the original for the preview.
      local source = p
      if not attr.size or attr.size <= cfg.maxFileSnapshot then
        local id = newId()
        local dest = cfg.filesDir .. "/file-" .. id .. (ext ~= "" and ("." .. ext) or "")
        if copyFile(p, dest) then
          el.stored = dest
          source = dest
        end
      end
      -- The preview is generated off the main thread. Set the deterministic path
      -- now, before the file exists, so the entry saves complete; a failed render
      -- clears the path and re-saves so nothing points at a missing file. el is the
      -- live element stored on the entry, so both edits persist.
      if preview.canPreview(ext) then
        local pid = newId()
        local prev = cfg.filesDir .. "/prev-" .. pid .. ".png"
        el.prev = prev
        preview.generate({ path = source, ext = ext, dest = prev, edge = cfg.previewEdge }, function(ok)
          if not ok then
            el.prev = nil
            save()
          end
          mediaReady()
        end)
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

-- The frozen bytes we hold on disk for an entry: an image's full-res original, or
-- the sum of the file elements we actually copied. Linked files and the tiny
-- preview PNGs do not count, only the heavy originals, since those are what the
-- byte budget bounds.
local function entryStoredBytes(e)
  if e.kind == "image" then
    return (e.full and e.size) or 0
  elseif e.kind == "file" then
    local n = 0
    for _, el in ipairs(e.files or {}) do
      if el.stored then n = n + (el.size or 0) end
    end
    return n
  end
  return 0
end

-- Keep total frozen bytes under maxSnapshotBytes by dropping the oldest first.
-- History is newest-first, so the oldest with bytes to free is walked from the
-- tail. A file demotes to a link, its copy deleted but its path, preview, and row
-- kept, so it lives on as Linked (or Deleted once the original is gone too). An
-- image has no original to fall back to, so its whole entry is removed. The small
-- preview PNGs are never touched here, so a demoted file keeps its thumbnail.
local function enforceBudget()
  local cap = cfg.maxSnapshotBytes
  if not cap then return end
  local total = 0
  for _, e in ipairs(history) do
    total = total + entryStoredBytes(e)
  end
  local i = #history
  while i >= 1 and total > cap do
    local e = history[i]
    local freed = entryStoredBytes(e)
    if freed > 0 then
      if e.kind == "image" then
        removeFiles(e)
        table.remove(history, i)
      else
        for _, el in ipairs(e.files or {}) do
          if el.stored then
            os.remove(el.stored)
            el.stored = nil
          end
        end
      end
      total = total - freed
    end
    i = i - 1
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
    entry.size = m.size
    entry._img = nil
  elseif entry.kind == "file" and entry._paths then
    entry.files = snapshotFiles(entry._paths)
    entry._paths = nil
    local total = 0
    for _, el in ipairs(entry.files) do
      total = total + (el.size or 0)
    end
    entry.size = total
  end

  entry._key = key
  table.insert(history, 1, entry)
  trim()
  enforceBudget()
  save()
  return entry
end

-- Locate the live history element for an entry that may be a foreign copy. The
-- chooser bridges its choices out through Objective C and hands its completion
-- callback a freshly rebuilt Lua table, so the entry that comes back from a paste
-- is a value copy, not the stored reference. Reference equality would miss it and
-- the move would silently do nothing, so match on a stable field first, the
-- dedupe _key for text, url, and file, or the unique full image path, and fall
-- back to identity.
local function indexOf(entry)
  for i = 1, #history do
    local h = history[i]
    if h == entry then
      return i
    elseif h.kind == entry.kind then
      if h._key and entry._key then
        if h._key == entry._key then return i end
      elseif h.kind == "image" and h.full == entry.full then
        return i
      end
    end
  end
  return nil
end

--- S.moveToFront(entry) - float a used entry to the top and refresh its recency,
--- the same treatment a duplicate copy gets, so a just pasted item reads as the
--- most recent. Accepts a foreign copy of the entry, matched by stable field, see
--- indexOf, so a paste coming back through the chooser callback still moves.
function S.moveToFront(entry)
  local i = indexOf(entry)
  if not i then return end
  local h = table.remove(history, i)
  h.ts = os.time() -- refresh recency, mirroring the dedupe branch of add
  table.insert(history, 1, h)
  save()
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

--- S.configure(c) - inject paths, caps, sizes, util, and the preview module.
--- Creates the dirs.
function S.configure(c)
  cfg = c
  util = c.util
  preview = c.preview
  ensureDirs()
  return S
end

return S
