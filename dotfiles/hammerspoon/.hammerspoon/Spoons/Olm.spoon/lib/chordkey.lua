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
--- A binding may also say that it repeats while its key stays down, and the key's
--- repeatMode decides how. A repeating handler is called with how deep into the hold it is,
--- 0 on the press and 1, 2, 3 on the repeats after it, since the engine is the only layer
--- that knows and an action may want to grow with the hold rather than only run again.
---
--- "system" leans on the OS autorepeat events themselves, so the feel matches every other
--- held key on the machine. "driven" ignores those events and schedules the repeats itself,
--- on the machine's own two beats, its delay until repeat and then its repeat interval held
--- steady. The timing is therefore the same either way, and what the second mode buys is that
--- the engine knows how deep into the hold each repeat is and can tell the handler, which an
--- OS autorepeat event gives no way to know.
---
--- A held key is remembered rather than queried, since a leader is a plain key and nothing can
--- be asked whether one is down, so the whole model rests on seeing a key-up for every key-down.
--- That stream is not reliable. macOS secure input blanks every tap on the machine while it is
--- on, the system disables a tap whose callback overruns its timeout, and a consumer callback
--- that throws abandons the rest of the callback. A leader left held by a lost key-up then
--- swallows every later keystroke into the chord path, so ordinary typing fires actions and
--- nothing in the stream can put it right. So a staleness watchdog rides on the autorepeat of
--- the held key itself, the one piece of positive evidence there is, and releases a leader that
--- has gone silent for longer than a real hold ever could. See _armStale and _release.
---
--- This is only the MECHANISM. The domain policy -- which keys map to what, and
--- how sub-modifiers resolve -- lives in the callers, which register their key(s)
--- here via addKey() and supply an onKey() lookup.
--- Because every key shares ONE eventtap, N leaders cost one tap, not N.
---
--- Everything lives inside Hammerspoon, so it adds no background process.
---
--- This is the olm side copy of ChordKey, moved into the core as lib/chordkey.lua in phase
--- five of the build plan. It is a faithful copy, the colon methods and the per key options
--- are unchanged, so assigning it to the ChordKey spoon global is a drop in. The original
--- this was copied from lived at Spoons/ChordKey.spoon.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "ChordKey"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

obj._tap = nil
obj._keys = nil        -- keyCode -> entry (config + runtime state)
obj._deferred = nil    -- pending handler timers, held until they fire, see _defer

-- Real hardware key events carry this event-source state id
-- (kCGEventSourceStateHIDSystemState). Keystrokes Hammerspoon posts itself, like
-- a consumer's synthesized paste (Cmd+V), carry a private id instead, so this
-- tells the two apart. See start(), which ignores everything that is not physical.
local HID_SYSTEM_STATE = 1

-- The one thing this engine says out loud, and only when the staleness watchdog releases a
-- leader whose key-up never arrived, which is a fault worth a line rather than a silence. It
-- is guarded because the unit cases load this file into an environment carrying a fake hs
-- with no logger in it, the same guard and the same reason as lib/nav.lua and lib/surface.lua.
local log = nil
if hs and hs.logger then
  log = hs.logger.new("ChordKey", "info")
end

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
-- How a binding that asks to repeat keeps firing while its key stays down.
--
-- "system" lets the OS autorepeat drive it, so a held key runs at whatever initial delay
-- and rate the person already set for every other key on the machine. That is the right
-- answer for stepping through a list, where the feel should match the arrow keys exactly.
--
-- "driven" ignores those OS events and schedules its own on the same two beats, the machine's
-- delay until repeat and then its repeat interval. The timing is deliberately identical, so
-- what it buys is not a different rate but a known depth, since the engine counts its own
-- repeats and an OS autorepeat event carries no count. A window nudge wants that, because a
-- press placing a window by eye and a repeat crossing a screen are not the same distance.
--
-- Per key rather than global, because the two leaders on this keyboard want different
-- answers, and "system" is the default so a caller that says nothing keeps what it had.
obj._repeatMode = "system"
-- The timing of a driven repeat, which is two numbers, and both are deliberately absent.
--
-- `delay` is the wait before the FIRST repeat and `interval` the wait between the repeats
-- after it, exactly the pair macOS itself calls Delay Until Repeat and Key Repeat. Absent
-- means ask the machine, so a held leader key waits the same beat and then runs at the same
-- steady rate as a held key in any text field, and a person who moves either slider moves
-- this with it. Naming one here overrides the machine for that key alone.
--
-- The long first beat is what keeps one deliberate press to one press. The steady rate after
-- it is the whole of the rest. There is no ramp, since a rate that keeps changing under a
-- held finger is a rate you cannot aim with, and it is not this engine's place to invent one
-- the platform did not.
obj._repeatTiming = {}

