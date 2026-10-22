-- The leader adapter's resolver, in plain Lua.
--
-- Until phase 3 of the keymap plan this pinned two adapters, lib/hyperkey.lua and
-- lib/windowleader.lua, near copies that differed in policy, so the merge had a fixed target. Both
-- are lib/leader.lua now, one adapter whose policy carries every difference, and every case below
-- is the old case asked of the merged adapter with the old adapter's policy. hyper is a ranked
-- leader, as HYPER ships, and window is one that drives its repeats, as META ships. Since phase A
-- of the list keys addendum a binding stating when is a list binding on every leader, so a case
-- that used when as a gate on the window leader states gate, which is what a global row carries. Every case still holds as it was except two, which the plan and Milos agreed and
-- whose names say FLIPPED. A key whose matching bindings are all gated off is swallowed on every
-- leader, where Hyper left it unbound, and an unknown predicate name warns once on every leader,
-- where Hyper said nothing. The cases after those cover what the merge added, the triggers, the
-- quiet rule, the reveal and the release wait, and the last block the composite trigger of phase 1
-- of docs/PLAN-MACHINES.md, a leader on a held key and a set of modifiers at once.
--
-- It needs no Hammerspoon and no lock. The adapter touches hs only for a logger, the keycode table
-- at bind time, a timer for the release wait and the modifiers for the modifier trigger, so a small
-- stub stands in, with the logger recording what was warned so the warn once rule can be counted.
--
-- Run it.
--   lua test/leaders.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local lib = here .. "../lib/"

