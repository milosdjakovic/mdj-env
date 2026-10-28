--- === Swift view ===
---
--- The swift chooser's view, the Lua half of a native panel. It satisfies lib/chooser/view.lua
--- the way lib/chooser/providers/default/canvas.lua does, and it is a Humble Object over the
--- Swift library in native/. It keeps no rule of its own. Each contract method turns the
--- engine's scene into plain data and hands it to the library, and each event the library sends
--- back is turned into the one engine call the view contract names for it. What a key means,
--- what choosing does and when anything fires stay in lib/chooser/engine/init.lua.
---
--- Everything Swift draws with comes from here, and everything here comes from the UI kit's
--- tokens through the engine's scene, the colour roles, the type roles' fonts and sizes, the
--- surface radius and the space steps, and from the engine's geometry, the rectangles and the
--- row metrics. No colour, font or size is written in this file or in the Swift sources, so a
--- theme or a typography change reaches the native panel exactly as it reaches the canvas.
---
--- The key order is run on the Swift side, since the field's editing sits in the middle of it
--- and the field is native. Swift asks dismiss, yields and listKey before its field edits,
--- emptyBackspace for a backspace on an empty field, and leftover after, and native/Panel.swift's
--- header says exactly which key goes where. Each event carries the key as the bytes of its
--- event, which hs.eventtap.event.newEventFromData turns back into the event the engine reads,
--- its key code, its flags and its autorepeat bit, the same object a tap would have handed it.
---
--- A press outside the panel is reported with its point and decided here, against the engine's
--- rects. A press inside the companion rect, or in the gap between it and the canvas, keeps the
--- list and asks the panel to take key again, and any other left press hides it. The gap is
--- inside on purpose, since with a companion the panel's one shape of glass spans it, which is
--- the one place this differs from the canvas view. A scroll over the companion is claimed
--- by a scroll wheel tap this view runs while it is started, the way the canvas view's mouse tap
--- claims it, since an event monitor in Swift could only watch it go by and the window under the
--- pointer would scroll too. The one exception is a docked pane drawn in this panel's own window,
--- which is a native scroll view, so a scroll over it is left to AppKit, which hands it to that
--- view with its momentum. View colon _onScroll is the one place the tap and the hosting meet,
--- and it asks the panel, through native.hostsPane, rather than knowing where a pane is drawn.
---
--- View.configure(opts) takes opts.ui, the UI kit, and opts.icon, the icon resolver. View.attach
--- (native) points the library's one callback at this file's dispatch. View.new(engine, native)
--- builds a view, and with it a panel of its own, for one engine instance.

local herePath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(relPath)
  local chunk, err = loadfile(herePath .. relPath)
  if not chunk then
    error("Swift view: failed to load " .. relPath .. ", " .. tostring(err))
  end
  return chunk()
end

-- THE SEAM, the same one the engine names. The list model and the geometry are pure and still
-- live beside the canvas view, where the engine loads them from. This view reads the model for
-- which rows are on screen, to number them, and the geometry for the icon's padding in a row.
local listModel = load("../default/list/model.lua")
local geometry = load("../default/geometry.lua")
local fieldKeys = load("fieldkeys.lua")

-- The injected UI kit, read for the nested radius, nil until View.configure runs.
local UI = nil

-- The injected icon resolver, function(icon, owner) -> hs.image or nil, read at every draw so a
-- light and dark switch reaches a row's icon with nothing watching for it.
local ICON = nil

-- What the list says when a typed query left no rows, the canvas view's own words.
local NO_RESULTS = "No results"

-- Every view built so far, by the id its panel answered, so the one callback finds its view.
local views = {}

--------------------------------------------------------------------------------
-- Small stateless helpers
--------------------------------------------------------------------------------

-- A colour with its alpha multiplied, how a disabled row and the placeholder are dimmed.
local function faded(color, factor)
  local c = {}
  for k, v in pairs(color or {}) do c[k] = v end
  c.alpha = (c.alpha or 1) * factor
  return c
end

local function pointInRect(point, rect)
  return rect ~= nil
    and point.x >= rect.x and point.x < rect.x + rect.w
    and point.y >= rect.y and point.y < rect.y + rect.h
