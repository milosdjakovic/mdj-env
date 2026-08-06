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
--- Storage is the path builder that turns the two roots in
--- config/settings.lua into a finished directory for a tool, see
--- lib/storage.lua for its api. Recency is the lift to front ordering
--- service, a factory handing out an independent instance per caller, see
--- lib/recency.lua for its api. Paste is the insertion engine, one shared
--- instance rather than a factory since the machine has one pasteboard, see
--- lib/paste.lua for its api and for the boundary it draws.
---
--- The six below arrived in phase five, copies of the six atom spoons the design
--- names as core, each a faithful copy of the spoon it came from so the composition
--- root can hand it straight to that spoon's global and leave every existing call
--- site alone. Chooser is the picker facade, a directory rather than a file because
--- it loads a matcher and a backend of its own. Panel is the shared canvas surface,
--- cheatsheet the overlay renderer that draws through it, chordkey the hold and tap
--- engine under every leader, hyperkey the leader modal every context binds into,
--- and deps the declaration reader. Each is loaded here and named nowhere else in
--- this file, so the root decides what becomes of it.
obj.lib = {
  storage = load("lib/storage.lua"),
  recency = load("lib/recency.lua"),
  paste = load("lib/paste.lua"),
  chooser = load("lib/chooser/init.lua"),
  panel = load("lib/panel.lua"),
  cheatsheet = load("lib/cheatsheet.lua"),
  chordkey = load("lib/chordkey.lua"),
  hyperkey = load("lib/hyperkey.lua"),
  deps = load("lib/deps.lua"),
}

return obj
