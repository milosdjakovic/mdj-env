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
function obj:configure(opts)
  opts = opts or {}
  self._chord = opts.chord or self._chord
  self._keyCode = opts.keyCode or self._keyCode
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

--- HyperKey:isActive()
--- Method
--- Return true while the Hyper key is physically held. Delegates to ChordKey.
--- Consumers use this to defer synthetic keystrokes
--- until release, since the engine's tap swallows every key during a hold.
function obj:isActive()
  return self._chord ~= nil and self._chord:isActive(self._keyCode)
end

--- HyperKey:start()
--- Method
--- Register the Hyper key into the shared ChordKey engine. The engine's own
--- start() (called once from init.lua) begins the actual event tap. onHold /
--- onHoldEnd are passed straight through -- ChordKey calls them with the
--- keycode, which the Hyper callbacks simply ignore.
function obj:start()
  if not self._chord then
    log.w("no ChordKey engine configured (opts.chord)")
    return self
  end
  local bindings = self._bindings
  self._chord:addKey(self._keyCode, {
    tapThreshold = self._tapThreshold,
    holdDelay = self._holdDelay,
    onTap = self._onTap,
    onHold = self._onHold,
    onHoldEnd = self._onHoldEnd,
    -- Resolve the pressed key against its bindings, honouring optional sub-mods.
    onKey = function(code, flags)
      return self:_resolve(bindings[code], flags)
    end,
  })
  return self
end

return obj
