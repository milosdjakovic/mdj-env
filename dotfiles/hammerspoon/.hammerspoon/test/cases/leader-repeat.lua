-- Unit case for the repeat half of Olm.spoon/lib/leader.lua, a leader whose policy drives its
-- repeats, as META's does, deciding that its keys are driven and carrying each binding's own
-- repeat flag through to the shared engine. The dispatch itself is an event tap and is not
-- reachable from here, so this covers what the leader ANSWERS, which is the pair its onKey
-- contract owes the engine. It was the window leader's own case until phase 3 of the keymap plan
-- merged that adapter and Hyper's into lib/leader.lua.
--
-- Loaded into an environment of this case's own, with a fake hs in it, for the same reason
-- cases/chordkey-repeat.lua does it, and with a stub engine standing in for ChordKey so what
-- the held trigger registers can be read rather than inferred.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local spoonPath = caseDir .. "/../../Spoons/Olm.spoon/"

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

local function env()
  local fakeHs = {
    logger = { new = function() return { w = function() end, e = function() end, i = function() end } end },
    keycodes = { map = KEYS },
  }
  return {
    hs = fakeHs, math = math, table = table, string = string, setmetatable = setmetatable,
    type = type, pairs = pairs, ipairs = ipairs, tostring = tostring, print = print,
  }
end

local function load(rel)
  local chunk, err = loadfile(spoonPath .. rel, "t", env())
  if not chunk then error("could not load " .. rel .. ", " .. tostring(err)) end
  return chunk()
end

-- A leader with META's shipped policy, on a held trigger over the given engine.
local WINDOW_POLICY = { drivenRepeat = true, quietOverLists = true }
local function freshLeader(engine, policy, predicates)
  local held = load("lib/leader/triggers/held.lua")
  return load("lib/leader.lua").new({
    name = "meta", policy = policy or WINDOW_POLICY, keyCode = KEYS.f16, predicates = predicates,
    trigger = held.new({ chord = engine, keyCode = KEYS.f16 }),
  })
end

local function stubEngine()
  local engine = { registered = {} }
  function engine:addKey(code, opts) self.registered[code] = opts end
  function engine:isActive() return false end
  return engine
end

-- A binding says whether it repeats and the leader answers with it beside the handler, which
-- is what lets the engine arm a repeat for a move key and not for a maximize key.
do
  local leader = freshLeader(stubEngine())
  local moved, maximized = 0, 0
  leader:bind("d", function() moved = moved + 1 end, nil, { repeats = true })
  leader:bind("s", function() maximized = maximized + 1 end)

  local bindings = leader._bindings
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
  local leader = freshLeader(stubEngine())
  leader:bind("d", function() end, { "shift" }, { repeats = false })
  leader:bind("d", function() end, nil, { repeats = true })

  local bindings = leader._bindings[KEYS.d]
  local _, bare = leader:_resolve(bindings, {})
  local _, shifted = leader:_resolve(bindings, { shift = true })
  check("the catch-all tier keeps its own repeat flag", bare == true, "got " .. tostring(bare))
  check("the exact-mods tier keeps its own repeat flag", shifted == false, "got " .. tostring(shifted))
end

-- The leader registers its keys as driven, since window keys are steps rather than
-- states, and it hands the engine an onKey that answers the pair.
do
  local engine = stubEngine()
  local leader = freshLeader(engine)
  leader:bind("d", function() end, nil, { repeats = true })
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

-- A leader whose policy does not drive its repeats leaves the engine's own mode, which is the
-- plain OS feel, and nothing else about the leader changes.
do
  local engine = stubEngine()
  local leader = freshLeader(engine, { quietOverLists = true })
  leader:start()
  check("a policy that does not drive repeats leaves the engine's own mode",
    engine.registered[KEYS.f16].repeatMode == nil,
    "got " .. tostring(engine.registered[KEYS.f16].repeatMode))
end

-- A binding that carries a gate is gated live by the injected predicate table. A false predicate
-- makes the key a swallowed no op, bound and inert, and it does not fall through to a catch all
-- beside it. A true one acts, and an unknown name stays active so a typo fails visibly.
do
  local open = false
  local leader = freshLeader(stubEngine(), nil, { multipleDisplays = function() return open end })
  local fired = 0
  leader:bind("d", function() fired = fired + 1 end, nil, { gate = "multipleDisplays" })
  leader:bind("s", function() fired = fired + 10 end, nil, { gate = "typo" })
  local bindings = leader._bindings

  local fn, repeats = leader:_resolve(bindings[KEYS.d], {})
  check("a false predicate still answers a handler, so the key is swallowed",
    type(fn) == "function" and not repeats)
  fn()
  check("a false predicate makes the key a no op", fired == 0, "fired " .. fired)

  open = true
  local fn2 = leader:_resolve(bindings[KEYS.d], {})
  fn2()
  check("a true predicate lets the action run", fired == 1, "fired " .. fired)

  local fn3 = leader:_resolve(bindings[KEYS.s], {})
  fn3()
  check("an unknown predicate name is treated as active", fired == 11, "fired " .. fired)
end
