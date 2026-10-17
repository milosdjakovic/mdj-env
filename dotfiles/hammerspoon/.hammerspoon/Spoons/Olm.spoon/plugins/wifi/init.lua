--- === Wifi ===
---
--- The current Wi-Fi network and every network in range, as one list. The first row is the
--- network this Mac is on, and choosing it disconnects. Every row below it is a network a
--- scan found, saved ones first, and choosing one joins it. A saved network joins with the
--- password the system already holds, and an unsaved secured one asks for its password first.
---
--- Reading is hs.wifi and joining is networksetup through a task. hs.wifi can join too, but
--- it holds the main thread for as long as the association takes, which is seconds, and every
--- key on the machine would wait with it.
---
--- A scan takes several seconds, so it runs in the background each time the list is shown and
--- the previous scan stays on screen until it lands. Names need Location Services, and without
--- that grant macOS answers blanks rather than refusing, so a blank is read as no name. Whether
--- the grant is held is judged from those answers rather than asked, because
--- hs.location.authorizationStatus says undefined in a fresh process until location updates
--- have been started once, however long ago the grant was given.

local M = { name = "Wifi", version = "1.0", author = "Milos Djakovic", license = "MIT" }

local cfg = {}

-- How long a scan may take before it is given up on, so a scan that never answers cannot
-- leave the list waiting forever. A scan measured at about eight seconds on this machine.
local SCAN_TIMEOUT = 20

-- How long a landed scan counts as current for the launcher scope, which is asked for rows on
-- every keystroke and every redraw and so cannot start a scan each time it is asked.
local SCAN_FRESH = 30

-- How long a network stays listed after it was last seen. A scan reports only part of what is
-- in range, measured as a 5 GHz network a few metres away missing from one scan and present
-- in the one before, so the list is what recent scans saw together rather than the last one.
local SEEN_FOR = 120

-- Every network seen recently, one entry per name, each stamped with when it was last seen.
local sightings = {}
-- Whether any scan has landed yet, so the list can say it is still looking.
local scannedOnce = false
-- The names this Mac has saved, read alongside each scan.
local saved = {}
local scanning = false
-- When the last scan landed, for the freshness check above.
local scannedAt = 0
-- Redraw callbacks waiting on the scan in flight, from the launcher scope.
local waiting = {}
-- The network a join is under way for, so its row can say so and a second pick is refused.
local joining = nil
-- Set once an answer came back without names, joined with no name or a scan of nameless
-- networks, which is how a missing Location Services grant shows itself.
local withheld = false

--------------------------------------------------------------------------------
-- Reading the interface
--------------------------------------------------------------------------------

local function iface()
  local all = hs.wifi.interfaces()
  return all and all[1] or nil
end

-- A name, or nil when macOS withheld it. Without Location Services the answer is a string of
-- spaces rather than nil, so an all blank string counts as no name.
local function readable(name)
  if type(name) ~= "string" or not name:find("%S") then return nil end
  return name
end

local function associated(details)
  return details.power and (details.transmitRate or 0) > 0
end

local function strength(rssi)
  if type(rssi) ~= "number" or rssi == 0 then return nil end
  if rssi >= -60 then return "strong signal" end
  if rssi >= -70 then return "good signal" end
  if rssi >= -80 then return "fair signal" end
  return "weak signal"
end

local function has(list, word)
  for _, v in ipairs(list or {}) do
    if v == word then return true end
  end
  return false
end

-- How a network is joined, judged from the security modes a scan reports. Open needs nothing,
-- personal needs a password, and enterprise needs a login networksetup cannot give, so that
-- one is left to System Settings.
local function security(modes)
  if has(modes, "Enterprise") then return "enterprise" end
  if has(modes, "None") or #(modes or {}) == 0 then return "open" end
  return "personal"
end

--------------------------------------------------------------------------------
-- Scanning
--------------------------------------------------------------------------------

local function settle()
  scanning = false
  if cfg.redrawPresented then cfg.redrawPresented("wifi") end
  local callbacks = waiting
  waiting = {}
  for _, fn in ipairs(callbacks) do fn() end
end

