-- Unit case for the BrowserTabs settings level, which has no level beneath it. The runner
-- reaches this file with a dofile call carrying an absolute path, so this file locates itself
-- through debug.getinfo and loads the chooser by path with loadfile, never require.
--
-- The promises under test are three. Choosing a browser row switches it where it stands, so
-- the intercept answers "stay" and the state flips. A permission row appears under a switched
-- on browser only when the permission asks something, names the browser and filters on its name
-- alone. The Settings row leads the tab list only when the query is a whole settings word, and
-- trails it on an empty query and on the start of one. Everything is
-- read through the module's own select, rows and intercept over a fake api, no test hook.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local chooserPath = caseDir .. "/../../Spoons/Olm.spoon/plugins/browsertabs/chooser.lua"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local chunk, err = loadfile(chooserPath)
if not chunk then error("could not load the browsertabs chooser, " .. tostring(err)) end
local M = chunk()

local states = { granted = "granted", notDetermined = "notDetermined", denied = "denied",
  notRunning = "notRunning", noTarget = "noTarget", unknown = "unknown" }
local enabled = { ["com.test.a"] = false, ["com.test.b"] = true, ["com.test.c"] = true }
local perm = { ["com.test.a"] = states.granted, ["com.test.b"] = states.notDetermined,
  ["com.test.c"] = states.granted }
local reloads = 0

local api = {
  states = states,
  notPermitted = "not permitted",
  status = function()
    return {
      { bundleID = "com.test.a", name = "Alpha", installed = true, enabled = enabled["com.test.a"], running = true },
      { bundleID = "com.test.b", name = "Bravo", installed = true, enabled = enabled["com.test.b"], running = true },
      { bundleID = "com.test.c", name = "Charlie", installed = false, enabled = false, running = false },
    }
  end,
  isEnabled = function(id) return enabled[id] end,
  setEnabled = function(id, on) enabled[id] = on end,
  permissionStatus = function(id, cb) cb(perm[id]) end,
  permissionRequest = function() end,
  openPermissionSettings = function() end,
  listTabs = function(cb) reloads = reloads + 1 cb({}, {}) end,
  order = function(list) return list end,
  recencyRank = function() return nil end,
}
M:configure({ api = api, matcher = false })

local child = M.select({ nav = true, to = "settings" })
check("choosing the Settings row answers a level", type(child) == "table")
check("the settings level filters like every other list", child.matcher == nil)

local rows = child.rows()
local function find(title)
  for i, r in ipairs(rows) do if r.title == title then return r, i end end
end

check("Back leads and filters on nothing", rows[1].title == "Back" and rows[1].filterText == "")
local alpha, ai = find("Alpha")
check("a browser row filters on its name", alpha ~= nil and alpha.filterText == "Alpha")
check("a switched off browser wears the off marker", alpha and alpha.icon == "off")
local bravo, bi = find("Bravo")
check("a switched on browser wears the on marker", bravo and bravo.icon == "active")
local charlie = find("Charlie")
check("an uninstalled browser is a disabled row saying so",
  charlie ~= nil and charlie.enabled == false and charlie.subTitle == "not installed")

-- The permission read starts when the level is presented, and lands through a stub that
-- answers at once.
child.onPresent()
rows = child.rows()
bravo, bi = find("Bravo")
local ask = rows[bi + 1]
check("a permission that can be asked adds one row under its browser, naming it",
  ask ~= nil and ask.title == "Ask Bravo for permission")
check("a permission row filters on its browser's name alone, so it travels with it",
  ask ~= nil and ask.filterText == "Bravo", ask and ask.filterText)
check("a permission row carries a key of its own", ask ~= nil and ask.item.key == "com.test.b.permission"
  and bravo.item.key == "com.test.b")
check("a browser whose permission reads fine adds no row", find("Alpha") and rows[select(2, find("Alpha")) + 1].title == "Bravo")

local result = child.intercept(alpha.item)
check("toggling a browser from the settings level answers stay", result == "stay")
check("toggling a browser flips its state", enabled["com.test.a"] == true)
check("toggling reloads the tab list", reloads >= 1)
rows = child.rows()
alpha = find("Alpha")
check("the list repaints with the new state", alpha and alpha.icon == "active")

result = child.intercept(bravo.item)
check("toggling a second time flips it back", result == "stay" and enabled["com.test.b"] == false)
rows = child.rows()
_, bi = find("Bravo")
check("a switched off browser carries no permission row", rows[bi + 1] == nil or rows[bi + 1].title ~= "Ask Bravo for permission")

-- The tab list, with one tab so the empty reasons are not what is shown.
api.listTabs = function(cb)
  cb({ { title = "Settings page", url = "https://example.com/a", browser = "Alpha", bundleID = "com.test.a" },
    { title = "Discord", url = "https://discord.com/app", browser = "Alpha", bundleID = "com.test.a" } }, {})
end
M.reload()
local list = M.rows("")
check("with an empty query Settings is the last row", list[#list].title == "Settings")
list = M.rows("settings")
check("typing a whole settings word puts Settings first", list[1].title == "Settings" and list[2] ~= nil)
list = M.rows("  Browsers ")
check("a whole word leads whatever its case and spaces", list[1].title == "Settings")
list = M.rows("di")
check("the start of a settings word that is also a tab's name leaves the tab first",
  list[1].title == "Discord" and list[#list].title == "Settings", list[1].title)
list = M.rows("sett")
check("the start of a settings word keeps Settings in reach after the tabs",
  list[1].title == "Settings page" and list[#list].title == "Settings", list[1].title)
list = M.rows("disc")
check("a query reaching for no settings word shows no Settings row", list[#list].title ~= "Settings")
