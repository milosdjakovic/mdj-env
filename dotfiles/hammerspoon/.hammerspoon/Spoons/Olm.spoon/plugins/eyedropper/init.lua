--- === Eyedropper ===
---
--- A screen colour sampler on the native macOS eyedropper. Start it and Apple's
--- own NSColorSampler loupe appears, the same smooth magnifier the system colour
--- pickers use, and a click copies the sampled pixel's hex to the clipboard.
--- Escape cancels without copying.
---
--- The copy is silent here. Confirming it visually is the composition root's
--- concern, handed out through the showColor seam below, so the confirmation is
--- drawn on the shared CanvasPanel like every other overlay rather than an
--- hs.alert, keeping the UI one surface.
---
--- Hammerspoon has no binding for NSColorSampler, so the sampler lives in a tiny
--- Swift helper (sampler.swift beside this file) that shows it and prints the
--- picked hex. The spoon compiles that helper once into a cached binary and runs
--- it per pick through hs.task, so there is no per frame screen snapshot and no
--- custom loupe, the magnifier is the real native one and there is no lag. The
--- cached binary lives under Library Caches, deliberately outside the watched
--- ~/.hammerspoon tree, so compiling it never triggers a config reload, and it is
--- rebuilt only when the Swift source is newer than the binary.
---
--- This is a self contained mechanism, not a list tool, so it does not ride the
--- shared Chooser atom. It exposes one small contract, pick to start and isActive
--- to query, so the composition root can wire it onto a Hyper key and a launcher
--- row like the other lone actions (lock, sleep). An optional injected showColor
--- callback hands the result out for whoever draws the confirmation.
---
--- This is the olm side copy of Eyedropper, phase six of the olm build plan, and the
--- original this was copied from lived at Spoons/Eyedropper.spoon.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Eyedropper"
obj.version = "2.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("Eyedropper", "info")

-- The Swift source beside this file, resolved by absolute path off this file since a spoon dir is
-- not on package.path. The compiled binary is cached under Library Caches, outside
-- the watched config tree so building it never reloads Hammerspoon.
local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local SOURCE = spoonPath .. "sampler.swift"
local CACHE_DIR = os.getenv("HOME") .. "/Library/Caches/Hammerspoon-Eyedropper"
local BINARY = CACHE_DIR .. "/sampler"

-- Injected policy and live state.
obj._onPick = nil    -- optional showColor(hex), handed the sampled result to be shown
obj._compiler = nil  -- injected resolved Swift compiler path, the one external tool here
obj._task = nil      -- the running sampler task, if any
obj._active = false

--------------------------------------------------------------------------------
-- Building the native sampler helper
--------------------------------------------------------------------------------

-- Whether the cached binary is present and no older than the Swift source, so a
-- source edit forces a rebuild but an unchanged one is reused instantly.
local function binaryFresh()
  local bin = hs.fs.attributes(BINARY, "modification")
  if not bin then return false end
  local src = hs.fs.attributes(SOURCE, "modification")
  return src == nil or bin >= src
end

-- Ensure the binary exists and is current, then call done(ok). Reuses a fresh
-- binary at once, otherwise compiles the source into the cache dir and calls done
-- once that finishes. Compilation runs off the main thread through hs.task, so the
-- first pick after an edit does not block Hammerspoon. The compiler path is injected
-- rather than hardcoded, so this spoon probes for nothing, and with none injected a
-- stale or absent binary simply cannot be built.
local function ensureBinary(compiler, done)
  if binaryFresh() then done(true) return end
  if not compiler then
    log.e("no Swift compiler available, the colour sampler cannot be built")
    done(false)
    return
  end
  hs.fs.mkdir(CACHE_DIR)
  local build = hs.task.new(compiler, function(code, _, err)
    if code ~= 0 then
      log.e("compiling the sampler failed (" .. tostring(code) .. "), " .. tostring(err))
    end
    done(code == 0)
  end, { "-O", SOURCE, "-o", BINARY })
  build:start()
end

--------------------------------------------------------------------------------
-- Public control surface
--------------------------------------------------------------------------------

--- Eyedropper:isActive()
--- Method
--- Whether the native sampler is currently up.
function obj:isActive()
  return self._active
end

--- Eyedropper:pick()
--- Method
--- Show the native macOS colour sampler. On a click the picked pixel's hex is
--- copied to the clipboard and handed to onPick, Escape cancels. A no op while a
--- sampler is already up.
function obj:pick()
  if self._active then return end
  self._active = true
  ensureBinary(self._compiler, function(ok)
    if not ok then
      self._active = false
      hs.alert.show("Color picker unavailable")
      return
    end
    self._task = hs.task.new(BINARY, function(_, out)
      self._active = false
      self._task = nil
      local hex = (out or ""):match("#%x%x%x%x%x%x")
      if not hex then return end -- cancelled, nothing sampled
      hs.pasteboard.setContents(hex)
      if self._onPick then self._onPick(hex) end
    end)
    self._task:start()
  end)
end

--- Eyedropper:configure(opts)
--- Method
--- Inject optional policy.
---
--- showColor is a callback(hex) handed each sampled result on top of the clipboard copy, so
--- whoever owns the overlay surface can show it. Named for what the root supplies rather than
--- for the event that reaches it, since a root value is delivered by field name, and onPick was
--- a word only this plugin used and therefore a name nothing could ever have paid.
---
--- The Swift compiler's path is asked of opts.deps, the scoped adapter that declaring a tool
--- earns, since building the native sampler is the one thing here needing a tool from outside
--- Hammerspoon. This spoon looks for nothing itself and names no installer.
function obj:configure(opts)
  opts = opts or {}
  self._onPick = opts.showColor
  -- Asked of the scope adapter rather than read off opts.compiler, which nothing fills.
  --
  -- Declaring a tool entitles a plugin to the ADAPTER, under opts.deps, never to a resolved path
  -- under a name of its own choosing. Read as opts.compiler it was nil on every run, so the
  -- native sampler could never be built and the whole point of this tool, a colour picked off
  -- any pixel on screen, silently fell back to nothing. Three plugins had this same mistake,
  -- each under a different field name, which is what makes it a class rather than a typo.
  self._compiler = opts.deps and opts.deps.path("swiftc") or nil
  -- Warm the native sampler build in the background so the first pick stays instant.
  -- This is the one wiring point, so the compile happens here rather than in init,
  -- which stays a pure return per the lifecycle contract. It never blocks and is a no
  -- op when the cached binary is already current.
  ensureBinary(self._compiler, function() end)
  return self
end

--- Eyedropper:init()
--- Method
--- Initialise the spoon. No side effects, per the lifecycle contract; the sampler
--- build is warmed from configure, the one wiring point.
function obj:init()
  return self
end

return obj
