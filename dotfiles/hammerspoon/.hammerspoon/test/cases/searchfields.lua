-- Unit case for the three search fields phase three of docs/PLAN-UNIFIED-SEARCH.md added, a
-- row's names, a presentation's searchText and its rowLimit, through the real rank engine in
-- Olm.spoon/lib/chooser/rank.lua, the real shared search in lib/chooser/match.lua and the real
-- check in lib/registrar.lua. The stage, the provider, the query scope and the action panel
-- threading them are proved in stage-search.lua and actionpanel.lua. The runner reaches this
-- file with a dofile call carrying an absolute path, so this file locates itself through
-- debug.getinfo, and the modules under test are only loaded.
--
-- Each check prints one line, PASS or FAIL followed by a plain description.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local olmDir = caseDir .. "/../../Spoons/Olm.spoon/"

local function load(path)
  local chunk, err = loadfile(olmDir .. path)
  if not chunk then
    print("FAIL load Olm.spoon/" .. path .. ", " .. tostring(err))
    return nil
  end
  return chunk()
end
local rank, match, registrar = load("lib/chooser/rank.lua"), load("lib/chooser/match.lua"), load("lib/registrar.lua")
if not rank or not match or not registrar then return end
local fuzzy = match.fuzzy
local LEVEL = match.LEVEL

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

-- The fuzzy answers for one row, read through the engine's own field rule.
local function graded(q, row)
  return fuzzy(q, rank.haystackOf(row), rank.fieldsOf(row))
end

--------------------------------------------------------------------------------
-- names
--------------------------------------------------------------------------------

-- Each word takes its best level across the title and the names, so github pull finds a tab
-- titled Pull request whose host is github.com, each word at a name word start in a different
-- name, which the title alone could never answer.
do
  local tab = { title = "Pull request", names = { "github.com", "https://github.com/olm/pull/12" } }
  local score, level, _, atStart = graded("github pull", tab)
  check("two words land in two names, each at a word start",
    score ~= nil and level == 2 * LEVEL.nameStart and atStart == true,
    string.format("score %s level %s", tostring(score), tostring(level)))
  check("without names the title alone does not answer github pull",
    graded("github pull", { title = "Pull request" }) == nil)
end

-- A word takes the strongest level any name gives it, a word start in a name over inside a
-- word of the title.
do
  local row = { title = "Repository", names = { "Positron" } }
  local _, level = graded("pos", row)
  check("a word takes a name's word start over the title's inside a word",
    level == LEVEL.nameStart, "level " .. tostring(level))
  local _, alone = graded("pos", { title = "Repository" })
  check("the title alone gives pos inside a word", alone == LEVEL.nameInside, "level " .. tostring(alone))
end

-- One word never spans two names. github in pieces needs git and hub in one name, as the
-- start of consecutive words, so a row naming them apart does not answer it.
do
  local apart = { title = "Alpha", names = { "Git", "Hub" } }
  local together = { title = "Alpha", names = { "Git Hub" } }
  check("one word never spans two names", graded("github", apart) == nil)
  local _, level = graded("github", together)
  check("the same pieces inside one name answer it", level == LEVEL.namePieces, "level " .. tostring(level))
  local titleAndName = { title = "Git", names = { "Hub" } }
  check("one word never spans the title and a name either", graded("github", titleAndName) == nil)
end