end

local function toLocal(rect, origin)
  if not rect then return nil end
  return { x = rect.x - origin.x, y = rect.y - origin.y, w = rect.w, h = rect.h }
end

-- The span from the canvas rect to the companion rect, the gap between them included, or nil
-- with no companion.
local function spanOf(canvas, companion)
  if not (canvas and companion) then return nil end
  local x0, y0 = math.min(canvas.x, companion.x), math.min(canvas.y, companion.y)
  local x1 = math.max(canvas.x + canvas.w, companion.x + companion.w)
  local y1 = math.max(canvas.y + canvas.h, companion.y + companion.h)
  return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

-- The window the panel stands in, the canvas rect alone or the span to the companion, and where
-- the list's content, the docked pane's region and the hairline divider sit inside it, in the
-- window's own space with y measured down. The divider is width points wide, centred in the gap
-- between the two, from the top of the window to the bottom.
local function windowRects(canvas, companion, width)
  local window = spanOf(canvas, companion)
  if not window then
    return canvas, { x = 0, y = 0, w = canvas.w, h = canvas.h }, nil, nil
  end
  local list, pane = toLocal(canvas, window), toLocal(companion, window)
  local left, right
  if pane.x >= list.x + list.w then left, right = list.x + list.w, pane.x
  else left, right = pane.x + pane.w, list.x end
  local divider = { x = (left + right - width) / 2, y = 0, w = width, h = window.h }
  return window, list, pane, divider
end

local function font(name, size)
  return { name = name, size = size }
end

-- A title or subtitle as a plain string, since a consumer may hand an hs.styledtext value.
local function plain(value)
  if value == nil then return "" end
  if type(value) == "string" then return value end
  if type(value) == "userdata" and value.getString then return value:getString() end
  return tostring(value)
end

-- The event a key's bytes describe, the one hs.eventtap.event the engine reads.
local function eventOf(data)
  if type(data) ~= "string" then return nil end
  return hs.eventtap.event.newEventFromData(data)
end

--------------------------------------------------------------------------------
-- Instance
--------------------------------------------------------------------------------

local View = {}
View.__index = View

--- View colon restyle, arity zero. The colours and fonts of the scene's tokens, handed to Swift.
function View:restyle()
  local s = self.engine:scene()
  local T, face = s.tokens, s.type
  local text = T.text
  self.native.style(self.id, {
    text = T.colors.foreground,
    textDim = faded(T.colors.foreground, T.alpha.dim),
    sub = T.colors.subtext,
    subDim = faded(T.colors.subtext, T.alpha.dim),
    highlight = T.colors.highlight,
    number = T.colors[text.section.color],
    background = T.colors.background,
    caption = T.colors[text.caption.color],
    badge = T.colors[text.section.color],
    divider = T.colors.border,
    fieldFont = font(face.fieldFont, face.fieldSize),
    titleFont = font(face.font, face.textSize),
    subFont = font(face.subFont, face.subSize),
    numberFont = font(face.numFont, face.numSize),
    captionFont = font(text.caption.font, text.caption.size),
    badgeFont = font(text.section.font, text.section.size),
    radius = T.radius.surface,
    highlightRadius = UI.nestedRadius(T.radius.surface, s.layout.marginX),
  })
end

