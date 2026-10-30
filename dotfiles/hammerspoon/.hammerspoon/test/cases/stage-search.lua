-- Unit case for a presentation's searchText and rowLimit reaching every place its rows are
-- ranked, docs/PLAN-UNIFIED-SEARCH.md phase three. The stage writes both onto the shared
-- instance beside the matcher before every show, the default provider ranks and cuts with them,
-- the stage's own highlight hold ranks with them, a presentation declaring neither clears what
-- the one before it declared, and a query scope declaring them filters its rows the same way.
-- The engine's own rules are proved in searchfields.lua, this proves the threading.
--
-- The stage and the default provider are the real modules, built the way stage-holdkey.lua
-- builds them, with show, hide and isShowing replaced on the instance so nothing is drawn. The
-- query scope is the real module loaded in an environment whose hs is a small stub.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local olmDir = caseDir .. "/../../Spoons/Olm.spoon/"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local function loadOrFail(path, env)
  local chunk, err
  if env then chunk, err = loadfile(path, "t", env) else chunk, err = loadfile(path) end
  if not chunk then error("could not load " .. path .. ", " .. tostring(err)) end
  return chunk()
end

local Chooser = loadOrFail(olmDir .. "lib/chooser/init.lua")
local ui = loadOrFail(olmDir .. "lib/ui/init.lua")
local Default = Chooser.providers.default
Default.configure({ panel = {}, ui = ui })

local inst
local factory = { matchers = Chooser.matchers, rank = Chooser.rank, new = function(config)
  if config.matcher == nil then config.matcher = Chooser.matchers.fuzzy end
  inst = Default.new(config)
  function inst:show()
    self.active = true
    self._rects = { rowCount = 10 }
    self:_updateDrawLayout()
    self._rects = nil
    self:_rebuildList("", true)
    self._suppressRebuild = true
    self.view:setText("")
    self._suppressRebuild = false
  end
  function inst:hide()
    if not self.active then return end
    self.active = false
    if self.config.onClose then self.config.onClose() end
  end
  function inst:isShowing() return self.active == true end
  return inst
end }

local printed = {}
local env = setmetatable({
  hs = { logger = { new = function() return { w = function() end, e = function() end, i = function() end } end },
    processInfo = {}, timer = { secondsSinceEpoch = os.time },
    application = { frontmostApplication = function() return nil end },
    printf = function(fmt, ...) printed[#printed + 1] = string.format(fmt, ...) end },
}, { __index = _G })
local stage = loadOrFail(olmDir .. "host/stage/init.lua", env)
stage:configure({ chooser = factory })

-- The ids of the rows the provider holds now, in the order drawn, the engine's row of more, which
-- ends a list its limit cut, as more.
local function shown()
  local out = {}
  for i, row in ipairs(inst.listState.filtered or {}) do
    out[i] = row.more and "more" or (row.item and row.item.id or "?")
  end
  return table.concat(out, ",")
end

-- A FileSearch shaped field, a root and an extension before the word to rank by. The grammar
-- is the plugin's, this stands in for it.
local function lastWord(text)
  local words = {}
  for w in text:gmatch("%S+") do
    if not w:match("^[~/.]") then words[#words + 1] = w end
  end
  return table.concat(words, " ")
end

local function fileRows()
  return {
    { title = "Back", pinned = true, item = { id = "back" } },
    { title = "notes.txt", item = { id = "notes", key = "notes" } },
    { title = "foo.js", item = { id = "foo", key = "foo" } },
    { title = "bar.js", item = { id = "bar", key = "bar" } },
    { title = "food.md", item = { id = "food", key = "food" } },
    { title = "fold.lua", item = { id = "fold", key = "fold" } },
  }
end

local files = { name = "files", rows = fileRows, onSelect = function() end,
  searchText = lastWord, rowLimit = 3 }

stage:present(files)
check("the stage writes searchText and rowLimit beside the matcher",
  select(2, inst:matcher()) ~= nil and select(2, inst:matcher()).searchText == lastWord
    and select(2, inst:matcher()).rowLimit == 3)
check("an empty field shows the first rows up to the limit and the pinned row in place, then the row of more",
  shown() == "back,notes,foo,bar,more", shown())
inst:setQuery("~/dev .js foo")
check("a structured query ranks by what searchText answers", shown() == "foo,food,back", shown())
inst:setQuery("~/dev fo")
check("the limit cuts after ranking and keeps the pinned row", shown() == "foo,food,fold,back", shown())
inst:setQuery("~/dev .js")
check("an empty answer keeps the supplier's order, then the row of more",
  shown() == "back,notes,foo,bar,more", shown())

-- The highlight hold ranks with the same search, so the row it finds is the one on screen.
inst:setQuery("~/dev .js foo")
check("the hold finds a row by key at its place under the answer", stage:selectWhere({ key = "food" })
  and inst:selectedRow() == 2, tostring(inst:selectedRow()))
inst:setQuery("")
check("the hold never finds a row the limit cut", not stage:selectWhere({ key = "fold" }))
stage:hide()

-- A presentation declaring neither clears what the one before it declared.
local plainList = { name = "plain", rows = fileRows, onSelect = function() end }
stage:present(plainList)
check("a presentation with neither field clears the search", select(2, inst:matcher()) == nil)
check("and shows every row", shown() == "back,notes,foo,bar,food,fold", shown())
inst:setQuery("~/dev .js foo")
check("and ranks the raw text, which matches nothing here", shown() == "back", shown())
stage:hide()

-- A scope declares the same two fields and its rows are filtered with them.
local QueryScope = loadOrFail(olmDir .. "host/queryscope/init.lua", env)
local qs = QueryScope:init()
qs:configure({
  matcher = Chooser.matchers.fuzzy, rank = Chooser.rank,
  scopes = {
    { name = "files", title = "Files", aliases = { "f" }, rows = function() return fileRows() end,
      run = function() end, searchText = lastWord, rowLimit = 2 },
    { name = "bad", title = "Bad", aliases = { "b" }, rows = function() return {} end,
      run = function() end, searchText = "foo" },
  },
})
local rows = qs:rows("f ~/dev .js fo")
local ids = {}
for i, r in ipairs(rows) do ids[i] = r.item and r.item.payload and r.item.payload.id or (r.item and r.item.id) or r.title end
check("a scope ranks its rows by its searchText and cuts them to its rowLimit",
  #rows == 3 and ids[1] == "foo" and ids[2] == "food" and ids[3] == "back", table.concat(ids, ","))
local refused = false
for _, line in ipairs(printed) do
  if line:find("bad has a searchText that is not a function", 1, true) then refused = true end
end
check("a scope whose searchText is not a function is refused", refused, table.concat(printed, "; "))
