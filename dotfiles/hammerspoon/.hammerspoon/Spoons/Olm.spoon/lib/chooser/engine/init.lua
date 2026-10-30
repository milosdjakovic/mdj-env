--- === Chooser engine ===
---
--- Every rule Olm's picker keeps, and all of its state, with no drawing in it. It implements the
--- twenty five methods of docs/CONTRACT-PICKER.md and the extras the stage calls, setPosture,
--- posture, toggleKeys and closeKeys, and leaves the surface, the field's text editing, the
--- pointer and every pixel to a view it is handed at construction. lib/chooser/view.lua is the
--- contract between the two, and this file knows a view only through it. The canvas view is
--- lib/chooser/providers/default/canvas.lua, and the default provider is this engine composed
--- with it. The split was made on 2026-10-28 so a second view, a native one, stands under the
--- same rules instead of a copy of them, see decisions/olm-swift-chooser.md.
---
--- Four places here are not plain bookkeeping, and each is named where it happens below.
---
--- The first is ranking. list/model.lua can rank a query itself, through the same
--- lib/chooser/rank.lua, and if this file let it, every query would be filtered twice, once
--- here and again over rows already presented. Before 2026-10-17 the model's own copy was also
--- hard wired to the fuzzy strategy, so it silently ignored a presentation that set matcher to
--- false. So this file ranks through lib/chooser/rank.lua itself, using the live matcher, and
--- hands the already ranked rows to the list model with an EMPTY query and no matcher every
--- time, so the list model ranks nothing and only holds, highlights and scrolls what it was
--- given. See Engine colon underscore rebuildList below for where that happens.
---
--- The second is teardown ordering. The view's taps are stopped first, before anything else in
--- Engine colon underscore teardown runs, and only then do the timers, the surface and the state
--- come down, and only then does onClose fire, guarded so a raise inside it cannot abandon the
--- rest of teardown. Commit 1ccab6f is this configuration's own record of what a tap left
--- believed armed costs on this machine, a leader believed held rather than checked swallowing
--- keys nobody meant to lose, and a keyboard tap or a mouse tap left running is the identical
--- hazard.
---
--- The third is Command with a digit. It chooses the row at that place in the list, list
--- model's own rowAtSlot, the first nine rows fixed however the list is scrolled.
---
--- The fourth is key order. A key down is asked of this file in a fixed order, Escape first and
--- before anything can yield it, then the yield predicate, then the list keys, then the field's
--- own editing, and last whatever is left over, Up, Down, Return, keypad Enter and Command with a
--- digit. The view runs that order, since the field's editing sits in the middle of it and the
--- field is the view's, and calls dismissKey, yieldsKey, listKey and leftoverKey below at their
--- places in it. lib/chooser/view.lua states the order for any view.
---
--- Every config callback is read live, at the moment it is called, never captured at
--- construction, since the ActionPanel decorator rewrites rows, intercept, back, onSelect,
--- onHighlight and onClose on the config table after this instance is built. config.onRightClick
--- is read live too, unlike the legacy provider, as docs/CONTRACT-PICKER.md asks.
---
--- The action bar, docs/PLAN-ACTION-BAR.md. A consumer that hands config.footer, a function
--- answering lib/hints.lua's footerModel shape for the list now showing, gets a footer model this
--- file asks on every show, after every highlight move and on a quarter second poll while the
--- list is up, so a gated key or a live label changes the bar without anyone telling this file.
--- This file owns the key panel's open state and which keys close it, and the view draws both
--- and owns the key button's hit test and the panel's rect. A consumer handing none gets no bar
--- and no change to its rows.
---
--- The bare posture. setPosture("bare") draws the list alone, no field over it and no action bar
--- under it, the list's own margin on every side and no peek of a further row. The field's tap
--- still runs, since the list's own keys are still read, the arrows, Return, keypad Enter and
--- Escape, and so are the list keys a person bound. Every other key down is handed to
--- config.onBareKey and never typed, and a key it answers true for is claimed. The posture is the
--- caller's to set and takes effect on the next show, like setRows. "full" is everything.
---
--- Engine.configure(opts) takes opts.ui, the UI kit, and optionally opts.yields, opts.listKeys
--- and opts.focusHold, each explained where it is held below. Engine.new(config, makeView) builds
--- an instance and asks makeView(engine) for its view.

local herePath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(relPath)
  local chunk, err = loadfile(herePath .. relPath)
  if not chunk then
    error("Chooser engine: failed to load " .. relPath .. ", " .. tostring(err))
  end
  return chunk()
end

local rank = load("../rank.lua")
local contract = load("../contract.lua")
local viewContract = load("../view.lua")

-- THE SEAM. Three modules this engine stands on still live beside the canvas view, where they
-- were written, and are loaded from there in this one place. geometry.lua resolves every
-- rectangle and the text budget, and list/model.lua holds the highlight and the scroll, both
-- pure and drawing nothing. footer.lua is the view's own drawing of the action bar, and the
-- engine reads only its height, which the layout reserves, never its bar or its key panel. Many
-- tests and probes load all three by these paths, so they stay put.
local geometry = load("../providers/default/geometry.lua")
local listModel = load("../providers/default/list/model.lua")
local footerLib = load("../providers/default/footer.lua")

--------------------------------------------------------------------------------
-- Module level collaborators
--------------------------------------------------------------------------------

-- The injected UI kit, lib/ui, nil until Engine.configure runs. Every instance reads the one
-- configured style, for its tokens, its type and its measurer.
local UI = nil

-- The injected predicate over a key down event, answering whether the key belongs to
-- something downstream of the field's tap and must pass on. Nil until Engine.configure runs,
-- and nil means the field claims everything. This file knows only that it is a predicate.
local YIELDS = nil

-- The injected watcher for list keys the open list binds with no held leader, a function(event)
-- that runs the matching binding and answers true, or answers false. Nil until Engine.configure
-- runs, and nil means the field reads no such key. This file knows only that it is a watcher.
local LIST_KEYS = nil

