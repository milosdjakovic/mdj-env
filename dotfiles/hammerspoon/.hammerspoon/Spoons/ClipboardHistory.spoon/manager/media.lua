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
--- A third state sits beside frozen and linked and belongs to neither, staged, and it is
--- decided nowhere near capture. resolveForPaste is asked once per paste, over every file
--- element together, and it answers two separate concerns rather than one. The first
--- always applies and needs nothing about the destination: a paste presents each file
--- under the basename of its entry's own path, never under whatever this module happened
--- to call its cache copy, since that name is the one thing every read site can trust
--- regardless of layout or whether the file was frozen or linked. The second only matters
--- for a paste already headed into a folder that turns out to hold a file of the same
--- name, a fact only the paste side can know and hands in as an optional folder, nil for
--- every app that is not Finder, and it is what decides whether a name needs Finder style
--- numbering at all. Staging itself only happens when the name a paste must present differs
--- from the name its content path already carries on disk, whether because the cache copy
--- carries an old generated name or because the numbering just gave it one, and it answers
--- with a hard link, costing no space whatever the original's size, and falls back to a copy
--- only when linking fails and the file is within maxFileSnapshot. Every call gets its own
--- fresh directory under a dedicated staging root, named the same way a frozen copy's own
--- directory is, so a number chosen on one call can never collide with the same number
--- chosen on another call, while two files needing the same number within one call are kept
--- apart by the numbering itself counting past names it has already handed out that same
--- call rather than by a second directory. Staged files never share a directory with a
--- frozen copy or an original and are never written under filesDir, and the whole staging
--- root is bounded by keeping only the most recent handful of these per call directories
--- rather than being cleared after every paste, since a paste that leaves the clipboard
--- loaded, which a paste from the picker does, leaves the clipboard pointing at whatever was
--- just staged, and clearing it eagerly would leave that clipboard pointing at nothing.
---
--- The small preview and thumbnail images are produced by the injected preview module
--- off the main thread, so a large image or video never stalls Hammerspoon. Generation
--- is async, so the entry is saved at once with the deterministic preview path and the
--- file lands a moment later, which onMediaReady tells the ui to repaint.
---
--- Contract the store calls: ingest turns a raw image or file entry into its stored
--- form and stamps its size, release deletes an entry's media, enforceBudget demotes
--- the oldest frozen bytes to stay under a cap. A second, smaller contract is for
--- anyone describing a file entry rather than storing one, fileBadge, which answers
--- whether a file entry is fine, merely linked, or missing its original, so the chooser
--- row and the sequential paste walk read the same rule instead of each keeping their
--- own copy of it. A third contract, resolveForPaste, is for the paste side alone and
--- touches none of the above, it only ever creates new files under the staging root and
--- never mutates a stored entry or anything ingest or release already know about.

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
  for _, d in ipairs({ cfg.cacheParent, cfg.dataDir, cfg.thumbDir, cfg.filesDir, cfg.stageDir }) do
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
-- Media state
--------------------------------------------------------------------------------

--- M.fileBadge(entry, exists) -> "Deleted" or "Linked" or nil
--- The three state model's badge for a file entry, the one fact both the chooser row and
--- the sequential paste walk need to say about a file, so it is decided once here rather
--- than by each caller working it out from the elements itself. A frozen element carries a
--- stored copy and needs no check, only a link, a file with no stored copy, or a folder,
--- which is never frozen, is worth asking about. Returns Deleted when any linked element's
--- original is gone, Linked when at least one element is a link but every one still exists,
--- or nil when every element is a frozen copy and nothing needs saying.
---
--- exists is an injected probe, a function from a path to a boolean, rather than something
--- this module calls directly, because the two callers want different things from it. The
--- chooser rebuilds every row on each keystroke, so it wants a memoized answer cleared on
--- close, which is a UI concern this module has no business owning. The paste walk wants the
--- opposite, a fresh stat at the moment of the press, since the whole point is to report the
--- file's state right then rather than an answer left over from whenever it was last asked.
--- So the rule stays pure and probing is a parameter, and each caller supplies the shape it
--- needs without the other ever finding out.
function M.fileBadge(entry, exists)
  local anyLink, anyMissing = false, false
  for _, el in ipairs(entry.files or {}) do
    if not el.stored then
      anyLink = true
      if not exists(el.path) then
        anyMissing = true
      end
    end
  end
  if anyMissing then return "Deleted" end
  if anyLink then return "Linked" end
  return nil
