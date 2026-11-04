-- Unit case for a level the stage pushes with a field prefix, the typed word that reached it,
-- decisions/olm-query-scope-handover.md. The field keeps the word in front of what is typed,
-- the level's rows, its search, query() and setQuery() see only the text after it, and
-- deleting into the word steps back to the level below with whatever text is left.
--
-- The stage and the default provider are the real modules, built the way stage-search.lua
-- builds them, with show, hide and isShowing replaced on the instance so nothing is drawn, and
-- hs.timer.doAfter held so the case runs the step back itself.

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

local pending = {}
local env = setmetatable({
  hs = { logger = { new = function() return { w = function() end, e = function() end, i = function() end } end },
    processInfo = {},
    timer = { secondsSinceEpoch = os.time, doAfter = function(_, fn)
      local t = { fn = fn }
      function t:stop() self.fn = nil end
      pending[#pending + 1] = t
      return t
    end },
    application = { frontmostApplication = function() return nil end },
    printf = function() end },
}, { __index = _G })
local stage = loadOrFail(olmDir .. "host/stage/init.lua", env)
stage:configure({ chooser = factory })

local function runPending()
  local list = pending
  pending = {}
  for _, t in ipairs(list) do if t.fn then t.fn() end end
end

local function shown()
  local out = {}
  for i, row in ipairs(inst.listState.filtered or {}) do
    out[i] = row.more and "more" or (row.item and row.item.id or "?")
  end
  return table.concat(out, ",")
end

local function lastWord(text)
  local words = {}
  for w in text:gmatch("%S+") do
    if not w:match("^[~/.]") then words[#words + 1] = w end
  end
  return table.concat(words, " ")
end

local asked = {}
local function fileRows(query)
  asked[#asked + 1] = query
  return {
    { title = "notes.txt", item = { id = "notes" } },
    { title = "foo.js", item = { id = "foo" } },
    { title = "food.md", item = { id = "food" } },
    { title = "bar.js", item = { id = "bar" } },
  }
end

local base = { name = "base", rows = function() return { { title = "Base", item = { id = "base" } } } end,
  onSelect = function() end }
local files = { name = "files", rows = fileRows, onSelect = function() end }
local grammar = { name = "grammar", rows = fileRows, onSelect = function() end, searchText = lastWord }

stage:present(base)
stage:push(files, { prefix = "/ " })
check("a pushed level shows its prefix in the field", inst:query() == "/ ", inst:query())
stage:setQuery("fo")
check("setQuery puts the prefix in front of the text", inst:query() == "/ fo", inst:query())
check("query answers the text after the prefix", stage:query() == "fo", stage:query())
check("the level's rows are asked with the text after the prefix", asked[#asked] == "fo", tostring(asked[#asked]))
check("the level ranks by the text after the prefix", shown() == "foo,food", shown())

inst:setQuery("/")
check("deleting into the prefix shows nothing while the step back waits", shown() == "", shown())
runPending()
check("and then steps back to the level below", stage:current() == "base", tostring(stage:current()))
check("with the text that was left in the field", inst:query() == "/", inst:query())
check("and the level below sees the whole text", stage:query() == "/", stage:query())

stage:push(grammar, { prefix = "/ " })
stage:setQuery("~/dev .js foo")
check("a level's own searchText reads the text after the prefix", shown() == "foo,food", shown())
stage:pop()

stage:push(files)
stage:setQuery("fo")
check("a push with no prefix leaves the field as typed", inst:query() == "fo", inst:query())
stage:hide()

stage:present(base)
stage:push(files, { prefix = "/ " })
stage:hide()
stage:present(files)
stage:setQuery("fo")
check("a hide forgets the prefix", inst:query() == "fo", inst:query())
stage:hide()