-- An optional function answering a release function or nil, asked once per open right after the
-- surface shows. It is the seam for whatever must give this list keys a tap cannot otherwise
-- hear, and the release it answers runs on teardown. It is handed a sink, key(event) feeding the
-- view's field as its tap would and text(string) replacing the field's text, for keys it hears by
-- another route, and may answer a mirror beside the release, told the field's text on every
-- change. Nil until Engine.configure runs.
local FOCUS_HOLD = nil

-- The most rows a list shows when its presentation names no rowLimit of its own, chooser.rowLimit
-- in config/settings.lua handed through the root, or nil for no default. A presentation's own
-- number wins and its false opts out. Rows past it are offered by the row of more, see moreRow.
-- Nil until Engine.configure runs.
local ROW_LIMIT = nil

-- The row of more's icon, { icon, owner }, a key and the manifest owner it is read against, the
-- way the bar's keys icon is handed over, so this file names no owner. Nil draws it without one.
local MORE_ICON = nil

-- Return, keypad enter, up and down, the four keys a field's editing never claims, so all four
-- reach leftoverKey unclaimed rather than being typed into the buffer as a stray character.
local KEYCODE_RETURN, KEYCODE_KEYPAD_ENTER = 36, 76
local KEYCODE_UP, KEYCODE_DOWN = 126, 125
local KEYCODE_ESCAPE = 53

-- The raw virtual keycodes for the digit keys one through nine, read from the running config's
-- own hs.keycodes.map the same way probe-canvasfield.lua's own header says its identical table
-- was derived, since Command with a digit is named nowhere in the field's keymap and reaches
-- leftoverKey the same unclaimed way up and down already do.
local KEYCODE_DIGIT = {
  [18] = 1, [19] = 2, [20] = 3, [21] = 4, [23] = 5,
  [22] = 6, [26] = 7, [28] = 8, [25] = 9,
}

-- How often a showing list asks its footer collaborator again, so a gated key or a live label
-- changes the action bar without anyone telling this file, the same quarter second CanvasPanel
-- polled the hint bar's state at. A redraw happens only when the answer changed.
local FOOTER_POLL_INTERVAL = 0.25

--------------------------------------------------------------------------------
-- Small stateless helpers, none of them touching self
--------------------------------------------------------------------------------

-- Runs fn inside a pcall and reports rather than raises, the same posture field/input.lua and
-- mouse.lua both already take toward a consumer callback. Used for every config callback this
-- file calls outward, so a mistake in a consumer's own code is a print line rather than a stuck
-- picker. The words name the canvas provider, as they did before the split, so a log search
-- for them still finds every line.
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
-- onHighlight, onSelect, intercept and selectedItem all ever hand back, never the row itself
-- and never its presented title.
local function rowItem(row)
  return row and row.item or nil
end

-- The row of more, the last row of a list its limit cut, naming how many rows choosing it adds,
-- a page of the limit or what is left when that is less, and how many are left in all when that
-- is more. It carries no item, so a highlight on it reports no item, it has no actions and a
-- right press on it is nobody's. more = true is what the engine and every view know it by.
local function moreRow(cut, page)
  local adds = math.min(cut, page)
  return {
    title = ("Show %d more"):format(adds),
    subTitle = cut > adds and ("%d more in all"):format(cut) or nil,
    icon = MORE_ICON and MORE_ICON.icon or nil,
    iconOwner = MORE_ICON and MORE_ICON.owner or nil,
    more = true,
  }
end

-- Whether a key down is one a bare list reads, the vertical arrows, Return and keypad Enter,
-- which leftoverKey answers. Escape is answered by dismissKey before it is ever asked. Command
-- and a digit is not one, since a bare list draws no row numbers to choose by, so it is typing
-- like every other key, which a bare list hands on rather than reads.
local function listReads(ev)
  local code = ev:getKeyCode()
  if code == KEYCODE_UP or code == KEYCODE_DOWN then return true end
  return code == KEYCODE_RETURN or code == KEYCODE_KEYPAD_ENTER
end

--------------------------------------------------------------------------------
-- Tokens, type and the layout geometry reads
--------------------------------------------------------------------------------

-- The four roles the field and every row are drawn in, read only from the kit's tokens. The
-- field takes title, row titles body, row subtitles caption and the row shortcut body, the size
-- of the title beside it. A line is the role's own line height, except the subtitle's, which is
-- the baseline step the row rule derives, see lib/chooser/rowheight.lua.
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

--------------------------------------------------------------------------------
-- Instance
--------------------------------------------------------------------------------

local Engine = {}
Engine.__index = Engine

-- Resolves the kit's tokens for the half the system is on now, the same moment the old theme
-- pick ran, so a light and dark switch is picked up at the next open rather than mid session.
function Engine:_selectTheme()
  self._tokens = UI.tokens()
  self._type = typeOf(self._tokens)
end

-- The display this open should appear on, config.screen called once per show, falling back to
-- the main screen and then the primary one, the identical fallback chain legacy.lua's own
-- Chooser colon underscore resolveScreen already takes.
function Engine:_resolveScreen()
  local fn = self.config.screen
  local s = fn and fn()
  return s or hs.screen.mainScreen() or hs.screen.primaryScreen()
end

-- Fix round item six. geometry.resolve trims the requested row count to whatever the screen
-- can actually hold and answers the trimmed number as self._rects.rowCount, sizing rects.list
-- and the canvas from that trimmed number. self.layout is the requested policy, the number
-- rowCount() and setRows speak about, and it must stay untrimmed for that reason, so this
-- builds a separate per show copy carrying the trimmed rowCount instead of writing over
-- self.layout. Both listModel.newState and the view's list renderer read a layout's rowCount to
-- decide how tall the viewport and the clip band stand, so both must read this copy, never
-- self.layout, or the two disagree on a screen short enough to trim, roughly under five hundred
-- and twenty four points of frame height. The clip band would then stand taller than the list
-- rect and rows would draw past the bottom of the surface, maxScrollTop would be too small for
-- the last rows ever to be reached. Called right after
-- self._rects is computed, in show and in reposition, which is every place this file computes a
-- fresh self._rects at all.
--
-- The draw layout also carries the three roles' fonts, sizes and line heights from the tokens,
-- the names the list renderer reads off a layout, since geometry.lua holds no type.
function Engine:_updateDrawLayout()
  local L = {}
  for k, v in pairs(self:_shapedLayout()) do L[k] = v end
  -- The viewport holds the whole rows and the peek of one more, so the model scrolls and the
  -- renderer clips to that height. A fractional count is fine for both, they work in points.
  L.rowCount = self._rects.viewRows or self._rects.rowCount
  -- The margin under the list scrolls with the rows, see geometry.resolve.
  L.padBottom = self.layout.marginY
  for k, v in pairs(self._type) do L[k] = v end
  self._drawLayout = L
