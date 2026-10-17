-- Unit case for the three row fields Olm.spoon/lib/chooser/rank.lua applies that say where a
-- row goes rather than what it answers to, pinned, tier and bonus, docs/PLAN-UNIFIED-SEARCH.md
-- phase two. It lives apart from chooserrank.lua because it ranks through the real shared
-- search in lib/chooser/match.lua, since what bonus may and may not cross is defined by that
-- search's level sums and phrase bonus, and a hand written matcher would prove nothing about
-- them. The runner reaches this file with a dofile call carrying an absolute path, so this
-- file locates itself through debug.getinfo, and the modules under test are only loaded.
--
-- Each check prints one line, PASS or FAIL followed by a plain description.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local libDir = caseDir .. "/../../Spoons/Olm.spoon/lib/chooser/"

local function load(name)
  local chunk, err = loadfile(libDir .. name)
  if not chunk then
    print("FAIL load Olm.spoon/lib/chooser/" .. name .. ", " .. tostring(err))
    return nil
  end
  return chunk()
end
local rank, match = load("rank.lua"), load("match.lua")
if not rank or not match then return end
local fuzzy = match.fuzzy

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  elseif detail then
    print("FAIL " .. description .. ", " .. detail)
  else
    print("FAIL " .. description)
  end
end

local function titles(list)
  local out = {}
  for i = 1, #list do out[i] = list[i].title end
  return table.concat(out, ",")
end

-- How many times the query occurs in the haystack, a matcher answering only a score.
local function countMatcher(query, hay)
  local q = query:lower()
  local n = select(2, hay:lower():gsub(q, q))
  if n == 0 then return nil end
  return n
end

-- The fuzzy answers for one row, so a case can state what it relies on before relying on it.
local function graded(q, row)
  return fuzzy(q, rank.haystackOf(row), rank.fieldsOf(row))
end

-- Pinned rows lead when the supplier gives them before every unpinned row and trail
-- otherwise, both in the supplier's order, while the rows between them are ranked.
do
  local items = {
    { title = "Back", pinned = true },
    { title = "Up", pinned = true },
    { title = "One a" },
    { title = "Settings", pinned = true },
    { title = "Three aaa" },
    { title = "New", pinned = true },
  }
  local got = titles(rank.apply(items, "a", countMatcher))
  check("pinned rows lead or trail by where the supplier put them, the rest ranked between",
    got == "Back,Up,Three aaa,One a,Settings,New", "got " .. got)
end

