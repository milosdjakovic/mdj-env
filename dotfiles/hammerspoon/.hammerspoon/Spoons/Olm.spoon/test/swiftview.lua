-- The swift chooser's Lua half, in plain Lua over a fake hs and a fake native library.
--
-- Pins that the engine drives the swift view through the view contract, a show placing the panel
-- on the canvas rect and sending the style, the rows, the text and the state before showing and
-- starting it, and a hide stopping it before hiding it, with onClose once. That every event the
-- panel sends reaches the engine call the view contract names for it, a typed text reranking,
-- dismiss hiding, yields and listKey answering what the engine answers, an empty backspace asking
-- back, a leftover Down moving the highlight and a leftover Return choosing, a hover highlighting,
-- a press and release choosing, a press outside hiding and a press in the companion keeping the
-- list and asking the panel to take key, a press in the gap before it too while there is one,
-- with the window spanning both and a hairline of the kit's border centred in the gap. And that
-- the provider serves the fallback when the
-- library is missing, while it builds, after a build in the same session, and when it fails,
-- and offers the docked pane's native backend only once its library is loaded.
--
-- And, after the review of 2026-10-28, that a missing command line tools directory, clang or SDK
-- serves the fallback without running anything, that a finished build removes all but the
-- newest three outputs, that the view hands the panel exactly the Control keys its field reads,
-- that a scroll over the companion is claimed by the view's own tap and nowhere else, that uses
-- answers for the field that serves, and that a loaded library's module table, which holds the
-- sentinel whose __gc cleans up when the state closes, stays referenced for the session.
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
    doEvery = function()
      return { stop = function() end }
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
-- One window holds the list's glass and the docked pane's, spanning both rects, with the gap clear.
local gap = rects.companion.x - (rects.canvas.x + rects.canvas.w)
check("there is a gap between the canvas and the companion", gap > 0, true)
check("the window starts at the canvas", lastPlace.window.x, rects.canvas.x)
check("the window spans the companion", lastPlace.window.w, rects.canvas.w + gap + rects.companion.w)
check("the list's glass is the canvas rect in the window", lastPlace.listFrame.x == 0
  and lastPlace.listFrame.y == 0 and lastPlace.listFrame.w == rects.canvas.w, true)
check("the pane's glass is the companion rect in the window, past the gap",
  lastPlace.paneFrame.x, rects.canvas.w + gap)
check("the companion travels in screen space, for a pane to be matched on", lastPlace.companion,
  rects.companion)
-- A hairline of the kit's border width, centred in the gap, from the top of the window to the
-- bottom, in the kit's border colour.
check("the divider is the kit's border width", lastPlace.dividerFrame.w, 1)
check("the divider is centred in the gap", lastPlace.dividerFrame.x, rects.canvas.w + (gap - 1) / 2)
check("the divider runs from the top", lastPlace.dividerFrame.y, 0)
check("to the bottom", lastPlace.dividerFrame.h, lastPlace.window.h)
check("the divider is the kit's border colour", lastStyle.divider.red, 0.45)
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

-- A press in the gap between the canvas and the companion is inside on purpose, since the one
-- shape of glass spans it, so it keeps the list and asks for key again, as the companion does.
-- The two opens here are left out of the close counts below.
local closedBefore = closed
picker:show()
mark = #calls
send("pressOutside", rects.canvas.x + rects.canvas.w + 1, rects.canvas.y + 5)
check("a press in the gap keeps the list", picker:isActive(), true)
check("a press in the gap asks for key again", since(mark), "refocus")
send("pressOutside", rects.companion.x + rects.companion.w + 5, rects.canvas.y + 5)
check("a press past the companion hides the list", picker:isActive(), false)

-- With no companion the window is the canvas rect alone, with no pane region and no divider.
picker:setPaneWidth(nil)
picker:show()
check("without a companion the window is the canvas", lastPlace.window, picker:scene().rects.canvas)
check("and there is no pane region", lastPlace.paneFrame, nil)
check("and no companion to match a pane on", lastPlace.companion, nil)
check("and no divider", lastPlace.dividerFrame, nil)
local bare = picker:scene().rects.canvas
send("pressOutside", bare.x + bare.w + 1, bare.y + 5)
check("just past the canvas, a press hides the list without a companion", picker:isActive(), false)
picker:hide()
picker:setPaneWidth(300)
closed = closedBefore

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

