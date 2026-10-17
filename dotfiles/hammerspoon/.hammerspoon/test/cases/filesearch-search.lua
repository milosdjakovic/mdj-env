-- Unit case for FileSearch on the shared search, phase three packet two B of
-- docs/PLAN-UNIFIED-SEARCH.md. The engine still decides when to ask a source and the sources
-- still fetch by the whole parse, while what a query keeps and in what order is the shared
-- search's, ranking the rows the surface builds by the presentation's searchText. So the engine
-- and the list surface are loaded by path into an environment of their own, over a stand in hs
-- whose timers fire only when this case says so and a stand in source answering when told, and
-- the rows the surface hands over are ranked through the real rank.lua and match.lua exactly as
-- the stage does. The live hs is never touched. The runner reaches this file with a dofile call
-- carrying an absolute path, so it locates itself through debug.getinfo and loads everything by
-- path with loadfile, never require.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local olm = caseDir .. "/../../Spoons/Olm.spoon/"
local fs = olm .. "plugins/filesearch/"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  elseif detail then
    print("FAIL " .. description .. ", " .. tostring(detail))
  else
    print("FAIL " .. description)
  end
end

local rank = assert(loadfile(olm .. "lib/chooser/rank.lua"))()
local fuzzy = assert(loadfile(olm .. "lib/chooser/match.lua"))().fuzzy

-- Timers that wait to be fired, so the debounce is a step this case takes rather than a race.
local timers = {}
local function fireTimers()
  local due = timers
  timers = {}
  for _, t in ipairs(due) do
    if not t.stopped then t.fn() end
  end
end

