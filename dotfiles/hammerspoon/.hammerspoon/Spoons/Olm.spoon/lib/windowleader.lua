--- === WindowLeader ===
---
--- Domain adapter: function-key "leader" modifiers for window management.
---
--- Right Option and Right Command are remapped to function keys at the HID level from the
--- root's leader catalog, see lib/keyremap.lua. This file owns the binding table and the
--- sub modifier resolution policy, the hold, tap and chord MECHANICS (swallowing keys while
--- held, hold to reveal timing) live in lib/chordkey.lua, the shared engine it registers its
--- leader into (opts.chord). There is no tap fallback here. This key exists only to drive
--- window management, so a bare press and release does nothing.
---
--- This was a plugin until phase two of the core split and it is core now, beside hyperkey,
--- which it mirrors on purpose. The root configures it once with the keycode the window role
--- resolved to, and a plugin that declares leader = "window" binds onto it the way a plugin on
--- the app leader binds onto Hyper, through bind(key, fn, mods, repeats) with no keycode in
--- sight, after asking for it through needs.lib.windowLeader. The root collects what such
--- plugins declare by walking the plan, so nothing here or there names a plugin.
---
--- A binding may require exact sub modifiers (e.g. Shift), so one leader can host two tiers,
--- a bare arrow switches display while Shift and an arrow moves the window. Bindings with no
--- `mods` are catch alls, they fire whenever no exact mods binding matches the currently held
--- modifiers.
---
--- Holding the leader about holdDelay seconds with no other key reveals the window cheat
--- sheet, calling show(leaderKeyCode) on the host opts.windowCheatSheet is. Releasing, or
--- pressing any bound key, calls hide() on it and cancels the hold. The root names the host
--- outright, since both are core, but the two closures that call it are built here, never
--- handed in from outside, which is what keeps this a thin adapter and preserves the :bind
--- contract its consumers depend on.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "WindowLeader"
obj.version = "2.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("WindowLeader", "info")

obj._chord = nil   -- shared ChordKey engine
obj._leaders = nil -- keyCode -> { bindings = { code -> { {mods, fn, repeats}, ... } } }
-- The one keycode the window role resolved to, set by configure. A plugin binds without ever
-- seeing it, which is what makes moving the window leader to another physical key one edit.
obj._keyCode = nil

-- Hold to reveal. onHold and onHoldEnd are this file's own closures, built once in
-- configure rather than handed in from outside, since the only part of this coupling
-- anything else could know is which module answers show and hide, never the callback
-- itself. _windowCheatSheet is that collaborator, the host configure receives under
-- opts.windowCheatSheet, nil where none loaded, in which case both closures below still
-- fire on schedule and simply find nothing to call.
obj._holdDelay = 0.6
-- Window actions are nudges rather than toggles, so a bound key that says it repeats has its
-- repeats scheduled by the engine rather than taken from the OS autorepeat events. The timing
-- is the same either way, the machine's own delay and then its own steady rate. What the
-- driven mode buys is that each repeat knows how deep into the hold it is, which is what lets
-- a press place a window by eye while a repeat travels far enough to cross a screen. This is
-- the leader's own answer for every key under it, a property of the domain rather than of one
-- binding, and configure may put it back on the plain OS events.
obj._repeatMode = "driven"
obj._onHold = nil
obj._onHoldEnd = nil
obj._windowCheatSheet = nil
-- An injected gate that answers true while the window leader must stay quiet, which today
-- means while any Olm list is open. The leaders exist to drive window management, and a
-- window action fired over an open chooser moves or resizes whatever sits underneath the
-- list a person is reading, so the whole leader goes inert rather than any one binding
-- carrying its own guard. Policy arrives from the composition root, this file never asks
-- what the gate actually watches, and absent means never suppressed, the original behaviour.
obj._suppressWhen = nil

-- What a suppressed key resolves to. A bound handler that does nothing, rather than nil,
-- because the shared engine treats an unresolved key as unbound, and with passthrough on it
-- would synthesize the pressed key downstream, where the open list's own field would receive
-- it as typed text. Bound and inert is the only answer that both runs nothing and swallows.
local function noop() end

--- WindowLeader:init()
--- Method
--- Initialize the spoon
function obj:init()
  self._leaders = {}
  return self
end