-- The panel is handed the Control keys the canvas field keymap reads, A, E, B, F, D, H and K,
-- and H alone as the one that stands for Backspace, so every other Control chord is a leftover.
local sorted = {}
for _, code in ipairs(fieldKeysSent and fieldKeysSent.control or {}) do sorted[#sorted + 1] = code end
table.sort(sorted)
check("the panel is handed exactly the field's Control keys", table.concat(sorted, ","), "0,2,3,4,11,14,40")
check("Control and H stands for Backspace", table.concat(fieldKeysSent and fieldKeysSent.backspace or {}, ","), "4")

-- A scroll over the companion is claimed by the view's own tap, which runs only while it is up.
local function scrollEvent(x, y, dy)
  return {
    location = function() return { x = x, y = y } end,
    getProperty = function(_, prop)
      if prop == "continuous" then return 1 end
      if prop == "point" then return dy end
      return 0
    end,
  }
end
local companionScrolls = {}
picker.config.onScroll = function(points) companionScrolls[#companionScrolls + 1] = points end
picker:show()
local tap = taps[#taps]
check("a started view runs a scroll wheel tap", tap ~= nil and tap.running, true)
check("the tap hears scroll wheel events only", tap and tap.types[1], "scrollWheel")
check("a scroll over the companion is claimed", tap.fn(scrollEvent(companion.x + 5, companion.y + 5, 3)), true)
check("and handed to the engine inverted", companionScrolls[1], -3)
check("a scroll over the list is not claimed", tap.fn(scrollEvent(rects.list.x + 5, rects.list.y + 5, 3)), false)
check("a zero scroll over the companion is not claimed", tap.fn(scrollEvent(companion.x + 5, companion.y + 5, 0)), false)
picker:hide()
check("a stopped view stops its scroll tap", tap.running, false)

-- An unknown id or event answers false and does nothing.
check("an unknown id is ignored", callback(99, "dismiss", keyData(53)), false)
check("an unknown event is ignored", callback(7, "nonsense"), false)

--------------------------------------------------------------------------------
-- The provider, serving the fallback whenever the library is not loaded
--------------------------------------------------------------------------------

local lines = {}
local log = {
  i = function(m) lines[#lines + 1] = "i " .. m end,
  e = function(m) lines[#lines + 1] = "e " .. m end,
}
local fallback = {
  new = function(config) return { fromFallback = true, config = config } end,
  uses = function() return "the canvas field's answer" end,
}
-- A directory that exists, the system's temporary one, so a finished build can be renamed in.
local scratch = os.tmpname()
os.remove(scratch)
local dir = scratch:match("(.*)/")
dirs[dir] = {}

-- A command line tools directory with clang and SDKs, the way the toolchain check reads one.
local CLT = "/CLT"
local SWIFTC = CLT .. "/usr/bin/swiftc"
dirs[CLT .. "/SDKs"] = { "MacOSX26.sdk", "MacOSX27.0.sdk", "MacOSX27.sdk" }

local Provider = dofile(spoon .. "lib/chooser/providers/swift/init.lua")

Provider.configure({ ui = UI, fallback = fallback, dir = dir, swiftc = nil, log = log })
check("with no compiler the fallback serves", Provider.serving(), "fallback")
check("new answers the fallback's instance", Provider.new({}).fromFallback, true)
check("the missing tools are said once", #lines, 1)
check("naming the default chooser", lines[1], "i swift chooser, no compiler inside the command line tools, so the default chooser serves")
check("and nothing is run", #tasks, 0)
check("uses answers for the fallback's field while it serves", Provider.uses(0, { "ctrl" }), "the canvas field's answer")
check("no native pane backend while the fallback serves", Provider.paneBackend(), nil)

lines = {}
Provider.configure({ ui = UI, fallback = fallback, dir = dir, swiftc = SWIFTC, log = log })
check("tools without clang serve the fallback", lines[1], "i swift chooser, the command line tools have no clang, so the default chooser serves")
check("and run nothing", #tasks, 0)

files[CLT .. "/usr/bin/clang"] = true
dirs[CLT .. "/SDKs"] = { "MacOSX26.sdk" }
lines = {}
Provider.configure({ ui = UI, fallback = fallback, dir = dir, swiftc = SWIFTC, log = log })
check("tools with no SDK for this macOS serve the fallback", lines[1], "i swift chooser, the command line tools have no macOS 27 SDK, so the default chooser serves")
check("and still run nothing", #tasks, 0)

dirs[CLT .. "/SDKs"] = { "MacOSX26.sdk", "MacOSX27.0.sdk", "MacOSX27.sdk" }
lines = {}
Provider.configure({ ui = UI, fallback = fallback, dir = dir, swiftc = SWIFTC, log = log })
check("a missing library starts a build", #tasks, 1)
local args = tasks[1] and tasks[1].args or {}
check("the build is handed the SDK the check found", args[3] == "-sdk" and args[4], CLT .. "/SDKs/MacOSX27.sdk")
check("the fallback serves while it builds", Provider.serving(), "fallback")
check("one line says the swift chooser takes over later",
  lines[1], "i swift chooser, building the library, the default chooser serves until the next reload")

-- The build finishing in this session does not switch providers under the shared picker, and it
-- leaves the newest three outputs of its name, itself among them.
local output = tasks[1].args[#tasks[1].args]
local built = output:gsub("%.building$", "")
local builtName = built:match("[^/]+$")
local olds = { "swiftchooser-aaaa.so", "swiftchooser-bbbb.so", "swiftchooser-cccc.so", "swiftchooser-dddd.so" }
for i, name in ipairs(olds) do files[dir .. "/" .. name] = { modification = 100 + i } end
dirs[dir] = { olds[1], olds[2], olds[3], olds[4], builtName, "other-eeee.so" }
local removed = {}
local realRemove = os.remove
os.remove = function(path) removed[#removed + 1] = path:match("[^/]+$") return realRemove(path) end
local handle = io.open(output, "w")
if handle then handle:close() end
tasks[1].callback(0, "", "")
os.remove = realRemove
os.remove(built)
table.sort(removed)
check("a finished build is said", lines[2], "i swift chooser, the library is built and takes over from the next reload")
check("the fallback still serves this session", Provider.serving(), "fallback")
check("the build removes all but the newest three of its name",
  table.concat(removed, ","), "swiftchooser-aaaa.so,swiftchooser-bbbb.so")

-- A failed build says the compiler's error.
lines = {}
dirs[dir] = {}
Provider.configure({ ui = UI, fallback = fallback, dir = dir, swiftc = SWIFTC, log = log })
tasks[#tasks].callback(1, "", "Panel.swift:1: error: nope")
check("a failed build says the compiler's error", lines[#lines]:match("error: nope") ~= nil, true)
check("the fallback serves after a failed build", Provider.serving(), "fallback")

-- A library already built is loaded at configure. Its module table carries the sentinel, here a
-- table whose __gc stands in for the native one, and the provider keeps the table for the
-- session, so a collection never finalizes it early and close the panels under an open list.
local Loaded = dofile(spoon .. "lib/chooser/providers/swift/init.lua")
local finalized = false
local loadedNative = {}
for k, v in pairs(native) do loadedNative[k] = v end
loadedNative._sentinel = setmetatable({}, { __gc = function() finalized = true end })
local realLoadlib = package.loadlib
package.loadlib = function() return function() return loadedNative end end
local spec = Loaded.spec({ dir = dir, swiftc = SWIFTC, sdk = CLT .. "/SDKs/MacOSX27.sdk",
  frameworks = hs.processInfo.bundlePath .. "/Contents/Frameworks" })
local present = dir .. "/swiftchooser-" .. dofile(spoon .. "lib/swiftbuild.lua").hash(spec) .. ".so"
files[present] = true
lines = {}
local tasksBefore = #tasks
Loaded.configure({ ui = UI, fallback = fallback, dir = dir, swiftc = SWIFTC, log = log })
package.loadlib = realLoadlib
loadedNative = nil
collectgarbage("collect")
collectgarbage("collect")
check("a built library serves at once", Loaded.serving(), "swift")
check("without a build", #tasks, tasksBefore)
check("and without a line", #lines, 0)
check("the module table and its sentinel live through a collection", finalized, false)
local instance = Loaded.new({ rows = function() return {} end })
check("new builds the engine over the native view", instance.view ~= nil and instance.fromFallback == nil, true)
check("uses answers for the native field, Control and A", Loaded.uses(0, { "ctrl" }), "the field's own moveToStart")
check("uses leaves Control and T free, the native field reads none", Loaded.uses(17, { "ctrl" }), nil)
check("uses still answers the engine's own keys", Loaded.uses(53, {}), "Escape closes the list")
check("a loaded library answers the native pane backend's factory", type(Loaded.paneBackend()), "function")

if failed then
  print("swiftview, FAILED")
  os.exit(1)
end
print("swiftview, every case passed")
