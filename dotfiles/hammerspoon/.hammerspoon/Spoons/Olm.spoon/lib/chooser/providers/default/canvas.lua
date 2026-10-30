--- === Canvas view ===
---
--- The default chooser's drawing and raw input, the view lib/chooser/engine/init.lua is composed
--- with to make the default provider. It satisfies lib/chooser/view.lua and owns only what is
--- drawn and how a hand reaches it, the surface, the field with its own editing model and keymap,
--- the caret blink, the list's rows as canvas elements, the action bar and its key panel as
--- canvas elements, the mouse tap with its hit tests and the wheel easing. Every picker rule,
--- what a key means, what choosing does, when a callback fires, lives in the engine, and this
--- file turns raw events into calls on it and draws what its scene says. It was split out of
--- the provider on 2026-10-28 with no change in behaviour, see decisions/olm-swift-chooser.md.
---
--- Everything this file stands on already exists. surface.lua owns the window, mouse.lua owns the
--- mouse tap, field is a complete text field, list/render.lua draws rows, footer.lua draws the
--- action bar, and the UI kit's tokens give every colour.
---
--- Rows here carry a title turned into an hs.styledtext value before list render ever sees them,
--- through presentRows, baking in the enabled aware colour, the font, the size and the
--- truncation mode, the same shape legacy.lua's own styledText bakes before handing a row to
--- hs.chooser. geometry.lua's own header measured that hs.canvas honours a styled value's
--- paragraphStyle exactly the way an ordinary macOS text field does, a single ellipsis landing
--- wherever the frame runs out of room, and list/render.lua draws whatever sits under a row's
--- own title or subTitle key without asking what type it is. Subtitles are always cut at the
--- tail, since docs/CONTRACT-PICKER.md says titleLineBreak governs the title alone.
---
--- Colour and type come from the UI kit's tokens, which the engine resolves for the current half
--- on every show and hands over in its scene. The text is foreground and the subtitle subtext,
--- the field's own selection band and the list's own row highlight are both the highlight token,
--- a disabled row and the placeholder are dimmed by the dim alpha, and the row numbers are the
--- section role's colour, subtext. A typed query that leaves no rows draws the shared empty
--- state, CanvasPanel.emptyStateElements in the caption role, saying No results in the band where
--- the rows would be, which list render decides and draws. The caret is left to field render's
--- own fallback, the text colour standing in for it.
---
--- The key order. The field's tap in field/input.lua asks Escape first through onDismiss, then
--- yields, then listKeys, then edits or types, then hands what is left to onKey, and each of those
--- is wired below to the engine call of the same place in lib/chooser/view.lua's order, so the
--- order is the field's own and unchanged by the split.
---
--- Canvas.configure(opts) takes opts.panel, the CanvasPanel module, opts.ui, the UI kit, and
--- optionally opts.icon and opts.iconElements, the icon engine as a picture and as canvas
--- elements. Canvas.new(engine) builds a view for one engine instance.

local herePath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(relPath)
  local chunk, err = loadfile(herePath .. relPath)
  if not chunk then
    error("Canvas provider: failed to load " .. relPath .. ", " .. tostring(err))
  end
  return chunk()
end

local Surface = load("surface.lua")
local Mouse = load("mouse.lua")
local fieldInput = load("field/input.lua")
local Field = fieldInput.Field
local fieldRender = load("field/render.lua")
local listModel = load("list/model.lua")
local listRender = load("list/render.lua")
local footerLib = load("footer.lua")

--------------------------------------------------------------------------------
-- Module level collaborators and constants
--------------------------------------------------------------------------------

-- The injected UI kit, lib/ui, nil until Canvas.configure runs, read for the nested radius and
-- handed to footer.lua, which draws through it.
local UI = nil

-- The injected CanvasPanel module, nil until Canvas.configure runs. Every view this file builds
-- draws through the identical shared chrome and the identical empty state.
local PANEL = nil

-- What the list says when a typed query left no rows, drawn through the shared empty state for
-- every list rather than offered by each tool, so it is never a row anybody can choose.
local NO_RESULTS = "No results"

