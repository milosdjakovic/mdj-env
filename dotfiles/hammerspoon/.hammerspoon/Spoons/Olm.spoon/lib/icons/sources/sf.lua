-- The SF Symbol source. A symbol is a vector from the system, so it is drawn in the colour the
-- engine hands over, and that is what lets an icon follow the light and dark halves where an
-- emoji cannot.
--
-- It is rendered in process through the AppKit bridge of hs.osascript.javascript, which needs no
-- compiler and no helper binary, verified on 2026 10 15 on Hammerspoon 1.1.1 at about 100 ms for
-- the first call. The script builds the symbol with a hierarchical colour configuration and writes
-- a PNG to a scratch path, and the picture is then loaded and placed. A compiled Swift helper was
-- the alternative and is rejected, see decisions/olm-icons.md.
--
-- Symbols are not square, cup.and.saucer.fill comes out wider than it is tall, so the loaded
-- image is drawn into a square canvas, centred, keeping its aspect, and its longest side fills
-- the same share of the box the emoji source's glyph does, 60 of 72 points. The result is then
-- sized to the points wanted, the same way the emoji source does it.
--
-- A name is spliced into JavaScript, so only the characters a symbol name is made of are
-- allowed, and anything else answers nil exactly as an unknown name does.

local M = {}

local SIDE = 72
local ART = 60

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

--- M.script(name, color, path) -> the JavaScript text, exposed so a test can read what is
--- spliced where. Answers the string, which ends in ok when the symbol was written and in
--- unknown when AppKit has no symbol of that name.
function M.script(name, color, path)
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
    "    $.NSImageSymbolConfiguration.configurationWithHierarchicalColor(col));",
    "var img = $.NSImage.imageWithSystemSymbolNameAccessibilityDescription("
      .. jsString(name) .. ", $('x'));",
    "var result = 'unknown';",
    "if (!img.isNil()) {",
    "  img = img.imageWithSymbolConfiguration(cfg);",
    "  var rep = $.NSBitmapImageRep.imageRepWithData(img.TIFFRepresentation);",
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

  function source.draw(name, points, color)
    if not safeName(name) then return nil end
    local path = scratchPath()
    local ok, result = hs.osascript.javascript(M.script(name, color, path))
    if not ok or result ~= "ok" then
      os.remove(path)
      return nil
    end
    local loaded = hs.image.imageFromPath(path)
    local size = loaded and loaded:size()
    local img
    if size and size.w > 0 and size.h > 0 then
      local scale = ART / math.max(size.w, size.h)
      local w, h = size.w * scale, size.h * scale
      local c = hs.canvas.new({ x = 0, y = 0, w = SIDE, h = SIDE })
      c[1] = { type = "image", image = loaded, imageScaling = "scaleProportionally",
               frame = { x = (SIDE - w) / 2, y = (SIDE - h) / 2, w = w, h = h } }
      img = c:imageFromCanvas()
      c:delete()
    end
    os.remove(path)
    if img and points and points ~= SIDE then img = img:setSize({ w = points, h = points }) end
    return img
  end

  return source
end

return M
