--- The VPN engine, the mechanism. It holds the current status and drives a provider
--- through the contract, naming no backend. Truth lives in the VPN daemon, not here,
--- so status reads the provider live, and the actions delegate and then refresh, firing
--- onChange so an open panel tracks the change. This is the Observer pattern. Liveness is
--- the provider's concern, checked at dispatch, since the
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

-- Configure is also the switch. A provider swapped in here brings none of the previous
-- one's state with it, so the cached status is dropped rather than left standing, since a
-- state read from one backend says nothing about another. Reporting the old backend's
-- Connected while the new one has not been asked yet would be confidently wrong in exactly
-- the moment a person is watching the list redraw. Unavailable is the honest starting
-- answer, and start below reads the truth immediately afterwards.
function M.configure(opts)
  opts = opts or {}
  provider = opts.provider
  onChange = opts.onChange
  last = { state = "unavailable" }
  return M
end

function M.start()
  refresh()
  return M
end

-- The status read on demand, so an opening panel shows the live state. Synchronous, kept
-- for a caller off the hot path, refresh above among them.
function M.status()
  if provider then last = provider.status() or { state = "unavailable" } end
  return last
end

-- The async counterparts to status and selectedLocation below, phase three review finding
-- eleven, for a caller that must never block the main thread while it draws, VPN's own
-- M.prepare among them. Answer through cb rather than updating last or firing onChange,
-- since a caller reading fresh state for its own presentation is not the daemon telling
-- every open panel something changed, two different events, and onChange stays the second
-- one's own door alone.
function M.statusAsync(cb)
  if not provider or not provider.statusAsync then
    if cb then cb(last) end
    return
  end
  provider.statusAsync(function(status) if cb then cb(status or { state = "unavailable" }) end end)
end

-- The two actions. Each delegates and then refreshes when it lands, so the status line
-- follows what the daemon actually did rather than what was asked of it.
--
-- Written out rather than driven through one varargs helper, which is what used to sit here.
-- A nil target is an ordinary argument now, go wherever this backend would go on its own, and
-- a nil in a varargs table is invisible to the length operator, so the helper would have
-- packed no arguments at all and handed the refresh thunk to connect as its target. Two
-- explicit lines cost nothing and cannot do that.
function M.connect(target)
  if not provider then return end
  provider.connect(target, function() refresh() end)
end

function M.disconnect()
  if not provider then return end
  provider.disconnect(function() refresh() end)
end

function M.listLocations(cb)
  if provider then provider.listLocations(cb) end
end

-- The relay this backend would use for a connect with no target, read live from the provider
-- so a caller with no target of its own can still name where a connect would go. Synchronous,
-- kept for a caller off the hot path.
--
-- Probed for rather than called outright, since the contract stopped requiring it. A backend
-- that holds no readable selection omits the method entirely, and nil here is the same answer
-- a backend that holds one but has nothing set already gives, so a caller needs no third
-- branch for the difference.
function M.selectedLocation()
  if provider and provider.selectedLocation then return provider.selectedLocation() end
  return nil
end

function M.selectedLocationAsync(cb)
  if not provider or not provider.selectedLocationAsync then
    if cb then cb(nil) end
    return
  end
  provider.selectedLocationAsync(cb)
end

return M
