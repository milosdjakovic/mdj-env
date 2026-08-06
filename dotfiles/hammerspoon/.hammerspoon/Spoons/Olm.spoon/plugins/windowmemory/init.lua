--- === WindowMemory ===
---
--- Remember every window's frame, scoped by location, and restore it automatically.
---
--- The reusable mechanism only, DisplayMemory widened from one app to all windows and
--- from a stored display to a stored frame. It watches all standard windows for moves
--- and resizes, records each window's frame under the current location scope, and
--- reapplies the recorded frames when the location changes by docking, undocking, or
--- waking. It never decides what a location is, the composition root injects a `scope`
--- that names the current one, exactly as DisplayMemory takes an injected scope.
---
--- Memory is one in memory table, scope to a map of live window id to frame. It is not
--- persisted, because a window id means nothing after a reboot and persisting it would
--- risk a fresh window colliding with a stale id. So the memory is session scoped, which
--- is all the automatic docking and waking case needs, since within one login every live
--- window keeps its id. A reload empties the table and it refills as windows move.
---
--- Two guards keep recording honest, both resting on real state rather than a clock. A
--- record is written only when no restore episode is active and the new frame differs
--- from the stored one by more than a small pixel tolerance. The tolerance test is
--- idempotent and absorbs the asynchronous echo of our own setFrame calls. The episode
--- flag suppresses the burst of moves macOS fires while displays are settling, which is
--- noise, not intent, and it is cleared when the triggered restore actually finishes.
---
--- Restore tolerates a slow waking display. A monitor is not ready the instant it connects,
--- so a window whose stored frame lands on a display not attached yet is left alone rather
--- than placed onto coordinates macOS would clamp onto the wrong screen, and the restore is
--- retried a few times until that display comes up.
---
--- This is the olm side copy of WindowMemory, made in the bundling pass, phase 6 of the
--- olm build plan, and the original this was copied from still lives at
--- Spoons/WindowMemory.spoon.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "WindowMemory"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("WindowMemory", "info")

-- Restore waits this much longer than DisplayProfiles does, so on a shared burst of screen
-- events DisplayProfiles settles and applies its arrangement first, and its displayplacer
-- changes are themselves screen events that push our restore out again. So window frames are
-- placed only after the geometry has settled, with no direct dependency on DisplayProfiles.
local ORDER_MARGIN = 0.5
-- After a restore, hold the episode flag this long so the trailing asynchronous move
-- events from our own placement stay suppressed. The tolerance guard also covers them,
-- so this is belt and suspenders.
local END_TAIL = 0.3
-- Backstop past the restore, so a disturbance that never restores cannot wedge recording
-- off forever.
local SAFETY_SLACK = 2.0
-- A slow waking external display is not ready the instant it connects, so a window whose
-- display is not present yet is left alone and the restore is retried. These bound the
-- retry, one pass every RETRY_INTERVAL seconds up to MAX_RETRIES, about a dozen seconds,
-- long enough for a slow monitor to come up without retrying forever.
local RETRY_INTERVAL = 2.0
local MAX_RETRIES = 6

-- Dependencies and config (injected via configure)
obj._scope = nil       -- string or function naming the current location
obj._tolerance = nil   -- pixels of slack when comparing frames
obj._settleDelay = nil -- seconds to coalesce a burst of screen or wake events

-- Owned state
obj._filter = nil        -- hs.window.filter over all standard windows
obj._screenWatcher = nil -- hs.screen.watcher, re-arms the settle timer on each change
obj._wakeWatcher = nil   -- hs.caffeinate.watcher, restores on wake
obj._debounce = nil      -- settle timer, re-armed per screen event so it fires once geometry is quiet
obj._safety = nil        -- backstop timer that force clears the episode flag
obj._endTail = nil       -- clears the episode flag after a restore settles
obj._retry = nil         -- delayed retry when a window's display was not ready yet
obj._mem = nil           -- { [scope] = { [windowId] = {x,y,w,h} } }
obj._applying = false    -- true while a restore episode is in progress

-- A window worth placing, standard and on screen and neither minimized nor fullscreen.
-- The window filter already enforces this for the record path, but restore reaches
-- windows by id straight from hs.window.get, so it re-checks here.
local function placeable(win)
  return win ~= nil
    and win:isStandard()
    and not win:isMinimized()
    and not win:isFullScreen()
end

-- Whether two frames are the same within the tolerance, the compare and skip test.
local function sameFrame(a, b, tol)
  return math.abs(a.x - b.x) <= tol
    and math.abs(a.y - b.y) <= tol
    and math.abs(a.w - b.w) <= tol
    and math.abs(a.h - b.h) <= tol
end

