-- Unit case for the BrowserTabs settings level, which has no level beneath it. The runner
-- reaches this file with a dofile call carrying an absolute path, so this file locates itself
-- through debug.getinfo and loads the chooser by path with loadfile, never require.
--
-- The promises under test are four. Choosing a browser row switches it where it stands, so
-- the intercept answers "stay" and the state flips. A permission row appears under a switched
-- on browser only when the permission asks something, names the browser and filters on its name
-- alone. The Settings row trails the tab list on an empty query, and once something is typed it
-- is scored against its own title like any tab, kept when it matches and dropped when it does
-- not. And since phase three of the unified search the tab list ranks nothing itself, each tab
-- row declares its title, its host and address as names, its browser as a keyword and its
-- recency as a bonus, and the real rank.lua and match.lua decide what a query keeps. Everything
-- is read through the module's own select, rows and intercept over a fake api, no test hook.

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

local matchChunk, matchErr = loadfile(caseDir .. "/../../Spoons/Olm.spoon/lib/chooser/match.lua")
if not matchChunk then error("could not load the shared match, " .. tostring(matchErr)) end
local fuzzy = matchChunk().fuzzy
local rankChunk, rankErr = loadfile(caseDir .. "/../../Spoons/Olm.spoon/lib/chooser/rank.lua")
if not rankChunk then error("could not load the rank engine, " .. tostring(rankErr)) end
local rank = rankChunk()

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

check("Back leads and is pinned", rows[1].title == "Back" and rows[1].pinned == true
  and rows[1].filterText == nil)
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

-- The tab list. Three Alpha tabs and two Bravo ones, listed the way the root's order hands them
-- over, the tabs this tool opened first in recency order and the rest after. recent holds the
-- remembered rank by address, one being the most recent.
local recent = {}
api.recencyRank = function(t) return recent[t.url] end
local listing = {
  { title = "Team notes", url = "https://wiki.test/team", browser = "Alpha", bundleID = "com.test.a" },
  { title = "Notes", url = "https://wiki.test/mine", browser = "Alpha", bundleID = "com.test.a" },
  { title = "Rediscover jazz", url = "https://music.test/r", browser = "Alpha", bundleID = "com.test.a" },
  { title = "Discord", url = "https://discord.com/app", browser = "Bravo", bundleID = "com.test.b" },
  { title = "Pull request 12", url = "https://www.github.com/o/r/pull/12", browser = "Bravo",
    bundleID = "com.test.b", group = "pinned" },
  { title = "Bravo release notes", url = "https://news.test/b", browser = "Alpha", bundleID = "com.test.a" },
}
recent["https://wiki.test/team"] = 1
recent["https://wiki.test/mine"] = 2
recent["https://music.test/r"] = 3
api.listTabs = function(cb) cb(listing, {}) end
M:configure({ api = api })
M.reload()

local function titlesOf(list)
  local out = {}
  for i, r in ipairs(list) do out[i] = r.title end
  return table.concat(out, ",")
end
local function position(list, title)
  for i, r in ipairs(list) do if r.title == title then return i end end
  return nil
end
local function ranked(query) return rank.apply(M.rows(query), query, fuzzy) end