-- A pinned row survives a query nothing else matches, and is never asked about.
do
  local asked = {}
  local recording = function(query, hay) asked[#asked + 1] = hay; return nil end
  local items = { { title = "Alpha" }, { title = "Save as", pinned = true }, { title = "Beta" } }
  local got = titles(rank.apply(items, "zzz", recording))
  check("a pinned row survives a query that drops every other row",
    got == "Save as", "got " .. got)
  check("a pinned row is never scored", #asked == 2, "asked " .. #asked .. " times")
end

-- On an empty query a pinned row keeps its exact place in the supplier's order.
do
  local items = { { title = "Alpha" }, { title = "Back", pinned = true }, { title = "Beta" } }
  local got = titles(rank.apply(items, "", fuzzy))
  check("an empty query leaves a pinned row where the supplier put it",
    got == "Alpha,Back,Beta", "got " .. got)
end

-- A smaller tier leads whatever the match, Docker matching ock only inside a word and
-- Ockham at the start of its name.
do
  local a, b = { title = "Ockham", tier = 1 }, { title = "Docker" }
  local la, lb = select(2, graded("ock", a)), select(2, graded("ock", b))
  check("Ockham matches ock at a higher level than Docker", la > lb, la .. " against " .. lb)
  local got = titles(rank.apply({ a, b }, "ock", fuzzy))
  check("a smaller tier leads a row that matched better", got == "Docker,Ockham", "got " .. got)
  got = titles(rank.apply({ { title = "One a" }, { title = "Three aaa", tier = 2 } }, "a", countMatcher))
  check("a smaller tier leads a better score from a score only matcher",
    got == "One a,Three aaa", "got " .. got)
end

-- A bonus reorders two rows at the same level sum. Doc Viewer scores below Docs for doc, by
-- where the word landed alone.
do
  local docs, viewer = { title = "Docs" }, { title = "Doc Viewer", bonus = 0.5 }
  local sd, ld = graded("doc", docs)
  local sv, lv = graded("doc", viewer)
  check("Docs and Doc Viewer sit at one level for doc, Docs scoring higher",
    ld == lv and sd > sv, string.format("levels %s %s scores %s %s", ld, lv, sd, sv))
  local got = titles(rank.apply({ docs, viewer }, "doc", fuzzy))
  check("a bonus leads inside one level sum against a better score", got == "Doc Viewer,Docs", "got " .. got)
end

-- A bonus never lifts a row over one at a higher level sum.
do
  local got = titles(rank.apply({ { title = "Docker", bonus = 1 }, { title = "Ockham" } }, "ock", fuzzy))
  check("a full bonus never lifts a lower level row over a higher one", got == "Ockham,Docker", "got " .. got)
end

-- A bonus never crosses the phrase bonus. Alpha holds do disturb in one declared phrase, Beta
-- holds the two words in two, at the same level sum.
do
  local alpha = { title = "Alpha", keywords = "do not disturb" }
  local beta = { title = "Beta", keywords = { "do", "disturb" }, bonus = 1 }
  local _, la, _, _, pa = graded("do disturb", alpha)
  local _, lb, _, _, pb = graded("do disturb", beta)
  check("Alpha and Beta sit at one level sum, Alpha alone with the phrase bonus",
    la == lb and pa == true and pb == false, string.format("levels %s %s phrase %s %s", la, lb, pa, pb))
  local got = titles(rank.apply({ beta, alpha }, "do disturb", fuzzy))
  check("a full bonus never lifts a row over one with the phrase bonus", got == "Alpha,Beta", "got " .. got)
end

-- A bonus above one or below zero is clamped, so 5 and 1 are equal and the score decides,
-- and -3 and 0 likewise.
do
  local got = titles(rank.apply({ { title = "Docs", bonus = 1 }, { title = "Doc Viewer", bonus = 5 } }, "doc", fuzzy))
  check("a bonus above one counts as one", got == "Docs,Doc Viewer", "got " .. got)
  got = titles(rank.apply({ { title = "Doc Viewer" }, { title = "Docs", bonus = -3 } }, "doc", fuzzy))
  check("a bonus below zero counts as zero", got == "Docs,Doc Viewer", "got " .. got)
end

-- A field of the wrong type is read as absent.
do
  local items = {
    { title = "Doc Viewer", bonus = "1", tier = "-1" },
    { title = "Back", pinned = "true" },
    { title = "Docs", tier = 0 / 0 },
  }
  local got = titles(rank.apply(items, "doc", fuzzy))
  check("a wrongly typed pinned, tier or bonus is ignored", got == "Docs,Doc Viewer", "got " .. got)
end

-- A matcher answering only a score said nothing about the kind of match, so its score still
-- decides before a bonus does, and a bonus orders only its equal scores.
do
  local got = titles(rank.apply({ { title = "One a", bonus = 1 }, { title = "Three aaa" } }, "a", countMatcher))
  check("a bonus never overrides a score only matcher's score", got == "Three aaa,One a", "got " .. got)
  got = titles(rank.apply({ { title = "Two a" }, { title = "One a", bonus = 0.1 } }, "a", countMatcher))
  check("a bonus orders a score only matcher's equal scores", got == "One a,Two a", "got " .. got)
end

-- Rows that set none of the three fields rank exactly as before the fields existed, score
-- descending and the supplier's index ascending, checked against that rule written out here
-- over a mixed list, real queries, the shared search and a score only matcher.
do
  local corpus = {
    { title = "Docker", subTitle = "Running" },
    { title = "Docs" },
    { title = "Doc Viewer", keywords = "pdf, reader" },
    { title = "Focus", subTitle = "System Settings", keywords = "focus, do not disturb, dnd" },
    { title = "Local Servers", keywords = "dev server, port, docker" },
    { title = "Downloads" },
    { title = "Window Left", filterText = "Window Left" },
    { title = "Screen Time", keywords = "downtime" },
    { title = "Beta", keywords = { "do", "disturb" } },
    { title = "Alpha", keywords = "do not disturb" },
    { title = "Ockham" },
    { title = "Docs" },
    { title = "Settings", subTitle = "Docker settings" },
    { title = "Local Servers" },
  }
  local function oldOrder(items, q, matcher)
    local e = {}
    for i, it in ipairs(items) do
      local s = matcher(q, rank.haystackOf(it), rank.fieldsOf(it))
      if s ~= nil then e[#e + 1] = { item = it, score = s, idx = i } end
    end
    table.sort(e, function(a, b)
      if a.score ~= b.score then return a.score > b.score end
      return a.idx < b.idx
    end)
    local out = {}
    for i, x in ipairs(e) do out[i] = x.item end
    return out
  end
  local bad = {}
  for _, q in ipairs({ "do", "doc", "d", "s", "lo se", "do disturb", "ock", "dokcer", "settings", "o" }) do
    for name, m in pairs({ fuzzy = fuzzy, substring = match.substring, count = countMatcher }) do
      local want, got = oldOrder(corpus, q, m), rank.apply(corpus, q, m)
      local same = #want == #got
      for i = 1, #want do if want[i] ~= got[i] then same = false end end
      if not same then bad[#bad + 1] = name .. " " .. q .. " got " .. titles(got) .. " want " .. titles(want) end
    end
  end
  check("rows setting no new field rank exactly as score then index did", #bad == 0, table.concat(bad, "; "))
end