end

-- The layout geometry.resolve is handed, the layout itself in the full posture and a copy in
-- the bare one, with the field's height down to the list's own margin, so the rows sit the same
-- distance from the top edge as from the bottom, and with no action bar and no peek, since a
-- list shown bare is as tall as its rows and has nothing below them to hint at. It draws no row
-- numbers either, since a bare list is stepped by its own key and Command and a digit is not read
-- there, see listReads.
function Engine:_shapedLayout()
  if not self._bare then return self.layout end
  local L = {}
  for k, v in pairs(self.layout) do L[k] = v end
  L.baseH = self.layout.marginY
  L.footerH = 0
  L.peek = 0
  L.showRowNumbers = false
  return L
end

--- Engine colon scene, arity zero, for the view. What to draw now, a fresh table, so a view
--- reads the engine's state through one call and never reaches into its fields. list is the
--- list model's state, for list/model.lua's pure readers, and a view never writes it.
function Engine:scene()
  return {
    rects = self._rects,
    layout = self.layout,
    drawLayout = self._drawLayout,
    tokens = self._tokens,
    type = self._type,
    list = self.listState,
    rankedQuery = self._rankedQuery,
    placeholder = self._placeholder,
    bare = self._bare,
    footer = self._footerModel,
    keysOpen = self._keysOpen,
  }
end

--------------------------------------------------------------------------------
-- Rows and ranking
--------------------------------------------------------------------------------

-- Asks config.rows for the given query and ranks the answer through lib/chooser/rank.lua
-- against the live matcher, the shared policy both providers read from one place.
--
-- Fix round item one. config.rows is a consumer callback like every other one this file calls
-- outward, so it goes through safeCall and falls back to an empty list rather than being called
-- bare. A raise here used to unwind out of the field's change callback and out of its tap
-- callback, so Hammerspoon let the event through unmodified and the character a person just
-- typed landed in the application underneath while the picker stayed up showing a stale list.
--
-- self._search is the presentation's searchText and rowLimit, handed over beside the matcher
-- through setMatcher, so the rows drawn are the rows the search kept and a list of thousands
-- presents only as many as its limit allows. A searchText that failed ranks nothing, and the
-- reason is said here the way a consumer callback's failure is.
--
-- The limit is the presentation's rowLimit, or ROW_LIMIT when it names none, times the pages the
-- row of more has added since the list was last built from the top. When it cut rows, the row of
-- more stands just after the last row it counted, before any pinned row.
function Engine:_rankedRows(query)
  local items = safeCall(self.config.rows, query) or {}
  local page = self:_rowLimit()
  local search = self._search
  if page then
    search = {}
    for k, v in pairs(self._search or {}) do search[k] = v end
    search.rowLimit = page * (self._pages or 1)
  elseif search and search.rowLimit == false then
    search = { searchText = search.searchText }
  end
  local ranked, reason, more = rank.apply(items, query, self._matcher, search)
  if reason then print("Olm canvas provider, " .. reason) end
  if more and page then
    table.insert(ranked, more.at, moreRow(more.count, page))
  end
  return ranked
end

-- The rows one page of the list holds, the presentation's own rowLimit when it names a number,
-- none when it says false, and ROW_LIMIT otherwise.
function Engine:_rowLimit()
  local own = self._search and self._search.rowLimit
  if own == false then return nil end
  if type(own) == "number" then return own end
  return ROW_LIMIT
end

-- Rebuilds self.listState from config.rows(query), ranked through lib/chooser/rank.lua and
-- presented by the view, then handed to list model with an EMPTY query, the ranking trap this
-- file's header names. Handing over an empty query and no matcher is what keeps list model from
-- ranking at all, it only holds, highlights and scrolls whatever this file already decided the
-- order should be.
--
-- resetHighlight true answers a fresh state, highlight on row one and scrollTop at the top, list
-- model's own newState. False preserves whatever row and scroll position self.listState already
-- held, clamped into whatever range the freshly ranked set can support through list model's own
-- normalized, rather than recomputed to keep that row visible, since a preserved highlight was
-- already on screen before this rebuild and a shrunk list only needs clamping.
--
-- The state this produces holds the rows as the view presented them, which for the canvas view
-- are hs.styledtext values. list model's own setQuery must never be called on this state, since
-- a matcher handed it would build a haystack from those values.
function Engine:_rebuildList(query, resetHighlight)
  -- The query these rows were ranked for, which is what decides the empty state. The field's
  -- text can run ahead of it for the length of a setQuery, so it is kept rather than read back.
  self._rankedQuery = query or ""
  -- A list built from the top, a show, a new query or a refresh from row one, is one page again.
  if resetHighlight or not self.listState then self._pages = 1 end
  local drawReady = self.view:presentRows(self:_rankedRows(query))
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

-- Reports the highlighted row's own opaque item through config.onHighlight, read live on every
-- call, then asks the footer again. There is no highlight poll of any kind, since this file
-- knows the instant its own highlight moves and calls this directly from wherever that happens.
function Engine:_fireHighlight()
  if self.config.onHighlight then
    local row = listModel.highlightedRow(self.listState)
    safeCall(self.config.onHighlight, rowItem(row))
  end
  -- After the consumer heard the move, since a label in the action bar may follow the row. The
  -- answer is whether the bar's words changed, for a caller that does not redraw anyway.
  return self:_refreshFooter()
end

--------------------------------------------------------------------------------
-- The action bar's model and its key panel, docs/PLAN-ACTION-BAR.md
--------------------------------------------------------------------------------

