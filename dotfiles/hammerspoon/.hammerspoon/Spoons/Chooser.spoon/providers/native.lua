--- === Chooser ===
---
--- A themed, keyboard driven chooser atom, the reusable mechanism behind the
--- clipboard picker and any similar tool. It owns only the chooser window, its
--- theming, row styling, j and k navigation, close on a key, top biased
--- positioning, and the click away dismissal. It knows nothing about clipboards,
--- caffeinate, HyperKey, or a preview. Each consumer injects its own rows, the
--- meaning of a selection, the field behavior, and an optional docked companion.
---
--- This is a FACTORY, not a singleton spoon. Call spoon.Chooser.new(config) to
--- get an independent instance, so two tools never share one chooser. The
--- composition root creates the instance, injects the theme and callbacks, and
--- binds a Hyper context to the four navigation methods (selectNext, selectPrev,
--- insertSelected, close).
---
--- Config (all optional unless noted):
---   theme        palette source { dark = {...}, light = {...} }, each with
---                bgDark, titleColor, subColor, and preview (a color set the
---                consumer reads for a companion). Injected from config.
---   screen       function() -> hs.screen, the display the chooser appears on.
---                Resolved once per show, before the chooser takes focus, and the
---                window is then forced onto that screen. Defaults to
---                hs.screen.mainScreen when omitted.
---   rows         REQUIRED supplier function(query) -> list of plain items, each
---                { title, subTitle, image, enabled, item, filterText }. Called on
---                show, refresh, and (in filter mode) on every query change. When a
---                matcher is set the supplier returns the full candidate list and the
---                atom filters and ranks it, so the supplier no longer filters itself.
---   matcher      function(query, hay) -> score or nil, from Chooser.matchers, usually
---                injected as the module default. When set and in filter mode, the atom
---                keeps only rows whose filterText matches and orders them by score,
---                original order breaking ties. false opts out (supplier owns
---                filtering), the default for a tool whose query is not a plain filter.
---   filterText   per-row, the text the matcher searches, defaulting to the title plus
---                the subtitle. A row sets it to fold in hidden keywords or synonyms.
---   onSelect     function(item) fired when a row is chosen (Return or the insert
---                key). Not fired for a disabled row or an empty dismissal.
---   onHighlight  function(item) fired when the highlight moves. Drives a
---                companion like the clipboard preview. Omit it and no poll runs.
---   onClose      function() fired once when the chooser tears down for any
---                reason (select, escape, click away, programmatic close).
---   onActivity   function() fired on every key press while the chooser is open, via a
---                passive eventtap (never consuming the key). A caller uses it as an
---                idle signal, e.g. to defer a docked hint panel until the user pauses.
---   onPositioned function(chooserFrame, companionFrame) fired after layout, both
---                a seed frame at show and a corrected frame once the real window
---                settles. A consumer docks its companion into companionFrame.
---   onInput      function(text) fired on Return while in input field mode.
---   fieldMode    "filter" (query filters rows), "off" (query inert), "input"
---                (query is a typed value, Return calls onInput), or "hybrid"
---                (rows plus a typed value, Return submits the text when the field
---                is non empty else selects the row). Default filter.
---   placeholder  the empty field hint.
---   layout       sizes: widthPct, paneMaxW, rowH, baseH, rowCount, gap, topFrac,
---                minVPad, companionWidth (0 for no companion), and the row font
---                (font, titleSize, subSize).

local obj = {}
obj.__index = obj
obj.name = "Chooser"
obj.version = "1.0"
obj.author = "mdj-env"

-- Minimal dark palette used only if no theme is injected, so an instance still
-- renders. The one duplicated color set, kept here as the seam.
local FALLBACK = {
  dark = {
    bgDark = true,
    titleColor = { white = 0.92 },
    subColor = { white = 0.55 },
    preview = { bg = "#1e1e22", fg = "#dcdcdc", meta = "#8a8a8a", path = "#7a7a7a", note = "#c8a86a" },
  },
}

