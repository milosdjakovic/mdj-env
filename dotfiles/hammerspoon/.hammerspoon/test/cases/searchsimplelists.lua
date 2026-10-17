-- Unit case for the simple lists that moved onto the shared search in phase two of
-- docs/PLAN-UNIFIED-SEARCH.md, Workspaces, DisplayProfiles and TmuxSessions. Each chooser is
-- loaded by path over a fake api and its rows are ranked through the real rank.lua and
-- match.lua, since what is under test is that the supplier hands back every row and that the
-- engine, not the supplier, decides what a query keeps. The runner reaches this file with a
-- dofile call carrying an absolute path, so it locates itself through debug.getinfo and
-- loads everything by path with loadfile, never require.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local olm = caseDir .. "/../../Spoons/Olm.spoon/"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  elseif detail then
    print("FAIL " .. description .. ", " .. detail)
  else
    print("FAIL " .. description)
  end
end

local function load(path)
  local chunk, err = loadfile(olm .. path)
  if not chunk then error("could not load " .. path .. ", " .. tostring(err)) end
  return chunk()
end

local rank = load("lib/chooser/rank.lua")
local fuzzy = load("lib/chooser/match.lua").fuzzy

local function titles(list)
  local out = {}
  for i, r in ipairs(list) do out[i] = r.title end
  return table.concat(out, ",")
end

local function has(list, title)
  for _, r in ipairs(list) do if r.title == title then return true end end
  return false
end

local function ranked(rows, query) return rank.apply(rows, query, fuzzy) end

--------------------------------------------------------------------------------
-- Workspaces
--------------------------------------------------------------------------------

