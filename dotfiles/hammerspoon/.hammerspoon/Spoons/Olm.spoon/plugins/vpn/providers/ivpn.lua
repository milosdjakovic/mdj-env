--- The IVPN provider, the only file that knows the ivpn CLI. It implements the VPN
--- contract by shelling out, exactly as the Mullvad provider does, and it resolves
--- nothing itself. The CLI path is handed in through configure by the layer above, which
--- reads it from the shared dependency resolver, so no install location appears here and
--- the probing happens once for the whole config. Until a path is handed in every method
--- degrades safely and available returns false, so the composition root can log the reason
--- and the picker still opens.
---
--- The CLI needs no elevation. The daemon publishes its port and a secret in a world
--- readable file and the GUI talks to it the same way, so every command here runs as the
--- ordinary user.
---
--- This provider does NOT implement selectedLocation, and that absence is the reason the
--- contract stopped requiring it. Mullvad holds a persistent location constraint that can
--- be read back while disconnected, so it can say where a connect would go. IVPN holds no
--- such thing. Its own answer to that question lives in a root owned settings file this
--- layer may not read, and the CLI exposes no reader for it, which was rechecked against the
--- tool rather than assumed. Its status prints nothing about a location while the tunnel is
--- down, and no subcommand reports the last used parameters that connect -last acts on.
--- Faking one would mean guessing, so the method stays absent.
---
--- What that absence used to cost is gone, and it went by moving the question rather than by
--- answering it. connect takes the target as an argument now, so where a connect is going is
--- something the caller states rather than something this file has to read back, and a caller
--- holding its own record of the last place it was asked for gets a named connect on this
--- backend exactly as it does on the other one. The nil target path below is what remains of
--- the old behaviour, the fallback now rather than the only thing available.

local M = {}

-- The human name of this backend, for the control surface and the provider page, the
-- provider being the one place that knows it.
M.name = "IVPN"

-- What provides this backend when its CLI is absent, so the panel can explain itself and
-- the console line can name the gap. A plain fact about the backend and nothing more. How
-- the application is obtained belongs to the repository root, which maps this tool name to
-- a concrete install, so naming one here would be that answer written a second time in the
-- one layer that must not hold it.
M.install = {
  note = "The IVPN app provides the ivpn CLI.",
}

-- The name this CLI is declared under in the plugin's manifest, with unit naming this
-- provider. The layer above looks the path up by it, so the declaration and this file
-- agree on one spelling.
M.tool = "ivpn"

-- The resolved absolute path, handed in through configure. Nil means the CLI is absent,
-- which every method below already treats as unavailable.
local cli = nil

-- The last location list this provider parsed, kept so a connected status can name where
-- the tunnel is. The CLI reports the connected server as a gateway hostname and nothing
-- else, so the city and the country are recovered by matching that hostname against the
-- list this provider already had to parse. Provider local on purpose, since the hostname
-- vocabulary is this file's own and no layer above should learn it. Empty until the first
-- list lands, which is why every read below falls back to the bare hostname.
local byHost = {}

--- M.configure(opts) - accept the resolved CLI path. Called by the plugin's own start with
--- whatever the shared resolver found, so this file performs no lookup of its own.
function M.configure(opts)
  cli = (opts or {}).path
  return M
end

function M.available()
  return cli ~= nil
end

--------------------------------------------------------------------------------
-- Status
--------------------------------------------------------------------------------

-- The state words the CLI prints, mapped onto the contract's own vocabulary. Reconnecting
-- is folded into connecting, since to a person watching a list they are the same waiting.
local STATE = {
  CONNECTED = "connected",
  CONNECTING = "connecting",
  RECONNECTING = "connecting",
  DISCONNECTED = "disconnected",
  DISCONNECTING = "disconnecting",
}

-- Shared by the synchronous read and its async counterpart, so the two can never parse the
-- identical CLI output two different ways.
--
-- The output is padded label and value lines rather than anything machine readable, the CLI
-- offering no structured form at all, so the state comes from the VPN line and the server
-- from the Server line. A missing VPN line is what a daemon that is not answering looks
-- like, since the CLI prints a failure sentence instead of the block, so that case answers
-- unavailable rather than guessing at disconnected. Reporting disconnected there would be
-- confidently wrong in the one situation where being wrong matters, a tunnel that is
-- actually up while the daemon is merely unreachable.
local function parseStatusOutput(out, ok)
  if not ok or not out or out == "" then return { state = "unavailable" } end
  local word = out:match("VPN%s*:%s*(%u+)")
  if not word then return { state = "unavailable" } end
  local s = { state = STATE[word] or "unknown" }
  local host = out:match("Server%s*:%s*(%S+)")
  if host then
    s.hostname = host
    local known = byHost[host]
    if known then
      s.city = known.city
      s.country = known.country
    end
  end
  return s
end

-- Read the tunnel state now. A single fast call, so synchronous, kept for a caller off the
-- hot path. The engine's own onChange is one.
function M.status()
  if not cli then return { state = "unavailable" } end
  local out, ok = hs.execute(cli .. " status 2>/dev/null")
  return parseStatusOutput(out, ok)
end

-- The async door, for a caller that must never block the main thread while it draws. The
-- plugin's own prepare is the one that matters, since it runs on the keypress that reveals
-- the list. Shares its parse with the synchronous read above.
--
-- start()'s own return is checked, since hs.task:start() answers nil rather than raising
-- when a task never launches, and an unchecked launch failure leaves a callback that is
-- never going to be called with nothing anywhere saying so. A failed launch answers the
-- same degraded value a missing CLI already answers.
function M.statusAsync(cb)
  if not cli then
    if cb then cb({ state = "unavailable" }) end
    return
  end
  local t = hs.task.new(cli, function(rc, so, _)
    if cb then cb(parseStatusOutput(so, rc == 0)) end
  end, { "status" })
  if not t:start() then
    if cb then cb({ state = "unavailable" }) end
  end
