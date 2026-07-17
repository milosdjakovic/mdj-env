--- The VPN engine, the mechanism. It holds the current status and drives a provider
--- through the contract, naming no backend. Truth lives in the VPN daemon, not here,
--- so status reads the provider live, and the actions delegate and then refresh, firing
--- onChange so an open panel tracks the change. This is the Observer the caffeinate
--- engine also uses. Liveness is the provider's concern, checked at dispatch, since the
--- daemon can stop while the CLI still exists, so status simply reports unavailable
--- when the daemon does not answer.

local M = {}

local provider = nil
local onChange = nil
local last = { state = "unavailable" }

local function fire()
  if onChange then onChange() end
end

-- Read the status from the provider and notify. A single fast call, so it runs on
-- the main thread.
local function refresh()
  if not provider then return end
  last = provider.status() or { state = "unavailable" }
  fire()
end

function M.configure(opts)
  opts = opts or {}
  provider = opts.provider
  onChange = opts.onChange
  return M
end

function M.start()
  refresh()
  return M
end

-- The status read on demand, so an opening panel shows the live state.
function M.status()
  if provider then last = provider.status() or { state = "unavailable" } end
  return last
end

-- An action runs through the provider off the main thread, then refreshes when it
-- lands so the status line follows. The provider appends its own completion callback,
-- so this passes the leading arguments and one refresh thunk.
local function run(method, ...)
  if not provider then return end
  local args = { ... }
  args[#args + 1] = function() refresh() end
  provider[method](table.unpack(args))
end

function M.connect() run("connect") end
function M.disconnect() run("disconnect") end
function M.setLocation(country, city) run("setLocation", country, city) end

function M.listLocations(cb)
  if provider then provider.listLocations(cb) end
end

return M