local warnings = {}
local notes = {}
local toggles = 0
local hotkeysBound = {}
local heldMods = {}
local waits = {}
local taps, timers = {}, {}
hs = {
  keycodes = { map = { a = 0, b = 11, c = 8, left = 123, ["`"] = 50 } },
  logger = {
    new = function()
      return setmetatable({
        w = function(message) warnings[#warnings + 1] = message end,
        i = function(message) notes[#notes + 1] = message end,
      }, { __index = function() return function() end end })
    end,
  },
  hotkey = {
    bind = function(mods, key, press, release, rep)
      hotkeysBound[#hotkeysBound + 1] = { mods = mods, key = key, press = press, release = release, rep = rep }
      return {}
    end,
  },
  eventtap = {
    checkKeyboardModifiers = function() return heldMods end,
    -- A tap that records its types and callback, so a case can drive events through it by hand.
    new = function(types, fn)
      local tap = { types = types, fn = fn, running = false }
      function tap:start() self.running = true return self end
      function tap:stop() self.running = false return self end
      taps[#taps + 1] = tap
      return tap
    end,
    event = { types = { keyDown = 10, flagsChanged = 12 } },
  },
  timer = {
    -- Timers that never fire alone, a case runs one by hand, so every delay and every stop is seen.
    doAfter = function(delay, fn)
      local t = { delay = delay, stopped = false }
      -- A one shot timer that has fired is spent, which counts as stopped.
      t.fn = function() t.stopped = true fn() end
      function t:stop() self.stopped = true end
      timers[#timers + 1] = t
      return t
    end,
    doEvery = function(delay, fn)
      local t = { delay = delay, fn = fn, stopped = false, every = true }
      function t:stop() self.stopped = true end
      timers[#timers + 1] = t
      return t
    end,
    waitUntil = function(pred, fn)
      local w = { pred = pred, fn = fn, stopped = false }
      function w:stop() self.stopped = true end
      waits[#waits + 1] = w
      return w
    end,
  },
  hid = { capslock = { toggle = function() toggles = toggles + 1 end } },
}

local failures, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %s, wanted %s, got %s", what, tostring(want), tostring(got)))
  end
end

-- Every case gets a fresh copy of the adapter, so nothing one case leaves behind reaches another.
local HYPER_POLICY = { ranked = true }
local WINDOW_POLICY = { drivenRepeat = true }
local function newLeader(policy, predicates, extra)
  local L = assert(loadfile(lib .. "leader.lua"))()
  local opts = { name = "x", policy = policy, predicates = predicates }
  for k, v in pairs(extra or {}) do opts[k] = v end
  return L.new(opts), L
end
local function newHyper(predicates) return (newLeader(HYPER_POLICY, predicates, { name = "hyper" })) end
local function newWindow(predicates) return (newLeader(WINDOW_POLICY, predicates, { name = "meta" })) end
local function isWindow(e) return e:policy().ranked ~= true end

local function listOf(engine, key)
  return engine._bindings[hs.keycodes.map[key]]
end

-- A handler that names itself, so what resolved can be compared by name. noop is whatever a leader
-- swallows with, found by asking for a handler that is not any of these.
local function handler(name) return function() return name end end
local function nameOf(fn) return fn and fn() or nil end

local live = {}
local predicates = {
  on = function() return true end,
  off = function() return false end,
  ctxA = function() return live.ctxA end,
  ctxB = function() return live.ctxB end,
}

-- A binding whose when is false. The window leader keeps the key and swallows it with a noop, so it
-- resolves to a function that does nothing, and since phase 3 Hyper does the same.
do
  local h = newHyper(predicates)
  h:bind("a", handler("gated"), nil, { when = "off" })
  local hf, hr = h:_resolve(listOf(h, "a"), {})
  eq(type(hf), "function", "FLIPPED hyper: a false when with nothing else is swallowed, it resolves to a function")
  eq(nameOf(hf), nil, "FLIPPED hyper: that function is the noop, it runs nothing")
  eq(hr, false, "FLIPPED hyper: the swallowing noop never repeats")

  local w = newWindow(predicates)
  w:bind("a", handler("gated"), nil, { when = "off" })
  local fn, repeats = w:_resolve(listOf(w, "a"), {})
  eq(type(fn), "function", "window: a false when on a catch all resolves to a function")
  eq(nameOf(fn), nil, "window: that function is the noop, it runs nothing")
  eq(repeats, false, "window: the swallowing noop never repeats")

  local wx = newWindow(predicates)
  wx:bind("a", handler("gated"), { "shift" }, { gate = "off" })
  wx:bind("a", handler("catch"))
  local fx = wx:_resolve(listOf(wx, "a"), { shift = true })
  eq(nameOf(fx), nil, "window: a false when on a matching exact binding is a noop, not a fall through to the catch all")

  local hx = newHyper(predicates)
  hx:bind("a", handler("gated"), { "shift" }, { gate = "off" })
  hx:bind("a", handler("catch"))
  eq(nameOf((hx:_resolve(listOf(hx, "a"), { shift = true }))), "catch",
    "hyper: a false when on a matching exact binding falls through to the catch all")

  -- The flip reaches only a key whose matching bindings are all gated. A gated exact binding on
  -- other modifiers is not a match, so with nothing else the key still resolves to nothing.
  local hm = newHyper(predicates)
  hm:bind("a", handler("gated"), { "shift" }, { when = "off" })
  eq(hm:_resolve(listOf(hm, "a"), {}), nil, "hyper: a gated binding on other modifiers leaves the key unbound")
end

-- Exact modifiers beat a catch all on both, and fn is ignored when comparing.
do
  for _, make in ipairs({ newHyper, newWindow }) do
    local e = make(predicates)
    local which = isWindow(e) and "window" or "hyper"
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
    local which = isWindow(e) and "window" or "hyper"
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

  -- A list key whose context is not live, on a key with no base binding, is gated off, so outside
  -- its list the key is swallowed rather than leaked, which is the flip seen from a list key.
  local k = newHyper(predicates)
  k:bind("c", handler("listOnly"), nil, { when = "ctxA", priority = 100 })
  live.ctxA = false
  eq(nameOf((k:_resolve(listOf(k, "c"), {}))), nil, "FLIPPED hyper: a list key outside its list is swallowed as a noop")
  eq(type((k:_resolve(listOf(k, "c"), {}))), "function", "FLIPPED hyper: and that noop is a bound handler")
  live.ctxA = true
  eq(nameOf((k:_resolve(listOf(k, "c"), {}))), "listOnly", "hyper: the list key runs while its list is live")

  -- A base binding dropped by the modal rule is outranked rather than gated, so while a list is
  -- open a key whose only binding is a base one still resolves to nothing and passes through.
  eq(h:_resolve(listOf(h, "b"), {}), nil, "hyper: a base key dropped by the modal rule still resolves to nothing")
  live.ctxA = false
end

-- An unknown predicate name is treated as active on both, and since phase 3 it warns once per name
-- on Hyper too, however many presses follow.
do
  local h = newHyper(predicates)
  h:bind("a", handler("typo"), nil, { when = "nope" })
  local before = #warnings
  eq(nameOf((h:_resolve(listOf(h, "a"), {}))), "typo", "hyper: an unknown predicate name passes")
  eq(nameOf((h:_resolve(listOf(h, "a"), {}))), "typo", "hyper: and passes again")
  eq(#warnings, before + 1, "FLIPPED hyper: and warns, once")

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
-- warning on both.
do
  for _, make in ipairs({ newHyper, newWindow }) do
    local e = make(predicates)
    local which = isWindow(e) and "window" or "hyper"
    local before = #warnings
    e:bind("nokey", handler("x"))
    eq(next(e._bindings), nil, which .. ": an unknown key is not stored")
    eq(#warnings, before + 1, which .. ": and is warned about")
  end
end

-- The binder, lib/binder.lua, handing keymap rows to these same leaders. A row lands on the leader
-- its name names, with its gate, priority and repeat in the options and nil modifiers for a catch
-- all, a row with no leader goes to the plain leader, and the leaders receive the rows in the order
-- of the list handed in, which is what decides a tie on one key.
do
  local binder = assert(loadfile(lib .. "binder.lua"))()
  local h, w = newHyper(predicates), newWindow(predicates)
  local plain = {}
  local plainLeader = { bind = function(_, key, fn, mods, opts)
    plain[#plain + 1] = { mods = mods, key = key, fn = fn, opts = opts }
  end }
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
  local problems = binder.bind(rows, { engines = { hyper = h, meta = w }, plain = plainLeader })

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
  eq(c and c[1].gate, "on", "binder: the gate travels in the options")
  eq(c and c[1].repeats, true, "binder: the repeat travels in the options")
  eq(nameOf((w:_resolve(c, {}))), "late", "binder: on the window leader the later catch all wins, so order is kept")
  eq(listOf(h, "c"), nil, "binder: a list's own key is left to the contexts")
  eq(#plain, 1, "binder: a row with no leader goes to the plain leader")
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
  -- The first flip as the binder's case sees it. The gated key used to resolve to nothing while
  -- false, and with passthrough on it leaked, and it is swallowed now.
  eq(nameOf((g:_resolve(listOf(g, "a"), {}))), nil, "FLIPPED binder: and is swallowed while false, running nothing")
  eq(type((g:_resolve(listOf(g, "a"), {}))), "function", "FLIPPED binder: as a bound noop rather than left unbound")

  -- A raise inside one engine costs that row and every other row still binds.
  local raising = { bind = function() error("boom") end }
  local h2 = newHyper(predicates)
  local raised = binder.bind({
    row({ leader = "broken", key = "a", run = handler("x") }),
    row({ leader = "hyper", key = "a", run = handler("kept") }),
  }, { engines = { broken = raising, hyper = h2 } })
  eq(#raised, 1, "binder: a raising engine is one problem")
  eq(listOf(h2, "a") and #listOf(h2, "a"), 1, "binder: and the next row still binds")

  -- A row whose descriptor waits for release carries that into the options.
  local seen = {}
  binder.bind({ row({ leader = "hyper", key = "a", run = handler("x"), afterRelease = true }) },
    { engines = { hyper = { bind = function(_, _, _, _, opts) seen[#seen + 1] = opts end } } })
  eq(seen[1] and seen[1].afterRelease, true, "binder: the release wait travels in the options")
end

--------------------------------------------------------------------------------
-- What the merge added
--------------------------------------------------------------------------------

-- The one rule over open lists, phase A of the list keys addendum. While a list is open a held
-- leader answers only its bindings for the open list and swallows every other key, whatever its
-- policy, and with no list open it is unchanged. It replaced quietOverLists and sealedOverLists.
-- A held leader is one whose trigger seals over lists, which the held trigger says, so these use a
-- trigger saying the same.
local SEALED = { sealsOverLists = true, bound = function() end, isActive = function() return false end,
  owns = function() return false end, start = function() return true end }
do
  for _, policy in ipairs({ HYPER_POLICY, WINDOW_POLICY }) do
    local open = false
    live.ctxA = false
    local e = newLeader(policy, predicates, { listOpen = function() return open end, trigger = SEALED })
    local which = policy.ranked and "hyper" or "window"
    e:bind("a", handler("global"))
    e:bind("c", handler("listKey"), nil, { when = "ctxA", priority = 100 })
    e:bind("c", handler("globalC"))
    local a, b, c = hs.keycodes.map.a, hs.keycodes.map.b, hs.keycodes.map.c
    eq(nameOf((e:_onKey(a, {}))), "global", which .. " over lists: with no list open a global key acts")
    eq(e:_onKey(b, {}), nil, which .. " over lists: with no list open an unbound key passes through")
    eq(nameOf((e:_onKey(c, {}))), "globalC", which .. " over lists: with no list open the global key on a list key's chord acts")
    open, live.ctxA = true, true
    eq(nameOf((e:_onKey(c, {}))), "listKey", which .. " over lists: a bound list key of the open list acts")
    local g = e:_onKey(a, {})
    eq(type(g), "function", which .. " over lists: a global key is swallowed")
    eq(nameOf(g), nil, which .. " over lists: and runs nothing")
    local u = e:_onKey(b, {})
    eq(type(u), "function", which .. " over lists: an unbound key is swallowed")
    eq(nameOf(u), nil, which .. " over lists: and runs nothing")
    live.ctxA = false
    local other = e:_onKey(c, {})
    eq(nameOf(other), nil, which .. " over lists: a list key of another list is swallowed, never the global key on its chord")
    open = false
  end

  -- A leader binding no list key is inert over a list, which is what META was through quietOverLists.
  local open = true
  local w = newLeader(WINDOW_POLICY, predicates, { listOpen = function() return open end, trigger = SEALED })
  w:bind("a", handler("move"))
  local q = w:_onKey(hs.keycodes.map.a, {})
  eq(type(q), "function", "over lists: a leader with no list key swallows its keys over a list")
  eq(nameOf(q), nil, "over lists: and runs none of them")

  -- List bindings on a leader that is not ranked still rank, so a closed list's gated binding bound
  -- first never swallows the open list's on the same key.
  local m = newLeader(WINDOW_POLICY, predicates, { name = "meta", listOpen = function() return open end, trigger = SEALED })
  m:bind("c", handler("listA"), nil, { when = "ctxA", priority = 100 })
  m:bind("c", handler("listB"), nil, { when = "ctxB", priority = 100 })
  live.ctxA, live.ctxB = false, true
  eq(nameOf((m:_onKey(hs.keycodes.map.c, {}))), "listB", "over lists: on meta the open list's key answers past a closed list's")
  live.ctxA, live.ctxB = false, false

  -- A leader on real modifiers is never sealed. The plain leader's combination and a named
  -- modifier leader's chord fire over an open list as they do anywhere, since the app beneath
  -- would otherwise lose a key the hotkey still takes, the fix round's first blocker.
  local modifier = assert(loadfile(lib .. "leader/triggers/modifier.lua"))()
  local plain = newLeader({}, predicates, { listOpen = function() return true end, trigger = modifier.new({ mods = {} }) })
  plain:bind("`", handler("summon"), { "alt" })
  eq(nameOf((plain:_onKey(hs.keycodes.map["`"], { alt = true }))), "summon",
    "over lists: the plain leader's combination fires over an open list")
  local nav = newLeader({}, predicates, { listOpen = function() return true end,
    trigger = modifier.new({ mods = { "shift", "ctrl" } }) })
  nav:bind("a", handler("navA"))
  eq(nameOf((nav:_onKey(hs.keycodes.map.a, {}))), "navA", "over lists: a named modifier leader's chord fires over an open list")
  local heldTrigger = assert(loadfile(lib .. "leader/triggers/held.lua"))().new({})
  eq(heldTrigger.sealsOverLists, true, "over lists: the held trigger is the one that seals")

  -- A modifier leader hosting a list key seals over an open list, the root saying so through the
  -- trigger once it knows which leaders host one. A key it resolves there that is no list key is the
  -- bound no op, and a leader hosting none still fires.
  local FOUR = { "shift", "ctrl", "alt", "cmd" }
  eq(modifier.new({ mods = FOUR }).sealsOverLists, false, "sealing: a modifier trigger says nothing by default")
  local listUp = true
  local sealing = newLeader({ ranked = true }, predicates, { name = "hyper", listOpen = function() return listUp end,
    trigger = modifier.new({ mods = FOUR, sealsOverLists = true }) })
  sealing:bind("a", handler("toggle"))
  sealing:bind("b", handler("listB"), nil, { when = "ctxA", priority = 100 })
  live.ctxA = true
  local sealedKey = sealing:_onKey(hs.keycodes.map.a, {})
  eq(type(sealedKey), "function", "sealing: a modifier leader hosting a list key resolves a global key over a list")
  eq(nameOf(sealedKey), nil, "sealing: to the bound no op")
  eq(nameOf((sealing:_onKey(hs.keycodes.map.b, {}))), "listB", "sealing: and its list key still acts")
  local unbound = sealing:_onKey(hs.keycodes.map.c, {})
  eq(type(unbound), "function", "sealing: even a key nothing binds is the no op over a list")
  live.ctxA = false
  local open = true
  local firing = newLeader({ ranked = true }, predicates, { name = "hyper", listOpen = function() return open end,
    trigger = modifier.new({ mods = FOUR, sealsOverLists = false }) })
  firing:bind("a", handler("toggle"))
  eq(nameOf((firing:_onKey(hs.keycodes.map.a, {}))), "toggle", "sealing: a modifier leader hosting no list key still fires over a list")
  listUp = false
  eq(nameOf((sealing:_onKey(hs.keycodes.map.a, {}))), "toggle", "sealing: with no list open the sealing leader fires as ever")

  -- The default chooser's field tap sees a chord before the hotkey, so the root asks the leader whether
  -- an event is its own, by the flags the event carries rather than the live keyboard.
  local function event(flags) return { getFlags = function() return flags end } end
  local owner = newLeader({}, predicates, { name = "hyper", trigger = modifier.new({ mods = FOUR, sealsOverLists = true }) })
  heldMods = {}
  eq(owner:owns(event({ shift = true, ctrl = true, alt = true, cmd = true })), true,
    "owns: an event holding the whole set is the leader's, whatever the keyboard says")
  eq(owner:owns(event({ shift = true, ctrl = true, alt = true, cmd = true, fn = true })), true,
    "owns: and fn beside it changes nothing")
  eq(owner:owns(event({ shift = true, ctrl = true, alt = true })), false, "owns: part of the set is not")
  eq(owner:owns(event({})), false, "owns: no modifiers is not")
  heldMods = { shift = true, ctrl = true, alt = true, cmd = true }
  eq(owner:owns(event({ cmd = true })), false, "owns: the event's own flags decide, not the live keyboard")
  eq(owner:owns(), true, "owns: handed no event it reads the live keyboard as isActive does")
  heldMods = {}
  local plainOwner = newLeader({}, predicates, { trigger = modifier.new({ mods = {} }) })
  eq(plainOwner:owns(event({ cmd = true })), false, "owns: the plain leader owns no event")

  -- A leader driving its repeats hands a repeating handler how deep into the hold it is, 0 on the
  -- press and one more per OS autorepeat of the hotkey, reset on each press.
  hotkeysBound = {}
  local depths = {}
  local driven = newLeader({ drivenRepeat = true }, predicates, { name = "hyper",
    trigger = modifier.new({ mods = FOUR }) })
  driven:bind("a", function(...) depths[#depths + 1] = select("#", ...) == 0 and "none" or select(1, ...) end,
    nil, { repeats = true })
  driven:start()
  local hk = hotkeysBound[1]
  hk.press()
  hk.rep()
  hk.rep()
  hk.press()
  hk.rep()
  eq(table.concat(depths, ","), "0,1,2,0,1", "driven repeat: the depth is 0 on a press, counts each repeat and resets on a press")
  hotkeysBound = {}
  depths = {}
  local system = newLeader({}, predicates, { name = "hyper", trigger = modifier.new({ mods = FOUR }) })
  system:bind("a", function(...) depths[#depths + 1] = select("#", ...) == 0 and "none" or select(1, ...) end,
    nil, { repeats = true })
  system:start()
  hotkeysBound[1].press()
  hotkeysBound[1].rep()
  eq(table.concat(depths, ","), "none,none", "driven repeat: a leader not stating it calls its handler as before")

  -- The retired fields are refused by name, each saying what replaced it.
  local L = assert(loadfile(lib .. "leader.lua"))()
  for _, field in ipairs({ "contexts", "quietOverLists", "sealedOverLists", "tapTogglesCapsLock" }) do
    local clean, problems = L.checkPolicy("HYPER", { [field] = true })
    eq(clean[field], nil, "retired: " .. field .. " is not kept")
    eq(#problems, 1, "retired: " .. field .. " is one problem")
    eq(problems[1] and problems[1].why:find("is retired", 1, true) ~= nil, true, "retired: " .. field .. " is named as retired")
  end
  local _, typed = L.checkPolicy("HYPER", { ranked = "yes" })
  eq(#typed, 1, "ranked: a non boolean is refused")
end

-- The held trigger registers the key with what the policy decided.
do
  local held = assert(loadfile(lib .. "leader/triggers/held.lua"))()
  local registered = {}
  local engine = { addKey = function(_, code, opts) registered[code] = opts end,
    isActive = function() return false end }
  local sheet = { show = function() end, hide = function() end }
  local h = newLeader(HYPER_POLICY, predicates, { trigger = held.new({ chord = engine, keyCode = 79, key = "capsLock" }),
    sheet = sheet, keyCode = 79, holdDelay = 0.6, tapThreshold = 0.2 })
  h:start()
  local o = registered[79]
  eq(o ~= nil, true, "held: the key is registered into the engine")
  eq(type(o and o.onTap), "function", "held: a Caps Lock leader gives the key a tap")
  toggles = 0
  o.onTap()
  eq(toggles, 1, "held: and the tap toggles Caps Lock")
  eq(o and o.repeatMode, nil, "held: a leader that does not drive its repeats leaves the engine's own mode")
  eq(type(o and o.onHold), "function", "held: a leader with a sheet arms a hold")
  eq(o and o.holdDelay, 0.6, "held: with the engine's hold delay")

  -- The tap follows the key and nothing else, so no other key on the allow list has one, whatever
  -- the policy says.
  for _, key in ipairs({ "rightControl", "rightOption", "rightCommand", "f13", "f20" }) do
    registered = {}
    local other = newLeader(HYPER_POLICY, predicates, { trigger = held.new({ chord = engine, keyCode = 80, key = key }),
      keyCode = 80 })
    other:start()
    eq(registered[80] and registered[80].onTap, nil, "held: a leader on " .. key .. " has no tap")
  end
  registered = {}
  local noKey = newLeader(HYPER_POLICY, predicates, { trigger = held.new({ chord = engine, keyCode = 80 }), keyCode = 80 })
  noKey:start()
  eq(registered[80] and registered[80].onTap, nil, "held: a trigger told no key has no tap")

  local w = newLeader(WINDOW_POLICY, predicates, { trigger = held.new({ chord = engine, keyCode = 106 }), keyCode = 106 })
  registered = {}
  w:bind("a", handler("step"), nil, { repeats = true })
  w:start()
  local wo = registered[106]
  eq(wo and wo.repeatMode, "driven", "held: a leader that drives its repeats registers as driven")
  eq(wo and wo.onTap, nil, "held: with no tap")
  eq(wo and wo.onHold, nil, "held: and no hold when it reveals no sheet")
  local fn, rep = wo.onKey(hs.keycodes.map.a, {})
  eq(nameOf(fn), "step", "held: its onKey answers the handler")
  eq(rep, true, "held: and the repeat flag together")
end

-- The hold reveal never draws over an open list, and conceal takes down only what this leader put up.
do
  local shown, hidden, open = 0, 0, false
  local sheet = { show = function() shown = shown + 1 end, hide = function() hidden = hidden + 1 end }
  local h = newLeader(HYPER_POLICY, predicates, { sheet = sheet, keyCode = 79, listOpen = function() return open end })
  h:conceal()
  eq(hidden, 0, "reveal: concealing what was never shown hides nothing")
  h:_reveal(79)
  eq(shown, 1, "reveal: a hold with no list open shows the sheet")
  h:conceal()
  eq(hidden, 1, "reveal: and its release hides it")
  open = true
  h:_reveal(79)
  eq(shown, 1, "reveal: a hold over an open list shows nothing")
  h:conceal()
  eq(hidden, 1, "reveal: and hides nothing")
end

-- A binding that waits for release runs at once when the leader is up and waits while it is down.
do
  local down = false
  local trigger = { isActive = function() return down end, owns = function() return down end,
    bound = function() end, start = function() return true end }
  local h = newLeader(HYPER_POLICY, predicates, { trigger = trigger })
  local ran = 0
  h:bind("a", function() ran = ran + 1 end, nil, { afterRelease = true })
  local fn = h:_resolve(listOf(h, "a"), {})
  fn(0)
  eq(ran, 1, "release: with the leader up the action runs at once")
  down = true
  waits = {}
  fn(0)
  eq(ran, 1, "release: with the leader down it waits")
  eq(#waits, 1, "release: on one waiter")
  down = false
  waits[1].fn()
  eq(ran, 2, "release: and runs once the leader is up")
end

-- The modifier trigger with an empty base set, which is how a plain combo binds now. Each combo is
-- claimed at start on exactly its own modifiers, a press resolves against the modifiers it was
-- claimed on, and an empty base set is never held.
do
  local modifier = assert(loadfile(lib .. "leader/triggers/modifier.lua"))()
  hotkeysBound = {}
  local p = newLeader({}, predicates, { trigger = modifier.new({ mods = {} }) })
  local ran = 0
  p:bind("`", function() ran = ran + 1 end, { "alt" })
  eq(#hotkeysBound, 0, "modifier: nothing is claimed before start")
  p:start()
  eq(#hotkeysBound, 1, "modifier: start claims the combo")
  eq(hotkeysBound[1] and hotkeysBound[1].key, "`", "modifier: on the key as the binding spelled it")
  eq(hotkeysBound[1] and table.concat(hotkeysBound[1].mods, "+"), "alt", "modifier: and on its own modifiers alone")
  eq(hotkeysBound[1] and hotkeysBound[1].rep, nil, "modifier: a combo that does not repeat asks for no repeat callback")
  heldMods = {}
  hotkeysBound[1].press()
  eq(ran, 1, "modifier: a press runs the binding whatever the hardware reports by then")
  eq(p:isActive(), false, "modifier: an empty base set is never held")
  p:bind("c", function() end, { "alt", "ctrl" })
  eq(#hotkeysBound, 2, "modifier: a binding after start is claimed at once")
  eq(table.concat(hotkeysBound[2].mods, "+"), "ctrl+alt", "modifier: in the one order a combination is spelled in")

  hotkeysBound = {}
  local named = newLeader({}, predicates, { trigger = modifier.new({ mods = { "shift", "ctrl" } }) })
  named:bind("a", function() end)
  named:start()
  eq(hotkeysBound[1] and table.concat(hotkeysBound[1].mods, "+"), "shift+ctrl", "modifier: a named base set is claimed with the binding")
  heldMods = { shift = true }
  eq(named:isActive(), false, "modifier: part of the base set is not the leader held")
  heldMods = { shift = true, ctrl = true }
  eq(named:isActive(), true, "modifier: the whole base set is")
  heldMods = {}
end

-- Review fixes to the modifier trigger. A claim that raises costs only its own combo, a combo
-- whose later binding repeats still gets the repeat callback, and a declared fn is passed through.
do
  local modifier = assert(loadfile(lib .. "leader/triggers/modifier.lua"))()
  local realBind = hs.hotkey.bind
  hotkeysBound = {}
  hs.hotkey.bind = function(mods, key, ...)
    if key == "b" then error("refused") end
    return realBind(mods, key, ...)
  end
  local p = newLeader({}, predicates, { trigger = modifier.new({ mods = {} }) })
  p:bind("a", function() end, { "alt" })
  p:bind("b", function() end, { "alt" })
  p:bind("c", function() end, { "alt" })
  local before = #warnings
  p:start()
  hs.hotkey.bind = realBind
  eq(#hotkeysBound, 2, "isolation: a combo whose claim raises costs only that combo")
  eq(hotkeysBound[2] and hotkeysBound[2].key, "c", "isolation: and the next combo still claims")
  eq(#warnings, before + 1, "isolation: the raise is said once")
  eq(warnings[#warnings] and warnings[#warnings]:find("b on alt", 1, true) ~= nil, true,
    "isolation: naming its key and modifiers")

  hotkeysBound = {}
  -- Ranked, so the gated first binding drops out of its tier and the second answers.
  local r = newLeader({ ranked = true }, predicates, { trigger = modifier.new({ mods = {} }) })
  local steps = 0
  r:bind("a", function() end, { "alt" }, { gate = "off" })
  r:bind("a", function() steps = steps + 1 end, { "alt" }, { repeats = true })
  r:start()
  eq(#hotkeysBound, 1, "repeat: two bindings on one combo claim it once")
  eq(type(hotkeysBound[1] and hotkeysBound[1].rep), "function",
    "repeat: the callback is there when a later binding on the combo repeats")
  hotkeysBound[1].rep()
  eq(steps, 1, "repeat: and resolves at fire time to the binding that repeats")

  hotkeysBound = {}
  local late = newLeader({}, predicates, { trigger = modifier.new({ mods = {} }) })
  late:bind("c", function() end, { "ctrl" })
  late:start()
  late:bind("c", function() end, { "ctrl" }, { repeats = true })
  eq(#hotkeysBound, 2, "repeat: a repeating binding after start reclaims its combo")
  eq(type(hotkeysBound[2] and hotkeysBound[2].rep), "function", "repeat: with the callback")

  hotkeysBound = {}
  local f = newLeader({}, predicates, { trigger = modifier.new({ mods = {} }) })
  f:bind("left", function() end, { "alt", "fn" })
  f:start()
  eq(hotkeysBound[1] and table.concat(hotkeysBound[1].mods, "+"), "alt+fn", "fn: a declared fn is claimed with the combo")
end

-- A launcher row that waits for release waits until no held leader is down, not only the first.
do
  local L = assert(loadfile(lib .. "leader.lua"))()
  local down = { a = true, b = true }
  local function fake(name)
    return { isActive = function() return down[name] end }
  end
  local ran = 0
  waits = {}
  L.afterAllReleased({ fake("a"), fake("b") }, function() ran = ran + 1 end)
  eq(ran, 0, "release all: with leaders held it waits")
  down.a = false
  eq(waits[1] and waits[1].pred(), false, "release all: one leader still down keeps it waiting")
  down.b = false
  eq(waits[1] and waits[1].pred(), true, "release all: and it runs only once every one is up")
  L.afterAllReleased({ fake("a") }, function() ran = ran + 1 end)
  eq(ran, 1, "release all: with none held it runs at once")
end

-- The policy is checked once and a typo is a problem line rather than read as absent.
do
  local L = assert(loadfile(lib .. "leader.lua"))()
  local clean, problems = L.checkPolicy("HYPER", { ranked = true, drivenRepeat = "yes", typo = true, sheet = false })
  eq(clean.ranked, true, "policy: a well typed field is kept")
  eq(clean.drivenRepeat, nil, "policy: a field of the wrong type is left at its default")
  eq(clean.sheet, nil, "policy: false is the same as absent")
  eq(#problems, 2, "policy: the wrong type and the unknown field are each one problem")
end

-- The reveal on the modifier trigger. A leader of modifiers that states a sheet runs one tap that
-- only observes. The sheet shows once exactly the base set has been held for the hold delay, and
-- any key or change of the set takes it down, with a poll of the live modifiers as the backstop.
do
  local modifier = assert(loadfile(lib .. "leader/triggers/modifier.lua"))()
  local HYPER = { "shift", "ctrl", "alt", "cmd" }
  local function allOf(list)
    local out = {}
    for _, m in ipairs(list) do out[m] = true end
    return out
  end
  local function setup(mods, withSheet, extra)
    taps, timers = {}, {}
    local sheet = { shown = {}, hid = 0 }
    function sheet:show(code) self.shown[#self.shown + 1] = code end
    function sheet:hide() self.hid = self.hid + 1 end
    local opts = { trigger = modifier.new({ mods = mods }), name = "hyper", holdDelay = 0.4 }
    if withSheet then opts.sheet = sheet end
    for k, v in pairs(extra or {}) do opts[k] = v end
    local l = newLeader({}, predicates, opts)
    l:start()
    return l, sheet
  end
  local types = hs.eventtap.event.types
  local function flags(tap, set)
    local ev = { getType = function() return types.flagsChanged end, getFlags = function() return set end }
    return tap.fn(ev)
  end
  local function key(tap)
    return tap.fn({ getType = function() return types.keyDown end })
  end
  local function live() local n = 0 for _, t in ipairs(timers) do if not t.stopped then n = n + 1 end end return n end

  local l, sheet = setup(HYPER, true)
  local tap = taps[1]
  eq(#taps, 1, "reveal: a leader of modifiers with a sheet runs one tap")
  eq(tap.running, true, "reveal: and starts it")
  eq(tap.types[1] == types.flagsChanged and tap.types[2] == types.keyDown, true, "reveal: over flags changes and key downs")
  heldMods = allOf(HYPER)
  eq(flags(tap, allOf(HYPER)), false, "reveal: the tap answers false on a flags change")
  eq(#timers, 1, "reveal: exactly the base set arms a timer")
  eq(timers[1].delay, 0.4, "reveal: for the leader's hold delay")
  eq(#sheet.shown, 0, "reveal: and nothing shows before it passes")
  timers[1].fn()
  eq(#sheet.shown, 1, "reveal: the sheet shows when the delay passes with the set held")
  eq(sheet.shown[1], "hyper", "reveal: found by the leader's name, since it has no keycode")
  eq(timers[2] and timers[2].every, true, "reveal: a poll runs while the sheet is up")
  eq(timers[2] and timers[2].delay, 0.25, "reveal: a quarter second apart")
  -- A flags change after the reveal takes it down and stops the poll.
  flags(tap, { shift = true, ctrl = true, alt = true })
  eq(sheet.hid, 1, "reveal: a change of the set conceals")
  eq(timers[2].stopped, true, "reveal: and stops the poll")
  eq(live(), 0, "reveal: leaving the set holds no timer")
  -- A key after the reveal.
  flags(tap, allOf(HYPER))
  timers[#timers].fn()
  eq(#sheet.shown, 2, "reveal: held again, it shows again")
  eq(key(tap), false, "reveal: the tap answers false on a key down")
  eq(sheet.hid, 2, "reveal: a key down conceals")
  eq(live(), 0, "reveal: and leaves no timer running")
  -- A key before the delay.
  flags(tap, { shift = true, ctrl = true, alt = true, cmd = true, fn = true })
  eq(#sheet.shown, 2, "reveal: fn alone is no change and shows nothing early")
  key(tap)
  eq(live(), 0, "reveal: a key down before the delay disarms the timer")
  -- A superset, a subset and fn or caps lock.
  local before = #sheet.shown
  flags(tap, { shift = true, ctrl = true })
  flags(tap, { shift = true, ctrl = true, alt = true, cmd = true, fn = true, capsLock = true })
  eq(live(), 1, "reveal: fn and caps lock are not counted against the set")
  flags(tap, { shift = true, ctrl = true, alt = true, cmd = true, alt2 = true })
  flags(tap, {})
  eq(live(), 0, "reveal: releasing everything disarms")
  eq(#sheet.shown, before, "reveal: a subset never reveals")
  local l2, sheet2 = setup({ "shift", "ctrl" }, true)
  flags(taps[1], { shift = true, ctrl = true, cmd = true })
  eq(live(), 0, "reveal: a superset arms nothing")
  flags(taps[1], { shift = true })
  eq(live(), 0, "reveal: a subset arms nothing")
  -- The poll conceals once the live modifiers no longer match, with the tap blind.
  local l3, sheet3 = setup(HYPER, true)
  heldMods = allOf(HYPER)
  flags(taps[1], allOf(HYPER))
  timers[1].fn()
  eq(#sheet3.shown, 1, "poll: the sheet is up")
  heldMods = { shift = true }
  timers[2].fn()
  eq(sheet3.hid, 1, "poll: it conceals when the live set no longer matches")
  eq(timers[2].stopped, true, "poll: and stops")
  -- The tap never saw the release, so the next press may arrive as one event naming the same set.
  heldMods = allOf(HYPER)
  local armed = #timers
  flags(taps[1], allOf(HYPER))
  eq(#timers, armed + 1, "poll: after it conceals, the same set in one event arms again")
  timers[#timers].fn()
  eq(#sheet3.shown, 2, "poll: and the sheet shows again")
  -- The timer firing with the live set already gone shows nothing.
  local l4, sheet4 = setup(HYPER, true)
  flags(taps[1], allOf(HYPER))
  heldMods = {}
  timers[1].fn()
  eq(#sheet4.shown, 0, "reveal: a timer firing after the set was lost shows nothing")
  -- Over an open list the adapter refuses and no poll starts.
  local l5, sheet5 = setup(HYPER, true, { listOpen = function() return true end })
  heldMods = allOf(HYPER)
  flags(taps[1], allOf(HYPER))
  timers[1].fn()
  eq(#sheet5.shown, 0, "reveal: nothing shows over an open list")
  eq(#timers, 1, "reveal: and no poll runs for a sheet that is not up")
  -- No tap without a sheet, or without a base set.
  setup(HYPER, false)
  eq(#taps, 0, "reveal: a leader with no sheet runs no tap")
  setup({}, true)
  eq(#taps, 0, "reveal: a plain leader never runs one")
  heldMods = {}
end

-- The composite trigger, phase 1 of docs/PLAN-MACHINES.md. Hyper ships on Caps Lock and on the four
-- modifiers at once, so these drive the real held and modifier triggers inside one composite, the
-- way the root builds it, and pin each method of the contract per half.
do
  local held = assert(loadfile(lib .. "leader/triggers/held.lua"))()
  local modifier = assert(loadfile(lib .. "leader/triggers/modifier.lua"))()
  local composite = assert(loadfile(lib .. "leader/triggers/composite.lua"))()
  local FOUR = { "shift", "ctrl", "alt", "cmd" }
  local function allOf(list)
    local out = {}
    for _, m in ipairs(list) do out[m] = true end
    return out
  end
  local F18 = 79
  local registered, engineDown = {}, false
  local engine = { addKey = function(_, code, opts) registered[code] = opts end,
    isActive = function() return engineDown end }
  -- A leader the way the root builds HYPER, the held half first and the modifier half beside it.
  local function build(opts)
    opts = opts or {}
    registered, engineDown, hotkeysBound, taps, timers, heldMods = {}, false, {}, {}, {}, {}
    local halves = {
      held.new({ chord = (not opts.noEngine) and engine or nil, keyCode = F18, key = "capsLock" }),
      modifier.new({ mods = opts.mods or FOUR, sealsOverLists = opts.hostsListKey == true, skipOverlap = true }),
    }
    local leaderOpts = { name = "hyper", trigger = composite.new({ triggers = halves }), keyCode = F18,
      listOpen = opts.listOpen, sheet = opts.sheet, holdDelay = 0.4 }
    return (newLeader(HYPER_POLICY, predicates, leaderOpts)), halves
  end
  local function event(code, flags)
    return { getKeyCode = function() return code end, getFlags = function() return flags or {} end }
  end

  -- start starts both halves.
  local h = build()
  h:bind("a", handler("toggle"))
  h:start()
  eq(registered[F18] ~= nil, true, "composite: start registers the held key into the engine")
  eq(#hotkeysBound, 1, "composite: and claims the binding on the modifiers")
  eq(hotkeysBound[1] and table.concat(hotkeysBound[1].mods, "+"), "shift+ctrl+alt+cmd", "composite: on the whole set")

  -- One half failing leaves the other, and only both failing fails the leader.
  local before = #warnings
  local lone = build({ noEngine = true })
  lone:bind("a", handler("toggle"))
  lone:start()
  eq(#hotkeysBound, 1, "composite: a held half that cannot start leaves the modifiers claimed")
  eq(#warnings, before + 1, "composite: and says so once")
  eq(warnings[#warnings] and warnings[#warnings]:find("first trigger did not start", 1, true) ~= nil, true,
    "composite: naming the trigger that failed")
  before = #warnings
  local broken = { start = function() error("refused") end, bound = function() end,
    isActive = function() return false end, owns = function() return false end }
  local dead = newLeader(HYPER_POLICY, predicates, { name = "hyper", trigger = composite.new({ triggers = {
    held.new({ keyCode = F18 }), broken } }) })
  dead:start()
  eq(#warnings, before + 3, "composite: both halves failing is a line for each and one for the leader")
  eq(warnings[#warnings] and warnings[#warnings]:find("the hyper leader did not start, none of its triggers started", 1, true) ~= nil,
    true, "composite: and the leader says none of its triggers started")

  -- isActive is either half.
  h = build()
  h:start()
  eq(h:isActive(), false, "composite: with neither half held it is not active")
  engineDown = true
  eq(h:isActive(), true, "composite: F18 held is active")
  engineDown, heldMods = false, allOf(FOUR)
  eq(h:isActive(), true, "composite: the four modifiers held are active")
  heldMods = {}

  -- owns follows the half that is pressed.
  eq(h:owns(event(F18)), true, "owns: the F18 press itself is the leader's")
  eq(h:owns(event(hs.keycodes.map.a)), false, "owns: a plain key with nothing held is not")
  engineDown = true
  eq(h:owns(event(hs.keycodes.map.a)), true, "owns: under a held F18 every key is the leader's")
  engineDown = false
  eq(h:owns(event(hs.keycodes.map.a, allOf(FOUR))), true, "owns: a key carrying the four modifiers is the leader's")
  eq(h:owns(event(hs.keycodes.map.a, { shift = true, ctrl = true, alt = true })), false,
    "owns: a key carrying part of the set is not")

  -- Sealing follows the half that fired. Over an open list an F18 press seals as a held leader does,
  -- and a press of the modifiers seals only when the leader hosts a list key.
  for _, hosts in ipairs({ false, true }) do
    local ran = 0
    local s = build({ hostsListKey = hosts, listOpen = function() return true end })
    s:bind("a", function() ran = ran + 1 end)
    s:start()
    local viaHeld = registered[F18].onKey(hs.keycodes.map.a, {})
    eq(type(viaHeld), "function", "sealing: an F18 press over a list resolves to a function, hosting " .. tostring(hosts))
    viaHeld()
    eq(ran, 0, "sealing: and it is the no op, a held leader sealed, hosting " .. tostring(hosts))
    hotkeysBound[1].press()
    eq(ran, hosts and 0 or 1, "sealing: a press of the modifiers seals only when the leader hosts a list key, hosting "
      .. tostring(hosts))
  end

  -- A binding asking for a modifier the set already holds is left to the held half, unclaimed and
  -- unwarned, and one note counts them.
  before = #warnings
  local noteCount = #notes
  local skip = build()
  skip:bind("c", handler("shot"), { "shift" })
  skip:bind("left", handler("preview"), { "cmd" })
  skip:bind("b", handler("toggle"))
  skip:start()
  eq(#hotkeysBound, 1, "skip: only the binding with no overlap is claimed on the modifiers")
  eq(hotkeysBound[1] and hotkeysBound[1].key, "b", "skip: the plain one")
  eq(#warnings, before, "skip: the overlapping ones are not warned about")
  eq(#notes, noteCount + 1, "skip: one note counts them")
  eq(notes[#notes] and notes[#notes]:find("hyper leader leaves 2 chord", 1, true) ~= nil, true, "skip: with the count")
  eq(nameOf((registered[F18].onKey(hs.keycodes.map.left, { cmd = true }))), "preview",
    "skip: and the held half still reaches a skipped binding")
  noteCount = #notes
  local three = build({ mods = { "shift", "ctrl", "alt" } })
  three:bind("c", handler("step"), { "cmd" })
  three:start()
  eq(hotkeysBound[1] and table.concat(hotkeysBound[1].mods, "+"), "shift+ctrl+alt+cmd",
    "skip: on three modifiers a binding adding cmd has no overlap and is claimed")
  eq(#notes, noteCount, "skip: and with nothing skipped no note is said")
  -- A leader of modifiers alone still warns, the skip is the composite's alone.
  before = #warnings
  local plainFour = newLeader(HYPER_POLICY, predicates, { name = "hyper", trigger = modifier.new({ mods = FOUR }) })
  plainFour:bind("c", handler("shot"), { "shift" })
  plainFour:start()
  eq(#warnings, before + 1, "skip: a modifier leader on its own still warns about the overlap")

  -- The sheet. A held hold reveals by keycode and a modifier hold too, since the leader has one, and
  -- one press never draws the sheet twice or has the other half take it down.
  local sheet = { shown = {}, hid = 0 }
  function sheet:show(code) self.shown[#self.shown + 1] = code end
  function sheet:hide() self.hid = self.hid + 1 end
  local sh = build({ sheet = sheet })
  sh:start()
  local tap = taps[1]
  local types = hs.eventtap.event.types
  local function flags(set)
    return tap.fn({ getType = function() return types.flagsChanged end, getFlags = function() return set end })
  end
  local function keyDown()
    return tap.fn({ getType = function() return types.keyDown end })
  end
  eq(type(registered[F18].onHold), "function", "sheet: the held half arms a hold")
  eq(tap ~= nil, true, "sheet: and the modifier half watches the modifiers")
  registered[F18].onHold(F18)
  eq(#sheet.shown, 1, "sheet: an F18 hold shows the sheet")
  eq(sheet.shown[1], F18, "sheet: by its keycode")
  keyDown()
  flags({ shift = true })
  eq(sheet.hid, 0, "sheet: a key or modifier under F18 is not the modifier half's to take down")
  heldMods = allOf(FOUR)
  flags(allOf(FOUR))
  timers[#timers].fn()
  eq(#sheet.shown, 1, "sheet: the modifier half asking while it is up draws nothing twice")
  registered[F18].onHoldEnd()
  eq(sheet.hid, 1, "sheet: and releasing F18 takes it down once")
  flags({})
  flags(allOf(FOUR))
  timers[#timers].fn()
  eq(#sheet.shown, 2, "sheet: a hold of the modifiers alone shows it")
  eq(sheet.shown[2], F18, "sheet: found by the leader's keycode, which the sheet host files it under")
  flags({ shift = true })
  eq(sheet.hid, 2, "sheet: and a change of the set takes it down")
  heldMods = {}
end

print(string.format("leaders: %d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
