--- The keep awake state machine, the mechanism.
---
--- Wraps hs.caffeinate to hold the display awake, either indefinitely or until a
--- moment in time, and owns the single expiry timer that ends a timed session. It
--- knows nothing about the chooser or Hyper. It exposes a small API and fires an
--- injected onChange after any state change, so a ui can refresh if it is open.
---
--- displayIdle is the assertion, so the screen stays on rather than only the
--- system staying awake. The assertion does not survive a config reload, the
--- pathwatcher drops it every time a Hammerspoon file is edited, so the session is
--- persisted to hs.settings and restored on start. An indefinite hold comes back
--- indefinite, and a timed hold comes back with its real remaining time, the timer
--- re-armed for whatever is left, or ended if it already lapsed while the config
--- was down.

local Engine = {}

-- One hs.settings key holds a snapshot of the session, the same shape status()
-- returns, so a reload or a relaunch can restore it. The assertion itself is
-- process state that a reload discards, this is the durable record of what the
-- session was.
local SETTINGS_KEY = "caffeinateSession"

local state = { active = false, expiry = nil } -- expiry nil while active means indefinite
local timer = nil
local onChange = nil

local function cancelTimer()
  if timer then
    timer:stop()
    timer = nil
  end
end

local function assertAwake(on)
  hs.caffeinate.set("displayIdle", on, true) -- true, apply on AC and battery
end

-- Save the current session so it survives a reload or a relaunch. expiry nil is an
-- indefinite hold and reads back as nil, expiry set is the absolute end.
local function persist()
  hs.settings.set(SETTINGS_KEY, { active = state.active, expiry = state.expiry })
end

local function changed()
  if onChange then onChange() end
end

--- Engine.configure(opts) - inject onChange, called after any state change.
function Engine.configure(opts)
  opts = opts or {}
  onChange = opts.onChange or onChange
  return Engine
end

--- Engine.start() - restore the persisted session, so a reload or a relaunch keeps
--- keep awake on. A reload drops the assertion, so this reapplies it. An indefinite
--- hold comes back indefinite, a timed hold with time left comes back with the timer
--- re-armed for the remaining span, a timed hold whose end already passed while the
--- config was down is ended, and anything not active is left off.
function Engine.start()
  local saved = hs.settings.get(SETTINGS_KEY)
  if not (saved and saved.active) then
    assertAwake(false)
    state.active, state.expiry = false, nil
    return Engine
  end
  if not saved.expiry then
    assertAwake(true)
    state.active, state.expiry = true, nil
    return Engine
  end
  local remaining = saved.expiry - os.time()
  if remaining <= 0 then
    assertAwake(false)
    state.active, state.expiry = false, nil
    persist()
    return Engine
  end
  assertAwake(true)
  state.active, state.expiry = true, saved.expiry
  timer = hs.timer.doAfter(remaining, function() Engine.disable() end)
  return Engine
end

--- Engine.keepIndefinitely() - hold awake with no time limit.
function Engine.keepIndefinitely()
  cancelTimer()
  assertAwake(true)
  state.active, state.expiry = true, nil
  persist()
  changed()
end

--- Engine.keepUntil(ts) - hold awake until the absolute time ts, then disable.
function Engine.keepUntil(ts)
  cancelTimer()
  assertAwake(true)
  state.active, state.expiry = true, ts
  -- doAfter with the remaining span, not doAt with the absolute time. doAt reads its
  -- argument as a time of day, so an absolute epoch value schedules the fire decades
  -- out and the session never ends on its own.
  timer = hs.timer.doAfter(ts - os.time(), function() Engine.disable() end)
  persist()
  changed()
end

--- Engine.keepFor(seconds) - hold awake for a span from now.
function Engine.keepFor(seconds)
  Engine.keepUntil(os.time() + seconds)
end

--- Engine.disable() - release the assertion and end any timed session.
function Engine.disable()
  cancelTimer()
  assertAwake(false)
  state.active, state.expiry = false, nil
  persist()
  changed()
end

--- Engine.status() - a snapshot { active, expiry } for the ui to render.
function Engine.status()
  return { active = state.active, expiry = state.expiry }
end

return Engine
