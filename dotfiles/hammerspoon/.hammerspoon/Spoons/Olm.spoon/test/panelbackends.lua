-- CanvasPanel's two drawing backends, in plain Lua over a stub canvas and a stub library.
--
-- Pins that lib/panel.lua drawing through lib/dockedpane/canvas.lua makes exactly the hs.canvas
-- calls it made before the backend existed, and that the native backend is handed the very same
-- element lists. The reference is the canvas code lib/panel.lua's show held until 2026-10-28,
-- copied below as it was, driven over the same recording canvas stub as the panel. Three panels,
-- a centred sheet with its own padding, a centred toast whose content takes a click, and a panel
-- docked below an anchor. For each, the canvas gets the same frame, level, mouse settings,
-- elements and shown state from both, and a click on it reaches the content the same way. Then
-- the same panel over lib/chooser/providers/swift/pane.lua is handed the content list the canvas
-- paints over its surface, element for element, at the surface's corner radius, in a panel window
-- at the panel's level with the content's click handler, and hide and isShowing reach both.
--
-- Run it.
--   lua test/panelbackends.lua

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

local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

--------------------------------------------------------------------------------
-- Stubs
--------------------------------------------------------------------------------

-- A canvas that records what it is told, in order, newest canvas last.
local canvases = {}
local LEVELS = { floating = 3, popUpMenu = 101 }
local canvasLib = {
  windowLevels = LEVELS,
  new = function(frame)
    local c = { made = frame, calls = {}, shown = false }
    local function note(s) c.calls[#c.calls + 1] = s end
    function c:level(l) self.lvl = l; note("level") end
    function c:clickActivating(v) self.activating = v; note("clickActivating") end
    function c:canvasMouseEvents(down, up) self.mouse = { down, up }; note("canvasMouseEvents") end
    function c:mouseCallback(fn) self.callback = fn; note("mouseCallback") end
    function c:frame(f) self.at = f; note("frame") end
    function c:replaceElements(els) self.els = els; note("replace") end
    function c:show() self.shown = true; note("show") end
    function c:hide() self.shown = false; note("hide") end
    function c:isShowing() return self.shown end
    function c:delete() self.deleted = true end
    canvases[#canvases + 1] = c
    return c
  end,
}

local SCREEN = { x = 0, y = 25, w = 1440, h = 875 }
hs = {
  canvas = canvasLib,
  screen = {
    mainScreen = function() return { frame = function() return SCREEN end } end,
    primaryScreen = function() return { frame = function() return SCREEN end } end,
  },
  timer = { doAfter = function() return { stop = function() end } end,
            doEvery = function() return { stop = function() end } end },
}

-- The Swift library's pane functions, recording what each is told.
local natives, nextId = {}, 70
local native = {
  paneNew = function(opts)
    nextId = nextId + 1
    natives[nextId] = { id = nextId, opts = opts, calls = {}, shown = false }
    return nextId
  end,
  panePlace = function(id, rect) natives[id].at = rect; table.insert(natives[id].calls, "place") end,
  paneDraw = function(id, radius, els, scroll)
    natives[id].radius, natives[id].els, natives[id].scroll = radius, els, scroll
    table.insert(natives[id].calls, "draw")
    return {}
  end,
  paneShow = function(id) natives[id].shown = true; table.insert(natives[id].calls, "show") end,
  paneHide = function(id) natives[id].shown = false; table.insert(natives[id].calls, "hide") end,
  paneIsVisible = function(id) return natives[id].shown end,
  paneDelete = function(id) natives[id].deleted = true end,
}

local ui = {
  tokens = function() return { pad = 14 } end,
  half = function() return "dark" end,
}
local STYLE = { cornerRadius = 12, borderWidth = 1,
  dark = { bg = "#1e1e2e", border = "#45475a" }, light = { bg = "#eff1f5", border = "#bcc0cc" } }

local function freshPanel()
  local P = dofile(spoon .. "lib/panel.lua")
  P.configure({ surface = STYLE, ui = ui })
  return P
end

local CanvasBackend = dofile(spoon .. "lib/dockedpane/canvas.lua")
-- The placements and alignments by name, read off the module rather than written as strings.
local NAMES = dofile(spoon .. "lib/panel.lua")
local CENTER, BELOW = NAMES.placements.center, NAMES.placements.below
local SwiftPane = dofile(spoon .. "lib/chooser/providers/swift/pane.lua")

--------------------------------------------------------------------------------
-- The reference, lib/panel.lua's canvas drawing as it was before the backend
--------------------------------------------------------------------------------

local function shifted(el, dx, dy)
  local copy = {}
  for k, v in pairs(el) do copy[k] = v end
  if el.frame then
    copy.frame = { x = (el.frame.x or 0) + dx, y = (el.frame.y or 0) + dy,
                   w = el.frame.w, h = el.frame.h }
  end
  return copy
end

-- The old Panel:show from the line after _layout, over the panel's own layout and surface.
local function referenceShow(P, panel, anchor)
  if not anchor and panel.config.placement ~= "center" then return end
  local frame, contentW, contentH, padX, padY = panel:_layout(anchor)
  local els = {}
  for _, el in ipairs(P.surfaceElements(frame.w, frame.h, panel.config.style)) do
    els[#els + 1] = el
  end
  for _, el in ipairs(panel.config.content.draw(contentW, contentH) or {}) do
    els[#els + 1] = shifted(el, padX, padY)
  end
  if not panel.refCanvas then
    panel.refCanvas = hs.canvas.new(frame)
    panel.refCanvas:level(panel.config.level or hs.canvas.windowLevels.popUpMenu)
    local onClick = panel.config.content.onClick
    if type(onClick) == "function" then
      panel.refCanvas:canvasMouseEvents(false, true)
      panel.refCanvas:mouseCallback(function(_, event, id)
        if event == "mouseUp" and id then onClick(id) end
      end)
    end
  else
    panel.refCanvas:frame(frame)
  end
  panel.refCanvas:replaceElements(els)
  panel.refCanvas:show()
end

--------------------------------------------------------------------------------
-- Contents, shaped like the real ones
--------------------------------------------------------------------------------

-- A sheet, a grid of icons and labels with a heading, fixed size.
local function sheetContent()
  return {
    preferredSize = function() return { w = 860, h = 420 } end,
    draw = function(w)
      return {
        { type = "text", text = "WINDOW", textSize = 13, frame = { x = 0, y = 0, w = w, h = 18 } },
        { type = "image", image = "an hs.image", imageScaling = "scaleProportionally",
          frame = { x = 0, y = 30, w = 32, h = 32 } },
        { type = "text", text = "Safari", frame = { x = 42, y = 36, w = 170, h = 18 } },
      }
    end,
  }
end

-- A toast with a Dismiss chip, the report toast's shape, telling clicks to onDismiss.
local function toastContent(log)
  return {
    preferredSize = function() return { w = 320, h = 120 } end,
    onClick = function(id) log[#log + 1] = id end,
    draw = function(w, h)
      return {
        { type = "text", text = "Not open", frame = { x = 0, y = 0, w = w, h = 20 } },
        { type = "rectangle", action = "fill", fillColor = { white = 0.3 },
          roundedRectRadii = { xRadius = 6, yRadius = 6 }, id = "dismiss", trackMouseUp = true,
          frame = { x = w - 80, y = h - 24, w = 80, h = 24 } },
        { type = "text", text = "Dismiss", id = "dismiss", trackMouseUp = true,
          frame = { x = w - 70, y = h - 20, w = 60, h = 16 } },
      }
    end,
  }
end

-- A panel docked below an anchor, sized along its own axis by its content.
local function dockedContent()
  return {
    preferredSize = function(availW) return { w = availW, h = 40 } end,
    draw = function(w)
      return { { type = "text", text = "hint", frame = { x = 0, y = 0, w = w, h = 18 } } }
    end,
  }
end

local ANCHOR = { x = 300, y = 200, w = 640, h = 400 }

local cases = {
  { name = "sheet", config = function() return { placement = CENTER, padX = 28, padY = 28,
      content = sheetContent() } end },
  { name = "toast", clicks = true, config = function(log) return { placement = CENTER,
      content = toastContent(log) } end },
  { name = "docked", anchor = ANCHOR, config = function() return { placement = BELOW, gap = 8,
      align = NAMES.aligns.center, breadth = 480, content = dockedContent() } end },
}

--------------------------------------------------------------------------------
-- The canvas backend against the reference
--------------------------------------------------------------------------------

for _, case in ipairs(cases) do
  local label = case.name
  -- The reference, the old show over its own panel instance.
  local RefP = freshPanel()
  local refLog = {}
  local refPanel = RefP.new(case.config(refLog))
  referenceShow(RefP, refPanel, case.anchor)
  referenceShow(RefP, refPanel, case.anchor)
  local ref = refPanel.refCanvas

  -- The panel today, over the canvas backend.
  local P = freshPanel()
  P.configure({ backend = CanvasBackend.new({ canvas = canvasLib }) })
  local log = {}
  local panel = P.new(case.config(log))
  panel:show(case.anchor)
  panel:show(case.anchor)
  local now = canvases[#canvases]

  check(label .. ", the canvas is made at the same frame", same(now.made, ref.made), true)
  check(label .. ", at the same level", now.lvl, ref.lvl)
  check(label .. ", at popUpMenu", now.lvl, LEVELS.popUpMenu)
  check(label .. ", click activation left as it was", now.activating, ref.activating)
  check(label .. ", the same mouse events", same(now.mouse, ref.mouse), true)
  check(label .. ", a mouse callback exactly when the reference has one",
    now.callback ~= nil, ref.callback ~= nil)
  check(label .. ", at the same frame", same(now.at or now.made, ref.at or ref.made), true)
  check(label .. ", the very same elements", same(now.els, ref.els), true)
  check(label .. ", shown", now.shown and ref.shown, true)
  check(label .. ", isShowing", panel:isShowing(), true)
  if case.clicks then
    ref.callback(ref, "mouseUp", "dismiss")
    now.callback(now, "mouseUp", "dismiss")
    now.callback(now, "mouseDown", "dismiss")
    check(label .. ", a click reaches the content as before", table.concat(log, " "),
      table.concat(refLog, " "))
  end
  panel:hide()
  check(label .. ", hide takes it down", now.shown, false)
  check(label .. ", and isShowing says so", panel:isShowing(), false)
end

--------------------------------------------------------------------------------
-- The native backend is handed the same element lists
--------------------------------------------------------------------------------

for _, case in ipairs(cases) do
  local label = "native " .. case.name
  local P = freshPanel()
  P.configure({ backend = CanvasBackend.new({ canvas = canvasLib }) })
  local panel = P.new(case.config({}))
  panel:show(case.anchor)
  local c = canvases[#canvases]

  local NP = freshPanel()
  NP.configure({ backend = SwiftPane.factory(native, nil) })
  local log = {}
  local npanel = NP.new(case.config(log))
  npanel:show(case.anchor)
  local n = natives[nextId]
  local surfaceN = #P.surfaceElements(c.made.w, c.made.h)

  check(label .. ", made as a panel window", n.opts and n.opts.panel, true)
  check(label .. ", at the panel's level", n.opts.level, LEVELS.popUpMenu)
  check(label .. ", with the click handler exactly when the content takes a click",
    n.opts.onClick ~= nil, case.clicks == true)
  check(label .. ", placed on the canvas's frame", same(n.at, c.at), true)
  check(label .. ", handed the content alone", #n.els, #c.els - surfaceN)
  local equal = #n.els > 0
  for i, el in ipairs(n.els) do
    if not same(el, c.els[surfaceN + i]) then equal = false end
  end
  check(label .. ", equal to the canvas's content, element for element", equal, true)
  check(label .. ", at the surface's corner", n.radius, STYLE.cornerRadius)
  check(label .. ", with no scroll", n.scroll, nil)
  check(label .. ", placed, drawn and shown in order", table.concat(n.calls, " "), "place draw show")
  check(label .. ", isShowing", npanel:isShowing(), true)
  if case.clicks then
    n.opts.onClick("dismiss")
    check(label .. ", a click reaches the content", log[1], "dismiss")
  end
  npanel:show(case.anchor)
  check(label .. ", a second show orders it up again", table.concat(n.calls, " "),
    "place draw show place draw show")
  npanel:hide()
  check(label .. ", hide takes it down", n.shown, false)
  check(label .. ", and isShowing says so", npanel:isShowing(), false)
end

-- A panel with no backend configured draws nothing rather than failing.
do
  local P = freshPanel()
  local before = #canvases
  local panel = P.new({ placement = CENTER, content = sheetContent() })
  panel:show()
  check("no backend, nothing is drawn", #canvases, before)
  check("no backend, not showing", panel:isShowing(), false)
end

-- A docked pane still calls the factory with no window, so its canvas floats and never activates.
do
  local backend = CanvasBackend.new({ canvas = canvasLib })({ x = 0, y = 0, w = 10, h = 10 })
  local c = canvases[#canvases]
  check("a pane's canvas floats", c.lvl, LEVELS.floating)
  check("a pane's canvas never activates", c.activating, false)
  check("a pane's canvas takes no mouse", c.callback, nil)
  check("and answers isShowing", backend.isShowing(), false)
end

if failed then
  print("panelbackends, FAILED")
  os.exit(1)
end
print("panelbackends, every case passed")
