-- Unit case for Return on a row of Olm.app's launcher, Launcher:bridgeChoose, step 3.6 of
-- docs/PLAN-STANDALONE.md. A row that becomes another list in the Lua launcher does the same in the
-- app's. A hosted tool's row answers present, a row that seeds a word answers setQuery, a scope row
-- that acts runs its act and answers rows held, and a row whose list the app does not host answers
-- unserved. Any other row answers hide and hands back its run.
--
-- A fresh copy of the launcher is loaded straight out of this checkout and its own method is called
-- on a table standing in for the instance, whose promote, memory and run are recorders, so nothing
-- here reaches the running config or the remembered picks. Under a plain lua interpreter a small
-- stub stands in for Hammerspoon.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local spoon = caseDir .. "/../../Spoons/Olm.spoon/"

if hs == nil then
  hs = {
    settings = { get = function() return nil end, set = function() end },
    processInfo = { bundleID = "org.hammerspoon.Hammerspoon" },
    logger = { new = function() return setmetatable({}, { __index = function() return function() end end }) end },
    timer = { doAfter = function(_, fn) return { fire = function() fn() end, stop = function() end } end },
    image = { imageFromAppBundle = function() return nil end },
    application = {
      runningApplications = function() return {} end,
      pathForBundleID = function() return "" end,
      nameForBundleID = function() return nil end,
    },
    hotkey = { bind = function() end },
  }
end

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  elseif detail then
    print("FAIL " .. description .. ", " .. detail)
  else
    print("FAIL " .. description)
  end
end

local function eq(description, got, want)
  check(description, got == want, "wanted " .. tostring(want) .. ", got " .. tostring(got))
end

local chunk = assert(loadfile(spoon .. "host/launcher/init.lua"))
local launcher = chunk()

local did = {}
local function note(text) did[#did + 1] = text end
local acted = 0
local answers = {
  vpn = { present = { name = "vpn" } },
  clipboard = { present = { name = "clipboard" } },
  aliasDirectory = { seed = "? " },
  dockHiding = { act = function() acted = acted + 1 end },
}
local fake = setmetatable({
  _actions = {
    rowIntercept = function(item) return answers[item.name] and function() end or nil end,
    rowInPlace = function(item) return answers[item.name] end,
  },
  _promote = function(_, key) note("promote " .. tostring(key)) end,
  _noteAssociation = function(_, item) note("remember " .. tostring(item.name)) end,
  _runItem = function(_, item) note("run " .. tostring(item.name)) end,
}, { __index = launcher })

local hosted = function(p) return p.name == "vpn" end
local function choose(item)
  did = {}
  return launcher.bridgeChoose(fake, item, "q", hosted)
end

local effects = choose({ kind = "special", name = "vpn" })
check("a hosted tool's row answers present", effects[1] and effects[1].present and effects[1].present.name == "vpn")
check("a hosted tool's row is promoted and remembered", did[1] and did[1]:match("^promote") and did[2] == "remember vpn")

effects = choose({ kind = "special", name = "clipboard" })
eq("a tool the app does not host answers unserved", effects[1] and effects[1].unserved and effects[1].unserved.name, "clipboard")
eq("an unserved row is not promoted", #did, 0)

effects = choose({ kind = "special", name = "aliasDirectory" })
eq("a row that seeds a word answers setQuery with it", effects[1] and effects[1].setQuery and effects[1].setQuery.query, "? ")
check("a row that seeds is promoted", did[1] and did[1]:match("^promote"))

effects = choose({ kind = "scope", name = "dockHiding" })
eq("a scope row that acts runs its act once", acted, 1)
eq("and answers its rows again with the highlight held", effects[1] and effects[1].rows and effects[1].rows.hold, true)

local run
effects, run = choose({ kind = "app", name = "Safari" })
check("any other row answers hide", effects[1] and effects[1].hide ~= nil)
check("and hands back its run, not yet called", type(run) == "function" and not (did[#did] or ""):match("^run"))
run()
eq("its run runs the row", did[#did], "run Safari")

-- Without rowInPlace the presentation alone is asked, as before step 3.6.
fake._actions.rowInPlace = nil
fake._actions.rowPresentation = function(item) local a = answers[item.name]; return a and a.present end
effects = choose({ kind = "special", name = "vpn" })
check("with no rowInPlace a hosted row still answers present", effects[1] and effects[1].present ~= nil)
effects = choose({ kind = "special", name = "aliasDirectory" })
check("with no rowInPlace a seeding row answers unserved", effects[1] and effects[1].unserved ~= nil)