-- One entry per name, keeping the strongest sighting, since a network with several access
-- points answers once per access point.
local function reduce(found)
  local byName, out = {}, {}
  for _, n in ipairs(found or {}) do
    local name = readable(n.ssid)
    if name then
      local seen = byName[name]
      if not seen then
        seen = { name = name, rssi = n.rssi, kind = security(n.security) }
        byName[name] = seen
        out[#out + 1] = seen
      elseif (n.rssi or -999) > (seen.rssi or -999) then
        seen.rssi = n.rssi
      end
    end
  end
  return out
end

local function sight(entry)
  local prior = sightings[entry.name]
  sightings[entry.name] = {
    name = entry.name,
    rssi = entry.rssi or (prior and prior.rssi),
    kind = entry.kind or (prior and prior.kind) or "personal",
    at = hs.timer.secondsSinceEpoch(),
  }
end

local function nearby()
  local now, out = hs.timer.secondsSinceEpoch(), {}
  for name, n in pairs(sightings) do
    if now - n.at <= SEEN_FOR then out[#out + 1] = n else sightings[name] = nil end
  end
  return out
end

local function readSaved(device, done)
  local tool = cfg.deps and cfg.deps.path("networksetup")
  if not tool then return done({}) end
  local task = hs.task.new(tool, function(_, out)
    local names = {}
    for line in (out or ""):gmatch("[^\n]+") do
      local name = line:match("^%s+(.-)%s*$")
      if name and name ~= "" then names[name] = true end
    end
    done(names)
  end, { "-listpreferredwirelessnetworks", device })
  if not task:start() then done({}) end
end

-- Starts a scan unless one is already running, and calls onDone once it lands or times out.
-- Every caller waiting on the same scan is called back, rather than the second one dropped.
local function scan(onDone)
  if onDone and not has(waiting, onDone) then waiting[#waiting + 1] = onDone end
  if scanning then return end
  local device = iface()
  if not device or not hs.wifi.interfaceDetails(device).power then
    scannedOnce = true
    return settle()
  end
  scanning = true

  local landed = false
  cfg.after(SCAN_TIMEOUT, function()
    if landed then return end
    landed = true
    settle()
  end)

  readSaved(device, function(names)
    saved = names
    hs.wifi.backgroundScan(function(found)
      if landed then return end
      landed = true
      -- A scan started soon after another answers from a cache with every name stripped,
      -- measured as dozens of nameless networks within milliseconds, even with the grant
      -- held. So a scan with no names never replaces a list that has them. It means the grant
      -- is missing only when the current network is nameless too.
      local list = reduce(found)
      scannedAt = hs.timer.secondsSinceEpoch()
      scannedOnce = true
      if #list > 0 then
        for _, n in ipairs(list) do sight(n) end
        withheld = false
      else
        if #(found or {}) > 0 and not readable(hs.wifi.currentNetwork(device)) then withheld = true end
      end
      settle()
    end, device)
  end)
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function currentRow(device, current)
  local details = hs.wifi.interfaceDetails(device)
  if not details.power then
    return { title = "Wi-Fi is off", subTitle = "Turn it on",
             icon = "off", item = { id = "power" } }
  end
  if not current then
    -- Joined but nameless means the name was withheld, not that nothing is joined.
    if associated(details) then
      withheld = true
      return { title = "Connected", subTitle = "Name hidden, choose to disconnect",
               icon = "connected", item = { id = "disconnect" } }
    end
    return { title = "Not connected", subTitle = "Pick a network below",
             icon = "network", enabled = false, item = { id = "none" } }
  end
  local signal = strength(details.rssi)
  return { title = current, subTitle = "Connected" .. (signal and (", " .. signal) or "") .. ", choose to disconnect",
           icon = "connected", item = { id = "disconnect", name = current } }
end

local function networkRow(n)
  local parts = {}
  if joining == n.name then
    parts[#parts + 1] = "joining"
  elseif saved[n.name] then
    parts[#parts + 1] = "saved"
  elseif n.kind == "open" then
    parts[#parts + 1] = "open"
  elseif n.kind == "enterprise" then
    parts[#parts + 1] = "enterprise, join it in System Settings"
  else
    parts[#parts + 1] = "secured"
  end
  parts[#parts + 1] = strength(n.rssi)
  local sub = table.concat(parts, ", ")
  sub = sub:sub(1, 1):upper() .. sub:sub(2)
  local usable = saved[n.name] or n.kind ~= "enterprise"
  return { title = n.name, subTitle = sub, icon = saved[n.name] and "saved" or "network",
           enabled = usable and true or false,
           item = { id = "join", name = n.name, kind = n.kind } }
end

local function rows()
  local device = iface()
  if not device then
    return { { title = "No Wi-Fi hardware", subTitle = "This Mac reports no wireless interface",
               icon = "warn", enabled = false, item = { id = "none" } } }
  end

  local current = readable(hs.wifi.currentNetwork(device))
  -- The network this Mac is on is in range by definition, so it counts as a sighting, and
  -- leaving it keeps it listed for as long as any other recent sighting.
  if current then
    withheld = false
    sight({ name = current, rssi = hs.wifi.interfaceDetails(device).rssi })
  end
  local out = { currentRow(device, current) }

  if withheld then
    out[#out + 1] = { title = "Allow Location Services",
      subTitle = "macOS hides network names without it. If nothing asks, turn Hammerspoon on in " ..
                 "System Settings, Privacy and Security, Location Services",
      icon = "locked", item = { id = "locate" } }
    return out
  end

  if not hs.wifi.interfaceDetails(device).power then return out end

  local list = {}
  for _, n in ipairs(nearby()) do
    if n.name ~= current then list[#list + 1] = n end
  end
  table.sort(list, function(a, b)
    local sa, sb = saved[a.name] and 1 or 0, saved[b.name] and 1 or 0
    if sa ~= sb then return sa > sb end
    return (a.rssi or -999) > (b.rssi or -999)
  end)
  for _, n in ipairs(list) do out[#out + 1] = networkRow(n) end

  -- An empty list says whether a scan is still coming, since a scan after moving somewhere new
  -- takes seconds and a list showing only the current network reads as finished.
  if #list == 0 then
    if scanning or not scannedOnce then
      out[#out + 1] = { title = "Looking for networks", subTitle = "One moment",
                        icon = "loading", enabled = false, item = { id = "none" } }
    else
      out[#out + 1] = { title = "No other networks in range", icon = "network",
                        enabled = false, item = { id = "none" } }
    end
  end
  return out
end

--------------------------------------------------------------------------------
-- Acting
--------------------------------------------------------------------------------

local function askPassword(name)
  hs.focus()
  local button, text = hs.dialog.textPrompt("Join " .. name, "Enter the network password.",
    "", "Join", "Cancel", true)
  if button ~= "Join" or text == "" then return nil end
  return text
end

-- networksetup prints nothing when the join worked and a sentence when it did not, and exits
-- zero either way, so any output at all is the failure.
local function join(name, password, retried)
  local device = iface()
  local tool = cfg.deps and cfg.deps.path("networksetup")
  if not (device and tool) then
    hs.alert.show("Wi-Fi cannot join without networksetup")
    return
  end
  local args = { "-setairportnetwork", device, name }
  if password then args[#args + 1] = password end
  joining = name
  local task = hs.task.new(tool, function(code, out, err)
    joining = nil
    local said = ((out or "") .. (err or "")):gsub("^%s+", ""):gsub("%s+$", "")
    if code == 0 and said == "" then
      if cfg.redrawPresented then cfg.redrawPresented("wifi") end
      return
    end
    -- A saved network the system could not find a password for gets asked once, rather than
    -- failing on a password the person could simply type.
    if not password and not retried then
      cfg.after(0, function()
        local typed = askPassword(name)
        if typed then join(name, typed, true) end
      end)
      return
    end
    cfg.log.w("joining " .. name .. " failed, " .. said)
    hs.alert.show("Could not join " .. name)
  end, args)
  if not task:start() then
    joining = nil
    hs.alert.show("Could not join " .. name)
  end
end

local function onSelect(sel)
  if not sel then return end
  local device = iface()
  if sel.id == "disconnect" then
    hs.wifi.disassociate(device)
  elseif sel.id == "locate" then
    -- Starting location updates is what raises the prompt. Nothing here wants a location, so
    -- updates stop again once the prompt has had time to be answered, and the grant stays.
    hs.location.start()
    cfg.after(60, function() hs.location.stop() end)
  elseif sel.id == "power" then
    hs.wifi.setPower(true, device)
    sightings, scannedOnce = {}, false
  elseif sel.id == "join" then
    if joining then return end
    if saved[sel.name] or sel.kind == "open" then
      join(sel.name)
    else
      -- Deferred so the list is gone before the prompt takes the screen.
      cfg.after(0, function()
        local typed = askPassword(sel.name)
        if typed then join(sel.name, typed, true) end
      end)
    end
  end
end

--------------------------------------------------------------------------------
-- Public surface
--------------------------------------------------------------------------------

function M.show()
  if cfg.stagePresent then cfg.stagePresent("wifi") end
end

function M.onPresent()
  scan()
end

M.rows = rows
M.select = onSelect

function M.placeholder()
  return "Wi-Fi networks"
end

-- The launcher scope. A scan landing here redraws through the callback the launcher hands in,
-- since this is not the presentation redrawPresented knows about. The scope is asked again on
-- every keystroke and on that redraw too, so starting a scan whenever it is asked loops, each
-- landing asking for the next. A scan starts only when the last one is stale. The waiting rows
-- are pinned so the matcher cannot rank away the only rows there are.
function M.scopeRows(_, redraw)
  if hs.timer.secondsSinceEpoch() - scannedAt > SCAN_FRESH then scan(redraw) end
  local out = rows()
  for _, r in ipairs(out) do
    if r.item and r.item.id == "none" then r.pinned = true end
  end
  return out
end

function M:configure(opts)
  cfg = opts or {}
  return M
end

return M
