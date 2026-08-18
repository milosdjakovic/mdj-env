--- Pictures of files, a Chain of Responsibility over pluggable generators.
---
--- The pane wants an image for a row and does not care where one comes from. HOW an image
--- is produced depends entirely on the file. macOS can decode a raster or an icon set in
--- process, while a pdf, a video, a spreadsheet or a keynote needs Quick Look, which is a
--- shellout and takes a moment. So each generator declares which extensions it covers and
--- the chain hands a row to the first one that claims it.
---
--- The mechanism names no format and the generators name no other. The composition root
--- injects the cache directory and the caps, and the order lives in the chain. Adding a
--- kind of file this pane can draw is a new generator plus one line in that list.
---
--- A generator:
---   name
---   handles(ext) -> bool                does this backend cover the extension
---   accepts(spec) -> bool               optional, will it take THIS file, see below
---   image(spec, cb)                     cb(hs.image or nil), on the main thread
--- spec = { path = <source file>, ext = <lower ext>, edge = <max px>, size = <bytes> }
---
--- DECLINING PASSES THE FILE ALONG, which is the same rule the pane's describer chain runs on
--- and it was missing here. `handles` answers about the TYPE, which is the question the pane
--- asks before claiming a row at all, while `accepts` answers about the FILE, so a backend can
--- step aside on this one and let the next take it. Without that, the in process generator
--- claimed every raster by extension and then refused the large ones on size, and the row ended
--- there with a heading reading no preview. Quick Look, sitting right behind it and perfectly
--- able to draw a 35MB png off the main thread, was never asked. Measured on exactly that file,
--- the chain answered nil while qlmanage rendered it to a 768KB thumbnail and exited clean.
---
--- So there is no maximum size this pane can show. A size only decides which backend does the
--- work, and the one that costs nothing on the main thread has no reason to have a limit.
---
--- THE CONTRACT IS AN IMAGE, NEVER A FILE. That is what keeps the pane ignorant of whether
--- anything was written to disk, so the cache is a private detail of the one generator that
--- needs it rather than a concept the whole feature has to carry.
---
--- Only the Quick Look generator caches, and it has to. A render costs a process launch and
--- a few hundred milliseconds, while a raster decode is immediate and writing it out would
--- cost more than doing it again. The cache is keyed on what the file WAS, its size and its
--- modification time, so an edited file is rendered again and an unchanged one is free on
--- every later open, and it is bounded by a file count swept once per session rather than
--- checked on every write.

local thumbsPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local util = loadfile(thumbsPath .. "util.lua")()

local M = {}

-- Quick Look, at the fixed absolute path a system binary lives at. Declared in the
-- plugin's manifest as the system kind, with unit naming thumbs, which is what allows
-- the literal here, the same as /bin/ls in sources/walk.lua and /usr/bin/open in
-- chooser.lua. Nothing is injected because nothing can move it, and this spoon still
-- never learns how anything is installed.
local QLMANAGE = "/usr/bin/qlmanage"

local cfg = {
  cacheDir = nil,   -- injected, where a rendered PNG is kept between opens
  cacheFiles = 400, -- how many renders are kept before the oldest are swept
}

-- What macOS decodes in process, cheaply enough to do it on the main thread. Rasters and
-- icon sets, which is what hs.image reads reliably from a path.
local NATIVE_EXT = {
  png = true, jpg = true, jpeg = true, gif = true, bmp = true, tiff = true, tif = true,
  heic = true, webp = true, icns = true, ico = true,
}

-- What Quick Look is asked for. Everything here has a generator on a stock macOS and none
-- of it can be drawn without one, which is the whole reason this generator exists.
--
-- An svg is on this list rather than the native one deliberately. hs.image will not read
-- one from a path, while Quick Look renders it properly, and it is exactly the file whose
-- markup you do not want printed at you.
local QL_EXT = {
  pdf = true, svg = true, eps = true, ai = true, psd = true,
  mp4 = true, mov = true, m4v = true, mkv = true, avi = true, webm = true,
  doc = true, docx = true, pages = true, rtf = true, odt = true, epub = true,
  xls = true, xlsx = true, numbers = true, csv = true,
  ppt = true, pptx = true, key = true,
  app = true,
}

