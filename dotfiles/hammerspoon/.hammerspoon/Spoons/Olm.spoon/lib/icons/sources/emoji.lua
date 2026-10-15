-- The emoji source, a glyph drawn as text onto a canvas and snapshotted to an image.
--
-- These are the numbers lib/glyphicon.lua always drew with, a 72 point canvas with the glyph
-- at 60 points, centred, the full frame, and they stay because they were measured live
-- on 2026 10 14. The text size fills the same 60 of 72 points an app icon's artwork fills, so
-- an emoji row and an app row show icons of one size. The canvas is always 72 and the result
-- is sized to the points wanted, so a small icon is a reduced copy of a sharp one rather than
-- a second drawing with its own numbers.
--
-- One canvas is held and reused for every glyph, since at this scale a canvas per glyph is the
-- whole cost. This was measured for the emoji picker, which renders up to a hundred rows on
-- an open, and its notes are in plugins/emoji/AGENTS.md. The snapshot is independent of the
-- canvas, so reusing it cannot change an image already handed out.
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
  local canvas

  function source.draw(glyph, points)
    if type(glyph) ~= "string" or glyph == "" then return nil end
    if not canvas then
      canvas = hs.canvas.new({ x = 0, y = 0, w = SIDE, h = SIDE })
      -- type-exempt, a glyph drawn into a row icon image, sized to its 72 point box
      canvas[1] = { type = "text", text = "", textSize = TEXT, textAlignment = "center",
                    frame = { x = "0%", y = "0%", w = "100%", h = "100%" } }
    end
    canvas[1].text = glyph
    local img = canvas:imageFromCanvas()
    if img and points and points ~= SIDE then img = img:setSize({ w = points, h = points }) end
    return img
  end

  return source
end

return M
