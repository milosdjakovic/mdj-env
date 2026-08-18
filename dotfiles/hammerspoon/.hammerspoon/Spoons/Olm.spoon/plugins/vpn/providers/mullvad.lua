--- The Mullvad provider, the only file that knows the mullvad CLI. It implements the
--- VPN contract by shelling out. It resolves nothing itself, the CLI path is handed in
--- through configure by the layer above, which reads it from the shared dependency
--- resolver, so no Homebrew location is hardcoded here and the probing happens once for
--- the whole config. Until a path is handed in every method degrades safely and
--- available returns false, so the root can log the reason and the picker still opens.
--- Fast reads, status, run synchronously. Slow actions, connect and the relay list,
--- run through hs.task off the main thread so the UI never stalls, and their callback
--- lands back on the main thread.

local M = {}

-- The human name of this backend, so the control panel can label which provider it
-- is driving without the engine or the panel learning the concrete backend. Metadata
-- beside the contract methods, the provider being the one place that knows it.
M.name = "Mullvad"

-- What provides this backend when its CLI is absent, so the control panel can explain
-- itself instead of opening empty, and the root can log the reason, without either one
-- learning the concrete tool. This is the same idea as name, metadata the provider owns
-- because it is the one place that knows which application ships the CLI.
--
-- It deliberately stops there and carries no install command. How a tool is obtained is
-- the concern of the layer above this config, which reads the collected manifest and maps
-- each declared name to a concrete install, so a command here would be that answer
-- written a second time in the one layer that must not know it. The console line and this
-- row say what is missing, and src/check-dependencies.sh says where it comes from.
M.install = {
  note = "The Mullvad VPN app provides the mullvad CLI.",
}

-- The name this CLI is declared under, in the plugin's manifest, with unit naming this
-- provider. The layer above looks the path up by it, so the declaration and this provider
-- agree on one spelling.
M.tool = "mullvad"

-- The resolved absolute path, handed in through configure. Nil means the CLI is absent,
-- which every method below already treats as unavailable.
local cli = nil

--- M.configure(opts) - accept the resolved CLI path. Called by the spoon's own start with
--- whatever the shared resolver found, so this file performs no lookup of its own.
function M.configure(opts)
  cli = (opts or {}).path
  return M
end

function M.available()
  return cli ~= nil
end

-- Read the tunnel state now. A single fast call, so synchronous. Returns a plain
-- table the engine caches. When the daemon does not answer the state is unavailable.
function M.status()
  if not cli then return { state = "unavailable" } end
  local out, ok = hs.execute(cli .. " status -j 2>/dev/null")
  if not ok or not out or out == "" then return { state = "unavailable" } end
  local data = hs.json.decode(out)
  if not data then return { state = "unavailable" } end
  local s = { state = data.state or "unknown" }
  local loc = data.details and data.details.location
  if loc then
    s.country = loc.country
    s.city = loc.city
    s.hostname = loc.hostname
  end
  return s
end

-- The relay the tunnel would use on connect, read from the location constraint rather
-- than the live tunnel, since a disconnected tunnel still has a selection and its status
-- reports the real geography, not the target. A fast synchronous read like status. The
-- constraint prints as "Location: city lax, us" for a city, "Location: country us" for a
-- country, or "any" when unset. Returns { countryCode, cityCode } with cityCode nil for a
-- country only constraint, or nil when nothing is set.
function M.selectedLocation()
  if not cli then return nil end
  local out, ok = hs.execute(cli .. " relay get 2>/dev/null")
  if not ok or not out then return nil end
  local rest = out:match("Location:%s*(.-)\n")
  if not rest then return nil end
  local city, country = rest:match("^city%s+(%S+),%s*(%a%a)")
  if city and country then return { countryCode = country, cityCode = city } end
  local c = rest:match("^country%s+(%a%a)")
  if c then return { countryCode = c } end
  return nil
end

-- Run a CLI subcommand off the main thread and fire the callback on completion. The
-- callback lands on the main thread, so it is safe to touch the UI from it.
local function runAsync(args, cb)
  if not cli then
    if cb then cb(false, "mullvad not installed") end
    return
  end
  local t = hs.task.new(cli, function(rc, _, se)
    if cb then cb(rc == 0, (se ~= nil and se ~= "" and se) or nil) end
  end, args)
  t:start()
end

function M.connect(cb) runAsync({ "connect" }, cb) end
function M.disconnect(cb) runAsync({ "disconnect" }, cb) end

-- Select a relay and go there. Setting the location constraint alone does not
-- connect when the tunnel is down, so this sets the location and then connects, which
-- also switches an already connected tunnel to the new place. The callback reports the
-- connect result.
function M.setLocation(country, city, cb)
  local args = { "relay", "set", "location", country }
  if city and city ~= "" then args[#args + 1] = city end
  runAsync(args, function(ok, err)
    if not ok then
      if cb then cb(false, err) end
      return
    end
    M.connect(cb)
  end)
end

-- Parse `mullvad relay list` into a flat list of city entries. Country lines sit at
-- the left margin as Name (cc), city lines are indented one tab as Name (ccc) @ coords,
-- and host lines are indented two tabs and ignored. Each city becomes one searchable
-- entry labelled City, Country.
local function parseRelays(output)
  local list, country, ccode = {}, nil, nil
  for line in (output .. "\n"):gmatch("(.-)\n") do
    if line:match("^\t\t") then
      -- host line, ignore
    elseif line:match("^\t") then
      local city, code = line:match("^\t(.-)%s+%((%a%a%a)%)")
      if city and country then
        list[#list + 1] = {
          id = ccode .. "/" .. code,
          label = city .. ", " .. country,
          country = country, countryCode = ccode,
          city = city, cityCode = code,
        }
      end
    else
      local c, cc = line:match("^(.-)%s+%((%a%a)%)%s*$")
      if c then country, ccode = c, cc end
    end
  end
  return list
end

function M.listLocations(cb)
  if not cli then
    if cb then cb({}) end
    return
  end
  local t = hs.task.new(cli, function(rc, so, _)
    if cb then cb((rc == 0 and so) and parseRelays(so) or {}) end
  end, { "relay", "list" })
  t:start()
end

return M
