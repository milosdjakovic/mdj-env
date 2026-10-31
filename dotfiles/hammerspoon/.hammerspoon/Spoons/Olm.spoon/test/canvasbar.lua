-- The canvas chooser's bar, two floating groups, in plain Lua over the real UI kit and stubs for
-- the few hs calls the kit and the view make.
--
-- Pins that lib/chooser/providers/default/bar.lua lays the groups out by the numbers swift's
-- view.lua hands Swift, the keys group the bar pad in from the left and the actions group the
-- bar pad in from the right, each as tall as footer.lua's height at the top of the footer rect,
-- the inner padding inside it, the background fill outlined in the border role at the border
-- stroke with its corner less half the stroke, the words in the body role, the icon at the hint
-- size, and that the entries' spans cover the actions group edge to edge in order.
--
-- Then that lib/chooser/providers/default/canvas.lua draws the list on down behind the bar
-- without moving the engine's scroll, runs the divider the full height of the window, and
-- answers the pointer the way swift does, a press on the keys group toggling the key panel, a
-- press and release on an entry running its action through footerAction, a press between the
-- groups reaching the row behind the bar, and the keys group and each entry lighting under the
-- pointer.
--
-- How it looks is seen live, not here.
--
-- Run it.
--   lua test/canvasbar.lua

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

--------------------------------------------------------------------------------
-- Stubs, a measurer of eight points a character and a canvas that keeps what it is handed
--------------------------------------------------------------------------------

local surfaceCanvas = { level = function() end, clickActivating = function() end,
  frame = function() end, isShowing = function() return true end,
  replaceElements = function(self, els) self.els = els end, show = function() end,
  hide = function() end }

