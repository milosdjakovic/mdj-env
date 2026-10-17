-- Unit case for Olm.spoon/lib/chooser/match.lua, the shared matching policy every chooser in
-- this config injects. The runner reaches this file with a dofile call carrying an absolute
-- path, so this file in turn locates itself the same way, through debug.getinfo, and
-- derives the module path from there. No absolute path is ever written down here, and the
-- module under test is only loaded, never edited.
--
-- Each check prints one line, PASS or FAIL followed by a plain description, and the
-- runner counts and reports from those lines alone. There is no shared assertion library
-- between this file and the runner, since one case file does not yet earn one.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local modulePath = caseDir .. "/../../Spoons/Olm.spoon/lib/chooser/match.lua"

local moduleChunk, loadErr = loadfile(modulePath)
if not moduleChunk then
  print("FAIL load Olm.spoon/lib/chooser/match.lua, " .. tostring(loadErr))
  return
end
local M = moduleChunk()

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

-- The fuzzy strategy.

check(
  "fuzzy matches when every query letter is present",
  M.fuzzy("dspl", "Displays") ~= nil
)

check(
  "fuzzy returns nil when the query letters are mostly absent",
  M.fuzzy("zzzzzz", "Displays") == nil
)

do
  local nearScore = M.fuzzy("dspl", "Displays")
  local scatteredScore = M.fuzzy("dspl", "Downloads System Preferences Look")
  check(
    "a near contiguous match outranks the same letters scattered across separate words",
    nearScore ~= nil and (scatteredScore == nil or nearScore > scatteredScore),
    string.format("near=%s scattered=%s", tostring(nearScore), tostring(scatteredScore))
  )
end

check(
  "fuzzy still matches through one wrong letter inside an otherwise good query",
  M.fuzzy("dqsplays", "Displays") ~= nil
)

check(
  "a low scoring scattered alignment falls under the relevance floor",
  M.fuzzy("dspl", "trackpad system preferences panel click") == nil
)

-- The substring strategy.

check(
  "substring matches a plain substring",
  M.substring("lay", "Displays") ~= nil
)

check(
  "substring returns nil for a non substring",
  M.substring("xyz", "Displays") == nil
)

check(
  "every substring match scores the same so the supplier's order survives",
  M.substring("d", "Displays") == M.substring("splay", "Displays")
)

-- The words strategy.

check(
  "words keeps a row when every query word is present in any order",
  M.words("there hello", "hello everyone there") ~= nil
)

check(
  "words drops a row when one query word is missing",
  M.words("hello xyz", "hello everyone there") == nil
)

check(
  "words matches on a prefix of a word",
  M.words("hel", "hello") ~= nil
)

-- The one search, docs/PLAN-UNIFIED-SEARCH.md phase one. These rank through the real engine,
-- lib/chooser/rank.lua, since the promise is about the order a list shows, not about a number.

local rank = assert(loadfile(caseDir .. "/../../Spoons/Olm.spoon/lib/chooser/rank.lua"))()

local function rows(titles)
  local out = {}
  for i, t in ipairs(titles) do out[i] = { title = t, filterText = t } end
  return out
end

local function order(query, titles)
  local out = {}
  for i, r in ipairs(rank.apply(rows(titles), query, M.fuzzy)) do out[i] = r.title end
  return out
end

local function placeOf(list, title)
  for i, t in ipairs(list) do if t == title then return i end end
  return nil
end

-- Contiguous first. se whole in a row beats s then e scattered, whatever the scattered row
-- scored before, and a whole match mid word still beats every scattered one.
do
  local got = order("se", { "Some example", "Safe", "Screen Time Sharing", "Base", "Sending", "Settings" })
  local joined = table.concat(got, ",")
  check(
    "se ranks the rows holding se whole above every row matching s then e scattered",
    (placeOf(got, "Settings") or 99) <= 3 and (placeOf(got, "Sending") or 99) <= 3
      and (placeOf(got, "Base") or 99) == 3,
    joined
  )
  check(
    "inside the whole tier a word start still beats a match mid word",
    (placeOf(got, "Base") or 0) > (placeOf(got, "Settings") or 99)
      and (placeOf(got, "Base") or 0) > (placeOf(got, "Sending") or 99),
    joined
  )
end

-- The measurement this work started from. Four real Chrome addresses that do not hold the
-- word, and a made up title that spells it scattered, all below the row that holds it.
do
  local addresses = {
    "https://resources.anthropic.com/hubfs/The-Complete-Guide-to-Building-Skill-for-Claude.pdf",
    "https://vicert-testing.canvasmedical.com/login?next=%2Fpatients",
    "https://vicert-testing.canvasmedical.com/login?next=%2Fpatient%2Fda85ab13b6cc4b0fa3a40c97ccbc7f96%2Fedit",
    "https://www.loom.com/share/5092de42f8f64542a66faf090599b20c",
  }
  local titles = { "seven little things" }
  for _, a in ipairs(addresses) do titles[#titles + 1] = a end
  titles[#titles + 1] = "Settings"
  local got = order("settings", titles)
  check(
    "settings ranks Settings first, above the four addresses and the scattered title",
    got[1] == "Settings",
    table.concat(got, " | ")
  )
  local whole = M.fuzzy("settings", "Settings")
  local beaten = true
  for _, t in ipairs(titles) do
    if t ~= "Settings" then
      local s = M.fuzzy("settings", t)
      if s ~= nil and s >= whole then beaten = false end
    end
  end
  check("every row without the word scores below the row holding it, or not at all", beaten)
end

-- The keyword bag case recorded at the weights. dspl is scattered in every row here, so this
-- proves the ordering inside the scattered tier is unchanged.
do
  local got = order("dspl", {
    "trackpad system preferences panel click", "Downloads System Preferences Look", "Displays" })
  check(
    "dspl still finds Displays first and the Trackpad keyword bag not at all",
    got[1] == "Displays" and placeOf(got, "trackpad system preferences panel click") == nil,
    table.concat(got, ",")
  )
end

check("a swapped pair of letters still matches", M.fuzzy("settigns", "Settings") ~= nil)

-- Each word separately, and every word required.
check("a two word query matches its words in either order", M.fuzzy("hello there", "there, hello") ~= nil)
check("a two word query drops a row holding only one of its words", M.fuzzy("hello there", "hello") == nil)
check(
  "a row holding both words whole beats one holding only one of them whole",
  (M.fuzzy("hello there", "hello everyone there") or 0) > (M.fuzzy("hello there", "help others there") or 0)
)

-- Long bodies match a word only where it sits whole, and never by subsequence or typo.
do
  local filler = string.rep("lorem ipsum dolor sit amet ", 12)
  local body = filler .. "the Chooser draws its rows " .. filler
  check("a long body is past the bound this case relies on", #body > 256, tostring(#body))
  check("a long body matches a word it holds whole, ignoring case", M.fuzzy("chooser", body) ~= nil)
  check("a long body matches two words held whole anywhere", M.fuzzy("rows chooser", body) ~= nil)
  check("a long body does not match the same word as a subsequence", M.fuzzy("chsr", body) == nil)
  check("a long body does not forgive a typo", M.fuzzy("choosre", body) == nil)
  check("a short row still matches the same subsequence", M.fuzzy("chsr", "the Chooser") ~= nil)
  check(
    "asking the same long body twice answers the same score, the lowered copy is kept faithfully",
    M.fuzzy("chooser", body) == M.fuzzy("chooser", body)
  )
end
