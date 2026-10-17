-- Unit case for the lists that moved onto the shared search in phase three packet two of
-- docs/PLAN-UNIFIED-SEARCH.md, the emoji picker, Obsidian and Processes. BrowserTabs has its own
-- case, browsertabs-settings.lua. Each supplier is loaded by path over stand ins and its rows are
-- ranked through the real rank.lua and match.lua, since what is under test is that the supplier
-- hands back every row with the fields it declares, and that the engine, not the supplier,
-- decides what a query keeps and in what order. The runner reaches this file with a dofile call
-- carrying an absolute path, so it locates itself through debug.getinfo and loads everything by
-- path with loadfile, never require.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local olm = caseDir .. "/../../Spoons/Olm.spoon/"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  elseif detail then
    print("FAIL " .. description .. ", " .. tostring(detail))
  else
    print("FAIL " .. description)
  end
end

local function load(path)
  local chunk, err = loadfile(olm .. path)
  if not chunk then error("could not load " .. path .. ", " .. tostring(err)) end
  return chunk()
end

local rank = load("lib/chooser/rank.lua")
local fuzzy = load("lib/chooser/match.lua").fuzzy

local function titles(list, n)
  local out = {}
  for i, r in ipairs(list) do
    if n and i > n then break end
    out[i] = r.title
  end
  return table.concat(out, ",")
end

local function position(list, title)
  for i, r in ipairs(list) do if r.title == title then return i end end
  return nil
end

--------------------------------------------------------------------------------
-- Emoji
--------------------------------------------------------------------------------

do
  local manifest = load("plugins/emoji/manifest.lua")
  check("the emoji list inherits the shared search", manifest.presentation.matcher == nil
    and manifest.registry.scope.matcher == nil)
  check("the emoji list and its scope keep a hundred rows after ranking",
    manifest.presentation.rowLimit == 100 and manifest.registry.scope.rowLimit == 100)
  local search = { rowLimit = manifest.presentation.rowLimit }

  local P = load("plugins/emoji/providers/hammerspoon.lua")
  P:configure({})
  local data = load("plugins/emoji/data.lua")
  -- A pick memory of our own, so the case never depends on what this machine has picked.
  P._recency = { n = 3, g = { ["⭐"] = { v = 2, k = 3 }, ["🍕"] = { v = 1, k = 1 } } }

  local rows = P:rows("zzz")
  check("the supplier hands every entry over whatever is typed", #rows == #data, #rows)
  check("the recents lead the resting order", rows[1].item == "⭐" and rows[2].item == "🍕",
    titles(rows, 3))
  check("upstream order follows the recents", rows[3].item == data[1].e, titles(rows, 3))
  local seen = 0
  for _, r in ipairs(rows) do if r.item == "⭐" then seen = seen + 1 end end
  check("a recent glyph appears once", seen == 1, seen)

  local grin = rows[3]
  check("an emoji row is titled by its name with its shortcodes under it",
    grin.title == "grinning face" and grin.subTitle == "grinning", grin.subTitle)
  check("its aliases, tags and category are keywords, a category joined at the ampersand",
    grin.keywords == "grinning, smile, happy, smileys & emotion", grin.keywords)
  check("an emoji is tier zero", grin.tier == 0)
  local symbol
  for _, r in ipairs(rows) do if r.tier == 1 then symbol = r break end end
  check("a symbol is tier one", symbol ~= nil)
  check("a row is built once and handed out again", P:rows("")[3] == grin)

  local kept = rank.apply(rows, "", fuzzy, search)
  check("an empty field shows the first hundred of the resting order", #kept == 100
    and kept[1].item == "⭐", #kept)

  kept = rank.apply(rows, "star", fuzzy, search)
  local lastEmoji, firstSymbol = 0, nil
  for i, r in ipairs(kept) do
    if r.tier == 0 then lastEmoji = i elseif not firstSymbol then firstSymbol = i end
  end
  check("every matching emoji sorts above the first matching symbol",
    firstSymbol ~= nil and lastEmoji < firstSymbol, tostring(lastEmoji) .. " " .. tostring(firstSymbol))

  kept = rank.apply(rows, "joy", fuzzy, search)
  local tears, bigEyes = position(kept, "face with tears of joy"), position(kept, "grinning face with big eyes")
  check("a name match leads a glyph found by a keyword", tears ~= nil and bigEyes ~= nil and tears < bigEyes,
    tostring(tears) .. " " .. tostring(bigEyes))
  kept = rank.apply(rows, "food", fuzzy, search)
  check("a category word still finds its group", position(kept, "pizza") ~= nil, titles(kept, 5))

  kept = rank.apply(rows, "katakana vu", fuzzy, search)
  check("a typed query ranks the whole set, so a glyph far past the first hundred is found",
    kept[1] and kept[1].title == "katakana letter vu", titles(kept, 3))
  kept = rank.apply(rows, "a", fuzzy, search)
  check("a broad query is cut to a hundred after ranking", #kept == 100, #kept)
end
