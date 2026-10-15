-- The emoji source, a glyph drawn as text onto a canvas and snapshotted to an image.
--
-- These are the numbers lib/glyphicon.lua always drew with, a 72 point canvas with the glyph
-- at 60 points, centred, the full frame, and they stay because they were measured live
-- on 2026 10 14. The text size fills the same 60 of 72 points an app icon's artwork fills, so
-- an emoji row and an app row show icons of one size. The canvas is always 72 and the result
-- is sized to the points wanted, so a small icon is a reduced copy of a sharp one rather than
-- a second drawing with its own numbers.
--
-- Emoji carry their own colours, so this source ignores the colour it is handed and does not
-- declare itself tinted.

local M = {}

-- The canvas side, and the share of it the glyph fills. See the header for where they come from.
local SIDE = 72
local TEXT = 60

--- M.new() -> source, the name emoji and a draw function, see lib/icons/contract.lua.
function M.new()
  local source = { name = "emoji" }

  function source.draw(glyph, points)
    if type(glyph) ~= "string" or glyph == "" then return nil end
    local c = hs.canvas.new({ x = 0, y = 0, w = SIDE, h = SIDE })
    -- type-exempt, a glyph drawn into a row icon image, sized to its 72 point box
    c[1] = { type = "text", text = glyph, textSize = TEXT, textAlignment = "center",
             frame = { x = "0%", y = "0%", w = "100%", h = "100%" } }
    local img = c:imageFromCanvas()
    c:delete()
    if img and points and points ~= SIDE then img = img:setSize({ w = points, h = points }) end
    return img
  end

  return source
end

return M
