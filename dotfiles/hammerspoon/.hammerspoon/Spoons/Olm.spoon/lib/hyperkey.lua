--- === HyperKey ===
---
--- Domain adapter: turn a single physical key into a "Hyper" trigger with a tap
--- fallback, for app-toggle style bindings (a key -> function map).
---
--- A binding may require exact sub-modifiers (e.g. Shift), so one key can host
--- two tiers: Hyper+4 fires one action while Hyper+Shift+4 fires another.
--- Bindings with no `mods` are catch-alls, they fire whenever no exact-mods
--- binding matches the modifiers held. This is the same mods aware resolver the
--- leaders use, so both adapters share one policy, and most Hyper bindings pass no
--- mods and stay a plain key lookup.
---
--- The hold / tap / chord MECHANICS -- swallowing keys while held, hold-to-reveal
--- timing, why the key must emit clean key-down/up -- live in ChordKey.spoon.
--- This spoon owns only the binding table and the tap policy, and registers its
--- key into the shared ChordKey engine (passed as opts.chord). Keeping it a thin
--- adapter preserves the :bind and :isActive contract its consumers depend on,
--- while the underlying engine stays the shared one.
---
--- This is the olm side copy of HyperKey, moved into the core as lib/hyperkey.lua in phase
--- five of the build plan. The colon methods are unchanged, so assigning it to the HyperKey
--- spoon global is a drop in. The original this was copied from still lives at
--- Spoons/HyperKey.spoon and knows nothing of what follows.
---
--- WHAT IS NEW HERE is that the trigger is no longer a constant. What physically means Hyper
--- is configuration now, a descriptor the composition root hands to configure, and this file
--- holds one strategy per shape behind the one contract the rest of the config already
--- consumes, bind, isActive, and start. The single key shape is this spoon's original path,
--- untouched. The modifier chord shape is new. See TRIGGERS below, which is the seam, for
--- why the two cannot share a mechanism and what each of them owes the other.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "HyperKey"
obj.version = "4.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("HyperKey", "info")

obj._chord = nil        -- shared ChordKey engine
obj._bindings = nil     -- keycode -> { { mods, fn, when, priority }, ... }
obj._predicates = nil   -- name -> function() -> bool, injected; gates `when` bindings
obj._contextWhens = nil -- set of `when` names seen on bindings; drives modal mode
obj._triggerSpec = nil  -- the descriptor configure was handed, { kind = ... }, see TRIGGERS
obj._trigger = nil      -- the live strategy built from it, built once and cached

-- F18 keycode (Caps Lock is remapped to F18 at the HID level)
obj._keyCode = 79
-- Max hold duration (seconds) that still counts as a tap
obj._tapThreshold = 0.2
-- Optional callbacks (see configure)
obj._onTap = nil
obj._holdDelay = nil
obj._onHold = nil
obj._onHoldEnd = nil

--- HyperKey:init()
--- Method
--- Initialize the spoon
function obj:init()
  self._bindings = {}
  self._contextWhens = {}
  self._trigger = nil
  return self
end

--- HyperKey:configure(opts)
--- Method
--- opts.chord        - the shared ChordKey engine to register into (required)
--- opts.keyCode      - keycode of the Hyper key (default 79, F18)
--- opts.tapThreshold - seconds below which a hold counts as a tap (default 0.2)
--- opts.onTap        - function to run on a quick tap with no other key
--- opts.holdDelay    - seconds to hold (no other key) before onHold fires
--- opts.onHold       - function to run once the hold passes holdDelay
--- opts.onHoldEnd    - function to run when a shown hold ends
--- opts.predicates   - name -> function() -> bool registry, injected so a binding
---                     may carry a `when` gate resolved by name (see bind)
--- opts.trigger      - what physically means Hyper, a descriptor the composition root
---                     builds from configuration. { kind = "leader", keyCode = <code> }
---                     is a single key through the shared engine, and its keyCode falls
---                     back to opts.keyCode above so a caller that names neither still
---                     gets the original behaviour. { kind = "chord", mods = { ... } } is
---                     a modifier chord. See TRIGGERS for what each shape does. Omitted
---                     means the leader shape, which is what this spoon always did.
function obj:configure(opts)
  opts = opts or {}
  self._chord = opts.chord or self._chord
  self._keyCode = opts.keyCode or self._keyCode
  -- A new descriptor drops whatever strategy was already built, so the last word on the
  -- trigger is the one that wins however many times this is called.
  if opts.trigger ~= nil then
    self._triggerSpec = opts.trigger
    self._trigger = nil
  end
  self._tapThreshold = opts.tapThreshold or self._tapThreshold
  self._onTap = opts.onTap or self._onTap
  self._holdDelay = opts.holdDelay or self._holdDelay
  self._onHold = opts.onHold or self._onHold
  self._onHoldEnd = opts.onHoldEnd or self._onHoldEnd
  self._predicates = opts.predicates or self._predicates
  return self
