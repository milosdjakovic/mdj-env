--- === KeyRemap ===
---
--- Apply a physical key remap at the HID level from a list of key names, so the leaders can
--- drive otherwise unused function keys. This is the mechanism half only. It turns friendly
--- key names into hidutil usage codes, applies the mapping, and clears it on quit. It does
--- not decide which keys are active, the composition root passes that in, so this applier
--- stays ignorant of apps, windows, or any consumer. It also owns which keys a held leader may
--- be, the allow list, and which function key each one's engine listens on, since those are facts
--- about the mapping and not about any leader. F13 to F20 are heard as they are, Caps Lock and the
--- right modifiers are remapped to one of them, and allocate below decides which, the same way for
--- the same rows on every load.
---
--- Why here and not a login LaunchAgent. The remapped keys only do anything while
--- Hammerspoon runs, so owning the remap here keeps one source of truth. A key becomes
--- special on load and reverts on quit, and an unreferenced key is simply never remapped, so
--- it stays a normal key with no extra step anywhere.
---
--- hidutil property --set replaces the whole mapping table in one shot, so each apply is
--- idempotent and also frees any key dropped since the last apply. No sudo is needed,
--- UserKeyMapping is per user.
---
--- This was a plugin until phase two of the core split, and it is core now beside the leader
--- adapter, lib/leader.lua, since the leaders are the root's own business and a plugin may only
--- name core.
--- The keys it is asked about are the keys of the held leaders in the leaders table the root
--- ships and the person's leaders section lays over, and the path of the binary arrives from the
--- root's own declaration of hidutil in root/manifest.lua.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "KeyRemap"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("KeyRemap", "info")

-- Friendly name -> HID keyboard usage code, every key a held leader may name. The list is the allow
-- list, so a key is admitted by a row here and nowhere else. The right modifiers and Caps Lock do
-- not send a clean press and release, so they are remapped to a function key. F13 to F20 do, and
-- are used as they are, which is also how a pedal, a macro pad or a programmable keyboard becomes
-- a leader, by being told in its own firmware to send one of them.
local USAGE = {
  capsLock     = 0x700000039,
  rightCommand = 0x7000000E7,
  rightOption  = 0x7000000E6,
  rightControl = 0x7000000E4,
  f13          = 0x700000068,
  f14          = 0x700000069,
  f15          = 0x70000006A,
  f16          = 0x70000006B,
  f17          = 0x70000006C,
  f18          = 0x70000006D,
  f19          = 0x70000006E,
  f20          = 0x70000006F,
}

-- The keys the engine listens on, in the order a free one is looked for. A key of USAGE is a
-- function key exactly when it is in this list.
local FUNCTION_KEYS = { "f13", "f14", "f15", "f16", "f17", "f18", "f19", "f20" }
local IS_FUNCTION = {}
for _, name in ipairs(FUNCTION_KEYS) do IS_FUNCTION[name] = true end

-- The function key a remapped source prefers. Caps Lock to F18, Right Option to F16 and Right
-- Command to F17 are the three rows the owner already wants HYPER, META and SUPER to be, kept
-- stable because another app may already bind one of them. A source with no row, Right Control,
-- takes the first free key. Every target is a function key of USAGE above.
local PREFERRED_TARGET = {
  capsLock     = "f18",
  rightOption  = "f16",
  rightCommand = "f17",
}

local CLEAR = '{"UserKeyMapping":[]}'

-- The command is built into a local rather than written inline, which is the shape a resolved
-- tool path has to arrive in and also what makes the reconciler's own door check able to see
-- that nothing here reaches around it.
local function setMapping(hidutil, json)
  local command = '"' .. hidutil .. '" property --set ' .. "'" .. json .. "'"
  hs.execute(command)
end

--- KeyRemap:init()
--- Method
--- Initialize the spoon
function obj:init()
  return self
end

--- KeyRemap.sources() -> set
--- Function
--- The key names a held leader may name, the allow list, as a set of name to true.
function obj.sources()
  local set = {}
  for name in pairs(USAGE) do set[name] = true end
  return set
end

