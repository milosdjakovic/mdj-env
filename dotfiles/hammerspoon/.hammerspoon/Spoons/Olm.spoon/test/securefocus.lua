-- The secure focus hold, in plain Lua over a fake hs.
--
-- Pins that hold answers nil and builds nothing when secure input is off, that when it is on a
-- chooser with no rows is shown and its window moved off screen, and that the release hides and
-- deletes it and activates the remembered application, once.
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

local previous = { activate = function() activated = activated + 1 end }
local window = {
  application = function() return { name = function() return "Hammerspoon" end } end,
  frame = function() return { x = 10, y = 20, w = 300, h = 200 } end,
  setFrame = function(_, f, d) moved = { f = f, d = d } end,
}

hs = {
  eventtap = { isSecureInputEnabled = function() return secure end },
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

if failed then os.exit(1) end
