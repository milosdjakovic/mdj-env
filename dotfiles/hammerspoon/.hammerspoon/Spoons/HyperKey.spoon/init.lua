--- === HyperKey ===
---
--- Turn a single physical key into a "Hyper" trigger with a tap fallback.
---
--- The key must emit normal key-down/key-up events (e.g. F18, which Caps Lock
--- is remapped to via hidutil — see src/setup-capslock-hyper.sh). A real
--- modifier or a toggle key like raw Caps Lock will not work: modifiers stamp
--- their flag onto every keystroke, and Caps Lock emits no usable up/down.
---
--- While the key is held, matching keys are dispatched to their handlers and
--- swallowed (so nothing leaks through). A quick tap with no other key runs the
--- optional onTap callback (used here to toggle real Caps Lock). Everything
--- lives inside Hammerspoon, so it adds no background process or memory.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "HyperKey"
obj.version = "3.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

obj._tap = nil
obj._active = false
obj._used = false     -- was another key pressed during this hold?
obj._downTime = 0
obj._bindings = nil   -- keycode -> function
obj._holdTimer = nil
obj._holdShown = false

-- F18 keycode (Caps Lock is remapped to F18 at the HID level)
obj._keyCode = 79
-- Max hold duration (seconds) that still counts as a tap
obj._tapThreshold = 0.2
-- Optional callback fired on a quick tap with no other key
obj._onTap = nil
-- Optional: fire _onHold after holding this long with no other key pressed
obj._holdDelay = nil
obj._onHold = nil    -- fired once when the hold passes _holdDelay
obj._onHoldEnd = nil -- fired when a shown hold ends (release or key press)

--- HyperKey:init()
--- Method
--- Initialize the spoon
function obj:init()
  self._bindings = {}
  return self
end

--- HyperKey:configure(opts)
--- Method
--- opts.keyCode      - keycode of the Hyper key (default 79, F18)
--- opts.tapThreshold - seconds below which a hold counts as a tap (default 0.2)
--- opts.onTap        - function to run on a quick tap with no other key
--- opts.holdDelay    - seconds to hold (no other key) before onHold fires
--- opts.onHold       - function to run once the hold passes holdDelay
--- opts.onHoldEnd    - function to run when a shown hold ends
function obj:configure(opts)
  opts = opts or {}
  self._keyCode = opts.keyCode or self._keyCode
  self._tapThreshold = opts.tapThreshold or self._tapThreshold
  self._onTap = opts.onTap or self._onTap
  self._holdDelay = opts.holdDelay or self._holdDelay
  self._onHold = opts.onHold or self._onHold
  self._onHoldEnd = opts.onHoldEnd or self._onHoldEnd
  return self
end

--- HyperKey:bind(key, fn)
--- Method
--- Register a handler that fires when the Hyper key is held and `key` is pressed
function obj:bind(key, fn)
  local name = type(key) == "string" and key:lower() or key
  local code = hs.keycodes.map[name]
  if code then
    self._bindings[code] = fn
  else
    print("HyperKey: unknown key '" .. tostring(key) .. "'")
  end
  return self
end

--- HyperKey:start()
--- Method
--- Begin watching for the Hyper key and its bound keys
function obj:start()
  local types = hs.eventtap.event.types
  self._tap = hs.eventtap.new({ types.keyDown, types.keyUp }, function(e)
    local t = e:getType()
    local code = e:getKeyCode()

    -- The Hyper key itself
    if code == self._keyCode then
      if t == types.keyDown then
        -- Held keys auto-repeat key-down; only the first press starts a hold
        if not self._active then
          self._active = true
          self._used = false
          self._holdShown = false
          self._downTime = hs.timer.secondsSinceEpoch()
          -- Arm the hold overlay: fires only if still held and unused
          if self._onHold and self._holdDelay then
            self._holdTimer = hs.timer.doAfter(self._holdDelay, function()
              if self._active and not self._used then
                self._holdShown = true
                self._onHold()
              end
            end)
          end
        end
      elseif t == types.keyUp then
        self:_cancelHold()
        if self._holdShown and self._onHoldEnd then
          self._onHoldEnd()
        end
        self._holdShown = false
        local heldFor = hs.timer.secondsSinceEpoch() - self._downTime
        local wasUsed = self._used
        self._active = false
        if not wasUsed and heldFor < self._tapThreshold and self._onTap then
          hs.timer.doAfter(0, self._onTap)
        end
      end
      return true, {} -- swallow the Hyper key entirely
    end

    -- Other keys, only while the Hyper key is held
    if self._active then
      if t == types.keyDown then
        self._used = true
        self:_cancelHold()
        if self._holdShown and self._onHoldEnd then
          self._onHoldEnd()
          self._holdShown = false
        end
        local fn = self._bindings[code]
        if fn then
          hs.timer.doAfter(0, fn)
        end
      end
      return true, {} -- swallow so nothing leaks while Hyper is held
    end

    return false
  end)
  self._tap:start()
  return self
end

--- HyperKey:_cancelHold()
--- Method
--- Cancel any pending hold-overlay timer
function obj:_cancelHold()
  if self._holdTimer then
    self._holdTimer:stop()
    self._holdTimer = nil
  end
end

--- HyperKey:stop()
--- Method
--- Stop watching
function obj:stop()
  if self._tap then
    self._tap:stop()
  end
  self:_cancelHold()
  self._active = false
  self._holdShown = false
  return self
end

return obj
