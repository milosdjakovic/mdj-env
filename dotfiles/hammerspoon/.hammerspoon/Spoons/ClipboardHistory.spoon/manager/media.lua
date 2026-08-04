--- The media lifecycle, images and files only. An optional layer of the store core.
---
--- Only a store that accepts images or files needs this. It owns everything on disk
--- under the cache dir except the history json itself, the saved images with their
--- thumbnails and downscaled previews, and the file snapshots. It is injected into the
--- core store as an optional layer, so a text only store simply has no media and none
--- of this code runs for it.
---
--- Whether a file is frozen, a real copy kept in our cache, or linked, only its path
--- remembered, is decided once at capture from its size. At or under maxFileSnapshot it
--- is frozen, over it is linked. That decision never changes on its own. Total frozen
--- bytes are then bounded by the byte retention policy, which calls enforceBudget here
--- to drop the oldest frozen bytes first. A file demotes to a link, its copy deleted but
--- its path and preview kept, so it lives on. An image has no original to fall back to,
--- so its whole entry is removed.
---
--- A frozen copy lives at filesDir/id/basename, its own directory named for a freshly
--- drawn id with the original basename kept inside, rather than in one flat directory
--- under a generated name. The directory is what stops two frozen copies of one name
--- from colliding, so the basename itself is free to stay exactly what was copied. That
--- basename is not what a paste presents though, a paste always takes its name from the
--- entry's own path field rather than from this copy, so a current layout copy simply
--- happens to agree with it while an older flat one, kept under a generated name of its
--- own, does not, and either way the name a paste shows is correct because it comes
--- straight from the record rather than from whatever this copy happens to be called. An
--- entry frozen before this layout still has its old flat path, straight under filesDir
--- with a generated name of its own, and still works, since every read site only ever
--- follows whatever path is stored rather than assuming a shape, and release and
--- enforceBudget below both tell the two shapes apart before removing anything.
---
--- The small preview and thumbnail images are produced by the injected preview module
--- off the main thread, so a large image or video never stalls Hammerspoon. Generation
--- is async, so the entry is saved at once with the deterministic preview path and the
--- file lands a moment later, which onMediaReady tells the ui to repaint.
---
--- Contract the store calls: ingest turns a raw image or file entry into its stored
--- form and stamps its size, release deletes an entry's media, enforceBudget demotes
--- the oldest frozen bytes to stay under a cap.

local M = {}

local cfg = nil     -- injected config, see configure
local util = nil
local preview = nil -- injected preview module
local save = nil    -- injected store save, called when a late render mutates an entry

-- Tell the ui a just-generated preview or thumbnail landed, so it can repaint the open
-- chooser. A no-op until the composition root injects onMediaReady.
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
    if d and not hs.fs.attributes(d) then
      hs.fs.mkdir(d)
    end
  end
end

local function newId()
  return tostring(os.time()) .. "-" .. tostring(math.random(100000))
end

-- Make sure a directory exists, tolerating one that already does. Shares the shape
-- of ensureDirs above but answers true or false rather than being a fire and forget
-- setup step, since the caller below needs to know whether it may now write into it.
local function ensureDir(d)
  return hs.fs.attributes(d) ~= nil or hs.fs.mkdir(d)
end

