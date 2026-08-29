--- === Workspaces.engine ===
---
--- The mechanism half of Workspaces, one state machine with two modes. In steady state it
--- watches windows move and records where they were put. In an episode it goes deaf, waits for
--- the display geometry to stop moving, and then puts every window it remembers back. It knows
--- nothing about the chooser and nothing about DisplayProfiles. The plugin composition root in
--- init.lua hands it a store and a callback and wires the rest.
---
--- A CONFIGURATION IS GEOMETRY, NEVER MONITOR IDENTITY. The fingerprint is every screen's
--- fullFrame in points, sorted by origin, joined into one string. So vendor, model, pixel
--- resolution, and plug order all stop mattering, and two identical panels can never be
--- confused, because a window is keyed to a position in point space rather than to a panel.
--- Two geometrically identical desks in different places deliberately share one configuration,
--- which was accepted outright when this was chosen, since what a window placement actually
--- depends on is the rectangles it can sit in and nothing else.
---
--- TWO LAYERS OF MEMORY, AND THEY ANSWER DIFFERENT QUESTIONS. The session layer is in memory
--- only, per fingerprint, window id to frame, and it restores every individual window exactly
--- after a dock or undock within one login, multi window apps included, because a window id
--- stays meaningful for as long as the window lives. The persistent layer is the JSON store,
--- per fingerprint, app bundle id to one frame, and it survives a reboot and drives fresh
--- launch placement, at the price of one frame per app. The session layer wins wherever it has
--- an answer, so exactness is used whenever it is available and durability covers the rest.
---
--- THE TWO GUARDS ARE HARVESTED FROM WINDOWMEMORY AND BOTH REST ON REAL STATE RATHER THAN A
--- CLOCK. The compare and skip test is the steady state guard, a move is recorded only when the
--- new frame differs from the stored one by more than a small tolerance, so the asynchronous
--- echo of our own placement is ignored without timing anything and the write is idempotent.
--- The episode flag handles the different problem of a display change, where macOS shuffles
--- every window for a second or two before settling. Those moves are noise rather than intent,
--- so from the moment a screen change or a wake arrives the flag is set and recording stops.
--- Compare and skip alone could not cover that, because during the shuffle the frames genuinely
--- differ from what is stored, so the garbage would be recorded before the restore could
--- correct it.
---
--- QUIESCENCE DECIDES WHEN THE EPISODE ENDS, NOT A FIXED WAIT. The idle timer is reset by every
--- further screen event and every window move, so it fires only once the geometry has actually
--- gone quiet. That is what orders this plugin after DisplayProfiles with no coupling to it at
--- all, since every displayplacer change DisplayProfiles makes is itself a screen event that
--- resets the timer. A hard ceiling from the moment the episode opened guarantees progress if
--- something keeps resetting it forever, and a safety backstop spanning the whole worst case
--- clears the flag even if no restore ever runs, so a missed signal can never wedge recording
--- off.
---
--- A SLOW WAKING DISPLAY NEEDS MORE THAN ONE PASS, also harvested. An external monitor can
--- report as connected the instant its cable is live and only start displaying seconds later, so
--- a window whose remembered frame sits on it would be placed onto coordinates that map to no
--- live screen and macOS would clamp it onto whatever display is awake. So a window is placed
--- only when its frame's center lands on a screen attached right now, and a pass that had to
--- defer any window schedules another, up to a bounded number. The retries are safe to repeat
--- because compare and skip makes a pass that changes nothing a no op, and the episode stays
--- open across the whole campaign so the shuffle is never recorded.

local E = {}
E.__index = E

local log = hs.logger.new("Workspaces", "info")

-- How far a window may drift before the move counts as intent rather than as the echo of our
-- own placement or an app nudging its own window by a pixel.
local TOLERANCE = 5

-- A burst of window moves is one intention, so writes are coalesced over this window rather
-- than rewriting the whole file on every event of a drag.
local PERSIST_DEBOUNCE = 2.0

-- The episode's own timings. IDLE is how long the geometry has to stay still before the
-- restore runs, reset by every further screen event and every window move. CEILING is measured
-- from the moment the episode opened and guarantees progress if something never lets the idle
-- timer expire. QUIET_BEAT is the tail past the last restore move, so the trailing asynchronous
-- events from our own placement stay suppressed.
local IDLE = 1.0
local CEILING = 10.0
local QUIET_BEAT = 0.75