-- Asks the footer collaborator for the model of the list now showing and keeps it, answering
-- whether what it says changed. The collaborator is config.footer, a function this file knows
-- only as answering lib/hints.lua's footerModel shape, so no keymap and no plugin is named here.
-- Without one there is no model and no bar.
function Engine:_refreshFooter()
  if not self.config.footer or self._bare then
    self._footerModel = nil
    return false
  end
  local model = safeCall(self.config.footer)
  if type(model) ~= "table" then model = nil end
  local before = self._footerModel and self._footerModel.state
  self._footerModel = model
  return (model and model.state) ~= before
end

-- Polls the footer collaborator while the list is up, the handle kept so the timer can neither
-- be collected before it fires nor outlive the open. Nothing to poll without a collaborator.
function Engine:_startFooterPoll()
  self:_stopFooterPoll()
  if not self.config.footer or self._bare then return end
  self._footerTimer = hs.timer.doEvery(FOOTER_POLL_INTERVAL, function()
    if self.active and self:_refreshFooter() then self.view:redraw() end
  end)
end

function Engine:_stopFooterPoll()
  if self._footerTimer then
    self._footerTimer:stop()
    self._footerTimer = nil
  end
end

-- Closes the key panel, redrawing only when it was open. Every key that acts closes it, since a
-- key that acts is a person who has found what they were looking for.
function Engine:_closeKeys()
  if not self._keysOpen then return end
  self._keysOpen = false
  self.view:redraw()
end

--------------------------------------------------------------------------------
-- Choosing a row, the one answer Return, Command with a digit, and a matching pointer press
-- and release all share
--------------------------------------------------------------------------------

--- Engine colon highlightIndex, arity one, for the view and for choosing. Moves the highlight
--- straight to index, an arbitrary row rather than one step away, which is what a pointer over a
--- row or a row about to be chosen both need. Leaves scrollTop untouched, list model's own
--- normalized only clamps it, matching what a hover is supposed to do, look without moving the
--- viewport.
function Engine:highlightIndex(index)
  local ns = listModel.normalized(self.listState)
  if index < 1 or index > #ns.filtered then return end
  if index == ns.highlight then return end
  ns.highlight = index
  self.listState = listModel.normalized(ns)
  self:_fireHighlight()
  self.view:redraw()
end

--- Engine colon followHighlight, arity one, for a view that moves its own highlight, the swift
--- list's arrows and pointer. The engine's highlight follows to index, counting as activity.
function Engine:followHighlight(index)
  self:_noteActivity()
  self:highlightIndex(index)
end

-- Chooses row, exactly what Return means, including asking config.intercept first and honouring
-- a disabled row, which can be highlighted but never reaches onSelect. intercept answering true
-- or "stay" refreshes and keeps the list up, true from the top and "stay" holding the row.
-- index, when known, is where in the filtered set row sits, moved onto the highlight first so
-- the row being chosen and the row reading as highlighted never disagree.
function Engine:_choose(row, index)
  if not row then return end
  if row.more then
    self:_showMore(index)
    return
  end
  if index then self:highlightIndex(index) end
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

-- The row of more chosen, by Return, a press or a digit. One more page is ranked in and the list
-- rebuilt holding its scroll, with the highlight on the first row it added, the one standing
-- where the row of more stood, so the list reads on from where the person was.
function Engine:_showMore(index)
  local ns = listModel.normalized(self.listState)
  index = index or ns.highlight
  self._pages = (self._pages or 1) + 1
  self.view:stopScroll()
  self:_rebuildList(self._rankedQuery or "", false)
  if index then self:selectRow(index) else self:_fireHighlight() end
  self.view:redraw()
end

-- Command and a digit chooses the row at that place in the list, list model's own rowAtSlot,
-- the third trap this file's header names.
function Engine:_chooseSlot(slot)
  local row, index = listModel.rowAtSlot(self.listState, slot)
  self:_choose(row, index)
end

--- Engine colon chooseIndex, arity one, for the view. Chooses the row at index in the ranked
--- list, a pointer release on the row its press landed on.
function Engine:chooseIndex(index)
  local ns = listModel.normalized(self.listState)
  self:_choose(ns.filtered[index], index)
end

--- Engine colon rightClickIndex, arity one, for the view. Tells config.onRightClick, read live,
--- which row a right press landed on, index nil when it landed on none.
function Engine:rightClickIndex(index)
  local ns = listModel.normalized(self.listState)
  local row = index and ns.filtered[index]
  if row and not row.more and self.config.onRightClick then
    safeCall(self.config.onRightClick, rowItem(row), index)
  end
end

--- Engine colon companionScroll, arity one, for the view. A scroll over the companion pane,
--- handed to config.onScroll with the delta in points, this file having no opinion about what
--- that pane does with it.
function Engine:companionScroll(points)
  if self.config.onScroll then safeCall(self.config.onScroll, points) end
end

--- Engine colon scrollTo and scrollBy, arity one, for the view. Move the list's viewport
--- through list model's own scrollTo and scrollBy, which clamp, and never the highlight.
function Engine:scrollTo(points)
  self.listState = listModel.scrollTo(self.listState, points)
end

function Engine:scrollBy(points)
  self.listState = listModel.scrollBy(self.listState, points)
end

--------------------------------------------------------------------------------
-- What the view tells the engine about keys and text
--------------------------------------------------------------------------------

--- Engine colon fieldChanged, arity one, for the view. Runs on every change the field reports,
--- printable or named, including a plain caret move that touches no text at all. Reranking on
--- every one of those would reset the list back to its own top each time a hand merely moved the
--- caret inside what it had already typed, so this compares against self._lastQuery and only
--- reranks when the text itself actually changed.
---
--- self._suppressRebuild is set only for the length of a programmatic setText this file itself
--- makes, show's own clearing of the field among them and setQuery below, since a view's setText
--- reports the change the identical way a keystroke does, and those callers rebuild for
--- themselves right after.
function Engine:fieldChanged(text)
  -- Text this list wrote itself reaches the hold's chooser too, so typing there carries on from it.
  if self._focusMirror then safeCall(self._focusMirror, text) end
  if self._suppressRebuild then
    self._lastQuery = text
    self.view:redraw()
    return
  end
  if text ~= self._lastQuery then
    self._lastQuery = text
    self.view:stopScroll()
    self:_rebuildList(text, true)
    self:_fireHighlight()
  end
  self._keysOpen = false
  self.view:redraw()
  if self.config.onActivity then safeCall(self.config.onActivity) end
