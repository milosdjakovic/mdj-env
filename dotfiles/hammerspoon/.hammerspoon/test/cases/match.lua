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

-- The scattered bag was "Downloads System Preferences Look" until 2026-10-17. Its words spell
-- dspl by their initials, which the four levels rank above a scattered match on Milos's
-- decision, so that row now leads Displays. The case keeps its point with a bag whose words do
-- not spell the query, the shape of the Device Management bug it was written for.
do
  local nearScore = M.fuzzy("dspl", "Displays")
  local scatteredScore = M.fuzzy("dspl", "Device Management sync profile lock")
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

-- The one search, docs/PLAN-UNIFIED-SEARCH.md phase one, as settled on 2026-10-17 after the
-- live test. These rank through the real engine, lib/chooser/rank.lua, since the promise is
-- about the order a list shows, not about a number.

local rank = assert(loadfile(caseDir .. "/../../Spoons/Olm.spoon/lib/chooser/rank.lua"))()
local L = M.LEVEL

local function rows(list)
  local out = {}
  for i, r in ipairs(list) do
    out[i] = type(r) == "string" and { title = r } or r
  end
  return out
end

local function order(query, list)
  local out = {}
  for i, r in ipairs(rank.apply(rows(list), query, M.fuzzy)) do out[i] = r.title end
  return out
end

local function levelOf(query, name) return select(2, M.fuzzy(query, name)) end

-- Each level, with Milos's own examples.
check("lose in Loser is a name word start", levelOf("lose", "Loser") == L.nameStart)
check("lose in Local Servers is name pieces", levelOf("lose", "Local Servers") == L.namePieces)
check("lose inside Enclosed is inside a word", levelOf("lose", "Enclosed") == L.nameInside)
check("os in OLM settings is name pieces", levelOf("os", "OLM settings") == L.namePieces)
check("dd in Docker Desktop is name pieces", levelOf("dd", "Docker Desktop") == L.namePieces)
check("mb in Menu Bar is name pieces", levelOf("mb", "Menu Bar") == L.namePieces)
check("ps in Printers & Scanners is name pieces, the ampersand is no word",
  levelOf("ps", "Printers & Scanners") == L.namePieces)
check("a camel hump offers a piece start without demanding one",
  levelOf("dcp", "DaVinci Control Panels") == L.namePieces
    and levelOf("dvcp", "DaVinci Control Panels") == L.namePieces)
check("dokcer finds Docker with one edit", levelOf("dokcer", "Docker") == L.nameEdit)
check("dcoker finds Docker with one edit", levelOf("dcoker", "Docker") == L.nameEdit)
check("two edits find nothing", M.fuzzy("dkocre", "Docker") == nil)
check("a two letter word with a typo matches nothing", M.fuzzy("dp", "Docker") == nil)
check("a two letter word never matches inside a word", M.fuzzy("do", "Window") == nil)
check("a three letter word does", levelOf("ndo", "Window") == L.nameInside)
check("os is not inside Photos", M.fuzzy("os", "Photos") == nil)
check("pieces never span clause punctuation",
  M.fuzzy("do", "x", { primary = "x", secondary = { { text = "disconnect, or join", visible = true } } }) == nil)

do
  local got = table.concat(order("lose", { "Enclosed", "Local Servers", "Loser" }), ",")
  check("lose gives Loser, then Local Servers, then the row holding lose inside a word",
    got == "Loser,Local Servers,Enclosed", got)
end

