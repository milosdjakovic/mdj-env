--- === Canvas picker provider ===
---
--- Section two of docs/BRIEF-CANVAS-PROVIDER.md, phase three c of the canvas chooser
--- track. Read docs/CONTRACT-PICKER.md first, it is the specification this file
--- satisfies, and this header only restates the decisions that shape the code below
--- rather than repeating that document whole.
---
--- Everything this file stands on already exists and is left untouched. geometry.lua
--- answers the arithmetic for where every rectangle sits, surface.lua owns the window,
--- mouse.lua owns the mouse tap, field is a complete text field, list is a complete row
--- list, lib/chooser/contract.lua says what a provider must offer, lib/chooser/rank.lua
--- answers the ranking policy both providers now share, and the UI kit's measurer
--- measures text. This file is mostly wiring those six pieces
--- together into one instance satisfying the picker contract, and the three places it
--- is not plain wiring are named where they happen below.
---
--- The first is ranking. list/model.lua carries its own matching through
--- lib/chooser/match.lua, built standalone before this provider existed, and if this
--- file let it run, every query would be filtered twice, once by the contract's own
--- live matcher and again by the list's own fuzzy strategy, silently ignoring a
--- presentation that set matcher to false to own its filtering, and silently answering
--- a different order than the native backend for the same query. So this file ranks
--- through lib/chooser/rank.lua itself, using the live matcher, and hands the already
--- ranked rows to the list model with an EMPTY query every time, so the list model
--- ranks nothing and only holds, highlights and scrolls what it was given. See
--- Provider colon underscore rebuildList below for where that happens, restated there
--- too since it reads like a bug to anyone who has not been told.
---
--- The second is teardown ordering. The field tap and the mouse tap are stopped first,
--- before anything else in Provider colon underscore teardown runs, and only then do
--- the timers, the surface and the state come down, and only then does onClose fire,
--- guarded so a raise inside it cannot abandon the rest of teardown. Commit 1ccab6f is
--- this configuration's own record of what a tap left believed armed costs on this
--- machine, a leader believed held rather than checked swallowing keys nobody meant to
--- lose, and a keyboard tap or a mouse tap left running here is the identical hazard.
---
--- The third is cmd with a digit. It chooses a VISIBLE slot, list model's own
--- rowAtVisibleSlot, one based from whatever row currently sits topmost on screen, and
--- not an index into the filtered set, the off by one the list round already carries a
--- test for. Every place in this file that turns a digit or a screen point into a row
--- keeps that distinction, a slot resolved through rowAtVisibleSlot or rowAtPoint,
--- never a bare filtered index guessed at by hand.
---
--- Rows here carry a title turned into an hs.styledtext value before this file ever
--- hands them to list render, baking in the enabled aware colour, the font, the size
--- and the truncation mode, the same shape legacy.lua's own styledText bakes before
--- handing a row to hs.chooser. geometry.lua's own header already measured that
--- hs.canvas honours a styled value's paragraphStyle exactly the way an ordinary macOS
--- text field does, a single ellipsis landing wherever the frame runs out of room
--- rather than a plain string sheared hard with none, and this is the one place that
--- measurement is put to use, since list/render.lua draws whatever sits under a row's
--- own title or subTitle key without asking what type it is. Subtitles are always cut
--- at the tail, matching what docs/CONTRACT-PICKER.md itself says titleLineBreak
--- governs the title alone. This part is beyond what section two's own task list names
--- outright, and it is called out in the build report as a deliberate reading of
--- geometry.lua's own groundwork rather than something asked for in so many words.
---
--- Colour and type come from the UI kit's tokens since stage two of
--- docs/DESIGN-UI-KIT.md, resolved for the current half on every show, and config.theme
--- is no longer read here. The text is foreground and the subtitle subtext, the field's
--- own selection band and the list's own row highlight are both the highlight token, a
--- disabled row and the placeholder are dimmed by the dim alpha, and the row numbers are
--- the section role's colour, subtext. The caret is left to
--- field render's own fallback, the text colour standing in for it. The font and the two
--- text sizes are the body and caption roles, handed to both renderers through the draw
--- layout, and the rest of the layout is geometry.lua's.
---
--- M.configure(opts) takes opts.panel, the CanvasPanel module, and opts.ui, the UI kit,
--- both injected here rather than loaded by path, since lib/panel.lua holds the shared
--- surface style and lib/ui the shared style the composition root configures exactly
--- once, and a second copy loaded fresh by path would answer an unconfigured module and
--- draw something that does not match every other surface in this configuration.
--- Whatever calls M.new is expected to have called M.configure first, the probe among
--- them, and M.new refuses with a plain reason when either is missing rather than
--- drawing something that looks subtly wrong.
---
--- What this file does not do. It does not touch host/stage/init.lua,
--- host/actionpanel/init.lua, root/compose.lua, any manifest, or any plugin. It is not
--- wired into lib/chooser/init.lua, the facade, which is phase four. And it delivers no
--- offline unit case of its own, this is a shell wiring real resources together and a
--- case built against a fake hs would only prove that the fake matched, so its
--- coverage is the live probe at Spoons/Olm.spoon/test/probe-canvaspicker.lua instead.

local herePath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(relPath)
  local chunk, err = loadfile(herePath .. relPath)
  if not chunk then
    error("Canvas provider: failed to load " .. relPath .. ", " .. tostring(err))
  end
  return chunk()
end

local geometry = load("geometry.lua")
local Surface = load("surface.lua")
local Mouse = load("mouse.lua")
local fieldInput = load("field/input.lua")
local Field = fieldInput.Field
local fieldRender = load("field/render.lua")
local listModel = load("list/model.lua")
local listRender = load("list/render.lua")

-- lib/chooser/rank.lua and lib/chooser/contract.lua sit two directories above this file,
-- providers up to chooser, the same siblings lib/chooser/providers/legacy.lua already
-- loads by the identical relative path.
local rank = load("../../rank.lua")
local contract = load("../../contract.lua")

--------------------------------------------------------------------------------
-- Module level constants
--------------------------------------------------------------------------------

-- The injected UI kit, lib/ui, nil until M.configure runs. Held at module level rather
-- than per instance, the same shape the injected panel below takes, since every instance
-- reads the one configured style. Declared up here because the instance methods read it.
local UI = nil

-- The injected predicate over a key down event, answering whether the key belongs to
-- something downstream of the field's tap and must pass on. Nil until M.configure runs,
-- and nil means the field claims everything. This file knows only that it is a predicate.
local YIELDS = nil

