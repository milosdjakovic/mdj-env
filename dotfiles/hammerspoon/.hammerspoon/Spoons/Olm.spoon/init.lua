--- === Olm ===
---
--- The reusable core, phase one of the build plan, with the tool registry from phase
--- seven added beside the libs that arrived before it. Init here stays deliberately
--- bare, a name, a version, an api version a plugin declares itself against, and the
--- loaded modules under Olm.lib. The registry is state and the composition root builds
--- its own instance from the factory this spoon loads, so nothing here names a tool or
--- holds an activation list of its own.

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
---
--- Registry arrived in phase seven, another factory like recency, handing the root an
--- independent instance to register every tool against. See lib/registry.lua for its
--- api.
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
  -- The tool registry, phase seven of the build plan. A factory in the same style as
  -- recency, so the root builds its own instance with M.new rather than reaching for a
  -- shared one, and every function it hands back is dot called, since it holds no
  -- metatable and no self. See lib/registry.lua for the descriptor shape, the four
  -- refusals, and what active and inactive mean today.
  registry = load("lib/registry.lua"),
}

return obj
