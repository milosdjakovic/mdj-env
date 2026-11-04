-- The canvas chooser's floating panes, in plain Lua over the real UI kit and a recording canvas.
--
-- First lib/chooser/providers/default/floatingpane.lua alone, the one drawing routine the info pane
-- and the actions pane share, the canvas clone of swift's FloatingPane.swift. Its sizes are pinned to
-- the tokens they come from, its placement to swift's layoutKeys and layoutActions, above its
-- group, the outer padding between, never above the list's top and never wider than the window
-- less the outer padding, and its highlight to the outer padding and the nested radius. Then the
-- canvas view over a fake engine, the info pane and the actions pane drawn above their anchors,
-- the list keeping the rows it showed while the actions pane floats, and the pointer reaching
-- the panel's lines through the engine calls the swift view makes, hover to highlightIndex and a
-- click to chooseIndex, while the rows behind take no press, no hover and no scroll of the engine.
--
-- How it looks is judged live, not here.
--
-- Run it.
--   lua test/canvasfloatingpane.lua

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

-- Every character seven points wide, every font the same metrics, so a width is countable.
local canvases = {}
hs = {
  host = { interfaceStyle = function() return "Dark" end },
  drawing = { getTextDrawingSize = function(s) return { w = 7 * #s, h = 18 } end },
  styledtext = { fontInfo = function() return { ascender = 13, descender = -4, capHeight = 10 } end,
    new = function(s) return { text = s } end },
  canvas = {
    new = function(frame)
      local c = { frame_ = frame, els = {}, shown = false }
      function c:level() end
      function c:clickActivating() end
      function c:frame(f) self.frame_ = f end
      function c:replaceElements(els) self.els = els end
      function c:show() self.shown = true end
      function c:hide() self.shown = false end
      function c:isShowing() return self.shown end
      canvases[#canvases + 1] = c
      return c
    end,
    windowLevels = { popUpMenu = "popUpMenu" },
  },
  timer = { doEvery = function() return { stop = function() end } end },
}

local UI = dofile(spoon .. "lib/ui/init.lua")
UI.configure({ spec = { radius = { surface = 17 } } })
local T = UI.tokens()
local floatingPane = dofile(spoon .. "lib/chooser/providers/default/floatingpane.lua")
local bottomBarLib = dofile(spoon .. "lib/chooser/providers/default/bottombar.lua")
-- Every chord is a kbd chord, lib/kbd.lua, one entry per key.
local kbd = dofile(spoon .. "lib/kbd.lua")
local listModel = dofile(spoon .. "lib/chooser/providers/default/list/model.lua")

local MARGIN = 12
local lineH = bottomBarLib.height(T)
local style = floatingPane.style(UI, T, MARGIN, lineH)

--------------------------------------------------------------------------------
-- The drawing routine alone
--------------------------------------------------------------------------------

check("the padding inside is the bar's one padding", style.outer, T.barInner)
check("and inside a line the same one", style.inner, T.barInner)
check("a line is the bar's row", style.lineH, lineH)
check("the corner is the highlighted row's, the surface less the list margin",
  style.radius, UI.nestedRadius(T.radius.surface, MARGIN))
check("a lit line's corner nests inside the floating pane's by the outer padding",
  style.lineRadius, UI.nestedRadius(style.radius, T.barInner))
check("the words are the body role", style.font, T.text.body.font)
check("a heading is the caption role", style.headFont, T.text.caption.font)
check("filled with the background role", style.background, T.colors.background)
check("outlined in the border role", style.border, T.colors.border)
check("at the border stroke", style.stroke, T.stroke.border)

-- The info pane, read lines and a header, laid out as the actions pane's lines are.
local keys = floatingPane.layout(UI, style, "Keys", {
  { label = "Copy", chord = kbd.of(kbd.Cmd, kbd.named("c")) },
  { label = "Open in Finder", chord = kbd.of(kbd.Cmd, kbd.named("o")) },
}, false)
-- The chord is a key cap, its glyphs one per key with the hint badge's gap between them and its
-- padding either side.
local widest = 7 * #"Open in Finder" + T.space.l + 7 * #"\u{2318}" + T.badge.hint.gap + 7 * #"O"
  + 2 * T.badge.hint.padX
check("a read line's text stands the outer and the inner padding in, as a chosen line's", keys.side,
  T.barInner + T.barInner)
check("a read floating pane is its widest line and both paddings on both sides", keys.w,
  math.ceil(widest + 4 * T.barInner))
check("and as tall as its header line, the rule, the padding under it, its lines and the outer padding", keys.h,
  math.ceil(lineH + T.stroke.border + T.barInner + 2 * lineH + 2 * T.barInner))

-- The legend, a leader symbol drawn bare before each label and the physical key as the chord.
check("caps lock is its own key", kbd.physical("capsLock").keys[1], kbd.CapsLock)
for _, name in ipairs({ "capsLock", "capslock", "caps", "caps_lock", "Caps Lock" }) do
  check("every spelling of Caps Lock is the one key, " .. name, kbd.named(name), kbd.CapsLock)
end
check("a right hand modifier is right and its glyph", #kbd.physical("rightOption").keys, 2)
check("the second key the modifier itself", kbd.physical("rightOption").keys[2], kbd.Alt)
check("a function key is itself", kbd.physical("f13").keys[1], kbd.named("f13"))
check("a right hand modifier is read from its name, rightShift", kbd.physical("rightShift").keys[2], kbd.Shift)
check("and rightControl", kbd.physical("rightControl").keys[2], kbd.Ctrl)
local legend = floatingPane.layout(UI, style, nil, {
  { lead = kbd.of(kbd.Hyper), label = "Hyper", chord = kbd.physical("capsLock") },
  { label = "Move Down", chord = kbd.of(kbd.Down) },
}, false)
local leadW = bottomBarLib.leadKeyWidth(UI, T, kbd.of(kbd.Hyper))
check("a line with a lead takes its room and the gap", legend.lines[1].leadW, leadW + T.space.l)
check("a line without one starts at the left edge", legend.lines[2].leadW, 0)
local legendEls = floatingPane.elements(UI, legend, { x = 0, y = 0, w = legend.w, h = legend.h }, {})
local hyperLabel
for _, el in ipairs(legendEls) do
  if el.type == "text" and el.text == "Hyper" then hyperLabel = el end
end
check("the label stands after the lead", hyperLabel.frame.x, legend.side + leadW + T.space.l)

-- The actions pane, chosen lines with sections and pictures.
local picture = function(frame) return { { type = "image", frame = frame } } end
local actions = floatingPane.layout(UI, style, nil, {
  { label = "Open", chord = kbd.of(kbd.Return), picture = picture },
  { label = "Reveal", chord = kbd.of(kbd.Cmd, kbd.Return), picture = picture },
  { label = "Rename", chord = kbd.of(kbd.Cmd, kbd.named("r")), picture = picture, section = "File" },
  { label = "Delete", chord = kbd.of(kbd.Cmd, kbd.Delete), picture = picture, section = "File", enabled = false },
  { label = "Share", chord = kbd.of(kbd.Cmd, kbd.named("s")), picture = picture, section = "Send" },
}, true)
check("a chosen line's text stands the outer and the inner padding in", actions.side, T.barInner + T.barInner)
check("a heading starts each run of one section", #actions.headings, 2)
check("the first heading stands above its first line", actions.headings[1].top, 2 * lineH)
check("and the line under it is pushed down by a line", actions.tops[3], 3 * lineH)
check("a chosen floating pane is as tall as its lines and the outer padding", actions.h, math.ceil(7 * lineH + 2 * T.barInner))
check("a picture takes its side and the gap", actions.lead, T.text.section.lineHeight + T.space.l)

-- Placement, swift's rules.
local keysAnchor = { x = 20, y = 500, w = 60, h = 30 }
local room = { w = 800, top = 50 }
local r = floatingPane.place(keys, keysAnchor, "left", room)
check("the info pane's left edge is on its group's", r.x, keysAnchor.x)
check("its bottom edge on its group's, whose corner it takes", r.y + r.h, keysAnchor.y + keysAnchor.h)
check("at its preferred size", r.w, keys.w)
local actionsAnchor = { x = 700, y = 500, w = 80, h = 30 }
r = floatingPane.place(actions, actionsAnchor, "right", room)
check("the actions pane's right edge is on its group's", r.x + r.w, actionsAnchor.x + actionsAnchor.w)
r = floatingPane.place(actions, actionsAnchor, "right", { w = 800, top = 400 })
check("never above the list's top", r.y, 400)
check("where it is shorter than its lines", r.h, keysAnchor.y + keysAnchor.h - 400)
r = floatingPane.place(keys, { x = 700, y = 500, w = 60, h = 30 }, "left", room)
check("never wider than the window less the outer padding", r.x + r.w, 800 - T.pad)
r = floatingPane.place(actions, { x = 40, y = 500, w = 20, h = 30 }, "right", room)
check("on the left too", r.x, T.pad)
local wide = { x = 400, y = 500, w = actions.w + 90, h = 30 }
r = floatingPane.place(actions, wide, "right", room)
check("never narrower than a wider group under it", r.w, wide.w)
check("its right edge still on the group's", r.x + r.w, wide.x + wide.w)
r = floatingPane.place(keys, { x = 20, y = 500, w = keys.w + 40, h = 30 }, "left", room)
check("the info pane too", r.w, keys.w + 40)

-- One rule for both, mirrored. Each pane stops the outer padding clear of the group that stays.
local narrowRoom = { w = 2 * keys.w, top = 50 }
local stays = { x = keys.w, y = 500, w = keys.w - 20, h = 30 }
narrowRoom.other = stays
r = floatingPane.place(keys, keysAnchor, "left", narrowRoom)
check("the info pane stops the pad clear of the right side", r.x + r.w, stays.x - T.pad)
check("its left edge still on its group's", r.x, keysAnchor.x)
local W = narrowRoom.w
local function flip(rect) return { x = W - rect.x - rect.w, y = rect.y, w = rect.w, h = rect.h } end
local right = floatingPane.place(keys, flip(keysAnchor), "right", { w = W, top = 50, other = flip(stays) })
check("the actions pane is the info pane mirrored, its x", right.x, flip(r).x)
check("and its width", right.w, r.w)
check("and its height", right.h, r.h)

-- The highlight, and the lines as hit rects.
r = floatingPane.place(actions, actionsAnchor, "right", room)
local els, info = floatingPane.elements(UI, actions, r, { highlight = 2 })
local lit
for _, el in ipairs(els) do
  if el.type == "rectangle" and el.fillColor == T.colors.highlight then lit = el end
end
check("the lit line is drawn", lit ~= nil, true)
check("the outer padding in from the floating pane's side", lit.frame.x, r.x + T.barInner)
check("as wide as the floating pane less the outer padding twice", lit.frame.w, r.w - 2 * T.barInner)
check("as tall as a line", lit.frame.h, lineH)
check("the outer padding below the floating pane's top, under the first line", lit.frame.y, r.y + T.barInner + lineH)
check("at the nested corner", lit.roundedRectRadii.xRadius, style.lineRadius)
check("every line is a hit rect", #info.lines, 5)
check("a hit rect names its line", info.lines[3].index, 3)
check("nothing to scroll at full height", info.maxScroll, 0)
local _, readInfo = floatingPane.elements(UI, keys, floatingPane.place(keys, keysAnchor, "left", room), { highlight = 1 })
local readLit = false
for _, el in ipairs((floatingPane.elements(UI, keys, floatingPane.place(keys, keysAnchor, "left", room), { highlight = 1 }))) do
  if el.type == "rectangle" and el.fillColor == T.colors.highlight then readLit = true end
end
check("a read floating pane lights nothing", readLit, false)
check("but its lines are still rects", #readInfo.lines, 2)
local strokes, fills = 0, 0
for _, el in ipairs(els) do
  if el.action == "stroke" then strokes = strokes + 1 end
  if el.type == "rectangle" and el.fillColor == T.colors.background then fills = fills + 1 end
end
check("one outline", strokes, 1)
check("one fill", fills, 1)

-- A short floating pane scrolls, and reveal brings the lit line into view.
local short = floatingPane.place(actions, actionsAnchor, "right", { w = 800, top = 500 - T.pad - 2 * lineH })
local _, sInfo = floatingPane.elements(UI, actions, short, { highlight = 5, reveal = true })
check("a short floating pane can scroll", sInfo.maxScroll > 0, true)
local shown = false
for _, l in ipairs(sInfo.lines) do if l.index == 5 and l.rect.h == lineH then shown = true end end
check("reveal shows the lit line whole", shown, true)
local _, clamped = floatingPane.elements(UI, actions, short, { scroll = 1e6 })
check("a scroll is clamped to its furthest", clamped.scroll, sInfo.maxScroll)

--------------------------------------------------------------------------------
-- The canvas view
--------------------------------------------------------------------------------

local Canvas = dofile(spoon .. "lib/chooser/providers/default/canvas.lua")
Canvas.configure({
  panel = { surfaceElements = function() return {} end, emptyStateElements = function() return {} end },
  ui = UI,
})

local drawLayout = { rowH = 40, rowCount = 8, font = T.text.body.font, textSize = T.text.body.size,
  textLine = T.text.body.lineHeight, numFont = T.text.body.font, numSize = T.text.body.size,
  subFont = T.text.caption.font, subSize = T.text.caption.size, subLine = 16, iconSize = 24,
  iconGap = 10, padX = 12, showRowNumbers = false }
local function rows(names)
  local out = {}
  for _, n in ipairs(names) do out[#out + 1] = { title = n, item = n } end
  return out
end
local listRows = listModel.newState(rows({ "alpha", "beta", "gamma", "delta" }), drawLayout)
local panelRows = listModel.newState({
  { title = "Open", chord = kbd.of(kbd.Return), item = "open" },
  { title = "Rename", chord = kbd.of(kbd.Cmd, kbd.named("r")), item = "rename", section = "File" },
}, drawLayout)

local scene = {
  rects = {
    canvas = { x = 100, y = 100, w = 600, h = 460 },
    field = { x = 112, y = 100, w = 576, h = 50 },
    list = { x = 100, y = 150, w = 600, h = 340 },
    bottomBar = { x = 100, y = 490, w = 600, h = 70 },
  },
  layout = { marginX = MARGIN, caretWidth = 2, titleLineBreak = "truncateTail" },
  drawLayout = drawLayout,
  tokens = T,
  type = { fieldFont = T.text.title.font, fieldSize = T.text.title.size },
  list = listRows,
  rankedQuery = "",
  placeholder = "",
  bare = false,
  bottomBar = { keys = { { label = "Copy", badges = { kbd.of(kbd.Cmd, kbd.named("c")) } } }, right = { { label = "Open", chord = kbd.of(kbd.Return) } },
    title = "Keys" },
  infoOpen = false,
}
local calls = {}
local engine = {
  scene = function() return scene end,
  isActive = function() return true end,
  posture = function() return "list" end,
  highlightIndex = function(_, i) calls[#calls + 1] = "highlight " .. tostring(i) end,
  chooseIndex = function(_, i) calls[#calls + 1] = "choose " .. tostring(i) end,
  rightClickIndex = function(_, i) calls[#calls + 1] = "right " .. tostring(i) end,
  scrollBy = function(_, d) calls[#calls + 1] = "scroll " .. tostring(d) end,
  toggleInfo = function() calls[#calls + 1] = "toggleInfo" end,
  hide = function() calls[#calls + 1] = "hide" end,
}
local function last() return calls[#calls] end
local view = Canvas.new(engine)
view:restyle()
view:place(scene.rects)

check("the canvas view floats the actions pane", view:floatsActionsPane(), true)

view:redraw()
check("nothing pops over a list at rest", next(view._floatingPanes), nil)
check("the anchors are kept for the floating panes", view._anchors and view._anchors.keys ~= nil, true)

-- The info pane above its anchor.
scene.infoOpen = true
view:redraw()
local kp = view._floatingPanes.keys
check("an open info pane is drawn", kp ~= nil, true)
local anchor = view._anchors.keys
check("its left edge on the keys anchor", kp.rect.x, anchor.x + scene.rects.canvas.x)
check("its bottom edge on the keys anchor's", kp.rect.y + kp.rect.h, anchor.y + anchor.h + scene.rects.canvas.y)
check("the left side is hidden while it is open", view._barHits.keys, nil)
check("and the right side stays", view._barHits.actions ~= nil, true)
local inPanel = { x = kp.rect.x + 5, y = kp.rect.y + kp.rect.h - 5 }
check("a point on the info pane is on no row", view:_rowIndexAtPoint(inPanel), nil)
calls = {}
check("a scroll over it is claimed", view:_onMouseScroll(inPanel, -3, true), true)
check("and never scrolls the list", #calls, 0)
-- A line longer than the room stops the info pane the bar pad clear of the right side.
local keptKeys = scene.bottomBar.keys
scene.bottomBar.keys = { { label = string.rep("A very long shortcut label ", 12), badges = { kbd.of(kbd.Cmd, kbd.named("c")) } } }
view:redraw()
local lk = view._floatingPanes.keys.rect
local actionsLeft = view._anchors.actions.x + scene.rects.canvas.x
check("a long line stops the info pane the bar pad clear of the right side", lk.x + lk.w, actionsLeft - T.pad)
check("its left edge still on the keys anchor", lk.x, anchor.x + scene.rects.canvas.x)
scene.bottomBar.keys = keptKeys
scene.infoOpen = false

-- The actions pane floats, and the list goes on drawing the rows it had.
scene.list = panelRows
scene.bottomBar.panelOpen, scene.bottomBar.panelTitle = true, nil
view:redraw()
local ap = view._floatingPanes.actions
check("the actions pane is drawn", ap ~= nil, true)
check("its right edge on the actions anchor", ap.rect.x + ap.rect.w,
  view._anchors.actions.x + view._anchors.actions.w + scene.rects.canvas.x)
check("the list keeps the rows it showed", view._held.list, listRows)
local drewAlpha = false
for _, el in ipairs(canvases[#canvases].els) do
  if el.type == "text" and el.text == "alpha" then drewAlpha = true end
end
check("so its first row is still drawn behind the panel", drewAlpha, true)
check("its lines are hit rects", #ap.lines, 2)

calls = {}
local line2 = ap.lines[2].rect
local onLine2 = { x = line2.x + 5, y = line2.y + 2 }
view:_onMouseMove(onLine2)
check("hovering a line highlights it through the engine", last(), "highlight 2")
calls = {}
view:_onMouseMove({ x = ap.lines[1].rect.x + 5, y = ap.lines[1].rect.y + 2 })
check("the lit line asks nothing again", #calls, 0)

calls = {}
check("a press on a line is claimed", view:_onMouseDown(onLine2, "left"), true)
view:_onMouseUp(onLine2, "left")
check("its release chooses the line through the engine", last(), "choose 2")

calls = {}
local onRow = { x = scene.rects.list.x + 20, y = scene.rects.list.y + 10 }
check("a row behind the floating panel is on no row", view:_rowIndexAtPoint(onRow), nil)
view:_onMouseMove(onRow)
view:_onMouseDown(onRow, "left")
view:_onMouseUp(onRow, "left")
view:_onMouseDown(onRow, "right")
check("and takes no hover, choose or right click", #calls, 0)
check("a scroll over it is claimed", view:_onMouseScroll(onRow, -5, true), true)
check("and moves only the kept rows", #calls, 0)
check("which it moved", view._held.list ~= listRows, true)

-- Closed again, the engine's rows draw and a row is a row.
scene.list = listRows
scene.bottomBar.panelOpen = false
view:redraw()
check("the actions pane is gone", view._floatingPanes.actions, nil)
check("its scroll forgotten", view._popScroll.actions, nil)
check("a row is a row again", view:_rowIndexAtPoint(onRow), 1)

-- The actions pane's width holds while it is open. The right side at rest is Paste, Copy and
-- Actions, and open it describes the panel, its Return label the lit line's, Mullvad or IVPN,
-- so the pane keeps the width the right side had at rest and does not follow the label.
do
  local Return, CmdReturn, Actions = kbd.of(kbd.Return), kbd.of(kbd.Cmd, kbd.Return), kbd.of(kbd.Cmd, kbd.named("k"))
  scene.list = listRows
  scene.bottomBar.panelOpen = false
  scene.bottomBar.right = {
    { label = "Paste", chord = Return, action = "primary", fit = true },
    { label = "Copy", chord = CmdReturn, action = "secondary", fit = true },
    { label = "Actions", chord = Actions, action = "actions" },
  }
  view:redraw()
  local restW = view._anchors.actions.w
  local restRight = view._anchors.actions.x + view._anchors.actions.w
  scene.list = panelRows
  scene.bottomBar.panelOpen = true
  scene.bottomBar.right = { { label = "Mullvad", chord = Return, fit = true }, { label = "Actions", chord = Actions } }
  view:redraw()
  local first = view._floatingPanes.actions.rect
  check("open over a shorter right side, the pane keeps the rest width", first.w, restW)
  check("its right edge where the right side stood", first.x + first.w, restRight + scene.rects.canvas.x)
  scene.bottomBar.right[1].label = "IVPN"
  view:redraw()
  check("the width holds as the Return label follows the lit line", view._floatingPanes.actions.rect.w, first.w)
  scene.bottomBar.right[1].label = "A much longer lit line title"
  view:redraw()
  check("whatever the label", view._floatingPanes.actions.rect.w, first.w)

  -- A pane line longer than the room stops the pane the bar pad clear of the left side.
  scene.list = listModel.newState({
    { title = "Open " .. string.rep("with a very long verb title ", 8), chord = Return, item = "open" },
  }, drawLayout)
  view:redraw()
  local lp = view._floatingPanes.actions.rect
  local keysRight = view._anchors.keys.x + view._anchors.keys.w + scene.rects.canvas.x
  check("a long line stops the pane the bar pad clear of the left side", lp.x, keysRight + T.pad)
  check("its right edge still where the right side stands", lp.x + lp.w, restRight + scene.rects.canvas.x)
  scene.list = listRows
  scene.bottomBar.panelOpen = false
  view:redraw()
end

if failed then
  print("canvasfloatingpane, FAILED")
  os.exit(1)
end
print("canvasfloatingpane, every check passed")
