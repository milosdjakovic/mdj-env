-- Unit case for file search's frecency as Olm.app takes it, step 1.4d of
-- docs/PLAN-STANDALONE.md, docs/DESIGN-APP-FRECENCY.md. The store's export is the history the root
-- shares with the app, the store ranks by either of its two orders, and the engine's held list hands the shadow the recent list as the dates
-- gave it, before the float, since each side floats from a history of its own. Everything loads by
-- path into an environment of its own over a stand in hs, so the live hs and its settings are
-- never touched.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local fs = caseDir .. "/../../Spoons/Olm.spoon/plugins/filesearch/"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  elseif detail then
    print("FAIL " .. description .. ", " .. tostring(detail))
  else
    print("FAIL " .. description)
  end
end

local noop = function() end
local saved = {
  ["/home/a.txt"] = { score = "2.5", at = 400 },
  ["/home/b.txt"] = { score = 1, at = 500 },
  ["/home/bad"] = { at = 1 },
}
local fakeHs = {
  logger = { new = function() return setmetatable({}, { __index = function() return noop end }) end },
  settings = { get = function() return saved end, set = noop },
  timer = { doAfter = function() return { stop = noop } end },
  fs = { attributes = function(_, field)
    if field == "mode" then return "file" end
    return { mode = "file" }
  end },
  image = { iconForFileType = function(t) return { type = t } end },
}
local env = setmetatable({ hs = fakeHs }, { __index = _G })
env.loadfile = function(path, mode, e) return loadfile(path, mode or "t", e or env) end
local function load(path) return assert(env.loadfile(path))() end

--------------------------------------------------------------------------------
-- The export
--------------------------------------------------------------------------------

local frecency = load(fs .. "frecency.lua")
frecency.configure({ key = "test" })
local exported = frecency.export()
check("the export holds every use as written, undecayed",
  exported["/home/a.txt"] and exported["/home/a.txt"].score == 2.5 and exported["/home/a.txt"].at == 400
  and exported["/home/b.txt"].score == 1 and exported["/home/b.txt"].at == 500)
check("and leaves a malformed entry out", exported["/home/bad"] == nil)
exported["/home/a.txt"].score = 99
check("and is a copy, so the store is not changed through it", frecency.score("/home/a.txt") < 99)

--------------------------------------------------------------------------------
-- The orders top ranks by
--------------------------------------------------------------------------------

-- No half life, so a score reads as written and a.txt, used more, sits before b.txt, used later.
frecency.configure({ key = "test", halfLifeDays = 0 })
check("top ranks by use when no order is given", table.concat(frecency.top(2), ",") == "/home/a.txt,/home/b.txt",
  table.concat(frecency.top(2), ","))
check("and by use when asked for it",
  table.concat(frecency.top(2, frecency.orders.use), ",") == "/home/a.txt,/home/b.txt")
check("the last use order leads with the latest",
  table.concat(frecency.top(2, frecency.orders.lastUse), ",") == "/home/b.txt,/home/a.txt",
  table.concat(frecency.top(2, frecency.orders.lastUse), ","))

--------------------------------------------------------------------------------
-- The shadow's recent list, before the float
--------------------------------------------------------------------------------

local util = load(fs .. "util.lua")
local engine = load(fs .. "engine.lua")
local asked = {}
local lastUsed = "/home/used.txt"
engine:init()
engine:configure({
  types = {},
  roots = {},
  limits = { minChars = 3, retainCap = 2000, recentCount = 40, debounceMs = 70, recentFloat = 1 },
  sources = { {
    name = "fake",
    available = function() return true end,
    supports = function() return true end,
    search = function(parsed, ctx, cb)
      asked[#asked + 1] = { parsed = parsed, cb = cb }
      return { cancel = noop }
    end,
  } },
  ranker = {
    score = function(path) return path == "/home/used.txt" and 3 or 0 end,
    top = function() return { lastUsed } end,
    note = function(path) lastUsed = path end,
  },
})
engine:reset()
asked[1].cb({ util.row("/home/new.txt", { source = "fake" }), util.row("/home/older.txt", { source = "fake" }) }, nil)
local shown = engine:rowsFor("")
local function paths(list, field)
  local out = {}
  for i, r in ipairs(list) do out[i] = r[field] end
  return table.concat(out, ",")
end
check("the recent list leads with the path used most", paths(shown or {}, "path") == "/home/used.txt,/home/new.txt,/home/older.txt",
  paths(shown or {}, "path"))
local held = engine:held()
check("and the shadow is handed the dates alone", paths(held.items, "key") == "/home/new.txt,/home/older.txt",
  paths(held.items, "key"))

-- A use while the list closes orders the held list at once, so the next open draws it with no
-- fetch and nothing moves when the dates land.
engine:noteUse("/home/older.txt")
engine:reset()
local reopened = engine:rowsFor("")
check("a use floats the held list again, so the next open draws it before the fresh dates land",
  #asked == 2 and paths(reopened or {}, "path") == "/home/older.txt,/home/new.txt",
  paths(reopened or {}, "path") .. " after " .. #asked .. " fetch(es)")


--------------------------------------------------------------------------------
-- The merge, the app's uses folded in, step 1.5
--------------------------------------------------------------------------------

local merged = load(fs .. "frecency.lua")
merged.configure({ key = "merge" })
local changed = merged.merge({
  ["/home/a.txt"] = { score = 9, at = 300 },
  ["/home/b.txt"] = { score = 4, at = 600 },
  ["/home/c.txt"] = { score = 1, at = 700 },
  ["/home/bad"] = { at = 1 },
})
check("a merge keeps each path's newer use, from either side", changed
  and merged.usedAt("/home/a.txt") == 400 and merged.usedAt("/home/b.txt") == 600
  and merged.usedAt("/home/c.txt") == 700)
check("and leaves a malformed entry out", merged.usedAt("/home/bad") == nil)
check("merging the same store again changes nothing", merged.merge({
  ["/home/b.txt"] = { score = 4, at = 600 }, ["/home/c.txt"] = { score = 1, at = 700 } }) == false)
merged.merge({ ["/home/c.txt"] = { score = 3, at = 700 } })
check("a tie in time keeps the higher score", merged.export()["/home/c.txt"].score == 3)
check("and a merge of nothing changes nothing", merged.merge(nil) == false)

local plugin = load(fs .. "init.lua")
plugin.frecency = merged
check("the plugin's takeHistory folds a history in", plugin:takeHistory({ entries = {
  ["/home/d.txt"] = { score = 1, at = 800 } } }) and merged.usedAt("/home/d.txt") == 800)
check("and takes nothing that is no history", plugin:takeHistory("x") == false)