-- The injected icon resolver, function(icon, owner) -> hs.image or nil, nil until
-- Canvas.configure runs. List render asks it for a row's icon at paint, so the colour is read on
-- every draw and a light and dark switch redraws the icon with nothing watching for it.
local ICON = nil
local ICON_ELEMENTS = nil

-- Every view built, weakly, so iconsChanged can repaint the ones on screen without keeping a
-- dropped one alive.
local views = setmetatable({}, { __mode = "k" })

-- Round five's own scroll easing constants, settled by hand in
-- Spoons/Olm.spoon/test/probe-canvasfield.lua and carried across rather than chosen a second
-- time. wheelNotchPoints is what one wheel notch is worth in points, scrollEaseFactor is the
-- fraction of the remaining distance each tick closes, scrollEaseInterval is how often a tick
-- runs, and scrollEaseEpsilon is how close is close enough to snap the last short distance
-- rather than let the ease technically never finish.
local WHEEL_NOTCH_POINTS = 120
local SCROLL_EASE_FACTOR = 0.28
local SCROLL_EASE_INTERVAL = 1 / 60
local SCROLL_EASE_EPSILON = 0.5

-- The caret blink period, half a second on and half a second off, matching the field probe's
-- own timer, a plain literal rather than a setting since nothing in this tree exposes one.
local BLINK_INTERVAL = 0.5

--------------------------------------------------------------------------------
-- Small stateless helpers, none of them touching self
--------------------------------------------------------------------------------

-- A colour with its alpha multiplied by factor, how a disabled row's title and the placeholder
-- are dimmed by the kit's dim alpha, a plain alpha cut rather than a second colour.
local function faded(color, factor)
  local c = {}
  for k, v in pairs(color) do c[k] = v end
  c.alpha = (c.alpha or 1) * factor
  return c
end

-- Bakes a plain string into an hs.styledtext value carrying the font, the size, the colour and a
-- lineBreak, the identical shape legacy.lua's own styledText already builds before handing a row
-- to hs.chooser, restated here rather than reached for since that file is left untouched.
local function styledText(str, size, color, font, lineBreak)
  return hs.styledtext.new(str or "", {
    font = { name = font, size = size },
    color = color,
    paragraphStyle = { lineBreak = lineBreak or "truncateTail" },
  })
end

-- Whether point sits inside rect, treated as closed at its own left and top edges and open at
-- its right and bottom ones, the identical convention geometry.lua's own M.rowAtPoint takes,
-- and answering false outright for a nil rect so a caller need not guard a missing companion.
local function pointInRect(point, rect)
  return rect ~= nil
    and point.x >= rect.x and point.x < rect.x + rect.w
    and point.y >= rect.y and point.y < rect.y + rect.h
end

-- Restates an absolute screen rect in a canvas's own local coordinates, subtracting the canvas's
-- own top left corner. The engine's rects are in absolute screen points, the same space mouse
-- events use, while an hs.canvas element is placed relative to its own canvas, so this is the
-- one conversion between the two, used only where this file draws rather than where it hit
-- tests, which stays in absolute terms throughout.
local function toLocal(rect, origin)
  if not rect then return nil end
  return { x = rect.x - origin.x, y = rect.y - origin.y, w = rect.w, h = rect.h }
end

-- The span from the canvas rect to the companion rect, the gap between them included, or nil
-- with no companion, the same span the swift view's one shape of glass covers.
local function spanOf(canvas, companion)
  if not (canvas and companion) then return nil end
  local x0, y0 = math.min(canvas.x, companion.x), math.min(canvas.y, companion.y)
  local x1 = math.max(canvas.x + canvas.w, companion.x + companion.w)
  local y1 = math.max(canvas.y + canvas.h, companion.y + companion.h)
  return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

local function sameRect(a, b)
  return a ~= nil and b ~= nil and a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

