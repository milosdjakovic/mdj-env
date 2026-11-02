-- The canvas chooser's bar, two floating groups, in plain Lua over the real UI kit and stubs for
-- the few hs calls the kit and the view make.
--
-- Pins that lib/chooser/providers/default/bar.lua lays the groups out by the numbers swift's
-- view.lua hands Swift, the left side the bar pad in from the left and the right side the
-- bar pad in from the right, each as tall as bottombar.lua's height at the top of the bottom bar rect,
-- the inner padding inside it, the background fill outlined in the border role at the border
-- stroke with its corner less half the stroke, the words in the body role, every chord a key cap
-- of the hint badge's size in its section role, the icon at the hint size, and that the items' spans cover the right side edge to edge in order.
--
-- Then that lib/chooser/providers/default/canvas.lua draws the list on down behind the bar
-- without moving the engine's scroll, runs the divider the full height of the window, and
-- answers the pointer the way swift does, a press on the left side toggling the info pane, a
-- press and release on an item running its action through bottomBarAction, a press between the
-- groups reaching the row behind the bar, and the left side and each item lighting under the
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
local bottomBarLib = dofile(spoon .. "lib/chooser/providers/default/bottombar.lua")
-- Every chord is a kbd chord, lib/kbd.lua, one item per key.
local kbd = dofile(spoon .. "lib/kbd.lua")
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
  keysChord = kbd.of(kbd.Cmd, kbd.Question),
  right = {
    { label = "Open", chord = kbd.of(kbd.Return), action = "primary" },
    { label = "Reveal", chord = kbd.of(kbd.Cmd, kbd.Return), action = "secondary" },
    { label = "Actions", chord = kbd.of(kbd.Cmd, kbd.named("k")), action = "actions" },
  },
}
local itemH = bottomBarLib.height(T)
local groupH = itemH + 2 * T.barInner
local rect = { x = 0, y = 400, w = 900, h = groupH + T.pad }
local m = barLib.metrics(T)
check("a item is as tall as bottombar.lua's row, a panel line", m.itemH, itemH)
check("the group height is the item and the padding around it", m.height, groupH)
check("the bar pad is the kit's pad", m.pad, T.pad)
check("the padding inside a group is the bar's one padding", m.inner, T.barInner)
check("which is also above and below the tallest part", bottomBarLib.height(T), math.max(T.badge.hint.height, T.text.body.lineHeight) + 2 * T.barInner)

local els, hits = barLib.elements(ui, T, model, rect, { radius = 9 })
local keys, actions = hits.keys, hits.actions
check("the left side stands the bar pad from the left", keys.x, rect.x + T.pad)
check("at the top of the bottom bar rect", keys.y, rect.y)
check("as tall as a item and the padding around it", keys.h, groupH)
-- The ? glyph and the chord's cap, each glyph eight points a byte, the cap its glyphs one per key
-- with the hint badge's gap between two keys and its padding either side.
local function capW(chord)
  return 8 * #kbd.text(chord) + (#chord.keys - 1) * T.badge.hint.gap + 2 * T.badge.hint.padX