end

--------------------------------------------------------------------------------
-- Staging for a paste
--------------------------------------------------------------------------------

-- How many per call staging directories are kept before the oldest are swept away, a
-- cap on the staging root rather than on any one entry. Sized well past an ordinary
-- burst of pastes, since the cost of keeping one is small and the cost of sweeping one
-- still holding the clipboard's own content would be real.
local STAGE_SLOTS = 20

-- The basenames already sitting in folder, read once per call so every path this call
-- considers is measured against the same live listing rather than rereading the folder
-- once per path. hs.fs.dir raises rather than answering nil when a directory cannot be
-- opened, so the listing is guarded, and a folder we cannot read is treated as though it
-- held nothing, which only ever means a path is treated as free when it might not be,
-- the same outcome as never staging at all.
local function existingNames(folder)
  local names = {}
  pcall(function()
    local iter, dirObj = hs.fs.dir(folder)
    for name in iter, dirObj do
      names[name] = true
    end
  end)
  return names
end

-- A basename split into its stem and its extension, the extension being whatever
-- follows the last dot. A name with no dot, or one that is nothing but a dot prefix
-- like .gitignore, keeps the whole name as its stem and answers no extension, since
-- splitting there would spend Finder's number in front of a dot that is not really
-- separating a stem from a kind.
local function splitStem(base)
  local stem, ext = base:match("^(.*)%.([^%.]+)$")
  if not stem or stem == "" then
    return base, nil
  end
  return stem, ext
end

-- The next name Finder itself would offer for base once base is already taken, stem, a
-- space, the number, then the extension, starting at 2 since the original already holds
-- no number of its own. existing is the destination folder's own listing and usedHere is
-- every name this same call has already handed out, and a candidate has to clear both
-- before it is free, which is what keeps two colliding files staged together from ever
-- being asked to share one name.
local function freeName(base, existing, usedHere)
  local stem, ext = splitStem(base)
  local n = 2
  while true do
    local candidate = ext and string.format("%s %d.%s", stem, n, ext) or string.format("%s %d", stem, n)
    if not existing[candidate] and not usedHere[candidate] then
      return candidate
    end
    n = n + 1
  end
end

-- Take down a directory this module made, one that holds only files with nothing
-- nested inside, which is all a frozen copy's or a staged call's own directory ever is.
-- os.remove will not take a directory down while anything still sits inside it, so its
-- files go first and the directory comes down once they are gone. Guarded the same way
-- the listing above is, since the same hs.fs.dir call is behind it.
local function removeDirRecursive(dir)
  local ok = pcall(function()
    local iter, dirObj = hs.fs.dir(dir)
    for name in iter, dirObj do
      if name ~= "." and name ~= ".." then
        os.remove(dir .. "/" .. name)
      end
    end
  end)
  if ok then
    hs.fs.rmdir(dir)
  end
end