end

-- The signal that a key acted on this list, told to a consumer's onActivity and closing the key
-- panel. A Hyper press never reaches leftoverKey, since the field yields it so the leader
-- dispatch can run, and that dispatch drives selectNext, selectPrev and insertSelected instead,
-- so those count here. A yielded key is deliberately not counted, because the leader
-- autorepeats while held and is not yet a key that acted.
function Engine:_noteActivity()
  if self.config.onActivity then safeCall(self.config.onActivity) end
  self:_closeKeys()
end

--- Engine colon dismissKey, arity one, for the view. Escape, asked before anything can yield it.
--- onActivity fires before hiding, matching legacy.lua's own key watcher, which fires it for
--- every key down including Escape, since Escape is answered before leftoverKey or fieldChanged
--- are ever reached and would otherwise be the one key the idle signal never learns about. ev may
--- be nil for a view that cannot hand over the event, and then it counts as a fresh press.
function Engine:dismissKey(ev)
  -- A held Escape that closed the key panel goes on repeating, and its autorepeat must not
  -- close the list too, so every repeat of that press is swallowed until a fresh one.
  local repeating = ev ~= nil and ev:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat) ~= 0
  if repeating and self._escapeClosedKeys then return end
  self._escapeClosedKeys = false
  if self.config.onActivity then safeCall(self.config.onActivity) end
  -- Escape over an open key panel closes the panel and leaves the list, the way a popover
  -- answers Escape, and a second Escape closes the list.
  if self._keysOpen then
    self._escapeClosedKeys = true
    self:_closeKeys()
    return
  end
  -- The same over an action panel the view floats as a popover, toggled closed through the
  -- action the footer model names for it, since the panel is the root's and not this file's.
  local model = self._footerModel
  if model and model.panelOpen and model.panelAction and self:floatsActionPanel() then
    self._escapeClosedKeys = true
    self:footerAction(model.panelAction)
    return
  end
  self:hide()
end

--- Engine colon yieldsKey, arity one, for the view. Whether a key down belongs downstream and
--- must pass on unclaimed, whatever predicate the composition root injected, read at the moment
--- a key arrives so a configure after this instance was built still takes effect.
function Engine:yieldsKey(ev)
  return YIELDS ~= nil and YIELDS(ev)
end

--- Engine colon listKey, arity one, for the view. Asked after yieldsKey and before the field
--- edits. Answers true when the open list took the key, which the view then claims and does
--- nothing else with. A key it took counts as activity, since it moved or acted on the list the
--- way a Hyper key does.
function Engine:listKey(ev)
  -- Whether the key panel was up before the key, so a key that opened it, the person's own
  -- showKeys chord on the field, is not taken as a key that acted and closes it again.
  local keysWereOpen = self._keysOpen
  if LIST_KEYS == nil or LIST_KEYS(ev) ~= true then
    -- A bare list has no field to type into, so a key the list does not read goes to the
    -- consumer, the stage, which claims it or lets the field swallow it as before.
    if self._bare and not listReads(ev) and self.config.onBareKey then
      return safeCall(self.config.onBareKey, ev) == true
    end
    return false
  end
  if self.config.onActivity then safeCall(self.config.onActivity) end
  if keysWereOpen then self:_closeKeys() end
  return true
end

--- Engine colon emptyBackspace, arity zero, for the view. A backward delete on an empty field
--- with nothing selected. Asks config.back and does nothing at all when it answers anything but
--- true, rather than dismissing, matching what legacy.lua's own colon underscore back does for
--- the identical press.
function Engine:emptyBackspace()
  self:_noteActivity()
  local ask = self.config.back
  if not ask then return end
  if safeCall(ask) ~= true then return end
  self:refresh(true)
end

--- Engine colon leftoverKey, arity one, for the view. A key down the field neither edits nor
--- types, Return, keypad Enter, Up, Down and Command with a digit among them. The view claims it
--- whatever happens here.
--- Fix round item seven. onActivity fires at the top, above the dispatch, since on Return the
--- branch through choosing, onSelect, hide and onClose would otherwise run before it and tell a
--- consumer using it as an idle signal that a key was pressed in a picker that was already gone.
function Engine:leftoverKey(ev)
  self:_noteActivity()
  local code = ev:getKeyCode()
  local digit = KEYCODE_DIGIT[code]
  if digit and ev:getFlags().cmd then
    self:_chooseSlot(digit)
  elseif code == KEYCODE_DOWN then
    self.view:stopScroll()
    self.listState = listModel.moveDown(self.listState)
    self:_fireHighlight()
    self.view:redraw()
  elseif code == KEYCODE_UP then
    self.view:stopScroll()
    self.listState = listModel.moveUp(self.listState)
    self:_fireHighlight()
    self.view:redraw()
  elseif code == KEYCODE_RETURN or code == KEYCODE_KEYPAD_ENTER then
    self:_insertHighlighted()
  end
end

--------------------------------------------------------------------------------
-- Teardown, one idempotent path for every dismissal
--------------------------------------------------------------------------------

-- Every way this picker can end, a selection, Escape, a click outside, or a programmatic hide,
-- funnels through here, and onClose fires exactly once per open however it ended. The view's
-- taps are stopped FIRST, then its timers, then the footer poll, then the surface comes down,
-- then the focus hold is released, and only then does onClose fire. The release and onClose
-- are each guarded so a raise inside either cannot abandon anything below it.
function Engine:_teardown()
  if not self.active then return end
  self.active = false

  self.view:stop()
  self:_stopFooterPoll()
  self._keysOpen = false
  self._escapeClosedKeys = false
  self.view:hide()

  -- After the surface is down and before onClose, so an insert a consumer makes on close lands
  -- in the application that had focus. A raise is printed and never abandons the teardown.
  local release = self._focusRelease
  self._focusRelease, self._focusMirror = nil, nil
  if release then
    local ok, err = pcall(release)
    if not ok then
      print("Olm canvas provider, the focus release failed, " .. tostring(err))
    end
  end

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