-- One element of a hosted pane moved from the pane's own space into the window's, a copy with its
-- frame, centre and coordinates shifted. A rectangle or an oval with no frame fills its canvas, so
-- one is given the pane's own box rather than spreading over the whole window.
local function shiftedElement(el, dx, dy, paneW, paneH)
  local copy = {}
  for k, v in pairs(el) do copy[k] = v end
  local frame = el.frame
  if not frame and (el.type == "rectangle" or el.type == "oval") and el.action ~= "clip" then
    frame = { x = 0, y = 0, w = paneW, h = paneH }
  end
  if frame then
    copy.frame = { x = (frame.x or 0) + dx, y = (frame.y or 0) + dy, w = frame.w, h = frame.h }
  end
  if el.center then
    copy.center = { x = (el.center.x or 0) + dx, y = (el.center.y or 0) + dy }
  end
  if el.coordinates then
    local coords = {}
    for i, c in ipairs(el.coordinates) do
      local p = {}
      for k, v in pairs(c) do p[k] = v end
      for _, k in ipairs({ "x", "c1x", "c2x" }) do if p[k] then p[k] = p[k] + dx end end
      for _, k in ipairs({ "y", "c1y", "c2y" }) do if p[k] then p[k] = p[k] + dy end end
      coords[i] = p
    end
    copy.coordinates = coords
  end
  return copy
end

-- Turns one already ranked row into what list render draws, a shallow copy with title replaced
-- by a styled value baking in the enabled aware colour, the font, the size and the live
-- titleLineBreak. subTitle is replaced the same way when the row carries a real one, always cut
-- at the tail. Everything else on the row, item, enabled, image and filterText, icon and
-- iconOwner among them, passes through untouched. The icon is drawn by list render at paint, so
-- a row the engine holds never holds a picture of one.
local function styleRow(scene, row)
  local L = scene.layout
  local T = scene.tokens
  local face = scene.type
  local enabled = row.enabled ~= false
  local titleColor = enabled and T.colors.foreground or faded(T.colors.foreground, T.alpha.dim)
  local out = {}
  for k, v in pairs(row) do out[k] = v end
  out.title = styledText(row.title, face.textSize, titleColor, face.font, L.titleLineBreak)
  if row.subTitle and row.subTitle ~= "" then
    local subColor = enabled and T.colors.subtext or faded(T.colors.subtext, T.alpha.dim)
    out.subTitle = styledText(row.subTitle, face.subSize, subColor, face.subFont, "truncateTail")
  end
  return out
end

--------------------------------------------------------------------------------
-- Instance
--------------------------------------------------------------------------------

local View = {}
View.__index = View

--- View colon restyle, arity zero. Derives the field's own style table and the list's own style
--- table from the scene's tokens. caretColor is left unset on purpose, field render's own
--- fallback to textColor already reads well.
function View:restyle()
  local s = self.engine:scene()
  local T = s.tokens
  self._fieldStyle = {
    font = s.type.fieldFont,
    fontSize = s.type.fieldSize,
    textColor = T.colors.foreground,
    selectionColor = T.colors.highlight,
    placeholderColor = faded(T.colors.foreground, T.alpha.dim),
    caretWidth = s.layout.caretWidth,
    measure = UI.measure,
  }
  self._listStyle = {
    titleColor = T.colors.foreground,
    subColor = T.colors.subtext,
    highlightColor = T.colors.highlight,
    -- The highlight sits marginX inside the surface's edge, so its corners nest inside the
    -- surface's own, one rule for every rounded thing drawn inside a rounded surface.
    highlightRadius = UI.nestedRadius(T.radius.surface, s.layout.marginX),
    numberColor = T.colors[T.text.section.color],
    dimAlpha = T.alpha.dim,
    -- Read late through the module level, so a configure after this view was built applies.
    iconElements = function(icon, owner, frame)
      return ICON_ELEMENTS and ICON_ELEMENTS(icon, owner, frame) or nil
    end,
    -- The shared empty state, in the caption role and the subtext colour, list render deciding
    -- when it shows.
    emptyState = function(w, h)
      return PANEL and PANEL.emptyStateElements(w, h, { text = NO_RESULTS }) or {}
    end,
  }
end