local resting = M.rows("")
check("the supplier hands every tab and the door whatever is typed",
  #M.rows("zzz") == #listing + 1 and titlesOf(M.rows("zzz")) == titlesOf(resting), titlesOf(M.rows("zzz")))
check("with an empty query the resting order stands and Settings is the last row",
  titlesOf(rank.apply(resting, "", fuzzy)) == "Team notes,Notes,Rediscover jazz,Discord,Pull request 12,"
    .. "Bravo release notes,Settings", titlesOf(rank.apply(resting, "", fuzzy)))

local pr = resting[position(resting, "Pull request 12")]
check("a tab row filters on its title, not on its status subtitle", pr.filterText == "Pull request 12"
  and pr.subTitle == "Bravo · pinned · github.com", pr.subTitle)
check("a tab row names its host and its address", pr.names and pr.names[1] == "github.com"
  and pr.names[2] == "https://www.github.com/o/r/pull/12")
check("a tab row declares its browser as a keyword", pr.keywords == "Bravo")
check("a tab this tool never opened has no bonus", pr.bonus == nil)
local team, mine, jazz = resting[1], resting[2], resting[3]
check("the most recently opened tab has the highest bonus, one", team.bonus == 1, tostring(team.bonus))
check("the bonus falls with recency and stays above zero", mine.bonus == 2 / 3 and jazz.bonus == 1 / 3,
  tostring(mine.bonus) .. " " .. tostring(jazz.bonus))
local door = resting[#resting]
check("the Settings door filters on its title and is not pinned while there are tabs",
  door.filterText == "Settings" and door.pinned ~= true)

local list = ranked("disc")
check("a better match beats a recent one, Discord at a word start above the recent Rediscover",
  list[1].title == "Discord" and position(list, "Rediscover jazz") == 2, titlesOf(list))
list = ranked("notes")
check("recency orders two equal matches, the recent Team notes above Notes at the field start",
  list[1].title == "Team notes" and list[2].title == "Notes", titlesOf(list))
list = ranked("git")
check("a tab answers to its host whatever its page is called", list[1] and list[1].title == "Pull request 12",
  titlesOf(list))
list = ranked("github pull")
check("two words may land in the host and the title", list[1] and list[1].title == "Pull request 12",
  titlesOf(list))
list = ranked("pinned")
check("Arc's group in the subtitle is not searched", position(list, "Pull request 12") == nil, titlesOf(list))
list = ranked("ravo")
check("the browser keyword matches only at a word start, ravo finds no Bravo tab",
  position(list, "Discord") == nil, titlesOf(list))
list = ranked("bravo")
check("the browser name gathers that browser's tabs", position(list, "Discord") ~= nil
  and position(list, "Pull request 12") ~= nil, titlesOf(list))
check("a page named after the browser outranks the tabs found by the keyword",
  list[1].title == "Bravo release notes", titlesOf(list))

list = ranked("settings")
check("typing settings scores the Settings row in with the tabs", position(list, "Settings") ~= nil,
  titlesOf(list))
list = ranked("sett")
check("the start of its title keeps Settings in the list", position(list, "Settings") ~= nil, titlesOf(list))
list = ranked("disc")
check("and drops Settings when it does not match", position(list, "Settings") == nil, titlesOf(list))
list = ranked("browsers")
check("its count subtitle is not searched", position(list, "Settings") == nil, titlesOf(list))
check("the module no longer carries the keyword rule", not io.open(chooserPath):read("a"):find("SETTINGS_WORDS", 1, true))
local source = io.open(chooserPath):read("a")
check("the module no longer scores its own rows", not source:find("bestFieldScore", 1, true)
  and not source:find("matchedTabs", 1, true) and not source:find("cfg.matcher", 1, true))

local scope = M.scopeRows("disc")
check("the scope hands every tab over for the query scope to rank", #scope == #listing, tostring(#scope))

-- With no tabs the guidance rows stay and the Settings row follows them whatever is typed.
api.listTabs = function(cb) cb({}, {}) end
M.reload()
list = rank.apply(M.rows("zzz"), "zzz", fuzzy)
check("with no tabs the guidance row and Settings stay under any query",
  #list == 2 and list[1].title == "No open tabs" and list[2].title == "Settings", titlesOf(list))
check("the scope's guidance rows are pinned so a typed rest keeps them",
  M.explain("there")[1].pinned == true)

local manifest = loadfile(caseDir .. "/../../Spoons/Olm.spoon/plugins/browsertabs/manifest.lua")()
check("the tab list and its scope inherit the shared search", manifest.presentation.matcher == nil
  and manifest.registry.scope.matcher == nil)
