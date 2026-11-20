-- Bringing an app forward, lib/appfocus.lua, and the app toggler's runs over it, in plain Lua, step
-- 6.2 of docs/PLAN-STANDALONE.md and docs/DESIGN-APP-APPS.md. It pins the one decision acting and
-- the shadow's plan share, focus or cycle and show or hide, and the seam: a press handed to Olm.app
-- when the forwarder takes it, run in Lua when it does not, a raise in the forwarder run in Lua, and
-- a placement written as a function never handed over.
--
-- It needs no Hammerspoon and no lock, a fake hs standing in for the apps.
--
-- Run it.
--   lua test/appfocus.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")

local failures, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %s, wanted %s, got %s", what, tostring(want), tostring(got)))
  end
end

-- The world: apps by bundle id, each with windows, which one is in front and which window has focus.
local world, did = {}, {}
local function window(id, opts)
  opts = opts or {}
  return { _id = id, id = function(w) return w._id end,
    isStandard = function() return opts.standard ~= false end,
    isMinimized = function() return opts.minimized == true end,
    focus = function(w) did[#did + 1] = "focus " .. w._id end }
end
local function app(bid, windows, front)
  world.apps[bid] = { _bid = bid, _windows = windows, _front = front,
    isFrontmost = function(a) return a._front end,
    allWindows = function(a) return a._windows end,
    hide = function(a) did[#did + 1] = "hide " .. a._bid end }
end
local function reset()
  world = { apps = {}, focused = nil }
  did = {}
end
reset()

_G.hs = {
  logger = { new = function() return { w = function() end, i = function() end } end },
  application = {
    get = function(bid) return world.apps[bid] end,
    launchOrFocusByBundleID = function(bid) did[#did + 1] = "launch " .. bid end,
  },
  window = { focusedWindow = function() return world.focused end },
  timer = { doAfter = function() return { stop = function() end } end },
}

local appfocus = assert(loadfile(here .. "../lib/appfocus.lua"))()

-- The decision, as the plan answers it.
reset()
eq(appfocus.plan("a.b", false).outcome, "launched", "an app not running launches")
app("a.b", {}, true)
eq(appfocus.plan("a.b", false).outcome, "focused", "an app in front with no window is focused")
local w1, w2, w3 = window(30), window(10), window(20, { minimized = true })
app("a.b", { w1, w2, w3 }, false)
eq(appfocus.plan("a.b", false).outcome, "focused", "an app behind is focused")
world.apps["a.b"]._front = true
world.focused = w2
local p = appfocus.plan("a.b", false)
eq(p.outcome, "cycled", "an app in front with windows cycles")
eq(p.window, 30, "to the next window by id, the minimized one left out")
world.focused = w1
eq(appfocus.plan("a.b", false).window, 10, "and wraps to the first")
world.focused = nil
eq(appfocus.plan("a.b", false).window, 10, "and with no focused window starts at the first")
eq(appfocus.plan("a.b", true).outcome, "hidden", "the show and hide form hides an app in front with a window")
world.apps["a.b"]._front = false
eq(appfocus.plan("a.b", true).outcome, "focused", "and focuses one behind")
eq(#did, 0, "the plan changes nothing")

-- Acting, with no forwarder.
world.apps["a.b"]._front = true
world.focused = w2
eq(appfocus.focusOrCycle("a.b"), "cycled", "focus or cycle answers its outcome")
eq(did[1], "focus 30", "and focuses the window the plan named")
did = {}
eq(appfocus.toggle("a.b"), "hidden", "toggle hides an app in front")
eq(did[1], "hide a.b", "through the app")
did = {}
eq(appfocus.toggle("x.y"), "launched", "toggle launches one not running")
eq(did[1], "launch x.y", "through launch or focus")

-- The seam.
local sent = {}
appfocus.forwardTo(function(press) sent[#sent + 1] = press; return true end)
did = {}
eq(appfocus.focusOrCycle("a.b"), "app", "a press the app took answers app")
eq(#did, 0, "and Lua does nothing")
eq(sent[1].id, "launcher", "a press with no id is the launcher's")
eq(sent[1].hides, false, "focus or cycle never hides")
appfocus.forwardTo(function() return false end)
eq(appfocus.focusOrCycle("a.b"), "cycled", "a press the app declined runs in Lua")
appfocus.forwardTo(function() error("gone") end)
eq(appfocus.focusOrCycle("a.b"), "cycled", "a raising forwarder is a press Lua runs")
appfocus.forwardTo(nil)
eq(appfocus.toApp({ bundle = "a.b" }), false, "with no forwarder nothing is handed over")

-- The toggler's runs.
local toggler = assert(loadfile(here .. "../plugins/apptoggler/init.lua"))()
sent = {}
appfocus.forwardTo(function(press) sent[#sent + 1] = press; return true end)
toggler:configure({ apps = { Ghostty = "g.g", Safari = "s.s", Fn = "f.f" }, appFocus = appfocus,
  styles = { popup = { hides = true, placement = { width = 100, height = 50 } } },
  toggles = { { app = "Ghostty", style = "popup" },
    { app = "Fn", placement = function(box) return box end } } })
local runs = {}
for _, a in ipairs(toggler:actions()) do runs[a.name] = a.run end
did = {}
runs.Ghostty()
eq(sent[1].id, "apptoggler.Ghostty", "a styled press is handed over under its action")
eq(sent[1].hides, true, "with its hides")
eq(sent[1].placement and sent[1].placement.width, 100, "and its placement table")
runs.Safari()
eq(sent[2].id, "apptoggler.Safari", "a plain press is handed over under its action")
eq(sent[2].hides, false, "as focus or cycle")
reset()
app("f.f", {}, false)
runs.Fn()
eq(#sent, 2, "a placement written as a function is never handed over")
eq(did[1], "launch f.f", "and runs in Lua")

print(string.format("appfocus: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
