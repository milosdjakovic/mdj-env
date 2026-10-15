-- The icon door of the hosts that draw rows of their own. It began as the glyph drawer, lifted
-- out of Launcher's private drawing once ActionPanel became a second caller, and the drawing now
-- lives in lib/icons while the resolution of an owner and a key or spec lives in
-- lib/icons/rows.lua. What is left is the small door those two hosts hold, so a launcher row, an
-- action panel verb and a row a plugin names all come out of the same numbers and the same rule.
--
-- M.new(resolver) returns an instance with one function, dot called, matching lib/recency.lua
-- and lib/registry.lua. instance.icon(spec, owner) answers the resolver's image for that icon
-- as the owner reads it, a key into the owner's manifest icons or a table spec, at 72 points,
-- the size the launcher rows have always been drawn at and scaled down from, or nil for a nil
-- icon or one nothing can draw. The engine caches, so the very same image comes back on every
-- call after the first.

local M = {}

-- The side an icon is drawn at, and what a row icon is scaled down from. Public, so the root
-- builds the resolver at the same size and a hosted row and a keyed row come out alike.
local POINTS = 72
M.POINTS = POINTS

--- M.new(resolver) -> instance. resolver is a lib/icons/rows instance, answering image(spec, owner).
function M.new(resolver)
  local instance = {}

  --- instance.icon(spec, owner) -> hs.image or nil
  function instance.icon(spec, owner)
    if spec == nil or not resolver then return nil end
    return resolver.image(spec, owner)
  end

  return instance
end

return M
