-- The modifier trigger, a set of real modifiers claimed through hs.hotkey.
--
-- A modifier emits no key of its own, it is a flag stamped on somebody else's event, so nothing
-- about it can be held, measured or tapped the way a held leader is. Each binding is claimed
-- instead as one hs.hotkey on the base set plus whatever sub modifiers the binding declared.
-- hs.hotkey claims only what it binds, so a combination nobody declared reaches whatever app
-- wanted it and there is no passthrough to write, and a combination that is claimed is claimed
-- machine wide.
--
-- The base set may be empty, and today it always is. A keymap row with no leader, a plain combo
-- such as Option and backtick, is a binding on the unnamed modifier leader whose base set is
-- empty, so the combo is the binding's own modifiers and nothing more. A person naming a set of
-- modifiers as a leader of their own, phase 5 of the keymap plan, is the same trigger handed a
-- base set, with no edit here and none in lib/leader.lua.
--
-- This was the chord shape of lib/hyperkey.lua until phase 3, carved out with two things left
-- behind. The hold reveal is gone, since holding Shift and Control is ordinary typing and a
-- sheet there would flash in use, which decisions/olm-keymap.md rejected. And a claimed combo
-- resolves against the modifiers it was claimed on rather than against what the hardware reports
-- by the time the callback runs, since hs.hotkey fires only on exactly that combination and a
-- finger lifted a moment early must not turn a press into nothing.
--
-- A trigger is a Strategy behind the contract lib/leader.lua calls, start, bound, isActive and
-- owns. Combos are claimed at start, every binding in the order it was bound, and a binding
-- arriving after start is claimed at once.

local obj = {}

-- The only modifiers a binding may require, in the one order a combination is spelled in, so one
-- set always spells one string. fn is excluded for the reason the leader resolver gives.
local REAL_MODS = { "shift", "ctrl", "alt", "cmd" }

local log = hs.logger.new("Leader", "info")

--- obj.new(spec) -> trigger
---   spec.mods  the base set of real modifiers, empty or absent for a plain combo
function obj.new(spec)
  spec = spec or {}
  local baseMods = spec.mods or {}
  local baseSet = {}
  for _, m in ipairs(baseMods) do baseSet[m] = true end

  -- One hs.hotkey per distinct pairing of a key with a modifier set. Held in a table so a bound
  -- combination is never collected, and claimed once so a second binding on the same combination
  -- adds no second hotkey competing for it.
  local hotkeys, claimed = {}, {}
  local started = false

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

  -- A binding whose own sub modifiers overlap the base set cannot be reached, since the overlap is
  -- taken out before resolving and the plain binding on that key answers instead. The two really
  -- are one physical combination, so the only honest thing is to say it once at claim time.
  local function warnIfUnreachable(key, subMods)
    if not subMods or #subMods == 0 then return end
    local overlap = {}
    for _, s in ipairs(subMods) do
      if baseSet[s] then overlap[#overlap + 1] = s end
    end
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
    local function press()
      local fn = host:_onKey(code, flags)
      if fn then fn() end
    end
    -- A combo no binding repeats is claimed with exactly the three arguments a plain hs.hotkey
    -- always had. The repeat callback resolves at each repeat, so it runs whichever binding answers
    -- then, and only when that binding repeats.
    if repeats then
      return hs.hotkey.bind(combo, binding.key, press, nil, function()
        local fn, rep = host:_onKey(code, flags)
        if fn and rep then fn() end
      end)
    end
    return hs.hotkey.bind(combo, binding.key, press)
  end

  -- Each claim runs under its own pcall, so one combination that raises costs that combination
  -- alone, said once with its key and modifiers, and every other one is still claimed, the per row
  -- isolation the binder gave plain combos before phase 3.
  local function claim(host, binding)
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

  local trigger = {}

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

  function trigger.owns() return trigger.isActive() end

  function trigger.bound(host, binding)
    if started then claim(host, binding) end
  end

  function trigger.start(host)
    started = true
    for _, binding in ipairs(host._sequence or {}) do claim(host, binding) end
    return true
  end

  return trigger
end

return obj
