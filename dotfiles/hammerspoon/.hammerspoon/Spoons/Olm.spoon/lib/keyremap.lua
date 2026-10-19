--- === KeyRemap ===
---
--- Apply a physical key remap at the HID level from a name based catalog, so the leaders can
--- drive otherwise unused function keys. This is the mechanism half only. It turns friendly
--- key names into hidutil usage codes, applies the mapping, and clears it on quit. It does
--- not decide which keys are active, the composition root passes that in, so this applier
--- stays ignorant of apps, windows, or any consumer.
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
--- The catalog it reads is root policy, policy.leaderCatalog in root/compose.lua, and the path
--- of the binary arrives from the root's own declaration of hidutil in root/manifest.lua.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "KeyRemap"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("KeyRemap", "info")

-- Friendly name -> HID keyboard usage code. Sources are the physical keys we
-- remap from, the f-keys are the unused targets we remap to. Add a row to
-- support another key, nothing else here changes.
local USAGE = {
  capsLock     = 0x700000039,
  rightCommand = 0x7000000E7,
  rightOption  = 0x7000000E6,
  f16          = 0x70000006B,
  f17          = 0x70000006C,
  f18          = 0x70000006D,
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

--- KeyRemap:apply(catalog, activeNames, hidutil)
--- Method
--- catalog     - name -> { source = <friendly>, fkey = <friendly> }
--- activeNames - list of catalog names to remap right now, anything not listed is left as a
---               normal key. Duplicates are ignored.
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
function obj:apply(catalog, activeNames, hidutil)
  if not hidutil then
    log.e("hidutil did not resolve through the dependency door, so no leader key was remapped "
      .. "and every one of them stays its own native key")
    return self
  end
  catalog = catalog or {}
  local seen, entries = {}, {}
  for _, name in ipairs(activeNames or {}) do
    if not seen[name] then
      seen[name] = true
      local row = catalog[name]
      if not row then
        log.w("unknown key '" .. tostring(name) .. "'")
      else
        local src, dst = USAGE[row.source], USAGE[row.fkey]
        if not src or not dst then
          log.w("'" .. name .. "' has unknown source/fkey, "
            .. tostring(row.source) .. " -> " .. tostring(row.fkey))
        else
          entries[#entries + 1] = string.format(
            '{"HIDKeyboardModifierMappingSrc":%d,"HIDKeyboardModifierMappingDst":%d}', src, dst)
        end
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