local DEFAULT_LAYOUT = {
  widthPct = 32,
  paneMaxW = 480,
  rowH = 42,
  baseH = 94,
  rowCount = 10,
  gap = 12,
  topFrac = 0.06,
  minVPad = 60,
  companionWidth = 0,
  font = ".AppleSystemUIFont",
  titleSize = 16,
  subSize = 12,
}

--------------------------------------------------------------------------------
-- Instance
--------------------------------------------------------------------------------

local Chooser = {}
Chooser.__index = Chooser

-- Row styling. hs.chooser has no font-size setting, but a row's text and subText
-- accept an hs.styledtext, so the font and color are set per row from the active
-- palette. A disabled row dims its title so it reads as inert. One line per row,
-- cut with an ellipsis rather than wrapping.
local function styledText(str, size, color, font)
  return hs.styledtext.new(str or "", {
    font = { name = font, size = size },
    color = color,
    paragraphStyle = { lineBreak = "truncateTail" },
  })
end

local function dim(color)
  local c = {}
  for k, v in pairs(color) do c[k] = v end
  c.alpha = 0.4
  return c
end

-- Point self.theme at the palette matching the current system appearance.
-- interfaceStyle is "Dark" in dark mode and nil in light, so anything but Dark
-- reads as light. Falls back to the dark entry when a light palette is absent.
-- Reselected on each show, so every open reflects the live theme (it tracks the
-- automatic light and dark switch). A flip while open is picked up on the next
-- open, not mid-session.
function Chooser:_selectTheme()
  local p = self.config.theme or FALLBACK
  local dark = hs.host.interfaceStyle() == "Dark"
  self.theme = (dark and p.dark) or p.light or p.dark or FALLBACK.dark
end

-- Turn one plain item from the supplier into an hs.chooser choice, styling it
-- with the active palette and carrying the opaque item back on a private key.
function Chooser:_toChoice(it)
  local L = self.layout
  local enabled = it.enabled ~= false
  local titleColor = enabled and self.theme.titleColor or dim(self.theme.titleColor)
  return {
    text = styledText(it.title, L.titleSize, titleColor, L.font),
    subText = styledText(it.subTitle, L.subSize, self.theme.subColor, L.font),
    image = it.image,
    _item = it.item,
    _enabled = enabled,
  }
end

-- The text the matcher searches for a row, the explicit filterText or the title plus
-- the subtitle. Kept here so a supplier that adds no filterText still matches on what
-- it shows, exactly the haystack the old per-consumer substring tests used.
local function haystackOf(it)
  return it.filterText or ((it.title or "") .. " " .. (it.subTitle or ""))
end

