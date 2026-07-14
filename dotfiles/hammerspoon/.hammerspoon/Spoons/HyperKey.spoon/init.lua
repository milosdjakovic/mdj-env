--- === HyperKey ===
---
--- Domain adapter: turn a single physical key into a "Hyper" trigger with a tap
--- fallback, for app-toggle style bindings (a key -> function map).
---
--- A binding may require exact sub-modifiers (e.g. Shift), so one key can host
--- two tiers: Hyper+4 fires one action while Hyper+Shift+4 fires another.
--- Bindings with no `mods` are catch-alls, they fire whenever no exact-mods
--- binding matches the modifiers held. This mirrors WindowLeader's resolver, so
--- both adapters share one policy; most Hyper bindings pass no mods and stay a
--- plain key lookup.
---
--- The hold / tap / chord MECHANICS -- swallowing keys while held, hold-to-reveal
--- timing, why the key must emit clean key-down/up -- live in ChordKey.spoon.
--- This spoon owns only the binding table and the tap policy, and registers its
--- key into the shared ChordKey engine (passed as opts.chord). Keeping it as a
--- thin adapter preserves the :bind / :isActive contract that AppToggler and
--- ClipboardHistory depend on, while the engine is shared with WindowLeader.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "HyperKey"
obj.version = "4.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

obj._chord = nil      -- shared ChordKey engine
obj._bindings = nil   -- keycode -> { { mods, fn }, ... }

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
function obj:configure(opts)
  opts = opts or {}
  self._chord = opts.chord or self._chord
  self._keyCode = opts.keyCode or self._keyCode
  self._tapThreshold = opts.tapThreshold or self._tapThreshold
  self._onTap = opts.onTap or self._onTap
  self._holdDelay = opts.holdDelay or self._holdDelay
  self._onHold = opts.onHold or self._onHold
  self._onHoldEnd = opts.onHoldEnd or self._onHoldEnd
  return self
end

--- HyperKey:bind(key, fn, mods)
--- Method
--- Register a handler that fires when the Hyper key is held and `key` is pressed.
--- `mods` is an optional list of required modifier names ({"shift"}); omit it for
--- a catch-all binding that fires when no exact-mods binding matches.
function obj:bind(key, fn, mods)
  local name = type(key) == "string" and key:lower() or key
  local code = hs.keycodes.map[name]
  if code then
    self._bindings[code] = self._bindings[code] or {}
    table.insert(self._bindings[code], { mods = mods, fn = fn })
  else
    print("HyperKey: unknown key '" .. tostring(key) .. "'")
  end
  return self
end

-- The only sub-modifiers a binding may require. `fn` is deliberately excluded:
-- macOS stamps `fn` onto some keys, so a raw exact check would never match. We
-- compare against these four only. Kept identical to WindowLeader's resolver.
local REAL_MODS = { "shift", "ctrl", "alt", "cmd" }

--- HyperKey:_resolve(list, flags)
--- Method
--- Pick the handler for the current modifier flags: an exact match on the real
--- modifiers (shift/ctrl/alt/cmd, ignoring `fn`) wins, otherwise fall back to a
--- catch-all (mods == nil) binding if present.
function obj:_resolve(list, flags)
  if not list then return nil end

  local present = {}
  for _, m in ipairs(REAL_MODS) do
    if flags[m] then present[m] = true end
  end

  local catchAll = nil
  for _, b in ipairs(list) do
    if b.mods then
      local need = {}
      for _, m in ipairs(b.mods) do need[m] = true end
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

--- HyperKey:isActive()
--- Method
--- Return true while the Hyper key is physically held. Delegates to ChordKey.
--- Consumers (e.g. ClipboardHistory) use this to defer synthetic keystrokes
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
    print("HyperKey: no ChordKey engine configured (opts.chord)")
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

--- HyperKey:stop()
--- Method
--- No-op: the shared ChordKey engine owns the event tap.
function obj:stop()
  return self
end

return obj
