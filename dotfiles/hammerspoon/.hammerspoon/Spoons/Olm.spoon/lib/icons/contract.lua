-- The contract an icon source answers, and the check that refuses one that does not.
--
-- A source is a table with a name and a draw function. The name is the key a spec uses to
-- address it, `{ emoji = "☕", sf = "cup.and.saucer.fill" }` reaches the source named emoji
-- with the first value and the one named sf with the second, so a spec carries one value per
-- source and the engine in lib/icons/init.lua never learns what either value means.
--
--   source.name                       a non empty string, unique among the sources of one engine.
--   source.draw(spec, points, color)  an hs.image sized points by points, or nil when this
--                                     source cannot draw that spec. spec is the source's own
--                                     value, an emoji string, an SF Symbol name. color is an hs
--                                     color table such as the kit hands out, or nil, and a
--                                     source that draws a picture of its own colours ignores it.
--   source.tinted                     optional boolean. True for a source whose picture takes the
--                                     colour it is given, so the engine keys its cache on the
--                                     colour for that source alone and a source that ignores
--                                     colour is not redrawn on every light and dark switch.
--   source.elements(spec, frame, color)
--                                     optional. Canvas elements that draw the spec straight
--                                     into frame, a table of x, y, w and h, or nil when this
--                                     source cannot draw it. A source offers it when drawing in
--                                     place is cheaper than keeping a picture, and the engine
--                                     then never draws or caches a picture for a canvas that
--                                     asks for elements. A source without it is wrapped, its
--                                     cached picture placed in the frame as an image element.
--
-- A Lua contract is structural, a documented set of members and no compiled interface, so
-- this is a runtime check and says only what it checked. It cannot prove draw answers the
-- right thing, only that there is a function to ask.

local M = {}

--- M.validate(source) -> source
--- Raises an error naming the source when it breaks the contract, and answers the source
--- unchanged otherwise, so a caller can validate where it registers.
function M.validate(source)
  if type(source) ~= "table" then
    error("icon source is " .. type(source) .. ", not a table", 3)
  end
  local label = type(source.name) == "string" and source.name ~= "" and source.name or "(unnamed)"
  if label == "(unnamed)" then
    error("icon source has no name, it needs a non empty string name", 3)
  end
  if type(source.draw) ~= "function" then
    error("icon source '" .. label .. "' has no draw function", 3)
  end
  if source.elements ~= nil and type(source.elements) ~= "function" then
    error("icon source '" .. label .. "' has an elements field that is not a function", 3)
  end
  if source.tinted ~= nil and type(source.tinted) ~= "boolean" then
    error("icon source '" .. label .. "' has a tinted field that is not a boolean", 3)
  end
  return source
end

return M