-- A row is never scored higher for having more names than an equal row with fewer. Extra names
-- that match no better, the same name again, or nothing at all leave every answer unchanged.
do
  local plain = { title = "Docker" }
  local q = "dock"
  local s0, l0, w0 = graded(q, plain)
  local bad = {}
  for label, row in pairs({
    unrelated = { title = "Docker", names = { "zzz", "yyy", "Nothing here" } },
    same = { title = "Docker", names = { "Docker", "Docker" } },
    weaker = { title = "Docker", names = { "Docker Desktop for Mac", "Moby Dock" } },
    many = { title = "Docker", names = { "Docker", "Docker", "Docker", "Docker", "Docker", "Docker" } },
  }) do
    local s, l, w = graded(q, row)
    if s ~= s0 or l ~= l0 or w ~= w0 then
      bad[#bad + 1] = string.format("%s %s against %s", label, tostring(s), tostring(s0))
    end
  end
  check("more names never score a row above an equal row with fewer", #bad == 0, table.concat(bad, "; "))
  local got = titles(rank.apply({
    { title = "Docker", names = { "Docker", "Docker", "Docker" } }, { title = "Docker" },
  }, q, fuzzy))
  check("two equal rows with one and four names keep the supplier's order", got == "Docker,Docker")
  -- Two words in two names score what each name gives, never more than the two best.
  local spread = { title = "Docker", names = { "Pull", "Pull", "Pull" } }
  local sa = graded("docker pull", spread)
  local sb = graded("docker pull", { title = "Docker", names = { "Pull" } })
  check("a word found in several names counts once", sa == sb, tostring(sa) .. " against " .. tostring(sb))
end

-- filterText still replaces the title as the primary, and names add to it.
do
  local row = { title = "Shown title", filterText = "Hidden name", names = { "Extra" } }
  check("filterText and a name answer together", graded("hidden extra", row) ~= nil)
  check("the title filterText replaced is still not searched", graded("shown", row) == nil)
  check("a name answers with an empty filterText", graded("extra", { title = "T", filterText = "", names = { "Extra" } }) ~= nil)
end

-- A long name follows the 256 byte rule, a word start or inside a word, never pieces.
do
  local body = string.rep("lorem ipsum ", 30) .. "quick Brown zebra"
  local row = { title = "Entry", names = { body } }
  local _, level = graded("zebra", row)
  check("a long name matches at a word start", level == LEVEL.nameStart, "level " .. tostring(level))
  _, level = graded("ebra", row)
  check("a long name matches inside a word", level == LEVEL.nameInside, "level " .. tostring(level))
  check("a long name never matches in pieces", graded("qbz", row) == nil)
  local short = { title = "Entry", names = { "quick Brown zebra" } }
  _, level = graded("qbz", short)
  check("the same pieces in a short name do", level == LEVEL.namePieces, "level " .. tostring(level))
end

-- A symbol word is looked for in the names too, and a one string strategy never sees names.
do
  local row = { title = "Note", names = { "a & b" } }
  check("a symbol word is found in a name", graded("note &", row) ~= nil)
  check("substring reads only title and subtitle, never names",
    rank.apply({ { title = "Note", names = { "zebra" } } }, "zebra", match.substring)[1] == nil)
end

-- A names field of the wrong shape is read as absent, and an entry that is not a string is
-- skipped.
do
  check("names as a string is read as absent", graded("zebra", { title = "Entry", names = "zebra" }) == nil)
  check("a name that is not a string is skipped", graded("zebra", { title = "Entry", names = { 42, "Zebra" } }) ~= nil)
end

--------------------------------------------------------------------------------
-- searchText
--------------------------------------------------------------------------------

-- The last word of the field, the way FileSearch reads ~/dev .js foo as a root, an extension
-- and the word to rank by. The grammar is the plugin's, this stands in for it.
local function lastWord(text)
  local words = {}
  for w in text:gmatch("%S+") do
    if not w:match("^[~/.]") then words[#words + 1] = w end
  end
  return table.concat(words, " ")
end

local files = {
  { title = "Back", pinned = true },
  { title = "notes.txt" },
  { title = "foo.js" },
  { title = "bar.js" },
  { title = "food.md" },
}

do
  local got = titles(rank.apply(files, "~/dev .js foo", fuzzy, { searchText = lastWord }))
  check("a structured query ranks by what searchText answers", got == "foo.js,food.md,Back", "got " .. got)
  got = titles(rank.apply(files, "~/dev .js foo", fuzzy))
  check("the same query without searchText ranks the raw text and finds nothing", got == "Back", "got " .. got)
end

do
  local got, reason = rank.apply(files, "~/dev .js", fuzzy, { searchText = lastWord })
  check("an empty answer keeps the supplier's order, pinned rows in place",
    titles(got) == "Back,notes.txt,foo.js,bar.js,food.md" and reason == nil, "got " .. titles(got))
  got = rank.apply(files, "x", fuzzy, { searchText = function() return "   " end })
  check("an answer of spaces only keeps the supplier's order", titles(got) == "Back,notes.txt,foo.js,bar.js,food.md",
    "got " .. titles(got))
end

do
  local got, reason = rank.apply(files, "foo", fuzzy, { searchText = function() error("broken grammar") end })
  check("a searchText that raises keeps the supplier's order and says why",
    titles(got) == "Back,notes.txt,foo.js,bar.js,food.md" and type(reason) == "string" and reason:find("broken grammar", 1, true) ~= nil,
    "got " .. titles(got) .. " reason " .. tostring(reason))
  got, reason = rank.apply(files, "foo", fuzzy, { searchText = function() return 7 end })
  check("a searchText answering no string keeps the supplier's order and says why",
    titles(got) == "Back,notes.txt,foo.js,bar.js,food.md" and type(reason) == "string", "got " .. titles(got))
end

do
  local asked = 0
  local got = rank.apply(files, "", fuzzy, { searchText = function() asked = asked + 1 return "foo" end })
  check("an empty field never asks searchText", asked == 0 and titles(got) == "Back,notes.txt,foo.js,bar.js,food.md")
  got = rank.apply(files, "~/dev foo", false, { searchText = lastWord })
  check("matcher false keeps the supplier's order whatever searchText says",
    titles(got) == "Back,notes.txt,foo.js,bar.js,food.md", "got " .. titles(got))
  got = rank.apply(files, "~/dev foo", fuzzy, { searchText = "foo" })
  check("a searchText that is not a function is read as absent", titles(got) == "Back", "got " .. titles(got))
end

--------------------------------------------------------------------------------
-- rowLimit
--------------------------------------------------------------------------------

do
  local items = {
    { title = "Back", pinned = true },
    { title = "Docs" },
    { title = "42", fromQuery = true },
    { title = "Doc Viewer" },
    { title = "Dock" },
    { title = "Docker" },
    { title = "New", pinned = true },
  }
  local got = titles(rank.apply(items, "doc", fuzzy, { rowLimit = 2 }))
  check("a typed query keeps the best rows up to the limit and every kept row",
    got == "42,Docs,Dock,Back,New", "got " .. got)
  got = titles(rank.apply(items, "", fuzzy, { rowLimit = 2 }))
  check("an empty query keeps the first rows up to the limit and every kept row in place",
    got == "Back,Docs,42,Doc Viewer,New", "got " .. got)
  got = titles(rank.apply(items, "doc", fuzzy, { rowLimit = 1, searchText = function(t) return t end }))
  check("the limit applies after searchText", got == "42,Docs,Back,New", "got " .. got)
  got = titles(rank.apply(items, "doc", false, { rowLimit = 1 }))
  check("the limit applies when the supplier owns its filtering", got == "Back,Docs,42,New", "got " .. got)
  got = titles(rank.apply(items, "doc", fuzzy, { rowLimit = 0 }))
  check("a limit that is not a positive whole number is read as absent",
    got == "42,Docs,Dock,Docker,Doc Viewer,Back,New", "got " .. got)
  got = titles(rank.apply(items, "doc", fuzzy, { rowLimit = 10 }))
  check("a limit above the matches cuts nothing", got == "42,Docs,Dock,Docker,Doc Viewer,Back,New", "got " .. got)
end

--------------------------------------------------------------------------------
-- Rows and searches setting none of the new fields rank exactly as before
--------------------------------------------------------------------------------

-- The same corpus rankvocabulary.lua checks against the old rule, ranked here with no search,
-- an empty search and a search whose fields are both absent, every list identical by identity.
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
    { title = "Back", pinned = true },
    { title = "Alpha", keywords = "do not disturb" },
    { title = "128", fromQuery = true },
    { title = "Settings", subTitle = "Docker settings" },
  }
  local bad = {}
  for _, q in ipairs({ "", "do", "doc", "d", "lo se", "do disturb", "ock", "dokcer", "settings" }) do
    for name, m in pairs({ fuzzy = fuzzy, substring = match.substring }) do
      local want = rank.apply(corpus, q, m)
      for label, search in pairs({ empty = {}, absent = { searchText = nil, rowLimit = nil } }) do
        local got = rank.apply(corpus, q, m, search)
        local same = #want == #got
        for i = 1, #want do if want[i] ~= got[i] then same = false end end
        if not same then bad[#bad + 1] = name .. " " .. label .. " " .. q end
      end
    end
  end
  check("a search with no field set ranks exactly as no search", #bad == 0, table.concat(bad, "; "))
  local fields = rank.fieldsOf({ title = "Docker" })
  check("a row with no names hands the search no names", fields.names == nil)
end

--------------------------------------------------------------------------------
-- The registrar
--------------------------------------------------------------------------------

do
  local module = { rows = function() return {} end, select = function() end, query = function(_, t) return t end }
  local function validate(fields)
    local p = {
      rows = { member = "rows", call = "method" },
      select = { member = "select", call = "method" },
    }
    for k, v in pairs(fields) do p[k] = v end
    local logged = {}
    local out = registrar.validatePresentation("demo", "demo", { presentation = p }, { demo = module },
      { log = function(_, line) logged[#logged + 1] = line end })
    return out, table.concat(logged, "; ")
  end
  local out, logged = validate({ searchText = { member = "query", call = "method" } })
  check("a searchText member spec resolves to a function",
    type(out.searchText) == "function" and out.searchText("~/dev foo") == "~/dev foo" and logged == "", logged)
  out, logged = validate({})
  check("a presentation declaring no searchText carries none", out.searchText == nil and out.rows ~= nil)
  for label, bad in pairs({ ["a bare string"] = "query", ["a number"] = 3,
    ["a member that does not resolve"] = { member = "missing", call = "method" },
    ["a member with no call kind"] = { member = "query" } }) do
    out, logged = validate({ searchText = bad })
    check("a searchText given as " .. label .. " is refused with a line naming it",
      out.rows == nil and logged:find("searchText", 1, true) ~= nil, logged)
  end
  out, logged = validate({ rowLimit = 100 })
  check("a whole rowLimit is carried through", out.rowLimit == 100 and logged == "", logged)
  for label, bad in pairs({ zero = 0, ["a fraction"] = 1.5, ["a string"] = "100", ["negative"] = -1 }) do
    out, logged = validate({ rowLimit = bad })
    check("a rowLimit given as " .. label .. " is refused with a line naming it",
      out.rows == nil and logged:find("rowLimit", 1, true) ~= nil, logged)
  end
end

--------------------------------------------------------------------------------
-- a title before a further name at the same level
--------------------------------------------------------------------------------

-- At one level a word found in the title or filterText leads the same level found only in a
-- further name, decided 2026-10-17 after the review of phase three. It sits inside the level,
-- under the phrase bonus and over the row's own bonus, so a recent row never lifts over one
-- whose title holds the word. And a further name never lends a row its score at a level the
-- title already reaches, unless the word spells that name whole. The emoji checks rank the
-- real rows, built by plugins/emoji/providers/hammerspoon.lua from data.lua over a stand in hs,
-- since a hand made row once passed while the real data put person facepalming first for face,
-- its shortcode facepalm lending the row the score of a word filling the start of a short field.
do
  local function ranked(q, list, search)
    return titles(rank.apply(list, q, fuzzy, search))
  end
  local stub = { settings = { get = function() return nil end, set = function() end } }
  local chunk = assert(loadfile(olmDir .. "plugins/emoji/providers/hammerspoon.lua", "t",
    setmetatable({ hs = stub }, { __index = _G })))
  local backend = chunk()
  backend:configure({})
  local emoji = backend:rows()
  check("the real emoji rows load", #emoji > 1000, tostring(#emoji))
  local function top(q, n)
    local list = rank.apply(emoji, q, fuzzy)
    local out = {}
    for i = 1, n do out[i] = list[i] and list[i].title end
    return out, list
  end
  local function place(list, title)
    for i, r in ipairs(list) do if r.title == title then return i end end
    return nil
  end
  local function rowNamed(title)
    for _, r in ipairs(emoji) do if r.title == title then return r end end
  end

  -- face leads with names that start with face, the shorter first, and a name holding face only
  -- in a later word, whatever its shortcode, comes after every one of them.
  local faces, list = top("face", 5)
  check("face lists face exhaling first on the real rows", faces[1] == "face exhaling", table.concat(faces, ","))
  local allStart = true
  for i = 1, 5 do allStart = allStart and faces[i]:sub(1, 5) == "face " end
  check("the first five names for face all start with face", allStart, table.concat(faces, ","))
  local lastStart = 0
  for i, r in ipairs(list) do if r.title:sub(1, 5) == "face " then lastStart = i end end
  check("person facepalming comes after every name starting with face",
    place(list, "person facepalming") > lastStart, tostring(place(list, "person facepalming")))
  check("the fist whose shortcode is facepunch comes after person facepalming",
    place(list, "oncoming fist") > place(list, "person facepalming"))
  check("face with tongue, the shorter name, leads face with monocle",
    place(list, "face with tongue") < place(list, "face with monocle"))

  -- flag lists the flags, never carp streamer whose shortcode is flags, before a flag.
  local flags
  flags, list = top("flag", 3)
  check("flag lists the country flags first", flags[1]:sub(1, 6) == "flag: " and flags[3]:sub(1, 6) == "flag: ",
    table.concat(flags, ","))
  local carp = place(list, "carp streamer")
  check("carp streamer comes after every name holding flag", carp ~= nil and carp > place(list, "pirate flag"),
    tostring(carp))

  -- grin, a shortcode spelled whole counts as the name, so the beaming face leads.
  local grins = top("grin", 3)
  check("grin lists the beaming face whose shortcode is grin first",
    grins[1] == "beaming face with smiling eyes", table.concat(grins, ","))
  check("then the shorter grinning names, cat before face",
    grins[2] == "grinning cat" and grins[3] == "grinning face", table.concat(grins, ","))

  local fist, palm = rowNamed("oncoming fist"), rowNamed("person facepalming")

  local onHost = { title = "Pull request", names = { "github.com", "https://github.com/x/pull/1" }, bonus = 1 }
  local inTitle = { title = "Pull request github", names = {} }
  got = ranked("github pull", { onHost, inTitle })
  check("github pull lists the title holding github first, whatever the other's bonus",
    got == "Pull request github,Pull request", got)

  -- The rule never crosses a level. A word start found only in a name still leads the same
  -- word inside a word of a title.
  local startInName = { title = "Repository", names = { "Positron" } }
  local insideTitle = { title = "Composer" }
  got = ranked("pos", { insideTitle, startInName })
  check("a name word start still leads a title inside a word", got == "Repository,Composer", got)

  -- The score alone orders the same way, for a consumer reading only the first answer, and a
  -- further name word never costs a row its level.
  check("the score alone puts the title match first", graded("face", palm) > graded("face", fist))
  check("and so does the score of a name that starts with face",
    graded("face", rowNamed("face with tongue")) > graded("face", palm))
  check("the score alone keeps a name word start over a title inside a word",
    graded("pos", startInName) > graded("pos", insideTitle))

  local _, _, _, _, _, fromNames = graded("face", fist)
  check("fuzzy answers how many words came only from a further name", fromNames == 1, tostring(fromNames))
  _, _, _, _, _, fromNames = graded("face", palm)
  check("a word in the title came from no further name", fromNames == 0, tostring(fromNames))

  -- A row with no names answers within exactly as before, the words' scores plus one spread for
  -- the phrase, which the launcher's nearness reads as a proportion.
  local row = { title = "Focus", keywords = "do not disturb" }
  local _, _, within = graded("do not", row)
  local _, _, a = graded("do", row)
  local _, _, b = graded("not", row)
  local spread = (2 * 11 + 256 * 0.02) + (3 * 11 + 256 * 0.02)
  check("a row with no names answers the within it always did",
    math.abs(within - (a + b + spread)) < 1e-9, string.format("%.3f against %.3f", within, a + b + spread))
end

--------------------------------------------------------------------------------
-- a category typed run together across its ampersand
--------------------------------------------------------------------------------

-- The run together key drops a standalone ampersand, so smileysemo finds a row declaring
-- smileys & emotion, and the key with the ampersand still answers smileys&emo.
do
  local grin = { title = "grinning face", keywords = "smile, happy, smileys & emotion" }
  local pizza = { title = "pizza", keywords = "food, food & drink" }
  for _, q in ipairs({ "smileysemo", "smileysemotion", "smileys&emo" }) do
    local got = titles(rank.apply({ pizza, grin }, q, fuzzy))
    check(q .. " finds the smileys & emotion row and only it", got == "grinning face", got)
  end
  local got = titles(rank.apply({ pizza, grin }, "fooddr", fuzzy))
  check("fooddr finds food & drink", got == "pizza", got)
  check("an ampersand inside a word stays in the key, atandt does not find AT&T",
    fuzzy("atandt", "x", { primary = "x", secondary = { { text = "AT&T", declared = true } } }) == nil)
  check("and at&t still does", fuzzy("at&t", "x", { primary = "x", secondary = { { text = "AT&T", declared = true } } }) ~= nil)
end