-- Run the consumer's supplier for the current query and map to chooser choices,
-- keeping the mapped list so navigation and selection can read items back. With a
-- matcher set and a non-empty query in filter mode the atom owns filtering: score every
-- candidate, drop the misses, and sort by score with the original order breaking ties,
-- so a stable secondary order like the launcher's recency still shows through. The
-- styling in _toChoice then runs only for the survivors, so a heavy list styles a few
-- matched rows per keystroke rather than all of them. Without a matcher, or on an empty
-- query, every returned item is kept in order, the pre-injection behaviour, which is
-- also the path a supplier that owns its own filtering (matcher = false) always takes.
function Chooser:_build(query)
  local items = self.config.rows and self.config.rows(query) or {}
  local matcher = self.matcher
  local out = {}
  if type(matcher) == "function" and self.fieldMode == "filter" and query ~= "" then
    local ranked = {}
    for i = 1, #items do
      local score = matcher(query, haystackOf(items[i]))
      if score ~= nil then
        ranked[#ranked + 1] = { it = items[i], score = score, idx = i }
      end
    end
    table.sort(ranked, function(a, b)
      if a.score ~= b.score then return a.score > b.score end
      return a.idx < b.idx
    end)
    for i = 1, #ranked do
      out[i] = self:_toChoice(ranked[i].it)
    end
  else
    for i = 1, #items do
      out[i] = self:_toChoice(items[i])
    end
  end
  self.currentChoices = out
  return out
end

--------------------------------------------------------------------------------
-- Teardown, one idempotent path for every dismissal
--------------------------------------------------------------------------------

function Chooser:_teardown()
  if not self.active then return end
  self.active = false
  if self.pollTimer then
    self.pollTimer:stop()
    self.pollTimer = nil
  end
  if self.clickWatcher then
    self.clickWatcher:stop()
    self.clickWatcher = nil
  end
  if self.activityWatcher then
    self.activityWatcher:stop()
    self.activityWatcher = nil
  end
  if self.config.onClose then
    self.config.onClose()
  end
end

--------------------------------------------------------------------------------
-- Positioning, with an optional reserved companion pane
--------------------------------------------------------------------------------

-- The display this open should appear on. Injected as config.screen by the root, so
-- the atom does not name the policy; resolved here once at show, before the chooser
-- takes focus, since resolving later (in the settle callback) would see the chooser's
-- own window as focused. Falls back to hs.screen.mainScreen when nothing is injected.
function Chooser:_resolveScreen()
  local fn = self.config.screen
  local s = fn and fn()
  return s or hs.screen.mainScreen() or hs.screen.primaryScreen()
end

-- Vertical top-left on screen sf: biased toward the top by topFrac, never closer
-- than minVPad to either edge. When too tall to keep both pads the top pad wins.
function Chooser:_topBiasedY(sf, paneH)
  local L = self.layout
  local floor, max, min = math.floor, math.max, math.min
  local lo = sf.y + L.minVPad
  local hi = sf.y + sf.h - L.minVPad - paneH
  if hi < lo then hi = lo end
  return max(lo, min(sf.y + floor(sf.h * L.topFrac), hi))
end

-- Rect to the right of the chooser for the companion, or nil when none.
function Chooser:_companionFrame(x, y, chooserW, h)
  local L = self.layout
  if not L.companionWidth or L.companionWidth <= 0 then return nil end
  return { x = x + chooserW + L.gap, y = y, w = math.min(L.companionWidth, L.paneMaxW), h = h }
end

-- The chooser clamps its own height to fit the screen, so its rendered height is
-- known only once it shows. Read the real window a moment after it appears and place
-- it authoritatively on the target screen, the same one the seed used: centered
-- horizontally (accounting for the companion pane) and top biased, then recompute the
-- companion rect beside it and report both. Forcing the position rather than adapting
-- to wherever hs.chooser dropped it is what keeps the chooser on the policy's display,
-- even when the widget came up shorter than requested or on another screen.
function Chooser:_settleFrames()
  hs.timer.doAfter(0.03, function()
    if not self.active then return end
    local app = hs.application.get("Hammerspoon")
    if not app then return end
    for _, w in ipairs(app:allWindows()) do
      if (w:title() or "") == "Chooser" and w:isVisible() then
        local L = self.layout
        local cf = w:frame()
        local sf = (self._targetScreen or w:screen() or hs.screen.mainScreen()):frame()
        local companionW = (L.companionWidth and L.companionWidth > 0)
          and math.min(L.companionWidth, L.paneMaxW) or 0
        local total = cf.w + (companionW > 0 and (L.gap + companionW) or 0)
        local x = sf.x + math.floor((sf.w - total) / 2)
        local y = self:_topBiasedY(sf, cf.h)
        w:setTopLeft({ x = x, y = y })
        local chooserFrame = { x = x, y = y, w = cf.w, h = cf.h }
        local companionFrame = self:_companionFrame(x, y, cf.w, cf.h)
        self.paneFrames = { chooser = chooserFrame, companion = companionFrame }
        if self.config.onPositioned then
          self.config.onPositioned(chooserFrame, companionFrame)
        end
        return
      end
    end
  end)
end

function Chooser:_positionAndShow()
  local L = self.layout
  -- Resolve the target display once, now, before hs.chooser:show steals focus, and
  -- keep it for the settle correction that runs after the window appears.
  self._targetScreen = self:_resolveScreen()
  local f = self._targetScreen:frame()
  local floor, min, max = math.floor, math.min, math.max

  -- Trim the row count so the pair fits between the mandatory pads on a short
  -- screen. On a tall screen the full request survives.
  local avail = f.h - 2 * L.minVPad
  local maxRows = max(1, floor((avail - L.baseH) / L.rowH))
  local rows = min(L.rowCount, maxRows)
  self.chooser:rows(rows)
  local paneH = L.baseH + rows * L.rowH

  local chooserW = min(floor(f.w * L.widthPct / 100), L.paneMaxW)
  local companionW = (L.companionWidth and L.companionWidth > 0) and min(L.companionWidth, L.paneMaxW) or 0
  local total = chooserW + (companionW > 0 and (L.gap + companionW) or 0)
  local x = f.x + floor((f.w - total) / 2)
  local y = self:_topBiasedY(f, paneH)

  -- hs.chooser width is a percent of the screen, so translate the capped pixel
  -- width back to a percent right before showing.
  self.chooser:width(chooserW / f.w * 100)

  -- Seed the frames so the companion and the click watcher have rects before the
  -- settle correction lands. Report the seed so a consumer can show its companion.
  local chooserFrame = { x = x, y = y, w = chooserW, h = paneH }
  local companionFrame = self:_companionFrame(x, y, chooserW, paneH)
  self.paneFrames = { chooser = chooserFrame, companion = companionFrame }
  if self.config.onPositioned then
    self.config.onPositioned(chooserFrame, companionFrame)
  end

  self.chooser:show({ x = x, y = y })
  self:_settleFrames()
  self:_startPollLoop()
  self:_startClickWatcher()
  self:_startActivityWatcher()
end

--------------------------------------------------------------------------------
-- Activity watcher (only when a consumer listens)
--------------------------------------------------------------------------------

-- Fire onActivity on every key press while the chooser is up, so a consumer can use it
-- as an idle signal (a deferred hint panel resets its countdown on each key). The tap
-- only observes, returning false so the key still reaches the chooser's field.
function Chooser:_startActivityWatcher()
  if not self.config.onActivity then return end
  if self.activityWatcher then self.activityWatcher:stop() end
  self.activityWatcher = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function()
    if self.active then self.config.onActivity() end
    return false
  end)
  self.activityWatcher:start()
