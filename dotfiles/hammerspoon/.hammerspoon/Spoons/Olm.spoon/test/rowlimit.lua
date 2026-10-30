-- The chooser's row limit and its row of more, offline, through the real engine.
--
-- Pins lib/chooser/rank.lua's third answer, what a limit cut and where the rest is offered, and
-- the engine above it. A list with no limit of its own takes the default handed to
-- Engine.configure, a presentation's own number wins and its false opts out, and a list longer
-- than the limit ends in one row of more, Show N more, carrying no item. Choosing it adds a page
-- and lands the highlight on the first row it added, a right press on it reaches nobody, and a
-- new query starts again from one page. The engine is composed with the swift view over a
-- recording stand in for its library, the same stubs test/swiftview.lua uses, since the rows the
-- engine hands a view are what is pinned and the view that draws them does not change them.
--
-- Run it.
--   lua test/rowlimit.lua

everyTimers = {}

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local spoon = here .. "../"
local failed = false

local function check(name, got, want)
  if got ~= want then
    failed = true
    print(("FAIL %s, wanted %s, got %s"):format(name, tostring(want), tostring(got)))
  else
    print(("ok   %s"):format(name))
  end
end

--------------------------------------------------------------------------------
-- A fake hs, only what the engine, the view and the build reach for
--------------------------------------------------------------------------------

local files, tasks, dirs, taps = {}, {}, {}, {}

-- A key event is described by its "bytes", the key code and the modifiers, which the fake
-- newEventFromData turns back into an object answering what the engine asks of an event.
local function keyData(code, ...)
  return table.concat({ tostring(code), ... }, ":")
end

