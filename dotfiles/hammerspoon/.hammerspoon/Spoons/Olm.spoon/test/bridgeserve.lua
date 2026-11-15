-- host/bridge's socket half in plain Lua, step 2.2 of docs/PLAN-STANDALONE.md. It pins the framing
-- of frame.lua, the routing of rpc.lua, hello first, the error codes, a method that raises and a
-- superseded rows answered stale, and then replays test/fixtures/bridge/launcher.json against
-- serve.lua over a fake launcher, the conversation docs/PROTOCOL-BRIDGE.md writes.
--
-- It needs no Hammerspoon and no lock.
--
-- Run it.
--   lua test/bridgeserve.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local replay = assert(loadfile(here .. "bridgereplay.lua"))()
local json, frame, rpc, serve = replay.json, replay.frame, replay.rpc, replay.serve
local encode, JSON = replay.encode, replay.JSON

local failures, checks = 0, 0
local function ok(cond, what)
  checks = checks + 1
  if not cond then
    failures = failures + 1
    print("  FAIL  " .. what)
  end
end

--------------------------------------------------------------------------------
-- The framing
--------------------------------------------------------------------------------

ok(frame.encode('{"a":1}') == '7\n{"a":1}', "a message is its length, a newline and the JSON")
ok(frame.length("7\n") == 7, "the length line reads as its count")
ok(frame.length("0\n") == 0, "and zero is a length")
ok(frame.length("x7\n") == nil and frame.length("7") == nil, "anything but digits and a newline is refused")
ok(frame.length(tostring(frame.MAX + 1) .. "\n") == nil, "a length past 8 MiB is refused")
ok(frame.length(tostring(frame.MAX) .. "\n") == frame.MAX, "and 8 MiB itself is allowed")
local clean, lossy = frame.clean("caf\xC3\xA9")
ok(clean == "café" and lossy == false, "valid UTF-8 is left as it is")
clean, lossy = frame.clean("a\xFFb\xC3")
ok(clean == "a\u{FFFD}b\u{FFFD}" and lossy == true, "each invalid byte becomes U+FFFD, and says so")

--------------------------------------------------------------------------------
-- The routing
--------------------------------------------------------------------------------

local sent, queued = {}, {}
local function drain()
  while #queued > 0 do table.remove(queued, 1)() end
