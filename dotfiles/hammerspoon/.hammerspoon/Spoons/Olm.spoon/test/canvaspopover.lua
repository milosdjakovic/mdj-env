-- The canvas chooser's popovers, in plain Lua over the real UI kit and a recording canvas.
--
-- First lib/chooser/providers/default/popover.lua alone, the one drawing routine the key panel
-- and the action panel share, the canvas clone of swift's Popover.swift. Its sizes are pinned to
-- the tokens they come from, its placement to swift's layoutKeys and layoutActions, above its
-- group, the outer padding between, never above the list's top and never wider than the window
-- less the outer padding, and its highlight to the outer padding and the nested radius. Then the
-- canvas view over a fake engine, the key panel and the action panel drawn above their anchors,
-- the list keeping the rows it showed while the action panel floats, and the pointer reaching
-- the panel's lines through the engine calls the swift view makes, hover to highlightIndex and a
-- click to chooseIndex, while the rows behind take no press, no hover and no scroll of the engine.
--
-- How it looks is judged live, not here.
--
-- Run it.
--   lua test/canvaspopover.lua

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
local popover = dofile(spoon .. "lib/chooser/providers/default/popover.lua")
local footerLib = dofile(spoon .. "lib/chooser/providers/default/footer.lua")
local listModel = dofile(spoon .. "lib/chooser/providers/default/list/model.lua")

local MARGIN = 12
local lineH = footerLib.height(T)
local style = popover.style(UI, T, MARGIN, lineH)

--------------------------------------------------------------------------------
-- The drawing routine alone
--------------------------------------------------------------------------------

check("the outer padding is the kit's pad", style.outer, T.pad)
check("the inner padding is the kit's inner", style.inner, T.inner)
check("a line is the bar's row", style.lineH, lineH)
check("the corner is the highlighted row's, the surface less the list margin",
  style.radius, UI.nestedRadius(T.radius.surface, MARGIN))
check("a lit line's corner nests inside the popover's by the outer padding",
  style.lineRadius, UI.nestedRadius(style.radius, T.pad))
check("the words are the body role", style.font, T.text.body.font)
check("a heading is the caption role", style.headFont, T.text.caption.font)
check("filled with the background role", style.background, T.colors.background)
check("outlined in the border role", style.border, T.colors.border)
check("at the border stroke", style.stroke, T.stroke.border)

-- The key panel, read lines and a header. Its text stands the outer padding from every edge.
local keys = popover.layout(UI, style, "Keys", {
  { label = "Copy", chord = "⌘ C" },
  { label = "Open in Finder", chord = "⌘ O" },
}, false)
local slack = (lineH - T.text.body.lineHeight) / 2
local widest = 7 * #"Open in Finder" + T.space.l + 7 * #"⌘ O"
check("a read popover is its widest line and the outer padding on both sides", keys.w,
  math.ceil(widest + 2 * T.pad))
check("and as tall as its header, its lines less the slack, and the outer padding", keys.h,
  math.ceil(T.text.body.lineHeight + 2 * T.pad + T.stroke.border + 2 * lineH - 2 * slack + 2 * T.pad))

