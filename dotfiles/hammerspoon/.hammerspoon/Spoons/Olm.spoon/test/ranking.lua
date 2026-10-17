-- The launcher's search ordering, end to end, in plain Lua.
--
-- Two halves. lib/queryassoc.lua's arithmetic and its rules, then host/launcher's own use of
-- it, which is the half no other gate reaches, since the dry gate cannot load that host at
-- all and reports it unknown on every run.
--
-- This tier exists for the same reason test/drygate.lua does. Everything else in this suite
-- proves something about code RUNNING, which needs a live Hammerspoon and the test lock and
-- several seconds. What this file checks needs neither, since the store's whole behaviour is
-- arithmetic over a table and the only Hammerspoon it touches is two hs.settings calls, so a
-- stub of four lines stands in for the whole application and an agent with no way to take the
-- lock can still prove the numbers.
--
-- The numbers asserted here are the ones the design was chosen for rather than whatever the
-- code happens to produce, which is the point of writing them down. Overturning a settled
-- leader on the fourth pick is the behaviour asked for, and a test that reads the constant and
-- recomputes the expectation from it would pass just as happily if the constant were wrong.
--
-- Run it.
--   lua test/ranking.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local spoon = here .. "../"

-- The whole of the application this module needs. hs.settings is a key value store over the
-- user defaults, so a table is a faithful stand in, and holding it out here lets a test reach
-- in and check what was actually persisted rather than only what the instance reports.
--
-- The launcher half needs three more fields to load at all, which is worth noting because it
-- is exactly the gap that makes that host the dry gate's permanent unknown. The gate stubs
-- hs.processInfo.bundleID as a table and the host concatenates it at load. A string here is
-- the whole difference.
local defaults = {}
local running = {}
hs = {
  settings = {
    get = function(key) return defaults[key] end,
    set = function(key, value) defaults[key] = value end,
  },
  processInfo = { bundleID = "org.hammerspoon.Hammerspoon" },
  logger = {
    new = function()
      return setmetatable({}, { __index = function() return function() end end })
    end,
  },
  application = { runningApplications = function() return running end },
}

local Q = assert(loadfile(spoon .. "lib/queryassoc.lua"))()

local failures, checks = 0, 0
local function ok(condition, what)
  checks = checks + 1
  if not condition then
    failures = failures + 1
    print("  FAIL  " .. what)
  end
end
local function eq(got, want, what)
  ok(got == want, string.format("%s, wanted %s, got %s", what, tostring(want), tostring(got)))
end

local function fresh(opts)
  defaults = {}
  opts = opts or {}
  opts.settingsKey = opts.settingsKey or "test.queryassoc"
  return Q.new(opts)
end

local function lead(a, query)
  return a.orderFor(query)[1]
end

print("queryassoc")

-- The scenario the whole design was argued from. Maps is picked thirty times under "ma" and
-- then Mail is picked, and the fourth Mail is the one that takes the top row. Three is too
-- eager and seven is the sluggishness this replaced.
do
  local a = fresh()
  for _ = 1, 30 do a.note("ma", "app:Maps") end
  eq(lead(a, "ma"), "app:Maps", "a settled favourite leads")

  a.note("ma", "app:Mail")
  eq(lead(a, "ma"), "app:Maps", "one pick of a challenger does not take the lead")
  a.note("ma", "app:Mail")
  eq(lead(a, "ma"), "app:Maps", "two picks do not take the lead")
  a.note("ma", "app:Mail")
  eq(lead(a, "ma"), "app:Maps", "three picks do not take the lead")
  a.note("ma", "app:Mail")
  eq(lead(a, "ma"), "app:Mail", "the fourth pick takes the lead")
end

-- The same crossing without the margin, so the margin is shown to be doing something rather
-- than being asserted to. Without it the scores cross on the fourth too, and what the margin
-- buys is everything after that, which the wobble case below states.
do
  local a = fresh({ margin = 0 })
  for _ = 1, 30 do a.note("ma", "app:Maps") end
  for _ = 1, 3 do a.note("ma", "app:Mail") end
  eq(lead(a, "ma"), "app:Maps", "no margin, three picks still lose")
  a.note("ma", "app:Mail")
  eq(lead(a, "ma"), "app:Mail", "no margin, the fourth still wins")