hs = {
  processInfo = { version = "1.0", bundlePath = "/Applications/Hammerspoon.app" },
  hash = { SHA256 = function(s) return ("%064x"):format(#s) end },
  fs = {
    attributes = function(path, attr)
      local f = files[path]
      if not f then return nil end
      if attr then return type(f) == "table" and f[attr] or 0 end
      return {}
    end,
    mkdir = function() return true end,
    dir = function(path)
      local list = dirs[path]
      if not list then error("no such directory " .. path) end
      local i = 0
      return function() i = i + 1 return list[i] end, nil
    end,
  },
  host = { operatingSystemVersion = function() return { major = 27 } end },
  task = {
    new = function(_, callback, args)
      local t = { callback = callback, args = args }
      function t:start() self.started = true end
      tasks[#tasks + 1] = t
      return t
    end,
  },
  screen = {
    mainScreen = function()
      return { frame = function() return { x = 0, y = 0, w = 1600, h = 1000 } end }
    end,
  },
  timer = {
    doEvery = function(_, fn)
      local t = { fn = fn, stopped = false }
      function t:stop() self.stopped = true end
      everyTimers[#everyTimers + 1] = t
      return t
    end,
  },
  eventtap = {
    new = function(types, fn)
      local t = { types = types, fn = fn, running = false }
      function t:start() self.running = true end
      function t:stop() self.running = false end
      taps[#taps + 1] = t
      return t
    end,
    event = {
      types = { scrollWheel = "scrollWheel" },
      properties = { keyboardEventAutorepeat = "autorepeat", scrollWheelEventIsContinuous = "continuous",
        scrollWheelEventPointDeltaAxis1 = "point", scrollWheelEventDeltaAxis1 = "line" },
      newEventFromData = function(data)
        local parts = {}
        for p in data:gmatch("[^:]+") do parts[#parts + 1] = p end
        local flags = {}
        for i = 2, #parts do flags[parts[i]] = true end
        return {
          getKeyCode = function() return tonumber(parts[1]) end,
          getFlags = function() return flags end,
          getProperty = function() return 0 end,
          asData = function() return data end,
        }
      end,
    },
  },
}

--------------------------------------------------------------------------------
-- A fake UI kit, tokens in the shape lib/ui answers them
--------------------------------------------------------------------------------

local function color(v) return { red = v, green = v, blue = v, alpha = 1 } end
local function role(c) return { font = "UI", size = 14, lineHeight = 18, color = c } end

local UI = {
  tokens = function()
    return {
      colors = { foreground = color(0.9), subtext = color(0.6), highlight = color(0.3),
        background = color(0.1), border = color(0.45) },
      text = { title = role("foreground"), body = role("foreground"), caption = role("subtext"),
        section = role("subtext") },
      alpha = { dim = 0.4 },
      radius = { surface = 12 },
      stroke = { border = 1 },
      space = { s = 6, l = 14 },
      pad = 14,
      inset = { x = 14, y = 10 },
      badge = { hint = { height = 20 } },
    }
  end,
  nestedRadius = function(outer, gap) return math.max(0, outer - gap) end,
}

--------------------------------------------------------------------------------
-- A fake native library, recording every call in order
--------------------------------------------------------------------------------

local calls, nativeText, visible, callback = {}, "", false, nil
local lastPlace, lastRows, lastUpdate = nil, nil, nil
local native = {}
local function record(name) calls[#calls + 1] = name end
function native.setCallback(fn) callback = fn end
function native.new() return 7 end
local lastStyle = nil
function native.style(_, t) record("style"); lastStyle = t end
function native.place(_, t) record("place"); lastPlace = t end
function native.setRows(_, rows) record("setRows"); lastRows = rows end
local lastImages = nil
function native.setImages(_, images) record("setImages"); lastImages = images end
local sentHighlight = nil
function native.update(_, t) record("update"); lastUpdate = t; if t.highlight ~= nil then sentHighlight = t.highlight end end
function native.text() return nativeText end
function native.setText(_, t) record("setText"); nativeText = t end
function native.feedKey() record("feedKey") end
function native.show() record("show"); visible = true end
function native.hide() record("hide"); visible = false end
function native.isVisible() return visible end
function native.start() record("start") end
function native.stop() record("stop") end
function native.refocus() record("refocus") end
local hosted = false
function native.hostsPane() return hosted end
local fieldKeysSent = nil
function native.setFieldKeys(_, t) fieldKeysSent = t end

local function since(mark)
  local out = {}
  for i = mark + 1, #calls do out[#out + 1] = calls[i] end
  return table.concat(out, ",")
end

local function send(event, ...)
  return callback(7, event, ...)
end


local rank = dofile(spoon .. "lib/chooser/rank.lua")

--------------------------------------------------------------------------------
-- rank.apply's third answer
--------------------------------------------------------------------------------

do
  local items = {}
  for i = 1, 10 do items[i] = { title = "row " .. i } end
  items[11] = { title = "pinned", pinned = true }
  local out, reason, more = rank.apply(items, "", nil, { rowLimit = 4 })
  check("an empty query keeps the limit's rows and the pinned one", #out, 5)
  check("and says nothing failed", reason, nil)
  check("and how many it cut", more and more.count, 6)
  check("offering the rest just after the last row it counted, before the pinned row", more and more.at, 5)
  local _, _, none = rank.apply(items, "", nil, { rowLimit = 20 })
  check("a list within its limit cuts nothing", none, nil)
  local _, _, off = rank.apply(items, "", nil, { rowLimit = false })
  check("false is no limit", off, nil)
  local match = function(q, hay) return hay:find(q, 1, true) and 1 or nil end
  local ranked, _, cut = rank.apply(items, "row", match, { rowLimit = 3 })
  check("a ranked query keeps the limit's best rows and the pinned one", #ranked, 4)
  check("and says how many matching rows it cut", cut and cut.count, 7)
end

--------------------------------------------------------------------------------
-- The engine's default limit and its row of more
--------------------------------------------------------------------------------

local Engine = dofile(spoon .. "lib/chooser/engine/init.lua")
local View = dofile(spoon .. "lib/chooser/providers/swift/view.lua")
Engine.configure({ ui = UI, yields = function() return false end,
  listKeys = function() return false end, rowLimit = 50, moreIcon = { icon = "more", owner = "olm" } })
View.configure({ ui = UI, icon = function() return nil end })
View.attach(native)

local total = 127
local selected, rightClicked = {}, {}
local picker = Engine.new({
  rows = function(query)
    local out = {}
    for i = 1, total do
      local name = ("row %03d"):format(i)
      if query == "" or name:find(query, 1, true) then out[#out + 1] = { title = name, item = i } end
    end
    return out
  end,
  onSelect = function(item) selected[#selected + 1] = item end,
  onRightClick = function(item) rightClicked[#rightClicked + 1] = item end,
}, function(engine) return View.new(engine, native) end)

local function titles() local out = {} for i, r in ipairs(lastRows or {}) do out[i] = r.title end return out end

picker:show()
local t = titles()
check("a list past the default limit shows the limit's rows and one row of more", #t, 51)
check("the row of more names the page it adds", t[51], "Show 50 more")
check("and how many are left in all", lastRows[51].subtitle, "77 more in all")
check("the row before it is the fiftieth", t[50], "row 050")
check("the swift view hands it to Swift as muted", lastRows[51].muted, true)
local moreState = picker.listState.filtered[51]
check("it carries the icon it was handed", moreState.icon, "more")
check("read against the owner it was handed", moreState.iconOwner, "olm")
check("and every result as not muted", lastRows[50].muted, false)

picker:selectRow(51)
check("a highlight on the row of more reports no item", picker:selectedItem(), nil)
picker:rightClickIndex(51)
check("a right press on it reaches nobody", #rightClicked, 0)
picker:insertSelected()
t = titles()
check("choosing it chooses nothing", #selected, 0)
check("and keeps the list up", picker:isShowing(), true)
check("and adds a page", #t, 101)
check("the highlight lands on the first row it added", picker:selectedItem(), 51)
check("the last page names what is left when that is less", t[101], "Show 27 more")
check("and no total, since it adds them all", lastRows[101].subtitle, "")
picker:chooseIndex(101)
t = titles()
check("the last page shows every row and no row of more", #t, total)
check("with nothing past the last row", t[total], "row 127")

picker:setQuery("row 0")
t = titles()
check("a new query is one page again", #t, 51)
check("its row of more counts what the query matched past the limit", t[51], "Show 49 more")

picker:setMatcher(nil, { rowLimit = 10 })
picker:refresh(true)
t = titles()
check("a presentation's own limit wins over the default", #t, 11)
check("and its page is its own", t[11], "Show 10 more")

picker:setMatcher(nil, { rowLimit = false })
picker:refresh(true)
check("false opts a list out", #titles(), 99)

picker:setMatcher(nil, nil)
total = 20
picker:refresh(true)
check("a list within the limit has no row of more", #titles(), 20)
picker:hide()

if failed then
  print("rowlimit, FAILED")
  os.exit(1)
end
print("rowlimit, every case passed")
