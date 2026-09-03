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
---
--- A PLACEMENT MACOS REFUSES USED TO BE INVISIBLE, SO IT NOW READS BACK. Setting a frame is not
--- a promise a constrained window keeps, and the center test above only asks whether a display is
--- attached, which is already true of one that is connected but not yet actually displaying. Such
--- a window was placed, macOS clamped it onto whatever panel was awake, and nothing about the
--- pass ever found out. So a placement now asks the window for its frame again right after
--- setting it and only counts as landed when the answer matches, which lets a refusal share the
--- same retry a slow display already had, rather than closing the episode as if nothing were
--- wrong.
---
--- CAPTURE NOW HAS A LOOK BEHIND, SINCE A MOVE CAN ARRIVE BEFORE THE EPISODE THAT EXPLAINS IT. The
--- screen watcher usually opens an episode before the filter's own half second delay hands a
--- shuffled move onward, but the watcher is documented as unreliable across sleep, so a shuffle
--- that beat the episode there used to be written under the stale fingerprint with a built in
--- frame. A move outside an episode is staged for a short grace now rather than written at once,
--- and a disturbance that arrives inside that grace drops the stage instead of letting it land.
---
--- A WINDOW NEVER DRAGGED HAD NO MEMORY EITHER, SO THE SESSION LAYER NOW FILLS ITS OWN GAPS. Both
--- layers used to record moves alone, and only of the focused window, so a window an app placed
--- itself, or one nobody ever touched under a configuration, was unknown there and stayed
--- wherever macOS threw it. Every placeable window's move is staged into the session layer
--- regardless of focus now, and the moment an episode closes, whatever window still has no entry
--- there is filled in from wherever it actually sits. The persistent layer keeps the focused
--- window rule as its own definition of intent, since one frame per app should reflect what a
--- person chose rather than whatever an app or a script last put there.

local E = {}

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

-- The retry campaign for a display that has not finished waking, or a placement macOS refused.
-- One pass every RETRY_INTERVAL seconds up to MAX_RETRIES, about twenty seconds, long enough for
-- a slow ultrawide without retrying forever.
local RETRY_INTERVAL = 2.0
local MAX_RETRIES = 10

-- The backstop that force clears the episode flag, spanning the whole worst case episode plus
-- slack, so it can never fire mid campaign and reopen recording while a slow display is still
-- being waited for. Ten seconds of slack rather than two, since the worst case is eleven full
-- window sweeps, the first pass plus every retry, each one reading every window's frame back
-- after setting it, and that cost was never in the two seconds this used to leave.
local SAFETY_SPAN = CEILING + MAX_RETRIES * RETRY_INTERVAL + QUIET_BEAT + 10.0

-- How long to wait after a window is born before placing it. An app that positions its own
-- window at birth does so within a frame or two, so placing immediately means fighting it and
-- usually losing.
local BIRTH_DELAY = 0.5

-- How long recording stays deaf around a placement the engine made outside an episode. The
-- filter delays every move event by half a second and restarts that delay on each further
-- notification before it ever hands one onward, so a mute shorter than that window expires
-- before the event it exists to suppress can ever arrive. One full second covers the delay with
-- room to spare.
local MUTE_TAIL = 1.0

-- How long a move staged outside an episode waits before it commits. The screen watcher usually
-- opens an episode before a shuffled move arrives, but it is documented as unreliable across
-- sleep, so this is the look behind that lets a disturbance arriving late still catch a move that
-- beat it here and drop it rather than have it commit under the wrong geometry.
local CAPTURE_GRACE = 1.0

-- How many times a newborn found mid episode waits another quiet beat plus its own birth delay
-- before giving up. A newborn has no retry campaign of its own, and an episode that somehow never
-- closes must not be waited on forever either.
local NEWBORN_WAIT_RETRIES = 20

