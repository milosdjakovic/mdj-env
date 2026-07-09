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
--- Everything lives inside Hammerspoon, so it adds no background process.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "WindowLeader"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

obj._tap = nil
obj._leaders = nil -- keyCode -> { active = bool, bindings = { code -> { {mods, fn}, ... } } }

--- WindowLeader:init()
--- Method
--- Initialize the spoon
function obj:init()
  self._leaders = {}
  return self
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

--- WindowLeader:_resolve(list, flags)
--- Method
--- Pick the handler for the current modifier flags: an exact-mods match wins,
--- otherwise fall back to a catch-all (mods == nil) binding if present.
function obj:_resolve(list, flags)
  if not list then return nil end
  local catchAll = nil
  for _, b in ipairs(list) do
    if b.mods then
      if flags:containExactly(b.mods) then
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

    -- A leader key itself: track held state and swallow it entirely.
    local leader = self._leaders[code]
    if leader then
      leader.active = (t == types.keyDown)
      return true, {}
    end

    -- Other keys, only while some leader is held.
    for _, l in pairs(self._leaders) do
      if l.active then
        if t == types.keyDown then
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
    l.active = false
  end
  return self
end

return obj
