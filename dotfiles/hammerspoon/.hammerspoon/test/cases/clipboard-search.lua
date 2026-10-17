-- Unit case for the clipboard history on the shared search, phase three packet two B of
-- docs/PLAN-UNIFIED-SEARCH.md. The history rows declare their fields and the shared engine ranks
-- them, so plugins/clipboard/manager/ui.lua is loaded by path over a stand in hs and a stand in
-- store, its supplier asked for rows, and those rows ranked through the real rank.lua and
-- match.lua with the presentation's searchText, exactly as the stage does. The live hs is never
-- touched. The runner reaches this file with a dofile call carrying an absolute path, so it
-- locates itself through debug.getinfo and loads everything by path with loadfile, never require.

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

local function load(path, env)
  local chunk, err
  if env then chunk, err = loadfile(olm .. path, "t", env) else chunk, err = loadfile(olm .. path) end
  if not chunk then error("could not load " .. path .. ", " .. tostring(err)) end
  return chunk()
end

local rank = load("lib/chooser/rank.lua")
local fuzzy = load("lib/chooser/match.lua").fuzzy

local function titles(list)
  local out = {}
  for i, r in ipairs(list) do out[i] = r.title end
  return table.concat(out, ",")
end

local function position(list, title)
  for i, r in ipairs(list) do if r.title == title then return i end end
  return nil
end

-- What the row build reaches in hs, an icon per file type and a thumbnail per image, each a
-- plain table, and a path that always exists.
local fakeHs = {
  image = {
    imageFromPath = function(path) return { path = path } end,
    iconForFileType = function(t) return { type = t } end,
    iconForFile = function(p) return { file = p } end,
  },
  fs = { attributes = function() return { mode = "file" } end },
}
local env = setmetatable({ hs = fakeHs }, { __index = _G })

-- The history, newest first as store.all answers it.
local history = {
  { kind = "text", title = "alpha beta gamma", text = "alpha beta gamma", preview = "16 chars", ts = 9 },
  { kind = "text", title = "scratch", text = "scratch\nwe are redeploying the stack tonight",
    preview = "43 chars", ts = 8 },
  { kind = "file", title = "report.pdf", files = { { path = "/tmp/q3/report.pdf" } }, preview = "file", ts = 7 },
  { kind = "text", title = "the report is late", text = "the report is late", preview = "18 chars", ts = 6 },
  { kind = "text", title = "deploy notes", text = "deploy notes\nstep one", preview = "21 chars", ts = 5 },
  { kind = "image", title = "Image 640x480", thumb = "/tmp/t.png", preview = "image", ts = 4 },
  { kind = "url", title = "https://example.com/x", text = "https://example.com/x", preview = "URL", ts = 3 },
  { kind = "text", title = "alpha", text = "alpha", preview = "5 chars", ts = 2 },
}
local store = { all = function() return history end }
-- The time each entry's age text next changes, by its ts, for the row cache cases below.
ageChanges = {}

local prune = load("plugins/clipboard/manager/prune.lua")
prune.configure({ store = store })
local UI = load("plugins/clipboard/manager/ui.lua", env)
UI.configure({
  store = store,
  util = {
    relTime = function() return "now" end,
    -- When the age text next reads differently, far ahead unless a case moves it.
    relTimeChanges = function(ts) return (ageChanges[ts] or math.huge) end,
    fileExt = function(p) return (p:match("%.([^./]+)$") or ""):lower() end,
  },
  media = { fileBadge = function() return nil end },
  prune = prune,
  ui = { tokens = function() return { radius = { nested = 0 } } end },
})

local manifest = load("plugins/clipboard/manifest.lua")
check("the clipboard history inherits the shared search", manifest.presentation.matcher == nil
  and manifest.surface.matcher == nil)
check("the presentation declares searchText", type(manifest.presentation.searchText) == "table"
  and manifest.presentation.searchText.member == "manager.searchText")
check("the presentation keeps two hundred rows after ranking", manifest.presentation.rowLimit == 200,
  tostring(manifest.presentation.rowLimit))
-- The manager loads the monitor and the store, which reach the live hs at load, so its forward
-- is read as text rather than loaded.
local managerFile = assert(io.open(olm .. "plugins/clipboard/manager/init.lua"))
local managerText = managerFile:read("a")
managerFile:close()
check("the manager forwards searchText to the ui",
  managerText:find("function M.searchText(raw)\n  return ui.searchText(raw)\nend", 1, true) ~= nil)

local search = { searchText = UI.searchText }
local function ranked(query)
  return rank.apply(UI.rows(query), query, fuzzy, search)
end

--------------------------------------------------------------------------------
-- The fields
--------------------------------------------------------------------------------

local rows = UI.rows("")
check("the supplier hands every entry over in the store's order", #rows == #history
  and rows[1].title == "alpha beta gamma" and rows[8].title == "alpha", titles(rows))
check("a row filters on its title, so its kind and age subtitle is not searched",
  rows[1].filterText == "alpha beta gamma")
