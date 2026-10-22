--- === KeyRemap ===
---
--- Apply a physical key remap at the HID level from a list of key names, so the leaders can
--- drive otherwise unused function keys. This is the mechanism half only. It turns friendly
--- key names into hidutil usage codes, applies the mapping, and clears it on quit. It does
--- not decide which keys are active, the composition root passes that in, so this applier
--- stays ignorant of apps, windows, or any consumer. It also owns which function key each
--- source is remapped to, since that is a fact about the mapping and not about any leader.
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

-- Friendly name -> HID keyboard usage code. Sources are the physical keys we
-- remap from, the function keys are the unused targets we remap to. Supporting another
-- source is a row here and a row in PREFERRED_TARGET below.
local USAGE = {
  capsLock     = 0x700000039,
  rightCommand = 0x7000000E7,
  rightOption  = 0x7000000E6,
  f16          = 0x70000006B,
  f17          = 0x70000006C,
  f18          = 0x70000006D,
}

-- The function key each source is remapped to. A source with a row here is one a held leader may
-- name, and the target is the spare key the leader's engine listens on. Caps Lock to F18, Right
-- Option to F16 and Right Command to F17 are the three rows the owner already wants HYPER, META and
-- SUPER to be, kept stable because another app may already bind one of them. Every target is a key
-- of USAGE above.
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
--- The source key names a held leader may name, as a set of name to true.
function obj.sources()
  local set = {}
  for source in pairs(PREFERRED_TARGET) do set[source] = true end
  return set
end

--- KeyRemap.targetFor(source) -> friendly name or nil
--- Function
--- The function key a source is remapped to, nil for a source this file does not know.
function obj.targetFor(source)
  return PREFERRED_TARGET[source]
end

--- KeyRemap:apply(held, hidutil)
--- Method
--- held        - list of { name = <leader name>, key = <source key name> } to remap right now,
---               anything not listed is left as a normal key. The name is only for the log. Two
---               rows with one key are remapped once.
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
      local target = PREFERRED_TARGET[key]
      local src, dst = USAGE[key], target and USAGE[target]
      if not src or not dst then
        log.w("'" .. tostring(row.name) .. "' names '" .. tostring(key)
          .. "', which is not a key this remap knows, so it is left as it is")
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
