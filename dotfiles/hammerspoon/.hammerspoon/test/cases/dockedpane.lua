-- Unit case for the shared docked companion pane, Spoons/Olm.spoon/lib/dockedpane.lua. The runner
-- reaches this file with a dofile call carrying an absolute path, so it locates itself through
-- debug.getinfo and derives every module path from there. It also runs under plain lua, since
-- the pane takes its backend and its timer from deps and nothing here touches Hammerspoon.
--
-- The canvas is a stub that records what it was told, the timer a stub that holds its callback
-- until the case fires it, and the kit a fake whose layout answers one element per node carrying
-- the node, the rect and the scroll, with a content height the node states. That is enough to
-- see the whole lifecycle, the dock, the empty state, content, the scroll and its clamp, the
-- hide guard, the redock and the destroy, without the real layout engine, which has cases of its
-- own.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local olm = caseDir .. "/../../Spoons/Olm.spoon/"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local chunk, err = loadfile(olm .. "lib/dockedpane.lua")
if not chunk then error("could not load lib/dockedpane.lua, " .. tostring(err)) end
local DockedPane = chunk()

-- The canvas backend the root hands every pane while the swift chooser does not serve, built
-- over the stub canvas below, so this case still sees each canvas call the pane causes.
local backendChunk, backendErr = loadfile(olm .. "lib/dockedpane/canvas.lua")
if not backendChunk then error("could not load lib/dockedpane/canvas.lua, " .. tostring(backendErr)) end
local CanvasBackend = backendChunk()

