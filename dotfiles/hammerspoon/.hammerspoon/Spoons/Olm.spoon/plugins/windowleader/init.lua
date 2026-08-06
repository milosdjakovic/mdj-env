--- === WindowLeader ===
---
--- Domain adapter: function-key "leader" modifiers for window management.
---
--- Right Option and Right Command are remapped to function keys at the HID level
--- from the leaderKeys catalog in config/keys.lua. This spoon owns the per-leader binding
--- tables and the sub-modifier resolution policy; the hold / tap / chord
--- MECHANICS (swallowing keys while held, hold-to-reveal timing) live in
--- ChordKey.spoon, the shared engine it registers its leaders into (opts.chord).
--- There is no tap fallback here. These keys exist only to drive
--- window management, so a bare press/release does nothing.
---
--- A binding may require exact sub-modifiers (e.g. Shift), so one leader can
--- host two tiers: on F16, a bare arrow switches display while Shift+arrow moves
--- the window. Bindings with no `mods` are catch-alls -- they fire whenever no
--- exact-mods binding matches the currently held modifiers.
---
--- Holding a leader ~holdDelay seconds with no other key fires the optional
--- onHold(leaderKeyCode) callback (used to reveal a cheat sheet); pressing any
--- bound key cancels it. Keeping WindowLeader a thin adapter preserves the
--- :bind contract its consumer depends on.
---
--- This is the olm side copy of WindowLeader, made in the bundling pass, phase 6 of the
--- olm build plan, and the original this was copied from still lives at
--- Spoons/WindowLeader.spoon.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "WindowLeader"
obj.version = "2.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("WindowLeader", "info")

obj._chord = nil   -- shared ChordKey engine
obj._leaders = nil -- keyCode -> { bindings = { code -> { {mods, fn}, ... } } }

-- Hold to reveal. onHold receives the leader's keycode so
-- a cheat sheet can show that leader's bindings; onHoldEnd takes none.
obj._holdDelay = 0.6
obj._onHold = nil
obj._onHoldEnd = nil

--- WindowLeader:init()
--- Method
--- Initialize the spoon
function obj:init()
  self._leaders = {}
  return self
end

--- WindowLeader:configure(opts)
--- Method
--- opts.chord     - the shared ChordKey engine to register into (required)
--- opts.holdDelay - seconds to hold a leader (no other key) before onHold fires
--- opts.onHold    - function(leaderKeyCode) run once the hold passes holdDelay
--- opts.onHoldEnd - function() run when a shown hold ends (release or key press)
function obj:configure(opts)
  opts = opts or {}
  self._chord = opts.chord or self._chord
  self._holdDelay = opts.holdDelay or self._holdDelay
  self._onHold = opts.onHold or self._onHold
  self._onHoldEnd = opts.onHoldEnd or self._onHoldEnd
  return self
end

--- WindowLeader:addLeader(keyCode)
--- Method
--- Register a leader key by its (remapped) virtual keycode, e.g. 64 (F17).
function obj:addLeader(keyCode)
  self._leaders[keyCode] = self._leaders[keyCode] or { bindings = {} }
  return self
end

--- WindowLeader:bind(leaderKeyCode, key, fn, mods)
--- Method
--- Register a handler under a leader. `mods` is an optional list of required
--- modifier names ({"shift"}); omit it for a catch-all binding.
function obj:bind(leaderKeyCode, key, fn, mods)
  local leader = self._leaders[leaderKeyCode]
  if not leader then
    log.w("no leader registered for keycode " .. tostring(leaderKeyCode))
    return self
  end

  local name = type(key) == "string" and key:lower() or key
  local code = hs.keycodes.map[name]
  if not code then
    log.w("unknown key '" .. tostring(key) .. "'")
    return self
  end

  leader.bindings[code] = leader.bindings[code] or {}
  table.insert(leader.bindings[code], { mods = mods, fn = fn })
  return self
end

-- The only sub-modifiers a binding may require. `fn` is deliberately excluded:
-- macOS stamps `fn` onto arrow (and nav) keys, so a raw containExactly() check
-- would never match a Shift+arrow binding. We compare against these four only.
local REAL_MODS = { "shift", "ctrl", "alt", "cmd" }

--- WindowLeader:_resolve(list, flags)
--- Method
--- Pick the handler for the current modifier flags: an exact match on the real
--- modifiers (shift/ctrl/alt/cmd, ignoring `fn`) wins, otherwise fall back to a
--- catch-all (mods == nil) binding if present.
function obj:_resolve(list, flags)
  if not list then return nil end

  -- Which real modifiers are actually held right now.
  local present = {}
  for _, m in ipairs(REAL_MODS) do
    if flags[m] then present[m] = true end
  end

  local catchAll = nil
  for _, b in ipairs(list) do
    if b.mods then
      local need = {}
      for _, m in ipairs(b.mods) do need[m] = true end
      -- Exact match: every real modifier's held-state equals its required-state.
      local match = true
      for _, m in ipairs(REAL_MODS) do
        if (present[m] or false) ~= (need[m] or false) then
          match = false
          break
        end
      end
      if match then
        return b.fn
      end
    else
      catchAll = b.fn
    end
  end
  return catchAll
end

--- WindowLeader:start()
--- Method
--- Register every leader into the shared ChordKey engine. The engine's own
--- start() (called once from init.lua) begins the actual event tap. Each
--- leader's onKey resolves the pressed key against that leader's bindings,
--- honouring optional sub-modifiers.
function obj:start()
  if not self._chord then
    log.w("no ChordKey engine configured (opts.chord)")
    return self
  end
  for keyCode, leader in pairs(self._leaders) do
    self._chord:addKey(keyCode, {
      holdDelay = self._holdDelay,
      onHold = self._onHold,
      onHoldEnd = self._onHoldEnd,
      -- No onTap: leaders have no tap fallback.
      onKey = function(code, flags)
        return self:_resolve(leader.bindings[code], flags)
      end,
    })
  end
  return self
end

return obj
