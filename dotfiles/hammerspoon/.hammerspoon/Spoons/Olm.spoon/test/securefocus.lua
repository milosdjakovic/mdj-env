-- The secure focus hold, in plain Lua over a fake hs.
--
-- Pins that hold answers nil and builds nothing when secure input is off, that when it is on a
-- chooser with no rows is shown and its window moved off screen, and that the release hides and
-- deletes it and activates the remembered application, once. And that while secure input stays on
-- the relay hands typed text and the claimed keys to the sink, Backspace only on empty text, goes
-- quiet the moment secure input is off, and is torn down by the release, that a person's own list
-- keys are relayed beside the fixed set and a key both name is claimed once, and that the mirror
-- writes the list's own text into the chooser.
--
-- Run it.
--   lua test/securefocus.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local failed = false

local function check(name, got, want)
  if got ~= want then
    failed = true
    print(("FAIL %s, wanted %s, got %s"):format(name, tostring(want), tostring(got)))
  else
    print(("ok   %s"):format(name))
  end
end

local log, secure, moved, activated = {}, false, nil, 0
local hotkeys, timers, onQuery, queried = {}, {}, nil, {}

local previous = { activate = function() activated = activated + 1 end }
local window = {
  application = function() return { name = function() return "Hammerspoon" end } end,
  frame = function() return { x = 10, y = 20, w = 300, h = 200 } end,
  setFrame = function(_, f, d) moved = { f = f, d = d } end,
}

hs = {
  keycodes = { map = { ["return"] = 36, j = 38 } },
  axuielement = { windowElement = function() return nil end },
  eventtap = {
    isSecureInputEnabled = function() return secure end,
    event = { newKeyEvent = function(mods, key) return { mods = mods, key = key } end },
  },
  hotkey = {
    new = function(mods, key, pressed, _, repeated)
      local k = { mods = table.concat(mods, "+"), key = key, pressed = pressed, repeated = repeated,
        enabled = false, deleted = false }
      function k:enable() self.enabled = true end
      function k:disable() self.enabled = false end
      function k:delete() self.deleted = true; self.enabled = false end
      hotkeys[#hotkeys + 1] = k
      return k
    end,
  },
  timer = {
    doEvery = function(_, fn)
      local t = { fn = fn, stopped = false }
      function t:stop() self.stopped = true end
      timers[#timers + 1] = t
      return t
    end,
  },
  application = { frontmostApplication = function() return previous end },
  window = { focusedWindow = function() return window end },
  chooser = {
    new = function()
      log[#log + 1] = "new"
      return {
        choices = function(_, c) log[#log + 1] = "choices" .. #c end,
        rows = function(_, n) log[#log + 1] = "rows" .. n end,
        show = function() log[#log + 1] = "show" end,
        hide = function() log[#log + 1] = "hide" end,
        delete = function() log[#log + 1] = "delete" end,
        queryChangedCallback = function(_, fn) onQuery = fn end,
        query = function(_, t) queried[#queried + 1] = t; if onQuery then onQuery(t) end end,
      }
    end,
  },
}

local lib = dofile(here .. "../lib/securefocus.lua")

check("off answers nil", lib.hold(), nil)
check("off builds no chooser", #log, 0)

secure = true
local release = lib.hold()
check("on answers a release function", type(release), "function")
check("on builds, empties and shows", table.concat(log, ","), "new,choices0,rows0,show")
check("window moved off screen", moved and moved.f.y, -10000)
check("window keeps x and size", moved and moved.f.x + moved.f.w + moved.f.h, 510)
check("window moved with no animation", moved and moved.d, 0)
check("nothing activated before release", activated, 0)

release()
check("release hides and deletes", table.concat(log, ","), "new,choices0,rows0,show,hide,delete")
check("release activates the remembered app", activated, 1)

release()
check("second release hides nothing more", #log, 6)
check("second release activates nothing more", activated, 1)

-- The relay, over Chrome, where secure input stays on with the chooser key.
local function hotkey(mods, key)
  for _, k in ipairs(hotkeys) do if k.mods == mods and k.key == key and not k.deleted then return k end end
end
local function enabledCount()
  local n = 0
  for _, k in ipairs(hotkeys) do if k.enabled then n = n + 1 end end
  return n
end

hotkeys, timers, log = {}, {}, {}
local keys, texts = {}, {}
local sink = {
  key = function(ev) keys[#keys + 1] = table.concat(ev.mods, "+") .. ":" .. ev.key end,
  text = function(t) texts[#texts + 1] = t end,
}
secure = true
release = lib.hold(sink)
check("relay polls secure input", #timers, 1)
check("relay claims the list keys and Backspace on empty text", enabledCount(), 19)
hotkey("", "down").pressed()
hotkey("", "down").repeated()
hotkey("", "escape").pressed()
hotkey("cmd", "return").pressed()
hotkey("", "delete").pressed()
check("claimed keys reach the sink as key events", table.concat(keys, ","), ":down,:down,:escape,cmd:return,:delete")
check("an arrow repeats and Return does not", hotkey("", "return").repeated, nil)

onQuery("ab")
check("typed text reaches the sink", table.concat(texts, ","), "ab")
check("Backspace is the chooser's own while there is text", hotkey("", "delete").enabled, false)
onQuery("")
check("Backspace is claimed again on empty text", hotkey("", "delete").enabled, true)

secure = false
timers[1].fn()
check("secure input off claims nothing", enabledCount(), 0)
onQuery("x")
check("text typed while the tap hears is not relayed", #texts, 2)

secure = true
timers[1].fn()
check("secure input back on claims again, Backspace aside", enabledCount(), 18)

-- The mirror, text the list wrote itself.
local _
hotkeys, timers, log, texts = {}, {}, {}, {}
secure = true
release, mirror = lib.hold(sink)
check("the hold answers a mirror", type(mirror), "function")
mirror("v ")
check("the mirror writes the chooser", table.concat(queried, ","), "v ")
check("the mirror is not relayed back", #texts, 0)
check("Backspace is the chooser's own after a mirror", hotkey("", "delete").enabled, false)
mirror("v ")
check("an unchanged text is not written again", #queried, 1)
release()
mirror("x")
check("a released hold mirrors nothing", #queried, 1)

-- A person's own list keys, one new and one the fixed set already claims.
hotkeys, timers = {}, {}
release = lib.hold(sink, { keys = { { { "ctrl" }, 38 }, { { "cmd" }, 36 } } })
check("a person's list key is relayed", hotkey("ctrl", 38) ~= nil, true)
check("a key the fixed set claims is claimed once", hotkey("cmd", 36), nil)
check("every relayed key enabled with the person's added", enabledCount(), 20)
release()
_ = nil

hotkeys, timers = {}, {}
secure = true
release = lib.hold(sink)
release()
local deleted = 0
for _, k in ipairs(hotkeys) do if k.deleted then deleted = deleted + 1 end end
check("release deletes every hotkey", deleted, #hotkeys)
check("release stops the poll", timers[1].stopped, true)

if failed then os.exit(1) end
