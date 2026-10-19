-- The two leader adapters' resolvers as they stand today, in plain Lua.
--
-- lib/hyperkey.lua and lib/windowleader.lua are near copies that differ in policy, and the
-- plan to merge them needs a fixed target. This pins what each does now, the differences
-- included, so a change to either shows up as a failed line rather than a surprise. A line
-- here asserts current behaviour and is not a statement that the behaviour is right. Where the
-- two disagree, both answers are written down, and the merge decides which one survives.
--
-- It needs no Hammerspoon and no lock. Both files touch hs only for a logger and the keycode
-- table at bind time, so a small stub stands in for the application, with the logger recording
-- what was warned so the warn once rule can be counted.
--
-- Run it.
--   lua test/leaders.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local lib = here .. "../lib/"

local warnings = {}
hs = {
  keycodes = { map = { a = 0, b = 11, c = 8, left = 123 } },
  logger = {
    new = function()
      return setmetatable({
        w = function(message) warnings[#warnings + 1] = message end,
      }, { __index = function() return function() end end })
    end,
  },
}

local failures, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %s, wanted %s, got %s", what, tostring(want), tostring(got)))
  end
end

-- Every case gets a fresh copy of each file, since the window leader remembers an unknown
-- predicate name at file level and a shared copy would let one case hide another's warning.
local KEY = 106
local function newHyper(predicates)
  local h = assert(loadfile(lib .. "hyperkey.lua"))()
  h:init()
  h:configure({ predicates = predicates })
  return h
end
local function newWindow(predicates)
  local w = assert(loadfile(lib .. "windowleader.lua"))()
  w:init()
  w:configure({ keyCode = KEY, predicates = predicates })
  w:addLeader(KEY)
  return w
end

local function listOf(engine, key)
  local code = hs.keycodes.map[key]
  if engine._leaders then return engine._leaders[KEY].bindings[code] end
  return engine._bindings[code]
end

-- A handler that names itself, so what resolved can be compared by name. noop is whatever the
-- window leader swallows with, found by asking for a handler that is not any of these.
local function handler(name) return function() return name end end
local function nameOf(fn) return fn and fn() or nil end

local live = {}
local predicates = {
  on = function() return true end,
  off = function() return false end,
  ctxA = function() return live.ctxA end,
  ctxB = function() return live.ctxB end,
}

-- A binding whose when is false. Hyper skips it, so with nothing else matching the key
-- resolves to nothing and the event passes through. The window leader keeps the key and
-- swallows it with a noop, so it resolves to a function that does nothing.
do
  local h = newHyper(predicates)
  h:bind("a", handler("gated"), nil, { when = "off" })
  eq(h:_resolve(listOf(h, "a"), {}), nil, "hyper: a false when with nothing else resolves to nothing")

  local w = newWindow(predicates)
  w:bind("a", handler("gated"), nil, { when = "off" })
  local fn, repeats = w:_resolve(listOf(w, "a"), {})
  eq(type(fn), "function", "window: a false when on a catch all resolves to a function")
  eq(nameOf(fn), nil, "window: that function is the noop, it runs nothing")
  eq(repeats, false, "window: the swallowing noop never repeats")

  local wx = newWindow(predicates)
  wx:bind("a", handler("gated"), { "shift" }, { when = "off" })
  wx:bind("a", handler("catch"))
  local fx = wx:_resolve(listOf(wx, "a"), { shift = true })
  eq(nameOf(fx), nil, "window: a false when on a matching exact binding is a noop, not a fall through to the catch all")

  local hx = newHyper(predicates)
  hx:bind("a", handler("gated"), { "shift" }, { when = "off" })
  hx:bind("a", handler("catch"))
  eq(nameOf((hx:_resolve(listOf(hx, "a"), { shift = true }))), "catch",
    "hyper: a false when on a matching exact binding falls through to the catch all")
end

-- Exact modifiers beat a catch all on both, and fn is ignored when comparing.
do
  for _, make in ipairs({ newHyper, newWindow }) do
    local e = make(predicates)
    local which = e._leaders and "window" or "hyper"
    e:bind("a", handler("catch"))
    e:bind("a", handler("shift"), { "shift" })
    eq(nameOf((e:_resolve(listOf(e, "a"), { shift = true }))), "shift", which .. ": exact mods beat the catch all")
    eq(nameOf((e:_resolve(listOf(e, "a"), {}))), "catch", which .. ": no modifiers falls to the catch all")
    eq(nameOf((e:_resolve(listOf(e, "a"), { shift = true, cmd = true }))), "catch",
      which .. ": extra real modifiers do not match an exact binding, so the catch all answers")
    eq(nameOf((e:_resolve(listOf(e, "a"), { shift = true, fn = true }))), "shift",
      which .. ": the fn flag is ignored")
    eq(nameOf((e:_resolve(listOf(e, "a"), { fn = true }))), "catch", which .. ": fn alone is no modifier")

    -- Order of binding does not matter to the tier.
    local r = make(predicates)
    r:bind("b", handler("shift"), { "shift" })
    r:bind("b", handler("catch"))
    eq(nameOf((r:_resolve(listOf(r, "b"), { shift = true }))), "shift", which .. ": an exact binding wins whichever was bound first")

    eq(e:_resolve(nil, {}), nil, which .. ": no list resolves to nothing")
  end
end

-- The repeats flag travels with the binding that was chosen.
do
  for _, make in ipairs({ newHyper, newWindow }) do
    local e = make(predicates)
    local which = e._leaders and "window" or "hyper"
    e:bind("a", handler("catch"))
    e:bind("a", handler("shift"), { "shift" }, { repeats = true })
    local _, rep = e:_resolve(listOf(e, "a"), { shift = true })
    eq(rep, true, which .. ": the chosen binding's repeats flag is returned with it")
    local _, none = e:_resolve(listOf(e, "a"), {})
    eq(none, nil, which .. ": the catch all carries no repeats flag")
  end
end

-- Hyper's modal rule. While any context predicate is live, a binding with no when is dropped,
-- and within a tier the best priority wins. The window leader has no contexts and no priority.
do
  local h = newHyper(predicates)
  h:bind("a", handler("base"))
  h:bind("a", handler("ctxA"), nil, { when = "ctxA", priority = 100 })
  h:bind("a", handler("ctxB"), nil, { when = "ctxB", priority = 200 })
  h:bind("b", handler("baseOnly"))
  local list = listOf(h, "a")

  live.ctxA, live.ctxB = false, false
  eq(nameOf((h:_resolve(list, {}))), "base", "hyper: with no context live the base binding answers")

  live.ctxA, live.ctxB = true, false
  eq(nameOf((h:_resolve(list, {}))), "ctxA", "hyper: a live context beats the base binding")
  eq(h:_resolve(listOf(h, "b"), {}), nil, "hyper: while a context is live a binding with no when is dropped")

  live.ctxA, live.ctxB = true, true
  eq(nameOf((h:_resolve(list, {}))), "ctxB", "hyper: the higher priority wins between live contexts")

  live.ctxA, live.ctxB = false, true
  eq(nameOf((h:_resolve(list, {}))), "ctxB", "hyper: the one live context answers")

  -- Priority applies inside a tier. An exact binding of low priority still beats a catch all of
  -- high priority, since the tier is decided before the priority.
  local t = newHyper(predicates)
  t:bind("a", handler("catchHigh"), nil, { priority = 9 })
  t:bind("a", handler("exactLow"), { "shift" }, { priority = 1 })
  t:bind("a", handler("exactHigh"), { "shift" }, { priority = 5 })
  eq(nameOf((t:_resolve(listOf(t, "a"), { shift = true }))), "exactHigh", "hyper: the best priority wins within the exact tier")
  eq(nameOf((t:_resolve(listOf(t, "a"), {}))), "catchHigh", "hyper: with no exact match the catch all tier answers")
  live.ctxA, live.ctxB = false, false

  -- The same shape on the window leader ignores priority, the last eligible catch all wins.
  local w = newWindow(predicates)
  w:bind("a", handler("first"), nil, { priority = 9 })
  w:bind("a", handler("second"))
  eq(nameOf((w:_resolve(listOf(w, "a"), {}))), "second", "window: no priority, the later catch all wins")
end

-- An unknown predicate name. Hyper treats it as active in silence. The window leader treats it
-- as active too, and warns once per name however many presses follow.
do
  local h = newHyper(predicates)
  h:bind("a", handler("typo"), nil, { when = "nope" })
  local before = #warnings
  eq(nameOf((h:_resolve(listOf(h, "a"), {}))), "typo", "hyper: an unknown predicate name passes")
  eq(nameOf((h:_resolve(listOf(h, "a"), {}))), "typo", "hyper: and passes again")
  eq(#warnings, before, "hyper: and says nothing")

  local w = newWindow(predicates)
  w:bind("a", handler("typo"), nil, { when = "nope" })
  before = #warnings
  eq(nameOf((w:_resolve(listOf(w, "a"), {}))), "typo", "window: an unknown predicate name passes")
  eq(#warnings, before + 1, "window: and warns")
  eq(nameOf((w:_resolve(listOf(w, "a"), {}))), "typo", "window: and passes again")
  eq(#warnings, before + 1, "window: and warns only once per name")
  w:bind("b", handler("other"), nil, { when = "nope2" })
  w:_resolve(listOf(w, "b"), {})
  eq(#warnings, before + 2, "window: a second unknown name warns on its own")
end

-- A binding is reachable only through the keycode table. An unknown key is dropped with a
-- warning on both, which is the same on both and worth pinning before a merge touches bind.
do
  local h = newHyper(predicates)
  local before = #warnings
  h:bind("nokey", handler("x"))
  eq(next(h._bindings), nil, "hyper: an unknown key is not stored")
  eq(#warnings, before + 1, "hyper: and is warned about")

  local w = newWindow(predicates)
  before = #warnings
  w:bind("nokey", handler("x"))
  eq(next(w._leaders[KEY].bindings), nil, "window: an unknown key is not stored")
  eq(#warnings, before + 1, "window: and is warned about")
end

print(string.format("leaders: %d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