--- View colon place, arity one. With a companion the surface spans rects.canvas, the gap and
--- rects.companion as one shape, the swift view's layout, and a docked pane placed on that
--- companion rect draws into it, see M.paneBackend. With none it is the canvas rect alone.
function View:place(rects)
  local window = spanOf(rects.canvas, rects.companion)
  self._window = window or rects.canvas
  -- Kept across a hide, the companion rect this view last reported, which a pane's backend
  -- matches its own rect against, so a pane painted as the list reopens lands here.
  self._companion = window and rects.companion or nil
  self.surface:setFrame(self._window)
end

--- View colon spansFooter, arity zero. True, since the surface spans the canvas, the gap and the
--- companion, so the action bar runs under the list and the docked pane alike, as in swift.
function View:spansFooter()
  return true
end

--- View colon footerHeight, arity one. The bar's region, a row as tall as the default bar's and
--- the bar pad below it, the swift view's own answer, so the two choosers share every rect.
function View:footerHeight(tokens)
  return footerLib.height(tokens) + tokens.pad
end

-- Whether this view hosts a pane placed at rect, its last companion rect while it spans one.
function View:_hostsFrame(rect)
  return self._companion ~= nil and sameRect(self._companion, rect)
end

-- A hosted pane's content, in the pane's own space, or nil to draw none. Redrawn at once while
-- the surface is up, and otherwise drawn with the next redraw.
function View:_setPaneContent(content)
  self._paneContent = content
  if self:isVisible() then self:redraw() end
end

--- View colon presentRows, arity one. The ranked rows styled for list render, see styleRow.
function View:presentRows(rows)
  local s = self.engine:scene()
  local out = {}
  for i = 1, #rows do
    out[i] = styleRow(s, rows[i])
  end
  return out
end

--- View colon text, arity zero. The field's own current text.
function View:text()
  return self.field:getState().text
end

--- View colon setText, arity one. Replaces the field's text, caret after it, which reports the
--- change to the engine through the field's own onChange before it returns.
function View:setText(text)
  self.field:setText(text)
end

--- View colon feedKey, arity one. A key heard by another route, taking exactly the path a
--- tapped one takes.
function View:feedKey(ev)
  self.field:feed(ev)
end