end

--------------------------------------------------------------------------------
-- Highlight poll (only when a consumer listens)
--------------------------------------------------------------------------------

function Chooser:_startPollLoop()
  if not self.config.onHighlight then return end
  if self.pollTimer then self.pollTimer:stop() end
  self.lastRow = nil
  self.pollTimer = hs.timer.doEvery(self.config.pollInterval or 0.08, function()
    if not self.chooser or not self.chooser:isVisible() then
      self:_teardown()
      return
    end
    local row = self.chooser:selectedRow()
    if row ~= self.lastRow then
      self.lastRow = row
      local choice = self.currentChoices[row]
      self.config.onHighlight(choice and choice._item or nil)
    end
  end)
end

--------------------------------------------------------------------------------
-- Click away dismissal
--------------------------------------------------------------------------------

local function pointInFrame(p, fr)
  return fr and p.x >= fr.x and p.x <= fr.x + fr.w and p.y >= fr.y and p.y <= fr.y + fr.h
end

-- The topmost standard window under a screen point, front to back.
local function windowUnderPoint(p)
  for _, w in ipairs(hs.window.orderedWindows()) do
    if w:isStandard() and pointInFrame(p, w:frame()) then
      return w
    end
  end
  return nil
end

-- Watch mouse-downs while the chooser is up. A click inside the chooser or its
-- companion is a real interaction, passed straight through. A click outside both
-- is a dismissal: tear down, capture the clicked window, hide the chooser so its
-- focus restore is queued first, then focus that window so it wins, and consume
-- the click so nothing re-activates after. This ordering is flicker free.
function Chooser:_startClickWatcher()
  if self.clickWatcher then self.clickWatcher:stop() end
  self.clickWatcher = hs.eventtap.new({ hs.eventtap.event.types.leftMouseDown }, function(e)
    local p = e:location()
    local fr = self.paneFrames or {}
    if pointInFrame(p, fr.chooser) or pointInFrame(p, fr.companion) then
      return false
    end
    local target = windowUnderPoint(p)
    self:_teardown()
    if self.chooser then
      self.chooser:hide() -- queues hs.chooser's restore to the old app first
    end
    if target then
      target:focus() -- queued last, so the clicked window wins the focus race
    end
    return true -- consume, so the click does not re-activate anything after
  end)
  self.clickWatcher:start()
