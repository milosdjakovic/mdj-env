-- Unit case for Olm.spoon/lib/chooser/rank.lua, the ranking policy pulled out of
-- lib/chooser/providers/native.lua's own _build during the canvas provider phase,
-- docs/BRIEF-CANVAS-PROVIDER.md section zero, so a second provider can share the exact
-- same order rather than carry a ranking policy of its own. The runner reaches this
-- file with a dofile call carrying an absolute path, so this file in turn locates
-- itself the same way, through debug.getinfo, and derives the module path from there.
-- No absolute path is ever written down here, and the module under test is only
-- loaded, never edited.
--
-- Each check prints one line, PASS or FAIL followed by a plain description, and the
-- runner counts and reports from those lines alone, the same convention every case in
-- this directory already follows.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local modulePath = caseDir .. "/../../Spoons/Olm.spoon/lib/chooser/rank.lua"

local moduleChunk, loadErr = loadfile(modulePath)
if not moduleChunk then
  print("FAIL load Olm.spoon/lib/chooser/rank.lua, " .. tostring(loadErr))
  return
end
local rank = moduleChunk()

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    if detail then
      print("FAIL " .. description .. ", " .. detail)
    else
      print("FAIL " .. description)
    end
  end
end

local function titles(list)
  local out = {}
  for i = 1, #list do
    out[i] = list[i].title
  end
  return table.concat(out, ",")
end

-- A matcher scoring a row by how many times the query occurs in the haystack, nil when
-- it does not occur at all. Plain and predictable rather than fuzzy, so a test can
-- state the expected order by hand rather than trusting lib/chooser/match.lua's own
-- strategy, which this case does not exercise at all since rank.lua takes a matcher as
-- a plain function and never names one of its own.
local function countMatcher(query, hay)
  local q = query:lower()
  local n = select(2, hay:lower():gsub(q, q))
  if n == 0 then return nil end
  return n
end

-- With no matcher at all, every candidate is kept in the supplier's own order.

do
  local items = {
    { title = "Alpha" },
    { title = "Beta" },
    { title = "Gamma" },
  }
  local out = rank.apply(items, "a", nil)
  check(
    "no matcher keeps every candidate in the supplier's own order",
    titles(out) == "Alpha,Beta,Gamma",
    "got " .. titles(out)
  )
end

-- An empty query keeps the supplier's own order even with a matcher present, since
-- there is nothing yet to score against.

do
  local items = {
    { title = "Alpha" },
    { title = "Beta" },
    { title = "Gamma" },
  }
  local out = rank.apply(items, "", countMatcher)
  check(
    "an empty query keeps every candidate in the supplier's own order",
    titles(out) == "Alpha,Beta,Gamma",
    "got " .. titles(out)
  )
end

-- matcher set to false means the supplier owns its own filtering, so rank.apply keeps
-- every candidate exactly as given regardless of the query.

do
  local items = {
    { title = "Alpha" },
    { title = "Beta" },
    { title = "Gamma" },
  }
  local out = rank.apply(items, "a", false)
  check(
    "matcher set to false keeps every candidate in the supplier's own order",
    titles(out) == "Alpha,Beta,Gamma",
    "got " .. titles(out)
  )
end

-- A matcher dropping a candidate removes it from the answer rather than scoring it low.

do
  local items = {
    { title = "Alpha" },
    { title = "Beta" },
    { title = "Gamma" },
  }
  local out = rank.apply(items, "z", countMatcher)
  check(
    "a matcher that scores every candidate nil drops all of them",
    #out == 0,
    "got " .. tostring(#out) .. " rows"
  )
end

-- Score ordering, a candidate scoring higher sorts before one scoring lower.

do
  local items = {
    { title = "One a" },
    { title = "Two aa" },
    { title = "Three aaa" },
  }
  local out = rank.apply(items, "a", countMatcher)
  check(
    "candidates sort by score descending",
    titles(out) == "Three aaa,Two aa,One a",
    "got " .. titles(out)
  )
end

-- The tie break preserves the supplier's own order for two equal scores, which is what
-- lets a stable secondary order such as the launcher's recency still show through. A
-- matcher answering the same real score for every row isolates the tie break itself
-- rather than any behaviour of a particular scoring function.

do
  local items = {
    { title = "First", filterText = "same" },
    { title = "Second", filterText = "same" },
    { title = "Third", filterText = "same" },
  }
  local sameScore = function(query, hay) return 1 end
  local out = rank.apply(items, "a", sameScore)
  check(
    "two candidates scoring equal keep the supplier's original order",
    titles(out) == "First,Second,Third",
    "got " .. titles(out)
  )
end

-- filterText wins over title and subtitle as the haystack the matcher searches.

do
  local seen = {}
  local recordingMatcher = function(query, hay)
    seen[#seen + 1] = hay
    return 1
  end
  local items = {
    { title = "Displayed Title", subTitle = "Displayed Sub", filterText = "hidden keyword" },
  }
  rank.apply(items, "a", recordingMatcher)
  check(
    "filterText is the haystack when a row carries one",
    seen[1] == "hidden keyword",
    "got " .. tostring(seen[1])
  )
end

do
  local seen = {}
  local recordingMatcher = function(query, hay)
    seen[#seen + 1] = hay
    return 1
  end
  local items = {
    { title = "Displayed Title", subTitle = "Displayed Sub" },
  }
  rank.apply(items, "a", recordingMatcher)
  check(
    "title and subtitle joined with a space is the haystack when there is no filterText",
    seen[1] == "Displayed Title Displayed Sub",
    "got " .. tostring(seen[1])
  )
end
