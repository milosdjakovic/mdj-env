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

-- The binder, lib/binder.lua, handing keymap rows to these same engines. A row lands on the
-- engine its leader names, with its gate, priority and repeat in the options and nil modifiers
-- for a catch all, a row with no leader goes to the plain combo binder, and the engines receive
-- the rows in the order of the list handed in, which is what decides a tie on one key.
do
  local binder = assert(loadfile(lib .. "binder.lua"))()
  local h, w = newHyper(predicates), newWindow(predicates)
  local plain = {}
  local function row(fields)
    local r = { layer = "global", mods = {}, anyMods = true, owner = "o", action = "x", source = "bindings" }
    for k, v in pairs(fields) do r[k] = v end
    return r
  end
  local rows = {
    row({ layer = "someList", leader = "hyper", key = "c", run = handler("list") }),
    row({ leader = "hyper", key = "a", run = handler("first") }),
    row({ leader = "hyper", key = "a", run = handler("second") }),
    row({ leader = "hyper", key = "b", mods = { "shift" }, anyMods = false, run = handler("shifted") }),
    row({ leader = "meta", key = "c", run = handler("early"), when = "on", repeats = true }),
    row({ leader = "meta", key = "c", run = handler("late") }),
    row({ key = "left", mods = { "alt" }, anyMods = false, run = handler("combo") }),
    row({ leader = "super", key = "a", run = handler("nowhere") }),
    row({ leader = "hyper", key = "b", run = nil }),
    row({ leader = "hyper", key = "b", run = nil, refused = true }),
  }
  local problems = binder.bind(rows, {
    engines = { hyper = h, meta = w },
    hotkey = function(mods, key, fn) plain[#plain + 1] = { mods = mods, key = key, fn = fn } end,
  })

  local a = listOf(h, "a")
  eq(a and #a, 2, "binder: both rows on one hyper key are bound")
  eq(a and nameOf(a[1].fn), "first", "binder: the engine receives rows in the order of the list")
  eq(a and nameOf(a[2].fn), "second", "binder: and never reorders them")
  eq(a and a[1].mods, nil, "binder: a catch all row is bound with nil modifiers")
  local b = listOf(h, "b")
  eq(b and #b, 1, "binder: a row with no function and a refused row are not bound")
  eq(b and table.concat(b[1].mods, "+"), "shift", "binder: an exact row keeps its modifiers")
  local c = listOf(w, "c")
  eq(c and #c, 2, "binder: a row on the window leader lands on the window engine")
  eq(c and c[1].when, "on", "binder: the gate travels in the options")
  eq(c and c[1].repeats, true, "binder: the repeat travels in the options")
  eq(nameOf((w:_resolve(c, {}))), "late", "binder: on the window leader the later catch all wins, so order is kept")
  eq(listOf(h, "c"), nil, "binder: a list's own key is left to the contexts")
  eq(#plain, 1, "binder: a row with no leader goes to the plain combo binder")
  eq(plain[1] and plain[1].key, "left", "binder: with its own key")
  eq(plain[1] and plain[1].mods[1], "alt", "binder: and its own modifiers")
  eq(#problems, 2, "binder: a leader with no engine and a row with no function are each one problem")
  local whys = {}
  for _, pr in ipairs(problems) do whys[#whys + 1] = pr.why end
  local text = table.concat(whys, " | ")
  eq(text:find("no engine binds on the leader super", 1, true) ~= nil, true, "binder: the missing engine is named")
  eq(text:find("answers no function", 1, true) ~= nil, true, "binder: the missing function is named")

  -- A gated global row on Hyper is plain eligibility. It is skipped while its predicate is false,
  -- and while it is true it never makes Hyper modal, so every other base binding still answers.
  local g = newHyper(predicates)
  live.ctxA = true
  binder.bind({
    row({ leader = "hyper", key = "a", run = handler("gated"), when = "ctxA" }),
    row({ leader = "hyper", key = "b", run = handler("plain") }),
  }, { engines = { hyper = g } })
  eq(next(g._contextWhens), nil, "binder: a gated global row is not recorded as a context")
  eq(g:_modal(), false, "binder: with its predicate true Hyper is not modal")
  eq(nameOf((g:_resolve(listOf(g, "b"), {}))), "plain", "binder: so another base key still answers")
  eq(nameOf((g:_resolve(listOf(g, "a"), {}))), "gated", "binder: and the gated key answers while true")
  live.ctxA = false
  eq(g:_resolve(listOf(g, "a"), {}), nil, "binder: and is skipped while false")

  -- A raise inside one engine costs that row and every other row still binds.
  local raising = { bind = function() error("boom") end }
  local h2 = newHyper(predicates)
  local raised = binder.bind({
    row({ leader = "broken", key = "a", run = handler("x") }),
    row({ leader = "hyper", key = "a", run = handler("kept") }),
  }, { engines = { broken = raising, hyper = h2 } })
  eq(#raised, 1, "binder: a raising engine is one problem")
  eq(listOf(h2, "a") and #listOf(h2, "a"), 1, "binder: and the next row still binds")
end

print(string.format("leaders: %d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
