-- Unit case for the simple lists that moved onto the shared search in phase two of
-- docs/PLAN-UNIFIED-SEARCH.md, Workspaces, DisplayProfiles, TmuxSessions, the Olm Plugins
-- page and the Olm Placement list. The first row under a typed query is checked by name wherever a pinned row
-- leads the resting list, since the first row is what the highlight and Enter land on. Each chooser is
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
    { id = "a", name = "Desk", available = true, apps = 4, excluded = 0, topology = "Studio", taken = "today" },
    { id = "b", name = "Travel", available = false, apps = 2, excluded = 1, topology = "one display",
      reason = "needs two displays", taken = "today" },
    { id = "c", name = "Work", available = true, apps = 3, excluded = 0, topology = "Studio", taken = "today" },
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
  check("workspaces top level returns every layout without filtering", #M.rows("desk") == 4)
  local kept = ranked(M.rows("desk"), "desk")
  check("a query keeps the layout that matches and New snapshot after it", titles(kept) == "Desk,New snapshot",
    titles(kept))
  kept = ranked(M.rows("work"), "work")
  check("with work typed the first row, where Enter lands, is the Work layout and not New snapshot",
    kept[1] and kept[1].title == "Work", titles(kept))
  for _, q in ipairs({ "apps", "studio", "applies" }) do
    kept = ranked(M.rows(q), q)
    check("a layout's status subtitle is not searched, " .. q .. " matches no layout",
      titles(kept) == "New snapshot", titles(kept))
  end
  kept = ranked(M.rows("zzzq"), "zzzq")
  check("a query matching nothing leaves New snapshot, never an empty list",
    titles(kept) == "New snapshot", titles(kept))
  check("there is no row for a query that matches nothing", not has(M.rows("zzzq"), "No layout matches"))

  local scope = M.scopeRows("desk")
  check("the scope returns every layout for the engine to filter", #scope == 3)
  kept = ranked(M.scopeRows("studio"), "studio")
  check("the scope's Apply subtitle is not searched either", #kept == 0, titles(kept))

  -- Return on a layout applies it, and its apps and its name are verbs of the action panel that
  -- push a level through stagePush, docs/PLAN-ACTION-PANEL.md.
  local applied, pushed = nil, nil
  api.apply = function(id) applied = id return true end
  M:configure({ stageSelectedItem = function() return { nav = "layout", id = "a" } end,
    stagePush = function(child) pushed = child return true end })
  check("Return on a layout applies it and opens no level",
    M.select({ nav = "layout", id = "a" }) == nil and applied == "a")
  check("isLayout answers for a layout row and not for New snapshot",
    M:isLayout({ nav = "layout", id = "a" }) and not M:isLayout({ nav = "new" }))
  M:editApps()
  local apps = pushed
  check("the apps level inherits the shared search and reads as one", apps and apps.matcher == nil
    and apps.placeholder == "Search apps in this layout")
  check("the apps level pins Back", apps.rows()[1].pinned == true)
  kept = ranked(apps.rows(), "main")
  check("an app row is searched by its name and not by where its windows sit", titles(kept) == "Back", titles(kept))
  check("the new snapshot name level keeps matcher false", M.select({ nav = "new" }).matcher == false)
  M:renameLayout()
  check("the rename level keeps matcher false", pushed and pushed.matcher == false)
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
  check("a query keeps the profile that matches and Capture after it",
    titles(kept) == "Laptop,Capture current arrangement", titles(kept))
  check("with a profile name typed the first row, where Enter lands, is that profile",
    kept[1] and kept[1].title == "Laptop", titles(kept))
  kept = ranked(M.rows("display"), "display")
  check("a profile's display count subtitle is not searched", titles(kept) == "Capture current arrangement",
    titles(kept))
  active = "Desk"
  kept = ranked(M.rows("active"), "active")
  check("the Active status is not searched", #kept == 0, titles(kept))
  rows = M.rows("")
  check("with a profile active there is no capture row", not has(rows, "Capture current arrangement") and #rows == 2)

  -- Return on a profile applies it, and its displays and its name are verbs of the action panel
  -- that push a level through stagePush, docs/PLAN-ACTION-PANEL.md.
  local applied, pushed = nil, nil
  api.reapply = function() applied = active end
  local highlighted = { nav = true, to = "profile", name = "Desk" }
  M:configure({ stageSelectedItem = function() return highlighted end,
    stagePush = function(child) pushed = child return true end })
  check("Return on the matching profile reapplies it and opens no level",
    M.select({ nav = true, to = "profile", name = "Desk" }) == nil and applied == "Desk")
  applied = nil
  check("Return on a profile whose displays are not attached runs nothing",
    M.select({ nav = true, to = "profile", name = "Laptop" }) == nil and applied == nil)
  M:showDisplays()
  local displays = pushed
  check("the displays screen inherits the shared search", displays and displays.matcher == nil)
  check("the displays screen pins Back", displays.rows()[1].title == "Back" and displays.rows()[1].pinned == true)
  highlighted = { nav = true, to = "profile", name = "Nowhere" }
  M:showDisplays()
  local gone = pushed.rows()
  check("Profile is gone is pinned like Layout is gone", gone[2] and gone[2].title == "Profile is gone"
    and gone[2].pinned == true)
  highlighted = { nav = true, to = "profile", name = "Desk" }
  M:renameProfile()
  check("the rename screen keeps matcher false", pushed and pushed.matcher == false)
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
  kept = ranked(child.rows(), "installed")
  check("a provider's Installed status is not searched", titles(kept) == "Back", titles(kept))
  kept = ranked(M.rows("fresh attach"), "fresh attach")
  check("the Settings door's sentence is not searched", not has(kept, "Settings"), titles(kept))
  check("the scope returns every window for the engine to filter", #M.scopeRows("vic") == 3)
end

--------------------------------------------------------------------------------
-- The Olm Plugins page, and the Olm Placement list
--------------------------------------------------------------------------------

do
  local catalog = {
    { identity = "calendar", about = { title = "Calendar" }, needs = {}, disabled = false },
    { identity = "clipboard", about = { title = "Clipboard" }, needs = {}, disabled = false,
      pending = true, after = { off = true } },
    { identity = "olmplugins", about = { title = "Olm Plugins" }, needs = {}, disabled = false },
  }
  local M = load("plugins/olmplugins/init.lua")
  M:configure({
    pluginCatalog = function() return catalog end,
    pluginCascade = function() return {} end,
    stagePluginSwitch = function() return true end,
    applyPluginSwitches = function() end,
  })
  local rows = M.rows()
  check("the Plugins page leads with Apply now, pinned", rows[1].title == "Apply now"
    and rows[1].pinned == true, titles(rows))
  local kept = ranked(rows, "clip")
  check("with clip typed the first row, where Enter lands, is Clipboard and not Apply now",
    kept[1] and kept[1].title == "Clipboard", titles(kept))
  check("and Apply now trails it", titles(kept) == "Clipboard,Apply now", titles(kept))
  kept = ranked(rows, "off")
  check("a plugin's state words are not searched", titles(kept) == "Apply now", titles(kept))

  local P = load("plugins/olmplacement/init.lua")
  P:configure({
    overlayPlacementMode = function() return "cursor" end,
    setOverlayPlacementMode = function() end,
  })
  kept = ranked(P.rows(), "active")
  check("a placement option is found by its title", titles(kept) == "With the active window", titles(kept))
end