end

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------

-- The sentences the CLI prints when a command did not do what was asked. They are matched
-- because the exit code cannot be trusted here, a connect to a location that matches no
-- server still exits zero, which was measured rather than assumed. So a rc of zero alone
-- would report every such failure as a success.
--
-- This list is deliberately short and deliberately not exhaustive. The real confirmation is
-- the status refresh the engine already runs after every action, which reads the tunnel
-- rather than a sentence, so a failure sentence nobody here recognised still surfaces as a
-- state that did not change. These exist to make the common mistakes answer promptly rather
-- than to be the only thing standing between a failure and a wrong report.
local FAILURES = {
  "No servers found",
  "Please specify server more correctly",
  "Not logged in",
  "Failed to connect to service",
}

local function failureIn(out)
  if not out or out == "" then return nil end
  for _, sentence in ipairs(FAILURES) do
    if out:find(sentence, 1, true) then return sentence end
  end
  return nil
end

-- Run a CLI subcommand off the main thread and fire the callback on completion. The
-- callback lands on the main thread, so it is safe to touch the UI from it. Both streams
-- are searched for a failure sentence, since the CLI writes some of them to stdout.
local function runAsync(args, cb)
  if not cli then
    if cb then cb(false, "ivpn not installed") end
    return
  end
  local t = hs.task.new(cli, function(rc, so, se)
    if not cb then return end
    local bad = failureIn(so) or failureIn(se)
    if bad then
      cb(false, bad)
    elseif rc ~= 0 then
      cb(false, (se ~= nil and se ~= "" and se) or nil)
    else
      cb(true, nil)
    end
  end, args)
  if not t:start() then
    if cb then cb(false, "ivpn failed to launch") end
  end
end

--- M.connect(target, cb) - bring the tunnel up at target. The caller hands back the two codes
--- off the row this provider itself produced, so cityCode is the full gateway hostname this
--- provider put there. It is matched against the server hostname rather than against a city or
--- a country name, because those are ambiguous in this CLI's own vocabulary and a hostname is
--- not. A country filter of us matches every American city, and even a gateway prefix is
--- ambiguous, us-ca being a prefix of both us-ca and us-ca-sjc, so the full hostname is the
--- only filter that names exactly one server.
---
--- One command, not two. Unlike the other backend there is no separate constraint to set
--- before connecting, connect takes the location directly and switching an already connected
--- tunnel is the same command.
---
--- A nil target falls back to the last used parameters the daemon itself holds, which is all
--- this backend can offer for go wherever you would go on your own, since it exposes no reader
--- for what those parameters are. It is reached only when the caller has never named a place
--- through this tool, and on a machine that has never connected at all the CLI reports that it
--- has no last, which is correct and self limiting, since choosing a location is the normal
--- first move anyway.
function M.connect(target, cb)
  local host = target and target.cityCode
  if host and host ~= "" then
    runAsync({ "connect", "-l", host }, cb)
    return
  end
  runAsync({ "connect", "-last" }, cb)
end

function M.disconnect(cb) runAsync({ "disconnect" }, cb) end

--------------------------------------------------------------------------------
-- Locations
--------------------------------------------------------------------------------

-- Parse `ivpn servers` into a flat list of location entries. The output is a padded table
-- with pipe separated columns, protocol, location, city, country, ISP, and tunnel address
-- family, with one header row.
--
-- Only the WireGuard rows are kept. Every location appears once per protocol, so reading
-- both would list all of them twice, and the protocol is not a choice this list offers.
-- WireGuard rather than OpenVPN because it is this backend's own default and the only one
-- of the two whose rows carry IPv6.
--
-- The city column carries the country code in parentheses, and the city name itself may
-- contain a comma, Los Angeles, CA being the ordinary case, so the label is built by
-- joining the whole city text to the country name rather than by splitting on commas.
--
-- The id is the gateway hostname, which is stable, unique, and the same thing the connect
-- filter takes. cityCode carries it too, since that is what connect above reads off a target
-- and the caller hands exactly those two codes back. detail carries it a third time as the
-- row's own subtitle text, which is the provider describing its location in its own
-- vocabulary rather than the plugin assuming every backend spells one the same way.
local function parseServers(output)
  local list = {}
  for line in (output .. "\n"):gmatch("(.-)\n") do
    local fields = {}
    for cell in line:gmatch("([^|]+)") do
      fields[#fields + 1] = cell:match("^%s*(.-)%s*$")
    end
    local protocol, host, cityCell, country = fields[1], fields[2], fields[3], fields[4]
    if protocol == "WireGuard" and host and cityCell and country then
      local city, code = cityCell:match("^(.-)%s*%((%a%a)%)$")
      if city and code then
        local cc = code:lower()
        list[#list + 1] = {
          id = host,
          label = city .. ", " .. country,
          country = country, countryCode = cc,
          city = city, cityCode = host,
          detail = host,
        }
      end
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
    local list = (rc == 0 and so) and parseServers(so) or {}
    -- Remember the hostname to place mapping, so a connected status can name where the
    -- tunnel is rather than only which gateway it reached. Rebuilt wholesale on every
    -- fetch, so a location that goes away does not linger.
    byHost = {}
    for _, loc in ipairs(list) do byHost[loc.id] = loc end
    if cb then cb(list) end
  end, { "servers" })
  if not t:start() then
    if cb then cb({}) end
  end
end

return M