--- View colon place, arity one. With a companion the panel's one shape of glass spans
--- rects.canvas, the gap and rects.companion, the list's content on the canvas rect, the docked
--- pane's region on the companion and a hairline of the kit's border width in the middle of the
--- gap, and with none it is the canvas rect alone. The field, the list and the bar go on the engine's own rects
--- inside the canvas, in the canvas's own space as before, with the row metrics of the layout the
--- list is drawn to. The companion is handed over in screen space too, since a docked pane is
--- matched to this panel on it.
function View:place(rects)
  local s = self.engine:scene()
  local L, T = s.drawLayout, s.tokens
  local origin = rects.canvas
  local iconPad, iconPadLeft = geometry.iconPad(L)
  local window, listFrame, paneFrame, dividerFrame = windowRects(rects.canvas, rects.companion,
    T.stroke.border)
  self.native.place(self.id, {
    canvas = rects.canvas,
    window = window,
    listFrame = listFrame,
    paneFrame = paneFrame,
    dividerFrame = dividerFrame,
    companion = rects.companion,
    field = toLocal(rects.field, origin),
    list = toLocal(rects.list, origin),
    footer = toLocal(rects.footer, origin),
    rowH = L.rowH,
    iconSize = L.iconSize,
    iconFrame = L.iconFrame or L.iconSize,
    iconPad = iconPad,
    iconPadLeft = iconPadLeft,
    iconGap = L.iconGap,
    padX = L.padX,
    numW = L.numW or L.iconSize,
    padBottom = L.padBottom or 0,
    showNumbers = L.showRowNumbers == true,
    barInset = s.layout.marginX,
    barGap = T.space.s,
    barGapWide = T.space.l,
    keysIcon = T.text.section.lineHeight,
    keysPad = T.pad,
  })
end

--- View colon presentRows, arity one. The rows as they came, in a list of their own, since Swift
--- is handed plain strings at draw time rather than a styled value the engine would hold.
function View:presentRows(rows)
  local out = {}
  for i = 1, #rows do out[i] = rows[i] end
  return out
end

--- View colon text, arity zero. The native field's text.
function View:text()
  return self.native.text(self.id)
end

--- View colon setText, arity one. Replaces the field's text, caret after it, and tells the engine
--- before returning, since a native field reports no change made by code.
function View:setText(text)
  self.native.setText(self.id, text or "")
  self.engine:fieldChanged(self.native.text(self.id))
end

--- View colon feedKey, arity one. A key heard by another route, handed to the panel as its bytes
--- so it takes the path a typed one takes. Nothing relays one today, since the swift provider
--- is handed no focus hold, but the contract asks for it.
function View:feedKey(ev)
  self.native.feedKey(self.id, ev:asData())
end

-- The row a disabled or enabled title and its picture become for Swift. icon is the picture this
-- view resolved for the row's icon key, or nil while the row has not been near the viewport.
local function rowData(row, icon)
  local image = row.image
  if image == nil then image = icon or nil end
  return { title = plain(row.title), subtitle = plain(row.subTitle), enabled = row.enabled ~= false,
    image = image }
end

