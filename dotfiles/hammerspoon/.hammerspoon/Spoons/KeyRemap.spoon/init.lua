--- === KeyRemap ===
---
--- Apply a physical key remap at the HID level from a name-based catalog, so
--- other spoons can drive otherwise-unused function keys. This is the mechanism
--- half only. It turns friendly key names into hidutil usage codes, applies the
--- mapping, and clears it on quit. It does not decide which keys are active, the
--- composition root passes that in, so this applier and the catalog it reads stay
--- ignorant of apps, windows, or any consumer.
---
--- Why here and not a login LaunchAgent. The remapped keys only do anything while
--- Hammerspoon runs, so owning the remap here keeps one source of truth. A key
--- becomes special on load and reverts on quit, and an unreferenced key is simply
--- never remapped, so it stays a normal key with no extra step anywhere.
---
--- hidutil property --set replaces the whole mapping table in one shot, so each
--- apply is idempotent and also frees any key dropped since the last apply. No
--- sudo is needed, UserKeyMapping is per user.

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

local function setMapping(json)
  hs.execute("/usr/bin/hidutil property --set '" .. json .. "'")
end

--- KeyRemap:init()
--- Method
--- Initialize the spoon
function obj:init()
  return self
end

--- KeyRemap:apply(catalog, activeNames)
--- Method
--- catalog     - name -> { source = <friendly>, fkey = <friendly> }
--- activeNames - list of catalog names to remap right now; anything not listed
---               is left as a normal key. Duplicates are ignored.
--- Builds one UserKeyMapping from the active rows and applies it, replacing any
--- previous mapping. Also arms a shutdown handler that clears the mapping when
--- Hammerspoon quits or reloads, so these keys are only special while it runs.
function obj:apply(catalog, activeNames)
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
  setMapping('{"UserKeyMapping":[' .. table.concat(entries, ",") .. ']}')
  -- Restore native keys when Hammerspoon exits or reloads. The next load
  -- reapplies, so a reload just blips through native for a moment.
  hs.shutdownCallback = function() setMapping(CLEAR) end
  return self
end

return obj
