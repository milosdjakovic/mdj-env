-- The one table a plugin receives as needs.lib.ui. It holds the primitives, the layout
-- call, tokens answering the current half, and the measurer, and it is the only file in
-- lib/ui that knows the other four exist. Style answers the look, measure answers widths,
-- kit answers what a node is, layout answers where it goes, and this file wires them.
--
-- configure is the composition root's door, the same way CanvasPanel.configure is, and a
-- plugin never calls it. It takes the style spec the root builds from policy and the
-- surface routine the chrome is painted with.
--
-- One instance, loaded by the spoon into Olm.lib like every other shared atom, so every
-- plugin reads the same configured style rather than a fresh unconfigured copy.

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(here .. name)
  if not chunk then error("Olm ui failed to load " .. name .. ", " .. tostring(err)) end
  return chunk()
end

local styleLib = load("style.lua")
local measureLib = load("measure.lua")
local kitLib = load("kit.lua")
local layoutLib = load("layout.lua")

local style = styleLib.new()
local measure = measureLib.new()
local engine = layoutLib.new({ measure = measure })

local ui = kitLib.new(styleLib.names)

ui.measure = measure

--- ui.configure(opts), the composition root's door.
--- opts.spec             the style spec, see lib/ui/style.lua.
--- opts.surfaceElements  CanvasPanel.surfaceElements, what a surface node paints.
--- Callable more than once, each call replacing only what it names.
function ui.configure(opts)
  opts = opts or {}
  if opts.spec ~= nil then style.configure(opts.spec) end
  if opts.surfaceElements ~= nil then
    engine = layoutLib.new({ measure = measure, surfaceElements = opts.surfaceElements })
  end
  return ui
end

--- ui.tokens() -> the resolved token table for the half the system is on now.
function ui.tokens()
  return style.tokens()
end

--- ui.layout(node, rect, opts) -> elements, contentHeight.
--- The engine's layout with the current tokens filled in. opts.tokens overrides them, for a
--- caller that resolved a table once and draws several trees from it.
function ui.layout(node, rect, opts)
  opts = opts or {}
  return engine.layout(node, rect, opts.tokens or style.tokens(), opts)
end

--- ui.iconImage(imageOrGlyph, size) -> hs.image or nil, size an icon name. The image an
--- icon node draws, for a native chooser row that wants the same picture.
function ui.iconImage(source, size)
  local points = style.tokens().icon[size]
  if not points then
    error("ui.iconImage, unknown size '" .. tostring(size) .. "'", 2)
  end
  return engine.iconImage(source, points)
end

return ui