end

--------------------------------------------------------------------------------
-- Completion (Return, click, escape)
--------------------------------------------------------------------------------

function Chooser:_completion(choice)
  -- Text submit. In input mode Return always commits the typed value. In hybrid
  -- mode, where rows and a typed value coexist, Return commits the text only when
  -- the field is non empty, otherwise it selects the highlighted row below.
  local q = self.chooser and self.chooser:query() or ""
  if self.config.onInput and (self.fieldMode == "input" or (self.fieldMode == "hybrid" and q ~= "")) then
    self:_teardown()
    self.config.onInput(q)
    return
  end
  local item, enabled = nil, true
  if choice then
    item = choice._item
    enabled = choice._enabled
  end
  -- onSelect fires first, so the consumer sees any pre-close state (like a
  -- collected batch) before onClose runs in teardown. A disabled row or an empty
  -- dismissal selects nothing.
  if item and enabled and self.config.onSelect then
    self.config.onSelect(item)
  end
  self:_teardown()
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Chooser:show() - reselect the theme, build rows, place and reveal.
function Chooser:show()
  if not self.chooser then return end
  self:_selectTheme()
  self.chooser:bgDark(self.theme.bgDark)
  self.active = true
  self.chooser:query("")
  self.chooser:choices(self:_build(""))
  -- Seed the highlight so a companion has content before the first poll tick.
  if self.config.onHighlight then
    self.config.onHighlight(self.currentChoices[1] and self.currentChoices[1]._item or nil)
  end
  self:_positionAndShow()
end

--- Chooser:hide() - dismiss and tear down.
function Chooser:hide()
  self:_teardown()
  if self.chooser then self.chooser:hide() end
end

--- Chooser:close() - alias for hide, the name a Hyper context binds to.
function Chooser:close()
  self:hide()
end

function Chooser:isShowing()
  return self.chooser ~= nil and self.chooser:isVisible()
end

--- Chooser:refresh(resetRow) - re-run the supplier for the current query. By default the
--- highlighted row is preserved (setting choices otherwise resets it to the top), which is
--- what a live in-place update wants. Pass resetRow true to jump the highlight back to the
--- first row, for a consumer that swaps the list wholesale, like a menu changing levels.
function Chooser:refresh(resetRow)
  if not self.chooser then return end
  local row = self.chooser:selectedRow()
  self.chooser:choices(self:_build(self.chooser:query() or ""))
  if resetRow then
    self.chooser:selectedRow(1)
  elseif row then
    self.chooser:selectedRow(row)
  end
end

--- Chooser:setQuery(text) - set the field text, clearing it with "". A consumer that changes
--- what the list means, like a menu drilling in, clears the filter so the new level is not
--- narrowed by what was typed at the previous one.
function Chooser:setQuery(text)
  if self.chooser then self.chooser:query(text or "") end
