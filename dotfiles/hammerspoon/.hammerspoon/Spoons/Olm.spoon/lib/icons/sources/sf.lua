-- The SF Symbol source. A symbol is a vector from the system, so it is drawn in the colour the
-- engine hands over, and that is what lets an icon follow the light and dark halves where an
-- emoji cannot.
--
-- Hammerspoon's own process never renders a symbol. A picture is a PNG file in the directory the
-- root hands in, the storage lib's cache directory for icons, named for everything that decides
-- it, the symbol, the side in points, the scale and the colour, so each picture is drawn once per
-- machine and survives every reload. A draw loads the file when it is there. When it is not, the
-- draw answers nil and pending, which the engine does not remember, and the symbol joins a queue
-- that a separate osascript process renders in the background, many pictures in one run. When
-- that process exits the onReady callback the root wired fires, and the root repaints whatever
-- list is showing, so the icon appears without a reopen.
--
-- It used to render in process through the AppKit bridge of hs.osascript.javascript. Every run
-- built a JavaScriptCore context group that bridged AppKit's metadata into strings and
-- dictionaries and was never released, so Hammerspoon grew by every symbol drawn, from 61 MB to
-- 564 MB after the swift chooser opened the launcher once, measured on 2026 10 28. A process that
-- exits takes whatever JXA leaks with it. See decisions/olm-icons.md.
--
-- The tool is declared in root/manifest.lua and its path comes through the dependency door, which
-- the root hands to configure. Nothing here names a path. Until configure runs a missing picture
-- waits in the queue, and once configure has said the tool is absent a missing picture answers a
-- plain nil, so the engine falls back to the next source and stops asking.
--
-- The root hands prefetch every symbol the manifests declare and the colour of the current half,
-- so a fresh machine renders the whole declared set in one run at load. A miss at a colour the
-- queue has not seen, the other half after a switch, queues every symbol the source has been told
-- about at that colour, so a switch costs one run and not one per row.
--
-- The configuration is a palette of one colour and not a hierarchical one, on purpose. A
-- hierarchical colour draws a symbol's secondary layers at reduced opacity, so a multi layer
-- symbol such as face.smiling or globe came out dim beside a single layer one such as
-- circle.fill. A palette hands every layer the same colour at full strength, which was checked
-- on 2026 10 15 by rendering both kinds and reading the pixels, so every icon has one contrast.
--
-- Symbols are not square, cup.and.saucer.fill comes out wider than it is tall, so the script
-- draws the symbol into a square bitmap, centred, keeping its aspect, and its longest side fills
-- the same share of the box the emoji source's glyph does, 60 of 72 points. The bitmap is SIDE
-- points square and SIDE times the scale pixels square, and its size in points is written into
-- the PNG, so the picture that is loaded reports 72 points whatever its pixels. The result is
-- then sized to the points wanted, the same way the emoji source does it, which changes the size
-- in points and leaves the bitmap as it is.
--
-- The scale is the largest backing scale among the attached screens, read from hs.screen, so an
-- icon carries at least one pixel per device pixel on the sharpest screen in use. A symbol is a
-- vector, so the larger bitmap is drawn from the vector at that size and is not a scaled copy.
-- The scale is in the file name and is also the source's variant for the engine's cache, so a
-- picture drawn at one scale is never handed back at another.
--
-- A symbol AppKit does not know leaves an empty marker file beside where its picture would be,
-- so it is not rendered again on the next load. The cache directory is safe to delete, which
-- only costs one run.
--
-- A name is spliced into JavaScript and into a file name, so only the characters a symbol name is
-- made of are allowed, and anything else answers nil exactly as an unknown name does.

local M = {}

local SIDE = 72
local ART = 60

-- The most a scale is allowed to be, a bound on the bitmap and not a guess at any screen.
local MAX_SCALE = 4

-- The suffix of the marker an unknown symbol leaves.
local UNKNOWN = ".none"

--- M.scale() -> number, the largest backing scale among the attached screens, never below 1.
--- It reads the scale of each screen's current mode, 1 for a native mode and 2 for a HiDPI one,
--- and answers 1 when hs.screen has no screens or cannot say.
function M.scale()
  local best = 1
  local ok, screens = pcall(function() return hs.screen.allScreens() end)
  if not ok or type(screens) ~= "table" then return best end
  for _, screen in ipairs(screens) do
    local okMode, mode = pcall(function() return screen:currentMode() end)
    local scale = okMode and type(mode) == "table" and tonumber(mode.scale) or nil
    if scale and scale > best then best = scale end
  end
  return math.min(best, MAX_SCALE)
end

-- The names a symbol is spelled with. Letters, digits, dots and dashes cover every SF Symbol,
-- and nothing in that set can end a JavaScript string or leave a directory.
local function safeName(name)
  return type(name) == "string" and name ~= "" and name:match("^[%w%.%-]+$") ~= nil
end

