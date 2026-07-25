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
--- Adding a backend is a new file in sources/ plus two lines below, the registration
--- and its policy slice, with no edit to the engine.

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

-- Register the concrete sources. Docker claims ports ahead of the raw listener
-- scan, see the note above.
obj.sources = {
  docker = load("sources/docker.lua"),
  ports = load("sources/ports.lua"),
}
obj._defaultSources = { obj.sources.docker, obj.sources.ports }

--- Processes:configure(opts)
--- Method
--- opts.policy   the pure data from config/processes.lua
--- opts.sources  an ordered source list, overriding the default order above
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

  obj.sources.docker.configure({
    graceSeconds = stop.graceSeconds,
    timeoutSeconds = policy.scanTimeoutSeconds,
  })

  return configureEngine(self, {
    sources = opts.sources or obj._defaultSources,
    genericDirs = policy.genericDirs,
  })
end

return obj
