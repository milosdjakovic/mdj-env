-- The glyph to icon facade. It began as the drawer itself, lifted out of Launcher's private
-- drawing once ActionPanel became a second caller, and the drawing now lives in lib/icons so
-- that one engine draws every icon Olm shows and the launcher, the action panel and every
-- row a plugin names all come out of the same numbers. What is left is the small door those
-- two hosts already hold, so neither changed when the drawing moved.
--
-- M.new(engine) returns an instance with one function, dot called, matching lib/recency.lua and
-- lib/registry.lua. instance.icon(glyph) answers the engine's image for that glyph as an emoji
-- at 72 points, the size the launcher rows have always been drawn at and scaled down from, or
-- nil for a nil glyph or one nothing can draw. The engine caches, so the very same image comes
-- back on every call after the first.

local M = {}

-- The side the glyph is drawn at, and what a row icon is scaled down from. Public, so the root
-- draws a manifest icon at the same size and a glyph row and a keyed row come out alike.
local POINTS = 72
M.POINTS = POINTS

--- M.new(engine) -> instance. engine is a lib/icons instance, answering image(spec, points).
function M.new(engine)
  local instance = {}

  --- instance.icon(glyph) -> hs.image or nil
  function instance.icon(glyph)
    if not glyph or not engine then return nil end
    return engine.image({ emoji = glyph }, POINTS)
  end

  return instance
end

return M