hs = {
  host = { interfaceStyle = function() return nil end },
  drawing = { getTextDrawingSize = function(s) return { w = 8 * #s, h = 20 } end },
  styledtext = {
    new = function(s, attrs) return { str = s, attrs = attrs } end,
    fontInfo = function() return { capHeight = 10, ascender = 14, descender = -4, leading = 0 } end,
  },
  canvas = { new = function() return surfaceCanvas end, windowLevels = { popUpMenu = "popUpMenu" } },
}

local ui = dofile(spoon .. "lib/ui/init.lua")
local T = ui.tokens()
local footerLib = dofile(spoon .. "lib/chooser/providers/default/footer.lua")
local barLib = dofile(spoon .. "lib/chooser/providers/default/bar.lua")
local listModel = dofile(spoon .. "lib/chooser/providers/default/list/model.lua")

local function filled(els, color)
  local out = {}
  for _, el in ipairs(els) do
    if el.type == "rectangle" and el.action == "fill" and el.fillColor == color then out[#out + 1] = el end
  end
  return out
end

local function strokes(els)
  local out = {}
  for _, el in ipairs(els) do
    if el.type == "rectangle" and el.action == "stroke" then out[#out + 1] = el end
  end
  return out
end

local function texts(els)
  local out = {}
  for _, el in ipairs(els) do
    if el.type == "text" then out[#out + 1] = el end
  end
  return out
end

--------------------------------------------------------------------------------
-- bar.lua alone
--------------------------------------------------------------------------------

local model = {
  keysChord = "⌘?",
  right = {
    { label = "Open", chord = "↩", action = "primary" },
    { label = "Reveal", chord = "⌘↩", action = "secondary" },
    { label = "Actions", chord = "⌘K", action = "actions" },
  },
}
local rect = { x = 0, y = 400, w = 900, h = footerLib.height(T) + T.pad }
local m = barLib.metrics(T)
check("the group height is footer.lua's", m.height, footerLib.height(T))
check("the bar pad is the kit's pad", m.pad, T.pad)
check("the inner padding is the kit's", m.inner, T.inner)

local els, hits = barLib.elements(ui, T, model, rect, { radius = 9 })
local keys, actions = hits.keys, hits.actions
check("the keys group stands the bar pad from the left", keys.x, rect.x + T.pad)
check("at the top of the footer rect", keys.y, rect.y)
check("as tall as the bar's row", keys.h, footerLib.height(T))
-- The ? glyph and the chord, each eight points a character, the small step between them.
check("as wide as its parts, the small gap and the inner padding twice",
  keys.w, 8 * #"?" + T.space.s + 8 * #"⌘?" + 2 * T.inner)
check("the actions group stands the bar pad from the right", actions.x + actions.w, rect.x + rect.w - T.pad)
check("at the same height", actions.y, rect.y)
local entriesW = 0
for _, r in ipairs(model.right) do entriesW = entriesW + 8 * #r.label + T.space.s + 8 * #r.chord end
check("as wide as its entries, the wide gap between them and the inner padding twice",
  actions.w, entriesW + 2 * T.space.l + 2 * T.inner)

local backs = filled(els, T.colors.background)
check("both groups are filled with the background role", #backs, 2)
check("at the corner handed in", backs[1].roundedRectRadii.xRadius, 9)
local outlines = strokes(els)
check("both groups are outlined", #outlines, 2)
check("in the border role", outlines[1].strokeColor, T.colors.border)
check("at the border stroke", outlines[1].strokeWidth, T.stroke.border)
check("drawn inside the shape", outlines[1].frame.x, keys.x + T.stroke.border / 2)
check("its corner less half the stroke", outlines[1].roundedRectRadii.xRadius, 9 - T.stroke.border / 2)
check("nothing lit at rest", #filled(els, T.colors.highlight), 0)
local words = texts(els)
check("every word and chord is drawn", #words, 2 + 2 * #model.right)
local allBody = true
for _, t in ipairs(words) do
  if t.text.attrs.font.size ~= T.text.body.size or t.text.attrs.font.name ~= T.text.body.font then allBody = false end
end
check("all in the body role", allBody, true)

check("one span per entry", #hits.entries, 3)
check("the first span starts at the group's edge", hits.entries[1].rect.x, actions.x)
check("the last ends at its other edge", hits.entries[3].rect.x + hits.entries[3].rect.w, actions.x + actions.w)
check("the spans meet", hits.entries[1].rect.x + hits.entries[1].rect.w, hits.entries[2].rect.x)
check("each names its action", hits.entries[2].action, "secondary")
-- The second entry's label starts after the first entry, the inner padding and the wide gap,
-- and its span half the wide gap before that.
check("a middle span starts half the wide gap before its label",
  hits.entries[2].rect.x, actions.x + T.inner + 8 * #"Open" + T.space.s + 8 * #"↩" + T.space.l / 2)

els = barLib.elements(ui, T, model, rect, { radius = 9, keysLit = true, hover = 2 })
local lit = filled(els, T.colors.highlight)
check("a lit keys group and a hovered entry sit on the highlight", #lit, 2)
check("the hovered entry lights across its span", lit[2].frame.x, hits.entries[2].rect.x)
check("and that span's width", lit[2].frame.w, hits.entries[2].rect.w)

local open = { keysChord = model.keysChord, right = model.right, panelOpen = true }
els = barLib.elements(ui, T, open, rect, { radius = 9 })
check("the actions group lights while the action panel is open", #filled(els, T.colors.highlight), 1)

local image = io.stdout
els, hits = barLib.elements(ui, T, { right = {} }, rect, { radius = 9, keysImage = image })
local pictures = {}
for _, el in ipairs(els) do if el.type == "image" then pictures[#pictures + 1] = el end end
check("the keyboard icon is drawn", #pictures, 1)
check("at the hint size", pictures[1].frame.w, T.icon.hint)
check("centred in the group", pictures[1].frame.y, rect.y + (footerLib.height(T) - T.icon.hint) / 2)
check("no right side, no actions group", hits.actions, nil)
check("and no entries", #hits.entries, 0)

--------------------------------------------------------------------------------
-- The canvas view drawing the bar and the list behind it
--------------------------------------------------------------------------------

local Canvas = dofile(spoon .. "lib/chooser/providers/default/canvas.lua")
-- The interior is the whole window, so nothing cuts the rows short of the bottom edge.
Canvas.configure({ ui = ui, panel = {
  surfaceElements = function() return {} end,
  surfaceInterior = function(w, h) return { x = 0, y = 0, w = w, h = h } end,
} })

local rowH, rowCount = 40, 5
local rows = {}
for i = 1, 12 do rows[i] = { title = "row " .. i } end
local footerH = footerLib.height(T) + T.pad
local canvasRect = { x = 100, y = 100, w = 600, h = 60 + rowH * rowCount + footerH }
local listRect = { x = 110, y = 160, w = 580, h = rowH * rowCount }
local footerRect = { x = 100, y = listRect.y + listRect.h, w = 600, h = footerH }
local scene = {
  bare = true,
  tokens = T,
  layout = { marginX = 10 },
  type = { fieldFont = T.text.title.font, fieldSize = T.text.title.size },
  drawLayout = { rowH = rowH, rowCount = rowCount, font = T.text.body.font, textSize = T.text.body.size,
    textLine = T.text.body.lineHeight, subFont = T.text.caption.font, subSize = T.text.caption.size,
    subLine = T.text.caption.lineHeight, numFont = T.text.body.font, numSize = T.text.body.size,
    showRowNumbers = false },
  rects = { canvas = canvasRect, list = listRect, footer = footerRect },
  footer = model,
}
scene.list = listModel.newState(rows, { rowH = rowH, rowCount = rowCount })

local calls = {}
local engine = {
  scene = function() return scene end,
  isActive = function() return false end,
  toggleKeys = function() calls[#calls + 1] = "toggleKeys" end,
  footerAction = function(_, name) calls[#calls + 1] = "footerAction " .. name end,
  chooseIndex = function(_, i) calls[#calls + 1] = "choose " .. i end,
  highlightIndex = function(_, i) calls[#calls + 1] = "highlight " .. i end,
  rightClickIndex = function() end,
  hide = function() calls[#calls + 1] = "hide" end,
}
local view = Canvas.new(engine)
view:restyle()
view:place(scene.rects)
view:redraw()

local function rowTitles(drawn)
  local n = 0
  for _, el in ipairs(drawn) do
    if el.type == "text" and type(el.text) == "string" and el.text:match("^row ") then n = n + 1 end
  end
  return n
end
-- Five rows in the viewport and the bar's height, two rows of it, past them.
check("the list runs on behind the bar", rowTitles(surfaceCanvas.els), rowCount + math.ceil(footerH / rowH))
check("without moving the engine's scroll", scene.list.scrollTop, 0)
check("or its furthest scroll", listModel.maxScrollTop(scene.list), (12 - rowCount) * rowH)
local clip
for _, el in ipairs(surfaceCanvas.els) do
  if el.type == "rectangle" and el.action == "clip" then clip = el; break end
end
check("the rows are cut at the bottom of the window", clip.frame.y + clip.frame.h, canvasRect.h)

local barHits = view._barHits
check("the keys group is kept in screen points", barHits.keys.x, canvasRect.x + T.pad)
check("so is the actions group", barHits.actions.x + barHits.actions.w, canvasRect.x + canvasRect.w - T.pad)
check("the groups are drawn after the rows", (function()
  local lastRow, firstGroup = 0, nil
  for i, el in ipairs(surfaceCanvas.els) do
    if el.type == "text" and type(el.text) == "string" and el.text:match("^row ") then lastRow = i end
    if not firstGroup and el.type == "rectangle" and el.fillColor == T.colors.background then firstGroup = i end
  end
  return firstGroup ~= nil and firstGroup > lastRow
end)(), true)

local function centre(r) return { x = r.x + r.w / 2, y = r.y + r.h / 2 } end

calls = {}
check("a press on the keys group is claimed", view:_onMouseDown(centre(barHits.keys), "left"), true)
check("and toggles the key panel", calls[1], "toggleKeys")

calls = {}
local second = centre(barHits.entries[2].rect)
view:_onMouseDown(second, "left")
check("a press on an entry runs nothing yet", #calls, 0)
view:_onMouseUp(second, "left")
check("its release runs the entry's action", calls[1], "footerAction secondary")

calls = {}
view:_onMouseDown(second, "left")
view:_onMouseUp(centre(barHits.entries[3].rect), "left")
check("a release on another entry runs nothing", #calls, 0)

-- Between the groups, ten points into the bar, which is the sixth row behind it.
calls = {}
local between = { x = (barHits.keys.x + barHits.keys.w + barHits.actions.x) / 2, y = footerRect.y + 10 }
view:_onMouseDown(between, "left")
view:_onMouseUp(between, "left")
check("a press between the groups chooses the row behind the bar", calls[1], "choose 6")

calls = {}
view:_onMouseMove(centre(barHits.keys))
check("the keys group lights under the pointer", view._barHover, "keys")
check("and the pointer on it highlights no row", #calls, 0)
view:_onMouseMove(second)
check("an entry lights under the pointer", view._barHover, 2)
check("drawn on the highlight", #filled(surfaceCanvas.els, T.colors.highlight) >= 1, true)
view:_onMouseMove(between)
check("off the groups nothing on the bar is lit", view._barHover, nil)
check("and the row behind it is highlighted", calls[#calls], "highlight 6")

check("a scroll over a group is claimed", view:_onMouseScroll(centre(barHits.keys), 1, true), true)
check("and moves nothing", scene.list.scrollTop, 0)

-- The divider with a pane, the full height of the window as in swift.
local pane = { x = canvasRect.x + canvasRect.w, y = canvasRect.y, w = 300, h = canvasRect.h }
scene.rects = { canvas = canvasRect, list = listRect, companion = pane,
  footer = { x = canvasRect.x, y = footerRect.y, w = canvasRect.w + pane.w, h = footerH } }
view:place(scene.rects)
view:redraw()
local divider
for _, el in ipairs(surfaceCanvas.els) do
  if el.type == "rectangle" and el.fillColor == T.colors.border and el.frame and el.frame.w == T.stroke.border then
    divider = el
  end
end
check("the divider runs from the top of the window", divider and divider.frame.y, 0)
check("to its bottom", divider and divider.frame.h, canvasRect.h)
check("and the actions group floats over the pane", view._barHits.actions.x + view._barHits.actions.w,
  pane.x + pane.w - T.pad)

if failed then
  print("canvasbar.lua, FAILED")
  os.exit(1)
end
print("canvasbar.lua, all passed")