-- A path as a JavaScript string literal, backslashes and quotes escaped so a directory with an
-- odd character in its name cannot end the string early.
local function jsString(text)
  return "'" .. text:gsub("[\\']", "\\%0"):gsub("\n", "\\n") .. "'"
end

-- The colour as eight hex digits, the precision a PNG keeps, or label for no colour.
local function colorName(color)
  if type(color) ~= "table" then return "label" end
  local function byte(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
  return string.format("%02x%02x%02x%02x", byte(color.red or 0), byte(color.green or 0),
    byte(color.blue or 0), byte(color.alpha or 1))
end

--- M.fileName(name, color, scale) -> the file a picture is kept in, inside the cache directory.
--- Every value that decides the picture is in it, the symbol, the side in points, the scale and
--- the colour, so two pictures that differ never share a file.
function M.fileName(name, color, scale)
  return string.format("sf-%s-%dpt-%gx-%s.png", name, SIDE, scale, colorName(color))
end

-- The JavaScript colour expression for one job.
local function tintOf(color)
  if type(color) ~= "table" then return "$.NSColor.labelColor" end
  return string.format("$.NSColor.colorWithSRGBRedGreenBlueAlpha(%.4f, %.4f, %.4f, %.4f)",
    color.red or 0, color.green or 0, color.blue or 0, color.alpha or 1)
end

--- M.script(jobs) -> the JavaScript text one osascript run executes, exposed so a test can read
--- what is spliced where. jobs is a list of { name, color, scale, path }, each name already safe.
--- The run writes each picture to its path and prints one line per job it could not write,
--- unknown and the path when AppKit has no symbol of that name, failed and the path when drawing
--- raised or the file was not written.
function M.script(jobs)
  local out = {
    "ObjC.import('AppKit');",
    "function render(name, col, scale, path) {",
    "  var cfg = $.NSImageSymbolConfiguration.configurationWithPointSizeWeightScale(64, 0, 2)",
    "    .configurationByApplyingConfiguration(",
    "      $.NSImageSymbolConfiguration.configurationWithPaletteColors($([col])));",
    "  var img = $.NSImage.imageWithSystemSymbolNameAccessibilityDescription(name, $('x'));",
    "  if (img.isNil()) return 'unknown';",
    "  img = img.imageWithSymbolConfiguration(cfg);",
    "  var side = " .. SIDE .. ";",
    "  var px = Math.ceil(side * scale);",
    "  var rep = $.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(",
    "    $(), px, px, 8, 4, true, false, $.NSDeviceRGBColorSpace, 0, 0);",
    "  rep.size = $.NSMakeSize(side, side);",
    "  var ctx = $.NSGraphicsContext.graphicsContextWithBitmapImageRep(rep);",
    "  $.NSGraphicsContext.saveGraphicsState;",
    "  $.NSGraphicsContext.setCurrentContext(ctx);",
    "  ctx.imageInterpolation = 3;",
    "  var sz = img.size, k = " .. ART .. " / Math.max(sz.width, sz.height);",
    "  var w = sz.width * k, h = sz.height * k;",
    "  img.drawInRectFromRectOperationFraction($.NSMakeRect((side - w) / 2, (side - h) / 2, w, h),",
    "    $.NSZeroRect, 2, 1);",
    "  $.NSGraphicsContext.restoreGraphicsState;",
    "  var ok = rep.representationUsingTypeProperties(4, $()).writeToFileAtomically(path, true);",
    "  return ok ? 'ok' : 'failed';",
    "}",
    "var lines = [];",
    "function job(name, col, scale, path) {",
    "  var result;",
    "  try { result = render(name, col, scale, path); } catch (e) { result = 'failed'; }",
    "  if (result !== 'ok') lines.push(result + '\\t' + path);",
    "}",
  }
  for _, j in ipairs(jobs) do
    local scale = tonumber(j.scale) or 1
    if scale < 1 then scale = 1 end
    out[#out + 1] = string.format("job(%s, %s, %.4f, %s);", jsString(j.name), tintOf(j.color),
      scale, jsString(j.path))
  end
  out[#out + 1] = "lines.join('\\n');"
  return table.concat(out, "\n")
end

-- Whether a file is on disk.
local function exists(path)
  return hs.fs.attributes(path, "mode") ~= nil
end

--- M.new(opts) -> source, the name sf, a draw function and the two members the root wires, see
--- lib/icons/contract.lua for draw.
--- opts.dir  function answering the directory pictures are kept in, which exists. The root hands
---           in the storage lib's cache directory for icons.
--- opts.log  optional table with w, told when a run fails.
---
--- source.configure{ osascript = path or nil, onReady = function } hands over the tool's path
--- from the dependency door and the callback fired after a run that wrote a picture. Called once
--- the door has answered, and any picture asked for before then is rendered from that moment.
---
--- source.prefetch(names, color) queues every name whose picture is not on disk, at color and
--- the current scale, and remembers the names, so a later miss at another colour queues them all.
function M.new(opts)
  opts = opts or {}
  local source = { name = "sf", tinted = true }
  local tool, configured, onReady = nil, false, nil
  local known, knownList = {}, {}
  -- The jobs waiting for a run, the same by path, and the paths of the run in flight.
  local queue, queued, flying = {}, {}, {}
  -- path to true for a picture that cannot be made this session, after a failed run or with no tool.
  local refused = {}
  local scheduled, running = nil, nil
  local counter = 0

  local function dir()
    return opts.dir and opts.dir() or nil
  end

  local function remember(name)
    if not known[name] then
      known[name] = true
      knownList[#knownList + 1] = name
    end
  end

  local function loadPicture(path, points)
    local img = hs.image.imageFromPath(path)
    local size = img and img:size()
    if not (size and size.w > 0 and size.h > 0) then return nil end
    if points and points ~= size.w then img = img:setSize({ w = points, h = points }) end
    return img
  end

  local runBatch

  local function schedule()
    if scheduled or running or not configured or not tool or #queue == 0 then return end
    -- One turn of the run loop, so the misses of one paint join one run.
    scheduled = hs.timer.doAfter(0, function()
      scheduled = nil
      runBatch()
    end)
  end

  -- Queues name at color and scale unless its picture or marker is on disk, it cannot be made
  -- this session, or it is already waiting.
  local function enqueue(base, name, color, scale)
    local path = base .. "/" .. M.fileName(name, color, scale)
    if queued[path] or flying[path] or refused[path] then return end
    if exists(path) or exists(path .. UNKNOWN) then return end
    queued[path] = true
    queue[#queue + 1] = { name = name, color = color, scale = scale, path = path }
  end

  local function finish(jobs, code, stdout)
    running = nil
    local unknown, failed = {}, {}
    for kind, path in tostring(stdout or ""):gmatch("(%a+)\t([^\n]+)") do
      if kind == "unknown" then unknown[path] = true else failed[path] = true end
    end
    local wrote, refusedCount = false, 0
    for _, job in ipairs(jobs) do
      flying[job.path] = nil
      if unknown[job.path] then
        local marker = io.open(job.path .. UNKNOWN, "w")
        if marker then marker:close() end
      elseif code == 0 and not failed[job.path] and exists(job.path) then
        wrote = true
      else
        refused[job.path] = true
        refusedCount = refusedCount + 1
      end
    end
    if refusedCount > 0 and opts.log then
      opts.log.w(string.format("sf icons, %d of %d symbols were not rendered, osascript exited %s",
        refusedCount, #jobs, tostring(code)))
    end
    schedule()
    if wrote and onReady then onReady() end
  end

  function runBatch()
    local base = dir()
    if running or not tool or not base or #queue == 0 then return end
    local jobs = queue
    queue = {}
    for _, job in ipairs(jobs) do
      queued[job.path] = nil
      flying[job.path] = true
    end
    counter = counter + 1
    local scriptPath = string.format("%s/sf-run-%d-%d.js", base, os.time(), counter)
    local file = io.open(scriptPath, "w")
    local task
    if file then
      file:write(M.script(jobs))
      file:close()
      task = hs.task.new(tool, function(code, stdout)
        os.remove(scriptPath)
        finish(jobs, code, stdout)
      end, { "-l", "JavaScript", scriptPath })
    end
    if not (task and task:start()) then
      if file then os.remove(scriptPath) end
      finish(jobs, -1, "")
      return
    end
    running = task
  end

  -- The scale a picture is drawn at, which the engine adds to its cache key.
  function source.variant()
    return string.format("%gx", M.scale())
  end

  function source.draw(name, points, color)
    if not safeName(name) then return nil end
    local base = dir()
    if not base then return nil end
    local scale = M.scale()
    local path = base .. "/" .. M.fileName(name, color, scale)
    if queued[path] or flying[path] then return nil, true end
    if refused[path] then return nil end
    if exists(path) then return loadPicture(path, points) end
    if exists(path .. UNKNOWN) then return nil end
    if configured and not tool then return nil end
    -- A miss queues this symbol and every symbol the source knows at this colour, so the other
    -- half after a switch is one run.
    remember(name)
    for _, other in ipairs(knownList) do enqueue(base, other, color, scale) end
    schedule()
    return nil, true
  end

  function source.prefetch(names, color)
    local base = dir()
    if not base then return end
    local scale = M.scale()
    for _, name in ipairs(names or {}) do
      if safeName(name) then
        remember(name)
        enqueue(base, name, color, scale)
      end
    end
    schedule()
  end

  function source.configure(config)
    config = config or {}
    tool = config.osascript
    onReady = config.onReady
    configured = true
    if not tool then
      for _, job in ipairs(queue) do
        queued[job.path] = nil
        refused[job.path] = true
      end
      queue = {}
      return
    end
    schedule()
  end

  return source
end

return M
