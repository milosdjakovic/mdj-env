-- The modifier trigger, a set of real modifiers claimed through hs.hotkey.
--
-- A modifier emits no key of its own, it is a flag stamped on somebody else's event, so nothing
-- about it can be held, measured or tapped the way a held leader is. Each binding is claimed
-- instead as one hs.hotkey on the base set plus whatever sub modifiers the binding declared.
-- hs.hotkey claims only what it binds, so a combination nobody declared reaches whatever app
-- wanted it and there is no passthrough to write, and a combination that is claimed is claimed
-- machine wide.
--
-- The base set is empty for the plain leader. A keymap row with no leader, a plain combo such as
-- Option and backtick, is a binding on the unnamed modifier leader whose base set is empty, so the
-- combo is the binding's own modifiers and nothing more. A leader of modifiers a person names, or
-- Hyper written as the four modifiers, is the same trigger handed a base set, with no edit in
-- lib/leader.lua.
--
-- This was the chord shape of lib/hyperkey.lua until phase 3, carved out with two things left
-- behind. The hold reveal, which phase 4 gives back as opt in, since holding Shift and Control is
-- ordinary typing and a sheet there would flash in use, which decisions/olm-keymap.md rejected, so
-- only a leader whose entry states a sheet runs it. And a claimed combo
-- resolves against the modifiers it was claimed on rather than against what the hardware reports
-- by the time the callback runs, since hs.hotkey fires only on exactly that combination and a
-- finger lifted a moment early must not turn a press into nothing.
--
-- The reveal is one hs.eventtap over flagsChanged and keyDown that only observes, every answer is
-- false, so nothing is swallowed or rewritten. When the modifiers become exactly the base set it
-- arms the leader's hold delay, and when that passes with the set unchanged and no key pressed it
-- asks the adapter to show the sheet. Any key, or any change of the set, takes it down. Every
-- flags event carries the true state, so the tap cannot stick the way a remembered key could, and
-- a short poll of the live modifiers runs while the sheet is up as well, since a tap can miss
-- events under secure input and the modifiers can always be asked.
--
-- A trigger is a Strategy behind the contract lib/leader.lua calls, start, bound, isActive and
-- owns. Combos are claimed at start, every binding in the order it was bound, and a binding
-- arriving after start is claimed at once.

local obj = {}

-- The only modifiers a binding may require, in the one order a combination is spelled in, so one
-- set always spells one string. fn is excluded for the reason the leader resolver gives.
local REAL_MODS = { "shift", "ctrl", "alt", "cmd" }

-- How long the sheet may outlive the modifiers when the tap missed the event that ended it.
local POLL_INTERVAL = 0.25
-- The hold delay when the leader states none and the root handed none, the engine's own.
local DEFAULT_HOLD_DELAY = 0.6

local log = hs.logger.new("Leader", "info")