--- WindowLeader:configure(opts)
--- Method
--- opts.chord           - the shared ChordKey engine to register into (required)
--- opts.keyCode         - the virtual keycode the window role resolved to, the one leader
---                        bind(key, fn, mods, repeats) binds onto
--- opts.holdDelay       - seconds to hold a leader (no other key) before the hold reveals
--- opts.repeatMode      - how a repeating binding under this leader keeps firing, the shared
---                        engine's own option, "driven" here rather than the engine's
---                        "system" default
--- opts.windowCheatSheet - the window cheat sheet host, this file's own hold calls
---                         show(leaderKeyCode) on it and its own release calls hide(),
---                         absent means only the reveal is lost, the leader and every
---                         bound key keep working
--- opts.suppressWhen    - a function answering true while every leader must stay quiet, no
---                        reveal on hold and every bound key inert though still swallowed,
---                        consulted live at each hold and each press, absent means never
function obj:configure(opts)
  opts = opts or {}
  self._chord = opts.chord or self._chord
  self._keyCode = opts.keyCode or self._keyCode
  self._holdDelay = opts.holdDelay or self._holdDelay
  self._repeatMode = opts.repeatMode or self._repeatMode
  self._windowCheatSheet = opts.windowCheatSheet or self._windowCheatSheet
  self._suppressWhen = opts.suppressWhen or self._suppressWhen

  -- Built here rather than accepted as opts.onHold and opts.onHoldEnd, so the composition
  -- root only ever hands over the collaborator and never the callback. The earlier shape
  -- had the root build both closures itself, which put the knowledge of what a hold does in
  -- the wrong file.
  self._onHold = function(leaderKeyCode)
    if self._suppressWhen and self._suppressWhen() then return end
    local sheet = self._windowCheatSheet
    if sheet then sheet:show(leaderKeyCode) end
  end
  self._onHoldEnd = function()
    local sheet = self._windowCheatSheet
    if sheet then sheet:hide() end
  end

  return self
end

--- WindowLeader:addLeader(keyCode)
--- Method
--- Register a leader key by its (remapped) virtual keycode, e.g. 64 (F17). The root calls it
--- once with the same keycode it gave configure, in the leaders stage ahead of every plugin.
function obj:addLeader(keyCode)
  self._leaders[keyCode] = self._leaders[keyCode] or { bindings = {} }
  return self
end

--- WindowLeader:bind(key, fn, mods, repeats)
--- Method
--- Register a handler under the window leader, the keycode configure was given. `mods` is an optional list of required
--- modifier names ({"shift"}); omit it for a catch-all binding. `repeats` is true for a
--- handler that should keep firing while its key stays held, which is the binding's own
--- business rather than the leader's, since moving a window a step is worth repeating and
--- maximizing it is not. HOW it repeats is the leader's, see _repeatMode.
function obj:bind(key, fn, mods, repeats)
  local leader = self._leaders[self._keyCode]
  if not leader then
    log.w("no window leader registered, so '" .. tostring(key) .. "' was not bound")
    return self
  end

  local name = type(key) == "string" and key:lower() or key
  local code = hs.keycodes.map[name]
  if not code then
    log.w("unknown key '" .. tostring(key) .. "'")
    return self
  end

  leader.bindings[code] = leader.bindings[code] or {}
  table.insert(leader.bindings[code], { mods = mods, fn = fn, repeats = repeats })
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
---
--- Answers the handler and its `repeats` flag as a pair, the shape the shared engine's onKey
--- contract asks for, so whether a key keeps firing travels with the handler that was
--- actually chosen rather than being looked up a second time against a different set of
--- modifiers than the one that resolved.
function obj:_resolve(list, flags)
  if not list then return nil end

  -- Which real modifiers are actually held right now.
  local present = {}
  for _, m in ipairs(REAL_MODS) do
    if flags[m] then present[m] = true end
  end

  local catchAll, catchAllRepeats = nil, nil
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
        return b.fn, b.repeats
      end
    else
      catchAll, catchAllRepeats = b.fn, b.repeats
    end
  end
  return catchAll, catchAllRepeats
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
      repeatMode = self._repeatMode,
      onHold = self._onHold,
      onHoldEnd = self._onHoldEnd,
      -- No onTap: leaders have no tap fallback.
      onKey = function(code, flags)
        if self._suppressWhen and self._suppressWhen() then return noop end
        return self:_resolve(leader.bindings[code], flags)
      end,
    })
  end
  return self
end

return obj