--------------------------------------------------------------------------------
-- The cache, private to the Quick Look generator
--------------------------------------------------------------------------------

local function ensureCacheDir()
  local dir = cfg.cacheDir
  if not dir then return nil end
  if hs.fs.attributes(dir, "mode") == "directory" then return dir end
  -- One level at a time, since mkdir does not make parents and the parent is a shared
  -- cache root that may not exist on a fresh machine either.
  local parent = util.dirname(dir)
  if parent and hs.fs.attributes(parent, "mode") ~= "directory" then hs.fs.mkdir(parent) end
  hs.fs.mkdir(dir)
  if hs.fs.attributes(dir, "mode") == "directory" then return dir end
  return nil
end

-- A stable file name for one version of one file. Hashed rather than derived from the path,
-- because a path contains slashes and spaces and can be longer than a file name may be,
-- and because the hash is fixed width so the sweep below can count files without parsing
-- any of them.
local function cacheName(spec, attrs)
  local key = string.format("%s|%s|%s", spec.path, tostring(attrs and attrs.size),
    tostring(attrs and attrs.modification))
  return hs.hash.MD5(key) .. ".png"
end

-- Keep the directory bounded. Swept once per session rather than per render, because the
-- cost is a full listing and the thing it guards against is growth over months, not over
-- one open. Oldest first by modification, which for a cache of renders is also least
-- recently produced.
local swept = false
local function sweep()
  if swept then return end
  swept = true
  local dir = cfg.cacheDir
  if not dir or hs.fs.attributes(dir, "mode") ~= "directory" then return end
  local files = {}
  -- Guarded because hs.fs.dir raises rather than returning nil when it cannot open a
  -- directory, so the check above is not enough on its own.
  local ok = pcall(function()
    local iter, dirObj = hs.fs.dir(dir)
    for name in iter, dirObj do
      if name:sub(-4) == ".png" then
        local full = dir .. "/" .. name
        local a = hs.fs.attributes(full)
        files[#files + 1] = { path = full, at = (a and a.modification) or 0 }
      end
    end
  end)
  if not ok then return end
  local excess = #files - (cfg.cacheFiles or 400)
  if excess <= 0 then return end
  table.sort(files, function(a, b) return a.at < b.at end)
  for i = 1, excess do os.remove(files[i].path) end
  util.log.i(string.format("thumbs: swept %d of %d cached renders", excess, #files))
end

--------------------------------------------------------------------------------
-- Generators
--------------------------------------------------------------------------------

-- In process and immediate, so the pane draws on the first paint with no repaint at all.
--
-- The size cap is a cap on THIS BACKEND rather than on the feature. Decoding happens on the
-- main thread and Hammerspoon owns every leader key here, so a big decode is a stalled
-- keyboard. Expressed as accepts rather than as a refusal inside image, so a file over the cap
-- goes to Quick Look, which is a different process and does not care how big it is.
local nativeGen = {
  name = "hsimage",
  handles = function(ext) return NATIVE_EXT[ext] == true end,
  accepts = function(spec)
    local size = spec.size
    if not size then
      local attrs = hs.fs.attributes(spec.path)
      size = attrs and attrs.size
    end
    if not size then return true end
    return size <= (cfg.nativeMaxBytes or 20 * 1024 * 1024)
  end,
  image = function(spec, cb)
    cb(hs.image.imageFromPath(spec.path))
  end,
}

-- Quick Look, off the main thread, into the cache. The same picture Finder shows with the
-- space bar, which is the point, since it means a file type this config has never heard of
-- is drawn correctly as long as something on the machine knows how.
--
-- -t asks for a thumbnail, -s the size of the larger edge, -o the directory to write into,
-- and the written name is the source name with .png appended rather than substituted, which
-- is why the result is looked up by that shape and then moved to the cache name.
-- The renders already running, by destination, each holding everyone waiting on it.
--
-- Two asks for one file are ordinary rather than unlikely. Moving the highlight away and
-- back arrives before the first render has finished, and without this that would launch a
-- second qlmanage writing into the same scratch directory as the first, where one would
-- rename the result out from under the other. So the second ask joins the first instead,
-- which removes the race and the duplicated work in the same move.
local inflight = {}
local qlGen = {
  name = "quicklook",
  -- Claims the raster types too, as the backstop behind the in process generator rather than
  -- as a competitor to it. Order still means the cheap one wins every ordinary photo, and this
  -- is what a raster the cheap one stepped aside from falls through to.
  handles = function(ext) return QL_EXT[ext] == true or NATIVE_EXT[ext] == true end,
  image = function(spec, cb)
    local dir = ensureCacheDir()
    if not dir then
      cb(nil)
      return
    end
    sweep()
    local attrs = hs.fs.attributes(spec.path)
    local dest = dir .. "/" .. cacheName(spec, attrs)
    local cached = hs.image.imageFromPath(dest)
    if cached then
      cb(cached)
      return
    end
    local waiting = inflight[dest]
    if waiting then
      waiting[#waiting + 1] = cb
      return
    end
    inflight[dest] = { cb }
    local function answer(img)
      local waiters = inflight[dest] or {}
      inflight[dest] = nil
      for _, waiter in ipairs(waiters) do waiter(img) end
    end
    -- Its own scratch directory per render, so the name qlmanage chooses does not have to be
    -- guessed exactly, only found, and so nothing half written is ever visible at the
    -- destination the next ask looks at.
    local scratch = dest:gsub("%.png$", ".d")
    hs.fs.mkdir(scratch)
    local t = hs.task.new(QLMANAGE, function()
      local produced = nil
      -- Guarded for the same reason as the sweep, and because this runs in a task callback
      -- where a raise would go unhandled and leave everyone waiting on it waiting forever.
      pcall(function()
        local iter, dirObj = hs.fs.dir(scratch)
        for name in iter, dirObj do
          if name:sub(-4) == ".png" then produced = scratch .. "/" .. name break end
        end
      end)
      local img = nil
      if produced then
        -- Moved into place rather than read where it lies, which is what makes the cache
        -- entry appear whole. Both paths are in the same directory so the rename is atomic,
        -- and a failure leaves the render readable where it is rather than losing it.
        if os.rename(produced, dest) then
          img = hs.image.imageFromPath(dest)
        else
          img = hs.image.imageFromPath(produced)
          os.remove(produced)
        end
      end
      -- The scratch directory goes whether or not anything came out of it, so a file type
      -- Quick Look cannot draw leaves nothing behind to accumulate.
      hs.fs.rmdir(scratch)
      answer(img)
    end, { "-t", "-s", tostring(spec.edge or 600), "-o", scratch, spec.path })
    if t then
      t:start()
    else
      hs.fs.rmdir(scratch)
      answer(nil)
    end
  end,
}

-- In priority order, cheapest first. A raster is claimed by the in process generator even
-- though Quick Look could also draw it, because one is immediate and the other is a process
-- launch for the same picture.
local chain = { nativeGen, qlGen }

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- thumbs.handles(ext) -> bool
--- Whether any generator covers this extension. The pane's image describer asks before
--- claiming a row, so a type nothing can draw falls through to the next describer rather
--- than showing a heading over a picture that is never going to arrive.
function M.handles(ext)
  ext = tostring(ext or ""):lower()
  if ext == "" then return false end
  for _, g in ipairs(chain) do
    if g.handles(ext) then return true end
  end
  return false
end

--- thumbs.image(spec, cb)
--- Run the first generator that covers the type AND will take this file. cb receives an
--- hs.image or nil, always on the main thread, and always exactly once. Nothing willing to
--- take it calls cb(nil), which is the pane's signal to describe the row by its header.
function M.image(spec, cb)
  cb = cb or function() end
  for _, g in ipairs(chain) do
    if g.handles(spec.ext) and (not g.accepts or g.accepts(spec)) then
      g.image(spec, cb)
      return
    end
  end
  cb(nil)
end

--- thumbs.configure(opts) - inject the cache directory and the caps. This module resolves
--- nothing itself and names no install location, so it learns where to keep its renders
--- rather than deciding.
function M.configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  return M
end

return M
