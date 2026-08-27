-- Unit case for the driven repeat in Olm.spoon/lib/chordkey.lua, the schedule a bound key
-- runs on while it stays held. Everything else in that engine is an event tap over real
-- keystrokes and is not reachable from here, so this case deliberately covers the scheduler
-- and the two option defaults around it, and nothing about dispatch.
--
-- The engine is loaded into an environment of this case's own, with a fake hs in it, rather
-- than over the live one. The scheduler is built on hs.timer, and swapping the real
-- hs.timer.doAfter inside a running Hammerspoon to observe it would leave every timer in the
-- live config running through a stub, which a failed assertion would then never put back. A
-- private environment cannot reach that far, and it also lets the waits be read exactly
-- rather than measured, so nothing here sleeps or races.
--
-- Each check prints one line, PASS or FAIL followed by a plain description, and the runner
-- counts from those lines alone, the same convention cases/recency.lua already follows.

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

-- One fake clock per module load. `pending` holds the single scheduled tick the chain ever
-- has outstanding, and `fire` runs it the way the runloop would, so a wait is read as the
-- number the engine asked for instead of being waited out.
local function freshModule()
  local clock = { pending = nil, stopped = 0, waits = {} }
  local fakeHs = {
    timer = {
      doAfter = function(delay, fn)
        clock.waits[#clock.waits + 1] = delay
        local handle = { stop = function(self) clock.stopped = clock.stopped + 1 end }
        clock.pending = { fn = fn, handle = handle }
        return handle
      end,
    },
    eventtap = {
      event = { types = {}, properties = {} },
      -- The machine's own two beats, fixed here so the case reads the same on any keyboard.
      keyRepeatDelay = function() return 0.5 end,
      keyRepeatInterval = function() return 0.1 end,
    },
  }
  clock.fire = function()
    local tick = clock.pending
    clock.pending = nil
    if tick then tick.fn() end
  end

  local env = {
    hs = fakeHs, math = math, table = table, string = string,
    type = type, pairs = pairs, ipairs = ipairs, tostring = tostring, print = print,
  }
  local chunk, err = loadfile(modulePath, "t", env)
  if not chunk then
    error("could not load Olm.spoon/lib/chordkey.lua, " .. tostring(err))
  end
  return chunk(), clock
end

-- The first repeat waits the long delay and every one after it the interval, which is the
-- shape a held key has always had on this platform. The long first beat is what keeps one
-- deliberate press from becoming three, and the steady rate after it is the whole of the rest.
do
  local engine, clock = freshModule()
  engine:init()
  local key = { active = true, repeatTiming = { delay = 0.5, interval = 0.1 } }
  local fires, depths = 0, {}

  engine:_startRepeat(key, 4, function(depth)
    fires = fires + 1
    depths[#depths + 1] = depth
  end)
  for _ = 1, 6 do clock.fire() end

  local waits = clock.waits
  check("the first repeat waits the long delay until repeat",
    near(waits[1], 0.5), "got " .. tostring(waits[1]))
  check("every repeat after it waits the interval",
    near(waits[2], 0.1) and near(waits[3], 0.1) and near(waits[6], 0.1),
    "got " .. tostring(waits[2]) .. ", " .. tostring(waits[3]) .. ", " .. tostring(waits[6]))
  check("one fire per tick and no fire before the first wait",
    fires == 6, "fired " .. tostring(fires) .. " times over six ticks")
  check("each repeat is told how deep into the hold it is, counting the press as zero",
    depths[1] == 1 and depths[2] == 2 and depths[6] == 6,
    "got " .. tostring(depths[1]) .. ", " .. tostring(depths[2]) .. ", " .. tostring(depths[6]))
end

-- Timing that names neither beat takes both off the machine, which is what the shipped
-- default does, so a person who moves either slider in System Settings moves these keys.
do
  local engine, clock = freshModule()
  engine:init()
  local key = { active = true, repeatTiming = {} }
  engine:_startRepeat(key, 4, function() end)
  for _ = 1, 3 do clock.fire() end
  check("the first wait is the machine's own delay until repeat",
    near(clock.waits[1], 0.5), "got " .. tostring(clock.waits[1]))
  check("the waits after it are the machine's own repeat interval",
    near(clock.waits[2], 0.1) and near(clock.waits[3], 0.1),
    "got " .. tostring(clock.waits[2]) .. ", " .. tostring(clock.waits[3]))
end

-- However long a key is held the rate never changes, which is the point of it. A rate that
-- kept shifting under a held finger would make where a window lands depend on the exact
-- moment it was released.
do
  local engine, clock = freshModule()
  engine:init()
  local timing = { delay = 0.5, interval = 0.1 }
  local key = { active = true, repeatTiming = timing }
  engine:_startRepeat(key, 4, function() end)
  for _ = 1, 60 do clock.fire() end

  local waits = clock.waits
  local drifted = false
  for i = 2, #waits do
    if not near(waits[i], timing.interval) then drifted = true end
  end
  check("sixty repeats and not one of them waits anything but the interval", not drifted)
  check("the very last wait of a long hold is still the interval",
    near(waits[#waits], timing.interval), "got " .. tostring(waits[#waits]))
end

-- Stopping is what a released key does, so a tick already in flight when it lands must find
-- the repeat gone rather than fire once more into an action nobody is asking for.
do
  local engine, clock = freshModule()
  engine:init()
  local key = { active = true, repeatTiming = { delay = 0.2, interval = 0.1 } }
  local fires = 0
  engine:_startRepeat(key, 4, function() fires = fires + 1 end)
  clock.fire()
  local before = fires

  engine:_stopRepeat(key)
  check("stopping clears which key was repeating", key.repeatCode == nil)
  check("stopping releases the pending timer", key.repeatTimer == nil)
  check("stopping stops the timer it was holding", clock.stopped >= 1)

  clock.fire()
  check("a tick that lands after the stop does not fire the handler",
    fires == before, "fired " .. tostring(fires) .. " against " .. tostring(before))
end

-- The leader coming up sets active false, and a tick in flight has to read that too, since
-- the release cannot reach into a timer that was already scheduled.
do
  local engine, clock = freshModule()
  engine:init()
  local key = { active = true, repeatTiming = { delay = 0.2, interval = 0.1 } }
  local fires = 0
  engine:_startRepeat(key, 4, function() fires = fires + 1 end)
  key.active = false
  clock.fire()
  check("a tick that lands after the leader was released does not fire", fires == 0,
    "fired " .. tostring(fires) .. " times")
end

-- A second bound key under one held leader takes the repeat over, so the first key's own
-- release must not stop what the second one is now running.
do
  local engine, clock = freshModule()
  engine:init()
  local key = { active = true, repeatTiming = { delay = 0.2, interval = 0.1 } }
  engine:_startRepeat(key, 4, function() end)
  engine:_startRepeat(key, 7, function() end)
  check("the later key owns the repeat", key.repeatCode == 7,
    "owner is " .. tostring(key.repeatCode))
  check("taking over stops the earlier chain", clock.stopped >= 1)
end

-- The mode a key repeats in is the caller's to set, and the default has to stay the OS
-- autorepeat, since every list nav key already registered relies on it.
do
  local engine = freshModule()
  engine:init()
  engine:addKey(100, {})
  engine:addKey(101, { repeatMode = "driven" })
  check("a key registered with no mode inherits the system autorepeat",
    engine._keys[100].repeatMode == "system",
    "got " .. tostring(engine._keys[100].repeatMode))
  check("a key may override the mode to driven",
    engine._keys[101].repeatMode == "driven",
    "got " .. tostring(engine._keys[101].repeatMode))

  engine:configure({ repeatMode = "driven", repeatTiming = { delay = 1, interval = 1 } })
  engine:addKey(102, {})
  check("configure moves the default every later key inherits",
    engine._keys[102].repeatMode == "driven",
    "got " .. tostring(engine._keys[102].repeatMode))
  check("configure moves the default timing too",
    engine._keys[102].repeatTiming.delay == 1)
  check("a key registered before configure keeps what it was given",
    engine._keys[101].repeatMode == "driven")
end
