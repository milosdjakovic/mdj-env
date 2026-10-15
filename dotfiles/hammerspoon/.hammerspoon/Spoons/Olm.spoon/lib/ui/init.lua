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

--- ui.loadTypography(path, read, log), the composition root's reader for the typography
--- file, see lib/ui/style.lua. It answers the valid fonts and sizes for the spec.
ui.loadTypography = styleLib.loadTypography

--- ui.configure(opts), the composition root's door.
--- opts.spec             the style spec, see lib/ui/style.lua.
--- opts.surfaceElements  CanvasPanel.surfaceElements, what a surface node paints.
--- opts.surfaceInterior  CanvasPanel.surfaceInterior, the box inside the surface's border.
--- Callable more than once, each call replacing only what it names.
local surfaceInterior = nil

function ui.configure(opts)
  opts = opts or {}
  if opts.spec ~= nil then style.configure(opts.spec) end
  if opts.surfaceInterior ~= nil then surfaceInterior = opts.surfaceInterior end
  if opts.surfaceElements ~= nil then
    engine = layoutLib.new({ measure = measure, surfaceElements = opts.surfaceElements })
  end
  return ui
end

--- ui.tokens() -> the resolved token table for the half the system is on now. A shallow
--- copy of a cached table, so a caller copies any nested group before changing it.
function ui.tokens()
  return style.tokens()
end

--- ui.half() -> "dark" | "light", which half the system is on now, without building tokens.
function ui.half()
  return style.half()
end

--- ui.layout(node, rect, opts) -> elements, contentHeight.
--- The engine's layout with the current tokens filled in. opts.tokens overrides them, for a
--- caller that resolved a table once and draws several trees from it.
function ui.layout(node, rect, opts)
  opts = opts or {}
  return engine.layout(node, rect, opts.tokens or style.tokens(), opts)
end

--- ui.interior(w, h) -> the box inside the border of a w x h surface at origin (0, 0), the
--- viewport a pane hands ui.layout so scrolled content is cut by the pane's edge rather than
--- by its padding. The whole box when no surface was configured.
function ui.interior(w, h)
  if surfaceInterior then return surfaceInterior(w, h) end
  return { x = 0, y = 0, w = w, h = h }
end

--- ui.nestedRadius(outer, gap) -> the corner radius for a shape sitting gap points inside a
--- shape rounded by outer, so both corners share one centre and the inner one reads as fitting
--- the outer one rather than as a second, unrelated curve. The outer radius less the gap, never
--- below square. A highlighted row inside a surface takes its radius from here, and so does
--- anything else drawn near an edge that should follow the surface's rounding.
ui.nestedRadius = styleLib.nestedRadius

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
