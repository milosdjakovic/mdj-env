--- The keep awake state machine, the mechanism.
---
--- Wraps hs.caffeinate to hold the display awake, either indefinitely or until a
--- moment in time, and owns the single expiry timer that ends a timed session. It
--- knows nothing about the chooser or Hyper. It exposes a small API and fires an
--- injected onChange after any state change, so a ui can refresh if it is open.
---
--- displayIdle is the assertion, so the screen stays on rather than only the
--- system staying awake. On start it reads the live assertion back, so a reload
--- reflects whether keep awake was on, though the timer of a timed session is not
--- restored (a known v1 limit, the session then runs until disabled by hand).

local Engine = {}

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

local function changed()
  if onChange then onChange() end
end

--- Engine.configure(opts) - inject onChange, called after any state change.
function Engine.configure(opts)
  opts = opts or {}
  onChange = opts.onChange or onChange
  return Engine
end

--- Engine.start() - sync from the live assertion, so a reload reflects reality.
function Engine.start()
  state.active = hs.caffeinate.get("displayIdle") and true or false
  state.expiry = nil -- a timer cannot survive reload, so treat a live session as indefinite
  return Engine
end

--- Engine.keepIndefinitely() - hold awake with no time limit.
function Engine.keepIndefinitely()
  cancelTimer()
  assertAwake(true)
  state.active, state.expiry = true, nil
  changed()
end

--- Engine.keepUntil(ts) - hold awake until the absolute time ts, then disable.
function Engine.keepUntil(ts)
  cancelTimer()
  assertAwake(true)
  state.active, state.expiry = true, ts
  timer = hs.timer.doAt(ts, function() Engine.disable() end)
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
  changed()
end

--- Engine.status() - a snapshot { active, expiry } for the ui to render.
function Engine.status()
  return { active = state.active, expiry = state.expiry }
end

return Engine