--- View colon redraw, arity zero. Draws the field, the rows and the action bar from the scene.
function View:redraw()
  local s = self.engine:scene()
  if not s.rects then return end
  local origin = self._window or s.rects.canvas
  local fieldRect = toLocal(s.rects.field, origin)
  local listRect = toLocal(s.rects.list, origin)
  local els = {}
  if not s.bare then
    local fieldState = self.field:getState()
    for _, el in ipairs(fieldRender.elements(fieldState, fieldRect, self._fieldStyle, self._caretVisible, s.placeholder)) do
      els[#els + 1] = el
    end
  end
  -- The band is cut at the inside of the border, so a row scrolled past the bottom stops at
  -- the edge of the surface and never draws over the border line.
  local clip = listRect
  local interior = self.surface:interior()
  if interior then
    local bottom = math.min(listRect.y + listRect.h, interior.y + interior.h)
    clip = { x = listRect.x, y = listRect.y, w = listRect.w, h = math.max(0, bottom - listRect.y) }
    -- The interior's rounded outline as a second clip, so a row cut by the bottom edge is cut
    -- along the surface's curve at the corners rather than poking past it.
    if (interior.radius or 0) > 0 then clip.round = interior end
  end
  for _, el in ipairs(listRender.elements(s.list, listRect, s.drawLayout, self._listStyle, clip, s.rankedQuery)) do
    els[#els + 1] = el
  end
  self:_paneElements(s, els, origin)
  self:_footerElements(s, els, origin, interior, listRect)
  self.surface:draw(els)
end

-- Appends the hairline between the list and the docked pane and the hosted pane's content to els,
-- in the window's own space, while the surface spans a companion. The hairline is the border role
-- at the border stroke, centred in the gap from the top down to the bar, and the content is cut
-- at the pane's own rect, so nothing it draws reaches the list or past the surface.
function View:_paneElements(s, els, origin)
  local companion = self._companion
  if not companion then return end
  local T = s.tokens
  local canvas = toLocal(s.rects.canvas, origin)
  local pane = toLocal(companion, origin)
  local left, right
  if pane.x >= canvas.x + canvas.w then left, right = canvas.x + canvas.w, pane.x
  else left, right = pane.x + pane.w, canvas.x end
  local width = T.stroke.border
  local footer = toLocal(s.rects.footer, origin)
  local bottom = footer and footer.y or (self._window.h)
  els[#els + 1] = { type = "rectangle", action = "fill", fillColor = T.colors.border,
    frame = { x = (left + right - width) / 2, y = 0, w = width, h = bottom } }
  local content = self._paneContent
  if not content then return end
  local clip = { type = "rectangle", action = "clip",
    frame = { x = pane.x, y = pane.y, w = pane.w, h = pane.h } }
  els[#els + 1] = clip
  for _, el in ipairs(content) do
    if el.type == "resetClip" then
      els[#els + 1] = el
      els[#els + 1] = clip
    else
      els[#els + 1] = shiftedElement(el, pane.x, pane.y, pane.w, pane.h)
    end
  end
  els[#els + 1] = { type = "resetClip" }
end

-- Appends the action bar, and the key panel above it when open, to els, in the canvas's own
-- coordinates. Both keep inside the surface's border, the interior's left and right edges, and
-- the bar's entries line up with the rows above, the list margin from the canvas's edge. The key
-- button's rect and the panel's are kept in screen points, the space the mouse handlers test in.
function View:_footerElements(s, els, origin, interior, listRect)
  self._keysHit, self._keysPanelRect = nil, nil
  local footerRect = toLocal(s.rects.footer, origin)
  if not footerRect or not s.footer then return end
  local band = footerRect
  if interior then
    band = { x = interior.x, y = footerRect.y, w = interior.w, h = footerRect.h }
  end
  local inset = math.max(0, s.layout.marginX - (band.x - footerRect.x))
  if s.keysOpen then
    local panelEls, panelRect = footerLib.keysPanel(UI, s.tokens, s.footer, band,
      math.max(0, band.y - listRect.y))
    for _, el in ipairs(panelEls) do els[#els + 1] = el end
    self._keysPanelRect = { x = panelRect.x + origin.x, y = panelRect.y + origin.y, w = panelRect.w, h = panelRect.h }
  end
  -- The key button's icon through the injected icon engine, read at paint like a row's, so it
  -- follows the light and dark halves. Without an engine the button keeps the ? glyph.
  local keysIcon = s.footer.keysIcon
  local keysImage = keysIcon and ICON and ICON(keysIcon.icon, keysIcon.owner) or nil
  local barEls, keysRect = footerLib.bar(UI, s.tokens, s.footer, band, inset,
    self._keysHover or s.keysOpen, keysImage)
  for _, el in ipairs(barEls) do els[#els + 1] = el end
  if keysRect then
    self._keysHit = { x = keysRect.x + origin.x, y = keysRect.y + origin.y, w = keysRect.w, h = keysRect.h }
  end
end

--- View colon show, arity zero. Reveals the surface.
function View:show()
  self.surface:show()
end

--- View colon start, arity zero. Arms the field tap and the mouse tap and starts the caret blink.
function View:start()
  self.field:start()
  self.mouse:start()
  self:_restartBlink()
end

--- View colon stop, arity zero. The two taps first, unconditionally, then the caret blink and
--- the scroll ease, the order the engine's teardown header gives.
function View:stop()
  self.field:stop()
  self.mouse:stop()
  self:_stopBlink()
  self:_stopScrollEase()
end

--- View colon stopScroll, arity zero. Ends a wheel's ease toward its target.
function View:stopScroll()
  self:_stopScrollEase()
end

--- View colon hide, arity zero. Forgets the pointer's press and hover and the hit rects of the
--- last draw, then hides the surface.
function View:hide()
  self._pressedRowIndex = nil
  self._keysHover = false
  self._keysHit, self._keysPanelRect = nil, nil
  self._paneContent = nil
  self.surface:hide()
end

--- View colon isVisible, arity zero. The surface's own isVisible.
function View:isVisible()
  return self.surface ~= nil and self.surface:isVisible()
end

--------------------------------------------------------------------------------
-- The caret blink
--------------------------------------------------------------------------------

-- Restarts the caret blink from visible, called on start and on every field change, the same
-- reset every keystroke gives it in probe-canvasfield.lua, so typing always reads as continuous.
-- Fix round item four. A setText can arrive while the list is not up at all, so this returns
-- whenever the engine is not active, which keeps a blink timer from ever starting outside an
-- open. A bare list draws no field and so no caret.
function View:_restartBlink()
  if not self.engine:isActive() or self.engine:posture() == "bare" then return end
  self._caretVisible = true
  if self._blinkTimer then self._blinkTimer:stop() end
  self._blinkTimer = hs.timer.doEvery(BLINK_INTERVAL, function()
    self._caretVisible = not self._caretVisible
    self:redraw()
  end)
end

function View:_stopBlink()
  if self._blinkTimer then
    self._blinkTimer:stop()
    self._blinkTimer = nil
  end
end

--------------------------------------------------------------------------------
-- Scrolling, lifted from probe-canvasfield.lua's own round five tap rather than reasoned out
-- again
--------------------------------------------------------------------------------

function View:_stopScrollEase()
  if self._scrollEaseTimer then
    self._scrollEaseTimer:stop()
    self._scrollEaseTimer = nil
  end
  self._scrollEaseTarget = nil
end

function View:_easeScrollStep()
  if not self._scrollEaseTarget then return end
  local current = self.engine:scene().list.scrollTop
  local remaining = self._scrollEaseTarget - current
  if math.abs(remaining) <= SCROLL_EASE_EPSILON then
    self.engine:scrollTo(self._scrollEaseTarget)
    self:_stopScrollEase()
    self:redraw()
    return
  end
  self.engine:scrollTo(current + remaining * SCROLL_EASE_FACTOR)
  self:redraw()
end

function View:_scrollByWheelNotch(deltaPoints)
  local list = self.engine:scene().list
  local base = self._scrollEaseTarget or list.scrollTop
  local target = base + deltaPoints
  local maxScroll = listModel.maxScrollTop(list)
  if target < 0 then target = 0 end
  if target > maxScroll then target = maxScroll end
  self._scrollEaseTarget = target
  if not self._scrollEaseTimer then
    self._scrollEaseTimer = hs.timer.doEvery(SCROLL_EASE_INTERVAL, function()
      self:_easeScrollStep()
    end)
  end
end

--------------------------------------------------------------------------------
-- Mouse
--------------------------------------------------------------------------------

-- The filtered index a screen point falls on, or nil when the point sits outside the list rect
-- entirely, answered by list model's own rowAtPoint from the point and the scroll.
function View:_rowIndexAtPoint(point)
  local s = self.engine:scene()
  local listRect = s.rects and s.rects.list
  if not pointInRect(point, listRect) then return nil end
  -- The key panel covers the bottom rows while it is up, so a point on it is on no row.
  if pointInRect(point, self._keysPanelRect) then return nil end
  return listModel.rowAtPoint(s.list, point.y - listRect.y)
end

-- A left or a right press. Outside this surface and outside its companion, if any, a LEFT press
-- hides the picker and does not claim the event, so the same press also reaches whatever the
-- person actually meant to click. A right press out there is left alone entirely, neither hiding
-- the picker nor being claimed, matching legacy.lua, whose own click watcher only ever looks at
-- left button events. Inside the companion, which this file draws none of, the press is left for
-- whatever owns that pane to answer. A right press on a row goes to the engine, which reads
-- config.onRightClick live. A left press records which row it landed on, for the matching
-- release to compare against.
function View:_onMouseDown(point, button)
  local rects = self.engine:scene().rects
  -- With a companion the window spans the canvas, the gap and the pane, so a press in the gap is
  -- on the surface and inside, as in swift.
  local insideWindow = pointInRect(point, self._window or (rects and rects.canvas))
  local insideCompanion = pointInRect(point, rects and rects.companion)
  if not insideWindow and not insideCompanion then
    if button == "left" then self.engine:hide() end
    return false
  end
  -- A press on the key button toggles the key panel, wherever the spanning bar put it. Any other
  -- press on the action bar or on the panel lands on no row, so it is claimed and chooses nothing.
  if button == "left" and pointInRect(point, self._keysHit) then
    self._pressedRowIndex = nil
    self.engine:toggleKeys()
    return true
  end
  if insideCompanion and not pointInRect(point, rects and rects.footer) then
    return false
  end
  if button == "right" then
    self.engine:rightClickIndex(self:_rowIndexAtPoint(point))
    return true
  end
  self._pressedRowIndex = self:_rowIndexAtPoint(point)
  return true
end

-- The release chooses the row the matching press landed on, only when the release lands on that
-- same row, ordinary click behaviour and also what legacy.lua's own click watcher measured the
-- real widget doing. A right release inside this surface is claimed too, purely so the down and
-- the up of the identical press agree about whether this surface owns it.
function View:_onMouseUp(point, button)
  local rects = self.engine:scene().rects
  local window = self._window or (rects and rects.canvas)
  if button == "right" then
    return pointInRect(point, window)
  end
  if button ~= "left" then return false end
  if not pointInRect(point, window) then
    self._pressedRowIndex = nil
    return false
  end
  local index = self:_rowIndexAtPoint(point)
  local pressed = self._pressedRowIndex
  self._pressedRowIndex = nil
  if index and pressed and index == pressed then
    self.engine:chooseIndex(index)
  end
  return true
end

-- A move over a row sets the highlight, which the native widget does for free on hover. Never
-- claimed, mouse.lua's own contract has onMove answer true to claim, and a plain hover claims
-- nothing.
function View:_onMouseMove(point)
  -- The key button lights under the pointer the way a row does, redrawn only as the pointer
  -- enters or leaves its rect, so a move anywhere else costs a comparison.
  local overKeys = pointInRect(point, self._keysHit)
  if overKeys ~= (self._keysHover == true) then
    self._keysHover = overKeys
    self:redraw()
  end
  local index = self:_rowIndexAtPoint(point)
  if index then self.engine:highlightIndex(index) end
end

-- A scroll over the list moves the viewport, never the highlight, a trackpad's continuous delta
-- followed directly and a wheel's coarse notch eased toward over a few ticks, both settled by
-- hand in round five. A scroll over the companion rect goes to the engine for config.onScroll.
function View:_onMouseScroll(point, dy, continuous)
  local rects = self.engine:scene().rects
  -- The open key panel covers the bottom rows, so a scroll over it is claimed and moves nothing,
  -- rather than scrolling a list the person cannot see under it.
  if pointInRect(point, self._keysPanelRect) then return true end
  if pointInRect(point, rects and rects.list) then
    self:_stopScrollEase()
    if continuous then
      self.engine:scrollBy(-dy)
      self:redraw()
    else
      self:_scrollByWheelNotch(-dy * WHEEL_NOTCH_POINTS)
    end
    return true
  end
  if pointInRect(point, rects and rects.companion) then
    self.engine:companionScroll(-dy)
    return true
  end
  return false
end

--------------------------------------------------------------------------------
-- Wiring, called once at construction
--------------------------------------------------------------------------------

-- Builds the mouse tap, dispatching by button and by rect the way the header above each handler
-- explains.
local function buildMouse(self)
  return Mouse.new({
    onDown = function(point, button) return self:_onMouseDown(point, button) end,
    onUp = function(point, button) return self:_onMouseUp(point, button) end,
    onMove = function(point)
      self:_onMouseMove(point)
      return false
    end,
    onScroll = function(point, dy, continuous) return self:_onMouseScroll(point, dy, continuous) end,
  })
end

-- Builds the field, wiring each of its callbacks to the engine call at the same place in the key
-- order. A field change restarts the caret blink before the engine hears of it.
local function buildField(self)
  local engine = self.engine
  return Field.new({
    text = "",
    onChange = function(state)
      self:_restartBlink()
      engine:fieldChanged(state.text)
    end,
    onKey = function(ev) engine:leftoverKey(ev) end,
    onDismiss = function(ev) engine:dismissKey(ev) end,
    onEmptyBackspace = function() engine:emptyBackspace() end,
    yields = function(ev) return engine:yieldsKey(ev) end,
    listKeys = function(ev) return engine:listKey(ev) end,
  })
end

--------------------------------------------------------------------------------
-- Module surface
--------------------------------------------------------------------------------

local M = {}

--- M.configure(opts) takes opts.panel, opts.ui, opts.icon and opts.iconElements. Callable more
--- than once, a nil field left unchanged, matching CanvasPanel.configure's own idiom.
function M.configure(opts)
  opts = opts or {}
  if opts.panel ~= nil then PANEL = opts.panel end
  if opts.ui ~= nil then UI = opts.ui end
  if opts.icon ~= nil then ICON = opts.icon end
  if opts.iconElements ~= nil then ICON_ELEMENTS = opts.iconElements end
  return M
end

--- M.iconsChanged() redraws every view on screen, since a row's icon is resolved at paint and a
--- picture that was still being made may exist now.
function M.iconsChanged()
  for view in pairs(views) do
    if view:isVisible() then view:redraw() end
  end
end

--- M.paneBackend(fallback) -> a docked pane backend factory, see lib/dockedpane.lua, that draws a
--- pane's content inside a canvas chooser spanning its rect, the list and the pane as one surface,
--- and through fallback, the plain canvas backend's factory, anywhere else. The surface is the
--- chooser's, so a hosted pane's own surface list is left out. Which one draws is asked again on
--- every place, the canvas counterpart of chooserHosting in the swift library. A panel, handed a
--- window, is never hosted.
function M.paneBackend(fallback)
  return function(frame, window)
    if window then return fallback(frame, window) end
    local own, host, shown, content = nil, nil, false, nil
    local function ownBackend()
      if not own then own = fallback(frame) end
      return own
    end
    local function hostFor(rect)
      for view in pairs(views) do
        if view:_hostsFrame(rect) then return view end
      end
      return nil
    end
    local backend = {}
    function backend.place(rect)
      local next = hostFor(rect)
      if next ~= host then
        if host then host:_setPaneContent(nil) end
        if next and own then own.hide() end
        host = next
      end
      if not host then ownBackend().place(rect) end
    end
    function backend.render(surface, elements)
      content = elements
      if host then
        if shown then host:_setPaneContent(content) end
      else
        ownBackend().render(surface, elements)
      end
    end
    function backend.show()
      shown = true
      if host then host:_setPaneContent(content) else ownBackend().show() end
    end
    function backend.hide()
      shown = false
      if host then host:_setPaneContent(nil) end
      if own then own.hide() end
    end
    function backend.isShowing()
      if host then return shown and host:isVisible() end
      return own ~= nil and own.isShowing()
    end
    function backend.destroy()
      if host then host:_setPaneContent(nil) end
      host, shown, content = nil, false, nil
      if own then own.destroy() end
      own = nil
    end
    return backend
  end
end

--- M.fieldOp(keyCode, flags) -> the name of the editing operation the field's own keymap reads
--- on exactly those modifiers, or nil, for the engine's uses.
function M.fieldOp(keyCode, flags)
  return fieldInput.keymap.resolve(keyCode, flags)
end

--- M.new(engine) answers a view for one engine instance, its surface, its mouse tap and its field
--- built and nothing armed.
function M.new(engine)
  local self = setmetatable({
    engine = engine,
    _pressedRowIndex = nil,
    _caretVisible = true,
  }, View)
  self.surface = Surface.new({ panel = PANEL })
  self.mouse = buildMouse(self)
  self.field = buildField(self)
  views[self] = true
  return self
end

return M