--- KeyRemap.allocate(rows) -> { leaders, remaps, issues, notes }
--- Function
--- Decides which function key each held leader's engine listens on. Pure, so the root asks it once
--- for every held leader the leaders table holds, in use or not, and the answer cannot depend on
--- which leaders happen to be in use on a load.
---   rows     list of { name, key, remapTo } for every held leader, remapTo nil unless stated
---   leaders  name to { fkey, target }, fkey the function key the engine listens on and target the
---            same key when the leader is remapped, nil when its key is a function key already
---   remaps   list of { name, key, target } for the leaders that are remapped, in name order
---   issues   list of { name, why } sorted by name, one per leader that cannot be placed, why the
---            sentence the leader's problem line carries. A conflict names every leader in it.
---   notes    routine lines, a preferred target that was taken
---
--- A function key is used directly. A remapped key goes to its remapTo when stated, else its
--- preferred target, else the first free key of F13 to F20. A key is not free when another leader
--- uses it directly or holds it as a pinned or earlier placed target. Pinned targets are placed
--- first, then preferred ones, then the rest, each pass in source key name order, so the same
--- rows always give the same answer.
function obj.allocate(rows)
  local issueList, notes = {}, {}
  local function issue(name, why) issueList[#issueList + 1] = { name = name, why = why } end

  -- A row naming a key off the list, or a remapTo that is not a function key or sits beside a key
  -- that needs none, cannot be placed.
  local ok = {}
  for _, row in ipairs(rows or {}) do
    local bad = nil
    if not USAGE[row.key] then
      bad = "has a key of '" .. tostring(row.key) .. "', which is not a key Olm can make a leader"
    elseif row.remapTo ~= nil and not IS_FUNCTION[row.remapTo] then
      bad = "has a remapTo of '" .. tostring(row.remapTo) .. "', which is not one of "
        .. FUNCTION_KEYS[1] .. " to " .. FUNCTION_KEYS[#FUNCTION_KEYS]
    elseif row.remapTo ~= nil and IS_FUNCTION[row.key] then
      bad = "has a remapTo beside the key " .. row.key .. ", which is a function key already and is not remapped"
    end
    if bad then issue(row.name, bad) else ok[#ok + 1] = row end
  end

  -- Two leaders on one physical key.
  local byKey = {}
  for _, row in ipairs(ok) do
    byKey[row.key] = byKey[row.key] or {}
    table.insert(byKey[row.key], row.name)
  end
  local placeable = {}
  for _, row in ipairs(ok) do
    local sharing = byKey[row.key]
    if #sharing > 1 then
      table.sort(sharing)
      issue(row.name, "shares the key " .. row.key .. " with " .. table.concat(sharing, ", ")
        .. ", and a key is one leader's")
    else
      placeable[#placeable + 1] = row
    end
  end

  -- Function keys leaders use directly, then the keys pinned by remapTo, which may not meet either
  -- a direct leader or another pin.
  local claimed, direct, pinned = {}, {}, {}
  for _, row in ipairs(placeable) do
    if IS_FUNCTION[row.key] then direct[row.key] = row.name end
  end
  for _, row in ipairs(placeable) do
    if row.remapTo ~= nil then
      pinned[row.remapTo] = pinned[row.remapTo] or {}
      table.insert(pinned[row.remapTo], row.name)
    end
  end
  local placed = {}
  for _, row in ipairs(placeable) do
    if IS_FUNCTION[row.key] then
      claimed[row.key] = true
      placed[row.name] = { fkey = row.key }
    end
  end
  local remapRows = {}
  for _, row in ipairs(placeable) do
    if not IS_FUNCTION[row.key] then remapRows[#remapRows + 1] = row end
  end
  table.sort(remapRows, function(a, b)
    if a.key ~= b.key then return a.key < b.key end
    return a.name < b.name
  end)
  for _, row in ipairs(remapRows) do
    local target = row.remapTo
    if target ~= nil then
      local users = pinned[target]
      if direct[target] then
        issue(row.name, "has a remapTo of " .. target .. ", which leader " .. direct[target]
          .. " uses directly as its key")
        issue(direct[target], "uses " .. target .. " directly, which leader " .. row.name
          .. " names as its remapTo")
      elseif #users > 1 then
        local sorted = { table.unpack(users) }
        table.sort(sorted)
        issue(row.name, "has a remapTo of " .. target .. ", which " .. table.concat(sorted, ", ")
          .. " all name, and a function key is one leader's")
      else
        claimed[target] = true
        placed[row.name] = { fkey = target, target = target, key = row.key }
      end
    end
  end
  -- Preferred targets next, then the first free key for what is left.
  local waiting = {}
  for _, row in ipairs(remapRows) do
    if row.remapTo == nil then
      local want = PREFERRED_TARGET[row.key]
      if want and not claimed[want] then
        claimed[want] = true
        placed[row.name] = { fkey = want, target = want, key = row.key }
      else
        waiting[#waiting + 1] = row
      end
    end
  end
  for _, row in ipairs(waiting) do
    local free = nil
    for _, name in ipairs(FUNCTION_KEYS) do
      if not claimed[name] then free = name break end
    end
    if not free then
      issue(row.name, "has no function key left to be remapped to, since F13 to F20 are all in use")
    else
      claimed[free] = true
      placed[row.name] = { fkey = free, target = free, key = row.key }
      local want = PREFERRED_TARGET[row.key]
      if want then
        notes[#notes + 1] = "leader " .. row.name .. " on " .. row.key .. " prefers " .. want
          .. ", which is in use, so it takes " .. free
      end
    end
  end

  -- Whatever a conflict left out is unplaced, and the rest is answered.
  local leaders, remaps = {}, {}
  for _, row in ipairs(placeable) do
    local slot = placed[row.name]
    if slot then
      leaders[row.name] = { fkey = slot.fkey, target = slot.target }
      if slot.target then remaps[#remaps + 1] = { name = row.name, key = row.key, target = slot.target } end
    end
  end
  table.sort(remaps, function(a, b) return a.name < b.name end)
  table.sort(issueList, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.why < b.why
  end)
  return { leaders = leaders, remaps = remaps, issues = issueList, notes = notes }
end

--- KeyRemap:apply(held, hidutil)
--- Method
--- held        - list of { name = <leader name>, key = <source key name>, target = <function key
---               name> } to remap right now, the rows allocate answers as remaps, anything not
---               listed is left as a normal key. The name is only for the log. Two rows with one
---               key are remapped once. A row with no target is a function key the engine hears
---               as it is, so it is left out of the mapping without a word.
--- hidutil     - the absolute path of the binary, resolved by the root through the dependency
---               door. It arrives as an argument so this file never probes for a tool or
---               hardcodes a prefix, which is the rule every other shellout here follows.
--- Builds one UserKeyMapping from the active rows and applies it, replacing any previous
--- mapping. Also arms a shutdown handler that clears the mapping when Hammerspoon quits or
--- reloads, so these keys are only special while it runs.
---
--- An unresolved binary returns without touching the mapping and without arming that handler,
--- which is the safe direction rather than merely the careful one. hidutil is declared
--- required, so this should be unreachable, but the two ways of getting it wrong are not
--- symmetric. Failing to apply leaves every leader as its own native key, which is visible
--- and recoverable. Failing while CLEARING would leave a machine wide remap in place after
--- Hammerspoon exits, recoverable only by hand or by a reboot, so the handler is armed only
--- once a path has already been proven to work by the apply above it.
function obj:apply(held, hidutil)
  if not hidutil then
    log.e("hidutil did not resolve through the dependency door, so no leader key was remapped "
      .. "and every one of them stays its own native key")
    return self
  end
  local seen, entries = {}, {}
  for _, row in ipairs(held or {}) do
    local key = row.key
    if not seen[key] then
      seen[key] = true
      local target = row.target
      local src, dst = USAGE[key], target and USAGE[target]
      if target == nil and IS_FUNCTION[key] then
        -- Nothing to remap, the engine listens on the key itself.
      elseif not src or not dst then
        log.w("'" .. tostring(row.name) .. "' names '" .. tostring(key)
          .. "', which is not a key this remap can map to a function key, so it is left as it is")
      else
        entries[#entries + 1] = string.format(
          '{"HIDKeyboardModifierMappingSrc":%d,"HIDKeyboardModifierMappingDst":%d}', src, dst)
      end
    end
  end
  setMapping(hidutil, '{"UserKeyMapping":[' .. table.concat(entries, ",") .. ']}')
  -- Restore native keys when Hammerspoon exits or reloads. The next load
  -- reapplies, so a reload just blips through native for a moment. The path is captured
  -- rather than resolved again here, so the clear can never fail for a reason the apply
  -- did not already fail for.
  hs.shutdownCallback = function() setMapping(hidutil, CLEAR) end
  return self
end

return obj
