-- Unit case for the four row fields Olm.spoon/lib/chooser/rank.lua applies that say where a
-- row goes rather than what it answers to, pinned, fromQuery, tier and bonus,
-- docs/PLAN-UNIFIED-SEARCH.md
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

-- Under a typed query every pinned row trails the ranked rows in the supplier's order, wherever
-- the supplier put it, so a Back row given first never takes the first row, which is where the
-- highlight and Enter land.
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
  check("pinned rows trail the ranked rows under a typed query, in the supplier's order",
    got == "Three aaa,One a,Back,Up,Settings,New", "got " .. got)
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

-- On an empty query, and with no matcher, every row keeps its exact place in the supplier's
-- order, so a Back row given first leads and takes the fresh highlight.
do
  local items = {
    { title = "Back", pinned = true }, { title = "Alpha" }, { title = "42", fromQuery = true },
    { title = "Beta" },
  }
  local got = titles(rank.apply(items, "", fuzzy))
  check("an empty query leaves pinned and fromQuery rows where the supplier put them",
    got == "Back,Alpha,42,Beta", "got " .. got)
  got = titles(rank.apply(items, "alpha", false))
  check("no matcher leaves every row where the supplier put it", got == "Back,Alpha,42,Beta", "got " .. got)
end

-- Under a typed query every fromQuery row leads, in the supplier's order, ahead of a ranked
-- row that matched at the top level, and is never scored. A row setting both kinds is a
-- fromQuery row.
do
  local asked = {}
  local recording = function(query, hay, fields)
    asked[#asked + 1] = hay
    return fuzzy(query, hay, fields)
  end
  local items = {
    { title = "Back", pinned = true },
    { title = "Docs" },
    { title = "128", fromQuery = true },
    { title = "Doc Viewer" },
    { title = "Converting", fromQuery = true, pinned = true },
  }
  local got = titles(rank.apply(items, "doc", recording))
  check("fromQuery rows lead the ranked rows and pinned rows trail them",
    got == "128,Converting,Docs,Doc Viewer,Back", "got " .. got)
  check("a fromQuery row is never scored", #asked == 2, "asked " .. #asked .. " times")
  got = titles(rank.apply(items, "zzz", fuzzy))
  check("fromQuery rows survive a query nothing matches, and pinned rows after them",
    got == "128,Converting,Back", "got " .. got)
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

-- M.before is a strict weak ordering when graded and ungraded entries meet. a and b are graded at
-- one level, a with the bonus and the lower score, c is ungraded between their scores. Comparing
-- c by score against a and b while a and b compare by bonus made a cycle.
do
  local a = { graded = true, level = 3, phrase = false, bonus = 1, score = 10, idx = 1, tier = 0 }
  local b = { graded = true, level = 3, phrase = false, bonus = 0, score = 30, idx = 2, tier = 0 }
  local c = { graded = false, level = 0, phrase = false, bonus = 0, score = 20, idx = 3, tier = 0 }
  local cycle = rank.before(a, b) and rank.before(b, c) and rank.before(c, a)
  check("graded and ungraded entries never compare in a cycle", not cycle,
    string.format("a<b %s b<c %s c<a %s", rank.before(a, b), rank.before(b, c), rank.before(c, a)))
end

-- A randomized mixed list, graded and ungraded, tiers, phrases and bonuses, checked over every
-- triple for transitivity and every pair for asymmetry, with a fixed seed so a failure repeats.
do
  math.randomseed(20261017)
  local entries = {}
  for i = 1, 36 do
    local graded = math.random() < 0.5
    entries[i] = {
      graded = graded, level = graded and math.random(0, 4) or 0,
      phrase = graded and math.random() < 0.3, bonus = ({ 0, 0, 0.5, 1 })[math.random(1, 4)],
      score = math.random(0, 40), tier = math.random() < 0.2 and 1 or 0, idx = i,
    }
  end
  local before, broken = rank.before, nil
  for i = 1, #entries do
    local x = entries[i]
    if before(x, x) then broken = broken or ("irreflexivity at " .. i) end
    for j = 1, #entries do
      local y = entries[j]
      if before(x, y) and before(y, x) then broken = broken or ("asymmetry at " .. i .. "," .. j) end
      if before(x, y) then
        for k = 1, #entries do
          if before(y, entries[k]) and not before(x, entries[k]) then
            broken = broken or ("transitivity at " .. i .. "," .. j .. "," .. k)
          end
        end
      end
    end
  end
  check("M.before is transitive and asymmetric over a randomized mixed list", broken == nil, broken)
end
