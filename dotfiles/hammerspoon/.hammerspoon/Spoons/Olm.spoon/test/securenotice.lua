-- The secure input notice, in plain Lua over a fake hs.
--
-- Pins that the holder is the first session's secure input pid naming an application this session
-- can see, that a held leader's key is claimed only while secure input is on, that a press names
-- the holder through ioreg and falls back to a message naming none, and that stop deletes it all.
--
-- Run it.
--   lua test/securenotice.lua

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

local secure, hotkeys, timers, tasks = false, {}, {}, {}
local apps = { [53106] = "Google Chrome" }

hs = {
  eventtap = { isSecureInputEnabled = function() return secure end },
  application = {
    applicationForPID = function(pid)
      local name = apps[pid]
      return name and { name = function() return name end } or nil
    end,
  },
  hotkey = {
    new = function(mods, key, pressed)
      local k = { key = key, pressed = pressed, enabled = false, deleted = false }
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
  task = {
    new = function(path, done, stream, args)
      local t = { path = path, done = done, stream = stream, args = args }
      function t:start() return true end
      tasks[#tasks + 1] = t
      return t
    end,
  },
}

local lib = dofile(here .. "../lib/securenotice.lua")

local IOREG = '"IOConsoleUsers" = ({"kCGSSessionUserIDKey"=501,"kCGSSessionSecureInputPID"=999},'
  .. '{"kCGSSessionUserIDKey"=502,"kCGSSessionSecureInputPID"=53106})'
check("the holder is the session pid this session can see", lib.holderIn(IOREG), "Google Chrome")
check("no visible pid names no holder", lib.holderIn('"kCGSSessionSecureInputPID"=999'), nil)
check("no output names no holder", lib.holderIn(nil), nil)

local messages = {}
lib.start({ keys = { { code = 79, name = "Hyper" } }, ioreg = "/usr/sbin/ioreg",
  notify = function(t) messages[#messages + 1] = t end })
check("a held leader's key is claimed", #hotkeys, 1)
check("claimed by its function key", hotkeys[1].key, 79)
check("not live while secure input is off", hotkeys[1].enabled, false)

secure = true
timers[1].fn()
check("live while secure input is on", hotkeys[1].enabled, true)

hotkeys[1].pressed()
check("a press asks ioreg", tasks[1] and tasks[1].path, "/usr/sbin/ioreg")
check("the output is read as it streams", tasks[1].stream(nil, IOREG:sub(1, 40)), true)
tasks[1].done(0, IOREG:sub(41))
check("the message names the holder and the leader", messages[1],
  "Google Chrome holds secure input, so Hyper is not heard until its password field loses focus")

secure = false
timers[1].fn()
check("off again once secure input is", hotkeys[1].enabled, false)

lib.start({ keys = { { code = 79, name = "Hyper" } }, notify = function(t) messages[#messages + 1] = t end })
check("a second start deletes what the first armed", hotkeys[1].deleted, true)
check("and stops its poll", timers[1].stopped, true)
hotkeys[2].pressed()
check("with no ioreg the message names no holder", messages[2],
  "Secure input is on, so Hyper is not heard until the password field loses focus")

lib.stop()
check("stop deletes the key", hotkeys[2].deleted, true)

lib.start({ keys = {}, notify = function() end })
check("no held leader arms no poll", #timers, 2)

if failed then os.exit(1) end