-- A timer's own delay does not run while the machine is asleep, it fires as soon as the machine
-- wakes with however much wall clock time has actually passed, so a timer armed just before a
-- long sleep can fire long after the interval it was given ever intended to measure. Comparing
-- the wall clock due time against now is what tells a timer that fired for that reason apart from
-- one that fired for the reason it exists.
local SLEEP_SLACK = 5.0

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
E._pending = nil     -- moves waiting out the look behind grace, keyed by window id
E._episode = false   -- true while capture is deaf
E._resolving = false -- true once the episode has stopped waiting and started restoring
E._session = nil     -- { [fingerprint] = { [windowId] = frame } }
E._fingerprint = nil -- the configuration attached right now
E._episodeStats = nil -- counts for the episode now open, created at open and cleared at close
E._unplaced = nil    -- ids the last restore pass could not place, refused or deferred, so the
                      -- baseline knows which gaps are not really gaps

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

-- A frame as one short readable string, for the warning naming which window macOS would not let
-- go where, so a person reading the log sees both the frame that was asked for and the one the
-- window actually holds without reading two raw tables against each other by eye.
local function frameStr(f)
  return string.format("%d,%d %dx%d", whole(f.x), whole(f.y), whole(f.w), whole(f.h))
end

-- The full frame of every attached screen, read once and handed to every question a restore
-- pass asks about them. Asking hs.screen.allScreens per window turned one cheap read into one
-- per candidate for no gain, since a screen cannot appear or disappear part way through a
-- synchronous pass without a screen event that will open a fresh episode anyway.
local function screenFrames()
  local out = {}
  for _, s in ipairs(hs.screen.allScreens()) do
    out[#out + 1] = s:fullFrame()
  end
  return out
end

-- The index, within the same screens list a whole pass reads once and reuses, of the screen
-- whose full frame contains a point, or nil when no attached screen does. The containment is done
-- by hand against each screen's full frame, since hs.screen.find matches a name or an id, never a
-- point. Answering an index rather than a boolean is what lets two different points be compared
-- for having landed on the same screen at all, which a plain yes or no could never say.
local function screenIndexAt(x, y, screens)
  for i, fr in ipairs(screens or {}) do
    if x >= fr.x and x < fr.x + fr.w and y >= fr.y and y < fr.y + fr.h then
      return i
    end
  end
  return nil
end

-- Whether a remembered frame lands on a screen attached right now, tested by its center. A
-- frame whose center is on no attached screen means a display that has not finished waking, so
-- the window is deferred rather than placed onto coordinates macOS would clamp onto the wrong
-- panel.
local function targetScreenReady(f, screens)
  return screenIndexAt(f.x + f.w / 2, f.y + f.h / 2, screens) ~= nil
end

-- A window worth placing, standard and neither minimized nor fullscreen, and not one of ours.
-- The id is asked for first because a window object outliving the window it names answers nil
-- to everything, which is how a placement scheduled half a second ago finds out that the window
-- it was waiting for has already closed.
local function placeable(win)
  if win == nil then return false end
  if not win:id() then return false end
  if not win:isStandard() then return false end
  if win:isMinimized() or win:isFullScreen() then return false end
  local app = win:application()
  if app and app:bundleID() == OWN_BUNDLE then return false end
  return true
end

-- Every standard window of one app, which is what the one window rule below is asked about.
-- Memoized per pass by process id, since a restore pass asks this once per candidate window and
-- an app with four windows would otherwise walk its own window list four times for one answer
-- that cannot change mid pass. A count of zero is a real answer and caches like any other, Lua
-- treating zero as truthy, so a memo hit is never mistaken for a miss.
local function standardWindowsOf(app, memo)
  if not app then return 0 end
  local key = memo and app:pid() or nil
  if key and memo[key] then return memo[key] end
  local n = 0
  for _, w in ipairs(app:allWindows() or {}) do
    if w:isStandard() then n = n + 1 end
  end
  if key then memo[key] = n end
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
  self._pending = self._pending or {}
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
  self._pending = self._pending or {}

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
  -- Whatever is still waiting out its grace gets the exact judgement _commit would have given it
  -- once the grace ran out, committing what is still valid and dropping the rest, rather than a
  -- second copy of that judgement written here, so a stop right after a drag loses nothing.
  for id, entry in pairs(self._pending or {}) do
    if entry.timer then entry.timer:stop() end
    self:_commit(id)
  end
  self._pending = {}
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
--
-- THIS IS THE ONLY PLACE A CONFIGURATION IS EVER CREATED, which is what keeps every one of them
-- named from its geometry. The store used to create one as a side effect of remembering an app
-- frame, and the only caller that ever reached that path had no name to give, so deleting the
-- configuration you were standing in and then moving a window resurrected it named by its raw
-- fingerprint string. The store now refuses to create, so there is one door and it is this one.
function E:_ensure(fingerprint, rects)
  if not fingerprint or not self._store then return end
  self._store:ensure(fingerprint, generateName(rects or {}))
  self:_schedulePersist()
end

--------------------------------------------------------------------------------
-- Steady state capture
--------------------------------------------------------------------------------

-- A move outside an episode no longer writes at once, it stages, since a shuffle that beats the
-- episode to the filter must still be caught rather than told apart from intent by a clock that
-- has already run out. Whether the window was focused when it moved is carried along as intent,
-- which is what the persistent layer uses as its own definition of a person dragging a window
-- rather than macOS or an app moving one, since a person holding a window is focused on it. The
-- session layer takes every placeable window's move regardless of that, because its job is
-- putting reality back rather than guessing at who meant it.
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
  local fingerprint = self._fingerprint
  if not fingerprint then return end

  local focused = hs.window.focusedWindow()
  local intent = focused ~= nil and focused:id() == id

  local f = win:frame()
  local frame = { x = whole(f.x), y = whole(f.y), w = whole(f.w), h = whole(f.h) }
  local slot = self._session[fingerprint]
  local stored = slot and slot[id]
  if stored and sameFrame(stored, frame, TOLERANCE) then return end

  local app = win:application()
  local bundleID = app and app:bundleID()

  -- A fresh disturbance to the same window while it is still waiting out its grace replaces the
  -- stage rather than stacking a second one beside it, and a drag that lost focus part way
  -- through still counts as intent, since the person was holding it when it started moving.
  local old = self._pending[id]
  if old and old.timer then old.timer:stop() end
  if old then intent = intent or old.intent end

  local entry = {
    win = win,
    frame = frame,
    fingerprint = fingerprint,
    bundleID = bundleID,
    intent = intent,
  }
  entry.timer = hs.timer.doAfter(CAPTURE_GRACE, function()
    self:_commit(id)
  end)
  self._pending[id] = entry
end

-- The grace ran out with nothing having stopped it, so the stage is trustworthy now, checked three
-- ways before it is allowed to land.
--
-- THE FINGERPRINT IS RECOMPUTED LIVE RATHER THAN READ FROM self._fingerprint, which is only ever
-- refreshed by an episode's own resolve. Comparing against that cached field would compare a
-- stale value against itself whenever the geometry changed with no screen event ever opening an
-- episode for it, and every clamped frame from the old geometry would then commit as if it still
-- described the desk. Asking the live fingerprint here is the look behind actually doing its job,
-- and finding a difference with no episode open means a screen event was missed, so the episode
-- that should have opened opens now instead of the miss going unnoticed.
--
-- THE WINDOW IS RE ASKED WHETHER IT IS STILL PLACEABLE, since a window that went fullscreen, was
-- minimized, or closed outright during the grace would otherwise commit whatever transition frame
-- it happened to be carrying the instant the grace ran out, which describes nothing real.
--
-- AN ID IN _unplaced IS DROPPED UNLESS INTENT IS TRUE, since a window stuck in the wrong frame by
-- a refused or deferred placement keeps producing frame events of its own, an echo of the campaign
-- rather than a person, and only a person actually holding that window, focused when it moved, is
-- worth believing over the memory the campaign already gave up on.
function E:_commit(id)
  local entry = self._pending[id]
  self._pending[id] = nil
  if not entry then return end
  if self._episode then return end

  local live = self:fingerprint()
  if entry.fingerprint ~= live then
    self:_disturb()
    return
  end

  if not placeable(entry.win) then return end

  if self._unplaced and self._unplaced[id] and not entry.intent then return end

  local slot = self._session[entry.fingerprint]
  if not slot then
    slot = {}
    self._session[entry.fingerprint] = slot
  end
  slot[id] = entry.frame

  -- The persistent layer takes the frame of the window the person last moved, which is what
  -- makes one frame per app the right frame rather than an arbitrary one, so only a staged move
  -- that carried intent reaches it.
  if entry.intent and entry.bundleID and self._store then
    self._store:setAppFrame(entry.fingerprint, entry.bundleID, entry.frame)
    self:_schedulePersist()
  end
end

--------------------------------------------------------------------------------
-- The episode
--------------------------------------------------------------------------------

-- Armed with its own due time in wall clock seconds rather than trusted to fire exactly CEILING
-- seconds from now, since a timer's delay does not run while the machine is asleep and one armed
-- just before a long sleep fires as soon as the machine wakes, long after the interval it was
-- given ever intended to measure. A timer that fired for that reason is not a geometry that failed
-- to settle, so it re arms a fresh ceiling and bumps instead, exactly what an ordinary disturbance
-- already does, and the wait for quiet simply starts over rather than resolving on grounds that
-- went stale during sleep.
function E:_armCeiling()
  local due = hs.timer.secondsSinceEpoch() + CEILING
  self._ceiling = hs.timer.doAfter(CEILING, function()
    self._ceiling = nil
    if hs.timer.secondsSinceEpoch() - due > SLEEP_SLACK then
      self:_armCeiling()
      self:_bump()
      return
    end
    self:_resolve()
  end)
end

-- Armed the same way and for the same reason, plus two guards of its own before it ever force
-- closes anything. A live campaign, a retry still waiting on a slow display or a refused
-- placement, or a tail still waiting out the quiet beat past the last one, will close the episode
-- itself in a bounded time, so firing while either is pending re arms for another SAFETY_SPAN and
-- returns rather than forcing a close that would only race whichever finishes it properly. Only
-- once nothing is pending, and the firing itself was not late from sleeping through it, does this
-- actually force the episode closed, and it stops and clears every timer this episode owns so
-- nothing is inherited by whatever opens next and this same close can never happen twice. _idle is
-- only stopped here, not cleared, since it is the one persistent timer this engine creates once in
-- start and reuses for the rest of its life, and dropping the reference would leave nothing able
-- to rearm it ever again.
function E:_armSafety()
  local due = hs.timer.secondsSinceEpoch() + SAFETY_SPAN
  self._safety = hs.timer.doAfter(SAFETY_SPAN, function()
    self._safety = nil
    if hs.timer.secondsSinceEpoch() - due > SLEEP_SLACK then
      self:_armSafety()
      return
    end
    if self._retry or self._tail then
      self:_armSafety()
      return
    end

    if self._ceiling then
      self._ceiling:stop()
      self._ceiling = nil
    end
    if self._idle then self._idle:stop() end
    if self._retry then
      self._retry:stop()
      self._retry = nil
    end
    if self._tail then
      self._tail:stop()
      self._tail = nil
    end

    -- A missed signal wedged recording off with nobody the wiser, so the same shape of line the
    -- ordinary close logs gets logged here too, as a warning naming the same counts, since a
    -- person reading the log afterward has to be able to tell the two closes apart just as easily
    -- as they can tell an ordinary one happened at all.
    if self._episodeStats then
      log.w(string.format(
        "episode force closed by the safety backstop, %s -> %s, %d passes, placed %d, refused %d, deferred %d, dropped %d pending",
        tostring(self._episodeStats.from), tostring(self._fingerprint), self._episodeStats.passes,
        self._episodeStats.placed, self._episodeStats.refused, self._episodeStats.deferred,
        self._episodeStats.dropped))
      self._episodeStats = nil
    end
    self._episode = false
    self._resolving = false
  end)
end

-- A screen change or a wake. Open the episode at once so the settling burst is never recorded,
-- and start or reset the wait for quiet.
--
-- A fresh disturbance always takes over whatever an earlier one was still doing. A retry
-- campaign waiting on a display that never woke, or a pending close, both belong to geometry
-- that has just changed again, so both are cancelled and the wait for quiet starts over. Without
-- that, docking while an earlier campaign was still retrying would be ignored until the campaign
-- ran out, which is exactly when a person is most likely to dock again.
function E:_disturb()
  -- The counters belong to the episode as a whole, so they are created only the moment one
  -- actually opens rather than on every re disturbance that keeps an already open one going.
  -- Dropped and passes accumulate across every disturbance and every pass, while placed, refused,
  -- and deferred are overwritten each pass, so the summary logged at the end reports a running
  -- total for the two counters a tally actually describes and the last pass's own numbers for the
  -- three that describe a state rather than a count.
  if not self._episode then
    self._episodeStats = {
      from = self._fingerprint,
      dropped = 0,
      placed = 0,
      refused = 0,
      deferred = 0,
      passes = 0,
    }
  end

  -- Whatever the last restore pass could not place belonged to that pass, and this is a fresh
  -- one, so the baseline must not go on skipping ids a campaign that already ended left behind.
  self._unplaced = nil

  -- A pending capture belongs to geometry that has just changed, so dropping it is the entire
  -- point of the grace, and how many were dropped is worth knowing in the summary, since it says
  -- how much of what a person just did was actually the shuffle this episode is about to correct.
  local dropped = 0
  for id, entry in pairs(self._pending or {}) do
    if entry.timer then entry.timer:stop() end
    self._pending[id] = nil
    dropped = dropped + 1
  end
  if self._episodeStats then
    self._episodeStats.dropped = self._episodeStats.dropped + dropped
  end

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
    self:_armCeiling()
  end

  -- The backstop is re armed from the latest disturbance instead, since its whole job is to
  -- clear the flag when no restore ever runs, and stopping the old one here is what keeps a
  -- disturbance mid wait from ever letting two backstops race each other.
  if self._safety then self._safety:stop() end
  self:_armSafety()

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
-- opened a fresh episode anyway. verbose is true only on the pass that runs out of attempts, never
-- on a pass that happens to succeed while attempts remain, since attemptsLeft reaching zero is the
-- only condition it watches.
function E:_runRestore(attemptsLeft)
  local verbose = attemptsLeft <= 0
  local deferred, refused = self:_restoreOnce(verbose)
  if self._episodeStats then
    self._episodeStats.passes = self._episodeStats.passes + 1
  end
  if deferred + refused > 0 and attemptsLeft > 0 then
    self._retry = hs.timer.doAfter(RETRY_INTERVAL, function()
      self._retry = nil
      self:_runRestore(attemptsLeft - 1)
    end)
    return
  end
  if deferred + refused > 0 then
    log.w(string.format(
      "%d window(s) left unplaced after the retry campaign ran out, %d waiting on a display that never became ready and %d refused by macOS",
      deferred + refused, deferred, refused))
  end
  self:_endEpisode()
end

-- Close the episode after one more quiet beat, so the trailing asynchronous move events from our
-- own placement land while recording is still deaf. The baseline fill runs here, inside that same
-- beat and before the flag clears, so it runs after the campaign's placements are done rather than
-- racing them, whether or not every one of them actually landed, which is exactly when the skip
-- list matters most.
function E:_endEpisode()
  if self._tail then self._tail:stop() end
  self._tail = hs.timer.doAfter(QUIET_BEAT, function()
    self._tail = nil
    local filled = self:_fillBaseline()
    -- This one line is the instrumentation the next real unplug gets read through, so it always
    -- fires, naming both fingerprints with tostring since either may be nil, on a bare desk with
    -- no screen attached at all being the concrete case.
    if self._episodeStats then
      log.i(string.format(
        "episode closed, %s -> %s, %d passes, placed %d, refused %d, deferred %d, dropped %d pending, baseline filled %d",
        tostring(self._episodeStats.from), tostring(self._fingerprint), self._episodeStats.passes,
        self._episodeStats.placed, self._episodeStats.refused, self._episodeStats.deferred,
        self._episodeStats.dropped, filled))
      self._episodeStats = nil
    end
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
function E:_persistentFrame(win, fingerprint, memo)
  if not self._store then return nil end
  local app = win:application()
  local bundleID = app and app:bundleID()
  if not bundleID then return nil end
  local f = self._store:appFrame(fingerprint, bundleID)
  if not f then return nil end
  if standardWindowsOf(app, memo) ~= 1 then return nil end
  return f
end

-- Sets the frame and answers whether it actually landed there, so a placement macOS silently
-- clamps elsewhere is no longer indistinguishable from one that worked. The readback is
-- trustworthy here because setting an accessibility attribute is synchronous and a window that
-- cannot be placed where it was asked answers back with the constrained frame it settled for
-- instead, rather than lying about it.
--
-- A READBACK OUTSIDE TOLERANCE STILL COUNTS AS LANDED WHEN IT SITS ON THE SAME SCREEN THE FRAME
-- WAS ASKED FOR. The shipped window.lua documents sticky edges and discrete resize steps of its
-- own, a terminal snapping to its cell grid or an app enforcing a minimum size being the ordinary
-- case, and no retry ever changes what an app itself insists on. Only a readback that lands on a
-- different screen, or on none at all, is macOS clamping the window elsewhere, which is the
-- refusal a retry can still fix. Without the split, an app with a grid of its own failed every
-- readback forever and the retry campaign fought it eleven times over twenty seconds with
-- recording deaf to everything else the whole time, for a placement nothing was ever going to
-- change. screens is the same list the calling pass already read once, so the two centers are
-- compared against the identical set of panels rather than each risking a fresh read mid pass.
function E:_place(win, f, screens)
  local cur = win:frame()
  if sameFrame(cur, f, TOLERANCE) then return true end
  win:setFrame(hs.geometry.rect(f.x, f.y, f.w, f.h), 0)
  local after = win:frame()
  if sameFrame(after, f, TOLERANCE) then return true end
  local wanted = screenIndexAt(f.x + f.w / 2, f.y + f.h / 2, screens)
  local got = screenIndexAt(after.x + after.w / 2, after.y + after.h / 2, screens)
  return wanted ~= nil and wanted == got
end

-- One restore pass. Walks the windows that exist rather than the ids remembered, so a window
-- with no memory is simply left alone rather than needing a rule of its own. A session layer hit
-- on the window id wins, since it is the exact frame of that exact window. Otherwise the
-- persistent layer answers for an app with one standard window. Returns how many windows were
-- deferred for a display that was not ready and how many were refused by macOS once placed, in
-- that order, so the caller can decide whether to retry and can tell the two reasons apart.
-- verbose is set by the caller only on the pass that runs out of attempts, and only then does a
-- refused window get its own warning line naming the app and both frames, since every earlier
-- pass is expected to see some of these and only the last one is worth a person's attention.
--
-- ONE SWEEP OF THE WINDOW LIST PER PASS, AND EVERYTHING BELOW READS OFF IT. hs.window.get is not
-- a lookup, it walks the whole window list on every call, so pruning the session table with one
-- get per remembered id cost a full sweep each, thirty of them on a desk with thirty remembered
-- windows, and a retry campaign multiplied that by seven, all synchronous on the main thread.
-- The snapshot, the id map built from it, the screen frames, and the per app standard window
-- count are all taken once here for the same reason. Pruning against the snapshot is exactly
-- what pruning through hs.window.get already meant, since that is the list it was searching.
function E:_restoreOnce(verbose)
  local fingerprint = self._fingerprint
  if not fingerprint then return 0, 0 end

  local snapshot = hs.window.allWindows()
  local byId = {}
  for _, win in ipairs(snapshot) do
    local id = win:id()
    if id then byId[id] = win end
  end
  local screens = screenFrames()
  local counts = {}

  -- Prune ids whose window is gone, so the session table cannot grow for a whole login.
  local slot = self._session[fingerprint]
  if slot then
    for id in pairs(slot) do
      if not byId[id] then slot[id] = nil end
    end
  end

  -- Replaced rather than merged, exactly like the counters below, so the baseline that reads
  -- this once the campaign ends only ever sees the ids the final pass could not reach, never one
  -- an earlier pass failed on and this one already corrected.
  local unplaced = {}

  local deferred, refused, placed = 0, 0, 0
  for _, win in ipairs(snapshot) do
    if placeable(win) then
      local id = win:id()
      local f = (slot and id) and slot[id] or nil
      if not f then f = self:_persistentFrame(win, fingerprint, counts) end
      if f then
        if targetScreenReady(f, screens) then
          -- placed counts every remembered window verified in place on this pass, including one
          -- already sitting exactly where it belongs, since _place answers true on the compare
          -- and skip shortcut too and that window is just as correctly placed for it.
          if self:_place(win, f, screens) then
            placed = placed + 1
          else
            refused = refused + 1
            if id then unplaced[id] = true end
            if verbose then
              local app = win:application()
              local name = (app and app:bundleID()) or "an app with no bundle id"
              log.w(string.format("%s refused placement, asked for %s and holds %s",
                name, frameStr(f), frameStr(win:frame())))
            end
          end
        else
          deferred = deferred + 1
          if id then unplaced[id] = true end
        end
      end
    end
  end

  self._unplaced = unplaced

  -- Written directly onto the episode's own counters rather than added to a running total,
  -- since a window already placed on an earlier pass answers placed again here without having
  -- needed anything a second time, so this pass's own numbers are the honest state of the whole
  -- campaign so far and the last pass to run is the one whose numbers belong in the summary.
  if self._episodeStats then
    self._episodeStats.placed = placed
    self._episodeStats.refused = refused
    self._episodeStats.deferred = deferred
  end

  return deferred, refused
end

-- Walked once when an episode closes, after the campaign's placements are done, while recording
-- is still deaf, so a window nobody ever dragged and no app placed for itself is not left forever
-- wherever macOS happened to put it. Only a gap in the session layer is filled, and only with
-- that window's own current frame, never the store, since the persistent layer's one frame per
-- app is answered by the focused window rule and has no business with a window nobody chose.
--
-- A window the last pass could not place, refused or deferred, is skipped here even when the
-- session has no entry for it yet, since that window is only sitting in its current frame
-- because nothing was able to move it, and writing that frame as its memory would let a wrong
-- session entry win over a correct one already waiting for it in the store on every later dock
-- under this fingerprint. A window that already had a session entry is left alone for the same
-- reason regardless, which is why this only ever fills a missing entry that a window actually
-- earned by resting in a frame nothing was still trying to change.
--
-- THIS DOES NOT CLEAR _unplaced. Whatever the campaign could not place stays excluded through the
-- steady state that follows too, since a window stuck in the wrong frame keeps producing frame
-- events of its own that are an echo of the campaign rather than a person, and _commit is what
-- consults this set on every later stage. Only the next _disturb clears it, because only a fresh
-- episode means the old campaign's verdict no longer applies.
--
-- A window still waiting on its own birth timer in _births is skipped too, since a newborn found
-- mid episode has not had its own placement attempt yet, and pinning it here at whatever frame it
-- happened to open with would teach the session the wrong thing before the window ever got its
-- chance.
function E:_fillBaseline()
  local fingerprint = self._fingerprint
  if not fingerprint then return 0 end
  local slot = self._session[fingerprint]
  if not slot then
    slot = {}
    self._session[fingerprint] = slot
  end
  local unplaced = self._unplaced or {}
  local filled = 0
  for _, win in ipairs(hs.window.allWindows()) do
    if placeable(win) then
      local id = win:id()
      if id and slot[id] == nil and not unplaced[id] and not self._births[id] then
        local f = win:frame()
        slot[id] = { x = whole(f.x), y = whole(f.y), w = whole(f.w), h = whole(f.h) }
        filled = filled + 1
      end
    end
  end
  return filled
end

--- E:restoreNow()
--- Method
--- Run a restore pass for the configuration attached right now, on purpose rather than because
--- something changed. Goes through the same episode machinery, so recording stays deaf and the
--- retry campaign still covers a display that is awake but not ready. A campaign already running
--- is cancelled and started over, since _disturb treats this exactly as it treats a screen event,
--- so asking twice in a row costs one restore rather than two overlapping ones.
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
--
-- EVERY WINDOW BORN ANYWHERE ON THE MACHINE ARRIVES HERE, and the overwhelming majority belong
-- to apps this configuration has never remembered, so the store is asked before anything is
-- scheduled at all. That turns an ordinary window opening into two table lookups instead of a
-- timer, a wake up, and a window walk half a second later. The one window rule is deliberately
-- left to _placeNewborn rather than checked here too, since an app opening its second window is
-- most likely to still be opening it right now, and the honest moment to count is when the
-- placement would actually happen.
--
-- AN EPISODE BEING OPEN NO LONGER EXCUSES THIS. A window can be born in the middle of a shuffle
-- just as easily as any other time, and giving up on it here would mean its placement never
-- happens at all rather than merely waiting, so scheduling proceeds exactly as it does in steady
-- state and _placeNewborn is the one that actually waits for the episode to close.
--
-- The window object the filter handed us is carried through rather than looked up again by id.
-- hs.window.get walks the whole window list, so re fetching a window we were already given was
-- paying a full sweep for something already in hand, and placeable asks the object for its id
-- first, which is how an object outliving its window is caught.
function E:_onBorn(win)
  if not self._store then return end
  local id = win and win:id()
  if not id then return end
  local fingerprint = self._fingerprint
  if not fingerprint then return end
  local app = win:application()
  local bundleID = app and app:bundleID()
  if not bundleID then return end
  if not self._store:appFrame(fingerprint, bundleID) then return end
  if self._births[id] then self._births[id]:stop() end
  self._births[id] = hs.timer.doAfter(BIRTH_DELAY, function()
    self._births[id] = nil
    self:_placeNewborn(win, fingerprint, 0)
  end)
end

-- An episode found open here means this window was born mid shuffle, so placing it now would mean
-- placing it against geometry that has not settled, exactly the noise the episode flag exists to
-- keep out. Rather than give up, this reschedules itself a quiet beat plus a birth delay later and
-- tries again, since a campaign that closes normally will have cleared the flag by then. retries
-- is bounded, since an episode that somehow never closes must not be waited on forever, and a
-- newborn that gives up this way is simply left unplaced, no different from one nobody remembered
-- in the first place.
--
-- A placement macOS refuses here is recorded into _unplaced exactly as a refusal during a restore
-- pass is, so the frame it is stuck in is never mistaken for its memory. There is no retry
-- campaign for a newborn, unlike a restore pass, since a freshly launched window that macOS will
-- not move is not expected to become movable two seconds later, and a person still watching it
-- open is a worse audience for a silent multi second fight than an episode already running deaf.
function E:_placeNewborn(win, fingerprint, retriesLeft)
  if self._episode then
    retriesLeft = retriesLeft or 0
    if retriesLeft >= NEWBORN_WAIT_RETRIES then return end
    local id = win and win:id()
    if not id then return end
    if self._births[id] then self._births[id]:stop() end
    self._births[id] = hs.timer.doAfter(QUIET_BEAT + BIRTH_DELAY, function()
      self._births[id] = nil
      self:_placeNewborn(win, fingerprint, retriesLeft + 1)
    end)
    return
  end
  if fingerprint ~= self._fingerprint then return end
  if not placeable(win) then return end
  local f = self:_persistentFrame(win, fingerprint)
  if not f then return end
  local screens = screenFrames()
  if not targetScreenReady(f, screens) then return end
  self:_mute(MUTE_TAIL)
  if not self:_place(win, f, screens) then
    local id = win:id()
    if id then
      self._unplaced = self._unplaced or {}
      self._unplaced[id] = true
    end
  end
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

--- E:ensureCurrent()
--- Method
--- Make sure the configuration attached right now exists, with a generated name. Called after a
--- delete, because deleting the attached configuration means forget what it remembered rather
--- than make it cease to exist. Which screens are attached is a fact, not a preference, so the
--- configuration comes straight back empty and named the way one seen for the first time is.
--- Routed through the engine rather than done by the caller so that the single creation door
--- above stays single.
function E:ensureCurrent()
  local fingerprint, rects = self:fingerprint()
  self._fingerprint = fingerprint
  self:_ensure(fingerprint, rects)
  return self
end

--- E:forgetSessionApp(fingerprint, bundleID)
--- Method
--- Drop every session entry belonging to one app under one configuration. Forgetting an app in
--- the store alone would not be forgetting, since the session layer wins on restore and would
--- put that app's windows back from a memory nobody can see or prune.
--- One snapshot here too, for the same reason the restore pass takes one. This runs on a key
--- press rather than in a timer, so the cost is a visible stall rather than a background one,
--- which is worse to meet and not better. An id the snapshot does not answer for belongs to a
--- window that is gone, so it is dropped either way.
function E:forgetSessionApp(fingerprint, bundleID)
  local slot = self._session[fingerprint]
  if not slot or not bundleID then return end
  local byId = {}
  for _, win in ipairs(hs.window.allWindows()) do
    local id = win:id()
    if id then byId[id] = win end
  end
  for id in pairs(slot) do
    local win = byId[id]
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