-- Whether the stored frame lands on a screen attached right now, tested by its center. A
-- slow waking external display is briefly absent, so its windows have no live screen to
-- sit on, and placing them anyway lets macOS clamp them onto the wrong display. So a frame
-- whose center is on no attached screen is treated as not yet placeable, to be retried. The
-- containment is done by hand against each screen's full frame, since hs.screen.find matches
-- a name or id, not a point.
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

--- WindowMemory:init()
--- Method
--- Initialize the spoon. No side effects, per the lifecycle contract.
function obj:init()
  self._mem = {}
  return self
end

--- WindowMemory:configure(opts)
--- Method
--- Configure the spoon. opts.scope names the current location, a string or a function
--- returning one, evaluated live so it tracks docking and undocking. opts.tolerance is
--- the pixel slack for the compare and skip test, default 5. opts.settleDelay is the
--- seconds to coalesce a burst of screen or wake events before restoring, default 1.5.
function obj:configure(opts)
  opts = opts or {}
  self._scope = opts.scope
  self._tolerance = opts.tolerance or 5
  self._settleDelay = opts.settleDelay or 1.5
  return self
end

--- WindowMemory:_scopeKey()
--- Method
--- The current location scope as a string. A function scope is called live, a string is
--- used as is, and nil collapses to one shared slot.
function obj:_scopeKey()
  local s = self._scope
  if type(s) == "function" then s = s() end
  if type(s) ~= "string" or s == "" then return "default" end
  return s
end

--- WindowMemory:_record(win)
--- Method
--- Record the window's frame under the current scope, unless an episode is active or the
--- frame is within tolerance of what is already stored.
function obj:_record(win)
  if self._applying then return end
  if not placeable(win) then return end
  local id = win:id()
  if not id then return end
  local f = win:frame()
  local scope = self:_scopeKey()
  local slot = self._mem[scope]
  if not slot then
    slot = {}
    self._mem[scope] = slot
  end
  local stored = slot[id]
  if stored and sameFrame(stored, f, self._tolerance) then return end
  slot[id] = { x = f.x, y = f.y, w = f.w, h = f.h }
end

--- WindowMemory:_restoreOnce()
--- Method
--- One restore pass over the current scope. Reapply each stored frame to the window still
--- open, skip any already within tolerance, prune ids whose window is gone, and leave a
--- window alone when its display is not attached yet. Returns the number of windows deferred
--- for a display that was not ready, so the caller can decide whether to retry.
function obj:_restoreOnce()
  local scope = self:_scopeKey()
  local slot = self._mem[scope]
  local deferred = 0
  if slot then
    for id, f in pairs(slot) do
      local win = hs.window.get(id)
      if not win then
        slot[id] = nil
      elseif placeable(win) then
        if not targetScreenReady(f) then
          deferred = deferred + 1
        else
          local cur = win:frame()
          if not sameFrame(cur, f, self._tolerance) then
            win:setFrame(hs.geometry.rect(f.x, f.y, f.w, f.h), 0)
          end
        end
      end
    end
  end
  return deferred
end

--- WindowMemory:restore()
--- Method
--- Reapply the stored frames for the current scope, retrying while any window's display is
--- still waking. Cancels the settle timer and any prior retry, since this call is taking
--- over, runs a pass, and if some windows were deferred for a not yet ready display schedules
--- another pass, up to MAX_RETRIES. Ends the episode once a pass defers nothing or the
--- retries run out. Called from the settle timer once geometry is quiet, or from the console.
function obj:restore()
  if self._debounce then self._debounce:stop() end
  if self._retry then
    self._retry:stop()
    self._retry = nil
  end
  self:_runRestore(MAX_RETRIES)
  return self
end

--- WindowMemory:_runRestore(attemptsLeft)
--- Method
--- One pass plus its retry scheduling. Kept apart from restore so a retry re-enters here
--- without re-cancelling the timers restore already cleared.
function obj:_runRestore(attemptsLeft)
  local deferred = self:_restoreOnce()
  if deferred > 0 and attemptsLeft > 0 then
    self._retry = hs.timer.doAfter(RETRY_INTERVAL, function()
      self._retry = nil
      self:_runRestore(attemptsLeft - 1)
    end)
  else
    if deferred > 0 then
      log.w(string.format("%d window(s) left unplaced, their display never became ready", deferred))
    end
    self:_endEpisode()
  end
end