-- Keep the staging root down to the most recent STAGE_SLOTS call directories, oldest
-- first by modification time, a plain bounded sweep over one directory listing. This is
-- deliberately not a clear after every paste. A paste that leaves
-- the clipboard loaded, which is what a paste out of the picker does, leaves the user's
-- clipboard pointing at whatever was just staged, so removing that the moment the paste
-- settles would leave the clipboard pointing at nothing rather than at what it just
-- pasted. So the root only ever grows by one slot per call and this walks it back down
-- afterward, and the whole root is wiped just once, in configure, so a slot from a
-- previous session can never be the one a still open clipboard is depending on.
local function evictOldSlots()
  local dir = cfg.stageDir
  if not dir then return end
  local slots = {}
  local ok = pcall(function()
    local iter, dirObj = hs.fs.dir(dir)
    for name in iter, dirObj do
      if name ~= "." and name ~= ".." then
        local full = dir .. "/" .. name
        local attr = hs.fs.attributes(full)
        if attr and attr.mode == "directory" then
          slots[#slots + 1] = { path = full, at = attr.modification or 0 }
        end
      end
    end
  end)
  if not ok then return end
  local excess = #slots - STAGE_SLOTS
  if excess <= 0 then return end
  table.sort(slots, function(a, b) return a.at < b.at end)
  for i = 1, excess do
    removeDirRecursive(slots[i].path)
  end
end

-- Empty the staging root once, at configure, so a slot left over from a previous
-- Hammerspoon session never lingers into a fresh one. Only the slot directories inside
-- come down, the root itself is left standing for the next call to write into.
local function wipeStageDir()
  local dir = cfg.stageDir
  if not dir or not hs.fs.attributes(dir) then return end
  pcall(function()
    local iter, dirObj = hs.fs.dir(dir)
    for name in iter, dirObj do
      if name ~= "." and name ~= ".." then
        removeDirRecursive(dir .. "/" .. name)
      end
    end
  end)
end

--- M.resolveForPaste(items, folder) -> list of paths
--- Resolves a whole paste in one pass. items is an ordered list of { content, name },
--- content the path whose bytes get pasted and name the basename the paste must present,
--- and folder is the destination folder or nil when the destination is unknown, which is
--- every app that is not Finder. Returns a plain list of paths to write to the pasteboard,
--- one per item, in the same order.
---
--- Two separate concerns live here and only one of them needs folder at all. The name
--- always comes from the record, never from the cache path, so an item's desired name
--- starts as its own name field, and two items in one paste never end up sharing that
--- name, with or without a folder, since usedHere disqualifies a repeat on its own. Only
--- the Finder style renumbering needs folder, a desired name already taken in that
--- destination's own listing becomes the next free Finder style name instead, reusing
--- freeName and splitStem, since only Finder's own numbering needs to know where the
--- paste is headed.
---
--- Staging is what makes a changed name actually true on disk. Once a desired name is
--- settled, it is compared against the basename its content path already carries, and a
--- match passes the content path through untouched, no staging, no slot, no cost, which is
--- the common case for a current layout file with no collision. A mismatch, whether because
--- the cache copy still carries an old generated name or because the numbering just gave it
--- one, is staged, a hard link when possible since that costs no space whatever the
--- original's size, and a copy only when linking fails and the file is within
--- maxFileSnapshot. A directory is never staged, since a folder cannot be hard linked and
--- copying one wholesale is not worth what it would cost, and a file that cannot be staged
--- any other way is passed through unchanged too, so the worst this ever does is exactly
--- today's paste, never worse. The staging directory itself is made lazily, once, and only
--- when some item actually needs it, so a paste that needs no rename leaves no directory
--- behind.
function M.resolveForPaste(items, folder)
  if not items or #items == 0 then
    return {}
  end

  -- Guarded so the destination is only asked about, and only listed, when there is one.
  local existing = folder and existingNames(folder) or nil
  local usedHere = {}
  local desired = {}
  for i, item in ipairs(items) do
    local name = item.name
    if usedHere[name] or (existing and existing[name]) then
      name = freeName(name, existing or {}, usedHere)
    end
    usedHere[name] = true
    desired[i] = name
  end

  local slotDir = nil -- created lazily, once, only if some item below actually needs it
  local result = {}
  for i, item in ipairs(items) do
    local contentBase = item.content:match("([^/]+)$")
    if desired[i] == contentBase then
      result[i] = item.content
    else
      if slotDir == nil then
        evictOldSlots()
        local dir = cfg.stageDir .. "/" .. newId()
        slotDir = ensureDir(dir) and dir or false
      end
      local staged = nil
      if slotDir then
        local attr = hs.fs.attributes(item.content)
        if attr and attr.mode ~= "directory" then
          local dest = slotDir .. "/" .. desired[i]
          if
            hs.fs.link(item.content, dest, false)
            or ((not attr.size or attr.size <= cfg.maxFileSnapshot) and copyFile(item.content, dest))
          then
            staged = dest
          end
        end
      end
      result[i] = staged or item.content
    end
  end
  return result
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

--- M.configure(opts) injects the dirs, sizes, util, the preview module, the store's save
--- (so a late async render can re-persist), and the mediaReady hook. Creates the media
--- dirs, including the staging root, and wipes any staging directories left over from a
--- previous session, so staging never grows across a reload or a relaunch.
function M.configure(opts)
  cfg = opts
  util = opts.util
  preview = opts.preview
  save = opts.save
  ensureDirs()
  wipeStageDir()
  return M
end

return M