--- obj.new(spec) -> trigger
---   spec.mods  the base set of real modifiers, empty or absent for a plain combo
---   spec.sealsOverLists  true when this leader hosts a list key, which the root knows once the
---              lists are laid out, so a key it resolves over an open list is the bound no op
---   spec.skipOverlap  true when this is the modifier half of a composite, so a binding asking for
---              a modifier the base set already holds is left unclaimed and counted rather than
---              warned about, since the held half still reaches it
function obj.new(spec)
  spec = spec or {}
  local baseMods = spec.mods or {}
  local baseSet = {}
  for _, m in ipairs(baseMods) do baseSet[m] = true end
  local skipOverlap = spec.skipOverlap == true
  local skipped = 0

  -- One hs.hotkey per distinct pairing of a key with a modifier set. Held in a table so a bound
  -- combination is never collected, and claimed once so a second binding on the same combination
  -- adds no second hotkey competing for it.
  local hotkeys, claimed = {}, {}
  local started = false
  -- Declared before the claims, since a claimed combo hands this trigger to the adapter with every
  -- press, which is how the adapter knows which trigger fired, see _onKey in lib/leader.lua.
  local trigger = {}

  -- The modifiers a binding is claimed on, the base set united with the binding's own. fn is not a
  -- modifier the resolver compares, but a row that declares it is claimed with it, as the binder
  -- claimed it before phase 3, so it is passed through last.
  local function comboFor(subMods)
    local need = {}
    for _, m in ipairs(baseMods) do need[m] = true end
    for _, m in ipairs(subMods or {}) do need[m] = true end
    local out = {}
    for _, m in ipairs(REAL_MODS) do
      if need[m] then out[#out + 1] = m end
    end
    if need.fn then out[#out + 1] = "fn" end
    return out
  end

  -- What the resolver is asked with when a claimed combo fires, the claimed set minus the base,
  -- since the base is the trigger and not part of what any binding asked for.
  local function flagsFor(combo)
    local flags = {}
    for _, m in ipairs(combo) do
      if not baseSet[m] then flags[m] = true end
    end
    return flags
  end

  -- The sub modifiers of a binding that the base set already holds, empty for most bindings.
  local function overlapOf(subMods)
    local overlap = {}
    for _, s in ipairs(subMods or {}) do
      if baseSet[s] then overlap[#overlap + 1] = s end
    end
    return overlap
  end

  -- A binding whose own sub modifiers overlap the base set cannot be reached, since the overlap is
  -- taken out before resolving and the plain binding on that key answers instead. The two really
  -- are one physical combination, so the only honest thing is to say it once at claim time.
  local function warnIfUnreachable(key, subMods)
    local overlap = overlapOf(subMods)
    if #overlap == 0 then return end
    log.w(string.format(
      "the %s binding asking for %s cannot be reached under this leader, %s is already part of the leader itself, so the plain %s binding answers that combination and this one never fires",
      tostring(key), table.concat(subMods, "+"), table.concat(overlap, "+"), tostring(key)))
  end

  -- Whether any binding on one combination repeats, asked of every binding the host holds, so the
  -- repeat callback is there whichever binding on the combination resolves at the press.
  local function anyRepeats(host, id)
    for _, b in ipairs(host._sequence or {}) do
      if b.repeats and tostring(b.code) .. "|" .. table.concat(comboFor(b.mods), "+") == id then return true end
    end
    return false
  end

  local function bindCombo(host, binding, combo, id, repeats)
    local flags, code = flagsFor(combo), binding.code
    -- A leader stating drivenRepeat hands a repeating handler how deep into the hold it is, 0 on
    -- the press and one more per OS autorepeat, the same argument the held path gives. Here the
    -- hotkey's own repeat callback is the schedule, so the depth counts those, reset on each press.
    local driven = host:_repeatMode() == "driven"
    local depth = 0
    local function press()
      depth = 0
      local fn = host:_onKey(code, flags, trigger)
      if fn then
        if driven then fn(0) else fn() end
      end
    end
    -- A combo no binding repeats is claimed with exactly the three arguments a plain hs.hotkey
    -- always had. The repeat callback resolves at each repeat, so it runs whichever binding answers
    -- then, and only when that binding repeats. A key is claimed by the name it was spelled with
    -- where Hammerspoon's own table knows that name, and by the code the leader resolved where it
    -- does not, since hs.hotkey reads a name against that table and the Globe key has no name there.
    local key = binding.key
    if type(key) ~= "string" or hs.keycodes.map[key:lower()] == nil then key = code end
    if repeats then
      return hs.hotkey.bind(combo, key, press, nil, function()
        local fn, rep = host:_onKey(code, flags, trigger)
        if fn and rep then
          if driven then
            depth = depth + 1
            fn(depth)
          else
            fn()
          end
        end
      end)
    end
    return hs.hotkey.bind(combo, key, press)
  end

  -- Each claim runs under its own pcall, so one combination that raises costs that combination
  -- alone, said once with its key and modifiers, and every other one is still claimed, the per row
  -- isolation the binder gave plain combos before phase 3.
  local function claim(host, binding)
    -- The modifier half of a composite leaves such a binding to the held half, which tells the two
    -- apart, so it is neither claimed nor warned about here, only counted for the composite's note.
    if skipOverlap and #overlapOf(binding.mods) > 0 then
      skipped = skipped + 1
      return
    end
    warnIfUnreachable(binding.key, binding.mods)
    local combo = comboFor(binding.mods)
    local id = tostring(binding.code) .. "|" .. table.concat(combo, "+")
    local repeats = anyRepeats(host, id)
    local held = claimed[id]
    -- Claimed already and its repeat answer unchanged, nothing to do. A binding arriving later that
    -- repeats on a combination claimed without the callback replaces that hotkey with one that has it.
    if held and (held.repeats or not repeats) then return end
    local ok, hotkey = pcall(bindCombo, host, binding, combo, id, repeats)
    if not ok then
      log.w(string.format("the plain combo %s on %s could not be claimed, %s, so it is not bound",
        tostring(binding.key), table.concat(combo, "+"), tostring(hotkey)))
      return
    end
    if held and held.hotkey and type(held.hotkey.delete) == "function" then pcall(held.hotkey.delete, held.hotkey) end
    claimed[id] = { hotkey = hotkey, repeats = repeats }
    hotkeys[#hotkeys + 1] = hotkey
  end

  -- Whether a table of modifier flags is exactly the base set, compared on the four real
  -- modifiers alone, so fn and caps lock count neither for nor against it.
  local function exactly(flags)
    flags = flags or {}
    for _, m in ipairs(REAL_MODS) do
      if (flags[m] == true) ~= (baseSet[m] == true) then return false end
    end
    return true
  end

  local function spelled(flags)
    flags = flags or {}
    local out = {}
    for _, m in ipairs(REAL_MODS) do
      if flags[m] then out[#out + 1] = m end
    end
    return table.concat(out, "+")
  end

  -- The reveal. Every handle sits in a field of the trigger, which owns the tap and both timers, and
  -- starting one stops the one before it.
  local function stopTimer(field)
    local t = trigger[field]
    if t then
      t:stop()
      trigger[field] = nil
    end
  end

  -- Takes down only a sheet this trigger put up. Alone that is every sheet the leader shows, and as
  -- the modifier half of a composite it leaves the held half's sheet alone, which a modifier pressed
  -- under F18 or the autorepeat of F18 itself would otherwise take down the moment it went up.
  local function conceal(host)
    stopTimer("_pollTimer")
    if not trigger._shown then return end
    trigger._shown = false
    host:conceal()
  end

  local function startPoll(host)
    stopTimer("_pollTimer")
    trigger._pollTimer = hs.timer.doEvery(POLL_INTERVAL, function()
      if not exactly(hs.eventtap.checkKeyboardModifiers()) then
        -- The tap missed the change that ended the hold, so the set it last saw is stale, and
        -- forgetting it lets the next press arm again even when it arrives as one event.
        trigger._lastSet = nil
        conceal(host)
      end
    end)
  end

  local function startReveal(host)
    trigger._lastSet = nil
    local function onFlags(flags)
      local now = spelled(flags)
      -- A change of fn or caps lock alone leaves the counted set as it was, which is no change.
      if now == trigger._lastSet then return end
      trigger._lastSet = now
      stopTimer("_armTimer")
      conceal(host)
      if not exactly(flags) then return end
      trigger._armTimer = hs.timer.doAfter(host._holdDelay or DEFAULT_HOLD_DELAY, function()
        trigger._armTimer = nil
        if not exactly(hs.eventtap.checkKeyboardModifiers()) then return end
        -- The adapter refuses over an open list, and over a sheet another trigger of the same
        -- leader already put up, so only a sheet this trigger put up is watched and taken down.
        local wasUp = host._revealed
        host:_reveal(nil)
        if host._revealed and not wasUp then
          trigger._shown = true
          startPoll(host)
        end
      end)
    end
    local types = hs.eventtap.event.types
    trigger._tap = hs.eventtap.new({ types.flagsChanged, types.keyDown }, function(ev)
      if ev:getType() == types.flagsChanged then
        onFlags(ev:getFlags())
      else
        stopTimer("_armTimer")
        conceal(host)
      end
      return false
    end)
    trigger._tap:start()
  end

  -- An empty base set is never held, there is nothing to hold, so a plain combo never makes a
  -- waiting action wait.
  function trigger.isActive()
    if #baseMods == 0 then return false end
    local live = hs.eventtap.checkKeyboardModifiers() or {}
    for _, m in ipairs(baseMods) do
      if not live[m] then return false end
    end
    return true
  end

  -- Whether a key down belongs to this leader. Handed an event it reads the flags the event itself
  -- carries, which is the answer for a key already in flight, since the live keyboard is read a
  -- moment later than the event and a tap asking about a chord needs what that chord held. Handed
  -- none it reads the live keyboard, as isActive does.
  function trigger.owns(ev)
    if ev == nil or type(ev.getFlags) ~= "function" then return trigger.isActive() end
    if #baseMods == 0 then return false end
    local flags = ev:getFlags() or {}
    for _, m in ipairs(baseMods) do
      if not flags[m] then return false end
    end
    return true
  end

  -- A leader hosting a list key seals over an open list, so a key it resolves there is the bound
  -- no op and nothing global fires beneath the list, the rule a held leader has always had.
  trigger.sealsOverLists = spec.sealsOverLists == true

  function trigger.bound(host, binding)
    if started then claim(host, binding) end
  end

  -- How many bindings the modifier half of a composite left to the held half, which the composite
  -- says once at start. Always 0 on a leader of modifiers alone.
  function trigger.skipped()
    return skipped
  end

  function trigger.start(host)
    started = true
    for _, binding in ipairs(host._sequence or {}) do claim(host, binding) end
    -- Only a leader with a sheet and something to hold watches the modifiers, since a watcher that
    -- reveals nothing is a tap for nothing.
    if #baseMods > 0 and host:_reveals() and not trigger._tap then startReveal(host) end
    return true
  end

  return trigger
end

return obj