-- The directory a frozen file's own copy would be removed with, or nil when there is
-- none to remove. A frozen copy from the current layout sits in its own directory
-- under filesDir, named for the entry's id, so that directory is what os.remove must
-- delete once its one file is gone, since os.remove will not take down a directory
-- that still holds anything. An older entry has no such directory at all, its copy
-- sits directly in filesDir under a generated name, so this must say nil for that
-- shape rather than ever naming filesDir itself. Comparing against filesDir first
-- catches that case, and the prefix check afterward is a second guard against ever
-- handing back a directory outside our own configured tree, in case a future layout
-- change ever loosens where a stored path can point.
local function ownDir(stored)
  local dir = stored and stored:match("^(.*)/[^/]+$")
  if not dir or dir == cfg.filesDir then
    return nil
  end
  local prefix = cfg.filesDir .. "/"
  if dir:sub(1, #prefix) ~= prefix then
    return nil
  end
  return dir
end

-- Copy a file in bounded chunks, so a big file neither loads whole into memory nor
-- needs shell quoting. Bounded by maxFileSnapshot, checked before calling.
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

-- Full-res image for faithful paste, a thumbnail for the row, and a downscaled preview
-- for the pane. The full image is encoded once here, we hold the object so this is
-- unavoidable. The thumbnail and preview are derived from that saved file off the main
-- thread by the preview module, so a large copy does not stall Hammerspoon. Only paths
-- are ever kept in memory, the derived files land a moment later and the ui repaints
-- via mediaReady.
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

-- Turn each copied path into a file element. A small enough file is frozen, its bytes
-- copied into our cache so the entry survives the original being deleted or moved. A
-- folder or an oversized file is linked, only its path remembered. Either way a
-- previewable file, a raster image, video, pdf, or icns, gets a small downscaled PNG in
-- our cache, so the pane never encodes a full-res image, a video shows a frame, and a
-- linked file still shows its thumbnail after the original is gone. The preview is
-- generated from our frozen copy when we have one, else from the original, read here at
-- capture while it is guaranteed to exist.
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
      -- prefer that durable copy as the preview source, above it we keep only the link
      -- and read the original for the preview.
      local source = p
      if not attr.size or attr.size <= cfg.maxFileSnapshot then
        -- One directory per frozen copy, named for a fresh id, with the original
        -- basename kept inside it. The id used to name the file itself, a string like
        -- file plus the id plus the extension, which kept two copies of hello.txt from
        -- colliding but only by giving up the real name, so a paste out of history
        -- landed under our generated one instead of the name the user copied. Moving
        -- the id onto the directory keeps the same guarantee, two frozen files of one
        -- name can never collide because they never share a directory, while the
        -- basename inside is free to stay exactly what it was, so the pasteboard's
        -- file url basenames it correctly with no rename at paste time and no second
        -- copy. The id is drawn fresh inside this loop, so two identically named files
        -- copied together in one entry still get their own directory each, never
        -- sharing one.
        local base = p:match("([^/]+)$")
        if not base or base == "" then
          base = "file" .. (ext ~= "" and ("." .. ext) or "")
        end
        local dir = cfg.filesDir .. "/" .. newId()
        local dest = dir .. "/" .. base
        if ensureDir(dir) and copyFile(p, dest) then
          el.stored = dest
          source = dest
        end
      end
      -- The preview is generated off the main thread. Set the deterministic path now,
      -- before the file exists, so the entry saves complete. A failed render clears the
      -- path and re-saves so nothing points at a missing file. el is the live element
      -- stored on the entry, so both edits persist.
      if preview.canPreview(ext) then
        local pid = newId()
        local prev = cfg.filesDir .. "/prev-" .. pid .. ".png"
        el.prev = prev
        preview.generate({ path = source, ext = ext, dest = prev, edge = cfg.previewEdge }, function(ok)
          if not ok then
            el.prev = nil
            if save then save() end
          end
          mediaReady()
        end)
      end
    end
    files[#files + 1] = el
  end
  return files
end

--------------------------------------------------------------------------------
-- Byte accounting
--------------------------------------------------------------------------------

-- The frozen bytes we hold on disk for an entry, an image's full-res original or the
-- sum of the file elements we actually copied. Linked files and the tiny preview PNGs do
-- not count, only the heavy originals, since those are what the byte budget bounds.
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

--------------------------------------------------------------------------------
-- Contract, called by the store core
--------------------------------------------------------------------------------

--- M.ingest(entry) - turn a raw image or file entry into its stored form and stamp its
--- byte size. Text and url carry no media, so they pass through untouched.
function M.ingest(entry)
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
  return entry
end

--- M.release(entry) - delete an entry's media when it leaves the store.
function M.release(e)
  if not e then return end
  if e.kind == "image" then
    if e.full then os.remove(e.full) end
    if e.thumb then os.remove(e.thumb) end
    if e.prev then os.remove(e.prev) end
  elseif e.kind == "file" then
    for _, el in ipairs(e.files or {}) do
      if el.stored then
        -- Removed in this order, since the directory only comes down once the one file
        -- it holds is gone. ownDir answers nil for an older flat entry, so that shape
        -- removes only its file exactly as it always did.
        local dir = ownDir(el.stored)
        os.remove(el.stored)
        if dir then os.remove(dir) end
      end
      if el.prev then os.remove(el.prev) end
    end
  end
end

--- M.enforceBudget(history, cap) - keep total frozen bytes under cap by dropping the
--- oldest first. History is newest-first, so the oldest with bytes to free is walked
--- from the tail. A file demotes to a link, its copy deleted but its path, preview, and
--- row kept, so it lives on as Linked, or Deleted once the original is gone too. An
--- image has no original to fall back to, so its whole entry is removed. The small
--- preview PNGs are never touched here, so a demoted file keeps its thumbnail.
function M.enforceBudget(history, cap)
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
        M.release(e)
        table.remove(history, i)
      else
        for _, el in ipairs(e.files or {}) do
          if el.stored then
            local dir = ownDir(el.stored)
            os.remove(el.stored)
            if dir then os.remove(dir) end
            el.stored = nil
          end
        end
      end
      total = total - freed
    end
    i = i - 1
  end
end

--- M.configure(opts) - inject the dirs, sizes, util, the preview module, the store's
--- save (so a late async render can re-persist), and the mediaReady hook. Creates the
--- media dirs.
function M.configure(opts)
  cfg = opts
  util = opts.util
  preview = opts.preview
  save = opts.save
  ensureDirs()
  return M
end

return M