--- ChordKey:init()
--- Method
--- Initialize the spoon
function obj:init()
  self._keys = {}
  self._deferred = {}
  return self
end

--- ChordKey:configure(opts)
--- Method
--- Set the defaults inherited by keys registered without their own value.
--- opts.holdDelay    - seconds held (nothing else pressed) before onHold fires
--- opts.tapThreshold - seconds under which a bare press/release counts as a tap
--- opts.passthrough  - default for whether unbound combos leak downstream (bool)
--- opts.repeatMode   - default for how a repeating binding is driven, "system" or "driven"
--- opts.repeatTiming - default repeat timing, { delay, interval }, where an absent one of
---                     either means the machine's own setting
function obj:configure(opts)
  opts = opts or {}
  if opts.holdDelay ~= nil then self._holdDelay = opts.holdDelay end
  if opts.tapThreshold ~= nil then self._tapThreshold = opts.tapThreshold end
  if opts.passthrough ~= nil then self._passthrough = opts.passthrough end
  if opts.repeatMode ~= nil then self._repeatMode = opts.repeatMode end
  if opts.repeatTiming ~= nil then self._repeatTiming = opts.repeatTiming end
  return self
end

--- ChordKey:addKey(keyCode, opts)
--- Method
--- Register a chord key by its (remapped) virtual keycode. opts:
---   holdDelay    - override the default hold delay for this key
---   tapThreshold - override the default tap threshold for this key
---   passthrough  - override whether this key's unbound combos leak downstream
---   repeatMode   - override how this key's repeating bindings are driven
---   repeatTiming - override the repeat timing used by "driven"
---   onTap        - function() on a quick tap with no other key (optional; omit
---                  for keys with no tap fallback, e.g. window leaders)
---   onHold       - function(keyCode) once the hold passes holdDelay (optional)
---   onHoldEnd    - function(keyCode) when a shown hold ends (release or key)
---   onKey        - function(pressedKeyCode, flags) -> handler|nil, repeats; the
---                  returned handler (if any) is dispatched when a key is pressed
---                  while this chord key is held, and a true second value says that
---                  handler keeps firing while the key stays down. The handler is called
---                  with the hold depth, 0 on the press and counting up per repeat. This is
---                  where domain lookup and sub-modifier resolution live.
function obj:addKey(keyCode, opts)
  opts = opts or {}
  self._keys[keyCode] = {
    code = keyCode,
    holdDelay = opts.holdDelay or self._holdDelay,
    tapThreshold = opts.tapThreshold or self._tapThreshold,
    passthrough = opts.passthrough ~= nil and opts.passthrough or self._passthrough,
    repeatMode = opts.repeatMode or self._repeatMode,
    repeatTiming = opts.repeatTiming or self._repeatTiming,
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
    repeatTimer = nil,       -- the pending tick of a driven repeat, see _startRepeat
    repeatCode = nil,        -- which key that repeat belongs to
    repeatFired = 0,         -- how many repeats it has already sent
    staleTimer = nil,        -- the pending staleness watchdog, see _armStale
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

--- ChordKey:_defer(delay, fn)
--- Method
--- Run a consumer's handler on a later tick, holding the timer until it fires.
---
--- Both callers hand control back to the tap immediately and let the handler run after,
--- a tap so the key-up is fully processed first and a chord so an overlay teardown can
--- settle. Holding the timer is not optional. A Hammerspoon timer is userdata whose
--- finalizer stops it, so one nothing refers to can be collected inside the wait and the
--- handler then never runs at all, which reads as a keypress the machine ignored.
---
--- Each handler takes its own key and releases only that key, deliberately. A fast
--- sequence under one held leader queues two handlers within the settle window, and a
--- single slot would let the second silently discard the first.
function obj:_defer(delay, fn)
  local slot = {}
  self._deferred[slot] = hs.timer.doAfter(delay, function()
    self._deferred[slot] = nil
    fn()
  end)
end

--- The wait before the next repeat, given how many have already gone out.
---
--- The first waits the delay until repeat and every one after it the repeat interval, the two
--- separate beats a held key has always had on this platform, read off the machine when the
--- timing table names neither. See _repeatTiming.
local function repeatDelay(timing, fired)
  timing = timing or {}
  if fired == 0 then
    return timing.delay or hs.eventtap.keyRepeatDelay()
  end
  return timing.interval or hs.eventtap.keyRepeatInterval()
end

--- ChordKey:_stopRepeat(k)
--- Method
--- End whatever driven repeat this chord key is running. Clearing the code as well as
--- the timer is what makes a tick already in flight a no-op, since the tick checks it.
function obj:_stopRepeat(k)
  if k.repeatTimer then
    k.repeatTimer:stop()
  end
  k.repeatTimer = nil
  k.repeatCode = nil
  k.repeatFired = 0
end

--- ChordKey:_startRepeat(k, code, fn)
--- Method
--- Keep firing a bound handler while its key stays down, on this engine's own schedule rather
--- than on the OS autorepeat's events.
---
--- Each tick schedules the next only after the handler has returned, rather than a repeating
--- timer at a fixed period. A window action is an accessibility round trip and a slow app can
--- take longer than the interval, so a repeating timer would queue ticks behind each other and
--- then fire them in a burst once the app caught up. Chaining makes a slow app simply repeat
--- slower, which is the graceful failure.
---
--- One repeat per chord key at a time. Pressing a second bound key under the same held leader
--- takes the repeat over, the same way typing another letter takes over the OS autorepeat, and
--- releasing the first key then finds it is no longer the one repeating and leaves the second
--- alone.
function obj:_startRepeat(k, code, fn)
  self:_stopRepeat(k)
  k.repeatCode = code
  k.repeatFired = 0
  local timing = k.repeatTiming
  local function tick()
    -- The leader or the key itself may have come up while this tick was waiting.
    if not k.active or k.repeatCode ~= code then return end
    -- The depth counts the press as 0, so the first repeat is 1. An action that grows with
    -- the hold reads this, and every action that does not simply ignores an extra argument.
    fn(k.repeatFired + 1)
    k.repeatFired = k.repeatFired + 1
    k.repeatTimer = hs.timer.doAfter(repeatDelay(timing, k.repeatFired), tick)
  end
  k.repeatTimer = hs.timer.doAfter(repeatDelay(timing, 0), tick)
end

--- The seconds of silence from a held leader after which it is no longer believed to be held.
---
--- A physically held key autorepeats its own key-down for as long as the finger stays on it,
--- and those repeats already arrive at this tap, so the largest gap a genuine hold can produce
--- is the machine's delay until the first repeat. Twice that plus a beat is the window, read
--- off the machine rather than written down here, so a person who moves that slider moves this
--- with it. A repeat is the only positive evidence available either way, since a leader is a
--- plain key rather than a modifier and nothing can be asked whether it is down.
---
--- The cap is what makes a machine with key repeat switched off degrade safely instead of
--- wrongly. Such a machine reports an enormous delay, which alone would arm a timer that never
--- fires and quietly give the recovery up, and thirty seconds is past any deliberate hold while
--- still being a bounded wait rather than none at all.
local function staleWindow()
  local delay = hs.eventtap.keyRepeatDelay and hs.eventtap.keyRepeatDelay() or 0.5
  return math.min(30, delay * 2 + 0.5)
end

--- ChordKey:_cancelStale(k)
--- Method
--- Drop this key's staleness window, which a real release and a stop both do.
function obj:_cancelStale(k)
  if k.staleTimer then
    k.staleTimer:stop()
    k.staleTimer = nil
  end
end

--- ChordKey:_armStale(k)
--- Method
--- Push this key's staleness window out, because its key-down just proved it is still held.
---
--- Losing a key-up is not hypothetical and it has three separate causes, none of which this
--- engine can prevent. The tap is blind for as long as macOS secure input is on, which any app
--- turns on by focusing a password field. The system disables a tap outright when its callback
--- overruns a timeout, and this callback posts synthesized events and tears a canvas down. And
--- a consumer callback that throws abandons the rest of the callback.
---
--- Any one of those drops the single event that clears `active`, and the cost of that is out of
--- all proportion to the cause, because a leader left active swallows every later keystroke into
--- the chord path. Ordinary typing then fires actions, with nothing in the event stream able to
--- put it right, and the only cure was pressing the leader again, which a person had to already
--- know. Believing a remembered flag over the evidence was the actual defect. This asks instead.
function obj:_armStale(k)
  self:_cancelStale(k)
  local window = staleWindow()
  k.staleTimer = hs.timer.doAfter(window, function()
    k.staleTimer = nil
    if not k.active then return end
    if log then
      log.w("leader " .. tostring(k.code) .. " saw no key-down for " .. tostring(window)
        .. "s while still held, so its key-up was lost, releasing it")
    end
    self:_release(k, { stale = true })
  end)
end

--- ChordKey:_release(k, opts)
--- Method
--- End a hold and put the key back to rest. The real key-up runs this and so does the staleness
--- watchdog above when the real key-up never came, which is exactly why it is one method rather
--- than a branch inside the tap. A recovery that reset only part of what a release resets would
--- leave the passthrough's synthesized leader held down across the whole machine, or a cheat
--- sheet on screen with nothing left that could ever take it down.
---
--- The order here is deliberate and it is half the fix. Everything this engine owns is read and
--- then cleared BEFORE any consumer callback runs, because onHoldEnd tears a canvas down while
--- still on the event tap thread and the reset used to sit underneath that call. A throw in the
--- teardown, or the system disabling the tap for overrunning inside it, left `active` standing
--- with the key already physically up. Nothing a consumer does can strand the engine now.
---
--- opts.stale says this is the watchdog's release rather than a real key-up, which suppresses
--- onTap. A tap is a deliberate quick press and release, so a hold nobody was seen to release is
--- by definition neither, and toggling Caps Lock off the back of a recovery would be inventing a
--- keystroke the person never made. The elapsed guard below already excludes it at any realistic
--- timing, and this states it rather than leaning on that.
function obj:_release(k, opts)
  opts = opts or {}
  self:_cancelHold(k)
  self:_stopRepeat(k)
  self:_cancelStale(k)

  local wasShown = k.shown
  local wasUsed = k.used
  local heldFor = hs.timer.secondsSinceEpoch() - k.downTime
  k.shown = false
  k.active = false
  if k.passthrough then self:_endPassthrough(k) end

  if not opts.stale and k.onTap and not wasUsed and heldFor < k.tapThreshold then
    self:_defer(0, k.onTap)
  end
  if wasShown and k.onHoldEnd then
    k.onHoldEnd(k.code)
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
        -- Every key-down for this leader refreshes the staleness window, and the OS autorepeats
        -- of a held key are deliberately included rather than filtered out here, since they are
        -- the only thing that keeps saying the finger is still down. See _armStale.
        self:_armStale(k)
      else -- keyUp
        -- The leader going up ends everything held under it, the repeat and the staleness
        -- window included, and the watchdog reaches the same place when this event never
        -- arrives at all. See _release.
        self:_release(k)
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
          -- onKey answers the handler plus whether it repeats; keep both, since an `and`
          -- guard would truncate the pair to one value.
          local fn, repeats
          if held.onKey then fn, repeats = held.onKey(code, e:getFlags()) end
          if fn then
            self:_defer(wasShown and self._overlaySettle or 0, function() fn(0) end)
            -- Under "driven" the repeat is this engine's own schedule, armed here on the
            -- first press. Under "system" there is nothing to arm, the OS autorepeat below
            -- is the schedule.
            if repeats and held.repeatMode == "driven" then
              self:_startRepeat(held, code, fn)
            end
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
          -- Under "driven" this engine is already firing on a schedule of its own, so the OS
          -- repeat is swallowed and never acted on, since acting on both would fire twice
          -- per tick.
          if fn and repeats and held.repeatMode ~= "driven" then fn() end
          return true, {}
        end
        -- The finger coming off the repeating key ends its repeat, and only its own. A
        -- second bound key pressed under the same leader has already taken the repeat over,
        -- so the first one's release finds it is no longer the one repeating and leaves the
        -- newer one running.
        if t == types.keyUp and held.repeatCode == code then
          self:_stopRepeat(held)
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
    self:_stopRepeat(k)
    self:_cancelStale(k)
    k.active = false
    k.shown = false
    k.passthroughDown = false
    k.passedKeys = {}
  end
  return self
end

return obj