-- The retry campaign for a display that has not finished waking. One pass every RETRY_INTERVAL
-- seconds up to MAX_RETRIES, about a dozen seconds, long enough for a slow monitor without
-- retrying forever.
local RETRY_INTERVAL = 2.0
local MAX_RETRIES = 6

-- The backstop that force clears the episode flag, spanning the whole worst case episode plus
-- slack, so it can never fire mid campaign and reopen recording while a slow display is still
-- being waited for.
local SAFETY_SPAN = CEILING + MAX_RETRIES * RETRY_INTERVAL + QUIET_BEAT + 2.0

-- How long to wait after a window is born before placing it. An app that positions its own
-- window at birth does so within a frame or two, so placing immediately means fighting it and
-- usually losing.
local BIRTH_DELAY = 0.5

-- How long recording stays deaf around a placement the engine made outside an episode. The
-- compare and skip guard already covers the echo, so this is belt and suspenders for the one
-- case where the app moves its own window in response to ours.
local MUTE_TAIL = 0.3

-- Hammerspoon's own windows, its console, its choosers, and every canvas overlay, are never
-- recorded and never placed.
local OWN_BUNDLE = "org.hammerspoon.Hammerspoon"

-- Configured state
E._store = nil       -- the persistent layer, or nil when no path was given
E._onChange = nil    -- injected, called when the active configuration changes so a view can redraw

-- Owned state
E._filter = nil      -- hs.window.filter over all standard windows
E._screens = nil     -- hs.screen.watcher, opens an episode on any change
E._wake = nil        -- hs.caffeinate.watcher, opens an episode on system did wake
E._idle = nil        -- the quiescence timer, reset by every disturbance
E._ceiling = nil     -- the hard progress guarantee from the moment the episode opened
E._safety = nil      -- the backstop that force clears the episode flag
E._tail = nil        -- the quiet beat past the last restore move
E._retry = nil       -- the next pass of a retry campaign
E._persist = nil     -- the debounced write
E._births = nil      -- pending fresh launch placements, keyed by window id
E._mutes = nil       -- pending mute releases, one entry per outstanding mute
E._muted = 0         -- how many placements outside an episode are still suppressing recording
E._episode = false   -- true while capture is deaf
E._resolving = false -- true once the episode has stopped waiting and started restoring
E._session = nil     -- { [fingerprint] = { [windowId] = frame } }
E._fingerprint = nil -- the configuration attached right now

--------------------------------------------------------------------------------
-- Geometry
--------------------------------------------------------------------------------

-- Points come back as numbers that may carry float noise, and a fingerprint that differs in the
-- last decimal is a different desk to a string comparison, so every value is rounded once here
-- and nothing downstream ever sees a fraction.
local function whole(v)
  return math.floor((tonumber(v) or 0) + 0.5)
end

-- Whether two frames are the same within the tolerance, the compare and skip test.
local function sameFrame(a, b, tol)
  return math.abs(a.x - b.x) <= tol
    and math.abs(a.y - b.y) <= tol
    and math.abs(a.w - b.w) <= tol
    and math.abs(a.h - b.h) <= tol
end

-- Whether a remembered frame lands on a screen attached right now, tested by its center. A
-- frame whose center is on no attached screen means a display that has not finished waking, so
-- the window is deferred rather than placed onto coordinates macOS would clamp onto the wrong
-- panel. The containment is done by hand against each screen's full frame, since hs.screen.find
-- matches a name or an id, never a point.
local function targetScreenReady(f)
  local cx = f.x + f.w / 2
  local cy = f.y + f.h / 2
  for _, s in ipairs(hs.screen.allScreens()) do
    local fr = s:fullFrame()
    if cx >= fr.x and cx < fr.x + fr.w and cy >= fr.y and cy < fr.y + fr.h then
      return true
    end
  end
  return false
end

-- A window worth placing, standard and neither minimized nor fullscreen, and not one of ours.
local function placeable(win)
  if win == nil then return false end
  if not win:isStandard() then return false end
  if win:isMinimized() or win:isFullScreen() then return false end
  local app = win:application()
  if app and app:bundleID() == OWN_BUNDLE then return false end
  return true
end

-- Every standard window of one app, which is what the one window rule below is asked about.
local function standardWindowsOf(app)
  local n = 0
  for _, w in ipairs((app and app:allWindows()) or {}) do
    if w:isStandard() then n = n + 1 end
  end
  return n
end

