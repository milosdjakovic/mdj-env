-- The swift chooser's Lua half, in plain Lua over a fake hs and a fake native library.
--
-- Pins that the engine drives the swift view through the view contract, a show placing the panel
-- on the canvas rect and sending the style, the rows, the text and the state before showing and
-- starting it, and a hide stopping it before hiding it, with onClose once. That every event the
-- panel sends reaches the engine call the view contract names for it, a typed text reranking,
-- dismiss hiding, yields and listKey answering what the engine answers, an empty backspace asking
-- back, a leftover Down moving the highlight and a leftover Return choosing, a hover highlighting,
-- a press and release choosing, a press outside hiding and a press in the companion keeping the
-- list and asking the panel to take key. And that the provider serves the fallback when the
-- library is missing, while it builds, after a build in the same session, and when it fails.
--
-- The key order itself runs in Swift, native/Panel.swift, so what this pins is that each step of
-- it lands on the right engine call. The panel is measured live.
--
-- Run it.
--   lua test/swiftview.lua

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

local files, tasks = {}, {}

-- A key event is described by its "bytes", the key code and the modifiers, which the fake
-- newEventFromData turns back into an object answering what the engine asks of an event.
local function keyData(code, ...)
  return table.concat({ tostring(code), ... }, ":")
end

