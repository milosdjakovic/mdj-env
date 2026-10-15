-- The icon engine. A row names an icon as data, a spec keyed by source name, and this answers
-- the picture, so no plugin draws one and no two plugins drift apart. Strategy, with the
-- sources as the strategies and the order as the policy that chooses among them.
--
-- The engine depends only on lib/icons/contract.lua. It never names a concrete source, the
-- composition root builds the sources and the order and hands both in, and a new source is
-- a new file under lib/icons/sources plus one line in that root.
--
-- M.new{ sources = { ... }, order = { "sf", "emoji" }, color = function() ... end } returns an
-- instance with one function, dot called like every other factory here, instance.image(spec,
-- points). order is the active set first and the fallback after it, and the first source that
-- both has an entry in the spec and draws a picture wins. A source with no entry is skipped
-- and so is one that draws nothing, which is what lets a spec carry an sf entry for most of a
-- plugin's icons and still show the emoji where a symbol name is unknown.
--
-- A string spec is shorthand for { emoji = string }, since the plain glyph is the common case
-- and the shipped fallback. The shorthand names the source emoji, which the root registers
-- under that name, so it is the one place this file knows a name, a seam and not a coupling to
-- a file.
--
-- Each icon is drawn once. The cache key is the source, its value and the size, plus the colour
-- for a source that declares it takes one, so a theme switch redraws a symbol and leaves an
-- emoji alone. A draw that answers nothing is remembered as false, so a spec nothing can
-- render is asked for once, and answered back out as nil.

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local contractChunk = assert(loadfile(here .. "contract.lua"))
local contract = contractChunk()

local M = {}

M.contract = contract

-- The one source name the string shorthand reaches. See the header.
local SHORTHAND = "emoji"

local function colorKey(color)
  if type(color) ~= "table" then return "-" end
  return string.format("%.4f,%.4f,%.4f,%.4f", color.red or 0, color.green or 0, color.blue or 0,
    color.alpha or 1)
end

--- M.new(opts) -> instance
--- opts.sources  array of sources, each validated against the contract. A bad one raises.
--- opts.order    array of source names, tried in turn. A name no source answers to is skipped.
--- opts.color    optional function answering the colour a tinted source draws in, called on
---               every image call so a theme change is seen on the next draw.
function M.new(opts)
  opts = opts or {}
  local byName = {}
  for _, source in ipairs(opts.sources or {}) do
    contract.validate(source)
    if byName[source.name] then
      error("icon source '" .. source.name .. "' is registered twice", 2)
    end
    byName[source.name] = source
  end
  local order = opts.order or {}
  local colorOf = opts.color
  local instance = {}
  local cache = {}

  local function specOf(spec)
    if type(spec) == "string" then return { [SHORTHAND] = spec } end
    if type(spec) == "table" then return spec end
    return nil
  end

  --- instance.image(spec, points) -> hs.image or nil
  --- spec is a table keyed by source name, or a string meaning its emoji. points is the square
  --- side wanted. Answers nil for a spec no source in the order can draw.
  function instance.image(spec, points)
    spec = specOf(spec)
    if not spec then return nil end
    local color
    local colorFetched = false
    for _, name in ipairs(order) do
      local source = byName[name]
      local value = source and spec[name]
      if value ~= nil then
        local key = name .. "\0" .. tostring(value) .. "\0" .. tostring(points)
        if source.tinted then
          if not colorFetched then
            color = colorOf and colorOf() or nil
            colorFetched = true
          end
          key = key .. "\0" .. colorKey(color)
        end
        if cache[key] == nil then
          cache[key] = source.draw(value, points, source.tinted and color or nil) or false
        end
        if cache[key] then return cache[key] end
      end
    end
    return nil
  end

  --- instance.has(name) -> boolean, whether a source answers to this name, so the root can
  --- warn about an order that names one nothing registered.
  function instance.has(name)
    return byName[name] ~= nil
  end

  return instance
end

return M
