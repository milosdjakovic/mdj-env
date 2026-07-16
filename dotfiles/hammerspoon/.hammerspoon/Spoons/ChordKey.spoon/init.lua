--- === ChordKey ===
---
--- Shared hold / tap / chord engine for function-key "leader" keys.
---
--- A single physical key -- which must emit clean key-down/key-up events, e.g.
--- the F16/F17/F18 that Right Command / Right Option / Caps Lock are remapped to
--- via hidutil (see src/setup-capslock-hyper.sh) -- becomes a modifier you HOLD.
--- A real modifier or a raw toggle key like Caps Lock will not work: modifiers
--- stamp their flag onto every keystroke, and Caps Lock emits no usable up/down.
---
--- While a registered key is held, other keys are routed to their handlers and
--- swallowed (so nothing leaks through). Two optional behaviours ride on top:
---   * a quick tap with no other key runs onTap (used to toggle real Caps Lock);
---   * holding past holdDelay with no other key runs onHold (used to reveal a
---     cheat sheet), and onHoldEnd fires when that shown hold releases.
---
--- This is only the MECHANISM. The domain policy -- which keys map to what, and
--- how sub-modifiers resolve -- lives in the callers (HyperKey, WindowLeader),
--- which register their key(s) here via addKey() and supply an onKey() lookup.
--- Because every key shares ONE eventtap, N leaders cost one tap, not N.
---
--- Everything lives inside Hammerspoon, so it adds no background process.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "ChordKey"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

obj._tap = nil
obj._keys = nil        -- keyCode -> entry (config + runtime state)

-- Real hardware key events carry this event-source state id
-- (kCGEventSourceStateHIDSystemState). Keystrokes Hammerspoon posts itself, like
-- the clipboard paste's Cmd+V, carry a private id instead, so this tells the two
-- apart. See start(), which ignores everything that is not physical.
local HID_SYSTEM_STATE = 1

-- Defaults applied to any key that does not override them (see configure()).
obj._holdDelay = 0.6
obj._tapThreshold = 0.2

--- ChordKey:init()
--- Method
--- Initialize the spoon
function obj:init()
  self._keys = {}
  return self
end

--- ChordKey:configure(opts)
--- Method
--- Set the defaults inherited by keys registered without their own value.
--- opts.holdDelay    - seconds held (nothing else pressed) before onHold fires
--- opts.tapThreshold - seconds under which a bare press/release counts as a tap
function obj:configure(opts)
  opts = opts or {}
  if opts.holdDelay ~= nil then self._holdDelay = opts.holdDelay end
  if opts.tapThreshold ~= nil then self._tapThreshold = opts.tapThreshold end
  return self
end

--- ChordKey:addKey(keyCode, opts)
--- Method
--- Register a chord key by its (remapped) virtual keycode. opts:
---   holdDelay    - override the default hold delay for this key
---   tapThreshold - override the default tap threshold for this key
---   onTap        - function() on a quick tap with no other key (optional; omit
---                  for keys with no tap fallback, e.g. window leaders)
---   onHold       - function(keyCode) once the hold passes holdDelay (optional)
---   onHoldEnd    - function(keyCode) when a shown hold ends (release or key)
---   onKey        - function(pressedKeyCode, flags) -> handler|nil; the returned
---                  handler (if any) is dispatched when a key is pressed while
---                  this chord key is held. This is where domain lookup and
---                  sub-modifier resolution live.
function obj:addKey(keyCode, opts)
  opts = opts or {}
  self._keys[keyCode] = {
    code = keyCode,
    holdDelay = opts.holdDelay or self._holdDelay,
    tapThreshold = opts.tapThreshold or self._tapThreshold,
    onTap = opts.onTap,
    onHold = opts.onHold,
    onHoldEnd = opts.onHoldEnd,
    onKey = opts.onKey,
    -- runtime state
    active = false,
    used = false,   -- was another key pressed during this hold?
    shown = false,  -- has onHold fired (overlay is up)?
    downTime = 0,
    holdTimer = nil,
  }
  return self
end

--- ChordKey:isActive(keyCode)
--- Method
--- Return true while the given chord key is physically held. Useful for actions
--- that synthesize keystrokes: the tap swallows all keys during a hold, so such
--- actions must wait for release before posting their events.
function obj:isActive(keyCode)
  local k = self._keys[keyCode]
  return k ~= nil and k.active
end

--- ChordKey:_cancelHold(k)
--- Method
--- Cancel a key's pending hold-overlay timer
function obj:_cancelHold(k)
  if k.holdTimer then
    k.holdTimer:stop()
    k.holdTimer = nil
  end
end

--- ChordKey:start()
--- Method
--- Begin the single event tap watching every registered chord key and, while
--- one is held, the keys pressed against it.
function obj:start()
  local types = hs.eventtap.event.types
  local props = hs.eventtap.event.properties
  self._tap = hs.eventtap.new({ types.keyDown, types.keyUp }, function(e)
    -- Only react to the physical keyboard. Keystrokes Hammerspoon posts itself
    -- (the clipboard paste's Cmd+V) pass straight through, so an insert fired
    -- while the leader is still held reaches the app instead of being swallowed
    -- and misread as a chord.
    if e:getProperty(props.eventSourceStateID) ~= HID_SYSTEM_STATE then
      return false
    end

    local t = e:getType()
    local code = e:getKeyCode()

    -- A registered chord key itself: track held state, arm the hold overlay,
    -- decide tap-vs-hold on release, and swallow it entirely.
    local k = self._keys[code]
    if k then
      if t == types.keyDown then
        -- Held keys auto-repeat key-down; only the first press starts a hold.
        if not k.active then
          k.active = true
          k.used = false
          k.shown = false
          k.downTime = hs.timer.secondsSinceEpoch()
          if k.onHold and k.holdDelay then
            k.holdTimer = hs.timer.doAfter(k.holdDelay, function()
              if k.active and not k.used then
                k.shown = true
                k.onHold(k.code)
              end
            end)
          end
        end
      else -- keyUp
        self:_cancelHold(k)
        if k.shown and k.onHoldEnd then
          k.onHoldEnd(k.code)
        end
        k.shown = false
        local heldFor = hs.timer.secondsSinceEpoch() - k.downTime
        local wasUsed = k.used
        k.active = false
        if k.onTap and not wasUsed and heldFor < k.tapThreshold then
          hs.timer.doAfter(0, k.onTap)
        end
      end
      return true, {} -- swallow the chord key entirely
    end

    -- Other keys, only while some chord key is held.
    for _, held in pairs(self._keys) do
      if held.active then
        if t == types.keyDown then
          -- A real key press means this is a chord, not a cheat-sheet hold:
          -- cancel the pending overlay (and dismiss it if already shown).
          held.used = true
          self:_cancelHold(held)
          if held.shown and held.onHoldEnd then
            held.onHoldEnd(held.code)
            held.shown = false
          end
          if held.onKey then
            local fn = held.onKey(code, e:getFlags())
            if fn then
              hs.timer.doAfter(0, fn)
            end
          end
        end
        return true, {} -- swallow so nothing leaks while a chord key is held
      end
    end

    return false
  end)
  self._tap:start()
  return self
end

--- ChordKey:stop()
--- Method
--- Stop the event tap and clear all held state
function obj:stop()
  if self._tap then
    self._tap:stop()
  end
  for _, k in pairs(self._keys or {}) do
    self:_cancelHold(k)
    k.active = false
    k.shown = false
  end
  return self
end

return obj