local DIRS = { ["/home/dev"] = true, ["/home"] = true }
local noop = function() end
local fakeHs = {
  logger = { new = function() return setmetatable({}, { __index = function() return noop end }) end },
  timer = { doAfter = function(_, fn)
    local t = { fn = fn }
    t.stop = function() t.stopped = true end
    timers[#timers + 1] = t
    return t
  end },
  fs = { attributes = function(path, field)
    if field == "mode" then return DIRS[path] and "directory" or nil end
    return DIRS[path] and { mode = "directory" } or { mode = "file" }
  end },
  image = { iconForFileType = function(t) return { type = t } end },
}
local env = setmetatable({ hs = fakeHs }, { __index = _G })
-- Every module the engine and the surface load for themselves lands in the same environment.
env.loadfile = function(path, mode, e) return loadfile(path, mode or "t", e or env) end
local function load(path) return assert(env.loadfile(path))() end

local util = load(fs .. "util.lua")
local engine = load(fs .. "engine.lua")
local chooser = load(fs .. "chooser.lua")

-- A source that answers every shape and replies only when this case says so, so a round trip is
-- visible as a call and its answer lands when the case chooses.
local asked = {}
local replies = {}
local function reply(i, paths)
  local rows = {}
  for _, p in ipairs(paths) do rows[#rows + 1] = util.row(p, { source = "fake" }) end
  asked[i].cb(rows, nil)
end
local fakeSource = {
  name = "fake",
  available = function() return true end,
  supports = function() return true end,
  search = function(parsed, ctx, cb)
    asked[#asked + 1] = { parsed = parsed, ctx = ctx, cb = cb }
    return { cancel = noop }
  end,
}

-- How much each path is used, the ranker's whole answer.
local used = { ["/home/dev/report-draft.txt"] = 4, ["/home/dev/myreport.txt"] = 50 }
engine:init()
engine:configure({
  types = { js = { "js" } },
  roots = { dev = "/home/dev" },
  limits = { minChars = 3, retainCap = 2000, recentCount = 40, debounceMs = 70 },
  sources = { fakeSource },
  ranker = {
    score = function(path) return used[path] or 0 end,
    top = function() return {} end,
  },
})
chooser:configure({
  api = {
    rowsFor = function(q) return engine:rowsFor(q) end,
    upQuery = function() return engine:upQuery() end,
    parsed = function() return engine:parsed() end,
    searchText = function(raw) return engine:searchTextFor(raw) end,
    preference = function(path) return engine:preference(path) end,
  },
})

local manifest = assert(loadfile(fs .. "manifest.lua"))()
check("the presentation and the scope inherit the shared search",
  manifest.presentation.matcher == nil and manifest.registry.scope.matcher == nil
    and manifest.surface.matcher == nil)
check("both declare searchText", manifest.presentation.searchText.member == "chooser.searchText"
  and manifest.registry.scope.searchText.member == "chooser.searchText")
check("both keep two hundred rows after ranking",
  manifest.presentation.rowLimit == 200 and manifest.registry.scope.rowLimit == 200)
local search = { searchText = chooser.searchText, rowLimit = manifest.presentation.rowLimit }

local function titles(list)
  local out = {}
  for i, r in ipairs(list) do out[i] = r.title end
  return table.concat(out, ",")
end
local function position(list, title)
  for i, r in ipairs(list) do if r.title == title then return i end end
  return nil
end
local function ranked(query)
  return rank.apply(chooser.rowsForQuery(query), query, fuzzy, search)
end

--------------------------------------------------------------------------------
-- searchText from the grammar
--------------------------------------------------------------------------------

check("a type, a scope and text rank by the text", chooser.searchText(".js ~/dev/ foo") == "foo",
  chooser.searchText(".js ~/dev/ foo"))
check("a scope with text ranks by the text", chooser.searchText("dl/hs") == "hs")
check("a lone dot ranks by the rest", chooser.searchText(". zshrc") == "zshrc")
check("a browse ranks by nothing", chooser.searchText("~/dev/") == "")
check("a bare type ranks by nothing", chooser.searchText(".js") == "")

--------------------------------------------------------------------------------
-- The recent list
--------------------------------------------------------------------------------

engine:reset()
check("a session asks for the recent files", #asked == 1 and asked[1].parsed.kind == "recent")
local loading = ranked("")
check("before they land the list says it is gathering", #loading == 1 and loading[1].pinned == true
  and loading[1].title == "Recent files", titles(loading))
reply(1, { "/home/dev/zeta.md", "/home/dev/alpha.md", "/home/dev/report-draft.txt" })
local recent = ranked("")
check("an empty query keeps the recent list in the order it came",
  titles(recent) == "zeta.md,alpha.md,report-draft.txt", titles(recent))

--------------------------------------------------------------------------------
-- A round trip, the fields and the order
--------------------------------------------------------------------------------

local typed = chooser.rowsForQuery("report")
check("a query worth a round trip arms one and asks nothing yet", #asked == 1)
check("while it waits the list ends with a pinned searching row",
  typed[#typed].title == "Searching" and typed[#typed].pinned == true, titles(typed))
local waiting = rank.apply(typed, "report", fuzzy, search)
check("held rows the new text matches stay above it", titles(waiting) == "report-draft.txt,Searching",
  titles(waiting))
fireTimers()
check("the debounce dispatches the parse", #asked == 2 and asked[2].parsed.text == "report")
reply(2, {
  "/home/dev/myreport.txt",
  "/home/dev/report-final.txt",
  "/home/dev/report-draft.txt",
  "/home/report/notes.txt",
  "/home/dev/Report-Summary.pdf",
  "/home/dev/other.txt",
})

local rows = chooser.rowsForQuery("report")
check("the engine hands every held row over, unfiltered", #rows == 6, titles(rows))
local final = rows[position(rows, "report-final.txt")]
check("a file row is titled by its name and filters on it", final.title == "report-final.txt"
  and final.filterText == "report-final.txt", tostring(final.filterText))
check("its subtitle is its folder", final.subTitle == "/home/dev", final.subTitle)
check("a file never used has no bonus", final.bonus == 0, tostring(final.bonus))
local draft = rows[position(rows, "report-draft.txt")]
check("a used file carries its use scaled into zero to one", draft.bonus == 4 / 6, tostring(draft.bonus))

local kept = ranked("report")
check("a folder word finds no file inside it", position(kept, "notes.txt") == nil, titles(kept))
check("a used file leads an equally good match", position(kept, "report-draft.txt") == 1
  and position(kept, "report-final.txt") == 2, titles(kept))
check("however much a file is used it never lifts over a better match",
  position(kept, "myreport.txt") == #kept, titles(kept))

--------------------------------------------------------------------------------
-- Narrowing between round trips
--------------------------------------------------------------------------------

rows = chooser.rowsForQuery("report-f")
check("typing on narrows with no round trip", #asked == 2 and #timers == 0)
check("and hands every held row over again, the engine dropping none", #rows == 6, titles(rows))
kept = rank.apply(rows, "report-f", fuzzy, search)
check("the held rows are ranked by the longer text", titles(kept) == "report-final.txt", titles(kept))
kept = ranked("report-fINAL")
check("case is folded by the shared search", titles(kept) == "report-final.txt", titles(kept))
kept = ranked("report summary")
check("a second word narrows too", titles(kept) == "Report-Summary.pdf", titles(kept))
kept = ranked("repo")
check("a shorter text asks again", #timers == 1, #timers)
fireTimers()
check("and dispatches", #asked == 3)

--------------------------------------------------------------------------------
-- rowLimit
--------------------------------------------------------------------------------

kept = ranked("item")
fireTimers()
local many = {}
for i = 1, 300 do many[i] = string.format("/home/dev/item%03d.txt", i) end
reply(#asked, many)
rows = chooser.rowsForQuery("item")
check("three hundred held rows are all handed over", #rows == 300, #rows)
kept = rank.apply(rows, "item", fuzzy, search)
check("the search keeps two hundred after ranking", #kept == 200, #kept)
kept = rank.apply(rows, "", fuzzy, search)
check("an empty field keeps two hundred too", #kept == 200, #kept)

--------------------------------------------------------------------------------
-- Rows that are not files
--------------------------------------------------------------------------------

rows = chooser.rowsForQuery("ab")
kept = rank.apply(rows, "ab", fuzzy, search)
check("a short query keeps its keep typing row whatever matches", kept[#kept].title == "Keep typing"
  and kept[#kept].pinned == true, titles(kept))

rows = chooser.rowsForQuery("dev/")
check("a browse leads with the pinned up row", rows[1].title == ".." and rows[1].pinned == true,
  titles(rows))
fireTimers()
reply(#asked, { "/home/dev/a.txt" })
rows = chooser.rowsForQuery("dev/")
kept = rank.apply(rows, "dev/", fuzzy, search)
check("the browse keeps the up row and the listing in order", titles(kept) == "..,a.txt", titles(kept))

rows = chooser.rowsForQuery("?")
kept = rank.apply(rows, "?", fuzzy, search)
check("the help screen keeps every help row", #kept == #rows and #rows > 0 and kept[1].pinned == true,
  titles(kept))

engine:cancel()

--------------------------------------------------------------------------------
-- The engine prefers what the shared search keeps, 2026-10-17
--------------------------------------------------------------------------------

-- A source asks more loosely than the shared search keeps, so the engine is handed keeps, built
-- by the root from the shared matcher and the surface's own search name, and fills its retain
-- cap with the rows the search keeps first. A round trip that brought back none of those says
-- no matches, and while a query of another population is pending the held rows are not shown.
asked, timers = {}, {}
engine:init()
engine:configure({
  types = { js = { "js" } },
  roots = { dev = "/home/dev" },
  limits = { minChars = 3, retainCap = 3, recentCount = 40, debounceMs = 70 },
  sources = { fakeSource },
  ranker = { score = function() return 0 end, top = function() return {} end },
  keeps = function(row, text) return fuzzy(text, chooser.searchName(row)) ~= nil end,
})
engine:reset()
reply(1, {})

chooser.rowsForQuery("report")
fireTimers()
reply(#asked, {
  "/home/report/one.txt", "/home/report/two.txt", "/home/report/three.txt",
  "/home/dev/report-final.txt",
})
kept = ranked("report")
check("a row the search keeps is held ahead of rows it drops when the cap cuts",
  titles(kept) == "report-final.txt", titles(kept))

chooser.rowsForQuery("ledger")
fireTimers()
reply(#asked, { "/home/ledger/a.txt", "/home/ledger/b.txt" })
kept = ranked("ledger")
check("a round trip holding only rows the search drops says no matches",
  titles(kept) == "No matches" and kept[1].pinned == true, titles(kept))

chooser.rowsForQuery("report")
fireTimers()
reply(#asked, { "/home/dev/report-final.txt", "/home/dev/report.js" })
kept = ranked("dev/ .js report")
check("while another population is asked only the searching status shows",
  titles(kept) == "Searching", titles(kept))
fireTimers()
reply(#asked, { "/home/dev/report.js" })
kept = ranked("dev/ .js report")
check("and the answer replaces it", titles(kept) == "report.js", titles(kept))

chooser.rowsForQuery("report")
fireTimers()
reply(#asked, { "/home/dev/report-final.txt", "/home/dev/report.js" })
kept = ranked("repo")
check("a backspace over the same population keeps the held rows while it asks",
  position(kept, "report-final.txt") ~= nil and kept[#kept].title == "Searching", titles(kept))
engine:cancel()