check("a text row names its whole body", #(rows[2].names or {}) == 1 and (rows[2].names or {})[1] == history[2].text)
check("a file row names its path", (rows[3].names or {})[1] == "/tmp/q3/report.pdf")
check("an image row has no names", type(rows[6].names) == "table" and #rows[6].names == 0)
check("the newest row has bonus one and the oldest one over the count",
  rows[1].bonus == 1 and rows[8].bonus == 1 / 8, tostring(rows[1].bonus) .. " " .. tostring(rows[8].bonus))
check("the supplier reads no query, a typed word keeps every row", #UI.rows("zebra") == #history)

--------------------------------------------------------------------------------
-- The grammar through searchText
--------------------------------------------------------------------------------

check("searchText answers what follows a type prefix", UI.searchText("file report") == "report"
  and UI.searchText("img: cat") == "cat", UI.searchText("file report"))
check("searchText answers plain text unchanged", UI.searchText("report late") == "report late")
check("the type prefix narrows the candidates to that kind", #UI.rows("file report") == 1
  and UI.rows("file report")[1].title == "report.pdf")
local kept = ranked("file report")
check("a prefixed query ranks the kind by the rest", titles(kept) == "report.pdf", titles(kept))
kept = ranked("report")
check("without a prefix a path and a body both answer",
  position(kept, "report.pdf") ~= nil and position(kept, "the report is late") ~= nil, titles(kept))
kept = ranked("img ")
check("a prefix alone lists that kind in the store's order", titles(kept) == "Image 640x480", titles(kept))

--------------------------------------------------------------------------------
-- What is searched and how it orders
--------------------------------------------------------------------------------

kept = ranked("chars")
check("the preview is not searched, chars finds nothing", #kept == 0, titles(kept))
kept = ranked("tonight")
check("a word deep in a body is found", titles(kept) == "scratch", titles(kept))
kept = ranked("deploy")
check("a first line match leads a newer entry matching inside a word of its body",
  position(kept, "deploy notes") == 1 and position(kept, "scratch") == 2, titles(kept))
kept = ranked("alpha")
check("among equal matches the newer leads, even where the older matched its whole title",
  titles(kept) == "alpha beta gamma,alpha", titles(kept))

-- An append rewrites an entry's body as a new string, and the next search finds the new words,
-- since the row names its body afresh and the long body memo is keyed by the string.
local before = history[8].text
history[8].text = before .. "\nappended zucchini"
UI.entryChanged(history[8])
kept = ranked("zucchini")
check("an appended entry is searched by its new text", titles(kept) == "alpha", titles(kept))
history[8].text = before
UI.entryChanged(history[8])

--------------------------------------------------------------------------------
-- The row cache
--------------------------------------------------------------------------------

-- A keystroke reuses each entry's row rather than building it and its names again, decided
-- 2026-10-17. Only the bonus is written each time.
local first = UI.rows("a")
local again = UI.rows("ab")
check("a keystroke hands the same row tables over again", first[2] == again[2] and first[5] == again[5])
check("and the same names table", first[2].names == again[2].names)
history[2].title = "scratch renamed"
UI.entryChanged(history[2])
again = UI.rows("ab")
check("an entry that changed is built again", again[2] ~= first[2] and again[2].title == "scratch renamed",
  again[2].title)
check("and the others are kept", again[5] == first[5])
history[2].title = "scratch"
UI.entryChanged(history[2])
-- The cached row keeps the time its age text was built to change at, so the entry is built
-- again here with that time already past.
ageChanges[history[4].ts] = 0
UI.entryChanged(history[4])
first = UI.rows("a")
again = UI.rows("ab")
check("a row whose age text would now read differently is built again", again[4] ~= first[4]
  and again[5] == first[5])
ageChanges[history[4].ts] = nil
first = UI.rows("a")
UI.onPresent()
again = UI.rows("a")
check("an open builds every row again, so icons and badges are current", again[1] ~= first[1])
UI.onClose()
check("the bonus still follows the store's order from the cache", again[1].bonus == 1 and again[8].bonus == 1 / 8)
table.insert(history, 1, { kind = "text", title = "newest", text = "newest", preview = "6 chars", ts = 10 })
local grown = UI.rows("a")
check("a cached row takes its new place in a grown store", grown[2] == again[1]
  and grown[2].bonus == 8 / 9 and grown[9].bonus == 1 / 9, tostring(grown[2].bonus))
table.remove(history, 1)

--------------------------------------------------------------------------------
-- The manage history page
--------------------------------------------------------------------------------

UI.manageHistory()
check("on the page searchText answers nothing", UI.searchText("4d") == "")
local page = UI.rows("4d")
kept = rank.apply(page, "4d", fuzzy, search)
check("a typed duration keeps the page's two rows in their order", #kept == 2
  and kept[1] == page[1] and kept[2] == page[2], titles(kept))
page = UI.rows("100")
kept = rank.apply(page, "100", fuzzy, search)
check("a typed count keeps them too", #kept == 2 and kept[1].title == page[1].title, titles(kept))
page = UI.rows("4d1")
kept = rank.apply(page, "4d1", fuzzy, search)
check("a half typed span keeps its hint row", #kept == 1 and kept[1].title == "Keep typing", titles(kept))
UI.leaveManageHistory()
check("leaving the page gives searchText back", UI.searchText("4d") == "4d")
