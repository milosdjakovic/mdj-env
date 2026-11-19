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

-- A tool's own key, step 3.8, its hosted list opened as the only level, the push's own fields.
local owning = serve.new({ rpc = rpc, clean = frame.clean, facade = facade,
  hosted = function(p) return p.name == "caffeinate" end,
  presentationFor = function(name) return name == "caffeinate" and top or (name == "vpn" and { name = "vpn" }) or nil end,
  launcher = { memoryKey = memoryKey, rows = function() return {} end },
  icons = function() return nil end })
local opened = owning.methods.open.run({ what = { tool = "caffeinate" }, query = "" })
ok(opened.level and opened.level.id == "v1" and opened.level.name == "caffeinate" and opened.level.placeholder == "Time"
  and opened.level.fit == true and opened.level.ranking == "source", "a hosted tool opens as a level with its presentation's fields")
ok(owning.levels.v1.top == true and owning.levels.v1.parent == nil, "the tool's top level, with no parent under it")
local ownRows = owning.methods.rows.run({ level = "v1", q = 1, query = "" })
ok(ownRows.changes and #ownRows.changes.upsert == 1, "and answers its rows")
ok(#owning.redraws("caffeinate") == 1, "a redraw of the tool reaches it")
local pendingAsk = owning.methods.open.run
local waiting = serve.new({ rpc = rpc, clean = frame.clean, facade = facade,
  hosted = function(p) return p.name == "caffeinate" end,
  presentationFor = function() return top end,
  pending = function(name) return name == "caffeinate" and { placeholder = "Waiting" } or nil end,
  launcher = { memoryKey = memoryKey, rows = function() return {} end },
  icons = function() return nil end })
ok(waiting.methods.open.run({ what = { tool = "caffeinate" }, query = "" }).level.placeholder == "Waiting",
  "a placeholder set while the key was opening the list is the level's")
local placed = owning.effectsOf({ id = "v1" }, { { setPlaceholder = { text = "Duration" } } })
ok(placed[1].setPlaceholder and placed[1].setPlaceholder.level == "v1" and placed[1].setPlaceholder.text == "Duration",
  "a placeholder a hosted list's code set is an effect naming its level")
local refused = pcall(pendingAsk, { what = { tool = "vpn" }, query = "" })
ok(refused == false, "a tool the config does not host is not served")
local unknown = pcall(owning.methods.open.run, { what = { tool = "nothing" }, query = "" })
ok(unknown == false, "nor is a name with no presentation")

-- Its cycle key, step 3.9, the level carrying the idle, and a key typed over it posted only once
-- the app has hidden.
local laters, retyped = {}, {}
local cycling = serve.new({ rpc = rpc, clean = frame.clean, facade = facade, cycleIdle = 0.8,
  hosted = function(p) return p.name == "caffeinate" end,
  presentationFor = function() return top end,
  retype = function(code, mods) retyped[#retyped + 1] = { code = code, mods = mods } end,
  later = function(_, fn) laters[#laters + 1] = fn end,
  launcher = { memoryKey = memoryKey, rows = function() return {} end },
  icons = function() return nil end })
local cycled = cycling.methods.open.run({ what = { tool = "caffeinate", cycle = true }, query = "" })
ok(cycled.level.cycle and cycled.level.cycle.idle == 0.8, "a cycle key's level carries the idle")
ok(opened.level.cycle == nil, "and a tool's own key's level carries none")
local cid = cycled.level.id
cycling.methods.rows.run({ level = cid, q = 1, query = "" })
local plain = cycling.methods.choose.run({ level = cid, q = 1, ref = cid .. ".1", query = "" })
ok(plain.effects[1].hide and plain.effects[#plain.effects].after == nil, "a choose with no key typed waits for nothing")
local typed = cycling.methods.choose.run({ level = cid, q = 1, ref = cid .. ".1", query = "",
  retype = { code = 0, mods = { "shift", 3 } } })
ok(typed.effects[1].hide and typed.effects[#typed.effects].after == "hidden", "a key typed over it closes and waits for hidden")
ok(#retyped == 0, "nothing is typed before the app has hidden")
cycling.methods.hidden.run({ level = cid })
ok(#retyped == 1 and retyped[1].code == 0 and #retyped[1].mods == 1 and retyped[1].mods[1] == "shift",
  "the key is typed once it has, with its named modifiers only")
laters[#laters]()
ok(#retyped == 1, "and the fallback after it types nothing twice")

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
ok(hostingWifi.hostedTop() == "wifi", "the hosted list on top is named, the deepest level open")
hostingWifi.methods.close.run({ level = deeper[1].push.level.id })
ok(told[3] == "child close" and #told == 3, "a child closed is told its onClose, the level under it nothing")
hostingWifi.methods.close.run({ level = wifiId })
ok(told[4] == "close", "closing the level tells its onClose")
ok(hostingWifi.hostedTop() == nil, "and none once the launcher is on top again")
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

-- Step 3.3b, a hosted list's actions pane. The verbs are the root's, faked here in the shape Tmux
-- Sessions answers them, one keyless Terminal verb with choices and a confirm beside it.
local ran = {}
local terminal = "Ghostty"
local verbs = {
  ids = function(name) return name == "tmuxsessions" and { "insertSelected", "setTerminal", "forget" } or {} end,
  actions = function(_, item)
    local out = { { action = "insertSelected", title = "Select" }, { action = "setTerminal", title = "Terminal" } }
    if item and item.id == "old" then out[#out + 1] = { action = "forget", title = "Forget" } end
    return out
  end,
  level = function(_, action)
    if action == "forget" then
      return { { title = "Cancel", icon = "cancel", iconOwner = "actionspane", cancel = true },
               { title = "Forget this session", icon = "clear", iconOwner = "tmuxsessions" } }
    end
    return { { title = "Ghostty", subTitle = "Installed", icon = "chosen", iconOwner = "actionspane", current = terminal == "Ghostty", value = "Ghostty" },
             { title = "Kitty", subTitle = "Installed", icon = "notChosen", iconOwner = "actionspane", value = "Kitty" },
             { title = "WezTerm", subTitle = "Not installed", icon = "notChosen", iconOwner = "actionspane", enabled = false, value = "WezTerm" } }
  end,
  run = function(_, action, item, value)
    ran[#ran + 1] = { action = action, item = item, value = value }
    if action == "setTerminal" then terminal = value; facade.record({ rows = { hold = true } }) end
  end,
}
local sessions = { name = "tmuxsessions", placeholder = "Search sessions and windows",
  rows = function() return { { title = "main", item = { id = "main" } }, { title = "old", item = { id = "old" } } } end,
  onSelect = function() end }
local hostingTmux = serve.new({ rpc = rpc, clean = frame.clean, facade = facade, verbs = verbs,
  hosted = function(p) return p.name == "tmuxsessions" end,
  launcher = { memoryKey = memoryKey, rows = function() return { { title = "Tmux Sessions", item = { kind = "special", name = "tmuxsessions" } } } end,
    choose = function(_, _, hosted) return { { present = hosted(sessions) and sessions or nil } } end },
  icons = function() return nil end })
hostingTmux.methods.open.run({ what = { launcher = true } })
hostingTmux.methods.rows.run({ level = "v1", q = 1, query = "" })
local tmuxPush = hostingTmux.methods.choose.run({ level = "v1", q = 1, ref = "v1.1", query = "" }).effects[1].push
ok(tmuxPush and #tmuxPush.level.actions == 3 and tmuxPush.level.actions[2] == "setTerminal",
  "the pushed level names every action its list's actions pane lists")
local tid = tmuxPush.level.id
local tmuxRows = hostingTmux.methods.rows.run({ level = tid, q = 2, query = "" }).changes.upsert
local mainRef, oldRef = tmuxRows[1].ref, tmuxRows[2].ref
local listed = hostingTmux.methods.actions.run({ level = tid, h = 3, ref = mainRef }).actions
ok(#listed == 2 and listed[2].action == "setTerminal" and listed[2].title == "Terminal",
  "actions answers the verbs that apply to the row, with their titles")
ok(#hostingTmux.methods.actions.run({ level = tid, h = 3, ref = oldRef }).actions == 3,
  "a verb whose applies holds only for another row is listed there")
local choices = hostingTmux.methods.choices.run({ level = tid, h = 3, ref = mainRef, action = "setTerminal" }).choices
ok(#choices == 3 and choices[1].current == true and choices[1].icon.owner == "actionspane" and choices[1].icon.key == "chosen"
  and choices[2].current == nil and choices[3].enabled == false and choices[1].subtitle == "Installed",
  "choices answers the verb's level, the one in force marked current, a choice this machine cannot take disabled")
ok(choices[1].value == nil and choices[1].choice == "c1", "a choice crosses as a ref, its value kept on the Lua side")
local setRun = hostingTmux.methods.run.run({ level = tid, q = 2, h = 3, ref = mainRef, query = "", action = "setTerminal", choice = choices[2].choice })
ok(ran[1].action == "setTerminal" and ran[1].value == "Kitty" and ran[1].item.id == "main" and terminal == "Kitty",
  "run hands the verb the chosen value and the row it was chosen over")
ok(#setRun.effects == 1 and setRun.effects[1].rows.hold == true and not facade.recording(),
  "and answers what the verb called, a redraw holding the highlight, recorded rather than acting")
hostingTmux.methods.run.run({ level = tid, q = 2, h = 3, ref = mainRef, query = "", action = "setTerminal", choice = choices[3].choice })
ok(#ran == 1, "a disabled choice runs nothing")
local confirm = hostingTmux.methods.choices.run({ level = tid, h = 3, ref = oldRef, action = "forget" }).choices
ok(confirm[1].cancel == true and confirm[1].title == "Cancel" and confirm[2].title == "Forget this session",
  "a confirm's level is Cancel first and then the confirm row")
hostingTmux.methods.run.run({ level = tid, q = 2, h = 3, ref = oldRef, query = "", action = "forget", choice = confirm[1].choice })
ok(#ran == 1, "Cancel runs nothing")
hostingTmux.methods.run.run({ level = tid, q = 2, h = 3, ref = oldRef, query = "", action = "forget", choice = confirm[2].choice })
ok(ran[2].action == "forget" and ran[2].value == nil and ran[2].item.id == "old", "the confirm row runs the verb plainly")
local refused = pcall(hostingTmux.methods.actions.run, { level = "v1", h = 1, ref = "v1.1" })
ok(refused == false, "the launcher's own level serves no actions pane")

-- Step 3.3c, what a hosted list's code records made into effects for the level it ran on, the
-- word answering from the request's own context. The bridge host's hostedWord is faked here as
-- the facade's own context read, test/bridge.lua pinning the real one.
local function word(name, ...)
  if not facade.recording() then return false end
  local ctx = facade.context() or {}
  if name == "stageSelectedItem" then return true, ctx.item end
  if name == "stageQuery" then return true, ctx.query end
  if name == "stageHide" then facade.record({ hide = {} }); return true end
  if name == "stagePop" then facade.record({ pop = {} }); return true, true end
  if name == "stageSetQuery" then facade.record({ setQuery = { query = (...) } }); return true end
  if name == "stagePush" then facade.record({ pushChild = (...) }); return true, true end
end
local copied
local settingsLevel = { name = "browserTabs", rows = function() return { { title = "Back", item = { to = "back" } }, { title = "Safari", item = { id = "safari" } } } end,
  onSelect = function() end,
  intercept = function(item) if item.to == "back" then word("stagePop"); return true end; return "stay" end }
local emojiList = { name = "emoji", placeholder = "Search by name or keyword", rowLimit = 100,
  rows = function(q) return { { title = "Teacup", item = "🍵" }, { title = "Tea" .. (q or ""), item = "🫖" } } end,
  onSelect = function(item) return item == "🫖" and settingsLevel or nil end,
  intercept = function(item) if item == "🔎" then word("stageSetQuery", "tea"); return true end end }
local wordVerbs = { ids = function() return { "insertSelected", "copySelected", "settings" } end,
  actions = function() return {} end, level = function() return {} end,
  run = function(_, action)
    if action == "copySelected" then
      local _, glyph = word("stageSelectedItem")
      local _, q = word("stageQuery")
      copied = glyph .. "|" .. q
      word("stageHide")
    elseif action == "settings" then
      word("stagePush", { rows = function() return {} end, onSelect = function() end })
    end
  end }
local hostingEmoji = serve.new({ rpc = rpc, clean = frame.clean, facade = facade, verbs = wordVerbs,
  hosted = function(p) return p.name == "emoji" end,
  launcher = { memoryKey = memoryKey, rows = function() return { { title = "Emoji", item = { kind = "special", name = "emoji" } } } end,
    choose = function(_, _, hosted) return { { present = hosted(emojiList) and emojiList or nil } } end },
  icons = function() return nil end })
hostingEmoji.methods.open.run({ what = { launcher = true } })
hostingEmoji.methods.rows.run({ level = "v1", q = 1, query = "" })
local emojiPush = hostingEmoji.methods.choose.run({ level = "v1", q = 1, ref = "v1.1", query = "" }).effects[1].push
ok(emojiPush.level.rowLimit == 100, "a hosted level carries its own row limit")
local eid = emojiPush.level.id
local erows = hostingEmoji.methods.rows.run({ level = eid, q = 5, query = "te" }).changes.upsert
local copy = hostingEmoji.methods.run.run({ level = eid, q = 5, h = 2, ref = erows[1].ref, row = 1, query = "te", action = "copySelected" })
ok(copied == "🍵|te", "a verb reading the selected item and the query reads the request's own")
ok(#copy.effects == 1 and copy.effects[1].hide, "and its stageHide is the answer's hide")
local pushedByWord = hostingEmoji.methods.run.run({ level = eid, q = 5, h = 2, ref = erows[1].ref, row = 1, query = "te", action = "settings" }).effects
ok(pushedByWord[1].push and pushedByWord[1].push.parent == eid and pushedByWord[1].push.level.name == "emoji"
  and hostingEmoji.levels[pushedByWord[1].push.level.id] ~= nil, "a stagePush opens a level of its own over the list, named after its tool")
local drilledEffects = hostingEmoji.methods.choose.run({ level = eid, q = 5, ref = erows[2].ref, row = 2, query = "te" }).effects
local sid = drilledEffects[1].push.level.id
local srows = hostingEmoji.methods.rows.run({ level = sid, q = 1, query = "" }).changes.upsert
local popped = hostingEmoji.methods.choose.run({ level = sid, q = 1, ref = srows[1].ref, row = 1, query = "" }).effects
ok(#popped == 2 and popped[1].pop and popped[1].pop.level == sid and popped[2].rows,
  "a row whose intercept pops answers pop naming its own level, then the rows")
local stayed = hostingEmoji.methods.choose.run({ level = sid, q = 1, ref = srows[2].ref, row = 2, query = "" }).effects
ok(#stayed == 1 and stayed[1].rows.hold == true, "a row that stays holds the highlight")
emojiList.rows = function() return { { title = "Search", item = "🔎" } } end
local qrows = hostingEmoji.methods.rows.run({ level = eid, q = 9, query = "" }).changes.upsert
local set = hostingEmoji.methods.choose.run({ level = eid, q = 9, ref = qrows[1].ref, row = 1, query = "" }).effects
ok(set[1].setQuery and set[1].setQuery.query == "tea" and set[1].setQuery.level == eid and set[1].setQuery.q == 9,
  "a stageSetQuery is the answer's setQuery, its level and the q it was asked on")
ok(not facade.recording() and facade.context() == nil, "and nothing is left recording")

-- Browser Tabs' switches, 2026-11-16, a choice saying on crosses with it, and a tab row naming its
-- browser by bundle id crosses as the application's own icon.
local switchVerbs = { ids = function() return { "insertSelected", "toggleBrowser" } end, actions = function() return {} end,
  level = function() return { { title = "Safari", value = "com.apple.Safari", on = true, icon = "checked", iconOwner = "actionspane" },
    { title = "Chrome", value = "com.google.Chrome", on = false, icon = "unchecked", iconOwner = "actionspane" } } end,
  run = function() end }
local tabsList = { name = "browserTabs", rows = function() return { { title = "Docs", image = {}, icon = { app = "com.apple.Safari" }, item = { kind = "tab" } } } end,
  onSelect = function() end }
local hostingTabs = serve.new({ rpc = rpc, clean = frame.clean, facade = facade, verbs = switchVerbs,
  hosted = function(p) return p.name == "browserTabs" end,
  launcher = { memoryKey = memoryKey, rows = function() return { { title = "Browser Tabs", item = { kind = "special", name = "browserTabs" } } } end,
    choose = function(_, _, hosted) return { { present = hosted(tabsList) and tabsList or nil } } end },
  icons = function() return nil end })
hostingTabs.methods.open.run({ what = { launcher = true } })
hostingTabs.methods.rows.run({ level = "v1", q = 1, query = "" })
local tid2 = hostingTabs.methods.choose.run({ level = "v1", q = 1, ref = "v1.1", query = "" }).effects[1].push.level.id
local tabWire = hostingTabs.methods.rows.run({ level = tid2, q = 1, query = "" }).changes.upsert
ok(tabWire[1].icon and tabWire[1].icon.app == "com.apple.Safari", "a row naming an application by bundle id crosses as its icon")
local switches = hostingTabs.methods.choices.run({ level = tid2, h = 1, ref = tabWire[1].ref, action = "toggleBrowser" }).choices
ok(switches[1].on == true and switches[2].on == false and switches[1].icon.key == "checked",
  "a choice saying on crosses with it, its checkbox the mark it wears")

-- A row's own picture, 2026-11-18, a clipboard image's thumbnail, crosses as a Picture where the row
-- names no icon the app resolves, and a row that names one sends no picture beside it.
local thumb, appPic = { thumb = true }, { app = true }
local clipList = { name = "clipboard", rows = function() return {
  { title = "cat.png", image = thumb, item = { kind = "image" } },
  { title = "Docs", image = appPic, icon = { app = "com.apple.Safari" }, item = { kind = "tab" } } } end,
  onSelect = function() end }
local hostingClip = serve.new({ rpc = rpc, clean = frame.clean, facade = facade,
  picture = function(img) return img == thumb and { path = "/tmp/thumb.png" } or { path = "/tmp/other.png" } end,
  hosted = function(p) return p.name == "clipboard" end,
  launcher = { memoryKey = memoryKey, rows = function() return { { title = "Clipboard", item = { kind = "special", name = "clipboard" } } } end,
    choose = function(_, _, hosted) return { { present = hosted(clipList) and clipList or nil } } end },
  icons = function() return nil end })
hostingClip.methods.open.run({ what = { launcher = true } })
hostingClip.methods.rows.run({ level = "v1", q = 1, query = "" })
local cid = hostingClip.methods.choose.run({ level = "v1", q = 1, ref = "v1.1", query = "" }).effects[1].push.level.id
local clipWire = hostingClip.methods.rows.run({ level = cid, q = 1, query = "" }).changes.upsert
ok(clipWire[1].icon == nil and clipWire[1].picture and clipWire[1].picture.path == "/tmp/thumb.png",
  "a row whose only picture is its own crosses with it as a Picture")
ok(clipWire[2].icon and clipWire[2].icon.app == "com.apple.Safari" and clipWire[2].picture == nil,
  "a row naming an icon the app resolves sends no picture beside it")

-- Step 3.3d, the preview pane. A hosted level with a pane says so as it is pushed, a highlight
-- tells onHighlight once per row under the facade, positioned tells onPositioned with both rects, the
-- top level's last highlight answers a stage word asked outside a request, and host/bridge/pane.lua's
-- router and encoder.
local told = { highlight = {}, positioned = {} }
local paneList = { name = "speedtest", previewPaneWidth = function() return true end,
  rows = function() return { { key = "run", title = "Run", item = { pane = "running" } }, { key = "past", title = "Past", item = { pane = "result" } } } end,
  onSelect = function() end,
  onHighlight = function(item)
    told.highlight[#told.highlight + 1] = { item = item, word = facade.recording() and facade.context().item }
  end,
  onPositioned = function(frame, paneFrame) told.positioned[#told.positioned + 1] = { frame = frame, pane = paneFrame } end }
local plainList = { name = "plain", rows = function() return {} end, onSelect = function() end }
local hostingPane = serve.new({ rpc = rpc, clean = frame.clean, facade = facade,
  hosted = function() return true end,
  launcher = { memoryKey = memoryKey, rows = function() return { { title = "Speed Test", item = { kind = "special", name = "speedtest" } },
      { title = "Plain", item = { kind = "special", name = "plain" } } } end,
    choose = function(item) return { { present = item.name == "plain" and plainList or paneList } } end },
  icons = function() return nil end })
hostingPane.methods.open.run({ what = { launcher = true } })
hostingPane.methods.rows.run({ level = "v1", q = 1, query = "" })
local pushed = hostingPane.methods.choose.run({ level = "v1", q = 1, ref = "v1.1", query = "" }).effects[1].push.level
ok(pushed.previewPane == true, "a hosted level whose previewPaneWidth answers true is pushed with its pane")
ok(hostingPane.hasPane(plainList) == false, "and one with no previewPaneWidth has none")
ok(hostingPane.paneLevel("speedtest") and hostingPane.paneLevel("speedtest").id == pushed.id,
  "the pane of a tool on top lands on its level")
ok(hostingPane.paneLevel("plain") == nil, "and no other tool's does")
local pwire = hostingPane.methods.rows.run({ level = pushed.id, q = 1, query = "" }).changes.upsert
hostingPane.methods.positioned.run({ level = pushed.id, frame = { x = 10, y = 20, w = 600, h = 400 },
  paneFrame = { x = 620, y = 20, w = 480, h = 400 } })
ok(#told.positioned == 1 and told.positioned[1].pane.w == 480 and told.positioned[1].frame.x == 10,
  "positioned tells onPositioned the list's rect and the pane's")
hostingPane.methods.positioned.run({ level = pushed.id, frame = { x = 10, y = 20, w = 600, h = 400 }, paneFrame = json.null })
ok(#told.positioned == 2 and told.positioned[2].pane == nil, "and a pane gone as nil")
local shownBefore = hostingPane.shownItem()
ok(shownBefore == false, "no highlight told answers nothing outside a request")
hostingPane.methods.highlight.run({ level = pushed.id, h = 3, ref = pwire[1].ref, row = 1, query = "" })
ok(#told.highlight == 1 and told.highlight[1].item.pane == "running" and told.highlight[1].word == told.highlight[1].item,
  "a highlight tells onHighlight its row, with the stage words reading that row")
hostingPane.methods.highlight.run({ level = pushed.id, h = 4, ref = pwire[1].ref, row = 1, query = "" })
ok(#told.highlight == 1 and hostingPane.paneLevel("speedtest").lit.h == 4,
  "the same row again tells nothing, and keeps the newer h for the next paint")
hostingPane.methods.highlight.run({ level = pushed.id, h = 5, ref = pwire[2].ref, row = 2, query = "" })
ok(#told.highlight == 2 and told.highlight[2].item.pane == "result", "another row tells it again")
local handled, item, row = hostingPane.shownItem()
ok(handled and item.pane == "result" and row == 2, "outside a request the top level's highlighted row answers")
hostingPane.methods.rows.run({ level = pushed.id, q = 2, query = "" })
ok(#told.highlight == 3 and told.highlight[3].item.pane == "result" and told.highlight[3].item ~= told.highlight[2].item,
  "a rebuild that leaves the highlighted row's key with another item tells onHighlight that item")
hostingPane.methods.highlight.run({ level = pushed.id, h = 6, ref = json.null, row = 0, query = "" })
ok(#told.highlight == 4 and told.highlight[4].item == nil, "no row is told as none")
ok(not facade.recording(), "and nothing is left recording")

local paneLib = assert(loadfile(here .. "../host/bridge/pane.lua"))()
local fakeImage, fakeText = setmetatable({}, { __name = "image" }), setmetatable({}, { __name = "styled" })
local encoded, dropped = paneLib.encode({
  { type = "rectangle", action = "fill", frame = { x = 0, y = 0, w = "100%", h = 4 }, fillColor = { red = 1, green = 0.5, blue = 0 },
    roundedRectRadii = { xRadius = 2, yRadius = 2 }, trackMouseUp = true, id = "x" },
  { type = "segments", action = "stroke", coordinates = { { x = 0, y = 1 }, { x = 5, y = 6 } }, strokeColor = { red = 0, green = 0, blue = 1, alpha = 0.5 } },
  { type = "text", text = fakeText, frame = { x = 1, y = 2, w = 3, h = 4 } },
  { type = "text", text = "plain", textFont = "Menlo", textSize = 14, frame = { x = 1, y = 2, w = 3, h = 4 } },
  { type = "image", image = fakeImage, frame = { x = 0, y = 0, w = 16, h = 16 }, imageAlpha = 1 },
  { type = "image", image = setmetatable({}, {}), frame = { x = 0, y = 0, w = 16, h = 16 } },
}, {
  color = function(c) return { red = c.red, green = c.green, blue = c.blue, alpha = c.alpha or 1 } end,
  text = function(t) return t == fakeText and { string = "Hi", font = "SF", size = 14, color = { red = 0, green = 0, blue = 0, alpha = 1 } } or nil end,
  picture = function(i) return i == fakeImage and { path = "/tmp/x.png" } or nil end })
ok(#encoded == 5 and #dropped == 1 and dropped[1] == "image", "a picture that cannot cross is left out and named")
ok(encoded[1].frame.w == "100%" and encoded[1].fillColor.alpha == 1 and encoded[1].roundedRectRadii.xRadius == 2,
  "a shape keeps its frame, radii and colour, alpha filled in")
ok(encoded[1].trackMouseUp == nil and encoded[1].id == nil, "the mouse tracking attributes stay behind")
ok(encoded[2].coordinates[2].y == 6 and encoded[2].strokeColor.alpha == 0.5, "a curve keeps its points")
ok(encoded[3].text.string == "Hi" and encoded[3].text.font == "SF", "a styled text crosses as a Text")
ok(encoded[4].text == "plain" and encoded[4].textFont == "Menlo", "a plain string crosses as it is, with its attributes")
ok(encoded[5].image.path == "/tmp/x.png" and encoded[5].imageAlpha == 1, "a picture crosses as its path")

local hostedNow, calls = false, {}
local function fakeBackend(tag, native)
  return function()
    return { place = function() calls[#calls + 1] = tag .. ":place" end,
      render = function(_, content, scroll) calls[#calls + 1] = tag .. ":render:" .. #content .. ":" .. tostring(scroll ~= nil) end,
      show = function() calls[#calls + 1] = tag .. ":show" end, hide = function() calls[#calls + 1] = tag .. ":hide" end,
      destroy = function() calls[#calls + 1] = tag .. ":destroy" end,
      scrollsNatively = function() return native end }
  end
end
local sentPaint = {}
local router = paneLib.router(fakeBackend("local", true),
  paneLib.backend(function(content, scroll) sentPaint[#sentPaint + 1] = { n = #content, scroll = scroll } end),
  function() return hostedNow end)({ x = 0, y = 0, w = 10, h = 10 })
ok(router.scrollsNatively() == true, "the router scrolls natively where the local backend does")
router.render({}, { {}, {} }, { height = 20 })
ok(calls[#calls] == "local:render:2:true" and #sentPaint == 0, "not hosted, the local backend draws")
hostedNow = true
router.render({}, { {} }, { height = 30, reset = false })
ok(#sentPaint == 1 and sentPaint[1].n == 1 and sentPaint[1].scroll.height == 30, "hosted, the paint goes to the app")
ok(calls[#calls] == "local:hide", "and the local backend it left is hidden")
router.destroy()
ok(calls[#calls] == "local:destroy", "destroy tears down what was built")

--------------------------------------------------------------------------------
-- Step 3.3e, a tool the app serves itself, and a typed word handing the list over
--------------------------------------------------------------------------------

do
  local files = { name = "fileSearch", rows = function() return {} end }
  local speed = { name = "speedtest", placeholder = "Speed", rows = function() return { { title = "Run", item = {} } } end }
  local opened = 0
  speed.onPresent = function() opened = opened + 1 end
  local claim = nil
  local handing = serve.new({ rpc = rpc, clean = frame.clean, facade = facade,
    hosted = function(p) return p.name == "speedtest" end,
    native = function(p) return p.name == "fileSearch" end,
    launcher = { memoryKey = memoryKey,
      rows = function(query)
        if claim and query:sub(1, #claim.prefix) == claim.prefix then
          return { { title = "row", item = { kind = "scope", key = "r" } } }, true, false,
            setmetatable({ prefix = claim.prefix, rest = query:sub(#claim.prefix + 1), target = claim.target },
              { __call = function() error("a hand over is never called over the bridge") end })
        end
        return { { title = "File Search", item = { kind = "special", name = "fileSearch" } },
                 { title = "Speed Test", item = { kind = "special", name = "speedtest" } } }
      end,
      choose = function(item, _, shows)
        local p = item.name == "fileSearch" and files or speed
        return { { present = shows(p) and p or nil } }
      end },
    icons = function() return nil end })
  handing.methods.open.run({ what = { launcher = true } })
  local plain = handing.methods.rows.run({ level = "v1", q = 1, query = "" })
  ok(plain.handOver == nil, "a launcher answer no scope claims hands nothing over")
  local fs = handing.methods.choose.run({ level = "v1", q = 1, ref = "v1.1", query = "" })
  ok(fs.effects[1].native and fs.effects[1].native.name == "filesearch" and not fs.effects[1].push,
    "a served tool's row answers native, by its name lowercased, and opens no level")
  local st = handing.methods.choose.run({ level = "v1", q = 1, ref = "v1.2", query = "" })
  ok(st.effects[1].push and st.effects[1].push.level.name == "speedtest", "a hosted tool's row still pushes its level")

  claim = { prefix = "/ ", target = files }
  local typed = handing.methods.rows.run({ level = "v1", q = 2, query = "/ foo" })
  ok(typed.exclusive == true and typed.handOver and typed.handOver.native
    and typed.handOver.native.name == "filesearch" and typed.handOver.prefix == "/ " and typed.handOver.query == "foo",
    "a claim handing over to a served tool answers native with the word and the rest")

  claim = { prefix = "st ", target = speed }
  opened = 0
  local s1 = handing.methods.rows.run({ level = "v1", q = 3, query = "st " })
  ok(s1.handOver and s1.handOver.push and s1.handOver.push.level.name == "speedtest"
    and s1.handOver.prefix == "st " and s1.handOver.query == "", "a claim handing over to a hosted tool pushes its level")
  local s2 = handing.methods.rows.run({ level = "v1", q = 4, query = "st " })
  ok(s2.handOver.push.level.id == s1.handOver.push.level.id and opened == 1,
    "the same query asked again answers the same level, opened once")
  handing.methods.close.run({ level = s1.handOver.push.level.id })
  local s3 = handing.methods.rows.run({ level = "v1", q = 5, query = "st " })
  ok(s3.handOver.push.level.id ~= s1.handOver.push.level.id and opened == 2,
    "and once the app closed it unused, a new one")

  claim = { prefix = "k ", target = { name = "caffeinate" } }
  ok(handing.methods.rows.run({ level = "v1", q = 6, query = "k 2h" }).handOver == nil,
    "a claim handing over to a list the app does not show carries none")
  claim = { prefix = "x ", target = nil }
  ok(handing.methods.rows.run({ level = "v1", q = 7, query = "x y" }).handOver == nil,
    "and a claim that hands nothing over carries none")
end

print(string.format("bridgeserve: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
