--- The Mullvad provider, the only file that knows the mullvad CLI. It implements the
--- VPN contract by shelling out. It resolves nothing itself, the CLI path is handed in
--- through configure by the layer above, which reads it from the shared dependency
--- resolver, so no Homebrew location is hardcoded here and the probing happens once for
--- the whole config. Until a path is handed in every method degrades safely and
--- available returns false, so the root can log the reason and the picker still opens.
---
--- status and selectedLocation are fast enough to read synchronously and are kept that
--- way for a caller off the hot path, the engine's own onChange among them, but each now
--- has an async counterpart too, statusAsync and selectedLocationAsync, phase three review
--- finding eleven. A synchronous CLI spawn on the path from a keypress to the stage's own
--- swap read as the swap stalling rather than as the tool opening, since the window that
--- used to hide the cost by already being closed no longer closes first. Both pairs share
--- one parse function each, so the synchronous and the asynchronous reads can never answer
--- the identical CLI output two different ways. connect, disconnect, setLocation, and the
--- relay list were already off the main thread, through hs.task, and still are.
---
--- Every hs.task spawn in this file now checks its own start() return, the phase three
--- verification rider. hs.task:start() answers nil rather than raising when the task never
--- actually launches, and none of the four spawns here used to look, so a launch failure left
--- a callback that was never going to be called with nothing anywhere saying so. That silence
--- reached furthest through statusAsync, selectedLocationAsync, and listLocations, the three
--- Vpn.init.lua's own M.prepare races together, whose countdown had no way to notice a leg
--- that would never land. A failed start now answers the identical degraded value a missing
--- cli already answers, unavailable for status, nil for the selected relay, an empty list for
--- the relays, so a daemon that cannot even be launched reads the same as one that was never
--- installed rather than as a fetch stuck open forever.

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

-- Shared by the synchronous read below and its async counterpart further down, so the two
-- can never parse the identical CLI output two different ways. Phase three review finding
-- eleven split the read from the parse for exactly that reason.
local function parseStatusOutput(out, ok)
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

-- Read the tunnel state now. A single fast call, so synchronous. Returns a plain
-- table the engine caches. When the daemon does not answer the state is unavailable.
function M.status()
  if not cli then return { state = "unavailable" } end
  local out, ok = hs.execute(cli .. " status -j 2>/dev/null")
  return parseStatusOutput(out, ok)
end

-- The relay the tunnel would use on connect, read from the location constraint rather
-- than the live tunnel, since a disconnected tunnel still has a selection and its status
-- reports the real geography, not the target. A fast synchronous read like status. The
-- constraint prints as "Location: city lax, us" for a city, "Location: country us" for a
-- country, or "any" when unset. Returns { countryCode, cityCode } with cityCode nil for a
-- country only constraint, or nil when nothing is set.
local function parseSelectedLocationOutput(out, ok)
  if not ok or not out then return nil end
  local rest = out:match("Location:%s*(.-)\n")
  if not rest then return nil end
  local city, country = rest:match("^city%s+(%S+),%s*(%a%a)")
  if city and country then return { countryCode = country, cityCode = city } end
  local c = rest:match("^country%s+(%a%a)")
  if c then return { countryCode = c } end
  return nil
end

function M.selectedLocation()
  if not cli then return nil end
  local out, ok = hs.execute(cli .. " relay get 2>/dev/null")
  return parseSelectedLocationOutput(out, ok)
end

-- Run a CLI subcommand off the main thread and fire the callback on completion. The
-- callback lands on the main thread, so it is safe to touch the UI from it.
--
-- start()'s own return is checked now, the phase three verification rider. hs.task:start()
-- answers nil rather than raising when the task never actually launches, a missing
-- executable or a spawn the OS refused among the causes, and every caller here used to trust
-- the task object it got back from hs.task.new regardless, so a launch failure left the
-- callback never called at all, silently, with nothing to tell connect, disconnect, or
-- setLocation their own action never ran.
local function runAsync(args, cb)
  if not cli then
    if cb then cb(false, "mullvad not installed") end
    return
  end
  local t = hs.task.new(cli, function(rc, _, se)
    if cb then cb(rc == 0, (se ~= nil and se ~= "" and se) or nil) end
  end, args)
  if not t:start() then
    if cb then cb(false, "mullvad failed to launch") end
  end
end

-- status and selectedLocation's own async doors, phase three review finding eleven, through
-- hs.task rather than hs.execute, the identical mechanism the relay list below already runs
-- its own read through. No shell string and no output redirect are needed the way the
-- synchronous reads above use them, since hs.task already answers stdout and stderr as two
-- separate values rather than one combined string a shell pipe would otherwise have to be
-- asked to separate. Each shares its own parse function with its synchronous counterpart, so
-- the two can never read the identical output two different ways.
--
-- Each now checks start()'s own return, the phase three verification rider. A task that never
-- launches used to leave its callback never called, which for these two feeds straight into
-- Vpn.init.lua's own M.prepare, whose three way countdown has no other way to learn a leg is
-- never coming, so a launch failure here degrades to the same unavailable answer a missing
-- cli already gives rather than to a fetch nothing can ever finish.
function M.statusAsync(cb)
  if not cli then
    if cb then cb({ state = "unavailable" }) end
    return
  end
  local t = hs.task.new(cli, function(rc, so, _)
    if cb then cb(parseStatusOutput(so, rc == 0)) end
  end, { "status", "-j" })
  if not t:start() then
    if cb then cb({ state = "unavailable" }) end
  end
end

function M.selectedLocationAsync(cb)
  if not cli then
    if cb then cb(nil) end
    return
  end
  local t = hs.task.new(cli, function(rc, so, _)
    if cb then cb(parseSelectedLocationOutput(so, rc == 0)) end
  end, { "relay", "get" })
  if not t:start() then
    if cb then cb(nil) end
  end
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
  if not t:start() then
    if cb then cb({}) end
  end
end

return M
