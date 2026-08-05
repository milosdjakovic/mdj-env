--- === Olm ===
---
--- The reusable core, phase one of the build plan. This spoon is where the
--- storage mechanism lives before the registry, the host, and the plugin
--- bundle described in the design ever land, so init here is deliberately
--- bare, a name, a version, an api version a future plugin will declare
--- itself against, and one loaded module. No registry, no activation list,
--- no plugin machinery yet, those are later phases.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Olm"
obj.version = "0.1"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- The api version a plugin will one day declare itself against, a single
-- integer starting at one, bumped only on a breaking change to what this
-- spoon exposes, settled in phase zero of the build plan.
obj.apiVersion = 1

-- Loaded relative to this file's own location rather than from a hardcoded
-- path, the same pattern ClipboardHistory.spoon already uses for every file
-- it loads, since a spoon directory is never on package.path.
local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(spoonPath .. name)
  if not chunk then
    error("Olm failed to load " .. name .. ", " .. tostring(err))
  end
  return chunk()
end

--- Olm.lib
--- The shared mechanisms every later plugin reaches through this table.
--- Storage is the first one, the path builder that turns the two roots in
--- config/settings.lua into a finished directory for a tool. See
--- lib/storage.lua for the api.
obj.lib = {
  storage = load("lib/storage.lua"),
}

return obj
