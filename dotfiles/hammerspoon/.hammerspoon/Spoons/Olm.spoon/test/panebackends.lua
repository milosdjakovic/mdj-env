-- The docked pane's two drawing backends, in plain Lua over a stub canvas and a stub library.
--
-- Pins that lib/dockedpane.lua hands both backends the same thing, so the native pane can only
-- ever draw what the canvas pane draws. The same pane is driven twice over the same describer
-- and painter, once over lib/dockedpane/canvas.lua on a recording hs.canvas stub and once over
-- lib/chooser/providers/swift/pane.lua on a recording stand in for the Swift library, for an
-- empty state, a described pane and a painted pane.
-- For each, the canvas is handed the surface and then the content as one list, the library is
-- handed the very content list the pane rendered, equal to the canvas's element for element and
-- nothing more, at the corner radius the surface was drawn with, and both are placed on the
-- same rect and shown in the same order of calls.
-- Then that hide, a redock and destroy reach both, that the native pane is placed on the rect it
-- is docked on before every draw, which is what the library matches it to its chooser on, and
-- that what the library could not draw is said once per name however often the pane repaints.
--
-- Then scrolling, where the two differ on purpose. The canvas pane scrolls as it always has, the
-- offset clamped in Lua, the content shifted by it, a thumb drawn, one paint a frame through the
-- timer, and its backend rendered with the surface and the content alone. The native pane answers
-- that it scrolls natively, so it is handed the content laid out at its full height, unshifted
-- and cut only at the viewport grown by the overflow, with the full height, the pane's height, the
-- reset and the thumb, scrollBy becomes the library's own scroll with no paint and no timer, and a
-- redraw of the same content keeps its place while new content goes back to the top. A painter is
-- called again with the grown viewport, which is how one that cuts at the viewport hands it all.
--
-- How Swift draws the list, and which window it draws it in, is measured live, not here.
--
-- Run it.
--   lua test/panebackends.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local spoon = here .. "../"
local failed = false

local function check(name, got, want)
  if got ~= want then
    failed = true
    print(("FAIL %s, wanted %s, got %s"):format(name, tostring(want), tostring(got)))
  else
    print(("ok   %s"):format(name))
  end
end

local DockedPane = dofile(spoon .. "lib/dockedpane.lua")
local CanvasBackend = dofile(spoon .. "lib/dockedpane/canvas.lua")
local SwiftPane = dofile(spoon .. "lib/chooser/providers/swift/pane.lua")

--------------------------------------------------------------------------------
-- Stubs
--------------------------------------------------------------------------------