--- WindowMemory:_beginEpisode()
--- Method
--- Mark a restore episode as active so recording stops, and arm a backstop that clears the
--- flag even if no restore runs, so recording can never stay wedged off. The backstop spans
--- the whole possible episode, the settle wait plus a full retry campaign, so it never fires
--- mid campaign and reopens recording while a slow display is still being waited on. Any
--- pending end tail from a prior episode is cancelled so it cannot clear the flag now.
function obj:_beginEpisode()
  self._applying = true
  if self._endTail then
    self._endTail:stop()
    self._endTail = nil
  end
  if self._safety then self._safety:stop() end
  local maxEpisode = self._settleDelay + ORDER_MARGIN + MAX_RETRIES * RETRY_INTERVAL + SAFETY_SLACK
  self._safety = hs.timer.doAfter(maxEpisode, function()
    self._applying = false
  end)
end

--- WindowMemory:_endEpisode()
--- Method
--- End a restore episode, clearing the flag after a short tail so the trailing
--- asynchronous move events from our own placement stay suppressed.
function obj:_endEpisode()
  if self._safety then
    self._safety:stop()
    self._safety = nil
  end
  if self._endTail then self._endTail:stop() end
  self._endTail = hs.timer.doAfter(END_TAIL, function()
    self._applying = false
  end)
end

--- WindowMemory:_onDisturbance()
--- Method
--- A screen change or a wake. Start the episode at once so the settling burst is not
--- recorded, and re-arm the settle timer. Because every screen change re-arms it, including
--- the ones DisplayProfiles causes when it applies an arrangement, the timer fires only after
--- the geometry has gone quiet, so windows are placed once at the end rather than jumping
--- through each intermediate layout. A retry campaign still running from an earlier
--- disturbance is cancelled, so the fresh disturbance drives the next restore cleanly.
function obj:_onDisturbance()
  if self._retry then
    self._retry:stop()
    self._retry = nil
  end
  self:_beginEpisode()
  if self._debounce then self._debounce:start() end
end

--- WindowMemory:start()
--- Method
--- Watch all standard windows for moves and resizes, and watch for screen changes and
--- wake. Idempotent.
function obj:start()
  if self._filter then return self end

  -- Standard windows of the normal visible apps, minus Hammerspoon's own so overlays and
  -- choosers are never recorded. The default filter is deliberate over new(true), it already
  -- excludes non standard windows and the known problematic menubar agents (Wallpaper,
  -- Notification Center, MonitorControl), whereas new(true) forces the filter to watch every
  -- one of them, which floods the log and stalls the main thread. Fullscreen and minimized
  -- windows are skipped by placeable at record and restore time. windowMoved is the only
  -- frame change event the filter emits and it covers both moving and resizing.
  self._filter = hs.window.filter.new()
  self._filter:setAppFilter("Hammerspoon", false)
  self._filter:subscribe(hs.window.filter.windowMoved, function(win)
    self:_record(win)
  end)

  -- The settle timer. hs.timer.delayed re-arms on each start, so a disturbance restarts its
  -- countdown and it fires only once no screen change has happened for the whole delay, that
  -- is once the display geometry is quiet. The ORDER_MARGIN keeps it a little longer than
  -- DisplayProfiles' own settle, so DisplayProfiles applies first and its changes re-arm this.
  self._debounce = hs.timer.delayed.new(self._settleDelay + ORDER_MARGIN, function()
    self:restore()
  end)

  -- Every screen change begins an episode, suppressing the settling burst, and re-arms the
  -- settle timer above, so the restore lands once the geometry stops moving.
  self._screenWatcher = hs.screen.watcher.new(function()
    self:_onDisturbance()
  end)
  self._screenWatcher:start()

  -- Wake restores too, since a wake that did not change the display set fires no screen
  -- event, which is the terminal on wake gap this closes.
  self._wakeWatcher = hs.caffeinate.watcher.new(function(event)
    if event == hs.caffeinate.watcher.systemDidWake
      or event == hs.caffeinate.watcher.screensDidWake then
      self:_onDisturbance()
    end
  end)
  self._wakeWatcher:start()

  log.i("started, watching all standard windows")
  return self
end

--- WindowMemory:stop()
--- Method
--- Stop watching and tear down every timer and watcher. The stored frames are kept, so a
--- restart of the watchers can still restore them within the session.
function obj:stop()
  if self._filter then
    self._filter:unsubscribeAll()
    self._filter = nil
  end
  if self._screenWatcher then
    self._screenWatcher:stop()
    self._screenWatcher = nil
  end
  if self._wakeWatcher then
    self._wakeWatcher:stop()
    self._wakeWatcher = nil
  end
  if self._debounce then
    self._debounce:stop()
    self._debounce = nil
  end
  if self._safety then
    self._safety:stop()
    self._safety = nil
  end
  if self._endTail then
    self._endTail:stop()
    self._endTail = nil
  end
  if self._retry then
    self._retry:stop()
    self._retry = nil
  end
  self._applying = false
  return self
end

return obj