do
  local layouts = {
    { id = "a", name = "Desk", available = true, apps = 4, excluded = 0, topology = "two displays", taken = "today" },
    { id = "b", name = "Travel", available = false, apps = 2, excluded = 1, topology = "one display",
      reason = "needs two displays", taken = "today" },
  }
  local api = {
    persists = function() return true end,
    here = function() return "this machine" end,
    list = function() return layouts end,
    get = function(id) for _, l in ipairs(layouts) do if l.id == id then return l end end end,
    apps = function() return { { name = "Notes", bundle = "com.test.notes", windows = 1, displays = "main" } } end,
    exists = function() return false end,
  }
  local M = load("plugins/workspaces/chooser.lua")
  M:configure({ api = api })

  local rows = M.rows("")
  check("workspaces top level leads with New snapshot, pinned", rows[1].title == "New snapshot" and rows[1].pinned == true)
  check("workspaces top level returns every layout without filtering", #M.rows("desk") == 3)
  local kept = ranked(M.rows("desk"), "desk")
  check("a query keeps New snapshot and the layout that matches", titles(kept) == "New snapshot,Desk", titles(kept))
  kept = ranked(M.rows("zzzq"), "zzzq")
  check("a query matching nothing leaves New snapshot, never an empty list",
    titles(kept) == "New snapshot", titles(kept))
  check("there is no row for a query that matches nothing", not has(M.rows("zzzq"), "No layout matches"))

  local scope = M.scopeRows("desk")
  check("the scope returns every layout for the engine to filter", #scope == 2)

  local layout = M.select({ nav = "layout", id = "a" })
  check("the layout level inherits the shared search", layout.matcher == nil)
  local lrows = layout.rows()
  check("the layout level pins Back", lrows[1].title == "Back" and lrows[1].pinned == true)
  local apps = M.select({ nav = "layout", id = "a" }).onSelect({ nav = "apps" })
  check("the apps level inherits the shared search and reads as one", apps.matcher == nil
    and apps.placeholder == "Search apps in this layout")
  check("the apps level pins Back", apps.rows()[1].pinned == true)
  check("the new snapshot name level keeps matcher false", M.select({ nav = "new" }).matcher == false)
  check("the rename level keeps matcher false", layout.onSelect({ nav = "rename" }).matcher == false)
  check("the delete confirm keeps matcher false", layout.onSelect({ nav = "delete" }).matcher == false)
  local app = apps.onSelect({ nav = "app", bundle = "b", name = "Notes", excluded = false })
  check("the app level keeps matcher false", app.matcher == false)
end

--------------------------------------------------------------------------------
-- DisplayProfiles
--------------------------------------------------------------------------------

do
  local active = nil
  local profiles = {
    { name = "Desk", command = "desk", editable = true },
    { name = "Laptop", command = "laptop", editable = true },
  }
  local api = {
    active = function() return active end,
    list = function() return profiles end,
    displays = function() return { { id = "1", res = "1920x1080", hz = 60, origin = "0,0", main = true } } end,
    exists = function() return false end,
  }
  local M = load("plugins/displayprofiles/chooser.lua")
  M:configure({ api = api })

  local rows = M.rows("")
  check("display profiles leads with Capture current arrangement, pinned, when nothing is active",
    rows[1].title == "Capture current arrangement" and rows[1].pinned == true)
  check("the top level returns every profile without filtering", #M.rows("desk") == 3)
  local kept = ranked(M.rows("lap"), "lap")
  check("a query keeps Capture and the profile that matches", titles(kept) == "Capture current arrangement,Laptop",
    titles(kept))
  active = "Desk"
  rows = M.rows("")
  check("with a profile active there is no capture row", not has(rows, "Capture current arrangement") and #rows == 2)

  local profile = M.select({ nav = true, to = "profile", name = "Desk" })
  check("the profile screen inherits the shared search", profile.matcher == nil)
  check("the profile screen pins Back", profile.rows()[1].title == "Back" and profile.rows()[1].pinned == true)
  check("the rename screen keeps matcher false", profile.onSelect({ nav = true, to = "rename" }).matcher == false)
  check("the delete confirm keeps matcher false", profile.onSelect({ nav = true, to = "delete" }).matcher == false)
  check("the capture screen keeps matcher false", M.select({ nav = true, to = "capture" }).matcher == false)
end

--------------------------------------------------------------------------------
-- TmuxSessions
--------------------------------------------------------------------------------

do
  local windows = {
    { name = "zsh", session = "vicert", target = "vicert:1", active = true, sessionAttached = true },
    { name = "zsh", session = "notes", target = "notes:1", active = false, sessionAttached = false },
    { name = "editor", session = "vicert", target = "vicert:2", active = false, sessionAttached = true },
  }
  local api = {}
  function api:windows() return windows end
  function api:providers() return { { name = "Terminal", available = function() return true end } } end
  function api:currentProviderName() return "Terminal" end
  local M = load("plugins/tmuxsessions/chooser.lua")
  M.configure({ api = api })

  local rows = M.rows("")
  check("a window row shows its name as the title and its session as the subtitle",
    rows[1].title == "zsh" and rows[1].subTitle == "vicert")
  check("the Settings door is the last row and not pinned", rows[#rows].title == "Settings"
    and rows[#rows].pinned == nil)
  check("the supplier returns every window with a query typed", #M.rows("vic zsh") == #rows)
  local kept = ranked(M.rows("vic zsh"), "vic zsh")
  check("two words find the window inside its session", kept[1] and kept[1].item.go == "vicert:1"
    and not has(kept, "editor"), titles(kept))
  kept = ranked(M.rows("settings"), "settings")
  check("typing settings scores the Settings door in", has(kept, "Settings"), titles(kept))
  kept = ranked(M.rows("editor"), "editor")
  check("a query for a window drops the Settings door like any other row", not has(kept, "Settings"), titles(kept))
  local child = M.select({ nav = true, to = "settings" })
  check("the settings level inherits the shared search", child.matcher == nil)
  check("the settings level pins Back", child.rows()[1].title == "Back" and child.rows()[1].pinned == true)
  check("the scope returns every window for the engine to filter", #M.scopeRows("vic") == 3)
end