-- The action panel, chosen lines with sections and pictures.
local picture = function(frame) return { { type = "image", frame = frame } } end
local actions = popover.layout(UI, style, nil, {
  { label = "Open", chord = "↩", picture = picture },
  { label = "Reveal", chord = "⌘↩", picture = picture },
  { label = "Rename", chord = "⌘R", picture = picture, section = "File" },
  { label = "Delete", chord = "⌘⌫", picture = picture, section = "File", enabled = false },
  { label = "Share", chord = "⌘S", picture = picture, section = "Send" },
}, true)
check("a chosen line's text stands the outer and the inner padding in", actions.side, T.pad + T.inner)
check("a heading starts each run of one section", #actions.headings, 2)
check("the first heading stands above its first line", actions.headings[1].top, 2 * lineH)
check("and the line under it is pushed down by a line", actions.tops[3], 3 * lineH)
check("a chosen popover takes no slack", actions.h, math.ceil(7 * lineH + 2 * T.pad))
check("a picture takes its side and the gap", actions.lead, T.text.section.lineHeight + T.space.l)

-- Placement, swift's rules.
local keysAnchor = { x = 20, y = 500, w = 60, h = 30 }
local room = { w = 800, top = 50 }
local r = popover.place(keys, keysAnchor, "left", room)
check("the key panel's left edge is on its group's", r.x, keysAnchor.x)
check("it stands the outer padding above its group", r.y + r.h, keysAnchor.y - T.pad)
check("at its preferred size", r.w, keys.w)
local actionsAnchor = { x = 700, y = 500, w = 80, h = 30 }
r = popover.place(actions, actionsAnchor, "right", room)
check("the action panel's right edge is on its group's", r.x + r.w, actionsAnchor.x + actionsAnchor.w)
r = popover.place(actions, actionsAnchor, "right", { w = 800, top = 400 })
check("never above the list's top", r.y, 400)
check("where it is shorter than its lines", r.h, keysAnchor.y - T.pad - 400)
r = popover.place(keys, { x = 700, y = 500, w = 60, h = 30 }, "left", room)
check("never wider than the window less the outer padding", r.x + r.w, 800 - T.pad)
r = popover.place(actions, { x = 40, y = 500, w = 20, h = 30 }, "right", room)
check("on the left too", r.x, T.pad)

-- The highlight, and the lines as hit rects.
r = popover.place(actions, actionsAnchor, "right", room)
local els, info = popover.elements(UI, actions, r, { highlight = 2 })
local lit
for _, el in ipairs(els) do
  if el.type == "rectangle" and el.fillColor == T.colors.highlight then lit = el end
end
check("the lit line is drawn", lit ~= nil, true)
check("the outer padding in from the popover's side", lit.frame.x, r.x + T.pad)
check("as wide as the popover less the outer padding twice", lit.frame.w, r.w - 2 * T.pad)
check("as tall as a line", lit.frame.h, lineH)
check("the outer padding below the popover's top, under the first line", lit.frame.y, r.y + T.pad + lineH)
check("at the nested corner", lit.roundedRectRadii.xRadius, style.lineRadius)
check("every line is a hit rect", #info.lines, 5)
check("a hit rect names its line", info.lines[3].index, 3)
check("nothing to scroll at full height", info.maxScroll, 0)
local _, readInfo = popover.elements(UI, keys, popover.place(keys, keysAnchor, "left", room), { highlight = 1 })
local readLit = false
for _, el in ipairs((popover.elements(UI, keys, popover.place(keys, keysAnchor, "left", room), { highlight = 1 }))) do
  if el.type == "rectangle" and el.fillColor == T.colors.highlight then readLit = true end
end
check("a read popover lights nothing", readLit, false)
check("but its lines are still rects", #readInfo.lines, 2)
local strokes, fills = 0, 0
for _, el in ipairs(els) do
  if el.action == "stroke" then strokes = strokes + 1 end
  if el.type == "rectangle" and el.fillColor == T.colors.background then fills = fills + 1 end
end
check("one outline", strokes, 1)
check("one fill", fills, 1)

-- A short popover scrolls, and reveal brings the lit line into view.
local short = popover.place(actions, actionsAnchor, "right", { w = 800, top = 500 - T.pad - 2 * lineH })
local _, sInfo = popover.elements(UI, actions, short, { highlight = 5, reveal = true })
check("a short popover can scroll", sInfo.maxScroll > 0, true)
local shown = false
for _, l in ipairs(sInfo.lines) do if l.index == 5 and l.rect.h == lineH then shown = true end end
check("reveal shows the lit line whole", shown, true)
local _, clamped = popover.elements(UI, actions, short, { scroll = 1e6 })
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
  { title = "Open", subTitle = "↩", item = "open" },
  { title = "Rename", subTitle = "⌘R", item = "rename", section = "File" },
}, drawLayout)

local scene = {
  rects = {
    canvas = { x = 100, y = 100, w = 600, h = 460 },
    field = { x = 112, y = 100, w = 576, h = 50 },
    list = { x = 100, y = 150, w = 600, h = 340 },
    footer = { x = 100, y = 490, w = 600, h = 70 },
  },
  layout = { marginX = MARGIN, caretWidth = 2, titleLineBreak = "truncateTail" },
  drawLayout = drawLayout,
  tokens = T,
  type = { fieldFont = T.text.title.font, fieldSize = T.text.title.size },
  list = listRows,
  rankedQuery = "",
  placeholder = "",
  bare = false,
  footer = { keys = { { label = "Copy", badges = { "⌘", "C" } } }, right = { { label = "Open", chord = "↩" } },
    title = "Keys" },
  keysOpen = false,
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
  toggleKeys = function() calls[#calls + 1] = "toggleKeys" end,
  hide = function() calls[#calls + 1] = "hide" end,
}
local function last() return calls[#calls] end
local view = Canvas.new(engine)
view:restyle()
view:place(scene.rects)

check("the canvas view floats the action panel", view:floatsActionPanel(), true)

view:redraw()
check("nothing pops over a list at rest", next(view._popovers), nil)
check("the anchors are kept for the popovers", view._anchors and view._anchors.keys ~= nil, true)

-- The key panel above its anchor.
scene.keysOpen = true
view:redraw()
local kp = view._popovers.keys
check("an open key panel is drawn", kp ~= nil, true)
local anchor = view._anchors.keys
check("its left edge on the keys anchor", kp.rect.x, anchor.x + scene.rects.canvas.x)
check("the outer padding above it", kp.rect.y + kp.rect.h, anchor.y + scene.rects.canvas.y - T.pad)
local inPanel = { x = kp.rect.x + 5, y = kp.rect.y + kp.rect.h - 5 }
check("a point on the key panel is on no row", view:_rowIndexAtPoint(inPanel), nil)
calls = {}
check("a scroll over it is claimed", view:_onMouseScroll(inPanel, -3, true), true)
check("and never scrolls the list", #calls, 0)
scene.keysOpen = false

-- The action panel floats, and the list goes on drawing the rows it had.
scene.list = panelRows
scene.footer.panelOpen, scene.footer.panelTitle = true, nil
view:redraw()
local ap = view._popovers.actions
check("the action panel is drawn", ap ~= nil, true)
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
scene.footer.panelOpen = false
view:redraw()
check("the action panel is gone", view._popovers.actions, nil)
check("its scroll forgotten", view._popScroll.actions, nil)
check("a row is a row again", view:_rowIndexAtPoint(onRow), 1)

if failed then
  print("canvaspopover, FAILED")
  os.exit(1)
end
print("canvaspopover, every check passed")
