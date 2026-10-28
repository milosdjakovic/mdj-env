-- The SF Symbol source. A symbol is a vector from the system, so it is drawn in the colour the
-- engine hands over, and that is what lets an icon follow the light and dark halves where an
-- emoji cannot.
--
-- It is rendered in process through the AppKit bridge of hs.osascript.javascript, which needs no
-- compiler and no helper binary, verified on 2026 10 15 on Hammerspoon 1.1.1 at about 100 ms for
-- the first call. The script builds the symbol with a palette colour configuration and writes
-- a PNG to a scratch path, and the picture is then loaded and placed. A compiled Swift helper was
-- the alternative and is rejected, see decisions/olm-icons.md.
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
-- icon carries at least one pixel per device pixel on the sharpest screen in use. The bitmap
-- used to be one pixel per point and hs.canvas scaled it up, which is half the pixels needed on a
-- Retina screen and showed as a soft edge. A symbol is a vector, so the larger bitmap is drawn
-- from the vector at that size and is not a scaled copy. The scale is also the source's variant
-- for the engine's cache, so a picture drawn at one scale is never handed back at another.
--
-- A name is spliced into JavaScript, so only the characters a symbol name is made of are
-- allowed, and anything else answers nil exactly as an unknown name does.

local M = {}

local SIDE = 72
local ART = 60

-- The most a scale is allowed to be, a bound on the bitmap and not a guess at any screen.
local MAX_SCALE = 4

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
-- and nothing in that set can end a JavaScript string.
local function safeName(name)
  return type(name) == "string" and name ~= "" and name:match("^[%w%.%-]+$") ~= nil
end

-- A path as a JavaScript string literal, backslashes and quotes escaped so a directory with an
-- odd character in its name cannot end the string early.
local function jsString(text)
  return "'" .. text:gsub("[\\']", "\\%0"):gsub("\n", "\\n") .. "'"
end

--- M.script(name, color, path, scale) -> the JavaScript text, exposed so a test can read what is
--- spliced where. scale is the pixels per point, 1 when it is not given. Answers the string,
--- which ends in ok when the symbol was written and in unknown when AppKit has no symbol of
--- that name.
function M.script(name, color, path, scale)
  scale = tonumber(scale) or 1
  if scale < 1 then scale = 1 end
  local tint
  if type(color) == "table" then
    tint = string.format("$.NSColor.colorWithSRGBRedGreenBlueAlpha(%.4f, %.4f, %.4f, %.4f)",
      color.red or 0, color.green or 0, color.blue or 0, color.alpha or 1)
  else
    tint = "$.NSColor.labelColor"
  end
  return table.concat({
    "ObjC.import('AppKit');",
    "var col = " .. tint .. ";",
    "var cfg = $.NSImageSymbolConfiguration.configurationWithPointSizeWeightScale(64, 0, 2)",
    "  .configurationByApplyingConfiguration(",
    "    $.NSImageSymbolConfiguration.configurationWithPaletteColors($([col])));",
    "var img = $.NSImage.imageWithSystemSymbolNameAccessibilityDescription("
      .. jsString(name) .. ", $('x'));",
    "var result = 'unknown';",
    "if (!img.isNil()) {",
    "  img = img.imageWithSymbolConfiguration(cfg);",
    "  var side = " .. SIDE .. ", scale = " .. string.format("%.4f", scale) .. ";",
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
    "  rep.representationUsingTypeProperties(4, $()).writeToFileAtomically("
      .. jsString(path) .. ", true);",
    "  result = 'ok';",
    "}",
    "result;",
  }, "\n")
end

--- M.new(opts) -> source, the name sf and a draw function, see lib/icons/contract.lua.
--- opts.scratchDir  optional function answering a directory that exists, for the temporary
---                  PNG. The root hands in the storage lib's cache directory. Without it the
---                  system temporary name is used.
function M.new(opts)
  opts = opts or {}
  local source = { name = "sf", tinted = true }
  local counter = 0

  local function scratchPath()
    local dir = opts.scratchDir and opts.scratchDir()
    if dir then
      counter = counter + 1
      return string.format("%s/sf-%d-%d.png", dir, os.time(), counter)
    end
    return os.tmpname() .. ".png"
  end

  -- The scale a picture is drawn at, which the engine adds to its cache key.
  function source.variant()
    return string.format("%gx", M.scale())
  end

  function source.draw(name, points, color)
    if not safeName(name) then return nil end
    local path = scratchPath()
    local ok, result = hs.osascript.javascript(M.script(name, color, path, M.scale()))
    if not ok or result ~= "ok" then
      os.remove(path)
      return nil
    end
    local img = hs.image.imageFromPath(path)
    local size = img and img:size()
    os.remove(path)
    if not (size and size.w > 0 and size.h > 0) then return nil end
    if points and points ~= size.w then img = img:setSize({ w = points, h = points }) end
    return img
  end

  return source
end

return M
