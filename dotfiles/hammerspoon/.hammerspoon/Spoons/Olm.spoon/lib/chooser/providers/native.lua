--- === Chooser ===
---
--- A themed, keyboard driven chooser atom, the reusable mechanism behind the
--- clipboard picker and any similar tool. It owns only the chooser window, its
--- theming, row styling, j and k navigation, close on a key, top biased
--- positioning, and the click away dismissal. It knows nothing about what its
--- rows mean. Each consumer injects its own rows, the meaning of a selection, the
--- field behavior, and an optional docked companion.
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
---   intercept    function(item) -> true to keep the chooser open. Asked BEFORE a row is
---                allowed to complete, so a row can mean "this list becomes another list"
---                rather than "act and close". The consumer does whatever the row meant,
---                rewriting the field or swapping its whole row supplier, and answers true,
---                and the atom then rebuilds the list from the top and stays open. That is
---                what makes a list you drill through stop flickering. false or nil is the
---                usual answer and the row completes as always. The atom deliberately does
---                not learn what the row meant, only that it was not a completion. Filter
---                mode only, since a field whose Return commits a typed value cannot also
---                mean navigate.
---   back         function() -> true when it went back. Asked on Backspace while the field
---                is EMPTY, which is the one press that otherwise does nothing at all, so a
---                consumer that swapped its list can step out of it the way deleting a
---                typed scope steps out of that. Answering true consumes the key and
---                rebuilds the list; anything else lets it through untouched.
---   onHighlight  function(item) fired when the highlight moves. Drives a
---                companion like the clipboard preview. Omit it and no poll runs.
---   onClose      function() fired once when the chooser tears down for any
---                reason (select, escape, click away, programmatic close).
---   onActivity   function() fired on every key press while the chooser is open, via a
---                passive eventtap (never consuming the key). A caller uses it as an
---                idle signal, e.g. to defer a docked hint panel until the user pauses.
---   onScroll     function(points) fired when a trackpad or a wheel scrolls over the
---                COMPANION rect, handing over how far to move the content in points,
---                positive being further down it, so a consumer never sees an event and
---                never has an opinion about direction. Omit it and no tap runs. A
---                companion is an hs.canvas, which has no scroll callback of its own, so
---                this is the only way a pane can be scrolled by hand.
---   onPositioned function(chooserFrame, companionFrame) fired after layout, both
---                a seed frame at show and a corrected frame once the real window
---                settles. A consumer docks its companion into companionFrame.
---   onInput      function(text) fired on Return while in input field mode.
---   fieldMode    "filter" (query filters rows), "off" (query inert), "input"
---                (query is a typed value, Return calls onInput), or "hybrid"
---                (rows plus a typed value, Return submits the text when the field
---                is non empty else selects the row). Default filter.
---   placeholder  the empty field hint.
---   layout       sizes: width (chooser width in px, the uniform default 480 unless
---                a consumer overrides it, clamped to the screen; set false to use
---                the responsive widthPct-of-screen-capped-at-paneMaxW fallback
---                instead); plus rowH, baseH, rowCount, gap, topFrac, minVPad,
---                companionWidth (0 for no companion), and the row font (font,
---                titleSize, subSize). Width is always worked in pixels and converted
---                to hs.chooser's percentage internally (see below).

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
  -- Uniform default chooser width, in points. Every chooser is this wide unless it
  -- passes its own layout.width. Set width = false to opt out and use the responsive
  -- fallback (widthPct of the screen, capped at paneMaxW) instead of a fixed width.
  width = 480,
  widthPct = 32,   -- responsive fallback width, used only when width is false/nil
  paneMaxW = 480,  -- companion pane cap, and the widthPct cap for the fallback
  rowH = 42,
  baseH = 94,
  rowCount = 10,
  gap = 12,
  topFrac = 0.06,
  minVPad = 60,
  -- One width serves the chooser and the pane. true inherits the chooser's own
  -- resolved width for that show. A number overrides it independently, the same as
  -- today. paneMaxW caps both. Zero, nil, and false all mean no pane.
  companionWidth = 0,
  font = ".AppleSystemUIFont",
  titleSize = 16,
  subSize = 12,
  -- Where a title too long for its row loses characters. The tail is right for almost
  -- everything, since a name is read left to right and the front is what identifies it.
  -- A consumer whose titles are FILENAMES wants "truncateMiddle" instead, because the last
  -- few characters of a filename are its extension and losing that is losing the one thing
  -- a tail cut could have kept. It is a per consumer choice rather than a global because it
  -- genuinely differs, the clipboard's titles being snippets where the front is everything.
  -- Subtitles are always cut at the tail, since nothing has asked otherwise.
  titleLineBreak = "truncateTail",
}