--- Engine colon show, arity zero. Reselects the theme and the view's styles, resolves the screen
--- and the rectangles through geometry.resolve, places the surface, builds rows for an empty
--- query with the highlight on row one, clears the field, draws, shows, asks the focus hold,
--- starts the view's input and the footer poll, reports onPositioned exactly once with the final
--- frames, since the surface is final on its first frame, and only then calls onHighlight with
--- the first row, synchronously, which is the whole mechanism rather than a seed for a poll.
function Engine:show()
  self:_selectTheme()
  self.view:restyle()
  self.active = true
  self._textBudget = nil

  local screen = self:_resolveScreen()
  self._targetScreen = screen
  local sf = screen:frame()
  self._rects = geometry.resolve(sf, self:_shapedLayout(), self._paneWidth)
  self:_updateDrawLayout()
  self.view:place(self._rects)

  self:_rebuildList("", true)
  self._suppressRebuild = true
  self.view:setText("")
  self._suppressRebuild = false

  self._keysOpen = false
  self:_refreshFooter()
  self.view:redraw()
  self.view:show()
  -- A show over a list already up keeps the hold it has, since a second would strand the first.
  if not self._focusRelease then
    -- Where a hold relays what the tap cannot hear, typed text and keys alike, into the field.
    local sink = {
      key = function(ev) self.view:feedKey(ev) end,
      text = function(text) self.view:setText(text) end,
    }
    if FOCUS_HOLD then
      local ok, release, mirror = pcall(FOCUS_HOLD, sink)
      if not ok then
        print("Olm canvas provider, the focus hold failed, " .. tostring(release))
      else
        self._focusRelease, self._focusMirror = release, mirror
      end
    end
  end

  self.view:start()
  self:_startFooterPoll()

  self._paneFrames = { chooser = self._rects.chooser, companion = self._rects.companion }
  safeCall(self.config.onPositioned, self._rects.chooser, self._rects.companion)

  if self:_fireHighlight() then self.view:redraw() end
end

--- Engine colon hide, arity zero. The single idempotent dismissal path, calling it when nothing
--- is up is not an error.
function Engine:hide()
  self:_teardown()
end

--- Engine colon isShowing, arity zero. Whether the surface is genuinely on screen right now,
--- the view's own answer rather than this instance's belief about itself.
function Engine:isShowing()
  return self.view:isVisible()
end

--- Engine colon isActive, arity zero. Whether this instance believes it is up, a different
--- question from isShowing, answering self.active.
function Engine:isActive()
  return self.active == true
end

--- Engine colon refresh, arity one. Reranks and redraws for the current query. A truthy
--- resetRow returns the highlight to row one, falsy preserves whatever row and scroll position
--- were already current, clamped rather than recomputed, see colon underscore rebuildList.
--- Fix round item three. Plain truthiness, as the contract and the legacy provider both read it.
function Engine:refresh(resetRow)
  if not self.active then return end
  -- A rebuild from the top is a page change, which closes the key panel the way a key that acts
  -- does. A refresh holding the row is a repaint in place, often a background answer arriving,
  -- and leaves an open key panel alone.
  if resetRow then self._keysOpen = false end
  self.view:stopScroll()
  self:_rebuildList(self:query(), resetRow)
  self:_fireHighlight()
  self.view:redraw()
end

--- Engine colon query, arity zero. The field's own current text.
function Engine:query()
  return self.view:text()
end

--- Engine colon setQuery, arity one. Sets the field text, caret left after it rather than the
--- text standing selected, and rebuilds the list for the new query with the highlight reset to
--- row one.
---
--- Fix round item five. This rebuilds on its own, as hs.chooser colon query does through its
--- own queryChangedCallback, since host/launcher/init.lua calls it in several places with no
--- refresh of its own. A caller that still refreshes right after rebuilds a second time,
--- harmless. self._suppressRebuild keeps the view's own change report from rebuilding a second
--- time inside this very call.
function Engine:setQuery(text)
  text = text or ""
  -- A new query is a new page or a seeded word, so the key panel closes with it.
  self._keysOpen = false
  self._suppressRebuild = true
  self.view:setText(text)
  self._suppressRebuild = false
  self.view:stopScroll()
  self:_rebuildList(text, true)
  self:_fireHighlight()
  self.view:redraw()
end

--- Engine colon setPlaceholder, arity one. Stores the hint text live, handed to the view through
--- the scene on every redraw, drawn dim whenever the field is empty.
function Engine:setPlaceholder(text)
  self._placeholder = text or ""
end

--- Engine colon setRows, arity one. Remembers a row count for this instance's next show,
--- matching what the contract promises. The canvas view could resize live, but the restriction
--- is inherited from the native provider's own promise, so a later phase is free to lift it
--- deliberately once a caller actually wants a live resize.
function Engine:setRows(n)
  self.layout.rowCount = n
end

--- Engine colon rowCount, arity zero. The row count this instance is currently built for.
function Engine:rowCount()
  return self.layout.rowCount
end

--- Engine colon selectNext, arity zero. Moves the highlight down by one, wrapping at the end,
--- list model's own decision, stated as this provider's own end policy the contract asks every
--- provider to state for itself.
function Engine:selectNext()
  if not self.active then return end
  self:_noteActivity()
  self.view:stopScroll()
  self.listState = listModel.moveDown(self.listState)
  self:_fireHighlight()
  self.view:redraw()
end

--- Engine colon selectPrev, arity zero. The same move upward.
function Engine:selectPrev()
  if not self.active then return end
  self:_noteActivity()
  self.view:stopScroll()
  self.listState = listModel.moveUp(self.listState)
  self:_fireHighlight()
  self.view:redraw()
end

--- Engine colon selectRow, arity one. Clamps n into the range the filtered set currently
--- supports and ignores a nil argument rather than raising. Also brings the row into view, fix
--- round item two, since list model deliberately never pulls scrollTop toward the highlight on
--- its own and host/actionpanel/init.lua restores a row that may sit past the visible band. It
--- pulls scrollTop up to the row's own top when it starts above the viewport and down to the
--- row's own bottom less the viewport height when it ends below.
function Engine:selectRow(n)
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
  self.view:redraw()
end

--- Engine colon selectedRow, arity zero. The highlighted row number, or nil.
function Engine:selectedRow()
  local ns = listModel.normalized(self.listState)
  return ns.highlight
