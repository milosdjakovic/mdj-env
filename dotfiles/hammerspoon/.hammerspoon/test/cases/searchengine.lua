-- Unit case for the one rank engine, docs/PLAN-UNIFIED-SEARCH.md phase one. Four places used to
-- carry their own copy of the rank loop, host/queryscope, the default provider's list model,
-- host/actionpanel and the launcher's catalog ranking. Each now ranks through
-- Olm.spoon/lib/chooser/rank.lua, and this case proves three of them answer exactly the order
-- rank.apply answers for the same rows, query and matcher. The action panel's own check lives in
-- actionpanel.lua beside the helpers that open a panel.
--
-- The runner reaches this file with a dofile call carrying an absolute path, so this file finds
-- every module from its own location through debug.getinfo. Nothing under test is edited, and
-- each module is loaded fresh by path, never required.
--
-- Each check prints one line, PASS or FAIL followed by a plain description, the convention every
-- case in this directory follows.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local spoonDir = caseDir .. "/../../Spoons/Olm.spoon/"

local function load(rel)
  local chunk, err = loadfile(spoonDir .. rel)
  if not chunk then error("could not load Olm.spoon/" .. rel .. ", " .. tostring(err)) end
  return chunk()
end

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local rank = load("lib/chooser/rank.lua")
local fuzzy = load("lib/chooser/match.lua").fuzzy
local model = load("lib/chooser/providers/default/list/model.lua")
local QueryScope = load("host/queryscope/init.lua")
local Launcher = load("host/launcher/init.lua")

-- Rows mixing every kind of match the engine distinguishes, whole words at a word start and mid
-- word, scattered letters, a typo, two words, and the addresses this work started from, each
-- with a descriptor so the launcher can key it.
local TITLES = {
  "Some example", "Base", "Sending", "Settings", "seven little things", "Displays",
  "Downloads System Preferences Look", "hello everyone there", "help others there",
  "https://vicert-testing.canvasmedical.com/login?next=%2Fpatients",
  "https://resources.anthropic.com/hubfs/The-Complete-Guide-to-Building-Skill-for-Claude.pdf",
}
local function rows()
  local out = {}
  for i, t in ipairs(TITLES) do
    out[i] = { title = t, subTitle = "row " .. i, filterText = t,
               item = { kind = "app", bundleID = "test." .. i } }
  end
  return out
end

local QUERIES = { "se", "settings", "dspl", "settigns", "hello there", "e" }

local function titles(list)
  local out = {}
  for i, r in ipairs(list) do out[i] = r.title end
  return table.concat(out, ",")
end

-- The default provider's list model, which used to hard wire fuzzy and ignore any matcher.
for _, q in ipairs(QUERIES) do
  local want = titles(rank.apply(rows(), q, fuzzy))
  local got = titles(model.setQuery(model.newState(rows(), nil, ""), q, fuzzy).filtered)
  check("the list model ranks " .. q .. " exactly as the engine does", got == want,
    "got " .. got .. ", wanted " .. want)
end

do
  local substring = load("lib/chooser/match.lua").substring
  local got = titles(model.setQuery(model.newState(rows(), nil, ""), "se", substring).filtered)
  local want = titles(rank.apply(rows(), "se", substring))
  check("the list model ranks with the matcher it is handed rather than a fixed one",
    got == want, "got " .. got .. ", wanted " .. want)
end

-- The query scope, whose own filter loop is gone.
do
  local qs = QueryScope
  qs:init()
  local scope = { name = "demo", title = "Demo", aliases = { "dm" },
    rows = function() return rows() end, run = function() end }
  qs:configure({ matcher = fuzzy, rank = rank, scopes = { scope } })
  for _, q in ipairs(QUERIES) do
    local want = titles(rank.apply(rows(), q, fuzzy))
    local got = titles(qs:_filter(scope, q, rows()))
    check("the query scope ranks " .. q .. " exactly as the engine does", got == want,
      "got " .. got .. ", wanted " .. want)
  end
  local whole = titles(qs:_filter(scope, "", rows()))
  check("the query scope keeps a scope's own order on an empty query", whole == titles(rows()))
end

-- The launcher, which since phase four ranks nothing itself. Its supplier hands the catalog over
-- in the resting order with no bonus when nothing is remembered, so the stage ranking it through
-- the engine answers exactly the engine's order. test/ranking.lua covers the memory, which
-- reaches the engine as each row's bonus.
do
  Launcher._assoc = nil
  Launcher._page = nil
  Launcher._predicates = {}
  Launcher._queryProviders = {}
  Launcher._orderedRowsCache = rows()
  for _, q in ipairs(QUERIES) do
    local want = titles(rank.apply(rows(), q, fuzzy))
    local got = titles(rank.apply(Launcher:_commandRows(q), q, fuzzy))
    check("the launcher ranks " .. q .. " exactly as the engine does with nothing remembered",
      got == want, "got " .. got .. ", wanted " .. want)
  end
  check("the launcher no longer carries a ranking of its own", Launcher._rankCatalog == nil)
end