end

-- What the margin is actually for. A leader that has just been overturned must not be handed
-- the row back by one stray pick, which is the flapping a bare comparison produces.
do
  local a = fresh()
  for _ = 1, 30 do a.note("ma", "app:Maps") end
  for _ = 1, 4 do a.note("ma", "app:Mail") end
  eq(lead(a, "ma"), "app:Mail", "the challenger has the lead")
  a.note("ma", "app:Maps")
  eq(lead(a, "ma"), "app:Mail", "one stray pick does not hand the lead straight back")

  local bare = fresh({ margin = 0 })
  for _ = 1, 30 do bare.note("ma", "app:Maps") end
  for _ = 1, 4 do bare.note("ma", "app:Mail") end
  bare.note("ma", "app:Maps")
  eq(lead(bare, "ma"), "app:Maps", "with no margin the same stray pick does hand it back")
end

-- A thing you stop picking leaves on its own, with nothing sweeping for it. From a full
-- ceiling at decay 0.80 and floor 0.05 that is about twenty four picks of anything else.
do
  local a = fresh()
  for _ = 1, 30 do a.note("ma", "app:Maps") end
  for _ = 1, 24 do a.note("ma", "app:Mail") end
  local order = a.orderFor("ma")
  eq(#order, 1, "the abandoned entry is forgotten")
  eq(order[1], "app:Mail", "and the one still picked remains")
end

-- Picking at one spelling teaches the shorter searches too, so the memory fills in as you
-- use it rather than only for the exact string that was in the field.
do
  local a = fresh()
  a.note("slac", "app:Slack")
  eq(lead(a, "slac"), "app:Slack", "the query itself is remembered")
  eq(lead(a, "sla"), "app:Slack", "and its three letter prefix")
  eq(lead(a, "sl"), "app:Slack", "and its two letter prefix")
  eq(lead(a, "s"), nil, "but never a single letter, which the catalog scopes answer to")
end

-- A single letter is remembered when it genuinely was the whole query, since then it is a
-- statement about that search rather than a side effect of a longer one.
do
  local a = fresh()
  a.note("s", "app:Safari")
  eq(lead(a, "s"), "app:Safari", "a one letter query records itself")
end

-- Typing further than you ever have before still finds what was learned, and the longest
-- remembered spelling is the one that answers.
do
  local a = fresh()
  a.note("ma", "app:Maps")
  a.note("mail", "app:Mail")
  eq(lead(a, "mailbox"), "app:Mail", "a longer query falls back to its longest known prefix")
  eq(lead(a, "map"), "app:Maps", "and a different branch falls back to its own")
end

-- Case is not a search. The matcher folds it, so the memory has to as well, or typing a
-- capital would silently be a different query.
do
  local a = fresh()
  a.note("Ma", "app:Maps")
  eq(lead(a, "ma"), "app:Maps", "a query is remembered case folded")
end

-- Pruning is deliberately partial. The caller proves what it can prove gone and says so
-- through the predicate, and everything it declines to claim is left alone, because a row
-- absent today may only be switched off.
do
  local a = fresh()
  a.note("ma", "app:Maps")
  a.note("te", "special:textCase")
  local isApp = function(key) return key:sub(1, 4) == "app:" end
  a.prune({}, isApp)
  eq(lead(a, "ma"), nil, "an app the caller says is gone is dropped")
  eq(lead(a, "te"), "special:textCase", "a key the predicate declines survives")

  local b = fresh()
  b.note("ma", "app:Maps")
  b.prune({ "app:Maps" }, isApp)
  eq(lead(b, "ma"), "app:Maps", "an app still present survives")
end

-- The memory survives a reload, which is the whole reason it is persisted at all, and a
-- second instance over the same key reads what the first wrote.
do
  local a = fresh()
  for _ = 1, 5 do a.note("ma", "app:Maps") end
  local reloaded = Q.new({ settingsKey = "test.queryassoc" })
  eq(lead(reloaded, "ma"), "app:Maps", "a fresh instance reads the persisted pairs")
end

-- This outlives the code that wrote it, so anything not shaped the way this file writes costs
-- one entry rather than the whole memory.
do
  defaults = {}
  defaults["test.queryassoc"] = {
    ["ma"] = { lead = "app:Maps", n = 3, s = { ["app:Maps"] = { v = 2, k = 3 } } },
    ["junk"] = { n = 1, s = { ["app:X"] = { v = "not a number", k = 1 } } },
    ["alsojunk"] = "not a table",
  }
  local a = Q.new({ settingsKey = "test.queryassoc" })
  eq(lead(a, "ma"), "app:Maps", "a well formed entry survives a malformed neighbour")
  eq(lead(a, "junk"), nil, "an entry with no usable key is dropped")
  eq(lead(a, "alsojunk"), nil, "an entry that is not a table is dropped")
end

-- A query never typed answers nothing rather than an empty leader, so a caller can ask
-- unconditionally on every keystroke.
do
  local a = fresh()
  eq(#a.orderFor("nothing"), 0, "an unknown query answers an empty order")
  eq(#a.orderFor(""), 0, "and so does an empty one")
end

-- The cap is on queries rather than on pairs, since a query is what a lookup is keyed by and
-- the weakest are the ones nobody will type again.
do
  local a = fresh({ maxQueries = 5 })
  for i = 1, 20 do a.note("q" .. i, "app:Thing" .. i) end
  local held = 0
  for _ in pairs(defaults["test.queryassoc"]) do held = held + 1 end
  ok(held <= 5, string.format("the query cap holds, wanted at most 5, got %d", held))
end


--------------------------------------------------------------------------------
-- host/launcher, the ordering itself.
--
-- Everything above is arithmetic. This is the behaviour that arithmetic was for, run through
-- the host's own _rankCatalog against the real shared matcher, so what is asserted here is
-- what a person actually sees in the list.
--------------------------------------------------------------------------------

print("launcher ranking")

local fuzzy = assert(loadfile(spoon .. "lib/chooser/match.lua"))().fuzzy
local rank = assert(loadfile(spoon .. "lib/chooser/rank.lua"))()
local Launcher = assert(loadfile(spoon .. "host/launcher/init.lua"))()

local function appRow(name, bundleID, subTitle)
  return {
    title = name, subTitle = subTitle, item = { kind = "app", bundleID = bundleID },
    -- The name alone, the shape the launcher hands its catalog over in since 2026-10-17, the
    -- subtitle being a status that is not searched.
    filterText = name,
  }
end

-- The exact scenario this whole change was argued from, and the reason the shared matcher is
-- used here rather than a fake one. Mail and Maps match "ma" identically, both on the first
-- letter and both extending the run, and Mail wins on nothing but its subtitle being nine
-- characters shorter, which the scorer charges 0.02 a character for.
local MAIL = appRow("Mail", "com.apple.mail", "Open")
local MAPS = appRow("Maps", "com.apple.Maps", "Not running")

local function launcher(assoc)
  defaults = {}
  Launcher._matcher = fuzzy
  Launcher._rank = rank
  Launcher._assoc = assoc
  Launcher._page = nil
  Launcher._installedApps = nil
  return Launcher
end

local function titles(rows)
  local out = {}
  for i, row in ipairs(rows) do out[i] = row.title end
  return table.concat(out, ",")
end

-- The complaint, stated as a test. Nothing has been picked yet, so the list is ordered on the
-- match alone and the row that loses does so for a reason that has nothing to do with typing.
do
  local l = launcher(nil)
  eq(titles(l:_rankCatalog("ma", { MAIL, MAPS })), "Mail,Maps",
    "with nothing remembered the longer subtitle loses")
end

-- And the fix. One pick is enough, because an association is a record of what was meant rather
-- than a guess about what is popular.
do
  local a = fresh()
  local l = launcher(a)
  a.note("ma", "app:com.apple.Maps")
  eq(titles(l:_rankCatalog("ma", { MAIL, MAPS })), "Maps,Mail",
    "one pick puts the chosen row first next time")
end

-- The prefix half, seen from the list rather than from the store. Picking at a longer spelling
-- improves the shorter searches on the way to it.
do
  local a = fresh()
  local l = launcher(a)
  a.note("map", "app:com.apple.Maps")
  eq(titles(l:_rankCatalog("ma", { MAIL, MAPS })), "Maps,Mail",
    "a pick at a longer query orders the shorter one too")
end

-- The guard that matters most, and the one this suite found the hard way. Every remembered
-- spelling answers for the longer queries it begins, so a pick made at "ma" is consulted when
-- you type "mail" too, and Maps genuinely does match "mail" by spending the scorer's typo
-- allowance on the letter it cannot place. Without the nearness guard this ordered Maps above
-- Mail while Mail was spelled out in full. Twenty picks is deliberately far more than it takes
-- to lead, to show that no amount of history buys its way past a clearly better match.
do
  local a = fresh()
  local l = launcher(a)
  for _ = 1, 20 do a.note("ma", "app:com.apple.Maps") end
  -- Maps used to match mail through the scorer's typo allowance and trail Mail. Since
  -- 2026-10-17 a four letter word gets one edit at a word start and nothing scattered, so Maps
  -- does not match at all and Mail stands alone, the same guarantee stated more strongly.
  eq(titles(l:_rankCatalog("mail", { MAIL, MAPS })), "Mail",
    "spelling a name out still wins, whatever was picked at a shorter spelling")
  eq(titles(l:_rankCatalog("ma", { MAIL, MAPS })), "Maps,Mail",
    "and the same memory still decides where the two match about equally")
end

-- The same guard from the other side. A row that matched a good deal worse stays where the
-- match put it even when the association is for this exact query rather than a prefix of it.
do
  local a = fresh()
  local l = launcher(a)
  a.note("map", "app:com.apple.mail")
  -- Mail used to match map weakly and trail Maps. Since 2026-10-17 a three letter word gets no
  -- edit, so Mail does not match at all and the association has nothing to lift.
  eq(titles(l:_rankCatalog("map", { MAPS, MAIL })), "Maps",
    "an exact association cannot bridge a real difference in match quality either")
end

-- Nothing is ever added to the list by remembering it. A row has to match what is typed now to
-- be ordered at all, which is what makes the prefix walk back safe however far it goes.
do
  local a = fresh()
  local l = launcher(a)
  a.note("s", "app:com.apple.Safari")
  local SAFARI = appRow("Safari", "com.apple.Safari", "Open")
  eq(titles(l:_rankCatalog("ma", { MAIL, MAPS, SAFARI })), "Mail,Maps",
    "a remembered row that does not match is simply not in the list")
end

-- The resting list is untouched, which is the thing that was explicitly not to change. An
-- empty query is handed back exactly as _orderedRows decided it, unscored and unfiltered.
do
  local a = fresh()
  local l = launcher(a)
  a.note("ma", "app:com.apple.Maps")
  eq(titles(l:_rankCatalog("", { MAIL, MAPS })), "Mail,Maps",
    "an empty query keeps the recency order untouched")
end

-- With no store at all the list still works and orders on the match, which is what the
-- optional policy on the declaration promises.
do
  local l = launcher(nil)
  -- Mail used to win here on its shorter subtitle. The subtitle is a status and is no longer
  -- searched, so the two names tie on ma and the resting order decides, which is what the
  -- complaint above asked for.
  eq(titles(l:_rankCatalog("ma", { MAPS, MAIL })), "Maps,Mail",
    "no store still scores and sorts")
end

-- The shared search ranks four levels of match, docs/PLAN-UNIFIED-SEARCH.md, and carries the
-- level as a large step in the score. These four cases pin how the memory reads that. Each was
-- proved by mutation on 2026-10-17, decisions/olm-unified-search.md, failing under the rule it
-- guards against.
local function plainRow(text, id)
  return { title = text, subTitle = "", item = { kind = "app", bundleID = id }, filterText = text }
end

-- A pick at a lower level can still be learned when the best row is not a word start match.
-- lose spells Local Servers in pieces and Closet with one edit, a level lower, yet Closet's score
-- inside its level is near, so the pick decides. A gate on the level itself locked this out.
do
  local a = fresh()
  local l = launcher(a)
  a.note("lose", "app:closet")
  eq(titles(l:_rankCatalog("lose", { plainRow("Local Servers", "servers"), plainRow("Closet", "closet") })),
    "Closet,Local Servers",
    "a pick at a lower level leads when the best row is not a word start match")
end

-- A pick never lifts a row over a best row matching at a word start when it does not, however
-- near their scores. ab starts a word deep in the first row, and Alpha Bravo spells it by
-- initials with a score inside its level that is near the first row's.
do
  local a = fresh()
  local l = launcher(a)
  a.note("ab", "app:alpha")
  local deep = plainRow(string.rep("x", 150) .. " ab", "deep")
  eq(titles(l:_rankCatalog("ab", { deep, plainRow("Alpha Bravo", "alpha") }))
      :gsub("^x+ ab", "deep"), "deep,Alpha Bravo",
    "a pick that is not a word start match never leads over a best row that is")
end

-- Two rows close only because of the step. Both start a word with ma, so both carry the same
-- large step, but the deep one scores well below Mail inside the level. A proportion of the
-- whole score read them as near, which this rules out.
do
  local a = fresh()
  local l = launcher(a)
  a.note("ma", "app:deep")
  local deep = plainRow("Some other words then Map", "deep")
  eq(titles(l:_rankCatalog("ma", { plainRow("Mail", "mail"), deep })), "Mail,Some other words then Map",
    "rows close only because of the step are not near")
end

-- A best row scoring below zero inside its level still admits a pick near it rather than the
-- proportion inverting and dropping every pick. The shared search no longer produces such a
-- score, its gaps are capped well under one matched letter, so a stand in matcher answers the
-- two scores directly, the guard being a property of the rule rather than of today's weights.
do
  local a = fresh()
  local l = launcher(a)
  a.note("zz", "app:second")
  local saved = l._matcher
  l._matcher = function(_, hay)
    if hay == "First" then return 100 - 4.0, 1, -4.0, false end
    return 100 - 4.2, 1, -4.2, false
  end
  local got = l:_rankCatalog("zz", { plainRow("First", "first"), plainRow("Second", "second") })
  l._matcher = saved
  eq(got[1] and got[1].item.bundleID, "second",
    "a pick near a best row scoring below zero still leads")
end

-- Recording is keyed by the same function the timeline uses, so a row with no identity to
-- remember is never recorded and the two memories can never disagree about what a row is.
do
  local a = fresh()
  local l = launcher(a)
  l._stage = { query = function() return "2+2" end }
  l:_noteAssociation({ kind = "calc", name = "4" })
  eq(#a.orderFor("2+2"), 0, "a computed row is never recorded")

  l._stage = { query = function() return "ma" end }
  l:_noteAssociation({ kind = "app", bundleID = "com.apple.Maps" })
  eq(a.orderFor("ma")[1], "app:com.apple.Maps", "an app row is recorded against what was typed")
end

-- Nothing is recorded while another tool's list is being hosted, since the rows on screen are
-- that tool's and the query carries its prefix.
do
  local a = fresh()
  local l = launcher(a)
  l._stage = { query = function() return "x" end }
  l._page = "vpn "
  l:_noteAssociation({ kind = "app", bundleID = "com.apple.Maps" })
  eq(#a.orderFor("vpn x"), 0, "a hosted page records nothing")
end

-- Pruning from the launcher's side, where the predicate is supplied and the truth is the app
-- scan. A tool's own memory has to survive it.
do
  local a = fresh()
  local l = launcher(a)
  a.note("ma", "app:com.apple.Maps")
  a.note("te", "special:textCase")
  l._installedApps = {}
  running = {}
  l:_pruneAssociations()
  eq(#a.orderFor("ma"), 0, "an uninstalled app is forgotten")
  eq(a.orderFor("te")[1], "special:textCase", "a tool's own memory survives the app prune")

  local b = fresh()
  local m = launcher(b)
  b.note("ma", "app:com.apple.Maps")
  m._installedApps = { ["com.apple.Maps"] = true }
  m:_pruneAssociations()
  eq(b.orderFor("ma")[1], "app:com.apple.Maps", "an installed app is kept")

  local c = fresh()
  local n = launcher(c)
  c.note("ma", "app:com.apple.Maps")
  n._installedApps = {}
  running = { { bundleID = function() return "com.apple.Maps" end } }
  n:_pruneAssociations()
  eq(c.orderFor("ma")[1], "app:com.apple.Maps", "a running app outside the scanned roots is kept")
  running = {}
end

print(string.format("%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