end

--- Engine colon selectedItem, arity zero. The opaque item under the highlight, or nil.
function Engine:selectedItem()
  return rowItem(listModel.highlightedRow(self.listState))
end

--- Engine colon insertSelected, arity zero. Behaves exactly as Return does, asking intercept
--- first and honouring a disabled row, through the shared colon underscore choose.
function Engine:insertSelected()
  if not self.active then return end
  self:_noteActivity()
  self:_insertHighlighted()
end

-- The choosing half of insertSelected, split out so Return through leftoverKey, which has
-- already counted as activity at the top of its own handler, does not count twice.
function Engine:_insertHighlighted()
  local ns = listModel.normalized(self.listState)
  local row = ns.highlight and ns.filtered[ns.highlight]
  self:_choose(row, ns.highlight)
end

--- Engine colon toggleKeys, arity zero. Opens the key panel above the action bar, or closes it
--- when it is open, the same as a click on the key button. Not part of the picker contract, since
--- only a provider that draws an action bar has a key panel, so a caller asks for it by name and
--- a provider without one is simply not asked. Does nothing while the list is down or when this
--- instance draws no bar.
function Engine:toggleKeys()
  if not self.active or not (self._rects and self._rects.footer) or not self._footerModel then return end
  self._keysOpen = not self._keysOpen
  self.view:redraw()
end

--- Engine colon footerAction, arity one. Runs the action a pressed entry of the bar names, through
--- config.footerAction, the same dispatch a key runs. Does nothing while the list is down.
function Engine:footerAction(name)
  if not self.active or type(name) ~= "string" then return end
  safeCall(self.config.footerAction, name)
end

--- Engine colon floatsActionPanel, arity zero. True when the view draws the action panel as a
--- popover over the list rather than in place of its rows, see floatsActionPanel in
--- lib/chooser/view.lua, so the panel leaves out the Back row a list of its own would need.
function Engine:floatsActionPanel()
  return type(self.view.floatsActionPanel) == "function" and self.view:floatsActionPanel() == true
end

--- Engine colon closeKeys, arity zero. Closes the key panel when it is open and does nothing
--- otherwise, what the composition root asks before every list key that acts.
function Engine:closeKeys()
  self:_closeKeys()
end

--- Engine colon textBudget, arity zero. The pixel room a row's text has on the screen this
--- picker will open on, resolved lazily and cached for the open through geometry.textBudget.
function Engine:textBudget()
  if not self._textBudget then
    local screen = self._targetScreen or self:_resolveScreen()
    local sf = screen:frame()
    local rects = geometry.resolve(sf, self:_shapedLayout(), self._paneWidth)
    self._textBudget = geometry.textBudget(rects, self.layout)
  end
  return self._textBudget
end

--- Engine colon textWidth, arity two. The rendered pixel width of str at the title size or the
--- subtitle size which selects, a passthrough onto the UI kit's measurer, whose width is the per
--- character sum, the same number the legacy provider answers, so a supplier formatting against
--- it gets one answer from either provider.
function Engine:textWidth(str, which)
  local face = self._type
  if which == "title" then return UI.measure:width(str, face.font, face.textSize) end
  return UI.measure:width(str, face.subFont, face.subSize)
end

--- Engine colon reposition, arity one. Recentres the already shown surface for paneWidth and
--- answers both frames, the companion nil when there is none, and nothing at all when this
--- instance is not up. Fix round item ten. It reads its argument without storing it, since the
--- stored companion policy is setPaneWidth's alone.
function Engine:reposition(paneWidth)
  if not self.active then return nil end
  local screen = self._targetScreen or self:_resolveScreen()
  local sf = screen:frame()
  self._rects = geometry.resolve(sf, self:_shapedLayout(), paneWidth)
  self:_updateDrawLayout()
  self.view:place(self._rects)
  self.view:redraw()
  self._paneFrames = { chooser = self._rects.chooser, companion = self._rects.companion }
  return self._rects.chooser, self._rects.companion
end

--- Engine colon settleDelay, arity zero. Zero seconds, the surface is final on its first frame
--- and has no correction pass to wait out.
function Engine:settleDelay()
  return 0
end

--- Engine colon matcher, arity zero. The current matching strategy, fronting self._matcher, and
--- as a second answer the search beside it, see setMatcher.
function Engine:matcher()
  return self._matcher, self._search
end

--- Engine colon setMatcher, arity one. false and nil are different answers and both survive the
--- round trip through self._matcher. search, optional, is how the rows are searched beside the
--- strategy, { searchText, rowLimit } as lib/chooser/rank.lua's M.apply reads it, and nil clears
--- it, so a presentation declaring neither leaves nothing behind.
function Engine:setMatcher(m, search)
  self._matcher = m
  self._search = search
end

--- Engine colon titleLineBreak, arity zero. The truncation mode a title takes, fronting
--- self.layout.titleLineBreak.
function Engine:titleLineBreak()
  return self.layout.titleLineBreak
end

--- Engine colon setTitleLineBreak, arity one. Sets the live title truncation mode.
function Engine:setTitleLineBreak(mode)
  self.layout.titleLineBreak = mode
end

--- Engine colon setPaneWidth, arity one. Sets the companion width policy for this instance's next
--- placement, true inheriting the surface's own resolved width, a number overriding it, nil or
--- zero meaning no companion, every answer capped at this instance's own paneMaxW wherever
--- geometry.resolve actually reads it.
function Engine:setPaneWidth(w)
  self._paneWidth = w
end

--- Engine colon setPosture, arity one. "bare" draws the list alone and hands every key the list
--- does not read to config.onBareKey, "full" draws the field and the action bar as well, and
--- anything else is read as full. Like setRows it takes effect on the next show.
function Engine:setPosture(word)
  self._bare = word == "bare"
  self._textBudget = nil
end

--- Engine colon posture, arity zero. "bare" or "full".
function Engine:posture()
  return self._bare and "bare" or "full"
end

--------------------------------------------------------------------------------
-- Module surface
--------------------------------------------------------------------------------

local M = {}

