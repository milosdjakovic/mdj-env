-- The held trigger, one physical key held down as a leader.
--
-- The key is one on the allow list, Caps Lock, a right modifier or F13 to F20, heard through a
-- function key that belongs to no app, the key itself for F13 to F20 and the one lib/keyremap.lua
-- remapped it to at the HID level for the rest, so it emits a clean key down and key up that can be
-- held, measured, tapped and swallowed. The shared engine, lib/chordkey.lua, does all of that for every
-- held leader through one event tap, and this file only registers the key there with the options
-- the leader's policy decided. It was the leader shape of lib/hyperkey.lua and the whole of the
-- registration in lib/windowleader.lua until phase 3 of the keymap plan.
--
-- A trigger is a Strategy behind the contract lib/leader.lua calls, start, bound, isActive and
-- owns. This one needs nothing at bind time, since the engine looks a pressed key up in the live
-- binding table on every press, so bound does nothing and a key bound after start still works.
--
-- It is pure Lua apart from the engine it is handed, so a plain test can drive it with a stub.

local obj = {}

--- obj.new(spec) -> trigger
---   spec.chord    the shared ChordKey engine the key registers into
---   spec.keyCode  the keycode of the function key the engine listens on
---   spec.key      the physical key the leader names, which decides what a tap does
function obj.new(spec)
  spec = spec or {}
  local chord, keyCode = spec.chord, spec.keyCode
  local trigger = {}

  -- THE SEAM. A quick tap of the key alone does what the key does alone, which for Caps Lock is to
  -- toggle it, since the remap otherwise takes that away. No other key on the allow list does
  -- anything alone that is worth keeping, so a tap on those is nothing. This is the one place
  -- the leader adapter names Caps Lock.
  local tap = nil
  if spec.key == "capsLock" then tap = function() hs.hid.capslock.toggle() end end

  -- Whether the key is down right now, asked of the engine, since a leader is a plain key and
  -- only the engine that swallows it knows. A synthetic keystroke waits on this before it posts.
  function trigger.isActive()
    return chord ~= nil and keyCode ~= nil and chord:isActive(keyCode)
  end

  -- A key down belongs to this leader when it is the leader key itself or arrives while the leader
  -- is held. The first covers the press that starts a hold, the second every key chorded under it.
  function trigger.owns(ev)
    if keyCode ~= nil and ev:getKeyCode() == keyCode then return true end
    return trigger.isActive()
  end

  function trigger.bound() end

  -- A held key is a leader that owns every key while it is down, so an open list seals it, the one
  -- rule over open lists in lib/leader.lua. A trigger claiming real modifiers says nothing, since a
  -- combination of real modifiers is the app's own key and is never swallowed for a list.
  trigger.sealsOverLists = true

  -- Registers the key with everything the leader decided. Answers false and a reason when there is
  -- nothing to register into, which the leader says once.
  function trigger.start(host)
    if not chord then return false, "no ChordKey engine was handed over" end
    if keyCode == nil then return false, "its function key resolved to no keycode" end
    chord:addKey(keyCode, {
      tapThreshold = host._tapThreshold,
      holdDelay = host._holdDelay,
      -- Nil leaves the engine's own default, system, so a leader whose policy says nothing rides
      -- the OS autorepeat exactly as Hyper always did.
      repeatMode = host:_repeatMode(),
      onTap = tap,
      -- Only a leader with a sheet arms a hold, since a reveal that shows nothing is a timer for
      -- nothing.
      onHold = host:_reveals() and function(code) host:_reveal(code) end or nil,
      onHoldEnd = host:_reveals() and function() host:conceal() end or nil,
      -- The trigger hands itself over with every key, so a leader listening on more than one
      -- trigger seals by the one that fired, see _onKey in lib/leader.lua.
      onKey = function(code, flags) return host:_onKey(code, flags, trigger) end,
    })
    return true
  end

  return trigger
end

return obj