for _, pair in ipairs({
  { "os", "OLM settings", "Photos" },
  { "dd", "Docker Desktop", "Hidden Bar" },
  { "mb", "Menu Bar", "Numbers" },
}) do
  local got = order(pair[1], { pair[3], pair[2] })
  check(pair[1] .. " lists " .. pair[2] .. " and not " .. pair[3],
    #got == 1 and got[1] == pair[2], table.concat(got, ","))
end

-- A declared term ranks below every name level, and a hidden one says why the row is listed.
do
  local focus = { title = "Focus", subTitle = "System Settings", keywords = "focus, do not disturb, dnd" }
  local dock = { title = "Dock", subTitle = "System" }
  local got = rank.apply({ focus, dock }, "do", M.fuzzy)
  check("a name match ranks above a declared term match", got[1] and got[1].title == "Dock")
  check("the declared phrase joins the subtitle of a row listed by it",
    got[2] and got[2].subTitle == "System Settings · do not disturb", got[2] and got[2].subTitle)
  check("the row handed in is never changed", focus.subTitle == "System Settings")
  local plain = rank.apply({ focus }, "foc", M.fuzzy)
  check("a row listed by its name shows its subtitle unchanged", plain[1].subTitle == "System Settings")
end

-- Real launcher rows, copied from the live catalog on 2026-10-17 in the shape the launcher now
-- hands them over, the name as filterText and the declared terms as keywords.
do
  local catalog = {
    { title = "Docker", subTitle = "Open", filterText = "Docker" },
    { title = "Docker Desktop", subTitle = "Open · Hyper D", filterText = "Docker Desktop" },
    { title = "Dock", subTitle = "System · hides or reveals the Dock (d, dock)", filterText = "Dock",
      keywords = { "dock, hide, hiding, autohide, show", "hides or reveals the Dock", " (d, dock)" } },
    { title = "Google Docs", subTitle = "Not running", filterText = "Google Docs" },
    { title = "Move Down", subTitle = "Window · Meta S", filterText = "Move Down" },
    { title = "Desktop & Dock", subTitle = "System Settings", filterText = "Desktop & Dock",
      keywords = { "desktop, dock, mission control, stage manager, hot corners" } },
    { title = "Focus", subTitle = "System Settings", filterText = "Focus",
      keywords = { "focus, do not disturb, dnd" } },
    { title = "Screen Time", subTitle = "System Settings", filterText = "Screen Time",
      keywords = { "screen time, limits, downtime" } },
    { title = "Maximize", subTitle = "Window · Meta ↩", filterText = "Maximize" },
    { title = "Move Left", subTitle = "Window · Meta A", filterText = "Move Left" },
    { title = "Center", subTitle = "Window · Meta C", filterText = "Center" },
    { title = "Wi-Fi", subTitle = "Network · see the current network, disconnect, or join another (wi, wifi)",
      filterText = "Wi-Fi", keywords = { "wifi, wi-fi, wireless, network, ssid, join, connect, disconnect",
        "see the current network, disconnect, or join another", " (wi, wifi)" } },
  }
  local got = {}
  for _, r in ipairs(rank.apply(catalog, "do", M.fuzzy)) do got[r.title] = true end
  local keep = { "Docker", "Docker Desktop", "Dock", "Google Docs", "Move Down", "Desktop & Dock",
    "Focus", "Screen Time" }
  local missing = {}
  for _, t in ipairs(keep) do if not got[t] then missing[#missing + 1] = t end end
  check("do keeps every row that names it", #missing == 0, table.concat(missing, ","))
  check("do drops every window command and Wi-Fi",
    not got["Maximize"] and not got["Move Left"] and not got["Center"] and not got["Wi-Fi"])
end

-- The measurement this work started from. Four real Chrome addresses and a made up title that
-- spells the word scattered, none of which match any more.
do
  local titles = {
    "seven little things",
    "https://resources.anthropic.com/hubfs/The-Complete-Guide-to-Building-Skill-for-Claude.pdf",
    "https://vicert-testing.canvasmedical.com/login?next=%2Fpatients",
    "https://vicert-testing.canvasmedical.com/login?next=%2Fpatient%2Fda85ab13b6cc4b0fa3a40c97ccbc7f96%2Fedit",
    "https://www.loom.com/share/5092de42f8f64542a66faf090599b20c",
    "Settings",
  }
  local got = order("settings", titles)
  check("settings lists Settings alone, the four addresses no longer match",
    #got == 1 and got[1] == "Settings", table.concat(got, " | "))
end

check("se in Base is not a match, two letters never match inside a word", M.fuzzy("se", "Base") == nil)

-- Each word separately, and every word required.
check("a two word query matches its words in either order", M.fuzzy("hello there", "there, hello") ~= nil)
check("a two word query drops a row holding only one of its words", M.fuzzy("hello there", "hello") == nil)
check("google chrome finds nothing in a row titled Chrome", M.fuzzy("google chrome", "Chrome") == nil)
check("a word never matches across the name and a secondary field together",
  M.fuzzy("ab", "x", { primary = "Alpha", secondary = { { text = "Beta", visible = true } } }) == nil)

-- Long bodies match a word only whole, at its best occurrence.
do
  local filler = string.rep("lorem ipsum dolor sit amet ", 12)
  local body = filler .. "the Chooser draws its rows " .. filler
  check("a long body is past the bound this case relies on", #body > 256, tostring(#body))
  check("a long body matches a word it holds at a word start", levelOf("chooser", body) == L.nameStart)
  check("a long body matches a word inside a word from three letters", levelOf("hoose", body) == L.nameInside)
  check("a long body never matches in pieces", M.fuzzy("tcd", body) == nil)
  check("a long body does not forgive a typo", M.fuzzy("choosre", body) == nil)
  check("a short name does match the same pieces", M.fuzzy("tcd", "the Chooser draws") ~= nil)
  check("a long body prefers a word start to an earlier hit inside a word",
    levelOf("ipsum", "xipsum " .. body) == L.nameStart)
end

-- Symbols, the review of 2026-10-17. A word with no letter or digit is a plain substring
-- anywhere in the row and adds no level, and a word starting with symbols matches on its word
-- part with the symbols somewhere in the row.
do
  local function names(query, list) return table.concat(order(query, list), ",") end
  check("date & time finds Date & Time", names("date & time", { "Date & Time", "Time Machine" }) == "Date & Time")
  check("desktop & dock finds Desktop & Dock", names("desktop & dock", { "Desktop & Dock", "Dock" }) == "Desktop & Dock")
  check("touch id & password finds Touch ID & Password",
    names("touch id & password", { "Touch ID & Password", "Passwords" }) == "Touch ID & Password")
  for _, q in ipairs({ "2 + 3", "100 - 20", "10 % of 50", "$5", "-5", "#1" }) do
    check("a query row whose name is the query matches " .. q, M.fuzzy(q, q) ~= nil)
  end
  check("an ampersand alone adds no level",
    select(2, M.fuzzy("date &", "Date & Time")) == select(2, M.fuzzy("date", "Date & Time")))
  check("a symbol the row does not hold drops it", M.fuzzy("date %", "Date & Time") == nil)
  check("$5 needs the dollar sign somewhere in the row", M.fuzzy("$5", "5 items") == nil)
end

-- The tighter typo, the review of 2026-10-17. One edit applies to a word start match only,
-- never touches the first letter, and never makes the last letter wrong or extra.
do
  check("docekr finds Docker, two neighbours swapped", levelOf("docekr", "Docker") == L.nameEdit)
  check("an edit never applies to pieces", M.fuzzy("lsoe", "Local Servers") == nil)
  check("an edit never touches the first letter", M.fuzzy("xocker", "Docker") == nil)
  -- Closet holds lose inside a word, level D, which the design keeps for words of three letters
  -- and more. It no longer reaches the edit level through an inserted first letter.
  check("lose finds Closet only inside a word, never by an edit", levelOf("lose", "Closet") == L.nameInside)
  check("note does not find Notifications", M.fuzzy("note", "Notifications") == nil)
  check("show does not find Shortcuts", M.fuzzy("show", "Shortcuts") == nil)
  check("wifi does not find Window Size", M.fuzzy("wifi", "Window Size") == nil)
  check("mail does not find Manage clipboard history", M.fuzzy("mail", "Manage clipboard history") == nil)
  check("focs does not find Lock Screen or Local Servers",
    M.fuzzy("focs", "Lock Screen") == nil and M.fuzzy("focs", "Local Servers") == nil)
  check("focs does find Focus", M.fuzzy("focs", "Focus") ~= nil)
  local got = table.concat(order("lose", { "Closet", "Login Items & Extensions", "OLM settings",
    "Lock Screen", "Local Servers", "Loser" }), ",")
  check("lose lists Loser, Local Servers, then Closet inside a word, and none of the edit rows",
    got == "Loser,Local Servers,Closet", got)
end

-- What a row shows for a hidden phrase, the review of 2026-10-17.
do
  local focus = { title = "Focus", subTitle = "System Settings", keywords = "focus, do not disturb, dnd" }
  local got = rank.apply({ focus }, "do not", M.fuzzy)
  check("two words in one hidden phrase show it once",
    got[1] and got[1].subTitle == "System Settings · do not disturb", got[1] and got[1].subTitle)
  local pieces = { title = "Screen", subTitle = "", keywords = "lock, screen time limits" }
  got = rank.apply({ pieces }, "stl", M.fuzzy)
  check("a pieces match shows the phrase its pieces started in",
    got[1] and got[1].subTitle == "screen time limits", got[1] and got[1].subTitle)
  local some = { title = "Clock", subTitle = "Sometimes", keywords = "time" }
  got = rank.apply({ some }, "time", M.fuzzy)
  check("a phrase inside a longer subtitle word is still shown",
    got[1] and got[1].subTitle == "Sometimes · time", got[1] and got[1].subTitle)
  local menu = { title = "Find Next", subTitle = "Edit ▸ Find", filterText = "Find Next",
    keywords = "Edit ▸ Find" }
  got = rank.apply({ menu }, "edit", M.fuzzy)
  check("a phrase the subtitle shows between triangles is not repeated",
    got[1] and got[1].subTitle == "Edit ▸ Find", got[1] and got[1].subTitle)
  check("pieces never span a triangle", M.fuzzy("ef", "x", { primary = "x",
    secondary = { { text = "Edit ▸ Find", visible = true } } }) == nil)
  check("pieces never span a middle dot", M.fuzzy("ns", "x", { primary = "x",
    secondary = { { text = "Network · see", visible = true } } }) == nil)
end