--- M.configure(opts) takes opts.ui, the UI kit, opts.yields, a function(event) answering true
--- for a key down the field must let through instead of claiming, opts.listKeys, a
--- function(event) that runs a list key the open list binds with no held leader and answers true
--- when it took the key, and opts.focusHold, a function answering a release function or nil,
--- asked once per open after the surface shows and released on teardown, opts.rowLimit, the
--- most rows a list shows when its presentation names none, false for no default, and
--- opts.moreIcon, { icon, owner }, the row of more's icon. Callable more than once, a nil field
--- left unchanged.
function M.configure(opts)
  opts = opts or {}
  if opts.ui ~= nil then UI = opts.ui end
  if opts.yields ~= nil then YIELDS = opts.yields end
  if opts.listKeys ~= nil then LIST_KEYS = opts.listKeys end
  if opts.focusHold ~= nil then FOCUS_HOLD = opts.focusHold end
  -- false clears the default, a positive whole number sets it, anything else is left unchanged.
  if opts.rowLimit == false then ROW_LIMIT = nil
  elseif type(opts.rowLimit) == "number" and opts.rowLimit >= 1 and opts.rowLimit % 1 == 0 then
    ROW_LIMIT = opts.rowLimit
  end
  if type(opts.moreIcon) == "table" then MORE_ICON = opts.moreIcon end
  return M
end

--- M.uses(keyCode, mods, fieldOp) -> string or nil
--- What the engine or the view's field already does with a chord, in a few words, or nil when
--- neither reads it, so a list key the person binds with no held leader cannot take a key the
--- field needs. mods is a list of shift, ctrl, alt and cmd. Escape always closes, plain Return
--- and keypad Enter choose, and the two vertical arrows move with any modifiers held, since
--- leftoverKey reads their keycode alone. Return or keypad Enter with a modifier is left free,
--- because listKey is asked before leftoverKey sees a key, so a list key on Command and Return
--- answers first and an unclaimed one still chooses. Command with a digit chooses one of the first nine rows.
--- fieldOp(keyCode, flags), the view's own, names the editing operation its field reads on those
--- exact modifiers, or nil. A printable key is the caller's to judge, since what it types depends
--- on the keyboard and not on this file.
function M.uses(keyCode, mods, fieldOp)
  if type(keyCode) ~= "number" then return nil end
  local flags = {}
  for _, m in ipairs(mods or {}) do flags[m] = true end
  if keyCode == KEYCODE_ESCAPE then return "Escape closes the list" end
  if (keyCode == KEYCODE_RETURN or keyCode == KEYCODE_KEYPAD_ENTER)
    and not (flags.shift or flags.ctrl or flags.alt or flags.cmd) then
    return "Return chooses the row"
  end
  if keyCode == KEYCODE_UP or keyCode == KEYCODE_DOWN then return "the arrow moves the highlight" end
  if KEYCODE_DIGIT[keyCode] and flags.cmd then return "Command and a digit choose one of the first nine rows" end
  local op = fieldOp and fieldOp(keyCode, flags)
  if op then return "the field's own " .. op end
  return nil
end

--- M.new(config, makeView) answers an instance satisfying lib/chooser/contract.lua, its view
--- built by makeView(engine) and checked against lib/chooser/view.lua, both raised on a gap here
--- rather than waiting for the facade to notice. Refuses outright when M.configure has not been
--- given the UI kit, since every colour, the type and the layout come from its tokens.
function M.new(config, makeView)
  if not UI then
    error("Chooser engine: M.configure must be called with opts.ui, the UI kit, before "
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
  -- The room inside a row, between its highlighted edge and its icon, is the inner padding, and
  -- the margin wrapping the list below is the outer one.
  local inner = tokens.inner or inset.x
  layout.padX, layout.iconGap = inner, inner
  -- The margin wrapping the list is one value on every side, so a highlighted row sits the
  -- same distance from the bottom edge as from the sides and its corners nest in the
  -- surface's. inset.y stays the text inset inside a row, handed to derivedRows below.
  layout.marginX, layout.marginY = inset.x, inset.x
  -- The gap between the chooser and its companion is that same inset, so one token moves every
  -- padding and every gap together.
  layout.gap = inset.x
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
  -- A consumer handing a footer collaborator gets the action bar, its height from the kit's
  -- tokens, and one handing none draws no bar and keeps every row it had.
  if config.footer then layout.footerH = footerLib.height(tokens) end
  for k, v in pairs(config.layout or {}) do layout[k] = v end

  local self = setmetatable({
    config = config,
    layout = layout,
    _tokens = nil,
    _type = nil,
    _matcher = config.matcher,
    _search = config.search,
    _paneWidth = nil,
    listState = listModel.newState({}, layout, ""),
    active = false,
    _lastQuery = "",
    _suppressRebuild = false,
    _placeholder = config.placeholder or "",
  }, Engine)

  -- Resolved once here as well as on every show, so a row presented or a width measured
  -- before the first show already has the tokens to read.
  self:_selectTheme()

  self.view = makeView(self)
  local viewOk, viewReason = viewContract.validate(self.view)
  if not viewOk then
    error("Chooser engine: the view does not satisfy the view contract, " .. tostring(viewReason))
  end
  -- A view drawing one surface across the canvas and the companion runs the bar under both,
  -- see spansFooter in lib/chooser/view.lua and footerSpan in geometry.resolve.
  -- Such a view also takes no gap, since the list's margin already stands between a row and the
  -- divider and the pane pads its content by the same inset, and a gap would sit between them as
  -- well and leave a row wider room on its right than on its left. A consumer's gap still wins.
  if type(self.view.spansFooter) == "function" and self.view:spansFooter() == true then
    layout.footerSpan = true
    if not (config.layout and config.layout.gap) then layout.gap = 0 end
  end
  -- A view whose bar is not the default row answers its own height, see footerHeight in
  -- lib/chooser/view.lua, unless the consumer's layout already set one.
  if config.footer and type(self.view.footerHeight) == "function"
      and not (config.layout and config.layout.footerH) then
    layout.footerH = self.view:footerHeight(tokens)
  end

  local ok, reason = contract.validate(self)
  if not ok then
    error("Chooser engine: the instance does not satisfy the picker contract, " .. tostring(reason))
  end

  return self
end

return M