-- Return, keypad enter, up and down, the four keys the field's own keymap never
-- claims, so all four already reach this provider's onKey unclaimed rather than being
-- typed into the buffer as a stray character.
local KEYCODE_RETURN, KEYCODE_KEYPAD_ENTER = 36, 76
local KEYCODE_UP, KEYCODE_DOWN = 126, 125

-- The raw virtual keycodes for the digit keys one through nine, read from the running
-- config's own hs.keycodes.map the same way probe-canvasfield.lua's own header says
-- its identical table was derived, carried across from that probe rather than chosen
-- again, since cmd with a digit is named nowhere in field keymap.lua and reaches this
-- provider's onKey the same unclaimed way up and down already do.
local KEYCODE_DIGIT = {
  [18] = 1, [19] = 2, [20] = 3, [21] = 4, [23] = 5,
  [22] = 6, [26] = 7, [28] = 8, [25] = 9,
}

-- Round five's own scroll easing constants, settled by hand in
-- Spoons/Olm.spoon/test/probe-canvasfield.lua and carried across rather than chosen a
-- second time here, per the brief's own instruction. wheelNotchPoints is what one
-- wheel notch is worth in points, scrollEaseFactor is the fraction of the remaining
-- distance each tick closes, scrollEaseInterval is how often a tick runs, and
-- scrollEaseEpsilon is how close is close enough to snap the last short distance
-- rather than let the ease technically never finish.
local WHEEL_NOTCH_POINTS = 120
local SCROLL_EASE_FACTOR = 0.28
local SCROLL_EASE_INTERVAL = 1 / 60
local SCROLL_EASE_EPSILON = 0.5

-- The caret blink period, half a second on and half a second off, matching the field
-- probe's own timer, a plain literal rather than a setting since nothing in this tree
-- exposes one for it.
local BLINK_INTERVAL = 0.5

--------------------------------------------------------------------------------
-- Small stateless helpers, none of them touching self
--------------------------------------------------------------------------------

-- Runs fn inside a pcall and reports rather than raises, the same posture
-- field/input.lua and mouse.lua both already take toward a consumer callback. Used for
-- every config callback this file calls outward, so a mistake in a consumer's own code
-- is a print line rather than a stuck picker.
local function safeCall(fn, ...)
  if not fn then return nil end
  local ok, result = pcall(fn, ...)
  if not ok then
    print("Olm canvas provider, a consumer callback failed, " .. tostring(result))
    return nil
  end
  return result
end

-- The caller's own opaque item off a row, or nil for an empty highlight, the one field
-- onHighlight, onSelect, intercept and selectedItem all ever hand back, never the row
-- itself and never its now styled title.
local function rowItem(row)
  return row and row.item or nil
end

-- A colour with its alpha multiplied by factor, how a disabled row's title and the
-- placeholder are dimmed by the kit's dim alpha, a plain alpha cut rather than a second
-- colour a caller would have to supply.
local function faded(color, factor)
  local c = {}
  for k, v in pairs(color) do c[k] = v end
  c.alpha = (c.alpha or 1) * factor
  return c
end

-- Bakes a plain string into an hs.styledtext value carrying the font, the size, the
-- colour and a lineBreak, the identical shape legacy.lua's own styledText already
-- builds before handing a row to hs.chooser, restated here rather than reached for
-- since that file is the one this whole track leaves untouched.
local function styledText(str, size, color, font, lineBreak)
  return hs.styledtext.new(str or "", {
    font = { name = font, size = size },
    color = color,
    paragraphStyle = { lineBreak = lineBreak or "truncateTail" },
  })
end

-- Whether point sits inside rect, treated as closed at its own left and top edges and
-- open at its right and bottom ones, the identical convention geometry.lua's own
-- M.rowAtPoint already takes, and answering false outright for a nil rect so a caller
-- need not guard a missing companion rect itself.
local function pointInRect(point, rect)
  return rect ~= nil
    and point.x >= rect.x and point.x < rect.x + rect.w
    and point.y >= rect.y and point.y < rect.y + rect.h
end

-- Restates an absolute screen rect in a canvas's own local coordinates, subtracting
-- the canvas's own top left corner. geometry.resolve answers every rectangle in
-- absolute screen points, the same space mouse events and onPositioned both already
-- use, while an hs.canvas element is placed relative to its own canvas, so this is the
-- one conversion standing between the two, used only where this file draws rather
-- than where it hit tests, which stays in absolute terms throughout.
local function toLocal(rect, origin)
  if not rect then return nil end
  return { x = rect.x - origin.x, y = rect.y - origin.y, w = rect.w, h = rect.h }
end

--------------------------------------------------------------------------------
-- Instance
--------------------------------------------------------------------------------

local Provider = {}
Provider.__index = Provider

--------------------------------------------------------------------------------
-- Tokens, screen and the styles both renderers are handed
--------------------------------------------------------------------------------

-- The four roles the field and every row are drawn in, read only from the kit's tokens. The
-- field takes title, row titles body, row subtitles caption and the row shortcut body, the size of the title beside it. A line
-- is the role's own line height, except the subtitle's, which is the baseline step the row
-- rule derives, see lib/chooser/rowheight.lua.
-- A role's capital height from the real font metrics, nil with no measure so the row rule
-- falls back to its own estimate.
local function capOf(tokens)
  return UI.measure and function(role)
    local v = tokens.text[role]
    return UI.measure:metrics(v.font, v.size).capHeight
  end
end

local function typeOf(tokens)
  local text = tokens.text
  return {
    font = text.body.font,
    textSize = text.body.size,
    textLine = text.body.lineHeight,
    subFont = text.caption.font,
    subSize = text.caption.size,
    subLine = geometry.derivedRows(text, capOf(tokens)).subStep,
    numFont = text.body.font,
    numSize = text.body.size,
    fieldFont = text.title.font,
    fieldSize = text.title.size,
  }
end

-- Resolves the kit's tokens for the half the system is on now, the same moment the old
-- theme pick ran, so a light and dark switch is picked up at the next open rather than
-- mid session.
function Provider:_selectTheme()
  self._tokens = UI.tokens()
  self._type = typeOf(self._tokens)
end

-- Derives the field's own style table and the list's own style table from the tokens.
-- caretColor is left unset on purpose, field render's own fallback to textColor already
-- reads well and needs no derivation of its own.
function Provider:_deriveStyles()
  local T = self._tokens
  self._fieldStyle = {
    font = self._type.fieldFont,
    fontSize = self._type.fieldSize,
    textColor = T.colors.foreground,
    selectionColor = T.colors.highlight,
    placeholderColor = faded(T.colors.foreground, T.alpha.dim),
    caretWidth = self.layout.caretWidth,
  }
  self._listStyle = {
    titleColor = T.colors.foreground,
    subColor = T.colors.subtext,
    highlightColor = T.colors.highlight,
    numberColor = T.colors[T.text.section.color],
    dimAlpha = T.alpha.dim,
  }
