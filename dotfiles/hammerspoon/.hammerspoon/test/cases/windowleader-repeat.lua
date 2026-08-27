-- Unit case for the repeat half of Olm.spoon/plugins/windowleader/init.lua, the leader
-- deciding that its keys are driven and carrying each binding's own repeat flag through to
-- the shared engine. The dispatch itself is an event tap and is not reachable from here, so
-- this covers what the leader ANSWERS, which is the pair its onKey contract owes the engine.
--
-- Loaded into an environment of this case's own, with a fake hs in it, for the same reason
-- cases/chordkey-repeat.lua does it, and with a stub engine standing in for ChordKey so what
-- the leader registers can be read rather than inferred.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local modulePath = caseDir .. "/../../Spoons/Olm.spoon/plugins/windowleader/init.lua"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

-- Two keys are enough for every check below, and naming them here keeps the case free of raw
-- keycodes standing in for letters.
local KEYS = { d = 2, s = 1, f16 = 106 }

local function freshModule()
  local fakeHs = {
    logger = { new = function() return { w = function() end, e = function() end, i = function() end } end },
    keycodes = { map = KEYS },
  }
  local env = {
    hs = fakeHs, math = math, table = table, string = string,
    type = type, pairs = pairs, ipairs = ipairs, tostring = tostring, print = print,
  }
  local chunk, err = loadfile(modulePath, "t", env)
  if not chunk then
    error("could not load plugins/windowleader/init.lua, " .. tostring(err))
  end
  return chunk()
end

local function stubEngine()
  local engine = { registered = {} }
  function engine:addKey(code, opts) self.registered[code] = opts end
  return engine
end

-- A binding says whether it repeats and the leader answers with it beside the handler, which
-- is what lets the engine arm a repeat for a move key and not for a maximize key.
do
  local leader = freshModule()
  leader:init()
  leader:addLeader(KEYS.f16)
  local moved, maximized = 0, 0
  leader:bind(KEYS.f16, "d", function() moved = moved + 1 end, nil, true)
  leader:bind(KEYS.f16, "s", function() maximized = maximized + 1 end)

  local bindings = leader._leaders[KEYS.f16].bindings
  local fn, repeats = leader:_resolve(bindings[KEYS.d], {})
  check("a repeating binding answers its handler and a true repeat flag",
    type(fn) == "function" and repeats == true, "repeats is " .. tostring(repeats))

  local fn2, repeats2 = leader:_resolve(bindings[KEYS.s], {})
  check("a binding that said nothing answers no repeat flag",
    type(fn2) == "function" and not repeats2, "repeats is " .. tostring(repeats2))

  local none, noneRepeats = leader:_resolve(nil, {})
  check("an unbound key answers nothing at all", none == nil and noneRepeats == nil)
end

-- Two tiers on one key, a bare press and a Shift press, each carry their own answer, since
-- the flag has to travel with the handler that actually resolved rather than with the key.
do
  local leader = freshModule()
  leader:init()
  leader:addLeader(KEYS.f16)
  leader:bind(KEYS.f16, "d", function() end, { "shift" }, false)
  leader:bind(KEYS.f16, "d", function() end, nil, true)

  local bindings = leader._leaders[KEYS.f16].bindings[KEYS.d]
  local _, bare = leader:_resolve(bindings, {})
  local _, shifted = leader:_resolve(bindings, { shift = true })
  check("the catch-all tier keeps its own repeat flag", bare == true, "got " .. tostring(bare))
  check("the exact-mods tier keeps its own repeat flag", shifted == false, "got " .. tostring(shifted))
end

-- The leader registers its keys as driven, since window keys are steps rather than
-- states, and it hands the engine an onKey that answers the pair.
do
  local leader = freshModule()
  leader:init()
  local engine = stubEngine()
  leader:configure({ chord = engine })
  leader:addLeader(KEYS.f16)
  leader:bind(KEYS.f16, "d", function() end, nil, true)
  leader:start()

  local opts = engine.registered[KEYS.f16]
  check("the leader registered itself into the engine", opts ~= nil)
  check("it registers as driven rather than riding the OS autorepeat",
    opts and opts.repeatMode == "driven", "got " .. tostring(opts and opts.repeatMode))

  local fn, repeats = opts.onKey(KEYS.d, {})
  check("its onKey answers the handler and the repeat flag together",
    type(fn) == "function" and repeats == true, "repeats is " .. tostring(repeats))
  check("it offers no tap fallback, as before", opts.onTap == nil)
end

-- A keyboard that wants the plain OS feel back says so through configure, and nothing else
-- about the leader changes.
do
  local leader = freshModule()
  leader:init()
  local engine = stubEngine()
  leader:configure({ chord = engine, repeatMode = "system" })
  leader:addLeader(KEYS.f16)
  leader:start()
  check("configure can put the leader back on the system autorepeat",
    engine.registered[KEYS.f16].repeatMode == "system",
    "got " .. tostring(engine.registered[KEYS.f16].repeatMode))
end
