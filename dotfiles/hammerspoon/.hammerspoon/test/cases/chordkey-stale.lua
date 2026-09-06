-- Unit case for the staleness watchdog in Olm.spoon/lib/chordkey.lua, and for the release
-- ordering it shares with a real key-up. Both exist for one fault, a leader whose key-up never
-- arrived and which then swallowed every later keystroke into the chord path, so the checks
-- here are all shapes of that fault rather than shapes of ordinary use.
--
-- Unlike cases/chordkey-repeat.lua, which said the tap was out of reach from here, this case
-- does drive it. The engine takes its tap from hs.eventtap.new, so an environment of this
-- case's own can hand it a fake that keeps the callback rather than installing anything, and
-- the callback is then an ordinary function taking an event shaped table. Nothing here touches
-- the running Hammerspoon, posts a key, or waits, and the clock is read rather than passed.
--
-- Each check prints one line, PASS or FAIL followed by a plain description, and the runner
-- counts from those lines alone, the same convention every other case follows.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local modulePath = caseDir .. "/../../Spoons/Olm.spoon/lib/chordkey.lua"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local function near(a, b)
  return math.abs(a - b) < 1e-9
end

local KEY_DOWN, KEY_UP = 10, 11
local PROP_SOURCE, PROP_REPEAT = 45, 8
local HID = 1

