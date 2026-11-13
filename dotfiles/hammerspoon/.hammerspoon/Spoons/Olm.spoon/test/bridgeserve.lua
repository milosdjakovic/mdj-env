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

print(string.format("bridgeserve: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
