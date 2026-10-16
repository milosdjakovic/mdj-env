-- Unit case for three things host/stage offers the composition root and a presentation. onClosed
-- tells its observers once each time the stage goes away, never on a pop back to the level above,
-- which is the seam staged plugin choices apply on. presentAt walks a path of items through each
-- level's own onSelect and shows the deepest level with a highlight found by item fields, which
-- is how a place is reopened after a reload. And a row that answers stay while stating a key
-- keeps the highlight on that key when a row above it appears or goes away.
--
-- The stage is loaded in an environment of its own whose hs is a small stub, so nothing here
-- touches the running config, and the chooser is a fake holding rows and a highlight index,
-- choosing the way the default provider does, intercept first, then refresh or complete.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local stagePath = caseDir .. "/../../Spoons/Olm.spoon/host/stage/init.lua"

local env = setmetatable({
  hs = { logger = { new = function() return { w = function() end, e = print, i = function() end } end },
    processInfo = {}, timer = { secondsSinceEpoch = os.time },
    application = { frontmostApplication = function() return nil end } },
}, { __index = _G })
local chunk, err = loadfile(stagePath, "t", env)
if not chunk then error("could not load the stage, " .. tostring(err)) end
local stage = chunk()
-- A fake chooser holding rows and a highlight index.
local inst
local factory = { matchers = {}, new = function(config)
  inst = { config = config, showing = false, hl = 1, rows = {}, q = "" }
  function inst:rowCount() return 10 end
  function inst:matcher() return nil end
  function inst:titleLineBreak() return "t" end
  function inst:setPlaceholder() end
  function inst:setPaneWidth() end
  function inst:setMatcher() end
  function inst:setTitleLineBreak() end
  function inst:setRows() end
  function inst:isShowing() return self.showing end
  function inst:show() self.showing = true self.rows = config.rows("") self.hl = 1 end
  function inst:hide() if self.showing then self.showing = false config.onClose() end end
  function inst:setQuery(q) self.q = q end
  function inst:query() return self.q end
  function inst:refresh(reset) self.rows = config.rows(self.q) if reset then self.hl = 1 end end
  function inst:selectRow(n) self.hl = n end
  function inst:selectedItem() local r = self.rows[self.hl] return r and r.item end
  function inst:choose() -- Return on the highlight, as the provider does
    local r = self.rows[self.hl]
    local a = config.intercept(r.item, true)
    if a == true or a == "stay" then self:refresh(a ~= "stay") return end
    config.onSelect(r.item) self:hide()
  end
  return inst end }
stage:configure({ chooser = factory })
local closed = 0
stage:onClosed(function() closed = closed + 1 end)
local function ok(d, c) print((c and "PASS " or "FAIL ") .. d) end
-- A two level tool, top level row drills into a page whose rows gain an Apply row on a toggle.
local staged = false
local child
local top = { name = "tool", rows = function() return { { item = { nav = true, to = "page" } } } end,
  onSelect = function(item) if item and item.to == "page" then return child end end }
child = { matcher = false,
  rows = function()
    local r = { { item = { back = true } } }
    if staged then r[#r + 1] = { item = { apply = true, key = "apply" } } end
    r[#r + 1] = { item = { plugin = "a", key = "a" } }
    r[#r + 1] = { item = { plugin = "b", key = "b" } }
    return r end,
  onSelect = function() end,
  intercept = function(item) if item.plugin then staged = not staged return "stay" end
    if item.back then stage:pop() return true end end }
ok("presentAt answers true", stage:presentAt(top, { { nav = true, to = "page" } }, { key = "b" }))
ok("the walk stacked two levels", #stage._stack == 2 and stage._stack[2] == child)
ok("the child took the parent's name", child.name == "tool")
ok("the highlight is on b", inst:selectedItem().key == "b")
inst:choose()
ok("a stay on b holds b although an Apply row appeared above", inst:selectedItem().key == "b")
inst:choose()
ok("and again when it goes away", inst:selectedItem().key == "b")
inst.hl = 1 inst:choose()
ok("popping back to the top is not a close", closed == 0 and #stage._stack == 1)
inst:hide()
ok("escape is one close", closed == 1)
stage:hide()
ok("a hide after that tells nobody again", closed == 1)
stage:presentAt(top, { { nav = true, to = "nowhere" } })
ok("a stale path stops at the deepest level reached", #stage._stack == 1)
stage:hide()
ok("a programmatic hide is one close", closed == 2)