end
local ran = 0
local session = rpc.new({ json = JSON, send = function(t) sent[#sent + 1] = json.decode(t) end,
  defer = function(fn) queued[#queued + 1] = fn end,
  methods = {
    hello = { run = function(_, s) s.open = true; return { protocol = 1 } end },
    boom = { run = function() error("the plugin fell over") end },
    rows = { supersedes = function(p) return p.level end, run = function(p) ran = ran + 1; return { q = p.q } end },
  } })

session:receive("not json")
ok(sent[1] and sent[1].error.code == rpc.PARSE and sent[1].id == json.null, "a message that is not JSON is answered -32700 with a null id")
session:receive(encode({ jsonrpc = "2.0", id = "x", method = "boom" }))
ok(sent[2].error.code == rpc.INVALID, "nothing is run before hello")
session:receive(encode({ jsonrpc = "2.0", id = "h", method = "hello", params = { protocol = 1 } }))
ok(sent[3].result.protocol == 1, "hello opens the session")
session:receive(encode({ jsonrpc = "2.0", id = "b", method = "boom" }))
ok(sent[4].error.code == rpc.RAISED and sent[4].error.data.message:find("fell over") ~= nil,
  "a method that raises answers -32014 with what it said")
session:receive(encode({ jsonrpc = "2.0", id = "n", method = "nothere" }))
ok(sent[5].error.code == rpc.UNKNOWN, "an unknown method answers -32601")
local before = #sent
session:receive(encode({ jsonrpc = "2.0", method = "nothere" }))
ok(#sent == before, "and an unknown notification answers nothing")
session:receive(encode({ jsonrpc = "2.0", id = "r1", method = "rows", params = { level = "v1", q = 1 } }))
session:receive(encode({ jsonrpc = "2.0", id = "r2", method = "rows", params = { level = "v1", q = 2 } }))
session:receive(encode({ jsonrpc = "2.0", id = "r3", method = "rows", params = { level = "v2", q = 1 } }))
ok(sent[#sent].id == "r1" and sent[#sent].error.code == rpc.STALE, "a rows request superseded before it ran is answered stale")
drain()
ok(ran == 2, "and never run, while the newest and another level's are")
ok(sent[#sent - 1].id == "r2" and sent[#sent - 1].result.q == 2 and sent[#sent].id == "r3",
  "each runs on the next turn, in order")
session:reset()
session:receive(encode({ jsonrpc = "2.0", id = "z", method = "rows", params = { level = "v1", q = 3 } }))
ok(sent[#sent].error.code == rpc.INVALID, "a reset session asks for hello again")

--------------------------------------------------------------------------------
-- The transcripts, as fixtures.lua runs them
--------------------------------------------------------------------------------

local f = assert(io.open(here .. "fixtures/bridge/launcher.json", "r"))
local file = json.decode(f:read("a"))
f:close()
for _, case in ipairs(file.cases) do
  local problems = replay.replay(case)
  for _, p in ipairs(problems) do ok(false, case.name .. ", " .. p) end
  ok(#problems == 0, case.name .. " replays")
end
local memoryKey = replay.memoryKey

-- A launcher whose rows raise costs that answer and leaves the level open.
local raising = serve.new({ rpc = rpc, clean = frame.clean,
  launcher = { rows = function() error("rows broke") end, memoryKey = memoryKey },
  icons = function() return nil end })
local said = {}
local r = rpc.new({ json = JSON, send = function(t) said[#said + 1] = json.decode(t) end,
  defer = function(fn) queued[#queued + 1] = fn end, methods = raising.methods })
r:receive(encode({ jsonrpc = "2.0", id = "h", method = "hello", params = { protocol = 1 } }))
r:receive(encode({ jsonrpc = "2.0", id = "o", method = "open", params = { what = { launcher = true } } }))
r:receive(encode({ jsonrpc = "2.0", id = "q", method = "rows", params = { level = "v1", q = 1, query = "" } }))
drain()
ok(said[3] and said[3].error.code == rpc.RAISED, "a launcher that raises answers -32014")
ok(raising.levels.v1 ~= nil, "and the level stays open")

-- A row's text that is not UTF-8 crosses replaced and marked lossy.
local bad = serve.new({ rpc = rpc, clean = frame.clean,
  launcher = { rows = function() return { { title = "a\xFFb", item = { kind = "app", bundleID = "x" } } } end, memoryKey = memoryKey },
  icons = function() return nil end })
local catalog = bad.methods.catalog.run({})
ok(catalog.rows[1].title == "a\u{FFFD}b" and catalog.rows[1].lossy == true, "a title that is not UTF-8 crosses cleaned and lossy")

-- A notification of ours goes only once hello has opened the session, step 2.3.
local told = {}
local n = rpc.new({ json = JSON, send = function(t) told[#told + 1] = json.decode(t) end,
  defer = function(fn) queued[#queued + 1] = fn end,
  methods = { hello = { run = function(_, s) s.open = true; return {} end } } })
ok(n:notify("shadow", { query = "ma" }) == false and #told == 0, "nothing is notified before hello")
n:receive(encode({ jsonrpc = "2.0", id = "h", method = "hello", params = { protocol = 1 } }))
ok(n:notify("shadow", { query = "ma" }) == true, "after hello a notification is sent")
ok(told[2] and told[2].method == "shadow" and told[2].id == nil and told[2].params.query == "ma",
  "as a message with a method, its params and no id")
n:reset()
ok(n:notify("shadow", {}) == false, "and a reset session sends none")

-- The memory the app holds is moved by the queries that changed, nothing before a launcher level.
local memory = { ma = { "app:maps", "app:mail" }, sa = { "app:safari" } }
local remembering = serve.new({ rpc = rpc, clean = frame.clean, rowLimit = 50,
  launcher = { rows = function() return {} end, memoryKey = memoryKey, memory = function() return memory end },
  icons = function() return nil end })
ok(remembering.methods.hello.run({ protocol = 1 }, {}).limits.rowLimit == 50,
  "hello sends the row limit the root hands in")
ok(remembering.memoryChanges() == nil, "no memory change is sent before a launcher level opens")
remembering.methods.open.run({ what = { launcher = true } })
ok(remembering.memoryChanges() == nil, "nor when nothing moved since the open")
memory = { ma = { "app:mail", "app:maps" }, sa = { "app:safari" }, te = { "app:terminal" } }
local moved = remembering.memoryChanges()
ok(moved and moved.memory.ma[1] == "app:mail" and moved.memory.te[1] == "app:terminal" and moved.memory.sa == nil,
  "a pick sends the queries whose order moved and the new ones, and leaves the rest out")
memory = { ma = { "app:mail", "app:maps" }, te = { "app:terminal" } }
moved = remembering.memoryChanges()
ok(moved and moved.memory.sa and next(moved.memory.sa) == nil and moved.memory.ma == nil,
  "a forgotten query is sent with an empty order")
ok(remembering.memoryChanges() == nil, "and once sent, nothing more")
memory = { ma = { "app:mail", "app:maps" }, te = { "app:terminal" }, ["a\xC4"] = { "app:cut" } }
ok(remembering.memoryChanges() == nil, "a spelling cut inside a letter never crosses")
remembering.methods.hello.run({ protocol = 1 }, {})
ok(remembering.memoryChanges() == nil, "a new session sends nothing until it opens the launcher again")

-- Choosing, step 3.1. A disabled row runs nothing, a run waits for hidden or the fallback, once.
local picked, later = {}, {}
local choosing = serve.new({ rpc = rpc, clean = frame.clean, later = function(_, fn) later[#later + 1] = fn end,
  launcher = { memoryKey = memoryKey,
    rows = function() return { { title = "Off", enabled = false, item = { kind = "app", bundleID = "off" } },
      { title = "On", item = { kind = "app", bundleID = "on" } } } end,
    choose = function(item) picked[#picked + 1] = item.bundleID; return { { hide = {} } }, function() picked[#picked + 1] = "ran" end end },
  icons = function() return nil end })
choosing.methods.open.run({ what = { launcher = true } })
choosing.methods.rows.run({ level = "v1", q = 1, query = "" })
local off = choosing.methods.choose.run({ level = "v1", q = 1, ref = "v1.1", query = "" })
ok(#off.effects == 0 and #picked == 0, "a disabled row answers no effects and is never handed to the launcher")
local on = choosing.methods.choose.run({ level = "v1", q = 1, ref = "v1.2", query = "" })
ok(#on.effects == 2 and on.effects[2].after == "hidden" and picked[1] == "on" and #picked == 1,
  "a row is handed over, and its run waits behind after hidden")
later[1]()
ok(picked[2] == "ran", "the fallback runs it when hidden never came")
choosing.methods.hidden.run({ level = "v1" })
ok(#picked == 2, "and a hidden after that runs nothing twice")

-- The facade, step 3.3. A word recorded while a request runs, and nothing outside one.
local facade = replay.facade.new()
ok(facade.record({ rows = {} }) == false and facade.recording() == false, "outside a request nothing is recorded")
local recorded, answer = facade.during(function()
  ok(facade.recording(), "inside a request the facade records")
  facade.record({ rows = { hold = true } })
  return "done"
end)
ok(#recorded == 1 and recorded[1].rows.hold == true and answer == "done", "a request answers what was recorded, in order, and what it returned")
ok(not facade.recording(), "and recording ends with it")
local raised = pcall(facade.during, function() error("plugin broke") end)
ok(raised == false and not facade.recording(), "an error ends the recording and is raised again")

-- A hosted level, its redraw, its back and a stage word its Return calls.
local top = { name = "caffeinate", placeholder = "Time", fit = true, matcher = false,
  rows = function() return { { title = "Keep Awake", item = { id = "on" } } } end,
  onSelect = function() facade.record({ rows = { hold = true } }) end }
local child = { name = "caffeinate", rows = function() return {} end, onSelect = function() end }
local paged = { name = "caffeinate", rows = function() return { { title = "Page", item = {} } } end,
  intercept = function() return "stay" end, back = function() facade.record({ rows = { hold = false } }); return true end,
  onSelect = function() return child end }
local hosting = serve.new({ rpc = rpc, clean = frame.clean, facade = facade,
  hosted = function(p) return p.name == "caffeinate" end,
  launcher = { memoryKey = memoryKey, rows = function() return { { title = "Keep Awake", item = { kind = "special", name = "caffeinate" } } } end,
    choose = function(_, _, hosted) return { { present = hosted(top) and top or nil } } end },
  icons = function() return nil end })
ok(#hosting.redraws("caffeinate") == 0, "no redraw is sent while no hosted level is open")
hosting.methods.open.run({ what = { launcher = true } })
hosting.methods.rows.run({ level = "v1", q = 1, query = "" })
local pushed = hosting.methods.choose.run({ level = "v1", q = 1, ref = "v1.1", query = "" })
ok(pushed.effects[1].push and pushed.effects[1].push.level.id == "v2", "a hosted tool's row pushes a level")
hosting.methods.rows.run({ level = "v2", q = 7, query = "" })
local redraws = hosting.redraws("caffeinate")
ok(#redraws == 1 and redraws[1].level == "v2" and redraws[1].q == 7 and redraws[1].effects[1].rows.hold == true,
  "a redraw of the tool reaches its open level, holding the highlight")
ok(hosting.redraws("caffeinate", nil, true)[1].effects[1].rows.hold == false, "and a redraw that resets the row says so")
ok(#hosting.redraws("vpn") == 0 and #hosting.redraws("caffeinate", {}) == 0, "another tool's, or another table's, reaches nothing")
local chose = hosting.methods.choose.run({ level = "v2", q = 7, ref = "v2.1", query = "" })
ok(#chose.effects == 1 and chose.effects[1].hide, "Return on its row closes the list, a redraw asked on the way dropped")
ok(hosting.methods.back.run({ level = "v2" }).handled == false, "a list with no back of its own declines it")
hosting.methods.close.run({ level = "v2" })
ok(#hosting.redraws("caffeinate") == 0, "and a closed level is sent no redraw")

-- A level whose intercept stays, whose back is its own and whose onSelect answers a child.
hosting.levels.v9 = { id = "v9", kind = "launcher" }
local stay = hosting.choosePresented({ kind = "presentation", presentation = paged, id = "v8" }, {})
ok(#stay == 1 and stay[1].rows.hold == true, "an intercept that stays asks the rows again, holding the highlight")
paged.intercept = nil
local drilled = hosting.choosePresented({ kind = "presentation", presentation = paged, id = "v8" }, {})
ok(drilled[1].push and drilled[1].push.parent == "v8" and drilled[1].push.level.name == "caffeinate"
  and hosting.levels[drilled[1].push.level.id].top == false, "an onSelect answering a child pushes it, a level that is not its tool's top")
hosting.levels.v8 = { id = "v8", kind = "presentation", presentation = paged }
local back = hosting.methods.back.run({ level = "v8" })
ok(back.handled == true and back.effects[1].rows.hold == false, "a back of its own is handled, with what it called")

-- Volume, the second hosted tool, its real plugin over a fake output device. One typed row, a
-- disabled one on an empty field or a value out of range, Return setting the level and closing.
local device = { volume = 25, muted = true }
function device:outputVolume() return self.volume end
function device:outputMuted() return self.muted end
function device:setOutputVolume(v) self.volume = v end
function device:setOutputMuted(m) self.muted = m end
function device:name() return "Speakers" end
local savedHs = _G.hs
_G.hs = { audiodevice = { defaultOutputDevice = function() return device end } }
local volume = assert(loadfile(here .. "../plugins/volume/init.lua"))()
local vol = { name = "volume", placeholder = volume.placeholder(), fit = true, matcher = false,
  rows = volume.rows, onSelect = volume.select }
local hostingVolume = serve.new({ rpc = rpc, clean = frame.clean, facade = facade,
  hosted = function(p) return p.name == "volume" end,
  launcher = { memoryKey = memoryKey, rows = function() return { { title = "Volume", item = { kind = "special", name = "volume" } } } end,
    choose = function(_, _, hosted) return { { present = hosted(vol) and vol or nil } } end },
  icons = function() return nil end })
hostingVolume.methods.open.run({ what = { launcher = true } })
hostingVolume.methods.rows.run({ level = "v1", q = 1, query = "" })
local volPush = hostingVolume.methods.choose.run({ level = "v1", q = 1, ref = "v1.1", query = "" }).effects[1].push
ok(volPush and volPush.level.name == "volume" and volPush.level.placeholder == "Volume" and volPush.level.fit == true
  and volPush.level.ranking == "source", "Volume's row pushes its level, fitting, its placeholder and its own order")
local id = volPush.level.id
local function volRows(q, query) return { rows = hostingVolume.methods.rows.run({ level = id, q = q, query = query }).changes.upsert } end
local empty = volRows(2, "")
ok(#empty.rows == 1 and empty.rows[1].enabled == false and empty.rows[1].title == "Volume 25%, muted",
  "an empty field is one disabled row saying the level now")
local noop = hostingVolume.methods.choose.run({ level = id, q = 2, ref = empty.rows[1].ref, query = "" })
ok(#noop.effects == 0 and device.volume == 25, "and Return on it does nothing")
local over = volRows(3, "101")
ok(over.rows[1].enabled == false and over.rows[1].title == "101 is above 100", "a level above 100 is disabled")
local set = volRows(4, "40")
ok(set.rows[1].title == "Set Volume to 40%" and set.rows[1].enabled ~= false, "a level in range is a row that acts")
local setChose = hostingVolume.methods.choose.run({ level = id, q = 4, ref = set.rows[1].ref, query = "40" })
ok(#setChose.effects == 1 and setChose.effects[1].hide and device.volume == 40 and device.muted == false,
  "Return sets the level, unmutes and closes the list")
local mute = volRows(5, "m")
ok(mute.rows[1].title == "Mute", "m means Mute")
hostingVolume.methods.choose.run({ level = id, q = 5, ref = mute.rows[1].ref, query = "m" })
ok(device.muted == true, "and Return mutes")
ok(hostingVolume.methods.back.run({ level = id }).handled == false, "Volume declines back, so the app pops")
_G.hs = savedHs

-- Step 3.3a, a hosted level told its onPresent as it opens and its onClose as it closes, as the
-- Lua stage tells them, a stage word either calls recorded rather than acting.
local told = {}
local scanned = { name = "wifi", placeholder = "Wi-Fi",
  rows = function() return { { title = "Network " .. #told, item = { id = "n" } } } end,
  onSelect = function() end,
  onPresent = function() told[#told + 1] = "present"; facade.record({ rows = { hold = true } }) end,
  onClose = function() told[#told + 1] = "close" end }
local scannedChild = { name = "wifi", rows = function() return {} end, onSelect = function() end,
  onPresent = function() told[#told + 1] = "child present" end,
  onClose = function() told[#told + 1] = "child close" end }
scanned.intercept = nil
local hostingWifi = serve.new({ rpc = rpc, clean = frame.clean, facade = facade,
  hosted = function(p) return p.name == "wifi" end,
  launcher = { memoryKey = memoryKey, rows = function() return { { title = "Wi-Fi", item = { kind = "special", name = "wifi" } } } end,
    choose = function(_, _, hosted) return { { present = hosted(scanned) and scanned or nil } } end },
  icons = function() return nil end })
hostingWifi.methods.open.run({ what = { launcher = true } })
hostingWifi.methods.rows.run({ level = "v1", q = 1, query = "" })
ok(#told == 0, "nothing is told before the row is chosen")
local wifiPush = hostingWifi.methods.choose.run({ level = "v1", q = 1, ref = "v1.1", query = "" }).effects
ok(#told == 1 and told[1] == "present" and #wifiPush == 1 and wifiPush[1].push,
  "choosing the row tells its onPresent once, the redraw it asks dropped, the push alone answered")
ok(not facade.recording(), "and the recording it ran under has ended")
local wifiId = wifiPush[1].push.level.id
local first = hostingWifi.methods.rows.run({ level = wifiId, q = 2, query = "" }).changes.upsert
ok(first[1].title == "Network 1", "the rows asked after it read what onPresent started")
local deeper = hostingWifi.choosePresented({ kind = "presentation", presentation = { name = "wifi",
  onSelect = function() return scannedChild end }, id = wifiId }, {})
ok(told[2] == "child present" and deeper[1].push, "a child pushed over it is told its own onPresent")
hostingWifi.methods.close.run({ level = deeper[1].push.level.id })
ok(told[3] == "child close" and #told == 3, "a child closed is told its onClose, the level under it nothing")
hostingWifi.methods.close.run({ level = wifiId })
ok(told[4] == "close", "closing the level tells its onClose")
hostingWifi.methods.close.run({ level = "v1" })
ok(#told == 4, "the launcher's own close tells no hook")
hostingWifi.methods.open.run({ what = { launcher = true } })
hostingWifi.methods.rows.run({ level = "v4", q = 1, query = "" })
hostingWifi.methods.choose.run({ level = "v4", q = 1, ref = "v4.1", query = "" })
hostingWifi.methods.hello.run({ protocol = serve.PROTOCOL }, {})
ok(told[5] == "present" and told[6] == "close" and next(hostingWifi.levels) == nil,
  "a new session closes every level the last one left, each hosted one told its onClose")
hostingWifi.methods.open.run({ what = { launcher = true } })
hostingWifi.methods.rows.run({ level = "v1", q = 1, query = "" })
hostingWifi.methods.choose.run({ level = "v1", q = 1, ref = "v1.1", query = "" })
hostingWifi.closeAll()
ok(told[8] == "close" and next(hostingWifi.levels) == nil, "and so does a socket that went")

print(string.format("bridgeserve: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