end

--- HyperKey:bind(key, fn, mods, opts)
--- Method
--- Register a handler that fires when the Hyper key is held and `key` is pressed.
--- `mods` is an optional list of required modifier names ({"shift"}); omit it for
--- a catch-all binding that fires when no exact-mods binding matches. `opts` is
--- optional and carries the context extras, `when` (a predicate name gating the
--- binding on live state), `priority` (higher wins when several active bindings
--- match the same key; the base bindings are priority 0), and `repeats` (when
--- true the handler re-fires on each OS key autorepeat while the key is held,
--- for nav like a chooser's j/k; omit it for toggles, which must fire once). A
--- binding with none of these behaves exactly as a plain bind.
function obj:bind(key, fn, mods, opts)
  opts = opts or {}
  local name = type(key) == "string" and key:lower() or key
  local code = hs.keycodes.map[name]
  if code then
    self._bindings[code] = self._bindings[code] or {}
    table.insert(self._bindings[code], {
      mods = mods,
      fn = fn,
      when = opts.when,
      priority = opts.priority,
      repeats = opts.repeats,
    })
    -- Remember which predicates gate a binding. When any of these is live the
    -- Hyper key is modal (see _resolve), owned by that context.
    if opts.when then
      self._contextWhens[opts.when] = true
    end
    -- Tell a live trigger about the new binding, since a shape that has to claim a
    -- combination of its own cannot discover one by looking a pressed key up. There is
    -- nothing to tell before start, which sweeps the whole table itself, so the two orders
    -- of binding and starting agree.
    if self._trigger then self._trigger.bound(code, mods) end
  else
    log.w("unknown key '" .. tostring(key) .. "'")
  end
  return self
end

-- The only sub-modifiers a binding may require. `fn` is deliberately excluded:
-- macOS stamps `fn` onto some keys, so a raw exact check would never match. We
-- compare against these four only. Kept identical to the leader resolver.
local REAL_MODS = { "shift", "ctrl", "alt", "cmd" }

--- HyperKey:_passes(binding)
--- Method
--- Whether a binding's optional `when` predicate allows it right now. A binding
--- with no `when` always passes. An unknown predicate name is treated as active,
--- so a typo fails visibly (the key stays live) rather than silently dying.
function obj:_passes(binding)
  if not binding.when then return true end
  local pred = self._predicates and self._predicates[binding.when]
  if pred == nil then return true end
  return pred() and true or false
end

--- HyperKey:_modal()
--- Method
--- Whether any context is currently live. When one is, Hyper belongs to that
--- context, so the base bindings (those with no `when`) are suppressed and only
--- context bindings act. This is what makes a context modal rather than an
--- overlay, so while the clipboard is open Hyper+A does nothing instead of
--- toggling an app.
function obj:_modal()
  for name in pairs(self._contextWhens or {}) do
    local pred = self._predicates and self._predicates[name]
    if pred and pred() then
      return true
    end
  end
  return false
end

--- HyperKey:_resolve(list, flags)
--- Method
--- Pick the handler for the current modifier flags. A binding is eligible only if
--- its `when` predicate passes, and while a context is modal the base bindings
--- (no `when`) are dropped so the context fully owns Hyper. Among the eligible, an
--- exact match on the real modifiers (shift/ctrl/alt/cmd, ignoring `fn`) beats a
--- catch-all (mods == nil), and within each tier the highest `priority` wins.
--- Returns two values, the chosen handler and its `repeats` flag, so the engine
--- knows whether to re-run it on each OS key autorepeat.
function obj:_resolve(list, flags)
  if not list then return nil end

  local present = {}
  for _, m in ipairs(REAL_MODS) do
    if flags[m] then present[m] = true end
  end

  local modal = self:_modal()

  local function eligible(b)
    if not self:_passes(b) then return false end
    -- In a modal context, only context bindings act; base bindings are hidden.
    if modal and not b.when then return false end
    return true
  end

  local function modsMatch(b)
    local need = {}
    for _, m in ipairs(b.mods) do need[m] = true end
    for _, m in ipairs(REAL_MODS) do
      if (present[m] or false) ~= (need[m] or false) then
        return false
      end
    end
    return true
  end

  local bestExact, bestExactP, bestExactR = nil, -math.huge, nil
  local bestCatch, bestCatchP, bestCatchR = nil, -math.huge, nil
  for _, b in ipairs(list) do
    if eligible(b) then
      local p = b.priority or 0
      if b.mods then
        if modsMatch(b) and p > bestExactP then
          bestExact, bestExactP, bestExactR = b.fn, p, b.repeats
        end
      elseif p > bestCatchP then
        bestCatch, bestCatchP, bestCatchR = b.fn, p, b.repeats
      end
    end
  end
  if bestExact then return bestExact, bestExactR end
  return bestCatch, bestCatchR
end

--------------------------------------------------------------------------------
-- THE SEAM. Everything above is the domain policy and everything below is the trigger.
--------------------------------------------------------------------------------

-- Everything above this line is the binding table and the resolver that picks a handler for
-- the modifiers held, and none of it cares what physically means Hyper. Everything below is
-- the trigger, and the two shapes of trigger are genuinely different inputs rather than two
-- spellings of one. A single key emits a clean key down and key up, so it can be held,
-- measured, tapped, and swallowed, which is exactly what the shared ChordKey engine does with
-- it. A modifier chord emits neither, it is a flag stamped on somebody else's event, so
-- nothing about it can be measured that way. It is claimed through hs.hotkey, and the one
-- thing hs.hotkey cannot see, a chord held with no key pressed at all, is watched for
-- separately.
--
-- So the split is a Strategy, and the seam is this table. A strategy answers three functions,
-- start, isActive, and bound, and the three colon methods below are thin delegations to them.
-- Nothing outside this file learns which strategy is live, since the rest of the config
-- consumes only bind, isActive, and start on this module. The composition root chooses by
-- handing configure a descriptor built from config/settings.lua, so this file names no
-- setting and that file names no mechanism, and a third shape would be an entry here plus a
-- kind there with nothing in between moving.
--
-- What the two owe each other. Both resolve a pressed key through the same _resolve above, so
-- sub modifiers, priority, the when gates, and the modal suppression of base bindings behave
-- identically whichever is live. Both answer isActive about the hardware right now, because
-- the paste seams read it to hold a synthetic keystroke back while the trigger is asserted,
-- and an answer that is merely remembered would let a keystroke out too early. Both reveal
-- the cheat sheet after the same holdDelay and take it down when anything fires. The tap is
-- the one behaviour that does not cross over, since a chord has no bare press and release to
-- measure, and it stays a property of the key shape rather than becoming an option.
local TRIGGERS = {}

--- The single key shape, which is this machine's and which is this spoon's original path
--- unchanged. The key registers into the shared ChordKey engine, which owns the swallowing,
--- the tap, and the hold, and the resolver above goes in as its onKey. isActive asks that
--- engine whether the key is down. bound does nothing, because the engine looks a pressed key
--- up in the live binding table on every press and so needs no telling about a new one.
TRIGGERS.leader = function(host, spec)
  -- Read late rather than captured, so a configure after this strategy was built still
  -- decides the key.
  local function keyCode()
    return spec.keyCode or host._keyCode
  end
  return {
    bound = function() end,
    isActive = function()
      return host._chord ~= nil and host._chord:isActive(keyCode())
    end,
    start = function()
      if not host._chord then
        log.w("no ChordKey engine configured (opts.chord)")
        return host
      end
      local bindings = host._bindings
      host._chord:addKey(keyCode(), {
        tapThreshold = host._tapThreshold,
        holdDelay = host._holdDelay,
        onTap = host._onTap,
        onHold = host._onHold,
        onHoldEnd = host._onHoldEnd,
        -- Resolve the pressed key against its bindings, honouring optional sub-mods.
        onKey = function(code, flags)
          return host:_resolve(bindings[code], flags)
        end,
      })
      return host
    end,
  }
end

-- Seconds to let a shown hold overlay tear down before the chorded action runs. The same beat
-- and the same reason as the engine's own overlay settle, presenting a native panel in the
-- runloop tick that tears a canvas down races the presentation and the panel silently fails
-- to show. The quick path, where no overlay was up, stays immediate and pays nothing.
local OVERLAY_SETTLE = 0.05

--- The modifier chord shape. Every binding is claimed through hs.hotkey on the chord plus
--- whatever sub modifiers that binding already declared, so a binding written for Hyper keeps
--- working with no edit. hs.hotkey claims only what it binds, so a combination nobody declared
--- reaches whatever app wanted it and there is no passthrough machinery to write.
---
--- Two things it does that hs.hotkey does not. It resolves through _resolve rather than
--- trusting the combination, so several bindings on one key still sort by priority and by
--- their when gates exactly as they do under the key shape. And it watches flagsChanged for
--- the chord held alone, since holding modifiers presses no key and fires no hotkey, which is
--- the only way the hold reveal can exist at all here.
---
--- WHERE IT IS NOT THE KEY SHAPE, and cannot be. A combination nobody claimed runs no code
--- here at all, so a hold that presses an unbound key neither dispatches nor even notices the
--- press, where the key shape sees every key through its own tap and can end a hold on any of
--- them. A combination that IS claimed is claimed machine wide, so it is swallowed even at a
--- moment when every binding on it is gated shut, where the key shape would leak it downstream
--- through passthrough. And a sub modifier already inside the chord collapses into the base
--- combination, which is warned about once at load and cannot be repaired here.
---
--- Refuses a descriptor naming no modifiers, since claiming every Hyper key as a bare global
--- hotkey would take the whole keyboard. See _strategy for what a refusal falls back to.
TRIGGERS.chord = function(host, spec)
  local chordMods = spec.mods or {}
  if #chordMods == 0 then
    return nil, "the chord trigger names no modifiers, which would claim every Hyper key as a bare global hotkey"
  end
  local chordSet = {}
  for _, m in ipairs(chordMods) do chordSet[m] = true end

  -- One hs.hotkey per distinct pairing of a key with a resolved modifier set. Held in a table
  -- so a bound combination is never collected, and claimed once so a second binding on the
  -- same combination adds no second hotkey competing for it.
  local hotkeys, claimed = {}, {}
  local started = false

  -- Hold state, the same two flags the engine keeps per key. shown is whether the reveal is
  -- up, used is whether anything fired during this hold.
  local shown, used = false, false
  local holdTimer, watcher = nil, nil

  -- Deferred dispatches, each held until it fires. A Hammerspoon timer is userdata whose
  -- finalizer stops it, so one nothing refers to can be collected inside the wait and the
  -- handler then never runs at all, which reads as a keypress the machine ignored. Each gets
  -- its own key so a fast pair under one held chord cannot discard each other.
  local pending = {}
  local function defer(delay, fn)
    local slot = {}
    pending[slot] = hs.timer.doAfter(delay, function()
      pending[slot] = nil
      fn()
    end)
  end

  -- The modifiers a binding is actually claimed on, the chord united with the binding's own
  -- sub modifiers, in the fixed order of REAL_MODS so one set always spells one string.
  local function comboFor(subMods)
    local need = {}
    for _, m in ipairs(chordMods) do need[m] = true end
    for _, m in ipairs(subMods or {}) do need[m] = true end
    local out = {}
    for _, m in ipairs(REAL_MODS) do
      if need[m] then out[#out + 1] = m end
    end
    return out
  end

  -- The modifiers a binding is RESOLVED against, which is what is held minus the chord itself.
  -- The chord is the trigger and not part of what any binding asked for, exactly as the leader
  -- key is not part of it under the other shape. Leaving it in the flags makes every binding
  -- declaring a sub modifier fail its exact match and fall through to the catch all, so the
  -- second tier of a key silently becomes the first. Subtracting it is what makes a binding on
  -- Hyper plus Shift plus a key mean the same thing whichever shape is live.
  local function withoutChord(flags)
    local out = {}
    for _, m in ipairs(REAL_MODS) do
      if flags[m] and not chordSet[m] then out[m] = true end
    end
    return out
  end

  -- Whether an event's flags are exactly the chord and nothing else, which is what arms the
  -- reveal. Exactly rather than at least, since a chord plus one more modifier is on its way
  -- to being some other combination and revealing there would be answering the wrong question.
  local function exactly(flags)
    for _, m in ipairs(REAL_MODS) do
      if (flags[m] or false) ~= (chordSet[m] or false) then return false end
    end
    return true
  end

  local function cancelHold()
    if holdTimer then
      holdTimer:stop()
      holdTimer = nil
    end
  end

  -- What a claimed hotkey runs. It asks the resolver exactly as the engine's onKey does, with
  -- the modifiers read from the hardware since hs.hotkey hands its callback nothing, and with
  -- the chord taken back out of them.
  --
  -- The hold is ended FIRST, before the resolver is even asked, which is the engine's own
  -- order. A press is a press whether or not it turns out to mean anything, so a reveal must
  -- come down and a pending one must be cancelled on any claimed key, or a chord holding
  -- through a gated shut key leaves the sheet hanging over whatever opens next.
  --
  -- Resolving to nothing then does nothing further, and the key is still swallowed, since a
  -- combination this claimed is claimed whether or not every binding on it happens to be gated
  -- shut at that moment. A combination nobody claimed never reaches here at all.
  local function fire(code)
    used = true
    cancelHold()
    local wasShown = shown
    if shown then
      shown = false
      if host._onHoldEnd then host._onHoldEnd() end
    end
    local flags = withoutChord(hs.eventtap.checkKeyboardModifiers() or {})
    local fn = host:_resolve(host._bindings[code], flags)
    if not fn then return end
    defer(wasShown and OVERLAY_SETTLE or 0, fn)
  end

  -- The OS autorepeat of a held key. Only a binding that asked for repeat runs again, matching
  -- the engine, so a toggle fires once however long the key is held while a nav key scrolls.
  -- The chord comes out of the flags here too, or a nav key declaring a sub modifier would
  -- resolve to the wrong binding on every repeat as well as on the first press.
  local function fireRepeat(code)
    local flags = withoutChord(hs.eventtap.checkKeyboardModifiers() or {})
    local fn, repeats = host:_resolve(host._bindings[code], flags)
    if fn and repeats then fn() end
  end

  -- A binding whose own sub modifiers overlap the chord cannot be reached, and this is the one
  -- place that can see it. The chord is subtracted before resolving, so an overlapping sub
  -- modifier is already gone by the time the resolver looks, its exact match can never succeed,
  -- and the plain binding on that key answers the combination instead. The two really are one
  -- physical combination under this chord, so there is nothing to repair and the only honest
  -- thing is to say it out loud once at load rather than leave a key quietly doing the other
  -- thing. Checked per binding rather than per claimed combination, so the second binding to
  -- collapse onto a combination is named too.
  local function warnIfUnreachable(code, subMods)
    if not subMods or #subMods == 0 then return end
    local overlap = {}
    for _, m in ipairs(REAL_MODS) do
      for _, s in ipairs(subMods) do
        if s == m and chordSet[m] then overlap[#overlap + 1] = m end
      end
    end
    if #overlap == 0 then return end
    local name = hs.keycodes.map[code] or tostring(code)
    log.w(string.format(
      "the %s binding asking for %s cannot be reached under this chord, %s is already part of the chord itself, so the plain %s binding answers that combination and this one never fires",
      tostring(name), table.concat(subMods, "+"), table.concat(overlap, "+"), tostring(name)))
  end

  local function claim(code, subMods)
    warnIfUnreachable(code, subMods)
    local combo = comboFor(subMods)
    local id = tostring(code) .. "|" .. table.concat(combo, "+")
    if claimed[id] then return end
    claimed[id] = true
    hotkeys[#hotkeys + 1] = hs.hotkey.bind(combo, code,
      function() fire(code) end, nil, function() fireRepeat(code) end)
  end

  -- The hold reveal, the one behaviour a chord cannot get from hs.hotkey, since holding
  -- modifiers alone presses no key. Any change of flags cancels a pending reveal and takes a
  -- shown one down, and landing exactly on the chord arms a fresh one after the same holdDelay
  -- the key shape uses, so both shapes reveal after the same wait. Returning false always,
  -- because this watches and never claims.
  local function onFlags(e)
    local flags = e:getFlags()
    cancelHold()
    if shown then
      shown = false
      if host._onHoldEnd then host._onHoldEnd() end
    end
    if not exactly(flags) then return false end
    used = false
    if not host._onHold or not host._holdDelay then return false end
    holdTimer = hs.timer.doAfter(host._holdDelay, function()
      holdTimer = nil
      if used then return end
      shown = true
      host._onHold()
    end)
    return false
  end

  return {
    bound = function(code, subMods)
      if started then claim(code, subMods) end
    end,
    isActive = function()
      local live = hs.eventtap.checkKeyboardModifiers() or {}
      for _, m in ipairs(chordMods) do
        if not live[m] then return false end
      end
      return true
    end,
    start = function()
      started = true
      for code, list in pairs(host._bindings or {}) do
        for _, b in ipairs(list) do claim(code, b.mods) end
      end
      if not watcher then
        watcher = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, onFlags)
        watcher:start()
      end
      return host
    end,
  }
end

--- HyperKey:_strategy()
--- Method
--- The live trigger strategy, built once from the descriptor and cached from then on, so a
--- bind arriving long after start reaches the same instance.
---
--- Two ways a descriptor can fail to produce one, a kind nothing answers to and a strategy
--- refusing the descriptor it was handed. Both land on the leader shape and both say why,
--- because a descriptor that cannot be honoured leaving Hyper dead, or worse leaving it
--- claiming the whole keyboard, is a great deal worse than one leaving Hyper as it was. A
--- builder refuses by returning nil and a reason, which is the whole of that contract.
---
--- The fallback carries no keycode of its own and takes the one configure was given, which is
--- why the root resolves the catalog keycode whatever shape it asked for.
function obj:_strategy()
  if not self._trigger then
    local spec = self._triggerSpec or { kind = "leader" }
    local build = TRIGGERS[spec.kind]
    local built, refused
    if build then
      built, refused = build(self, spec)
    else
      refused = "unknown trigger kind '" .. tostring(spec.kind) .. "'"
    end
    if not built then
      log.w(tostring(refused) .. ", using the leader key instead")
      built = TRIGGERS.leader(self, { kind = "leader" })
    end
    self._trigger = built
  end
  return self._trigger
end

--- HyperKey:isActive()
--- Method
--- Return true while the Hyper trigger is physically asserted, which is the key being held
--- under the leader shape and every chord modifier being held under the chord shape.
--- Consumers use this to defer synthetic keystrokes
--- until release, since the engine's tap swallows every key during a hold.
function obj:isActive()
  return self:_strategy().isActive()
end

--- HyperKey:start()
--- Method
--- Begin the configured trigger. Under the leader shape that registers the Hyper key into the
--- shared ChordKey engine, whose own start() (called once from init.lua) begins the actual
--- event tap, with onHold / onHoldEnd passed straight through -- ChordKey calls them with the
--- keycode, which the Hyper callbacks simply ignore. Under the chord shape it claims every
--- declared binding and starts the watcher behind the hold reveal. Either way a binding
--- registered after this still works.
function obj:start()
  return self:_strategy().start()
end

return obj