end

-- The display this open should appear on, config.screen called once per show, falling
-- back to the main screen and then the primary one, the identical fallback chain
-- legacy.lua's own Chooser colon underscore resolveScreen already takes.
function Provider:_resolveScreen()
  local fn = self.config.screen
  local s = fn and fn()
  return s or hs.screen.mainScreen() or hs.screen.primaryScreen()
end

-- Fix round item six. geometry.resolve trims the requested row count to whatever the
-- screen can actually hold and answers the trimmed number as self._rects.rowCount,
-- sizing rects.list and the canvas from that trimmed number. self.layout is the
-- requested policy, the number rowCount() and setRows speak about, and it must stay
-- untrimmed for that reason, so this builds a separate per show copy carrying the
-- trimmed rowCount instead of writing over self.layout. Both listModel.newState and
-- listRender.elements read a layout's rowCount to decide how tall the viewport and the
-- clip band stand, so both must read this copy, never self.layout, or the two disagree
-- on a screen short enough to trim, roughly under five hundred and twenty four points of
-- frame height. The clip band would then stand taller than the list rect and rows would
-- draw past the bottom of the surface, maxScrollTop would be too small for the last rows
-- ever to be reached, and rowAtVisibleSlot would answer slots that are not on screen, so
-- cmd plus a digit would act on a row nobody can see. Called right after self._rects is
-- computed, in show and in reposition, which is every place this file computes a fresh
-- self._rects at all. The rider at the same root, setRows writing self.layout.rowCount
-- live while an already built listState and an already sized self._rects still carried
-- the old number, is closed by this same copy being rebuilt on every show, and costs
-- nothing today since the stage always hides before it resizes.
--
-- The draw layout also carries the three roles' fonts, sizes and line heights from the
-- tokens, the names list render reads off a layout, since geometry.lua holds no type.
function Provider:_updateDrawLayout()
  local L = {}
  for k, v in pairs(self.layout) do L[k] = v end
  -- The viewport holds the whole rows and the peek of one more, so the model scrolls and the
  -- renderer clips to that height. A fractional count is fine for both, they work in points.
  L.rowCount = self._rects.viewRows or self._rects.rowCount
  -- The margin under the list scrolls with the rows, see geometry.resolve.
  L.padBottom = self.layout.marginY
  for k, v in pairs(self._type) do L[k] = v end
  self._drawLayout = L
end

--------------------------------------------------------------------------------
-- Rows, ranking, and the styled title truncation bakes in for the list
--------------------------------------------------------------------------------

-- Turns one already ranked row into what list render actually draws, a shallow copy
-- with title replaced by a styled value baking in the enabled aware colour, the font,
-- the size and this instance's own titleLineBreak. subTitle is replaced the same way
-- when the row carries a real one, always cut at the tail regardless of
-- titleLineBreak, matching docs/CONTRACT-PICKER.md's own words that titleLineBreak
-- governs the title alone. Everything else on the row, item, enabled, image and
-- filterText among them, passes through untouched.
function Provider:_styleRow(row)
  local L = self.layout
  local T = self._tokens
  local face = self._type
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

-- Asks config.rows for the given query and ranks the answer through
-- lib/chooser/rank.lua against the live matcher, the shared policy both providers
-- read from one place now rather than each carrying a copy of it.
--
-- Fix round item one. config.rows is a consumer callback like every other one this
-- file calls outward, so it goes through safeCall and falls back to an empty list
-- rather than being called bare. A raise here used to unwind out of this call, out of
-- Provider colon underscore onFieldChange, out of Field colon underscore handle, past
-- its own return true, so the eventtap callback itself errored, Hammerspoon let the
-- event through unmodified, and the character a person just typed landed in the
-- application underneath while the picker stayed up showing a stale list. Field colon
-- underscore apply's own pcall never reached this, that pcall only wraps the model
-- mutation and the notify call that reads this file's own rebuilt list happens after
-- it returns, outside any guard field input.lua itself owns.
function Provider:_rankedRows(query)
  local items = safeCall(self.config.rows, query) or {}
  return rank.apply(items, query, self._matcher)
end

-- Rebuilds self.listState from config.rows(query), ranked through
-- lib/chooser/rank.lua and styled through colon underscore styleRow above, then handed
-- to list model with an EMPTY query, the ranking trap this whole file exists to avoid.
-- list/model.lua does its own matching through lib/chooser/match.lua, built standalone
-- before this provider existed, and letting it rank a second time behind this file's
-- own ranking would filter every query twice, once by the contract's own live matcher
-- and again by the list's own fuzzy strategy, silently ignoring a presentation that
-- set matcher to false to own its filtering and silently answering a different order
-- than the native backend for the same query. Handing over an empty query is what
-- keeps list model from ever calling its own matcher at all, it only holds, highlights
-- and scrolls whatever this file already decided the order should be.
--
-- resetHighlight true answers a fresh state, highlight on row one and scrollTop at the
-- top, list model's own newState. False preserves whatever row and scroll position
-- self.listState already held, clamped into whatever range the freshly ranked set can
-- support through list model's own normalized, rather than recomputed to keep that
-- row visible, since a preserved highlight was already on screen before this rebuild
-- and a shrunk list only needs clamping, not a fresh scroll animation. This is the
-- canvas answer to what legacy.lua's own refresh does by reading self.chooser colon
-- selectedRow back after rebuilding its choices.
--
-- The state this produces holds already styled rows, hs.styledtext values baked in by
-- colon underscore styleRow above, in both its rows and its filtered fields. list
-- model's own setQuery must never be called on this state. Nothing here does, the
-- empty query handed to newState is what keeps its internal ranking from running at
-- all, but a future caller reaching for setQuery on it would hand match.fuzzy a
-- haystack built by concatenating an hs.styledtext value into a string, which is not
-- what that function expects.
function Provider:_rebuildList(query, resetHighlight)
  local ranked = self:_rankedRows(query)
  local drawReady = {}
  for i = 1, #ranked do
    drawReady[i] = self:_styleRow(ranked[i])
  end
  if resetHighlight or not self.listState then
    self.listState = listModel.newState(drawReady, self._drawLayout, "")
    return
  end
  local prev = listModel.normalized(self.listState)
  self.listState = listModel.normalized({
    rows = drawReady, query = "", filtered = drawReady,
    highlight = prev.highlight, scrollTop = prev.scrollTop,
    rowH = prev.rowH, visibleCount = prev.visibleCount, padEnd = prev.padEnd,
  })
end

