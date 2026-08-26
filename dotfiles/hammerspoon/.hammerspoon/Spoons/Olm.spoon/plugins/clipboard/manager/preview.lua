--- Async preview-image generation, a Chain of Responsibility over pluggable
--- backends.
---
--- The store persists media, then needs a small downscaled PNG for the preview
--- pane and, for image copies, a tiny row thumbnail. HOW that PNG is produced
--- depends on the source type: sips resizes a raster image, ffmpeg grabs a frame
--- from a video, and hs.image renders the rest (pdf first page, icns). Each
--- backend is a generator that declares which extensions it covers and runs off
--- the main thread (via hs.task) so a large image or video never stalls
--- Hammerspoon.
---
--- The mechanism (the chain) names no concrete backend and the generators name no
--- other. The composition root, P.configure, injects util and resolves the tool
--- paths the generators read; the order lives in the chain. Adding a type is a new
--- generator plus one line in the chain.
---
--- A generator:
---   name
---   handles(ext) -> bool   does this backend cover the extension right now
---   run(spec, cb)          write spec.dest (a PNG), then cb(ok) on the main thread
--- spec = { path = <source file>, ext = <lower ext>, dest = <output png>,
---          edge = <max px, the larger dimension> }

local P = {}

local util = nil
local ffmpeg = nil -- injected absolute path, or nil when ffmpeg is not installed
local ffprobe = nil
local sips = nil -- injected absolute path, or nil when the dependency door could not place it

local function wrote(dest)
  return hs.fs.attributes(dest) ~= nil
end

--------------------------------------------------------------------------------
-- Generators
--------------------------------------------------------------------------------

-- Raster images: sips resizes to an edge-box keeping aspect ratio and forces PNG,
-- so heic/webp become something the preview webview always renders. Built into
-- macOS, so it is always available.
local sipsGen = {
  name = "sips",
  handles = function(ext)
    return util.RASTER_EXT[ext] == true
  end,
  run = function(spec, cb)
    -- sips ships on every real Mac, so a nil path here is a stranger machine rather than
    -- the ordinary case, and it takes the same route hs.task.new failing already takes,
    -- one raster preview quietly missing rather than an error.
    if not sips then
      cb(false)
      return
    end
    local t = hs.task.new(sips, function(code)
      cb(code == 0 and wrote(spec.dest))
    end, { "-s", "format", "png", "-Z", tostring(spec.edge), spec.path, "--out", spec.dest })
    if t then
      t:start()
    else
      cb(false)
    end
  end,
}

-- Videos: ffmpeg grabs a single frame from a random point in the clip, scaled so
-- the width is at most edge, keeping aspect ratio. The duration comes from ffprobe
-- so the seek stays inside the clip; a short or unreadable clip falls back to the
-- first frame. Needs Homebrew ffmpeg, so handles() gates on it being resolved and
-- the store then skips a preview path for videos on a machine without it.
local videoGen = {
  name = "ffmpeg",
  handles = function(ext)
    return ffmpeg ~= nil and util.VIDEO_EXT[ext] == true
  end,
  run = function(spec, cb)
    local function grab(at)
      -- The comma in min() must be escaped so ffmpeg's filtergraph parser does not
      -- read it as a filter separator.
      local scale = "scale=w=min(iw\\," .. tostring(spec.edge) .. "):h=-1"
      local task = hs.task.new(ffmpeg, function(code)
        cb(code == 0 and wrote(spec.dest))
      end, {
        "-loglevel", "error", "-ss", string.format("%.3f", at), "-i", spec.path,
        "-frames:v", "1", "-vf", scale, "-y", spec.dest,
      })
      if task then
        task:start()
      else
        cb(false)
      end
    end

    if not ffprobe then
      grab(0)
      return
    end
    local probe = hs.task.new(ffprobe, function(_, out)
      local dur = tonumber((out or ""):match("[%d%.]+"))
      if dur and dur > 0.4 then
        -- A random point in the middle band, avoiding intro/outro black frames.
        grab(dur * (0.1 + math.random() * 0.75))
      else
        grab(0)
      end
    end, { "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", spec.path })
    if probe then
      probe:start()
    else
      grab(0)
    end
  end,
}

-- Everything else macOS can draw (pdf first page, icns): hs.image on the main
-- thread. These are small and rare, so the in-process render is acceptable and
-- needs no external tool.
local hsImageGen = {
  name = "hsimage",
  handles = function(ext)
    return util.DOC_EXT[ext] == true
  end,
  run = function(spec, cb)
    local img = hs.image.imageFromPath(spec.path)
    if not img then
      cb(false)
      return
    end
    local ok = img:copy():setSize({ w = spec.edge, h = spec.edge }):saveToFile(spec.dest)
    cb(ok and true or false)
  end,
}

-- The chain, in priority order. Generators read the tool paths configure resolves.
local chain = { sipsGen, videoGen, hsImageGen }

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- P.canPreview(ext) -> bool
--- Does any generator cover this extension right now (video depends on ffmpeg
--- being installed). The store asks before setting a preview path, so a type with
--- no backend never gets a path pointing at a file that will not exist.
function P.canPreview(ext)
  for _, g in ipairs(chain) do
    if g.handles(ext) then
      return true
    end
  end
  return false
end

--- P.generate(spec, cb)
--- Run the first matching generator. spec = { path, ext, dest, edge }. cb(ok)
--- fires on the main thread when the PNG is written or on failure. No match calls
--- cb(false).
function P.generate(spec, cb)
  cb = cb or function() end
  for _, g in ipairs(chain) do
    if g.handles(spec.ext) then
      g.run(spec, cb)
      return
    end
  end
  cb(false)
end

--- P.configure(opts)
--- Inject util and the tool paths. This module resolves nothing itself, the paths come
--- from the outside already resolved, so it names no binary location and no installer,
--- and the shared resolver above it does the probing once for every consumer. A nil
--- ffmpeg simply leaves the video generator unable to handle anything, which the chain
--- treats as any other non handler, and the shared summary line already reports the
--- absence, so nothing is logged twice here. sips and hs.image need nothing installed.
function P.configure(opts)
  util = opts.util
  ffmpeg = opts.ffmpeg
  ffprobe = opts.ffprobe
  sips = opts.sips
  return P
end

return P