end
check("the hint badge spaces two keys of a chord by its gap, four points", T.badge.hint.gap, 4)
check("as wide as its parts, the small gap, the padding inside its item and around it",
  keys.w, 8 * #"?" + T.space.s + capW(model.keysChord) + 4 * T.barInner)
check("its one item stands the padding in from the group", hits.leftItem.x, keys.x + T.barInner)
check("from the top too", hits.leftItem.y, keys.y + T.barInner)
check("and is a item tall", hits.leftItem.h, itemH)
check("the right side stands the bar pad from the right", actions.x + actions.w, rect.x + rect.w - T.pad)
check("at the same height", actions.y, rect.y)
local entriesW = 0
for _, r in ipairs(model.right) do entriesW = entriesW + 8 * #r.label + T.space.s + capW(r.chord) + 2 * T.barInner end
check("as wide as its items, each padded inside, and the padding around them",
  actions.w, entriesW + 2 * T.barInner)

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
local words, caps = {}, {}
for _, t in ipairs(texts(els)) do
  if type(t.text) == "table" then words[#words + 1] = t else caps[#caps + 1] = t end
end
check("every word is drawn", #words, 1 + #model.right)
local allBody = true
for _, t in ipairs(words) do
  if t.text.attrs.font.size ~= T.text.body.size or t.text.attrs.font.name ~= T.text.body.font then allBody = false end
end
check("all in the body role", allBody, true)
local keyCount = #model.keysChord.keys
for _, r in ipairs(model.right) do keyCount = keyCount + #r.chord.keys end
check("every key of every chord is a glyph of its own", #caps, keyCount)
local capRole = T.text[T.badge.hint.text]
local allCode = true
for _, t in ipairs(caps) do
  if t.textSize ~= capRole.size or t.textFont ~= capRole.font then allCode = false end
end
check("its glyphs in the hint badge's role, the mono code role", allCode and T.badge.hint.text == "code", true)
check("two keys of a chord stand the gap apart", caps[2].frame.x - (caps[1].frame.x + caps[1].frame.w), T.badge.hint.gap)
local chips = {}
for _, el in ipairs(els) do
  if el.type == "rectangle" and el.action == "fill" and el.frame.h == T.badge.hint.height then chips[#chips + 1] = el end
end
check("each on a chip the hint badge's height", #chips, 1 + #model.right)
check("the chip as wide as its glyphs, the gap and the padding", chips[1].frame.w, capW(model.keysChord))
check("centred in the item", chips[1].frame.y, math.floor(rect.y + T.barInner + (itemH - T.badge.hint.height) / 2 + 0.5))

-- A chord naming alternatives is one chip per key with the alternative word between them.
local alt = { kbd.of(kbd.named("j")), kbd.of(kbd.Down) }
local altEls = bottomBarLib.keycap(ui, T, alt, 0, 0, bottomBarLib.height(T), 9)
local altChips, altWord = 0, false
for _, el in ipairs(altEls) do
  if el.type == "rectangle" then altChips = altChips + 1 end
  if el.type == "text" and el.text == bottomBarLib.ALT_WORD then altWord = true end
end
check("alternatives are one chip per key", altChips, 2)
check("with the alternative word between them", altWord, true)
check("as wide as both chips, the word and the small step either side of it",
  bottomBarLib.keycapWidth(ui, T, alt), capW(alt[1]) + capW(alt[2]) + 8 * #bottomBarLib.ALT_WORD + 2 * T.space.s)
check("a chord that is a string is refused", pcall(bottomBarLib.keycapWidth, ui, T, "\u{2318}K"), false)

check("one item per item", #hits.items, 3)
check("the first item stands the padding in from the group's edge", hits.items[1].rect.x, actions.x + T.barInner)
check("and the last from its other edge", hits.items[3].rect.x + hits.items[3].rect.w, actions.x + actions.w - T.barInner)
check("the items meet", hits.items[1].rect.x + hits.items[1].rect.w, hits.items[2].rect.x)
check("each stands the padding from the group's top", hits.items[2].rect.y, actions.y + T.barInner)
check("and is a item tall", hits.items[2].rect.h, itemH)
check("each names its action", hits.items[2].action, "secondary")
check("a middle item starts right after the first",
  hits.items[2].rect.x, actions.x + T.barInner + 8 * #"Open" + T.space.s + capW(model.right[1].chord) + 2 * T.barInner)

els = barLib.elements(ui, T, model, rect, { radius = 9, leftHover = true, hover = 2 })
local lit = filled(els, T.colors.highlight)
check("a hovered keys item and a hovered item sit on the highlight", #lit, 2)
check("the keys item lights over its item", lit[1].frame.x, hits.leftItem.x)
check("the hovered item lights over its item", lit[2].frame.x, hits.items[2].rect.x)
check("and that item's width", lit[2].frame.w, hits.items[2].rect.w)
check("at the panel line's corner, the group's less the padding", lit[2].roundedRectRadii.xRadius,
  ui.nestedRadius(9, T.barInner))
els = barLib.elements(ui, T, model, rect, { radius = 9, leftLit = true })
check("a left side whose panel is open sits on the highlight whole", filled(els, T.colors.highlight)[1].frame.w, keys.w)

local open = { keysChord = model.keysChord, right = model.right, panelOpen = true }
els = barLib.elements(ui, T, open, rect, { radius = 9 })
check("the right side lights while the actions pane is open", #filled(els, T.colors.highlight), 1)

local image = io.stdout
els, hits = barLib.elements(ui, T, { right = {} }, rect, { radius = 9, keysImage = image })
local pictures = {}
for _, el in ipairs(els) do if el.type == "image" then pictures[#pictures + 1] = el end end
check("the keyboard icon is drawn", #pictures, 1)
check("at the hint size", pictures[1].frame.w, T.icon.hint)
check("centred in the item", pictures[1].frame.y, rect.y + T.barInner + (itemH - T.icon.hint) / 2)
check("no right side, no right side", hits.actions, nil)
check("and no items", #hits.items, 0)

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
local bottomBarH = bottomBarLib.height(T) + 2 * T.barInner + T.pad
local canvasRect = { x = 100, y = 100, w = 600, h = 60 + rowH * rowCount + bottomBarH }
local listRect = { x = 110, y = 160, w = 580, h = rowH * rowCount }
local bottomBarRect = { x = 100, y = listRect.y + listRect.h, w = 600, h = bottomBarH }
local scene = {
  bare = true,
  tokens = T,
  layout = { marginX = 10 },
  type = { fieldFont = T.text.title.font, fieldSize = T.text.title.size },
  drawLayout = { rowH = rowH, rowCount = rowCount, font = T.text.body.font, textSize = T.text.body.size,
    textLine = T.text.body.lineHeight, subFont = T.text.caption.font, subSize = T.text.caption.size,
    subLine = T.text.caption.lineHeight, numFont = T.text.body.font, numSize = T.text.body.size,
    showRowNumbers = false },
  rects = { canvas = canvasRect, list = listRect, bottomBar = bottomBarRect },
  bottomBar = model,
}
scene.list = listModel.newState(rows, { rowH = rowH, rowCount = rowCount })

local calls = {}
local engine = {
  scene = function() return scene end,
  isActive = function() return false end,
  toggleInfo = function() calls[#calls + 1] = "toggleInfo" end,
  bottomBarAction = function(_, name) calls[#calls + 1] = "bottomBarAction " .. name end,
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
check("the list runs on behind the bar", rowTitles(surfaceCanvas.els), rowCount + math.ceil(bottomBarH / rowH))
check("without moving the engine's scroll", scene.list.scrollTop, 0)
check("or its furthest scroll", listModel.maxScrollTop(scene.list), (12 - rowCount) * rowH)
local clip
for _, el in ipairs(surfaceCanvas.els) do
  if el.type == "rectangle" and el.action == "clip" then clip = el; break end
end
check("the rows are cut at the bottom of the window", clip.frame.y + clip.frame.h, canvasRect.h)

local barHits = view._barHits
check("the left side is kept in screen points", barHits.keys.x, canvasRect.x + T.pad)
check("so is the right side", barHits.actions.x + barHits.actions.w, canvasRect.x + canvasRect.w - T.pad)
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
check("a press on the left side is claimed", view:_onMouseDown(centre(barHits.keys), "left"), true)
check("and toggles the info pane", calls[1], "toggleInfo")

calls = {}
local second = centre(barHits.items[2].rect)
view:_onMouseDown(second, "left")
check("a press on an item runs nothing yet", #calls, 0)
view:_onMouseUp(second, "left")
check("its release runs the item's action", calls[1], "bottomBarAction secondary")

calls = {}
view:_onMouseDown(second, "left")
view:_onMouseUp(centre(barHits.items[3].rect), "left")
check("a release on another item runs nothing", #calls, 0)

-- Between the groups, ten points into the bar, which is the sixth row behind it.
calls = {}
local between = { x = (barHits.keys.x + barHits.keys.w + barHits.actions.x) / 2, y = bottomBarRect.y + 10 }
view:_onMouseDown(between, "left")
view:_onMouseUp(between, "left")
check("a press between the groups chooses the row behind the bar", calls[1], "choose 6")

calls = {}
view:_onMouseMove(centre(barHits.keys))
check("the left side lights under the pointer", view._barHover, "keys")
check("and the pointer on it highlights no row", #calls, 0)
view:_onMouseMove(second)
check("an item lights under the pointer", view._barHover, 2)
check("drawn on the highlight", #filled(surfaceCanvas.els, T.colors.highlight) >= 1, true)
view:_onMouseMove(between)
check("off the groups nothing on the bar is lit", view._barHover, nil)
check("and the row behind it is highlighted", calls[#calls], "highlight 6")

check("a scroll over a group is claimed", view:_onMouseScroll(centre(barHits.keys), 1, true), true)
check("and moves nothing", scene.list.scrollTop, 0)

-- The divider with a pane, the full height of the window as in swift.
local pane = { x = canvasRect.x + canvasRect.w, y = canvasRect.y, w = 300, h = canvasRect.h }
scene.rects = { canvas = canvasRect, list = listRect, previewPane = pane,
  bottomBar = { x = canvasRect.x, y = bottomBarRect.y, w = canvasRect.w + pane.w, h = bottomBarH } }
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
check("and the right side floats over the pane", view._barHits.actions.x + view._barHits.actions.w,
  pane.x + pane.w - T.pad)

if failed then
  print("canvasbar.lua, FAILED")
  os.exit(1)
end
print("canvasbar.lua, all passed")
