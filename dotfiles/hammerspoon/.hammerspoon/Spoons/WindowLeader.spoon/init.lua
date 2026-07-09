--- === WindowLeader ===
---
--- Function-key "leader" modifiers for window management.
---
--- Right Option and Right Command are remapped to F17 and F16 at the HID level
--- (see src/setup-capslock-hyper.sh). While a leader key is physically held,
--- bound keys dispatch to their handlers and are swallowed (nothing leaks
--- through). Unlike HyperKey there is no tap fallback -- these keys exist only
--- to drive window management, so a bare press/release does nothing.
---
--- A binding may require exact sub-modifiers (e.g. Shift), so one leader can
--- host two tiers: on F16, a bare arrow switches display while Shift+arrow
--- moves the window. Bindings with no `mods` are catch-alls -- they fire
--- whenever no exact-mods binding matches the currently held modifiers.
---
--- Like HyperKey, holding a leader ~holdDelay seconds with no other key fires
--- the optional onHold(leaderKeyCode) callback (used to reveal a cheat sheet);
--- pressing any bound key cancels it. Wire this via configure().
---
--- Everything lives inside Hammerspoon, so it adds no background process.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "WindowLeader"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

obj._tap = nil
obj._leaders = nil -- keyCode -> { active, used, shown, holdTimer, bindings = { code -> { {mods, fn}, ... } } }

-- Optional hold-to-reveal (parallels HyperKey). onHold receives the leader's
-- keycode so a cheat sheet can show that leader's bindings; onHoldEnd takes none.
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
--- opts.holdDelay - seconds to hold a leader (no other key) before onHold fires
--- opts.onHold    - function(leaderKeyCode) run once the hold passes holdDelay
--- opts.onHoldEnd - function() run when a shown hold ends (release or key press)
function obj:configure(opts)
  opts = opts or {}
  self._holdDelay = opts.holdDelay or self._holdDelay
  self._onHold = opts.onHold or self._onHold
  self._onHoldEnd = opts.onHoldEnd or self._onHoldEnd
  return self
end

--- WindowLeader:_cancelHold(leader)
--- Method
--- Cancel a leader's pending hold-overlay timer
function obj:_cancelHold(leader)
  if leader.holdTimer then
    leader.holdTimer:stop()
    leader.holdTimer = nil
  end
end

--- WindowLeader:addLeader(keyCode)
--- Method
--- Register a leader key by its (remapped) virtual keycode, e.g. 64 (F17).
function obj:addLeader(keyCode)
  self._leaders[keyCode] = self._leaders[keyCode] or { active = false, bindings = {} }
  return self
end

--- WindowLeader:bind(leaderKeyCode, key, fn, mods)
--- Method
--- Register a handler under a leader. `mods` is an optional list of required
--- modifier names ({"shift"}); omit it for a catch-all binding.
function obj:bind(leaderKeyCode, key, fn, mods)
  local leader = self._leaders[leaderKeyCode]
  if not leader then
    print("WindowLeader: no leader registered for keycode " .. tostring(leaderKeyCode))
    return self
  end

  local name = type(key) == "string" and key:lower() or key
  local code = hs.keycodes.map[name]
  if not code then
    print("WindowLeader: unknown key '" .. tostring(key) .. "'")
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
--- Begin watching for leader keys and their bound keys
function obj:start()
  local types = hs.eventtap.event.types
  self._tap = hs.eventtap.new({ types.keyDown, types.keyUp }, function(e)
    local t = e:getType()
    local code = e:getKeyCode()

    -- A leader key itself: track held state, arm the hold overlay, swallow it.
    local leader = self._leaders[code]
    if leader then
      if t == types.keyDown then
        -- Held keys auto-repeat key-down; only the first press starts a hold.
        if not leader.active then
          leader.active = true
          leader.used = false
          leader.shown = false
          if self._onHold and self._holdDelay then
            leader.holdTimer = hs.timer.doAfter(self._holdDelay, function()
              if leader.active and not leader.used then
                leader.shown = true
                self._onHold(code)
              end
            end)
          end
        end
      else -- keyUp
        self:_cancelHold(leader)
        if leader.shown and self._onHoldEnd then
          self._onHoldEnd()
        end
        leader.shown = false
        leader.active = false
      end
      return true, {}
    end

    -- Other keys, only while some leader is held.
    for _, l in pairs(self._leaders) do
      if l.active then
        if t == types.keyDown then
          -- A real key press means this is window management, not a cheat-sheet
          -- hold: cancel the pending overlay (and dismiss it if already shown).
          l.used = true
          self:_cancelHold(l)
          if l.shown and self._onHoldEnd then
            self._onHoldEnd()
            l.shown = false
          end
          local fn = self:_resolve(l.bindings[code], e:getFlags())
          if fn then
            hs.timer.doAfter(0, fn)
          end
        end
        return true, {} -- swallow so nothing leaks while a leader is held
      end
    end

    return false
  end)
  self._tap:start()
  return self
end

--- WindowLeader:stop()
--- Method
--- Stop watching
function obj:stop()
  if self._tap then
    self._tap:stop()
  end
  for _, l in pairs(self._leaders or {}) do
    self:_cancelHold(l)
    l.active = false
    l.shown = false
  end
  return self
end

return obj
