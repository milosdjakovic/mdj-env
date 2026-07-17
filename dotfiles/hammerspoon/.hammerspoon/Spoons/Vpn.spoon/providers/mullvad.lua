--- The Mullvad provider, the only file that knows the mullvad CLI. It implements the
--- VPN contract by shelling out. Availability is resolved once at load, the CLI path
--- found on PATH or in the common Homebrew locations, and when it is missing every
--- method degrades safely and available returns false so the root can log the reason.
--- Fast reads, status, run synchronously. Slow actions, connect and the relay list,
--- run through hs.task off the main thread so the UI never stalls, and their callback
--- lands back on the main thread.

local M = {}

local CANDIDATES = { "/opt/homebrew/bin/mullvad", "/usr/local/bin/mullvad" }

-- Resolve the CLI once. Prefer the known Homebrew paths, then fall back to a PATH
-- lookup through a login shell, since Hammerspoon's own PATH is minimal.
local function resolveCli()
  for _, p in ipairs(CANDIDATES) do
    if hs.fs.attributes(p) then return p end
  end
  local out, ok = hs.execute("command -v mullvad", true)
  if ok and out then
    local path = out:gsub("%s+$", "")
    if path ~= "" then return path end
  end
  return nil
end

local cli = resolveCli()

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
function M.reconnect(cb) runAsync({ "reconnect" }, cb) end

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