-- The rows whose icon is resolved, the ones the viewport shows and one viewport's worth past each
-- edge, so a scroll of up to a page lands on rows that already carry their picture. Answers the
-- first and the last index, or 1 and 0 for an empty list. The canvas view resolves an icon only
-- for a row it paints, and this is the same rule for a list Swift scrolls on its own.
local function iconWindow(ns)
  local visible = listModel.visibleRows(ns)
  if #visible == 0 then return 1, 0 end
  local first, last = visible[1].index, visible[#visible].index
  local margin = #visible
  return math.max(1, first - margin), math.min(#ns.filtered, last + margin)
end

-- The footer model flattened to strings, a key panel entry's badges joined into one chord.
local function footerData(model)
  if not model then return nil end
  local right, keys = {}, {}
  for _, r in ipairs(model.right or {}) do right[#right + 1] = { label = r.label or "", chord = r.chord or "" } end
  for _, k in ipairs(model.keys or {}) do
    keys[#keys + 1] = { label = k.label or "", chord = table.concat(k.badges or {}, " ") }
  end
  local icon = model.keysIcon
  return { right = right, keys = keys, keysChord = model.keysChord,
    keysImage = icon and ICON and ICON(icon.icon, icon.owner) or nil }
end

-- Resolves the icon of every row from lo to hi not asked yet, through the injected resolver, and
-- remembers each answer by index, false for a row with nothing to resolve or nothing drawn yet.
-- Answers true when a row gained a picture the panel does not have.
function View:_resolveIcons(rows, lo, hi)
  local gained = false
  for i = lo, hi do
    if self._icons[i] == nil then
      local row = rows[i]
      local image = nil
      if row and row.image == nil and row.icon ~= nil and ICON then
        image = ICON(row.icon, row.iconOwner)
      end
      self._icons[i] = image or false
      if image then gained = true end
    end
  end
  return gained
end

--- View colon redraw, arity zero. Sends the rows when the engine holds a new list, or when rows
--- that came near the viewport gained their icon, then the state the scene says now. An icon is
--- resolved only for a row in iconWindow, so opening a long list draws a few pages of icons and
--- not its whole catalog, and a scroll, which reaches here through the engine, resolves the rows
--- it brings near. Nothing before the first place.
function View:redraw()
  local s = self.engine:scene()
  if not s.rects then return end
  local ns = listModel.normalized(s.list)
  local fresh = ns.filtered ~= self._sentRows
  if fresh then
    self._sentRows = ns.filtered
    self._icons = {}
  end
  local lo, hi = iconWindow(ns)
  local gained = self:_resolveIcons(ns.filtered, lo, hi)
  if fresh or gained then
    local rows = {}
    for i, row in ipairs(ns.filtered) do rows[i] = rowData(row, self._icons[i]) end
    self.native.setRows(self.id, rows)
  end
  local slots = {}
  if s.drawLayout and s.drawLayout.showRowNumbers then
    for slot, entry in ipairs(listModel.visibleRows(ns)) do
      if slot > 9 then break end
      slots[slot] = entry.index
    end
  end
  local empty = type(s.rankedQuery) == "string" and s.rankedQuery ~= "" and #ns.filtered == 0
  self.native.update(self.id, {
    highlight = ns.highlight or 0,
    scrollTop = ns.scrollTop,
    placeholder = s.placeholder or "",
    bare = s.bare == true,
    slots = slots,
    empty = empty,
    emptyText = NO_RESULTS,
    lineBreak = s.layout.titleLineBreak,
    footer = (not s.bare) and footerData(s.footer) or nil,
    keysOpen = s.keysOpen == true,
  })
end

--- View colon show, arity zero.
function View:show()
  self.native.show(self.id)
end

-- The scroll deltas lib/chooser/providers/default/mouse.lua reads, the point delta for a
-- trackpad and the line delta for a wheel.
local function scrollDelta(ev)
  local props = hs.eventtap.event.properties
  local continuous = ev:getProperty(props.scrollWheelEventIsContinuous) ~= 0
  if continuous then return ev:getProperty(props.scrollWheelEventPointDeltaAxis1) end
  return ev:getProperty(props.scrollWheelEventDeltaAxis1)
end

-- A scroll anywhere on screen, claimed and handed to the engine only over the companion rect, the
-- canvas view's rule. Everywhere else it passes on untouched, the panel's own list included.
--
-- THE COUPLING between this tap and where the docked pane is drawn lives here and nowhere else.
-- While this panel's window holds a shown native pane, the companion rect is that window and the
-- pane in it is a scroll view, so the event is left alone for AppKit to hand it, momentum and all.
-- Claiming it would delete it before the window saw it. A canvas pane, or a native pane standing
-- in a window of its own, is not hosted here, so the scroll is claimed as before, the app
-- underneath never scrolls, and the engine hands it to the pane's scrollBy.
function View:_onScroll(ev)
  local rects = self.engine:scene().rects
  if not pointInRect(ev:location(), rects and rects.companion) then return false end
  if self.native.hostsPane(self.id) then return false end
  local dy = scrollDelta(ev)
  if not dy or dy == 0 then return false end
  self.engine:companionScroll(-dy)
  return true
end

--- View colon start, arity zero. The panel starts routing keys and watching for a press outside,
--- and the scroll tap starts.
function View:start()
  self.native.start(self.id)
  if not self._scrollTap then
    self._scrollTap = hs.eventtap.new({ hs.eventtap.event.types.scrollWheel }, function(ev)
      local ok, claimed = pcall(self._onScroll, self, ev)
      if not ok then
        print("Olm swift view, a companion scroll failed, " .. tostring(claimed))
        return false
      end
      return claimed
    end)
    self._scrollTap:start()
  end
end

--- View colon stop, arity zero. Key routing, the outside watchers and the scroll tap end. The
--- native panel runs no timer of its own, the caret blink being the system's.
function View:stop()
  self.native.stop(self.id)
  if self._scrollTap then
    self._scrollTap:stop()
    self._scrollTap = nil
  end
end

--- View colon stopScroll, arity zero. Nothing to stop, since the scrolling is the system's own and
--- runs no animation this file started.
function View:stopScroll()
end

--- View colon hide, arity zero. Hides the panel, which forgets a press in progress.
function View:hide()
  self.native.hide(self.id)
end

--- View colon isVisible, arity zero.
function View:isVisible()
  return self.native.isVisible(self.id) == true
end

--------------------------------------------------------------------------------
-- Events from the panel, each one engine call
--------------------------------------------------------------------------------

-- A left press outside the panel. Inside the companion rect, or in the gap between it and the
-- canvas, which is glass of this panel's own window, it keeps the list up and gives the panel key
-- again, since the press may have taken it, and anywhere else it hides the list. The gap is
-- inside only while there is a companion, and only here, since the canvas view draws nothing
-- there and still hides for a press in it.
function View:_pressOutside(x, y)
  local rects = self.engine:scene().rects
  local point = { x = x, y = y }
  if pointInRect(point, rects and rects.canvas) then return end
  if pointInRect(point, rects and spanOf(rects.canvas, rects.companion)) then
    self.native.refocus(self.id)
    return
  end
  self.engine:hide()
end

local handlers = {
  text = function(v, text) v.engine:fieldChanged(text or "") end,
  dismiss = function(v, data) v.engine:dismissKey(eventOf(data)) end,
  yields = function(v, data)
    local ev = eventOf(data)
    return ev ~= nil and v.engine:yieldsKey(ev) == true
  end,
  listKey = function(v, data)
    local ev = eventOf(data)
    return ev ~= nil and v.engine:listKey(ev) == true
  end,
  emptyBackspace = function(v) v.engine:emptyBackspace() end,
  leftover = function(v, data)
    local ev = eventOf(data)
    if ev then v.engine:leftoverKey(ev) end
  end,
  hover = function(v, index) v.engine:highlightIndex(index) end,
  choose = function(v, index) v.engine:chooseIndex(index) end,
  rightClick = function(v, index) v.engine:rightClickIndex(index) end,
  -- A native scroll moved the viewport, so the engine's model follows it, and the redraw renumbers
  -- the rows now on screen.
  scroll = function(v, y)
    v.engine:scrollTo(y)
    v:redraw()
  end,
  toggleKeys = function(v) v.engine:toggleKeys() end,
  pressOutside = function(v, x, y) v:_pressOutside(x, y) end,
}

--------------------------------------------------------------------------------
-- Module surface
--------------------------------------------------------------------------------

local M = {}

--- M.dispatch(id, event, ...) -> boolean
--- The library's one callback. Finds the view by its panel's id and runs the handler for event,
--- answering its boolean, false for an unknown id or event.
function M.dispatch(id, event, ...)
  local view = views[id]
  local handler = handlers[event]
  if not view or not handler then return false end
  return handler(view, ...) == true
end

--- M.iconsChanged() makes every view resolve its icons again, since a picture that was still
--- being made may exist now. A view on screen redraws at once, and one that is hidden resends
--- its rows on its next draw.
function M.iconsChanged()
  for _, view in pairs(views) do
    view._sentRows = nil
    if view:isVisible() then view:redraw() end
  end
end

--- M.configure(opts) takes opts.ui and opts.icon. Callable more than once, a nil field left
--- unchanged.
function M.configure(opts)
  opts = opts or {}
  if opts.ui ~= nil then UI = opts.ui end
  if opts.icon ~= nil then ICON = opts.icon end
  return M
end

--- M.attach(native) registers dispatch as the loaded library's callback, once per load.
function M.attach(native)
  native.setCallback(M.dispatch)
end

--- M.new(engine, native) answers a view for one engine instance, with a panel of its own, built
--- and not yet placed or shown.
function M.new(engine, native)
  local self = setmetatable({ engine = engine, native = native, _sentRows = nil, _icons = {} }, View)
  self.id = native.new()
  views[self.id] = self
  native.setFieldKeys(self.id, fieldKeys.controlKeys())
  return self
end

return M
