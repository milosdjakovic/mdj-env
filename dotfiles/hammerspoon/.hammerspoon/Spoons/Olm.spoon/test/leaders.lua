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
-- quiet rule, the reveal and the release wait.
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
local hotkeysBound = {}
local heldMods = {}
local waits = {}
hs = {
  keycodes = { map = { a = 0, b = 11, c = 8, left = 123, ["`"] = 50 } },
  logger = {
    new = function()
      return setmetatable({
        w = function(message) warnings[#warnings + 1] = message end,
      }, { __index = function() return function() end end })
    end,
  },
  hotkey = {
    bind = function(mods, key, press, release, rep)
      hotkeysBound[#hotkeysBound + 1] = { mods = mods, key = key, press = press, release = release, rep = rep }
      return {}
    end,
  },
  eventtap = { checkKeyboardModifiers = function() return heldMods end },
  timer = {
    waitUntil = function(pred, fn)
      local w = { pred = pred, fn = fn, stopped = false }
      function w:stop() self.stopped = true end
      waits[#waits + 1] = w
      return w
    end,
  },
  hid = { capslock = { toggle = function() end } },
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
local HYPER_POLICY = { ranked = true, tapTogglesCapsLock = true }
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

  -- The retired fields are refused by name, each saying what replaced it.
  local L = assert(loadfile(lib .. "leader.lua"))()
  for _, field in ipairs({ "contexts", "quietOverLists", "sealedOverLists" }) do
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
  local h = newLeader(HYPER_POLICY, predicates, { trigger = held.new({ chord = engine, keyCode = 79 }),
    sheet = sheet, keyCode = 79, holdDelay = 0.6, tapThreshold = 0.2 })
  h:start()
  local o = registered[79]
  eq(o ~= nil, true, "held: the key is registered into the engine")
  eq(type(o and o.onTap), "function", "held: a policy that toggles Caps Lock gives the key a tap")
  eq(o and o.repeatMode, nil, "held: a leader that does not drive its repeats leaves the engine's own mode")
  eq(type(o and o.onHold), "function", "held: a leader with a sheet arms a hold")
  eq(o and o.holdDelay, 0.6, "held: with the engine's hold delay")

  local w = newLeader(WINDOW_POLICY, predicates, { trigger = held.new({ chord = engine, keyCode = 106 }), keyCode = 106 })
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

print(string.format("leaders: %d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
