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
  check("its shortcode aliases are names of the row",
    type(grin.names) == "table" and #grin.names == 1 and grin.names[1] == "grinning",
    table.concat(grin.names or {}, "/"))
  check("its tags and category are keywords, a category joined at the ampersand",
    grin.keywords == "smile, happy, smileys & emotion", grin.keywords)
  check("an emoji is tier zero", grin.tier == 0)
  local symbol
  for _, r in ipairs(rows) do if r.tier == 1 then symbol = r break end end
  check("a symbol is tier one", symbol ~= nil)
  check("a symbol has no names, its synonym line stays a keyword",
    symbol ~= nil and #symbol.names == 0 and symbol.keywords ~= "", symbol and symbol.keywords)
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
  kept = rank.apply(rows, "grin", fuzzy, search)
  check("an exact alias leads an emoji whose name only starts with it",
    kept[1] and kept[1].title == "beaming face with smiling eyes"
      and position(kept, "grinning face") == 2, titles(kept, 3))
  kept = rank.apply(rows, "thumbsup", fuzzy, search)
  check("a shortcode finds its emoji by name", kept[1] and kept[1].title == "thumbs up", titles(kept, 3))
  kept = rank.apply(rows, "food", fuzzy, search)
  check("a category word still finds its group", position(kept, "pizza") ~= nil, titles(kept, 5))

  kept = rank.apply(rows, "katakana vu", fuzzy, search)
  check("a typed query ranks the whole set, so a glyph far past the first hundred is found",
    kept[1] and kept[1].title == "katakana letter vu", titles(kept, 3))
  kept = rank.apply(rows, "a", fuzzy, search)
  check("a broad query is cut to a hundred after ranking", #kept == 100, #kept)
end

--------------------------------------------------------------------------------
-- Obsidian
--------------------------------------------------------------------------------

-- The plugin reads Obsidian's registry and walks the vault through hs, so it is loaded into an
-- environment of its own whose hs is a stand in over a vault that exists only here. The live
-- hs is never touched.
local function obsidianOver(tree, registry, remembered)
  local function attributes(path, field)
    local node = tree[path]
    if node == nil then return nil end
    if field == "mode" then return node == "dir" and "directory" or "file" end
    if field == "modification" then return type(node) == "number" and node or 0 end
  end
  local function dir(path)
    local names = {}
    for p in pairs(tree) do
      local parent, name = p:match("^(.*)/([^/]+)$")
      if parent == path then names[#names + 1] = name end
    end
    table.sort(names)
    local i = 0
    return function() i = i + 1 return names[i] end, nil
  end
  local noop = function() end
  local fakeHs = {
    logger = { new = function() return setmetatable({}, { __index = function() return noop end }) end },
    json = { read = function(path)
      if path:sub(-#"obsidian.json") == "obsidian.json" then return registry end
      if path:sub(-#"app.json") == "app.json" then return { userIgnoreFilters = { "Archive/" } } end
    end },
    fs = { attributes = attributes, dir = dir },
    timer = { doAfter = function() return { stop = noop } end, secondsSinceEpoch = function() return 0 end },
  }
  local env = setmetatable({ hs = fakeHs }, { __index = _G })
  local chunk = assert(loadfile(olm .. "plugins/obsidian/init.lua", "t", env))
  local M = chunk()
  local recency = {
    rankOf = function(key) return remembered[key] end,
    order = function(items, keyOf)
      local lead, rest = {}, {}
      for _, it in ipairs(items) do
        if remembered[keyOf(it)] then lead[#lead + 1] = it else rest[#rest + 1] = it end
      end
      table.sort(lead, function(a, b) return remembered[keyOf(a)] < remembered[keyOf(b)] end)
      for _, it in ipairs(rest) do lead[#lead + 1] = it end
      return lead
    end,
    touch = noop,
  }
  M:configure({ recency = recency })
  return M
end

do
  local manifest = load("plugins/obsidian/manifest.lua")
  check("the Obsidian list and its scope inherit the shared search", manifest.presentation.matcher == nil
    and manifest.registry.scope.matcher == nil)
  check("both keep two hundred notes after ranking", manifest.presentation.rowLimit == 200
    and manifest.registry.scope.rowLimit == 200)

  local tree = {
    ["/v/Work"] = "dir",
    ["/v/Work/Meeting.md"] = 100,
    ["/v/Work/Prevention.md"] = 90,
    ["/v/Work/Projects"] = "dir",
    ["/v/Work/Projects/Alpha plan.md"] = 300,
    ["/v/Work/Projects/Plan review.md"] = 200,
    ["/v/Work/Archive"] = "dir",
    ["/v/Work/Archive/Plan old.md"] = 400,
    ["/v/Work/Daily"] = "dir",
    ["/v/Work/Daily/Planning.md"] = 50,
  }
  local registry = { vaults = { w = { path = "/v/Work", open = true } } }
  local remembered = { ["w/Prevention.md"] = 1, ["w/Projects/Alpha plan.md"] = 2 }
  local M = obsidianOver(tree, registry, remembered)

  local rows = M.rows("")
  check("an empty field keeps the resting order, opened notes first, then newest, excluded last",
    titles(rank.apply(rows, "", fuzzy)) == "Prevention,Alpha plan,Plan review,Meeting,Planning,Plan old",
    titles(rows))
  local alpha = rows[position(rows, "Alpha plan")]
  check("a note row is titled by its name with its folder under it",
    alpha.title == "Alpha plan" and alpha.subTitle == "Projects", alpha.subTitle)
  check("a note at the vault root names the vault", rows[position(rows, "Meeting")].subTitle == "Work")
  check("the most recently opened note has bonus one and the next a half",
    rows[1].bonus == 1 and alpha.bonus == 0.5, tostring(rows[1].bonus) .. " " .. tostring(alpha.bonus))
  check("a note never opened here has no bonus", rows[position(rows, "Meeting")].bonus == nil)
  check("an excluded note is tier one", rows[position(rows, "Plan old")].tier == 1
    and alpha.tier == nil)
  check("the supplier hands every note over whatever is typed", #M.rows("zzz") == 6 + 2, #M.rows("zzz"))

  local kept = rank.apply(M.rows("plan"), "plan", fuzzy)
  check("recency orders equal matches, the opened Alpha plan above Plan review and Planning",
    kept[1].title == "Alpha plan", titles(kept))
  check("an excluded note is the last note however well it matches",
    kept[4].title == "Plan old", titles(kept))
  check("the create and search rows are pinned and trail the notes",
    kept[5].title == "New note \"plan\"" and kept[6].title == "Search notes for \"plan\""
      and kept[5].pinned == true and kept[6].pinned == true, titles(kept))

  kept = rank.apply(M.rows("rev"), "rev", fuzzy)
  check("a better match beats a recent one, Plan review at a word start above the opened Prevention",
    kept[1].title == "Plan review" and position(kept, "Prevention") == 2, titles(kept))
  kept = rank.apply(M.rows("projects"), "projects", fuzzy)
  check("a folder word finds the notes in it", position(kept, "Alpha plan") ~= nil
    and position(kept, "Plan review") ~= nil and position(kept, "Meeting") == nil, titles(kept))
  kept = rank.apply(M.rows("zzz"), "zzz", fuzzy)
  check("a query matching no note leaves the two action rows", titles(kept)
    == "New note \"zzz\",Search notes for \"zzz\"", titles(kept))

  local none = obsidianOver({}, { vaults = {} }, {})
  kept = rank.apply(none.rows("plan"), "plan", fuzzy)
  check("with no vault the explaining row stays whatever is typed",
    #kept == 1 and kept[1].title == "Obsidian knows no vaults yet", titles(kept))
end

--------------------------------------------------------------------------------
-- Processes
--------------------------------------------------------------------------------

-- The chooser loads util, metrics, preview and icons beside it. It is loaded into an environment
-- of its own where those loads answer stand ins, except util, which is pure and loaded for real,
-- so no canvas is drawn, no sampler runs and the live hs is never touched.
do
  local manifest = load("plugins/processes/manifest.lua")
  check("the Processes list inherits the shared search", manifest.presentation.matcher == nil
    and manifest.surface.matcher == nil)

  local noop = function() end
  local heat = {}
  local stubs = {
    ["icons.lua"] = { badge = function() return nil, nil end, emoji = function() return nil end, refresh = noop },
    -- Every row reads thirty three percent, so a query of 33 would match a live figure if one
    -- were searched. score is what a heat sort orders by.
    ["metrics.lua"] = { reading = function(key) return { cpu = 33, rss = 2048, score = heat[key] } end,
      configure = noop, start = noop, stop = noop },
    ["preview.lua"] = { show = noop, hide = noop, dock = noop, destroy = noop, refresh = noop,
      configure = noop, isEnabled = function() return false end },
  }
  local fakeHs = {
    logger = { new = function() return setmetatable({}, { __index = function() return noop end }) end },
    timer = { doAfter = function() return { stop = noop } end },
    alert = { show = noop },
  }
  local env
  env = setmetatable({
    hs = fakeHs,
    loadfile = function(path)
      local name = path:match("([^/]+)$")
      if stubs[name] then return function() return stubs[name] end end
      return loadfile(path, "t", env)
    end,
  }, { __index = _G })
  local M = assert(loadfile(olm .. "plugins/processes/chooser.lua", "t", env))()

  -- The scan's own order, port holders first, then the container, then the portless watcher.
  local scanned = {
    { key = "a", title = "node", ports = { 3000 }, runtime = "node", pid = 10,
      cwd = "/Users/x/dev/api", command = "node server.js" },
    { key = "c", title = "vite", ports = { 5173 }, runtime = "node", pid = 11,
      cwd = "/Users/x/dev/web", command = "vite --host" },
    { key = "b", title = "api", runtime = "docker", containerName = "api", status = "Up 2 hours" },
    { key = "d", title = "tsc", runtime = "node", pid = 12, cwd = "/Users/x/dev/tools",
      command = "tsc --watch" },
  }
  local stopped = nil
  M:configure({ api = {
    scan = function(cb) cb(scanned) end,
    stop = function(row, opts, cb) stopped = row.key cb(false, "confirm, it has 40 processes") end,
  } })
  M.enter(function() return true end)

  local rows = M.rows("")
  check("the supplier hands every row over in the scan's order",
    titles(rows) == "node   :3000,vite   :5173,api,tsc", titles(rows))
  local node = rows[1]
  check("a row filters on its title, the ports included, never its live subtitle",
    node.filterText == "node   :3000" and node.subTitle:find("33%%") ~= nil, node.subTitle)
  check("its keywords are the runtime, the command and the project folder",
    table.concat(node.keywords or {}, "|") == "node|node server.js|api", table.concat(node.keywords or {}, "|"))
  check("a container's name is a keyword", table.concat(rows[3].keywords or {}, "|") == "docker|api",
    table.concat(rows[3].keywords or {}, "|"))
  check("the group order is the bonus, first at one and last at a quarter",
    rows[1].bonus == 1 and rows[2].bonus == 0.75 and rows[3].bonus == 0.5 and rows[4].bonus == 0.25)

  local kept = rank.apply(M.rows("api"), "api", fuzzy)
  check("match first, the api container above the node process found only through its folder",
    titles(kept) == "api,node   :3000", titles(kept))
  kept = rank.apply(M.rows("3000"), "3000", fuzzy)
  check("a bare port finds its listener", titles(kept) == "node   :3000", titles(kept))
  kept = rank.apply(M.rows(":5173"), ":5173", fuzzy)
  check("a port with its colon finds its listener", titles(kept) == "vite   :5173", titles(kept))
  kept = rank.apply(M.rows("33"), "33", fuzzy)
  check("a live figure is never searched", #kept == 0, titles(kept))
  kept = rank.apply(M.rows("dev"), "dev", fuzzy)
  check("a folder is matched by its own name, not anywhere in its path", #kept == 0, titles(kept))

  -- A heat sort puts the watcher first and the port holder last in hand. An empty field shows
  -- that order, and a typed query still orders equal matches by the scan's group order.
  heat = { a = 1, c = 2, b = 3, d = 4 }
  M.sortByLoad()
  rows = M.rows("")
  check("after a heat sort an empty field shows the heat order", titles(rows) == "tsc,api,vite   :5173,node   :3000",
    titles(rows))
  kept = rank.apply(M.rows("node"), "node", fuzzy)
  check("the title match leads, then equal keyword matches in group order, not heat order",
    titles(kept) == "node   :3000,vite   :5173,tsc", titles(kept))

  M.select({ key = "a" })
  check("a stop the source wants confirmed asks", stopped == "a")
  rows = M.rows("")
  check("the confirmation leads with the harmless answer and both are pinned",
    titles(rows) == "Keep it running,Stop anyway" and rows[1].pinned == true and rows[2].pinned == true,
    titles(rows))
  kept = rank.apply(M.rows("zzz"), "zzz", fuzzy)
  check("typing on a confirmation never drops an answer", titles(kept) == "Keep it running,Stop anyway",
    titles(kept))
end