end

-- Move the highlight by delta through the chooser's own selectedRow so it scrolls
-- natively. Clamps at the ends rather than wrapping.
function Chooser:_move(delta)
  if not self:isShowing() then return end
  local n = #self.currentChoices
  if n == 0 then return end
  local r = (self.chooser:selectedRow() or 1) + delta
  if r < 1 then r = 1 end
  if r > n then r = n end
  self.chooser:selectedRow(r)
end

function Chooser:selectNext() self:_move(1) end
function Chooser:selectPrev() self:_move(-1) end

--- Chooser:insertSelected() - choose the highlighted row, exactly as Return does.
--- chooser:select fires the completion callback, so the onSelect path runs.
function Chooser:insertSelected()
  if not self:isShowing() then return end
  local r = self.chooser:selectedRow()
  if r and r >= 1 then self.chooser:select(r) end
end

--- Chooser:selectedItem() - the opaque item under the highlight, or nil.
function Chooser:selectedItem()
  local c = self.currentChoices[self.chooser and self.chooser:selectedRow() or 0]
  return c and c._item or nil
end

--- Chooser:setFieldMode(mode) - switch the field between filter, off, and input
--- at runtime. In input mode the placeholder should state the expected format.
function Chooser:setFieldMode(mode)
  self.fieldMode = mode or "filter"
end

--- Chooser:setPlaceholder(text) - update the empty-field hint live.
function Chooser:setPlaceholder(text)
  if self.chooser then self.chooser:placeholderText(text or "") end
end

--- Chooser:activeTheme() - the palette selected for this open, so a consumer can
--- style a companion (its preview colors live under .preview).
function Chooser:activeTheme()
  return self.theme
end

--- Chooser:query() - the current field text.
function Chooser:query()
  return self.chooser and self.chooser:query() or ""
end

--------------------------------------------------------------------------------
-- Factory
--------------------------------------------------------------------------------

--- Chooser.new(config) -> instance. Builds the hs.chooser once and reuses it
--- across shows. hs.chooser settles to a compact height on the second and later
--- shows, which is the steady state the row font is tuned against.
function obj.new(config)
  config = config or {}
  local layout = {}
  for k, v in pairs(DEFAULT_LAYOUT) do layout[k] = v end
  for k, v in pairs(config.layout or {}) do layout[k] = v end

  local self = setmetatable({
    config = config,
    layout = layout,
    fieldMode = config.fieldMode or "filter",
    -- The injected filter strategy, resolved by the facade to the module default when
    -- the consumer named none. A function means the atom filters; false or nil means it
    -- does not and the supplier owns filtering.
    matcher = config.matcher,
    currentChoices = {},
    active = false,
    theme = FALLBACK.dark,
  }, Chooser)

  self:_selectTheme()

  local c = hs.chooser.new(function(choice) self:_completion(choice) end)
  c:bgDark(self.theme.bgDark)
  c:width(layout.widthPct)
  c:rows(layout.rowCount)
  c:placeholderText(config.placeholder or "")
  -- Setting queryChangedCallback disables hs.chooser's built-in matching, so the
  -- consumer's supplier owns filtering. Only filter mode refilters on typing; off
  -- and input leave the rows as they were built.
  c:queryChangedCallback(function(q)
    if self.fieldMode == "filter" then
      c:choices(self:_build(q))
      self.lastRow = nil -- top row changed, force a highlight refresh
    end
  end)
  -- Right click hands the consumer the item under the row (clipboard deletes it),
  -- which then calls refresh to redraw. Wired only when a handler is given.
  if config.onRightClick then
    c:rightClickCallback(function(row)
      local ch = self.currentChoices[row]
      if ch then config.onRightClick(ch._item, row) end
    end)
  end
  self.chooser = c
  return self
end

return obj
