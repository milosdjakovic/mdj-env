-- Unit case for the stage holding the highlight on the same item across a repaint that keeps
-- the person on the same level. An async redraw, a refresh and a stay all rebuild the rows, and
-- the provider on its own keeps only the row number, so a row inserted above the one the person
-- is on would slide the highlight onto a neighbour and Enter would act on something they never
-- chose. A row whose item states a key is found again by that key, in the list as it is shown,
-- filtered and ranked under a typed query, and a row with no key keeps its number as before.
--
-- The stage and the default provider are both the real modules. The stage is loaded in an
-- environment of its own whose hs is a small stub, so nothing here touches the running config.
-- The provider is built through its own new from a fresh copy of the chooser facade, with only
-- show, hide and isShowing replaced on the instance so nothing is ever drawn on screen. Ranking,
-- filtering, the highlight, refresh and selectRow are the provider's own code.

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

-- The real provider, kept off screen. show does what the real one does to the list, rebuild it
-- for an empty query with the highlight on row one, and draws nothing. The draw layout is
-- derived from a row count alone, and the rects are cleared again so the provider's own redraw
-- stays a no op without a canvas.
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
    self.field:setText("")
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

local loggedErrors = 0
local env = setmetatable({
  hs = { logger = { new = function() return { w = function() end,
    e = function() loggedErrors = loggedErrors + 1 end, i = function() end } end },
    processInfo = {}, timer = { secondsSinceEpoch = os.time },
    application = { frontmostApplication = function() return nil end } },
}, { __index = _G })
local stage = loadOrFail(olmDir .. "host/stage/init.lua", env)
stage:configure({ chooser = factory })

local function keyed() local it = inst:selectedItem() return it and it.key end

-- A settings page of browsers. An extra line for Safari appears above Chrome when its read
-- lands, which is the case that used to move the highlight onto it. Each row filters on the
-- browser's name.
local extra = false
local page = { name = "keyed",
  rows = function()
    local r = { { title = "Back", pinned = true, item = { back = true } } }
    r[#r + 1] = { title = "Safari", filterText = "Safari", item = { key = "safari" } }
    if extra then
      r[#r + 1] = { title = "Ask Safari for permission", filterText = "Safari",
        item = { key = "safari.permission" } }
    end
    r[#r + 1] = { title = "Chrome", filterText = "Chrome", item = { key = "chrome", toggle = true } }
    r[#r + 1] = { title = "Chrome Canary", filterText = "Chrome", item = { key = "canary", toggle = true } }
    return r
  end,
  onSelect = function() end,
  intercept = function(item) if item.toggle then extra = not extra return "stay" end end }

stage:present(page)
check("the page is up on the real provider", inst:isShowing() and keyed() == nil)
inst:selectRow(3)
check("the highlight is on Chrome", keyed() == "chrome")
extra = true
stage:refresh()
check("an async redraw that inserts a row above keeps Chrome", keyed() == "chrome",
  tostring(keyed()) .. " at row " .. tostring(inst:selectedRow()))
check("and Chrome is now one row lower", inst:selectedRow() == 4)
extra = false
stage:refresh()
check("a redraw that removes it keeps Chrome too", keyed() == "chrome" and inst:selectedRow() == 3)
inst:insertSelected()
check("a stay on Chrome that inserts a row above keeps Chrome", keyed() == "chrome" and extra,
  tostring(keyed()))

-- Under a typed query the shown list is filtered and ranked, so the row number of the item is
-- its place in that list rather than in the presentation's own. Both Chrome rows score the
-- same, so the provider keeps them in the order the rows gave them, and the Safari line
-- inserted above does not match the query at all. A Chrome line inserted above both does. Back
-- is pinned, so it trails the matches and never shifts their row numbers.
extra = false
inst:setQuery("chrome")
check("a typed query shows the two Chrome rows first", inst:selectedRow() == 1 and keyed() == "chrome")
inst:selectRow(2)
check("the highlight is on Canary", keyed() == "canary")
local insertedAbove = false
local base = page.rows
page.rows = function()
  local r = base()
  if insertedAbove then
    table.insert(r, 2, { title = "Chrome helper", filterText = "Chrome", item = { key = "helper" } })
  end
  return r
end
insertedAbove = true
stage:refresh()
check("under a query an async redraw that inserts a matching row above keeps Canary", keyed() == "canary",
  tostring(keyed()) .. " at row " .. tostring(inst:selectedRow()))
check("and finds it at its ranked place, the third row shown", inst:selectedRow() == 3)
inst:insertSelected()
check("a stay under a query keeps Canary", keyed() == "canary" and inst:selectedRow() == 3,
  tostring(keyed()))
extra = false
inst:setQuery("saf")
inst:selectRow(1)
check("under a query matching Safari the highlight is on Safari", keyed() == "safari")
extra = true
stage:refresh()
check("the Safari line landing below it under the query leaves Safari held",
  keyed() == "safari" and inst:selectedRow() == 1)
stage:hide()

-- A level whose rows state no key keeps the row number exactly as before.
local grow = false
local plain = { name = "plain", matcher = false,
  rows = function()
    local r = {}
    if grow then r[#r + 1] = { title = "new", item = { id = "new" } } end
    r[#r + 1] = { title = "one", item = { id = "one" } }
    r[#r + 1] = { title = "two", item = { id = "two" } }
    return r
  end,
  onSelect = function() end }
stage:present(plain)
inst:selectRow(2)
grow = true
stage:refresh()
check("a level with no keys keeps the row number", inst:selectedRow() == 2
  and inst:selectedItem().id == "one")
stage:hide()

-- A held key that is gone keeps the row number too.
local gone = false
local vanishing = { name = "vanishing", matcher = false,
  rows = function()
    local r = { { title = "a", item = { key = "a" } } }
    if not gone then r[#r + 1] = { title = "b", item = { key = "b" } } end
    r[#r + 1] = { title = "c", item = { key = "c" } }
    return r
  end,
  onSelect = function() end }
stage:present(vanishing)
inst:selectRow(2)
gone = true
stage:refresh()
check("a held key that is gone keeps the row number", inst:selectedRow() == 2
  and inst:selectedItem().key == "c")
stage:hide()

-- A keyed level whose rows raise on the second call after a redraw is asked for. The provider's
-- own rebuild is the first call and survives, the stage's lookup by key is the second, and it
-- must not unwind out of refresh into whatever background tick asked for the redraw. The row
-- number stands and the failure is logged.
local calls, armed = 0, false
local raising = { name = "raising", matcher = false,
  rows = function()
    if armed then
      calls = calls + 1
      if calls == 2 then error("rows failed on purpose") end
    end
    return { { title = "a", item = { key = "a" } }, { title = "b", item = { key = "b" } },
      { title = "c", item = { key = "c" } } }
  end,
  onSelect = function() end }
stage:present(raising)
inst:selectRow(2)
armed = true
local before = loggedErrors
local okRefresh, why = pcall(function() stage:refresh() end)
check("a refresh whose rows raise inside the hold does not raise", okRefresh, tostring(why))
check("and the row number stands", inst:selectedRow() == 2 and inst:selectedItem().key == "b")
check("and the failure is logged", loggedErrors == before + 1, tostring(loggedErrors - before))
stage:hide()