-- Every canvas the stub made, newest last.
local canvases = {}
local canvasLib = {
  windowLevels = { floating = "floating" },
  new = function(frame)
    local c = { made = frame, shown = false, deleted = false, els = nil, frameSet = nil }
    function c:level(l) self.lvl = l end
    function c:clickActivating(v) self.activating = v end
    function c:frame(f) self.frameSet = f end
    function c:replaceElements(els) self.els = els end
    function c:show() self.shown = true end
    function c:hide() self.shown = false end
    function c:delete() self.deleted = true self.shown = false end
    canvases[#canvases + 1] = c
    return c
  end,
}

-- The one pending scroll paint, fired by hand.
local pending = nil
local timerLib = {
  doAfter = function(_, fn)
    local t = { fn = fn, stopped = false }
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

local tokens = { pad = 10, colors = { subtext = { white = 0.5 } }, alpha = { fade = 0.5 },
  radius = { nested = 4 } }
local ui = {
  tokens = function() return tokens end,
  interior = function(w, h) return { x = 1, y = 1, w = w - 2, h = h - 2 } end,
  layout = function(node, rect, opts)
    return { { type = "text", node = node, rect = rect, scrollY = opts and opts.scrollY } }, node.h or 0
  end,
}
local surface = function(w, h) return { { type = "surface", w = w, h = h } } end
local emptyCalls = {}
local emptyState = function(w, h, opts)
  emptyCalls[#emptyCalls + 1] = { w = w, h = h, opts = opts }
  return { { type = "empty", frame = { x = 0, y = 0, w = w, h = h }, text = opts and opts.text } }
end

local deps = { ui = ui, surface = surface, emptyState = emptyState,
  backend = CanvasBackend.new({ canvas = canvasLib }), timer = timerLib }

local function kinds(els)
  local out = {}
  for _, el in ipairs(els or {}) do out[#out + 1] = el.type end
  return table.concat(out, ",")
end

local FRAME = { x = 500, y = 100, w = 300, h = 200 }

--------------------------------------------------------------------------------
-- enabled, docking and the empty state
--------------------------------------------------------------------------------

local pane = DockedPane.new(deps, { scroll = true })
check("a pane with a surface and a kit is enabled", pane.isEnabled())
check("a pane without a kit is not", not DockedPane.new({ surface = surface }).isEnabled())
check("there is no inner rect before the first dock", pane.inner() == nil)

pane.dock(FRAME)
check("a dock with nothing to show makes no canvas", #canvases == 0)
local inner = pane.inner()
check("the inner rect is the frame less the pad, in the canvas's own coordinates",
  inner.x == 10 and inner.y == 10 and inner.w == 280 and inner.h == 180)

pane.clear()
local c = canvases[1]
check("clear paints one canvas at the companion rect", #canvases == 1 and c.frameSet == FRAME and c.shown)
check("the canvas floats and a click on it activates nothing",
  c.lvl == "floating" and c.activating == false)
check("the empty state is drawn over the surface", kinds(c.els) == "surface,empty")
check("the empty state is laid into the inner box",
  c.els[2].frame.x == 10 and c.els[2].frame.y == 10 and c.els[2].frame.w == 280)
check("with no emptyText the shared routine is called with no options",
  emptyCalls[#emptyCalls].opts == nil)

local guided = DockedPane.new(deps, { emptyText = "Highlight something" })
guided.dock(FRAME)
guided.clear()
check("a pane's own emptyText reaches the shared routine",
  emptyCalls[#emptyCalls].opts and emptyCalls[#emptyCalls].opts.text == "Highlight something")
guided.destroy()

--------------------------------------------------------------------------------
-- content, the scroll and its clamp
--------------------------------------------------------------------------------

local tall = { kind = "stack", h = 500 }
local seen = nil
local before = #canvases
pane.show(function(kit, view)
  seen = view
  return tall
end)
check("show reuses the one canvas", #canvases == before)
check("content is drawn over the surface", kinds(c.els) == "surface,text")
check("the describer is handed the kit's view, the frame, the inner box and the viewport",
  seen.frame == FRAME and seen.inner.w == 280 and seen.viewport.x == 1 and seen.scrollY == 0)
check("the node is laid out in the inner box", c.els[2].rect.x == 10 and c.els[2].rect.h == 180)

check("a scroll inside the overflow moves", pane.scrollBy(100) == true)
check("the paint waits for the next frame", c.els[2].scrollY == 0 and pending ~= nil)
pane.scrollBy(50)
fire()
check("several scrolls before the frame cost one paint at their sum", c.els[2].scrollY == 150)
check("a scroll past the overflow stops at it", pane.scrollBy(10000) == true)
fire()
check("the overflow is the content less the inner height", c.els[2].scrollY == 320)
check("a scroll at the end moves nothing", pane.scrollBy(10) == false)

pane.show(function() return tall end, { keepScroll = true })
check("keepScroll repaints where the person left it", c.els[2].scrollY == 320)
pane.show(function() return { kind = "stack", h = 250 } end, { keepScroll = true })
check("content that shrinks underneath clamps the offset", c.els[2].scrollY == 70)
pane.show(function() return tall end)
check("a new show starts at the top", c.els[2].scrollY == 0)

local short = DockedPane.new(deps, {})
short.dock(FRAME)
short.show(function() return tall end)
check("a pane that does not scroll lays out with no offset",
  canvases[#canvases].els[2].scrollY == nil)
check("and refuses a scroll", short.scrollBy(50) == false)
short.destroy()

local thumbed = DockedPane.new(deps, { scroll = true, thumb = true })
thumbed.dock(FRAME)
thumbed.show(function() return tall end)
local tc = canvases[#canvases]
check("a thumb is drawn while there is more than fits", kinds(tc.els) == "surface,text,rectangle")
check("the thumb sits at the right edge, sized to the share that fits",
  tc.els[3].frame.x == 293 and math.abs(tc.els[3].frame.h - 180 * 180 / 500) < 0.001)
thumbed.show(function() return { kind = "stack", h = 100 } end)
check("no thumb when everything fits", kinds(tc.els) == "surface,text")
thumbed.destroy()

--------------------------------------------------------------------------------
-- a painter
--------------------------------------------------------------------------------

local calls = {}
pane.draw(function(view)
  calls[#calls + 1] = view.scrollY
  return { { type = "header" }, { type = "body", scrollY = view.scrollY } }, 40
end)
check("a painter's elements are drawn over the surface", kinds(c.els) == "surface,header,body")
pane.scrollBy(1000)
fire()
check("a painter's overflow clamps the scroll, and it is asked again at the clamped offset",
  c.els[3].scrollY == 40 and calls[#calls] == 40)

--------------------------------------------------------------------------------
-- hide, the redock and destroy
--------------------------------------------------------------------------------

pane.show(function() return tall end)
pane.scrollBy(60)
pane.hide()
check("hide takes the canvas down without deleting it", not c.shown and not c.deleted)
check("hide drops the pending scroll paint", pending == nil or pending.stopped)
pane.repaint()
pane.clear()
check("nothing late brings a hidden pane back up", not c.shown)
pane.show(function() return tall end)
check("not even a fresh show", not c.shown)

local moved = { x = 520, y = 120, w = 300, h = 200 }
pane.dock(moved)
check("a redock shows the pane again with what is current", c.shown and c.frameSet == moved
  and kinds(c.els) == "surface,text")

pane.clear()
pane.hide()
pane.dock(FRAME)
check("a redock after a clear repaints the empty state", c.shown and kinds(c.els) == "surface,empty")

pane.destroy()
check("destroy deletes the canvas", c.deleted and not c.shown)
check("and forgets the frame", pane.inner() == nil)
before = #canvases
pane.show(function() return tall end)
check("a show after destroy waits for a dock", #canvases == before)
pane.dock(FRAME)
local fresh = canvases[#canvases]
check("the next dock makes a fresh canvas", fresh ~= c and not fresh.deleted and fresh.shown)
pane.destroy()