-- The horizontal room a row loses to everything on it that is not text, so what is left
-- is what a title or a subtitle actually has. MEASURED rather than derived, by walking a
-- live chooser through the accessibility API, because hs.chooser exposes no geometry at
-- all and its window comes from a compiled nib with nothing readable in it.
--
-- 61 points lead, the left pad plus the icon column, and 65 trail, the right pad plus the
-- command number badge the widget draws on a row. Four things were checked before trusting
-- one number for all of it. It held at 360, 480 and 640 point windows, so it is a constant
-- to subtract and not a fraction to scale. It was identical on a row carrying an icon and a
-- row carrying none, since the icon column is reserved either way. It did not change past
-- the ninth row where the badge stops being drawn. And the title and the subtitle reported
-- the same column to the point, which is why one budget answers for both.
local ROW_TEXT_INSET = 126

--------------------------------------------------------------------------------
-- Instance
--------------------------------------------------------------------------------

local Chooser = {}
Chooser.__index = Chooser

-- Row styling. hs.chooser has no font-size setting, but a row's text and subText
-- accept an hs.styledtext, so the font and color are set per row from the active
-- palette. A disabled row dims its title so it reads as inert. One line per row,
-- cut with an ellipsis rather than wrapping.
local function styledText(str, size, color, font, lineBreak)
  return hs.styledtext.new(str or "", {
    font = { name = font, size = size },
    color = color,
    paragraphStyle = { lineBreak = lineBreak or "truncateTail" },
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
    text = styledText(it.title, L.titleSize, titleColor, L.font, L.titleLineBreak),
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
  if type(matcher) == "function" and self.fieldMode == obj.fieldModes.filter and query ~= "" then
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
  if self.settleTimer then
    self.settleTimer:stop()
    self.settleTimer = nil
  end
  if self.clickWatcher then
    self.clickWatcher:stop()
    self.clickWatcher = nil
  end
  if self.keyWatcher then
    self.keyWatcher:stop()
    self.keyWatcher = nil
  end
  if self.scrollWatcher then
    self.scrollWatcher:stop()
    self.scrollWatcher = nil
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

-- Resolves layout.companionWidth to a pane width in pixels for this show, or 0 for
-- no pane, given chooserW, the chooser's own resolved width for this same show. true
-- means the pane inherits chooserW, capped by paneMaxW exactly as a number is capped.
-- A number is the independent override, also capped. nil, false, and any number at
-- or below zero all mean no pane. This is the one place the boolean is turned into a
-- number, since every comparison downstream is against a number and Lua errors
-- comparing a boolean to one. All three read sites route through this.
function Chooser:_resolveCompanionWidth(chooserW)
  local L = self.layout
  local cw = L.companionWidth
  if cw == true then cw = chooserW end
  if not cw or cw <= 0 then return 0 end
  return math.min(cw, L.paneMaxW)
end

-- Rect to the right of the chooser for the companion, or nil when none.
function Chooser:_companionFrame(x, y, chooserW, h)
  local L = self.layout
  local w = self:_resolveCompanionWidth(chooserW)
  if w <= 0 then return nil end
  return { x = x + chooserW + L.gap, y = y, w = w, h = h }
end

-- The chooser clamps its own height to fit the screen, so its rendered height is
-- known only once it shows. Read the real window a moment after it appears and place
-- it authoritatively on the target screen, the same one the seed used: centered
-- horizontally (accounting for the companion pane) and top biased, then recompute the
-- companion rect beside it and report both. Forcing the position rather than adapting
-- to wherever hs.chooser dropped it is what keeps the chooser on the policy's display,
-- even when the widget came up shorter than requested or on another screen.
-- The timer is held in a field, because a Hammerspoon timer is userdata whose finalizer
-- stops it, so one nothing refers to can be collected before it fires. Losing this settle
-- leaves the chooser wherever hs.chooser dropped it, which looks like a placement bug and
-- is not one. A re-show stops the previous settle first, since it is measuring a frame that
-- no longer exists and the newer one supersedes it.
function Chooser:_settleFrames()
  if self.settleTimer then self.settleTimer:stop() end
  self.settleTimer = hs.timer.doAfter(0.03, function()
    if not self.active then return end
    local app = hs.application.get("Hammerspoon")
    if not app then return end
    for _, w in ipairs(app:allWindows()) do
      if (w:title() or "") == "Chooser" and w:isVisible() then
        local L = self.layout
        local cf = w:frame()
        local sf = (self._targetScreen or w:screen() or hs.screen.mainScreen()):frame()
        local companionW = self:_resolveCompanionWidth(cf.w)
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

-- Width handling. hs.chooser exposes no pixel width, only a percentage, and that
-- percentage is measured against hs.screen.mainScreen(), the screen holding the
-- focused window when the chooser opens, not the screen the chooser is shown on and
-- not the primary. hs.window cannot resize the panel afterward either. So the atom
-- does all width work in pixels and converts to that percentage against the main
-- screen in exactly one place, below, which is the chooser's true contract rather
-- than a guess: dividing by the target or the primary width scaled the window by
-- mainW/thatW whenever they differed, which fixed-mode placement on a non-focused
-- display exposed (a 480px pin came out 211px or ~1090px depending on focus).

-- The chooser's target width in pixels on screen sf. An explicit layout.width wins,
-- clamped to the screen, so a consumer can pin a fixed width; otherwise it is the
-- responsive layout.widthPct of the target screen capped at layout.paneMaxW, which
-- keeps it ~480px on a normal display and only shrinks on a narrow one.
function Chooser:_desiredWidthPx(sf)
  local L = self.layout
  if L.width then return math.min(L.width, sf.w) end
  return math.min(math.floor(sf.w * L.widthPct / 100), L.paneMaxW)
end

-- The percentage to hand hs.chooser so a window of desiredPx pixels comes out that
-- wide on whatever screen it lands on. Divides by the main screen width, the base
-- hs.chooser applies the percentage to. Resolved at show time (just before the
-- chooser takes focus), so mainScreen is still the previously focused window's
-- screen, the one the percentage will be measured against.
function Chooser:_widthPercentFor(desiredPx)
  local mainW = (hs.screen.mainScreen() or self._targetScreen):frame().w
  return desiredPx / mainW * 100
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

  local chooserW = self:_desiredWidthPx(f)
  local companionW = self:_resolveCompanionWidth(chooserW)
  local total = chooserW + (companionW > 0 and (L.gap + companionW) or 0)
  local x = f.x + floor((f.w - total) / 2)
  local y = self:_topBiasedY(f, paneH)

  -- Pixels in, percentage out (see _widthPercentFor: hs.chooser measures against the
  -- primary screen), so the window is chooserW wide on whatever screen it lands on.
  self.chooser:width(self:_widthPercentFor(chooserW))

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
  self:_startKeyWatcher()
  self:_startScrollWatcher()
end

--------------------------------------------------------------------------------
-- Key watcher (only when a consumer listens)
--------------------------------------------------------------------------------

-- Return and the keypad's Enter, the two keys hs.chooser treats as "take this row", plus
-- Backspace, which it treats as nothing once the field is empty.
local SUBMIT_KEYCODES = { [36] = true, [76] = true }
local BACKSPACE_KEYCODE = 51

-- One tap over every key press while the chooser is up, serving three consumers.
--
-- onActivity is an idle signal (a deferred hint panel resets its countdown on each key),
-- and it only observes.
--
-- intercept is the one thing here that has to consume a key. hs.chooser hardwires Return to
-- complete and offers no hook before that happens, so by the time a consumer is told a row
-- was chosen the window is already gone, and a row whose whole meaning is that this list
-- becomes another list has nothing left to change. Taking Return away from the widget is the
-- only place such a row can still be answered. Verified rather than assumed: an eventtap
-- returning true on Return leaves the chooser open with nothing selected, where the same
-- press let through closes it and chooses the row.
--
-- back is the way out of that. A consumer that swapped its list needs a press meaning step
-- out again, and Backspace on an empty field is the honest one, since it already means delete
-- the last thing I typed and there is nothing left to delete. It is also the same press that
-- steps out of a typed scope, where deleting the space hands the list back, so one habit
-- covers both.
--
-- The item and its enabled flag under the highlight right now, together. selectedItem()
-- alone used to be enough for the keyboard path, back when only _completion asked about
-- enabled and it read the choice itself. The stage's own contract v3 intercept probe reads
-- a plugin's own onSelect from inside intercept now, so intercept has to know a row's
-- enabled state too, the identical fact the click watcher already reads off its own choice
-- before ever calling _intercept. One lookup, shared by both callers below, so neither drifts
-- from how the other learns it.
function Chooser:_highlightedChoice()
  local c = self.currentChoices[self.chooser and self.chooser:selectedRow() or 0]
  return c and c._item or nil, c and c._enabled
end

-- Every other key falls straight through, and so does Return on a row that answers no.
function Chooser:_startKeyWatcher()
  if not (self.config.onActivity or self.config.intercept or self.config.back) then return end
  if self.keyWatcher then self.keyWatcher:stop() end
  self.keyWatcher = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
    if not self.active then return false end
    if self.config.onActivity then self.config.onActivity() end
    local code = e:getKeyCode()
    if SUBMIT_KEYCODES[code] then
      local item, enabled = self:_highlightedChoice()
      if self:_intercept(item, enabled) then return true end
    end
    if code == BACKSPACE_KEYCODE and self:_back() then
      return true
    end
    return false
  end)
  self.keyWatcher:start()
end

-- Ask the consumer whether a row means something other than completing, and rebuild if it
-- did. Asking here rather than at each caller is what makes Return, the insert key and a
-- click agree, since one of them is the widget's and the other two are ours.
--
-- The consumer is the one that acts, because what a row meant is its business and the atom
-- would only be guessing at it. All the atom does is rebuild from the top afterwards, since
-- the list now means something else and the highlight should not stay on whatever row number
-- the previous level left it on.
--
-- enabled, a second argument now, review findings H1 and H2, is forwarded straight to ask
-- rather than judged here, since what a disabled row should do is the consumer's own policy
-- and this atom already trusts the consumer with the identical question over a plain item.
-- Every consumer of this atom is the stage today, and the stage answers true and does
-- nothing for a disabled row, before asking anything else, which is what keeps a guidance
-- row from being actionable through Return or the insert key the way the click watcher's own
-- inline check already kept it from being actionable through a click.
function Chooser:_intercept(item, enabled)
  local ask = self.config.intercept
  if not ask or not item or self.fieldMode ~= obj.fieldModes.filter then return false end
  if ask(item, enabled) ~= true then return false end
  self:refresh(true)
  return true
end

-- Step out of a swapped list, but only from an empty field, so Backspace stays ordinary
-- editing for every press that has a character to delete.
function Chooser:_back()
  local ask = self.config.back
  if not ask or self.fieldMode ~= obj.fieldModes.filter then return false end
  if (self.chooser and self.chooser:query() or "") ~= "" then return false end
  if ask() ~= true then return false end
  self:refresh(true)
  return true
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
-- Reaching the widget's own parts, which it exposes no other way
--------------------------------------------------------------------------------

-- hs.chooser hands out no field, no rows and no hit testing, so two features here have to read
-- the window macOS drew. The accessibility tree carries all of it with exact frames, which is the
-- same route the row text inset was measured by. Nothing else in this file goes near it.

local function pointInFrame(p, fr)
  return fr and p.x >= fr.x and p.x <= fr.x + fr.w and p.y >= fr.y and p.y <= fr.y + fr.h
end

-- The first descendant holding one of these roles, depth limited so a malformed tree cannot spin.
-- The chooser's parts carry no identifier to ask for, so they are found by role.
local FIELD_ROLES = { AXTextField = true, AXComboBox = true }
local TABLE_ROLES = { AXTable = true, AXOutline = true }

local function findByRole(element, roles, depth)
  if depth > 6 then return nil end
  for _, kid in ipairs(element:attributeValue("AXChildren") or {}) do
    if roles[kid:attributeValue("AXRole")] then return kid end
    local found = findByRole(kid, roles, depth + 1)
    if found then return found end
  end
  return nil
end

-- The visible chooser window. Only one is ever visible however many instances exist, which is
-- the same assumption the frame settle above already makes.
local function chooserWindowElement()
  local app = hs.application.get("Hammerspoon")
  local axApp = app and hs.axuielement.applicationElement(app)
  if not axApp then return nil end
  for _, w in ipairs(axApp:attributeValue("AXWindows") or {}) do
    if (w:attributeValue("AXTitle") or "") == "Chooser" then return w end
  end
  return nil
end

--------------------------------------------------------------------------------
-- Click away dismissal
--------------------------------------------------------------------------------

-- The topmost standard window under a screen point, front to back.
local function windowUnderPoint(p)
  for _, w in ipairs(hs.window.orderedWindows()) do
    if w:isStandard() and pointInFrame(p, w:frame()) then
      return w
    end
  end
  return nil
end

--- Chooser:_rowAtPoint(p) -> row number or nil
--- The row under a screen point. Read from the accessibility tree, where every row carries its
--- own frame, rather than computed from the layout numbers. That is not fastidiousness. The
--- widget renders rows at its own height and settles to a more compact one after the first show,
--- so a row number worked out from `rowH` would be right on some opens and off by one on others,
--- and being off by one here means acting on the wrong row.
---
--- Rows come back in display order, so counting them gives the same index the choices list uses.
--- The table's last child is a column rather than a row, which is why only rows are counted.
function Chooser:_rowAtPoint(p)
  local window = chooserWindowElement()
  local table_ = window and findByRole(window, TABLE_ROLES, 0)
  if not table_ then return nil end
  local n = 0
  for _, kid in ipairs(table_:attributeValue("AXChildren") or {}) do
    if kid:attributeValue("AXRole") == "AXRow" then
      n = n + 1
      if pointInFrame(p, kid:attributeValue("AXFrame")) then return n end
    end
  end
  return nil
end

-- Watch the mouse while the chooser is up, for three cases.
--
-- A click on a row the consumer intercepts is answered here and goes no further, because the
-- widget's only answer to a click is to complete, and completing is the thing an intercept
-- exists to avoid. So a click means what the keyboard means on the same row, which is what a
-- click should mean. It costs an accessibility read to learn which row was hit, since the widget
-- moves its highlight on the RELEASE and so cannot be asked while the button is still down,
-- measured rather than assumed. The release is then swallowed too, so the widget never sees
-- half a click it might act on once the list under the pointer has changed.
--
-- Any other click inside the chooser or its companion is a real interaction, passed straight
-- through.
--
-- A click outside both is a dismissal: tear down, capture the clicked window, hide the chooser
-- so its focus restore is queued first, then focus that window so it wins, and consume the
-- click so nothing re-activates after. This ordering is flicker free.
function Chooser:_startClickWatcher()
  if self.clickWatcher then self.clickWatcher:stop() end
  local types = hs.eventtap.event.types
  self.clickWatcher = hs.eventtap.new({ types.leftMouseDown, types.leftMouseUp }, function(e)
    local p = e:location()
    local fr = self.paneFrames or {}
    if e:getType() == types.leftMouseUp then
      -- Only ever true for the release of a press this watcher already answered.
      local swallow = self._swallowMouseUp
      self._swallowMouseUp = false
      return swallow == true
    end
    if pointInFrame(p, fr.chooser) or pointInFrame(p, fr.companion) then
      if self.config.intercept then
        local row = self:_rowAtPoint(p)
        local choice = row and self.currentChoices[row]
        if choice and choice._enabled ~= false and self:_intercept(choice._item) then
          self._swallowMouseUp = true
          return true
        end
      end
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
-- Scroll over the companion (only when a consumer listens)
--------------------------------------------------------------------------------

-- What one wheel notch is worth in points. A wheel reports whole notches while a
-- trackpad reports pixels, so a notch has to be given a size, and this is the same
-- distance the clipboard already moves per key press, which keeps a notch and a press
-- feeling like the same amount of movement.
local WHEEL_NOTCH_POINTS = 120

-- Watch scrolls while the chooser is up, and answer only for the companion rect.
--
-- A companion is an hs.canvas and a canvas has no scroll callback, so without this a
-- trackpad over a preview pane does nothing at all and the pane can only be moved by
-- the keys bound to it. This lives in the atom rather than in a pane because the atom
-- is the piece that already owns the rects and already runs taps, so one watcher here
-- gives every companion the same gesture instead of each pane growing its own.
--
-- Outside the rect it returns false untouched, which matters twice. A scroll over the
-- list is hs.chooser's own and must reach it, and a scroll anywhere else on screen
-- belongs to whatever is under the pointer.
--
-- The delta is normalised HERE in both senses, so a consumer is handed a distance to
-- move its content by and never an event.
--
-- The unit first. A trackpad sends continuous events measuring in pixels while a wheel
-- sends discrete notches, and telling them apart is what keeps one press of a wheel from
-- moving a pane by a single point.
--
-- Then the direction. The event measures the FINGERS and a pane measures its CONTENT, so
-- the two run opposite ways and the sign is flipped once here. Doing it in the atom
-- rather than in each pane is the difference between one negation and one per consumer,
-- all of which would have to agree. Natural scrolling stays the system's preference,
-- since it flips the event before this ever sees it.
function Chooser:_startScrollWatcher()
  if not self.config.onScroll then return end
  if self.scrollWatcher then self.scrollWatcher:stop() end
  local props = hs.eventtap.event.properties
  self.scrollWatcher = hs.eventtap.new({ hs.eventtap.event.types.scrollWheel }, function(e)
    local fr = self.paneFrames or {}
    if not pointInFrame(e:location(), fr.companion) then return false end
    local points
    if e:getProperty(props.scrollWheelEventIsContinuous) ~= 0 then
      points = e:getProperty(props.scrollWheelEventPointDeltaAxis1)
    else
      points = e:getProperty(props.scrollWheelEventDeltaAxis1) * WHEEL_NOTCH_POINTS
    end
    if points and points ~= 0 then self.config.onScroll(-points) end
    return true
  end)
  self.scrollWatcher:start()
end

--------------------------------------------------------------------------------
-- Completion (Return, click, escape)
--------------------------------------------------------------------------------

function Chooser:_completion(choice)
  -- Text submit. In input mode Return always commits the typed value. In hybrid
  -- mode, where rows and a typed value coexist, Return commits the text only when
  -- the field is non empty, otherwise it selects the highlighted row below.
  local q = self.chooser and self.chooser:query() or ""
  if self.config.onInput and (self.fieldMode == obj.fieldModes.input
    or (self.fieldMode == obj.fieldModes.hybrid and q ~= "")) then
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
  -- Dropped before the first build asks for it, so an open on a narrower display gets
  -- that display's budget rather than the one the last open happened to land on.
  self._textBudget = nil
  self.chooser:query("")
  self.chooser:choices(self:_build(""))
  -- Always open at the top. hs.chooser reuses one instance across shows and would
  -- otherwise restore the row the last open left highlighted, so a reopen would flash
  -- the old scroll position before snapping back. Resetting the highlight here, before
  -- the window is revealed in _positionAndShow, makes every open start at the first row
  -- with no visible jump.
  self.chooser:selectedRow(1)
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
  -- The list was just rebuilt, so whatever the highlight is sitting on is a different row
  -- than it was, even when the NUMBER has not moved. The poll compares that number, so
  -- without this a companion pane keeps describing the row that used to be in that
  -- position. The same clearing the query callback already does, for the same reason.
  self.lastRow = nil
end

--- Chooser:setQuery(text) - set the field text, clearing it with "". A consumer that changes
--- what the list means, like a menu drilling in, clears the filter so the new level is not
--- narrowed by what was typed at the previous one.
---
--- The caret lands after the text, which takes a second step because hs.chooser:query leaves
--- everything it just wrote SELECTED. Text handed to a field on the user's behalf is the start
--- of what they are about to type, so a selection turns the next character into a deletion of
--- the whole thing. Seeding `t ` and typing would silently drop the scope and search for the
--- letter instead, which reads as the seeding never having worked.
function Chooser:setQuery(text)
  if not self.chooser then return end
  text = text or ""
  self.chooser:query(text)
  if text ~= "" then self:_caretToEnd() end
end

-- Put the caret after everything in the search field, replacing the selection hs.chooser made.
-- There is no field object and no caret api, so the field is reached through the accessibility
-- helpers above. It takes effect at once, so this needs no timer and no second attempt.
--
-- The length is asked of the field rather than counted here, since a range is in the units
-- AppKit stores and Lua counts bytes. Counting UTF8 characters is the fallback, which is
-- exact for anything but an astral character and lands the caret slightly early rather than
-- selecting anything if one appears.
function Chooser:_caretToEnd()
  local window = chooserWindowElement()
  local field = window and findByRole(window, FIELD_ROLES, 0)
  if not field then return end
  local n = field:attributeValue("AXNumberOfCharacters")
  if type(n) ~= "number" then
    local value = field:attributeValue("AXValue") or ""
    n = utf8.len(value) or #value
  end
  field:setAttributeValue("AXSelectedTextRange", { location = n, length = 0 })
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
---
--- Including the intercept question, which is what "exactly as Return does" has to mean. This
--- key is ours and Return is the widget's, so the two reach the same answer only by asking
--- the same thing, and the shared check lives in _intercept for that reason. Review finding
--- H2, rework, reads _highlightedChoice rather than selectedItem alone now, the identical
--- fix _startKeyWatcher already needed, so a disabled row cannot be actioned through this key
--- either.
function Chooser:insertSelected()
  if not self:isShowing() then return end
  local item, enabled = self:_highlightedChoice()
  if self:_intercept(item, enabled) then return end
  local r = self.chooser:selectedRow()
  if r and r >= 1 then self.chooser:select(r) end
end

--- Chooser:selectedItem() - the opaque item under the highlight, or nil.
function Chooser:selectedItem()
  local c = self.currentChoices[self.chooser and self.chooser:selectedRow() or 0]
  return c and c._item or nil
end

--- Chooser:selectedRow() - the highlighted row number, or nil. The plain public counterpart
--- of selectedItem above, added for ActionPanel, phase eight of the build plan, which has to
--- put the highlight back on a row number rather than on an item, since the row it restores to
--- may by then hold a different item than the one captured when the panel opened.
function Chooser:selectedRow()
  return self.chooser and self.chooser:selectedRow() or nil
end

--- Chooser:selectRow(n) - set the highlighted row, clamped to the number of rows currently
--- built so a caller cannot ask for a row that is not there. Added for ActionPanel alongside
--- selectedRow above. Clears self.lastRow afterward, the same clearing refresh already does
--- and for the same reason, so the highlight poll notices that what is under the cursor
--- changed rather than describing the row that used to sit at this number.
---
--- A nil n answers by doing nothing rather than raising on the comparison below. Not reachable
--- today, since every caller reads n from selectedRow first, but selectedRow itself can answer
--- nil, an empty list among the ways, so this stays a guard rather than an assumption.
function Chooser:selectRow(n)
  if not self.chooser or n == nil then return end
  local count = #self.currentChoices
  if count == 0 then return end
  if n < 1 then n = 1 end
  if n > count then n = count end
  self.chooser:selectedRow(n)
  self.lastRow = nil
end

--- Chooser.fieldModes - the four field modes, published so a caller writes
--- Chooser.fieldModes.filter rather than the bare string "filter". A closed set this
--- file owns because this is the only file that reads one, enumerated in prose in the
--- config doc above since before it existed, so publishing it states once what was
--- already stated twice. A member's value is its own name, so nothing a consumer stores
--- or logs changes.
obj.fieldModes = { filter = "filter", off = "off", input = "input", hybrid = "hybrid" }

--- Chooser.memberFieldMode(mode) - the mode when it is one of the set, else filter with
--- one warning naming what was given and what is allowed. Shared by the constructor and
--- by setFieldMode so both answer a bad value the same way, which they did not when each
--- wrote its own `or "filter"` and neither looked at what it had been handed.
function obj.memberFieldMode(mode)
  if mode == nil then return obj.fieldModes.filter end
  for _, member in pairs(obj.fieldModes) do
    if mode == member then return mode end
  end
  local names = {}
  for name in pairs(obj.fieldModes) do names[#names + 1] = name end
  table.sort(names)
  print("Chooser: fieldMode was given " .. tostring(mode) .. ", which is not one of "
    .. table.concat(names, ", ") .. ", so filter is used")
  return obj.fieldModes.filter
end

--- Chooser:setFieldMode(mode) - switch the field between filter, off, input and
--- hybrid at runtime. In input mode the placeholder should state the expected format.
--- An unknown mode warns and falls back to filter rather than being stored, since a
--- stored typo leaves a field that silently does nothing and nothing anywhere saying why.
function Chooser:setFieldMode(mode)
  self.fieldMode = obj.memberFieldMode(mode)
end

--- Chooser:setPlaceholder(text) - update the empty-field hint live.
function Chooser:setPlaceholder(text)
  if self.chooser then self.chooser:placeholderText(text or "") end
end

--- Chooser:setRows(n) - remember a new row count for this instance's NEXT show. Docs/
--- PROBE-FINDINGS-2026-08-27.md section C2 found that a live window does not resize when
--- rows() is called on it directly, and that the pending count applies cleanly on the
--- following hide and show with no rebuild at all, the same finding that let width work the
--- identical way. This is a plain passthrough onto layout.rowCount, the one field
--- _positionAndShow already reads to ask the widget how tall to draw, so it changes nothing
--- about a window already on screen. A caller wanting the resize to actually show hides and
--- shows around this call itself, host/stage/init.lua being the one caller this exists for,
--- the one permitted lib/chooser change of the geometry phase per docs/BRIEF-GEOMETRY.md.
function Chooser:setRows(n)
  self.layout.rowCount = n
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
-- How much a row can say, which only the atom can answer
--------------------------------------------------------------------------------

-- Why this lives here at all. A consumer writing a subtitle wants to know whether it
-- will be cut, and answering that needs the chooser's pixel width, the row font, the row
-- font size and the inset above. The atom is the only layer holding all four, so it
-- answers the question and every consumer decides for itself what to do with the answer.
-- Handing back a shortened string instead would put policy in the widget, and how to
-- shorten a path is a file tool's business rather than a list widget's.

--- Chooser:textBudget() -> the pixel room a row's text has, title and subtitle alike.
---
--- Resolved lazily and cached for the open, since show builds its rows BEFORE it places
--- the window, so there is no width to read at the moment the first supplier runs. The
--- screen it resolves against is the same one the placement will pick, so the number is
--- right on the first build rather than right from the second keystroke onward.
function Chooser:textBudget()
  if not self._textBudget then
    local sf = (self._targetScreen or self:_resolveScreen() or hs.screen.mainScreen()):frame()
    self._textBudget = math.max(0, self:_desiredWidthPx(sf) - ROW_TEXT_INSET)
  end
  return self._textBudget
end

--- Chooser:textWidth(str, which) -> how wide that string renders in a row, in pixels.
--- `which` is "title" or "sub" and picks the font size the row will actually use.
---
--- SUMMED FROM A PER CHARACTER TABLE rather than measured whole, which is the trade the
--- whole feature rests on. Measuring a whole subtitle costs 0.11 ms, so a page of two
--- hundred rows would spend 22 ms per keystroke. Measuring each distinct character once
--- and adding costs 0.003 ms a string, thirty six times less, and a page disappears into
--- the noise. The characters in a row are drawn from a tiny alphabet that repeats across
--- every row, so the table fills in the first few rows and never grows again.
---
--- The price is kerning, which the sum cannot see. Measured against true whole string
--- widths it runs 0.7 percent high on real paths, under two pixels on a 254 pixel string.
--- HIGH is the direction that matters. Over counting shortens marginally early, which
--- looks like nothing, where under counting would let a string through that then gets
--- cut, which is the exact failure this exists to prevent. So there is no fudge factor,
--- the error already leans the safe way.
---
--- Stepped by UTF8 sequence and not by byte, because a path can hold anything and the
--- ellipsis this feeds is itself three bytes. Measuring those bytes one at a time returns
--- nothing for each and would undercount a shortened string to zero.
function Chooser:textWidth(str, which)
  if not str or str == "" then return 0 end
  local L = self.layout
  local size = (which == "title") and L.titleSize or L.subSize
  local memo = self._charWidths[size]
  if not memo then
    memo = {}
    self._charWidths[size] = memo
  end
  local style = { font = L.font, size = size }
  local total, i, n = 0, 1, #str
  while i <= n do
    -- A plain byte is its own character, so the common path skips utf8.offset entirely.
    -- Paths and ages are almost all ASCII and this runs on every row of every keystroke.
    local ch, nxt
    if str:byte(i) < 0x80 then
      ch, nxt = str:sub(i, i), i + 1
    else
      nxt = utf8.offset(str, 2, i) or (n + 1)
      ch = str:sub(i, nxt - 1)
    end
    local w = memo[ch]
    if not w then
      local sz = hs.drawing.getTextDrawingSize(ch, style)
      w = (sz and sz.w) or 0
      memo[ch] = w
    end
    total = total + w
    i = nxt
  end
  return total
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
    -- Adversarial review finding L4, the geometry phase of the chooser stage build.
    -- host/stage/init.lua reads layout.rowCount, layout.gap, and layout.paneMaxW, and writes
    -- layout.companionWidth and paneFrames, directly, on the one instance it owns, the same
    -- kind of seam decision five of docs/BRIEF-STAGE.md already opened for config, which the
    -- ActionPanel decorator mutates in place for the identical reason, this atom storing both
    -- by reference and reading them live rather than copying either at construction. No
    -- method here exposes either field, so a reader of this file has no way to learn that
    -- from here alone, and this comment is what closes that gap. Whichever of
    -- _positionAndShow and
    -- _settleFrames runs next still overwrites paneFrames on its own terms regardless of what
    -- a caller last wrote there, since neither reads it back, only companionWidth is ever
    -- read live by this file's own arithmetic.
    layout = layout,
    fieldMode = obj.memberFieldMode(config.fieldMode),
    -- The injected filter strategy, resolved by the facade to the module default when
    -- the consumer named none. A function means the atom filters; false or nil means it
    -- does not and the supplier owns filtering.
    matcher = config.matcher,
    currentChoices = {},
    active = false,
    theme = FALLBACK.dark,
    -- Character widths per font size, kept for the life of the instance rather than the
    -- open, since a character in a fixed font at a fixed size renders the same forever
    -- and both are settled here at construction.
    _charWidths = {},
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
    if self.fieldMode == obj.fieldModes.filter then
      c:choices(self:_build(q))
      self.lastRow = nil -- top row changed, force a highlight refresh
    end
  end)
  -- Right click hands the consumer the item under the row (a consumer may delete it),
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