-- A canvas that records what it is told, newest canvas last.
local canvases = {}
local canvasLib = {
  windowLevels = { floating = "floating" },
  new = function(frame)
    local c = { made = frame, calls = {} }
    function c:level(l) self.lvl = l end
    function c:clickActivating(v) self.activating = v end
    function c:frame(f) self.at = f; self.calls[#self.calls + 1] = "frame" end
    function c:replaceElements(els) self.els = els; self.calls[#self.calls + 1] = "replace" end
    function c:show() self.shown = true; self.calls[#self.calls + 1] = "show" end
    function c:hide() self.shown = false; self.calls[#self.calls + 1] = "hide" end
    function c:delete() self.deleted = true; self.shown = false end
    canvases[#canvases + 1] = c
    return c
  end,
}

-- The Swift library's pane functions, recording what each pane is told. paneDraw answers what
-- `refuse` names, the way the library names what it could not draw.
local panes, nextId, refuse = {}, 40, {}
local native = {
  paneNew = function()
    nextId = nextId + 1
    panes[nextId] = { id = nextId, calls = {} }
    return nextId
  end,
  panePlace = function(id, rect) panes[id].at = rect; table.insert(panes[id].calls, "place") end,
  paneDraw = function(id, radius, els)
    panes[id].radius, panes[id].els = radius, els
    table.insert(panes[id].calls, "draw")
    return refuse
  end,
  paneShow = function(id) panes[id].shown = true; table.insert(panes[id].calls, "show") end,
  paneHide = function(id) panes[id].shown = false; table.insert(panes[id].calls, "hide") end,
  paneDelete = function(id) panes[id].deleted = true end,
  paneScrollBy = function(id, points)
    panes[id].scrolled = (panes[id].scrolled or 0) + points
    table.insert(panes[id].calls, "scroll")
    return true
  end,
}
local function newestPane() return panes[nextId] end

local lines = {}
local log = { e = function(line) lines[#lines + 1] = line end }

-- A timer that holds its one callback until fire.
local pending = nil
local timerLib = {
  doAfter = function(_, fn)
    local t = { fn = fn }
    function t:stop() self.stopped = true end
    pending = t
    return t
  end,
}
local function fire()
  local t = pending
  pending = nil
  if t and not t.stopped then t.fn() end
end

-- A kit whose layout answers one text element per node, scrolled by scrollY and clipped to the
-- viewport the way the real layout opens and closes its clip, with the content height the node
-- states.
local tokens = { pad = 10, colors = { subtext = { white = 0.5 } }, alpha = { fade = 0.5 },
  radius = { nested = 4 } }
local ui = {
  tokens = function() return tokens end,
  interior = function(w, h) return { x = 1, y = 1, w = w - 2, h = h - 2, radius = 11 } end,
  layout = function(node, rect, opts)
    local els = {}
    if opts and opts.viewport then
      els[#els + 1] = { type = "rectangle", action = "clip", frame = opts.viewport }
    end
    els[#els + 1] = { type = "text", text = node.str, frame = { x = rect.x,
      y = rect.y - ((opts and opts.scrollY) or 0), w = rect.w, h = node.h or 0 } }
    if opts and opts.viewport then els[#els + 1] = { type = "resetClip" } end
    return els, node.h or 0
  end,
}

-- The shared surface, a rounded fill and its border, the shape lib/panel.lua draws.
local function surface(w, h)
  return {
    { type = "rectangle", action = "fill", fillColor = { white = 0.1 },
      roundedRectRadii = { xRadius = 12, yRadius = 12 }, frame = { x = 0, y = 0, w = w, h = h } },
    { type = "rectangle", action = "stroke", strokeColor = { white = 0.3 }, strokeWidth = 1,
      roundedRectRadii = { xRadius = 11.5, yRadius = 11.5 },
      frame = { x = 0.5, y = 0.5, w = w - 1, h = h - 1 } },
  }
end
local function emptyState(w, h)
  return { { type = "text", text = "Nothing to preview", frame = { x = 0, y = h / 2, w = w, h = 16 } } }
end

local FRAME = { x = 500, y = 200, w = 300, h = 400 }

local function newPane(backend, spec)
  return DockedPane.new({ ui = ui, surface = surface, emptyState = emptyState, backend = backend,
    timer = timerLib }, spec)
end

-- The content list the pane last handed a backend's render, recorded on the way in, so the
-- comparison can see that the backend passes the very same table on to the library, with the
-- scroll argument a native backend is given and how many arguments the render was handed.
local rendered, renderedScroll, renderedArgs = nil, nil, nil
local function spied(factory)
  return function(frame)
    local backend = factory(frame)
    local render = backend.render
    backend.render = function(...)
      local surfaceEls, content, scroll = ...
      rendered, renderedScroll, renderedArgs = content, scroll, select("#", ...)
      return render(surfaceEls, content, scroll)
    end
    return backend
  end
end

-- Both panes over the same spec, one per backend.
local function pair(spec)
  return newPane(CanvasBackend.new({ canvas = canvasLib }), spec),
    newPane(spied(SwiftPane.factory(native, log)), spec)
end

--------------------------------------------------------------------------------
-- The comparison
--------------------------------------------------------------------------------

local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- The canvas got the surface and then the content, the library got the content alone, equal
-- to the canvas's element for element, and it is the very table the pane handed the backend, so
-- nothing was copied, dropped or added on the way. The two panes run their describer or painter
-- once each, so across the two the elements are equal rather than the same tables.
local function compare(label)
  local c, p = canvases[#canvases], newestPane()
  local surfaceN = #surface(FRAME.w, FRAME.h)
  check(label .. ", the canvas is handed the surface first",
    same({ c.els[1], c.els[2] }, surface(FRAME.w, FRAME.h)), true)
  check(label .. ", the library is handed the content alone", #p.els, #c.els - surfaceN)
  local equal = #p.els > 0
  for i, el in ipairs(p.els) do
    if not same(el, c.els[surfaceN + i]) then equal = false end
  end
  check(label .. ", equal to the canvas's content, element for element", equal, true)
  check(label .. ", and the very list the pane rendered", p.els, rendered)
  check(label .. ", at the surface's own corner", p.radius, 12)
  check(label .. ", both at the companion rect", c.at == FRAME and p.at == FRAME, true)
  check(label .. ", both shown", c.shown == true and p.shown == true, true)
  check(label .. ", in the same order of calls",
    (table.concat(c.calls, " "):gsub("replace", "draw"):gsub("frame", "place")), table.concat(p.calls, " "))
end

-- A describer and a painter that build fresh elements on every call, as real ones do.
local function describer(str, h)
  return function() return { str = str, h = h } end
end

local function painter(view)
  return {
    { type = "rectangle", action = "clip", frame = view.inner },
    { type = "segments", action = "stroke", strokeWidth = 2, strokeColor = { white = 1 },
      strokeCapStyle = "round", coordinates = { { x = 10, y = 20 }, { x = 40, y = 5 } } },
    { type = "image", image = "an hs.image", imageScaling = "scaleProportionally",
      imageAlignment = "topLeft", imageAlpha = 1, frame = { x = 10, y = 30, w = 32, h = 32 } },
    { type = "text", text = "painted", frame = { x = 10, y = 70 - view.scrollY, w = 200, h = 18 } },
    { type = "resetClip" },
  }, 0
end

--------------------------------------------------------------------------------
-- Cases
--------------------------------------------------------------------------------

-- The empty state.
do
  local a, b = pair({})
  a.dock(FRAME); b.dock(FRAME)
  a.clear(); b.clear()
  compare("empty")
end

-- A described pane, unscrolled.
do
  local a, b = pair({})
  a.dock(FRAME); b.dock(FRAME)
  a.show(describer("described", 50)); b.show(describer("described", 50))
  compare("described")
end

-- A painted pane, a painter answering every element type the panes draw.
do
  local a, b = pair({})
  a.dock(FRAME); b.dock(FRAME)
  a.draw(painter); b.draw(painter)
  compare("painted")
  check("painted, the native pane is handed every element type",
    #newestPane().els, 5)
end

-- The canvas pane, a described pane scrolled with its thumb through the scroll timer, exactly as
-- before the native scroll existed.
do
  local a = newPane(spied(CanvasBackend.new({ canvas = canvasLib })), { scroll = true, thumb = true })
  a.dock(FRAME)
  a.show(describer("long", 1000))
  check("canvas, rendered with the surface and the content alone", renderedArgs, 2)
  check("canvas, the pane moves", a.scrollBy(120), true)
  check("canvas, and waits for the timer to paint", pending ~= nil, true)
  fire()
  local els = canvases[#canvases].els
  check("canvas, the text is drawn scrolled", els[4].frame.y, 10 - 120)
  check("canvas, cut at the viewport", els[3].frame.h, 398)
  check("canvas, the thumb is the last element", els[#els].fillColor ~= nil, true)
  check("canvas, clamped at the overflow", a.scrollBy(10000), true)
  fire()
  check("canvas, the text drawn at the end", canvases[#canvases].els[4].frame.y, 10 - 620)
  check("canvas, and no further", a.scrollBy(10), false)
  check("canvas, the backend does not scroll natively",
    CanvasBackend.new({ canvas = canvasLib })(FRAME).scrollsNatively, nil)
end

-- The native pane, the same described pane handed over at full height and scrolled natively.
-- The pane is 400 high with a pad of 10, so the inner box is 380 and a 1000 point node overflows
-- by 620, the viewport inside the border is 398 and grows to 1018, and the whole is 1020.
do
  local b = newPane(spied(SwiftPane.factory(native, log)), { scroll = true, thumb = true })
  b.dock(FRAME)
  b.show(describer("long", 1000))
  local p = newestPane()
  check("native, the text is laid out unshifted", p.els[2].frame.y, 10)
  check("native, cut at the viewport grown by the overflow", p.els[1].frame.h, 398 + 620)
  check("native, with no thumb drawn in Lua", p.els[#p.els].type, "resetClip")
  check("native, the very list the pane rendered", p.els, rendered)
  check("native, told the full height", renderedScroll.height, 1020)
  check("native, and the pane's own", renderedScroll.visible, 400)
  check("native, a new content goes to the top", renderedScroll.reset, true)
  check("native, asked for its own thumb", renderedScroll.thumb, true)
  p.calls = {}
  check("native, scrollBy moves the native view", b.scrollBy(120), true)
  check("native, by those points", p.scrolled, 120)
  check("native, with no paint", table.concat(p.calls, " "), "scroll")
  check("native, and no timer", pending, nil)
  b.repaint()
  check("native, a repaint keeps its place", renderedScroll.reset, false)
  b.show(describer("long", 1000), { keepScroll = true })
  check("native, the same content kept keeps its place", renderedScroll.reset, false)
  b.dock(FRAME)
  check("native, a redock keeps its place", renderedScroll.reset, false)
  b.show(describer("other", 1000))
  check("native, new content goes back to the top", renderedScroll.reset, true)
  b.clear()
  check("native, the empty state is the pane's own height", renderedScroll.height, 400)
  check("native, an empty pane does not scroll", b.scrollBy(120), false)
end

-- A short native pane is its own height and does not scroll, and a pane without scroll is laid
-- out unscrolled however tall its content.
do
  local b = newPane(spied(SwiftPane.factory(native, log)), { scroll = true })
  b.dock(FRAME)
  b.show(describer("short", 100))
  check("native short, the pane's own height", renderedScroll.height, 400)
  check("native short, no thumb asked for", renderedScroll.thumb, false)
  check("native short, nothing to scroll", b.scrollBy(50), false)
  local c = newPane(spied(SwiftPane.factory(native, log)), {})
  c.dock(FRAME)
  c.show(describer("long", 1000))
  check("native unscrolled, the pane's own height", renderedScroll.height, 400)
  check("native unscrolled, cut at the viewport", newestPane().els[1].frame.h, 398)
end

-- A painter that cuts its body at the viewport, the way a pane with a fixed header does, and
-- reports how far the body overflows the room it has. The canvas pane hands it the offset, the
-- native one calls it again with the viewport grown by the overflow and no offset.
local function cutPainter(view)
  local body = 900
  return { { type = "text", text = "body", frame = { x = 10, y = 10 - view.scrollY, w = 200,
    h = view.viewport.h } } }, body - view.inner.h
end
do
  local a = newPane(spied(CanvasBackend.new({ canvas = canvasLib })), { scroll = true })
  a.dock(FRAME)
  a.draw(cutPainter)
  a.scrollBy(100)
  fire()
  local els = canvases[#canvases].els
  check("canvas painter, drawn at the offset", els[3].frame.y, 10 - 100)
  check("canvas painter, cut at the viewport", els[3].frame.h, 398)
  local b = newPane(spied(SwiftPane.factory(native, log)), { scroll = true })
  b.dock(FRAME)
  b.draw(cutPainter)
  local p = newestPane()
  check("native painter, unshifted", p.els[1].frame.y, 10)
  check("native painter, handed the grown viewport", p.els[1].frame.h, 398 + 520)
  check("native painter, told the full height", renderedScroll.height, 400 + 520)
  check("native painter, scrolled natively", b.scrollBy(100), true)
  check("native painter, by the library", p.scrolled, 100)
  b.draw(cutPainter, { keepScroll = true })
  check("native painter, the same content kept keeps its place", renderedScroll.reset, false)
end

-- Hide, redock and destroy reach both backends.
do
  local a, b = pair({})
  a.dock(FRAME); b.dock(FRAME)
  a.clear(); b.clear()
  local c, p = canvases[#canvases], newestPane()
  a.hide(); b.hide()
  check("hide takes both down", c.shown == false and p.shown == false, true)
  a.repaint(); b.repaint()
  check("a late repaint after hide brings neither back", c.shown == false and p.shown == false, true)
  a.dock(FRAME); b.dock(FRAME)
  check("a redock brings both back", c.shown == true and p.shown == true, true)
  a.destroy(); b.destroy()
  check("destroy deletes the canvas", c.deleted, true)
  check("destroy deletes the native pane", p.deleted, true)
end

-- The native pane is placed on the very rect it is docked on, every time, since the library
-- matches it to the chooser panel whose reported companion is that rect and draws it into that
-- panel's window, and falls back to the pane's own window when none matches. A redock at a moved
-- companion is placed there before it draws, so the match is made against the rect now current.
do
  local _, b = pair({})
  b.dock(FRAME)
  b.clear()
  local p = newestPane()
  local moved = { x = 520, y = 200, w = 280, h = 400 }
  p.calls = {}
  b.dock(moved)
  check("a redock places the native pane on the new companion", p.at, moved)
  check("and places it before it draws and shows", table.concat(p.calls, " "), "place draw show")
end

-- What the library could not draw is said once per name.
do
  local _, b = pair({})
  b.dock(FRAME)
  refuse = { "oval", "rectangle.withShadow" }
  b.draw(painter)
  b.repaint()
  b.repaint()
  refuse = {}
  check("each refused name is said once", #lines, 2)
  check("naming it", lines[1], "Olm swift pane, an element it cannot draw was left out, oval")
end

-- The corner the glass takes, read off whichever surface element carries one.
check("the radius of a fill", SwiftPane.radiusOf(surface(10, 10)), 12)
check("the radius of a border alone, widened by half its stroke",
  SwiftPane.radiusOf({ surface(10, 10)[2] }), 12)
check("no surface, a square pane", SwiftPane.radiusOf({}), 0)

if failed then
  print("panebackends, FAILED")
  os.exit(1)
end
print("panebackends, every case passed")
