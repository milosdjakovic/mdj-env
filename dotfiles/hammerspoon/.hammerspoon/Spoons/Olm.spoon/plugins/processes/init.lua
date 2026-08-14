--- === Processes ===
---
--- Find and stop the development servers you left running. It lists what you
--- started rather than what the machine is running, identified by the port it holds
--- and the project it runs in, and stops it correctly by taking the whole process
--- group or the whole container rather than one leaf process.
---
--- This file is the composition root of the spoon, and only this. It loads the
--- pieces, names the concrete sources, sets the claim order, hands each source the
--- slice of policy it needs, and returns the assembled spoon.
---   engine.lua      the Context, owns the merge, the labelling and the dispatch
---   contract.lua    the interface every source must implement
---   util.lua        stateless shellout and formatting helpers
---   chooser.lua     the list surface, pure policy over the engine's api
---   metrics.lua     the live CPU and memory sampler, owned by the surface
---   sources/*.lua   the concrete backends, one self contained file each
---
--- The split keeps each piece ignorant of the others. The engine never names a
--- source, the sources never know about each other or about the merge, and the
--- contract knows nothing about any of them. So this is the ONE file that names
--- concrete sources, which is why both the claim order and the policy distribution
--- live here.
---
--- Docker is registered first on purpose. Claim order is what decides who owns a
--- port, and every published container port is also held by one docker proxy
--- process that the ports source would otherwise report as a nameless listener. By
--- claiming first, docker republishes those ports as named containers and the ports
--- source's view of them is dropped, which is how the collapse happens without the
--- engine knowing what a container is.
---
--- Runtimes is registered last, and that one is not a preference either. It reports
--- development processes holding no socket, so its rows are identified by the
--- processes they name rather than by a port. A portless row can never claim a port
--- away from a row that holds one, so putting it earlier would not invert the order
--- the way swapping docker and ports does, it would simply publish a tree first and
--- leave the port holding view of the same tree to appear beside it as a duplicate.
--- The order here is strongest identity first, and a port is the strongest.
---
--- Adding a backend is a new file in sources/ plus two lines below, the registration
--- and its policy slice, with no edit to the engine.
---
--- This is the olm side copy of Processes, phase six of the plugin bundling pass, and
--- the original this was copied from lived at Spoons/Processes.spoon.

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(spoonPath .. name)
  if not chunk then
    error("Processes: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end

local obj = load("engine.lua")

-- Inject the contract the engine validates the source list against.
obj._contract = load("contract.lua")

-- Register the concrete sources, in claim order. Docker ahead of the raw listener
-- scan, and the portless runtimes scan last of all, see the note above.
obj.sources = {
  docker = load("sources/docker.lua"),
  ports = load("sources/ports.lua"),
  runtimes = load("sources/runtimes.lua"),
}
obj._defaultSources = { obj.sources.docker, obj.sources.ports, obj.sources.runtimes }

-- The list surface. It reaches the engine only through the api built in configure
-- below, so it never learns that sources exist.
obj.chooser = load("chooser.lua")

--- Processes:configure(opts)
--- Method
--- opts.policy   the pure data from config/processes.lua
--- opts.sources  an ordered source list, overriding the default order above
--- opts.deps     the per consumer dependency adapter from the root, the only way a
---               source here learns where its CLI lives
---
--- Wraps the engine's own configure so this file stays the only place that knows
--- both which sources exist and which part of the policy each one reads. The engine
--- is handed only what it uses itself and never forwards opaque config it cannot
--- read, which is what stops the policy shape from leaking into the mechanism.
local configureEngine = obj.configure
function obj:configure(opts)
  opts = opts or {}
  local policy = opts.policy or {}
  local stop = policy.stop or {}

  obj.sources.ports.configure({
    runtimes = policy.runtimes,
    ignoreCommands = policy.ignoreCommands,
    devRoots = policy.devRoots,
    graceSeconds = stop.graceSeconds,
    confirmAbove = stop.confirmAbove,
    timeoutSeconds = policy.scanTimeoutSeconds,
  })

  -- The same slice the ports source reads, because the two apply the same policy to
  -- different evidence. Ports treats a runtime or a dev root as enough on its own,
  -- since holding a socket is already strong evidence, while runtimes needs both,
  -- see its own header for why either half alone is far too loose without a port.
  obj.sources.runtimes.configure({
    runtimes = policy.runtimes,
    ignoreCommands = policy.ignoreCommands,
    devRoots = policy.devRoots,
    graceSeconds = stop.graceSeconds,
    confirmAbove = stop.confirmAbove,
    timeoutSeconds = policy.scanTimeoutSeconds,
  })

  -- Docker is the one source here whose tool is not a fixed system path, so it is the one
  -- that gets handed a resolved location. It is looked up by the name the source itself
  -- declares, the same way the Vpn spoon hands its provider a path, so this file names a
  -- source but never a location. Without a docker CLI the lookup yields nil, the source
  -- reports itself unavailable, and the picker simply shows no containers.
  obj.sources.docker.configure({
    graceSeconds = stop.graceSeconds,
    timeoutSeconds = policy.scanTimeoutSeconds,
    path = opts.deps and opts.deps.path(obj.sources.docker.tool) or nil,
  })

  configureEngine(self, {
    sources = opts.sources or obj._defaultSources,
    genericDirs = policy.genericDirs,
  })

  -- The api the list surface talks through. Two verbs and nothing else, so the
  -- surface cannot reach a source, cannot reorder the merge, and cannot learn what
  -- a container is. This is also the seam a second surface would reuse unchanged.
  obj.chooser:configure({
    api = {
      scan = function(cb) obj:scan(cb) end,
      stop = function(row, stopOpts, cb) obj:stop(row, stopOpts, cb) end,
    },
    -- The live sampler's slice, handed to the surface rather than configured beside
    -- the sources, because sampling runs only while the picker is open and the
    -- surface is the piece that owns that window. The surface loads the sampler
    -- itself and forwards this, since each loadfile returns a fresh table and
    -- loading it here as well would leave two independent modules, one configured
    -- and one sampling.
    metrics = policy.metrics,
  })

  return self
end

return obj
