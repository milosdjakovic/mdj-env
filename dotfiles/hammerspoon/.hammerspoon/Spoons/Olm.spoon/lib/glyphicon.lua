-- The glyph to icon drawer, lifted out of Launcher's own private _glyphIcon once
-- ActionPanel became a genuine second caller of the exact same drawing, phase eight's
-- third packet. A row with no app bundle behind it, a command, a window action, a panel
-- verb, still wants something in its icon slot, and this is what turns an emoji into an
-- hs.image sized and framed to line up with a real app icon, drawn once per glyph and
-- cached from then on.
--
-- M.new() returns an independent instance, a factory in the same style as
-- lib/recency.lua and lib/registry.lua, since a cache is state and each caller owns
-- one. There is exactly one function on the returned instance, dot called rather than
-- colon called, since there is no metatable here and no self to receive, matching both
-- of those modules exactly.
--
-- instance.icon(glyph) answers a cached hs.image for that glyph, drawing it the first
-- time and answering the very same cached object on every call after, or nil for a nil
-- glyph and nil for a glyph that drew nothing. The canvas size, the text size, the
-- alignment, and the frame are copied exactly from the drawing Launcher owned before
-- this packet, unchanged in every number, since a launcher row and a panel row have to
-- line up and any change to those numbers would be a change to the launcher this packet
-- is not making. A drawing that answers no image is remembered as false internally, so a
-- glyph nothing can render is asked for once rather than on every row it appears on, and
-- answered back out as nil, the honest public answer, never the internal sentinel.

local M = {}

--- M.new() returns instance.
--- Returns a fresh instance holding its own cache, independent of any other instance,
--- so two callers never share or invalidate each other's drawings.
function M.new()
  local instance = {}
  local cache = {}

  --- instance.icon(glyph)
  --- The cached hs.image for this glyph, drawn once and reused after. nil in, nil out.
  --- A glyph that draws nothing is cached as false internally so it is only ever drawn
  --- once, and this still answers nil for it, never the internal sentinel.
  function instance.icon(glyph)
    if not glyph then return nil end
    if cache[glyph] == nil then
      local size = 72
      local c = hs.canvas.new({ x = 0, y = 0, w = size, h = size })
      c[1] = { type = "text", text = glyph, textSize = 52, textAlignment = "center",
               frame = { x = "0%", y = "8%", w = "100%", h = "100%" } }
      cache[glyph] = c:imageFromCanvas() or false
      c:delete()
    end
    return cache[glyph] or nil
  end

  return instance
end

return M