hs = {
  processInfo = { version = "1.0", bundlePath = "/Applications/Hammerspoon.app" },
  hash = { SHA256 = function(s) return ("%064x"):format(#s) end },
  fs = {
    attributes = function(path) return files[path] and {} or nil end,
    mkdir = function() return true end,
  },
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
    doEvery = function()
      return { stop = function() end }
    end,
  },
  eventtap = {
    event = {
      properties = { keyboardEventAutorepeat = "autorepeat" },
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
        background = color(0.1) },
      text = { title = role("foreground"), body = role("foreground"), caption = role("subtext"),
        section = role("subtext") },
      alpha = { dim = 0.4 },
      radius = { surface = 12 },
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
function native.style() record("style") end
function native.place(_, t) record("place"); lastPlace = t end
function native.setRows(_, rows) record("setRows"); lastRows = rows end
function native.update(_, t) record("update"); lastUpdate = t end
function native.text() return nativeText end
function native.setText(_, t) record("setText"); nativeText = t end
function native.feedKey() record("feedKey") end
function native.show() record("show"); visible = true end
function native.hide() record("hide"); visible = false end
function native.isVisible() return visible end
function native.start() record("start") end
function native.stop() record("stop") end
function native.refocus() record("refocus") end

local function since(mark)
  local out = {}
  for i = mark + 1, #calls do out[#out + 1] = calls[i] end
  return table.concat(out, ",")
end

local function send(event, ...)
  return callback(7, event, ...)
end

--------------------------------------------------------------------------------
-- The engine composed with the swift view, as the provider composes them
--------------------------------------------------------------------------------

local Engine = dofile(spoon .. "lib/chooser/engine/init.lua")
local View = dofile(spoon .. "lib/chooser/providers/swift/view.lua")
local backs, selected, closed, queries = 0, {}, 0, {}
local listTaken, yielded = false, false
Engine.configure({
  ui = UI,
  yields = function() return yielded end,
  listKeys = function() return listTaken end,
})
View.configure({ ui = UI, icon = function() return nil end })
View.attach(native)

local ROWS = { "alpha", "beta", "gamma", "delta" }
local picker = Engine.new({
  rows = function(query)
    queries[#queries + 1] = query
    local out = {}
    for _, name in ipairs(ROWS) do
      if query == "" or name:find(query, 1, true) then
        out[#out + 1] = { title = name, subTitle = "sub " .. name, item = name }
      end
    end
    return out
  end,
  onSelect = function(item) selected[#selected + 1] = item end,
  onClose = function() closed = closed + 1 end,
  back = function() backs = backs + 1 return false end,
}, function(engine) return View.new(engine, native) end)
picker:setPaneWidth(300)

local mark = #calls
picker:show()
-- The text is cleared first, and its change report draws, which sends the rows and the state,
-- then the engine draws once more, and only then is the panel shown and started.
check("show sends style, place, text, rows, state, then shows and starts",
  since(mark), "style,place,setText,setRows,update,update,show,start")
local rects = picker:scene().rects
check("the panel sits on the canvas rect", lastPlace.canvas, rects.canvas)
check("the list rect is the canvas's own", lastPlace.list.y, rects.list.y - rects.canvas.y)
check("every row is sent", #lastRows, 4)
check("a row's subtitle travels as a string", lastRows[2].subtitle, "sub beta")
check("the highlight starts on row one", lastUpdate.highlight, 1)
check("a list with no query draws no empty state", lastUpdate.empty, false)

-- Typing, reported by the native field, reranks through config.rows and resends the rows.
send("text", "ta")
check("typed text reaches the engine as the query", queries[#queries], "ta")
check("the reranked rows are sent", #lastRows, 2)
send("text", "zzz")
check("a query with no rows draws the empty state", lastUpdate.empty, true)
send("text", "")

-- setText from the engine tells the engine, since a native field reports no change made by code.
picker:setQuery("del")
check("setQuery writes the native field", nativeText, "del")
check("setQuery reranks", #lastRows, 1)
picker:setQuery("")

-- The asks before the field edits answer what the engine answers.
yielded = true
check("yields answers true when the engine yields", send("yields", keyData(4, "cmd")), true)
yielded = false
check("yields answers false otherwise", send("yields", keyData(4)), false)
listTaken = true
check("listKey answers true when the list took the key", send("listKey", keyData(38, "ctrl")), true)
listTaken = false
check("listKey answers false otherwise", send("listKey", keyData(38, "ctrl")), false)

-- The leftover keys move and choose.
send("leftover", keyData(125))
check("leftover Down moves the highlight", picker:selectedRow(), 2)
send("hover", 3)
check("a hover highlights its row", picker:selectedRow(), 3)
send("scroll", 0)
check("a native scroll is followed by the engine", picker:scene().list.scrollTop, 0)

-- An empty backspace asks back, which answers false here and leaves the list up.
send("emptyBackspace")
check("an empty backspace asks back", backs, 1)
check("a back answering false keeps the list", picker:isActive(), true)

-- A press in the companion keeps the list and asks the panel for key, one anywhere else hides.
local companion = rects.companion
mark = #calls
send("pressOutside", companion.x + 5, companion.y + 5)
check("a press in the companion keeps the list", picker:isActive(), true)
check("a press in the companion asks for key again", since(mark), "refocus")

-- Return chooses the highlighted row, onSelect then the teardown, stop before hide.
mark = #calls
send("leftover", keyData(36))
check("Return chooses the highlighted row", selected[1], "gamma")
check("choosing tears down, input stopped before the panel hides", since(mark), "stop,hide")
check("onClose fires once", closed, 1)
check("the list is down", picker:isActive(), false)

-- A pointer press and release chooses that row.
picker:show()
send("choose", 2)
check("a press and release chooses its row", selected[2], "beta")
check("onClose fires once per open", closed, 2)

-- Escape hides, and a press outside hides.
picker:show()
send("dismiss", keyData(53))
check("dismiss hides the list", picker:isActive(), false)
picker:show()
send("pressOutside", 1, 1)
check("a press outside hides the list", picker:isActive(), false)
check("every open closed once", closed, 4)

-- An unknown id or event answers false and does nothing.
check("an unknown id is ignored", callback(99, "dismiss", keyData(53)), false)
check("an unknown event is ignored", callback(7, "nonsense"), false)

--------------------------------------------------------------------------------
-- The provider, serving the fallback whenever the library is not loaded
--------------------------------------------------------------------------------

local Provider = dofile(spoon .. "lib/chooser/providers/swift/init.lua")
local lines = {}
local log = {
  i = function(m) lines[#lines + 1] = "i " .. m end,
  e = function(m) lines[#lines + 1] = "e " .. m end,
}
local fallback = { new = function(config) return { fromFallback = true, config = config } end }
-- A directory that exists, the system's temporary one, so a finished build can be renamed in.
local scratch = os.tmpname()
os.remove(scratch)
local dir = scratch:match("(.*)/")

Provider.configure({ ui = UI, fallback = fallback, dir = dir, swiftc = nil, log = log })
check("with no compiler the fallback serves", Provider.serving(), "fallback")
check("new answers the fallback's instance", Provider.new({}).fromFallback, true)
check("the missing compiler is said once", #lines, 1)
check("as an error naming the fallback", lines[1]:match("^e swift chooser, the build failed") ~= nil, true)

lines = {}
Provider.configure({ ui = UI, fallback = fallback, dir = dir, swiftc = "/usr/bin/swiftc", log = log })
check("a missing library starts a build", #tasks, 1)
check("the build runs the declared compiler", tasks[1] and tasks[1].args[1], "-emit-library")
check("the fallback serves while it builds", Provider.serving(), "fallback")
check("one line says the swift chooser takes over later",
  lines[1], "i swift chooser, building the library, the default chooser serves until the next reload")

-- The build finishing in this session does not switch providers under the shared picker.
local output = tasks[1].args[#tasks[1].args]
local handle = io.open(output, "w")
if handle then handle:close() end
tasks[1].callback(0, "", "")
os.remove(output:gsub("%.building$", ""))
check("a finished build is said", lines[2], "i swift chooser, the library is built and takes over from the next reload")
check("the fallback still serves this session", Provider.serving(), "fallback")

-- A failed build says the compiler's error.
lines = {}
Provider.configure({ ui = UI, fallback = fallback, dir = dir, swiftc = "/usr/bin/swiftc", log = log })
tasks[#tasks].callback(1, "", "Panel.swift:1: error: nope")
check("a failed build says the compiler's error", lines[#lines]:match("error: nope") ~= nil, true)
check("the fallback serves after a failed build", Provider.serving(), "fallback")

if failed then
  print("swiftview, FAILED")
  os.exit(1)
end
print("swiftview, every case passed")