-- One fake world per module load. The clock keeps every outstanding timer rather than the one
-- the repeat case needed, since a held leader has a hold timer and a staleness timer alive at
-- the same moment and the checks below fire one without disturbing the other.
local function freshModule(opts)
  opts = opts or {}
  local world = { timers = {}, posted = {}, now = 1000 }

  local function doAfter(delay, fn)
    local entry = { delay = delay, fn = fn, live = true }
    entry.handle = { stop = function() entry.live = false end }
    world.timers[#world.timers + 1] = entry
    return entry.handle
  end

  local fakeHs = {
    timer = {
      doAfter = doAfter,
      secondsSinceEpoch = function() return world.now end,
    },
    eventtap = {
      -- The machine's own two beats, fixed here so the case reads the same on any keyboard.
      -- A delay of 0.5 makes the staleness window 1.5, which every check below names.
      keyRepeatDelay = function() return opts.repeatDelay or 0.5 end,
      keyRepeatInterval = function() return 0.1 end,
      new = function(_, fn)
        world.callback = fn
        return { start = function() return true end, stop = function() return true end }
      end,
      event = {
        types = { keyDown = KEY_DOWN, keyUp = KEY_UP },
        properties = { eventSourceStateID = PROP_SOURCE, keyboardEventAutorepeat = PROP_REPEAT },
        newKeyEvent = function(mods, code, isDown)
          return { post = function()
            world.posted[#world.posted + 1] = { code = code, down = isDown }
          end }
        end,
      },
    },
  }

  -- Fire the newest timer still live whose wait is this one, which is how a check names the
  -- staleness window without depending on the order two armed timers happen to sit in.
  world.fireDelay = function(delay)
    for i = #world.timers, 1, -1 do
      local entry = world.timers[i]
      if entry.live and near(entry.delay, delay) then
        entry.live = false
        entry.fn()
        return true
      end
    end
    return false
  end

  world.liveWithDelay = function(delay)
    local n = 0
    for _, entry in ipairs(world.timers) do
      if entry.live and near(entry.delay, delay) then n = n + 1 end
    end
    return n
  end

  local env = {
    hs = fakeHs, math = math, table = table, string = string,
    type = type, pairs = pairs, ipairs = ipairs, tostring = tostring, print = print,
  }
  local chunk, err = loadfile(modulePath, "t", env)
  if not chunk then
    error("could not load Olm.spoon/lib/chordkey.lua, " .. tostring(err))
  end
  return chunk(), world
end

-- An event shaped exactly as much as the tap reads it, which is its type, its keycode, its
-- flags, and the two properties the guards ask for.
local function event(kind, code, isRepeat, sourceState)
  return {
    getType = function() return kind end,
    getKeyCode = function() return code end,
    getFlags = function() return {} end,
    getProperty = function(_, prop)
      if prop == PROP_SOURCE then return sourceState or HID end
      if prop == PROP_REPEAT then return isRepeat and 1 or 0 end
      return 0
    end,
  }
end

local function leaderEngine(opts)
  opts = opts or {}
  local engine, world = freshModule(opts)
  engine:init()
  local seen = { tap = 0, holdEnd = 0, hold = 0 }
  engine:addKey(79, {
    holdDelay = 0.6,
    tapThreshold = 0.2,
    passthrough = opts.passthrough ~= false,
    onTap = function() seen.tap = seen.tap + 1 end,
    onHold = function() seen.hold = seen.hold + 1 end,
    onHoldEnd = function() seen.holdEnd = seen.holdEnd + 1 end,
    onKey = function() return nil end,
  })
  engine:start()
  return engine, world, seen
end

-- The window comes off the machine rather than being written down, because the gap it has to
-- outlast is the machine's own delay before a held key starts repeating.
do
  local engine, world = leaderEngine()
  world.callback(event(KEY_DOWN, 79))
  check("a leader key-down arms a staleness window twice the machine's repeat delay plus a beat",
    world.liveWithDelay(1.5) == 1,
    "live windows at 1.5s " .. tostring(world.liveWithDelay(1.5)))
  check("the hold overlay timer is still armed beside it and untouched",
    world.liveWithDelay(0.6) == 1,
    "live timers at 0.6s " .. tostring(world.liveWithDelay(0.6)))
  check("the engine has the leader held", engine:isActive(79))
end

-- A machine with key repeat switched off reports an enormous delay and would otherwise arm a
-- window that never fires, so the cap is what keeps the recovery bounded there.
do
  local _, world = leaderEngine({ repeatDelay = 5000 })
  world.callback(event(KEY_DOWN, 79))
  check("a machine reporting no key repeat still gets a bounded window, capped at thirty seconds",
    world.liveWithDelay(30) == 1,
    "live windows at 30s " .. tostring(world.liveWithDelay(30)))
end

-- The autorepeat of a held key is the only positive evidence the finger is still down, so it
-- has to push the window out rather than being ignored the way every other repeat is.
do
  local _, world = leaderEngine()
  world.callback(event(KEY_DOWN, 79))
  world.callback(event(KEY_DOWN, 79, true))
  world.callback(event(KEY_DOWN, 79, true))
  check("each autorepeat of the held leader replaces the window rather than adding one",
    world.liveWithDelay(1.5) == 1,
    "live windows at 1.5s " .. tostring(world.liveWithDelay(1.5)))
  check("the windows it replaced were stopped", #world.timers >= 4)
end

-- The fault itself. The key-up is simply never delivered, which is what secure input, a tap the
-- system disabled, and a callback that threw all look like from in here.
do
  local engine, world, seen = leaderEngine()
  world.callback(event(KEY_DOWN, 79))
  world.fireDelay(0.6)
  check("holding past the delay shows the overlay", seen.hold == 1)

  world.now = world.now + 1.5
  world.fireDelay(1.5)
  check("a leader that went silent while still held is released", not engine:isActive(79))
  check("releasing it takes the overlay down", seen.holdEnd == 1,
    "onHoldEnd ran " .. tostring(seen.holdEnd) .. " times")
  check("the recovery does not invent a tap the person never made", seen.tap == 0,
    "onTap ran " .. tostring(seen.tap) .. " times")
  check("the leader synthesized downstream is lifted with it, so nothing sticks system wide",
    (function()
      for _, p in ipairs(world.posted) do
        if p.code == 79 and p.down == false then return true end
      end
      return #world.posted == 0
    end)())
end

-- A key pressed after the recovery is an ordinary key again, which is the whole point of it.
-- Before this, every one of them resolved as a chord and fired whatever the leader bound.
do
  local engine, world = leaderEngine()
  world.callback(event(KEY_DOWN, 79))
  world.now = world.now + 1.5
  world.fireDelay(1.5)
  local swallowed = world.callback(event(KEY_DOWN, 4))
  check("an ordinary key after the recovery is no longer swallowed into the chord path",
    swallowed == false, "the tap answered " .. tostring(swallowed))
end

-- A real key-up must leave nothing armed behind it, or a window from a finished hold would fire
-- into the next one.
do
  local engine, world, seen = leaderEngine()
  world.callback(event(KEY_DOWN, 79))
  world.now = world.now + 0.1
  world.callback(event(KEY_UP, 79))
  check("a real key-up releases the leader", not engine:isActive(79))
  check("a real key-up leaves no staleness window armed", world.liveWithDelay(1.5) == 0,
    "live windows at 1.5s " .. tostring(world.liveWithDelay(1.5)))
  -- onTap is handed to the next tick rather than run here, so that the key-up is fully
  -- processed before a consumer that synthesizes keystrokes gets to run. See _defer.
  world.fireDelay(0)
  check("a real quick press and release still fires the tap", seen.tap == 1,
    "onTap ran " .. tostring(seen.tap) .. " times")
end

-- A window that fires after its leader was already released has nothing to recover, and must
-- not run a second release over a key that is resting.
do
  local _, world, seen = leaderEngine()
  world.callback(event(KEY_DOWN, 79))
  world.now = world.now + 0.1
  world.callback(event(KEY_UP, 79))
  local before = seen.tap
  world.fireDelay(1.5)
  check("a window that lands after a real release does nothing", seen.tap == before,
    "onTap ran " .. tostring(seen.tap) .. " against " .. tostring(before))
end

-- The ordering half of the fix, stated as the fault it was. onHoldEnd runs on the event tap
-- thread and tears a canvas down, so anything it throws used to abandon the rest of the release
-- with active still standing, which is the stuck leader arriving by a second road.
do
  local engine = freshModule()
  engine:init()
  engine:addKey(79, {
    onHoldEnd = function() error("the overlay teardown threw") end,
  })
  local k = engine._keys[79]
  k.active = true
  k.shown = true
  k.downTime = 1000
  local ok = pcall(function() engine:_release(k) end)
  check("a consumer callback that throws is not swallowed and still reaches the caller", not ok)
  check("but it can no longer leave the leader held, since the reset ran before it",
    not engine:isActive(79))
end

-- Synthetic keystrokes are not evidence of anything. The guard that already kept a consumer's
-- own paste out of the chord path also keeps one from arming a window.
do
  local engine, world = leaderEngine()
  world.callback(event(KEY_DOWN, 79, false, 2))
  check("a keystroke this config posted itself neither holds the leader nor arms a window",
    not engine:isActive(79) and world.liveWithDelay(1.5) == 0)
end

-- A stop is a teardown, so it must take the windows with it rather than leaving one to fire
-- into an engine that is no longer watching anything.
do
  local engine, world = leaderEngine()
  world.callback(event(KEY_DOWN, 79))
  engine:stop()
  check("stopping the engine disarms the staleness window", world.liveWithDelay(1.5) == 0,
    "live windows at 1.5s " .. tostring(world.liveWithDelay(1.5)))
  check("stopping the engine clears the held state", not engine:isActive(79))
end
