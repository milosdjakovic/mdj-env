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
--- With passthrough on (a configure default, overridable per key), a held key
--- that resolves to no handler no longer swallows the combo but leaks it to other
--- apps as leader+key. Since the leader's own key-down was already swallowed, the
--- engine synthesizes it once on the first unbound press, synthesizes the pressed
--- key with its live modifiers, and emits the leader key-up on release. This lets
--- an eventtap-based app downstream (a shortcut recorder, Raycast, Karabiner) bind
--- combos the domain does not claim, while bound combos still run and swallow.
---
--- This is only the MECHANISM. The domain policy -- which keys map to what, and
--- how sub-modifiers resolve -- lives in the callers, which register their key(s)
--- here via addKey() and supply an onKey() lookup.
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
-- a consumer's synthesized paste (Cmd+V), carry a private id instead, so this
-- tells the two apart. See start(), which ignores everything that is not physical.
local HID_SYSTEM_STATE = 1

-- The modifier universe, most to least common. Used to turn a live flags table
-- (from getFlags()) into the list form newKeyEvent wants, so a passed-through key
-- keeps whatever real modifiers were held with it (fn included, as macOS stamps
-- it onto arrow keys).
local MODS = { "cmd", "alt", "ctrl", "shift", "fn" }
local function modsList(flags)
  local list = {}
  for _, m in ipairs(MODS) do
    if flags[m] then list[#list + 1] = m end
  end
  return list
end

-- Defaults applied to any key that does not override them (see configure()).
obj._holdDelay = 0.6
obj._tapThreshold = 0.2
-- Seconds to let a shown hold overlay tear down before the chorded action runs.
-- Tearing the overlay canvas down and presenting a native panel (hs.chooser) in the
-- same runloop tick races the panel's presentation, so it silently fails to show. A
-- brief settle fixes it; the quick chord path, where no overlay was shown, stays
-- immediate so nothing pays this cost.
obj._overlaySettle = 0.05
-- Whether an unbound combo leaks downstream instead of being swallowed. Off by
-- default so a key that opts out (or a caller that never configures it) keeps the
-- original swallow-everything behaviour.
obj._passthrough = false

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
--- opts.passthrough  - default for whether unbound combos leak downstream (bool)
function obj:configure(opts)
  opts = opts or {}
  if opts.holdDelay ~= nil then self._holdDelay = opts.holdDelay end
  if opts.tapThreshold ~= nil then self._tapThreshold = opts.tapThreshold end
  if opts.passthrough ~= nil then self._passthrough = opts.passthrough end
  return self
end

--- ChordKey:addKey(keyCode, opts)
--- Method
--- Register a chord key by its (remapped) virtual keycode. opts:
---   holdDelay    - override the default hold delay for this key
---   tapThreshold - override the default tap threshold for this key
---   passthrough  - override whether this key's unbound combos leak downstream
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
    passthrough = opts.passthrough ~= nil and opts.passthrough or self._passthrough,
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
    passthroughDown = false, -- have we synthesized this leader's key-down?
    passedKeys = {},         -- codes leaked downstream this hold, pending their up
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

--- ChordKey:_passDown(k)
--- Method
--- Synthesize this leader's key-down for downstream apps, once per hold. The real
--- key-down was swallowed, so an app cannot see the leader is held until we post
--- one. Posting the leader before the pressed key keeps the order the app expects.
function obj:_passDown(k)
  if k.passthroughDown then return end
  k.passthroughDown = true
  hs.eventtap.event.newKeyEvent({}, k.code, true):post()
end

--- ChordKey:_endPassthrough(k)
--- Method
--- Close out a hold's passthrough: emit an up for any key still held downstream
--- (so nothing sticks), then the leader's own key-up if we ever synthesized its
--- down. Keys first, leader last, mirroring the order they went out.
function obj:_endPassthrough(k)
  for code in pairs(k.passedKeys) do
    hs.eventtap.event.newKeyEvent({}, code, false):post()
  end
  k.passedKeys = {}
  if k.passthroughDown then
    k.passthroughDown = false
    hs.eventtap.event.newKeyEvent({}, k.code, false):post()
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
    -- (a consumer's synthesized paste, Cmd+V) pass straight through, so an insert fired
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
          k.passthroughDown = false
          k.passedKeys = {}
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
        if k.passthrough then self:_endPassthrough(k) end
      end
      return true, {} -- swallow the chord key entirely
    end

    -- Other keys, only while some chord key is held.
    for _, held in pairs(self._keys) do
      if held.active then
        -- A held key auto-repeats its key-down, but a chord is one discrete
        -- press, so dispatch only on the first. Firing on each repeat re-runs
        -- the handler, which for a toggle consumer opens and closes it
        -- over and over while the key stays down. The repeat is still swallowed
        -- below so nothing leaks. This mirrors the first-press-only guard the
        -- chord key itself uses above.
        local repeated = e:getProperty(props.keyboardEventAutorepeat) ~= 0
        if t == types.keyDown and not repeated then
          -- A real key press means this is a chord, not a cheat-sheet hold:
          -- cancel the pending overlay (and dismiss it if already shown).
          held.used = true
          self:_cancelHold(held)
          -- Whether the hold overlay was up. When it was, its teardown needs a beat
          -- to settle before the action runs, or a native panel the action opens
          -- races the teardown and never shows (see _overlaySettle).
          local wasShown = held.shown
          if held.shown and held.onHoldEnd then
            held.onHoldEnd(held.code)
            held.shown = false
          end
          local fn = held.onKey and held.onKey(code, e:getFlags())
          if fn then
            hs.timer.doAfter(wasShown and self._overlaySettle or 0, fn)
            return true, {} -- bound: run the handler and swallow the key
          end
          -- Unbound. With passthrough on, leak the combo downstream so another
          -- app can bind it: synthesize the leader's key-down (once), then a copy
          -- of this key with its live modifiers, and swallow the real one so the
          -- ordering is ours. The matching up goes out when the key is released.
          if held.passthrough then
            self:_passDown(held)
            held.passedKeys[code] = true
            hs.eventtap.event.newKeyEvent(modsList(e:getFlags()), code, true):post()
          end
          return true, {}
        end
        -- Autorepeat of a held key. Swallowed by default so a toggle fires once
        -- (the guard above), but a binding may opt into repeat, so re-run only
        -- those. The initial delay and repeat rate are the OS autorepeat's own
        -- (System Settings > Keyboard), so a held nav key like a chooser's j/k
        -- scrolls exactly like the arrow keys. Any hold overlay was already torn
        -- down on the first press, so dispatch directly with no settle. onKey
        -- returns the handler plus its repeats flag; keep both (an `and` guard
        -- would truncate the pair to one value).
        if t == types.keyDown and repeated then
          local fn, repeats
          if held.onKey then fn, repeats = held.onKey(code, e:getFlags()) end
          if fn and repeats then fn() end
          return true, {}
        end
        -- The release of a key we leaked downstream: send the matching synthetic
        -- up so the app never sees it stuck down. Repeats stay swallowed.
        if held.passthrough and held.passedKeys[code] then
          if t == types.keyUp then
            held.passedKeys[code] = nil
            hs.eventtap.event.newKeyEvent(modsList(e:getFlags()), code, false):post()
          end
          return true, {}
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
    k.passthroughDown = false
    k.passedKeys = {}
  end
  return self
end

return obj