-- Reports the highlighted row's own opaque item through config.onHighlight, if one is
-- injected, read live on every call rather than captured once. This provider has no
-- poll of any kind, unlike the native one, since it knows the instant its own
-- highlight moves and calls this directly from wherever that happens.
function Provider:_fireHighlight()
  if not self.config.onHighlight then return end
  local row = listModel.highlightedRow(self.listState)
  safeCall(self.config.onHighlight, rowItem(row))
end

--------------------------------------------------------------------------------
-- Drawing and the caret blink
--------------------------------------------------------------------------------

function Provider:_redraw()
  if not self._rects then return end
  local origin = self._rects.canvas
  local fieldRect = toLocal(self._rects.field, origin)
  local listRect = toLocal(self._rects.list, origin)
  local els = {}
  local fieldState = self.field:getState()
  for _, el in ipairs(fieldRender.elements(fieldState, fieldRect, self._fieldStyle, self._caretVisible, self._placeholder)) do
    els[#els + 1] = el
  end
  -- The band is cut at the inside of the border, so a row scrolled past the bottom stops at
  -- the edge of the surface and never draws over the border line.
  local clip = listRect
  local interior = self.surface:interior()
  if interior then
    local bottom = math.min(listRect.y + listRect.h, interior.y + interior.h)
    clip = { x = listRect.x, y = listRect.y, w = listRect.w, h = math.max(0, bottom - listRect.y) }
  end
  for _, el in ipairs(listRender.elements(self.listState, listRect, self._drawLayout, self._listStyle, clip)) do
    els[#els + 1] = el
  end
  self.surface:draw(els)
end

-- Restarts the caret blink from visible, called on show and on every field change, the
-- same reset every keystroke gives it in probe-canvasfield.lua, so typing always reads
-- as continuous rather than as the caret happening to be in its off half already.
-- Fix round item four. setQuery can be called while this instance is not up at all,
-- and this function used to be reached unconditionally from every field change, so a
-- call arriving before the first show, or after a hide, armed a repeating timer
-- redrawing a hidden canvas that nothing would ever stop, since _teardown returns on
-- its own first line once active is already false. Returning here whenever active is
-- false is what keeps a blink timer from ever starting outside an open at all.
function Provider:_restartBlink()
  if not self.active then return end
  self._caretVisible = true
  if self._blinkTimer then self._blinkTimer:stop() end
  self._blinkTimer = hs.timer.doEvery(BLINK_INTERVAL, function()
    self._caretVisible = not self._caretVisible
    self:_redraw()
  end)
end

function Provider:_stopBlink()
  if self._blinkTimer then
    self._blinkTimer:stop()
    self._blinkTimer = nil
  end
end

--------------------------------------------------------------------------------
-- Scrolling, lifted from probe-canvasfield.lua's own round five tap rather than
-- reasoned out again, decision recorded at the top of this file
--------------------------------------------------------------------------------

function Provider:_stopScrollEase()
  if self._scrollEaseTimer then
    self._scrollEaseTimer:stop()
    self._scrollEaseTimer = nil
  end
  self._scrollEaseTarget = nil
end

function Provider:_easeScrollStep()
  if not self._scrollEaseTarget then return end
  local current = self.listState.scrollTop
  local remaining = self._scrollEaseTarget - current
  if math.abs(remaining) <= SCROLL_EASE_EPSILON then
    self.listState = listModel.scrollTo(self.listState, self._scrollEaseTarget)
    self:_stopScrollEase()
    self:_redraw()
    return
  end
  self.listState = listModel.scrollTo(self.listState, current + remaining * SCROLL_EASE_FACTOR)
  self:_redraw()
end

function Provider:_scrollByWheelNotch(deltaPoints)
  local base = self._scrollEaseTarget or self.listState.scrollTop
  local target = base + deltaPoints
  local maxScroll = listModel.maxScrollTop(self.listState)
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
-- Choosing a row, the one answer Return, cmd plus a digit, and a matching mouse press
-- and release all share
--------------------------------------------------------------------------------

-- Moves the highlight straight to index, an arbitrary row rather than one step away
-- from wherever it already sat, which is what a mouse hovering a row or a row about to
-- be chosen both need and neither moveDown nor moveUp can answer on their own. Leaves
-- scrollTop untouched, list model's own normalized only clamps it rather than
-- recentres it, matching what a hover is supposed to do, look without moving the
-- viewport.
function Provider:_setHighlightIndex(index)
  local ns = listModel.normalized(self.listState)
  if index < 1 or index > #ns.filtered then return end
  if index == ns.highlight then return end
  ns.highlight = index
  self.listState = listModel.normalized(ns)
  self:_fireHighlight()
  self:_redraw()
end

-- Chooses row, exactly what Return means, including asking config.intercept first and
-- honouring a disabled row. index, when known, is where in the filtered set row sits,
-- moved onto the highlight first so the row being chosen and the row reading as
-- highlighted never disagree, the same fact legacy.lua's own click watcher gets for
-- free from the widget moving its own selection on a click before this file's mouse
-- equivalent ever runs.
function Provider:_choose(row, index)
  if not row then return end
  if index then self:_setHighlightIndex(index) end
  local item = rowItem(row)
  local enabled = row.enabled ~= false
  if self.config.intercept then
    local answer = safeCall(self.config.intercept, item, enabled)
    if answer == true or answer == "stay" then
      self:refresh(answer ~= "stay")
      return
    end
  end
  if not enabled then return end
  if self.config.onSelect then safeCall(self.config.onSelect, item) end
  self:hide()
end

-- Cmd plus a digit chooses the VISIBLE slot that digit names, list model's own
-- rowAtVisibleSlot, one based from whatever row currently sits topmost on screen, and
-- not an index into the filtered set, the off by one the list round already carries a
-- test for and the third trap this whole file was built to avoid.
function Provider:_chooseVisibleSlot(slot)
  local row, index = listModel.rowAtVisibleSlot(self.listState, slot)
  self:_choose(row, index)
end

--------------------------------------------------------------------------------
-- The field's own callbacks
--------------------------------------------------------------------------------

-- Runs on every applied key the field answers, printable or named, including a plain
-- caret move that touches no text at all. Reranking on every one of those would reset
-- the list back to its own top each time a hand merely moved the caret inside what it
-- had already typed, so this compares against self._lastQuery, the same guard
-- probe-canvasfield.lua's own syncListQuery already keeps, and only reranks when the
-- text itself actually changed.
--
-- self._suppressRebuild is set only for the length of a programmatic setText call this
-- file itself makes, show's own clearing of the field among them and setQuery below,
-- since Field colon setText always fires onChange the identical way a keystroke does,
-- and setQuery's own contract is that it sets the field and asks nothing to rebuild on
-- its own, host/actionpanel/init.lua and host/stage/init.lua both already relying on
-- that and calling refresh themselves right after.
function Provider:_onFieldChange(state)
  self:_restartBlink()
  if self._suppressRebuild then
    self._lastQuery = state.text
    self:_redraw()
    return
  end
  if state.text ~= self._lastQuery then
    self._lastQuery = state.text
    self:_stopScrollEase()
    self:_rebuildList(state.text, true)
    self:_fireHighlight()
  end
  self:_redraw()
  if self.config.onActivity then safeCall(self.config.onActivity) end
end

-- The idle signal a consumer such as the docked hint panel restarts its countdown on.
-- A Hyper press never reaches _onFieldKey, since the field yields it so the leader
-- dispatch can run, and that dispatch drives selectNext, selectPrev and insertSelected
-- instead, so those count here. The field itself deliberately does not count a yielded
-- key, because the leader autorepeats while held and the panel would never appear.
function Provider:_noteActivity()
  if self.config.onActivity then safeCall(self.config.onActivity) end
end

-- Runs for a key down neither the field's own keymap nor its printable check claims,
-- return, keypad enter, up, down and cmd plus a digit among them. Everything this
-- provider does not itself recognise is swallowed rather than let through, the field's
-- own tap having already claimed the key down regardless, since the frontmost app
-- still holds focus and would otherwise receive it.
-- Fix round item seven. onActivity used to fire at the foot of this function, reached
-- only after the dispatch below, so on Return the branch through insertSelected,
-- underscore choose, onSelect, hide and onClose had already run before this line ever
-- had a chance to, telling a consumer using it as an idle signal that a key was
-- pressed in a picker that was already gone. Native fires it at the top of its own key
-- watcher before it looks at the keycode at all, so this moves to the top the same
-- way, above the dispatch rather than below it.
function Provider:_onFieldKey(ev)
  self:_noteActivity()
  local code = ev:getKeyCode()
  local digit = KEYCODE_DIGIT[code]
  if digit and ev:getFlags().cmd then
    self:_chooseVisibleSlot(digit)
  elseif code == KEYCODE_DOWN then
    self:_stopScrollEase()
    self.listState = listModel.moveDown(self.listState)
    self:_fireHighlight()
    self:_redraw()
  elseif code == KEYCODE_UP then
    self:_stopScrollEase()
    self.listState = listModel.moveUp(self.listState)
    self:_fireHighlight()
    self:_redraw()
  elseif code == KEYCODE_RETURN or code == KEYCODE_KEYPAD_ENTER then
    self:_insertHighlighted()
  end
end

-- Section one of the brief's own addition to field/input.lua, a backward delete on an
-- empty field with nothing selected. Asks config.back and does nothing at all when it
-- answers anything but true, rather than dismissing, matching what legacy.lua's own
-- colon underscore back does for the identical press.
function Provider:_onEmptyBackspace()
  if self.config.onActivity then safeCall(self.config.onActivity) end
  local ask = self.config.back
  if not ask then return end
  if safeCall(ask) ~= true then return end
  self:refresh(true)
end

--------------------------------------------------------------------------------
-- Mouse
--------------------------------------------------------------------------------

-- The filtered index a screen point falls on, or nil when the point sits outside the
-- list rect entirely, composing geometry's own arithmetic with list model's own
-- rowAtVisibleSlot through list model's own rowAtPoint, never treated as a slot on its
-- own, the identical composition the ranking header above already names as one of the
-- three traps this file was built to avoid.
function Provider:_rowIndexAtPoint(point)
  local listRect = self._rects and self._rects.list
  if not pointInRect(point, listRect) then return nil end
  return listModel.rowAtPoint(self.listState, point.y - listRect.y)
end

-- A left or a right press. Outside this surface and outside its companion, if any, a
-- LEFT press hides the picker and does not claim the event, so the same press also
-- reaches whatever the person actually meant to click, matching what happens today. A
-- right press out there is left alone entirely, neither hiding the picker nor being
-- claimed, matching legacy.lua, whose own click watcher only ever looks at left button
-- events at all, a right click anywhere it does not already own never reaching that
-- atom's notice in the first place. Inside the companion, which this file draws none
-- of, the press is left for whatever owns that pane to answer, the identical choice
-- legacy.lua's own click watcher makes for the same rect. A right press on a row reads
-- config.onRightClick LIVE on every use rather than once at construction, the one
-- asymmetry with legacy.lua this document already names and asks not to be reproduced.
-- A left press records which row it landed on, for the matching release to compare
-- against.
function Provider:_onMouseDown(point, button)
  local rects = self._rects
  local insideCanvas = pointInRect(point, rects and rects.canvas)
  local insideCompanion = pointInRect(point, rects and rects.companion)
  if not insideCanvas and not insideCompanion then
    if button == "left" then self:hide() end
    return false
  end
  if not insideCanvas then
    return false
  end
  if button == "right" then
    local index = self:_rowIndexAtPoint(point)
    local ns = listModel.normalized(self.listState)
    local row = index and ns.filtered[index]
    if row and self.config.onRightClick then
      safeCall(self.config.onRightClick, rowItem(row), index)
    end
    return true
  end
  self._pressedRowIndex = self:_rowIndexAtPoint(point)
  return true
end

-- The release chooses the row the matching press landed on, only when the release
-- lands on that same row, ordinary click behaviour and also what legacy.lua's own
-- click watcher measured the real widget doing. A right release inside this surface is
-- claimed too, purely so the down and the up of the identical press agree about
-- whether this surface owns it, and answers nothing further since the row already had
-- its answer on the down half of the same press.
function Provider:_onMouseUp(point, button)
  local rects = self._rects
  if button == "right" then
    return pointInRect(point, rects and rects.canvas)
  end
  if button ~= "left" then return false end
  if not pointInRect(point, rects and rects.canvas) then
    self._pressedRowIndex = nil
    return false
  end
  local index = self:_rowIndexAtPoint(point)
  local pressed = self._pressedRowIndex
  self._pressedRowIndex = nil
  if index and pressed and index == pressed then
    local ns = listModel.normalized(self.listState)
    self:_choose(ns.filtered[index], index)
  end
  return true
end

-- A move over a row sets the highlight, which the native widget does for free on
-- hover, and this file's absence of it would read as this backend being broken. Never
-- claimed, mouse.lua's own contract already has onMove answer true to claim nothing on
-- its own, the caller deciding, and this file has no reason to claim a plain hover.
function Provider:_onMouseMove(point)
  local listRect = self._rects and self._rects.list
  if not pointInRect(point, listRect) then return end
  local index = listModel.rowAtPoint(self.listState, point.y - listRect.y)
  if index then self:_setHighlightIndex(index) end
end

-- A scroll over the list moves the viewport through list model's own scrollBy or
-- scrollByWheelNotch above, never the highlight, a trackpad's continuous delta
-- followed directly and a wheel's coarse notch eased toward over a few ticks, both
-- settled by hand in round five and carried across rather than chosen again. A scroll
-- over the companion rect instead calls config.onScroll with the raw delta, this file
-- having no opinion about what that pane does with it.
function Provider:_onMouseScroll(point, dy, continuous)
  local rects = self._rects
  if pointInRect(point, rects and rects.list) then
    self:_stopScrollEase()
    if continuous then
      self.listState = listModel.scrollBy(self.listState, -dy)
      self:_redraw()
    else
      self:_scrollByWheelNotch(-dy * WHEEL_NOTCH_POINTS)
    end
    return true
  end
  if pointInRect(point, rects and rects.companion) then
    if self.config.onScroll then safeCall(self.config.onScroll, -dy) end
    return true
  end
  return false
end

--------------------------------------------------------------------------------
-- Teardown, one idempotent path for every dismissal
--------------------------------------------------------------------------------

-- Every way this picker can end, a selection, escape, a click outside, or a
-- programmatic hide, funnels through here, and onClose fires exactly once per open
-- however it ended. The two taps are stopped FIRST, unconditionally, before anything
-- else in this function runs, and only then do the timers, the surface and the
-- pressed row state come down, and only then does onClose fire, guarded so a raise
-- inside a consumer's own code cannot abandon anything below it. Commit 1ccab6f is
-- this configuration's own record of what a tap left believed armed after a raise
-- above its own stop costs, a leader believed held rather than checked swallowing
-- keys nobody meant to lose, and a keyboard tap or a mouse tap left running here is
-- the identical hazard turned toward this surface.
function Provider:_teardown()
  if not self.active then return end
  self.active = false

  if self.field then self.field:stop() end
  if self.mouse then self.mouse:stop() end

  self:_stopBlink()
  self:_stopScrollEase()
  self._pressedRowIndex = nil
  if self.surface then self.surface:hide() end

  if self.config.onClose then
    local ok, err = pcall(self.config.onClose)
    if not ok then
      print("Olm canvas provider, onClose failed, " .. tostring(err))
    end
  end
end

--------------------------------------------------------------------------------
-- The picker contract, docs/CONTRACT-PICKER.md
--------------------------------------------------------------------------------

--- Provider colon show, arity zero. Reselects the theme, resolves the screen and the
--- derived styles, resolves the rectangles through geometry.resolve, places the
--- surface, builds rows for an empty query with the highlight on row one, clears the
--- field, draws, shows, arms the field tap, the mouse tap and the caret blink, reports
--- onPositioned exactly once with the final frames, since this surface is final on its
--- first frame and has no correction pass, and only then calls onHighlight with the
--- first row, synchronously, which is not a seed for a poll about to start, it is the
--- whole mechanism, since this provider knows the instant its own highlight moves and
--- never polls for it.
function Provider:show()
  self:_selectTheme()
  self:_deriveStyles()
  self.active = true
  self._textBudget = nil

  local screen = self:_resolveScreen()
  self._targetScreen = screen
  local sf = screen:frame()
  self._rects = geometry.resolve(sf, self.layout, self._paneWidth)
  self:_updateDrawLayout()
  self.surface:setFrame(self._rects.canvas)

  self:_rebuildList("", true)
  self._suppressRebuild = true
  self.field:setText("")
  self._suppressRebuild = false

  self:_redraw()
  self.surface:show()

  self.field:start()
  self.mouse:start()
  self:_restartBlink()

  self._paneFrames = { chooser = self._rects.chooser, companion = self._rects.companion }
  safeCall(self.config.onPositioned, self._rects.chooser, self._rects.companion)

  self:_fireHighlight()
end

--- Provider colon hide, arity zero. The single idempotent dismissal path, calling it
--- when nothing is up is not an error.
function Provider:hide()
  self:_teardown()
end

--- Provider colon isShowing, arity zero. Whether the surface is genuinely on screen
--- right now, answering the surface's own isVisible rather than this instance's belief
--- about itself.
function Provider:isShowing()
  return self.surface ~= nil and self.surface:isVisible()
end

--- Provider colon isActive, arity zero. Whether this provider believes it is up, a
--- different question from isShowing, answering self.active.
function Provider:isActive()
  return self.active == true
end

--- Provider colon refresh, arity one. Reranks and redraws for the current query.
--- A truthy resetRow returns the highlight to row one, matching the reset every
--- keystroke already takes, falsy preserves whatever row and scroll position were
--- already current, clamped rather than recomputed, the same distinction colon
--- underscore rebuildList's own header explains in full.
---
--- Fix round item three. This used to test resetRow == true, where the contract
--- document says a truthy argument resets and native itself tests with a plain if
--- resetRow then. host/stage/init.lua forwards whatever a caller handed it unexamined,
--- so a caller passing anything truthy other than the literal true, one for instance,
--- would silently have been treated as falsy here and nowhere else. Testing plain
--- truthiness by handing resetRow straight to colon underscore rebuildList, whose own
--- guard already reads it that way, is what brings this in line with both the
--- contract and native.
function Provider:refresh(resetRow)
  if not self.active then return end
  self:_stopScrollEase()
  self:_rebuildList(self:query(), resetRow)
  self:_fireHighlight()
  self:_redraw()
end

--- Provider colon query, arity zero. The field's own current text.
function Provider:query()
  return self.field:getState().text
end

--- Provider colon setQuery, arity one. Sets the field text, caret left after it rather
--- than the text standing selected, and rebuilds the list for the new query with the
--- highlight reset to row one.
---
--- Fix round item five. The comment that used to stand here claimed this asks nothing
--- to rebuild on its own because the stage and the action panel always refresh
--- themselves right after, and that was not true as stated. host/launcher/init.lua
--- calls this in several places with no refresh of its own, surviving today only
--- because each call sits inside an intercept handler or a back handler, and colon
--- underscore choose already refreshes once that handler answers, luck rather than
--- design. Native rebuilds inside setQuery for a plain reason this file was missing,
--- hs.chooser colon query fires its own queryChangedCallback on every call, which is
--- exactly what runs native's own rebuild, so setQuery already rebuilds there whether a
--- caller refreshes afterward or not. This function now does the same. A caller that
--- still calls refresh right after this rebuilds a second time, harmless and no
--- different from the double rebuild native already pays in the same situation.
--- self._suppressRebuild is what keeps Field colon setText's own onChange from
--- rebuilding a second time inside this very call, explained in full where that flag
--- is read.
function Provider:setQuery(text)
  text = text or ""
  self._suppressRebuild = true
  self.field:setText(text)
  self._suppressRebuild = false
  self:_stopScrollEase()
  self:_rebuildList(text, true)
  self:_fireHighlight()
  self:_redraw()
end

--- Provider colon setPlaceholder, arity one. Stores the hint text live and passed to
--- field/render.lua on every redraw, drawn dim whenever the buffer is empty, fix round
--- item thirteen below.
function Provider:setPlaceholder(text)
  self._placeholder = text or ""
end

--- Provider colon setRows, arity one. Remembers a row count for this instance's next
--- show, matching what the contract promises rather than what this backend can
--- actually do. This backend CAN resize live, geometry.resolve and a fresh setFrame
--- would pick up a new rowCount at once, but the restriction here is inherited from
--- the native provider's own promise rather than anything this backend needs, so a
--- later phase is free to lift it deliberately once a caller actually wants a live
--- resize.
function Provider:setRows(n)
  self.layout.rowCount = n
end

--- Provider colon rowCount, arity zero. The row count this instance is currently built
--- for.
function Provider:rowCount()
  return self.layout.rowCount
end

--- Provider colon selectNext, arity zero. Moves the highlight down by one, wrapping at
--- the end, list model's own decision, stated as this provider's own end policy the
--- contract asks every provider to state for itself.
function Provider:selectNext()
  if not self.active then return end
  self:_noteActivity()
  self:_stopScrollEase()
  self.listState = listModel.moveDown(self.listState)
  self:_fireHighlight()
  self:_redraw()
end

--- Provider colon selectPrev, arity zero. The same move upward.
function Provider:selectPrev()
  if not self.active then return end
  self:_noteActivity()
  self:_stopScrollEase()
  self.listState = listModel.moveUp(self.listState)
  self:_fireHighlight()
  self:_redraw()
end

--- Provider colon selectRow, arity one. Clamps n into the range the filtered set
--- currently supports and ignores a nil argument rather than raising. Also brings the
--- row into view, fix round item two below.
---
--- list model.lua deliberately never pulls scrollTop toward the highlight on its own,
--- its own header explains at length why, so setting ns.highlight alone can leave a
--- row highlighted well outside whatever band the viewport currently shows. That is
--- exactly what host/actionpanel/init.lua relies on this method for, restoring the row
--- a person was on when they opened the action panel, and a captured row past the
--- visible band used to land off screen with the highlight invisible until the next
--- arrow press corrected it. hs.chooser colon selectedRow n scrolls its own table for
--- free, so this brings the row into view the same way, through the public
--- listModel.scrollTo rather than reaching into list/model.lua's own private
--- scrollToShowHighlight, pulling scrollTop up to the row's own top when it starts
--- above the viewport and down to the row's own bottom less the viewport height when
--- it ends below.
function Provider:selectRow(n)
  if n == nil then return end
  local ns = listModel.normalized(self.listState)
  local total = #ns.filtered
  if total == 0 then return end
  if n < 1 then n = 1 end
  if n > total then n = total end
  ns.highlight = n
  self.listState = listModel.normalized(ns)

  local rowH = self.listState.rowH
  local viewportH = rowH * self.listState.visibleCount
  local topOf = (n - 1) * rowH
  local bottomOf = n * rowH
  local scrollTop = self.listState.scrollTop
  if topOf < scrollTop then
    self.listState = listModel.scrollTo(self.listState, topOf)
  elseif bottomOf > scrollTop + viewportH then
    self.listState = listModel.scrollTo(self.listState, bottomOf - viewportH)
  end

  self:_fireHighlight()
  self:_redraw()
end

--- Provider colon selectedRow, arity zero. The highlighted row number, or nil.
function Provider:selectedRow()
  local ns = listModel.normalized(self.listState)
  return ns.highlight
end

--- Provider colon selectedItem, arity zero. The opaque item under the highlight, or
--- nil.
function Provider:selectedItem()
  return rowItem(listModel.highlightedRow(self.listState))
end

--- Provider colon insertSelected, arity zero. Behaves exactly as Return does, asking
--- intercept first and honouring a disabled row, through the shared colon underscore
--- choose this file's Return key, its cmd plus digit path and its own mouse release
--- all three call.
function Provider:insertSelected()
  if not self.active then return end
  self:_noteActivity()
  self:_insertHighlighted()
end

-- The choosing half of insertSelected, split out so the Return key in the field, which
-- has already counted as activity at the top of its own handler, does not count twice.
function Provider:_insertHighlighted()
  local ns = listModel.normalized(self.listState)
  local row = ns.highlight and ns.filtered[ns.highlight]
  self:_choose(row, ns.highlight)
end

--- Provider colon textBudget, arity zero. The pixel room a row's text has on the
--- screen this picker will open on, resolved lazily and cached for the open through
--- geometry.textBudget, the replacement for legacy.lua's own measured ROW_TEXT_INSET.
function Provider:textBudget()
  if not self._textBudget then
    local screen = self._targetScreen or self:_resolveScreen()
    local sf = screen:frame()
    local rects = geometry.resolve(sf, self.layout, self._paneWidth)
    self._textBudget = geometry.textBudget(rects, self.layout)
  end
  return self._textBudget
end

--- Provider colon textWidth, arity two. The rendered pixel width of str at the title
--- size or the subtitle size which selects, a passthrough onto the UI kit's measurer,
--- whose width is the per character sum, the same number the native provider answers, so a
--- supplier formatting against it gets one answer from either provider.
function Provider:textWidth(str, which)
  local face = self._type
  if which == "title" then return UI.measure:width(str, face.font, face.textSize) end
  return UI.measure:width(str, face.subFont, face.subSize)
end

--- Provider colon reposition, arity one. Recentres the already shown surface for
--- paneWidth and answers both frames, the companion nil when there is none, and
--- nothing at all when this instance is not up. Cheap and live here, unlike the native
--- provider's own equivalent, since this backend only ever has to recompute through
--- geometry.resolve and move the surface, the whole gain this backend was built for.
---
--- Fix round item ten. This used to write paneWidth straight into self._paneWidth,
--- which is the field colon underscore setPaneWidth owns as this instance's next
--- placement policy. Native's own reposition reads its argument and leaves
--- layout.companionWidth untouched, and the difference was invisible only because the
--- stage always passes the identical value to both this method and setPaneWidth, so a
--- reposition silently rewriting a presentation's own stored policy was wrong even
--- though nothing today notices. This reads the argument and answers frames for it
--- without storing it anywhere.
function Provider:reposition(paneWidth)
  if not self.active then return nil end
  local screen = self._targetScreen or self:_resolveScreen()
  local sf = screen:frame()
  self._rects = geometry.resolve(sf, self.layout, paneWidth)
  self:_updateDrawLayout()
  self.surface:setFrame(self._rects.canvas)
  self:_redraw()
  self._paneFrames = { chooser = self._rects.chooser, companion = self._rects.companion }
  return self._rects.chooser, self._rects.companion
end

--- Provider colon settleDelay, arity zero. Zero seconds, this surface is final on its
--- first frame and has no correction pass to wait out.
function Provider:settleDelay()
  return 0
end

--- Provider colon matcher, arity zero. The current matching strategy, fronting
--- self._matcher.
function Provider:matcher()
  return self._matcher
end

--- Provider colon setMatcher, arity one. false and nil are different answers and both
--- survive the round trip through self._matcher.
function Provider:setMatcher(m)
  self._matcher = m
end

--- Provider colon titleLineBreak, arity zero. The truncation mode a title takes,
--- fronting self.layout.titleLineBreak.
function Provider:titleLineBreak()
  return self.layout.titleLineBreak
end

--- Provider colon setTitleLineBreak, arity one. Sets the live title truncation mode.
function Provider:setTitleLineBreak(mode)
  self.layout.titleLineBreak = mode
end

--- Provider colon setPaneWidth, arity one. Sets the companion width policy for this
--- instance's next placement, true inheriting the surface's own resolved width, a
--- number overriding it, nil or zero meaning no companion, every answer capped at
--- this instance's own paneMaxW wherever geometry.resolve actually reads it.
function Provider:setPaneWidth(w)
  self._paneWidth = w
end

--------------------------------------------------------------------------------
-- Wiring, called once at construction
--------------------------------------------------------------------------------

-- Builds the mouse tap, dispatching by button and by rect the way the header above
-- each handler already explains.
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

-- Builds the field, wiring every one of its four callbacks to this instance's own
-- handlers, including section one's own onEmptyBackspace, the addition this brief
-- makes to field/input.lua so config.back can ever be reached at all. onDismiss fires
-- onActivity before hiding, matching legacy.lua's own key watcher, which fires
-- onActivity for every key down including escape before asking which key it saw, since
-- the field's own escape path answers before onKey or onChange are ever reached and
-- would otherwise be the one key this provider's idle signal never learns about.
local function buildField(self)
  return Field.new({
    text = "",
    onChange = function(state) self:_onFieldChange(state) end,
    onKey = function(ev) self:_onFieldKey(ev) end,
    onDismiss = function()
      if self.config.onActivity then safeCall(self.config.onActivity) end
      self:hide()
    end,
    onEmptyBackspace = function() self:_onEmptyBackspace() end,
    -- Whatever predicate the composition root injected, read at the moment a key arrives
    -- so a configure after this instance was built still takes effect.
    yields = function(ev) return YIELDS ~= nil and YIELDS(ev) end,
  })
end

--------------------------------------------------------------------------------
-- Module surface
--------------------------------------------------------------------------------

local M = {}

-- The injected CanvasPanel module, nil until M.configure runs. Held at module level
-- rather than per instance, the same shape lib/panel.lua's own configure already takes
-- for its shared style, since every instance this file ever builds draws through the
-- identical shared chrome.
local PANEL = nil

--- M.configure(opts) takes opts.panel, the CanvasPanel module, and opts.ui, the UI kit, and
--- optionally opts.yields, a function(event) answering true for a key down the field's tap
--- must let through instead of claiming. Callable more than once, a nil field left unchanged, matching CanvasPanel.configure's
--- own idiom. Whatever calls M.new is expected to have called this first.
function M.configure(opts)
  opts = opts or {}
  if opts.panel ~= nil then PANEL = opts.panel end
  if opts.ui ~= nil then UI = opts.ui end
  if opts.yields ~= nil then YIELDS = opts.yields end
  return M
end

--- M.new(config) answers an instance satisfying lib/chooser/contract.lua exactly,
--- validated against that module at the end of this function and raised on a gap
--- rather than waiting for the facade to notice, so a missing name is found by the
--- probe rather than by a person. Refuses outright when M.configure has not been
--- called with a panel, rather than drawing a surface with no shared chrome, which
--- would look subtly wrong instead of loudly missing.
function M.new(config)
  if not PANEL then
    error("Canvas provider: M.configure must be called with opts.panel, the CanvasPanel "
      .. "module, before M.new can build an instance, wiring this at the composition "
      .. "root is phase four and nothing has done it yet")
  end
  if not UI then
    error("Canvas provider: M.configure must be called with opts.ui, the UI kit, before "
      .. "M.new can build an instance, since every colour and the type come from its tokens")
  end
  config = config or {}

  local layout = {}
  for k, v in pairs(geometry.DEFAULT_LAYOUT) do layout[k] = v end
  -- Every inset is the kit's one inset and the row and field heights follow it and the type
  -- roles' real capital heights, so a size change in config/typography.toml or the inset
  -- reflows them. A consumer's own layout still wins over what is derived.
  local tokens = UI.tokens()
  local inset = tokens.inset or { x = layout.padX, y = layout.marginY }
  layout.padX, layout.iconGap = inset.x, inset.x
  layout.marginX, layout.marginY = inset.x, inset.y
  local cap = capOf(tokens)
  local derived = geometry.derivedRows(tokens.text, cap, inset)
  layout.iconSize = derived.iconSize
  layout.iconFrame = derived.iconFrame
  -- The shortcut column is as wide as the widest shortcut drawn in it, measured in the body
  -- role, so the title's budget is exactly what is left.
  if UI.measure then
    layout.numW = math.ceil(UI.measure:width("\u{2318}9", tokens.text.body.font, tokens.text.body.size))
  end
  layout.rowH = derived.rowH
  layout.baseH = derived.baseH
  for k, v in pairs(config.layout or {}) do layout[k] = v end

  local self = setmetatable({
    config = config,
    layout = layout,
    _tokens = nil,
    _type = nil,
    _matcher = config.matcher,
    _paneWidth = nil,
    listState = listModel.newState({}, layout, ""),
    active = false,
    _lastQuery = "",
    _suppressRebuild = false,
    _pressedRowIndex = nil,
    _caretVisible = true,
    _placeholder = config.placeholder or "",
  }, Provider)

  -- Resolved once here as well as on every show, so a row styled or a width measured
  -- before the first show already has the tokens to read.
  self:_selectTheme()

  self.surface = Surface.new({ panel = PANEL })
  self.mouse = buildMouse(self)
  self.field = buildField(self)

  local ok, reason = contract.validate(self)
  if not ok then
    error("Canvas provider: the instance does not satisfy the picker contract, " .. tostring(reason))
  end

  return self
end

return M