-- Where one screen sits relative to the primary, by the larger of the two center offsets, so a
-- monitor slightly higher than the built in panel beside it still reads as left or right rather
-- than as above.
local function relationOf(primary, other)
  local dx = (other.x + other.w / 2) - (primary.x + primary.w / 2)
  local dy = (other.y + other.h / 2) - (primary.y + primary.h / 2)
  if math.abs(dx) >= math.abs(dy) then
    return dx < 0 and "left" or "right"
  end
  return dy < 0 and "above" or "below"
end

-- A readable name for a configuration nobody has named yet, derived from the geometry alone so
-- it is deterministic and two machines at the same desk generate the same words. The primary is
-- the screen at the origin, which is where macOS puts it in point space, and every other screen
-- is named by its size and where it sits.
local function generateName(rects)
  if #rects == 0 then return "no displays" end
  local primaryIndex = 1
  for i, r in ipairs(rects) do
    if r.x == 0 and r.y == 0 then
      primaryIndex = i
      break
    end
  end
  local primary = rects[primaryIndex]
  local others = {}
  for i, r in ipairs(rects) do
    if i ~= primaryIndex then
      others[#others + 1] = string.format("%dx%d %s", r.w, r.h, relationOf(primary, r))
    end
  end
  local name = string.format("%dx%d", primary.w, primary.h)
  if #others > 0 then
    name = name .. " with " .. table.concat(others, ", ")
  end
  return name
end

--- E:fingerprint()
--- Method
--- The configuration attached right now as one comparable string, plus the sorted rectangles it
--- was built from so a caller can name it. Every screen's full frame in points, sorted by origin
--- x then origin y, each written as x,y,WxH and joined. Answers nil when no screen is attached
--- at all, which a sleeping or locked machine can briefly report, so an empty string never
--- becomes a configuration of its own.
function E:fingerprint()
  local rects = {}
  for _, s in ipairs(hs.screen.allScreens()) do
    local f = s:fullFrame()
    rects[#rects + 1] = { x = whole(f.x), y = whole(f.y), w = whole(f.w), h = whole(f.h) }
  end
  if #rects == 0 then return nil, rects end
  table.sort(rects, function(a, b)
    if a.x ~= b.x then return a.x < b.x end
    return a.y < b.y
  end)
  local parts = {}
  for _, r in ipairs(rects) do
    parts[#parts + 1] = string.format("%d,%d,%dx%d", r.x, r.y, r.w, r.h)
  end
  return table.concat(parts, ";"), rects
end

--- E:nameFor(rects)
--- Method
--- The generated name for a set of rectangles, exposed so the plugin root can label a
--- configuration the same way the engine does.
function E:nameFor(rects)
  return generateName(rects or {})
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

--- E:configure(opts)
--- Method
--- opts.store     the persistent layer, or nil to run on the session layer alone.
--- opts.onChange  called with no arguments when the active configuration changes, so a view
---                showing which one is active can correct itself.
function E:configure(opts)
  opts = opts or {}
  self._store = opts.store
  self._onChange = opts.onChange
  self._session = self._session or {}
  self._births = self._births or {}
  self._mutes = self._mutes or {}
  return self
end

--- E:start()
--- Method
--- Subscribe to window moves and births, watch for screen changes and wake, then compute the
--- fingerprint, make sure the configuration exists, and run one restore pass through the same
--- episode machinery every later disturbance uses, so a reboot lands windows where they belong
--- with no second code path to keep honest. Idempotent.
function E:start()
  if self._filter then return self end
  self._session = self._session or {}
  self._births = self._births or {}
  self._mutes = self._mutes or {}

  -- Standard windows of the normal visible apps, minus Hammerspoon's own. The default filter is
  -- deliberate over new(true), harvested from WindowMemory, since it already excludes non
  -- standard windows and the known problematic menubar agents, whereas new(true) forces the
  -- filter to watch every one of them, which floods the log and stalls the main thread.
  -- windowMoved is the only frame change event the filter emits and it covers moving and
  -- resizing alike.
  self._filter = hs.window.filter.new()
  self._filter:setAppFilter("Hammerspoon", false)
  self._filter:subscribe(hs.window.filter.windowMoved, function(win)
    self:_onMoved(win)
  end)
  self._filter:subscribe(hs.window.filter.windowCreated, function(win)
    self:_onBorn(win)
  end)

  -- hs.timer.delayed re arms on each start, which is exactly what a quiescence timer is, so a
  -- disturbance restarts the countdown and it fires only once nothing has moved for the whole
  -- delay.
  self._idle = hs.timer.delayed.new(IDLE, function()
    self:_resolve()
  end)
  self._persist = hs.timer.delayed.new(PERSIST_DEBOUNCE, function()
    self:_flush()
  end)

  self._screens = hs.screen.watcher.new(function()
    self:_disturb()
  end)
  self._screens:start()

  -- Wake opens an episode too, since a wake that did not change the display set fires no screen
  -- event at all, and that is the case where every window is where it was but the geometry may
  -- have been rearranged underneath while the machine slept.
  self._wake = hs.caffeinate.watcher.new(function(event)
    if event == hs.caffeinate.watcher.systemDidWake then
      self:_disturb()
    end
  end)
  self._wake:start()

  local fingerprint, rects = self:fingerprint()
  self._fingerprint = fingerprint
  self:_ensure(fingerprint, rects)
  self:_disturb()

  log.i("started, watching all standard windows, configuration " .. tostring(fingerprint))
  return self
end

--- E:stop()
--- Method
--- Stop watching and tear down every timer and watcher, flushing whatever was pending so a stop
--- never loses a move already recorded. The remembered frames are kept, so a restart of the
--- watchers can still restore them within the session.
function E:stop()
  if self._filter then
    self._filter:unsubscribeAll()
    self._filter = nil
  end
  if self._screens then
    self._screens:stop()
    self._screens = nil
  end
  if self._wake then
    self._wake:stop()
    self._wake = nil
  end
  for _, timer in pairs(self._births or {}) do timer:stop() end
  self._births = {}
  for _, timer in pairs(self._mutes or {}) do timer:stop() end
  self._mutes = {}
  self._muted = 0
  for _, field in ipairs({ "_idle", "_ceiling", "_safety", "_tail", "_retry" }) do
    if self[field] then
      self[field]:stop()
      self[field] = nil
    end
  end
  if self._persist then
    self._persist:stop()
    self._persist = nil
  end
  self:_flush()
  self._episode = false
  self._resolving = false
  return self
end

--------------------------------------------------------------------------------
-- Persistence, coalesced
--------------------------------------------------------------------------------

function E:_flush()
  if not self._store then return end
  if not self._store:flush() then
    log.w("could not write the workspaces file, this configuration's memory is session only until it succeeds")
  end
end

function E:_schedulePersist()
  if self._persist then self._persist:start() end
end

-- Make sure a configuration exists in the store, named from its geometry the first time it is
-- seen. A fingerprint never seen before silently becomes a new configuration, which is the whole
-- promise, arriving at a new desk should cost nobody a setup step.
function E:_ensure(fingerprint, rects)
  if not fingerprint or not self._store then return end
  self._store:ensure(fingerprint, generateName(rects or {}))
  self:_schedulePersist()
end

--------------------------------------------------------------------------------
-- Steady state capture
--------------------------------------------------------------------------------

-- A move is recorded only when no episode is open, nothing the engine did is still being echoed,
-- the moved window is the focused window, and the frame moved further than the tolerance. The
-- focused window rule is what separates a person dragging a window from macOS shuffling one,
-- since a shuffle moves windows nobody is touching.
function E:_onMoved(win)
  if self._episode then
    -- Even a move nobody asked for is evidence the geometry is still settling, so it resets the
    -- quiescence timer rather than being ignored outright.
    self:_bump()
    return
  end
  if self._muted > 0 then return end
  if not placeable(win) then return end
  local id = win:id()
  if not id then return end
  local focused = hs.window.focusedWindow()
  if not focused or focused:id() ~= id then return end
  local fingerprint = self._fingerprint
  if not fingerprint then return end

  local f = win:frame()
  local slot = self._session[fingerprint]
  if not slot then
    slot = {}
    self._session[fingerprint] = slot
  end
  local stored = slot[id]
  if stored and sameFrame(stored, f, TOLERANCE) then return end
  local frame = { x = whole(f.x), y = whole(f.y), w = whole(f.w), h = whole(f.h) }
  slot[id] = frame

  -- The persistent layer takes the frame of the window the person last moved, which is what
  -- makes one frame per app the right frame rather than an arbitrary one.
  local app = win:application()
  local bundleID = app and app:bundleID()
  if bundleID and self._store then
    self._store:setAppFrame(fingerprint, bundleID, frame)
    self:_schedulePersist()
  end
end

--------------------------------------------------------------------------------
-- The episode
--------------------------------------------------------------------------------

-- A screen change or a wake. Open the episode at once so the settling burst is never recorded,
-- and start or reset the wait for quiet.
--
-- A fresh disturbance always takes over whatever an earlier one was still doing. A retry
-- campaign waiting on a display that never woke, or a pending close, both belong to geometry
-- that has just changed again, so both are cancelled and the wait for quiet starts over. Without
-- that, docking while an earlier campaign was still retrying would be ignored until the campaign
-- ran out, which is exactly when a person is most likely to dock again.
function E:_disturb()
  if self._retry then
    self._retry:stop()
    self._retry = nil
  end
  if self._tail then
    self._tail:stop()
    self._tail = nil
  end
  self._resolving = false
  self._episode = true

  -- The ceiling is measured from the moment the wait began rather than from the last event, so
  -- it is armed only when nothing is already counting, which is what makes it a guarantee of
  -- progress rather than another thing an endless stream of events can push out forever.
  if not self._ceiling then
    self._ceiling = hs.timer.doAfter(CEILING, function()
      self._ceiling = nil
      self:_resolve()
    end)
  end

  -- The backstop is re armed from the latest disturbance instead, since its whole job is to
  -- clear the flag when no restore ever runs, and one that fired in the middle of a campaign
  -- would reopen recording while a slow display was still being waited for.
  if self._safety then self._safety:stop() end
  self._safety = hs.timer.doAfter(SAFETY_SPAN, function()
    self._safety = nil
    self._episode = false
    self._resolving = false
  end)

  self:_bump()
end

-- Reset the wait for quiet. Deliberately inert once the restore has started, since from that
-- moment every move is one the engine itself is making and extending the episode with our own
-- placements would never let it close.
function E:_bump()
  if not self._episode or self._resolving then return end
  if self._idle then self._idle:start() end
end

-- The geometry has gone quiet, or the ceiling ran out. Recompute the fingerprint, create the
-- configuration if it is new, and restore.
function E:_resolve()
  if self._resolving then return end
  self._resolving = true
  if self._idle then self._idle:stop() end
  if self._ceiling then
    self._ceiling:stop()
    self._ceiling = nil
  end

  local fingerprint, rects = self:fingerprint()
  local changed = fingerprint ~= self._fingerprint
  self._fingerprint = fingerprint
  self:_ensure(fingerprint, rects)
  if changed and self._onChange then self._onChange() end

  self:_runRestore(MAX_RETRIES)
end

-- One pass plus its retry scheduling. Kept apart from _resolve so a retry re enters here without
-- recomputing the fingerprint, which cannot have changed without a screen event that would have
-- opened a fresh episode anyway.
function E:_runRestore(attemptsLeft)
  local deferred = self:_restoreOnce()
  if deferred > 0 and attemptsLeft > 0 then
    self._retry = hs.timer.doAfter(RETRY_INTERVAL, function()
      self._retry = nil
      self:_runRestore(attemptsLeft - 1)
    end)
    return
  end
  if deferred > 0 then
    log.w(string.format("%d window(s) left unplaced, their display never became ready", deferred))
  end
  self:_endEpisode()
end

-- Close the episode after one more quiet beat, so the trailing asynchronous move events from our
-- own placement land while recording is still deaf.
function E:_endEpisode()
  if self._tail then self._tail:stop() end
  self._tail = hs.timer.doAfter(QUIET_BEAT, function()
    self._tail = nil
    self._episode = false
    self._resolving = false
    if self._safety then
      self._safety:stop()
      self._safety = nil
    end
  end)
end

--------------------------------------------------------------------------------
-- Restore
--------------------------------------------------------------------------------

-- The frame the persistent layer knows for this window, which it only answers for a window that
-- is its app's only standard window. One frame per app cannot say which of three Finder windows
-- it meant, so rather than guess it declines, and the session layer covers the multi window case
-- whenever it has seen those windows move.
-- The store lookup comes before the one window test on purpose. Counting an app's standard
-- windows means asking the accessibility layer, which is the expensive half, and most windows on
-- a machine are not remembered at all, so asking the cheap question first keeps a restore pass
-- from walking every app's window list for nothing.
function E:_persistentFrame(win, fingerprint)
  if not self._store then return nil end
  local app = win:application()
  local bundleID = app and app:bundleID()
  if not bundleID then return nil end
  local f = self._store:appFrame(fingerprint, bundleID)
  if not f then return nil end
  if standardWindowsOf(app) ~= 1 then return nil end
  return f
end

function E:_place(win, f)
  local cur = win:frame()
  if sameFrame(cur, f, TOLERANCE) then return end
  win:setFrame(hs.geometry.rect(f.x, f.y, f.w, f.h), 0)
end

-- One restore pass. Walks the windows that exist rather than the ids remembered, so a window
-- with no memory is simply left alone rather than needing a rule of its own. A session layer hit
-- on the window id wins, since it is the exact frame of that exact window. Otherwise the
-- persistent layer answers for an app with one standard window. Returns how many windows were
-- deferred for a display that was not ready, so the caller can decide whether to retry.
function E:_restoreOnce()
  local fingerprint = self._fingerprint
  if not fingerprint then return 0 end
  local slot = self._session[fingerprint]
  local deferred = 0

  -- Prune ids whose window is gone, so the session table cannot grow for a whole login.
  if slot then
    for id in pairs(slot) do
      if not hs.window.get(id) then slot[id] = nil end
    end
  end

  for _, win in ipairs(hs.window.allWindows()) do
    if placeable(win) then
      local id = win:id()
      local f = (slot and id) and slot[id] or nil
      if not f then f = self:_persistentFrame(win, fingerprint) end
      if f then
        if targetScreenReady(f) then
          self:_place(win, f)
        else
          deferred = deferred + 1
        end
      end
    end
  end
  return deferred
end

--- E:restoreNow()
--- Method
--- Run a restore pass for the configuration attached right now, on purpose rather than because
--- something changed. Goes through the same episode machinery, so recording stays deaf and the
--- retry campaign still covers a display that is awake but not ready. A no op while an episode
--- is already restoring, since that pass is about to do the same thing.
function E:restoreNow()
  self:_disturb()
  self:_resolve()
  return self
end

--------------------------------------------------------------------------------
-- Fresh launch placement
--------------------------------------------------------------------------------

-- A window appeared while nothing was settling. Wait a moment before placing it, because an app
-- that positions its own window at birth does so within a frame or two and placing immediately
-- means fighting it. Several apps can be launching at once and a later one must not cancel an
-- earlier one, so the pending calls are held per window id rather than in one field.
function E:_onBorn(win)
  if self._episode then return end
  if not self._store then return end
  local id = win and win:id()
  if not id then return end
  local fingerprint = self._fingerprint
  if not fingerprint then return end
  if self._births[id] then self._births[id]:stop() end
  self._births[id] = hs.timer.doAfter(BIRTH_DELAY, function()
    self._births[id] = nil
    self:_placeNewborn(id, fingerprint)
  end)
end

function E:_placeNewborn(id, fingerprint)
  if self._episode then return end
  if fingerprint ~= self._fingerprint then return end
  local win = hs.window.get(id)
  if not placeable(win) then return end
  local f = self:_persistentFrame(win, fingerprint)
  if not f then return end
  if not targetScreenReady(f) then return end
  self:_mute(MUTE_TAIL)
  self:_place(win, f)
end

-- Suppress recording for a moment around a placement the engine made outside an episode, so our
-- own move is never written back as if a person had made it. Held as a table of pending releases
-- rather than one field, since two placements can overlap and the later one must not release the
-- earlier one's mute.
function E:_mute(seconds)
  self._muted = self._muted + 1
  local key = {}
  self._mutes[key] = hs.timer.doAfter(seconds, function()
    self._mutes[key] = nil
    self._muted = math.max(0, self._muted - 1)
  end)
end

--------------------------------------------------------------------------------
-- What the plugin root asks
--------------------------------------------------------------------------------

--- E:current()
--- Method
--- The fingerprint of the configuration attached right now, as last computed.
function E:current()
  return self._fingerprint
end

--- E:forgetSessionApp(fingerprint, bundleID)
--- Method
--- Drop every session entry belonging to one app under one configuration. Forgetting an app in
--- the store alone would not be forgetting, since the session layer wins on restore and would
--- put that app's windows back from a memory nobody can see or prune.
function E:forgetSessionApp(fingerprint, bundleID)
  local slot = self._session[fingerprint]
  if not slot or not bundleID then return end
  for id in pairs(slot) do
    local win = hs.window.get(id)
    local app = win and win:application()
    if not win or (app and app:bundleID() == bundleID) then
      slot[id] = nil
    end
  end
end

--- E:forgetSession(fingerprint)
--- Method
--- Drop the whole session layer for one configuration, so deleting a configuration really
--- forgets this desk rather than leaving an invisible half of it behind.
function E:forgetSession(fingerprint)
  if fingerprint then self._session[fingerprint] = nil end
end

return E
