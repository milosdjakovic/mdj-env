--- === Speedtest ===
---
--- Measure this connection with the tool macOS already ships, and read the answer against
--- this network's own past rather than against a number from a review.
---
--- This file is the composition root of the plugin, and only this. It loads the pieces, names
--- them, hands each the slice of the world it needs, and returns the assembled module.
---   runner.lua   one measurement, from flags to a finished record. Owns the task and the
---                timeout, outlives the list, knows nothing about lists or panes.
---   store.lua    the history, the network names, and the run settings, one JSON file.
---   chooser.lua  the list surface, pure policy over the two above.
---   pane.lua     the docked companion pane, loaded by the chooser since only the chooser
---                knows when a window exists to draw beside.
---   util.lua     stateless formatting and the one question of which network this is.
---
--- There is no provider contract here and there should not be one yet. There is exactly one
--- way to measure a connection on this machine, so an engine and a contract would be
--- indirection with a single caller. The seam that would matter is already clean, runner.parse
--- turns one tool's output into the record everything else reads, so a second backend would be
--- a second file and one more line in this one rather than a rewrite.

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")

local function load(name)
  local chunk, err = loadfile(spoonPath .. name)
  if not chunk then
    error("Speedtest: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end

local obj = { name = "Speedtest" }

local util = load("util.lua")
local store = load("store.lua")
local runner = load("runner.lua")

-- The list surface, reached by the manifest as chooser.rows and the rest.
obj.chooser = load("chooser.lua")

--- Speedtest:configure(opts)
--- opts.storage            lib/storage.lua, for the one data directory this plugin owns.
--- opts.deps               the per plugin dependency adapter, the only way this file learns
---                         where networkQuality lives. Nothing here ever names a path.
--- opts.glyphIcon          the shared glyph drawer, so a row's icon lines up with every other
---                         row's in this configuration.
--- opts.surface            the shared pane surface, granted because the manifest asks for a
---                         pane. Absent means the list opens with no companion rect at all.
--- opts.emptyState         the shared quiet state a docked pane paints with nothing to say.
--- opts.theme              the shared palette, which the pane resolves per open.
--- opts.stagePresent, opts.redrawPresented, opts.stagePop, opts.stageSelectedItem
---                         the four root published words this plugin speaks.
function obj:configure(opts)
  opts = opts or {}

  store.configure({
    storage = opts.storage,
    log = opts.log,
  })

  runner.configure({
    -- Looked up by the name the manifest itself declares, so this file names a tool but never
    -- a location. Without it the lookup yields nil, the runner reports itself unavailable, and
    -- the list opens to one row saying so with the history still readable.
    path = opts.deps and opts.deps.path("networkQuality") or nil,
    -- The pty. Absent means a run still happens and still keeps everything, with no figures
    -- arriving while it is being taken, which is exactly what this plugin did before the live
    -- graph existed.
    pty = opts.deps and opts.deps.path("script") or nil,
    -- The module rather than a finished path, so the directory is built on the first run rather
    -- than at configure. Asking for a path here would make this plugin's own configure depend on
    -- storage having been configured already, which is true live and is not true under the dry
    -- gate's stub, and the cost of that is the gate reporting this plugin unknown and checking
    -- none of its member paths, which is the coverage the gate exists for. One temporary file per
    -- run lives under the cache root, since it is regenerable by definition, unlike the history.
    storage = opts.storage,
    log = opts.log,
    -- Handed over rather than loaded there, since loadfile answers a fresh module every call
    -- and two copies of a stateless helper is one more thing to keep in step for no gain.
    util = util,
  })

  obj.chooser.configure({
    runner = runner,
    store = store,
    surface = opts.surface,
    emptyState = opts.emptyState,
    theme = opts.theme,
    glyphIcon = opts.glyphIcon,
    stagePresent = opts.stagePresent,
    redrawPresented = opts.redrawPresented,
    stagePop = opts.stagePop,
    stageSelectedItem = opts.stageSelectedItem,
    log = opts.log,
  })

  return self
end

return obj
