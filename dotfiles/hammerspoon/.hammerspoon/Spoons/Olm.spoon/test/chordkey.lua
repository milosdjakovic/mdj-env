-- The ChordKey engine's hold bookkeeping, in plain Lua.
--
-- What this pins is the recovery of a hold whose key-up never arrived. A leader is remembered as
-- held rather than asked, so a lost key-up leaves it held and every later key is read as a chord.
-- The staleness window cannot end that while a person keeps typing, since each typed key pushes it
-- out, so the blind stream check releases every hold the moment secure input is on or the tap has
-- been disabled. The cases also hold the ordinary paths in place, a tap toggling, a chord firing
-- and a long hold over a list surviving the check.
--
-- It needs no Hammerspoon and no lock. A stub tap hands the test its callback, so a key is a call,
-- and a stub timer runs only when the test says time has passed.
--
-- Run it.
--   lua test/chordkey.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local lib = here .. "../lib/"

local warnings = {}
local now = 0
local timers = {}
local secureInput = false
local tapEnabled = true
local tapStarts = 0
local tapCallback = nil
local posted = {}

local function newTimer(delay, fn, every)
  local t = { at = now + delay, fn = fn, every = every and delay or nil, stopped = false }
  function t:stop() self.stopped = true end
  timers[#timers + 1] = t
  return t
end

-- Move the clock on, firing every timer that falls due in order, a repeating one as often as it
-- would have fired.
local function advance(seconds)
  local target = now + seconds
  while true do
    local nextTimer = nil
    for _, t in ipairs(timers) do
      if not t.stopped and t.at <= target and (not nextTimer or t.at < nextTimer.at) then
        nextTimer = t
      end
    end
    if not nextTimer then break end
    now = nextTimer.at
    if nextTimer.every then
      nextTimer.at = now + nextTimer.every
    else
      nextTimer.stopped = true
    end
    nextTimer.fn()
  end
  now = target
end

local types = { keyDown = 10, keyUp = 11 }
local props = { eventSourceStateID = 45, keyboardEventAutorepeat = 8 }

hs = {
  logger = {
    new = function()
      return setmetatable({
        w = function(message) warnings[#warnings + 1] = message end,
      }, { __index = function() return function() end end })
    end,
  },
  timer = {
    doAfter = function(delay, fn) return newTimer(delay, fn, false) end,
    doEvery = function(delay, fn) return newTimer(delay, fn, true) end,
    secondsSinceEpoch = function() return now end,
  },
  eventtap = {
    isSecureInputEnabled = function() return secureInput end,
    keyRepeatDelay = function() return 0.5 end,
    keyRepeatInterval = function() return 0.05 end,
    new = function(_, fn)
      tapCallback = fn
      return {
        start = function() tapEnabled = true tapStarts = tapStarts + 1 end,
        stop = function() tapEnabled = false end,
        isEnabled = function() return tapEnabled end,
      }
    end,
    event = {
      types = types,
      properties = props,
      newKeyEvent = function(mods, code, down)
        return { post = function() posted[#posted + 1] = { code = code, down = down } end }
      end,
    },
  },
}

local failures, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print("FAIL " .. what .. ", got " .. tostring(got) .. ", want " .. tostring(want))
  end
end

-- A physical key event as the tap sees it, returning whether the tap swallowed it.
local function key(code, down, repeated)
  local e = {
    getProperty = function(_, p)
      if p == props.eventSourceStateID then return 1 end
      if p == props.keyboardEventAutorepeat then return repeated and 1 or 0 end
      return 0
    end,
    getType = function() return down and types.keyDown or types.keyUp end,
    getKeyCode = function() return code end,
    getFlags = function() return {} end,
  }
  return (tapCallback(e))
end

local F18, A, B = 79, 0, 11

-- A fresh engine with one leader on F18 that counts its taps and binds A.
local function engine(opts)
  opts = opts or {}
  local ChordKey = dofile(lib .. "chordkey.lua")
  local ck = setmetatable({}, ChordKey):init()
  local counts = { taps = 0, fired = 0 }
  ck:configure({ passthrough = opts.passthrough })
  ck:addKey(F18, {
    onTap = function() counts.taps = counts.taps + 1 end,
    onKey = function(code)
      if code == A then return function() counts.fired = counts.fired + 1 end, false end
      return nil
    end,
  })
  ck:start()
  return ck, counts
end

local function reset()
  warnings, timers, posted = {}, {}, {}
  now, secureInput, tapEnabled, tapStarts = 0, false, true, 0
end

-- A quick press and release is a tap, and nothing is left watching afterwards.
do
  reset()
  local ck, counts = engine()
  key(F18, true)
  advance(0.1)
  key(F18, false)
  advance(0.01)
  eq(counts.taps, 1, "a quick tap toggles")
  eq(ck:isActive(F18), false, "a tap leaves the leader at rest")
  advance(1)
  eq(ck._watch, nil, "the check stops once every key is at rest")
end

-- A chord under the held leader fires and the leader stays held until its key-up.
do
  reset()
  local ck, counts = engine()
  key(F18, true)
  eq(key(A, true), true, "a bound key is swallowed")
  key(A, false)
  advance(0.01)
  eq(counts.fired, 1, "a bound key fires its handler")
  eq(ck:isActive(F18), true, "the leader is still held after a chord")
  key(F18, false)
  advance(0.01)
  eq(counts.taps, 0, "a chord is not a tap")
  eq(ck:isActive(F18), false, "the key-up releases the leader")
end

-- A long hold over a list survives the check while nothing makes the stream blind, which is the
-- path the staleness window was once too short for.
do
  reset()
  local ck = engine()
  key(F18, true)
  key(A, true)
  key(A, false)
  advance(10)
  eq(ck:isActive(F18), true, "a quiet hold of ten seconds is still believed")
  eq(#warnings, 0, "nothing is said about an ordinary hold")
  key(F18, false)
end

-- Secure input turning on while the leader is held releases it, the key-up having gone to a
-- password field the tap could not see, and typing afterwards reaches the app.
do
  reset()
  local ck, counts = engine()
  key(F18, true)
  key(A, true)
  key(A, false)
  advance(0.01)
  secureInput = true
  advance(0.3)
  secureInput = false
  eq(ck:isActive(F18), false, "secure input ends the hold")
  eq(counts.taps, 0, "a recovery never toggles Caps Lock")
  eq(#warnings, 1, "the recovery is said once")
  eq(warnings[1] and warnings[1]:find("secure input", 1, true) ~= nil, true,
    "the line names secure input")
  eq(key(B, true), false, "a key typed after the recovery reaches the app")
  eq(counts.fired, 1, "nothing fires after the recovery")
end

-- The commonest stuck hold. Without the check, typing kept pushing the staleness window out
-- forever, so the leader stayed held for as long as the person kept typing.
do
  reset()
  local ck = engine()
  key(F18, true)
  key(A, true)
  key(A, false)
  secureInput = true
  for _ = 1, 5 do
    advance(0.1)
  end
  secureInput = false
  for _ = 1, 100 do
    key(B, true)
    key(B, false)
    advance(0.2)
  end
  eq(ck:isActive(F18), false, "typing after a lost key-up no longer keeps the leader held")
end

-- A tap the system disabled is started again and every hold it was serving is released.
do
  reset()
  local ck = engine()
  key(F18, true)
  local startsBefore = tapStarts
  tapEnabled = false
  advance(0.3)
  eq(ck:isActive(F18), false, "a disabled tap ends the hold")
  eq(tapStarts, startsBefore + 1, "the tap is started again")
  eq(warnings[1] and warnings[1]:find("disabled", 1, true) ~= nil, true,
    "the line names the disabled tap")
end

-- A recovery closes the passthrough, so a leaked leader is not left down across the machine.
do
  reset()
  local ck = engine({ passthrough = true })
  key(F18, true)
  key(B, true)
  secureInput = true
  advance(0.3)
  secureInput = false
  local leaderUp = false
  for _, p in ipairs(posted) do
    if p.code == F18 and p.down == false then leaderUp = true end
  end
  eq(leaderUp, true, "the synthesized leader key-down gets its key-up")
  eq(ck:isActive(F18), false, "the leaked hold is released")
end

-- Stopping the engine stops the check with it.
do
  reset()
  local ck = engine()
  key(F18, true)
  ck:stop()
  eq(ck._watch, nil, "stop ends the check")
end

print(string.format("%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
