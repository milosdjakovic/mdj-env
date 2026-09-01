--- === Speedtest.util ===
---
--- Stateless formatting and the one question of which network this is. Dot called, no
--- policy, no state, so both the list and the pane can read it without either owning it.
---
--- Naming a network is the awkward part and it is worth saying why rather than leaving the
--- next reader to rediscover it. macOS stopped handing out the SSID to an application that
--- does not hold Location Services, and it does not refuse, it answers a string of spaces,
--- so a plain check for nil reads a blank name as a real one. Hammerspoon on this machine
--- has never been asked for that permission, so the honest position is that the name may
--- simply not be knowable.
---
--- What is always knowable is the AirPort ProfileID, a stable hash of the network profile
--- that survives reconnecting and needs no permission at all, so identity keys on that and
--- the readable name is a separate question layered on top. That split is what lets the
--- history stay correctly separated per network even when every one of them has to be shown
--- under a made up label, and it is why a person can rename one without anything moving.

local M = {}

--------------------------------------------------------------------------------
-- Figures
--------------------------------------------------------------------------------

--- util.mbps(bits) -> number or nil
--- Every throughput the tool reports is in bits per second, confirmed against its own
--- printed summary, where a dl_throughput of 21697432 prints as 21.697 Mbps.
function M.mbps(bits)
  if type(bits) ~= "number" then return nil end
  return bits / 1000000
end

--- util.rate(bits) -> "10.9" or nil
--- The number alone, since every caller pairs it with its own wording. A fast link loses
--- the decimal, which is noise at three figures and costs a column the row needs.
function M.rate(bits)
  local mbps = M.mbps(bits)
  if not mbps then return nil end
  if mbps >= 100 then return string.format("%.0f", mbps) end
  return string.format("%.1f", mbps)
end

--- util.rating(rpm) -> "low", "medium", "high", or nil
--- The word the tool prints beside its own responsiveness figure. It is not in the machine
--- readable output, only in the human summary, so it has to be banded here. The low band is
--- the one verified against the real tool, 69 RPM printing as Low, and the two above it come
--- from Apple's own published banding. The number is always shown beside the word for
--- exactly that reason, so a band drawn a little wrong never misleads on its own.
function M.rating(rpm)
  if type(rpm) ~= "number" then return nil end
  if rpm < 100 then return "low" end
  if rpm < 450 then return "medium" end
  return "high"
end

--- util.loadedMs(rpm) -> number or nil
--- Round trips per minute converted back to the milliseconds one round trip took, which is
--- the same arithmetic the tool's own summary does, 69 RPM printing as 865 ms.
function M.loadedMs(rpm)
  if type(rpm) ~= "number" or rpm <= 0 then return nil end
  return 60000 / rpm
end

--------------------------------------------------------------------------------
-- Samples
--------------------------------------------------------------------------------

--- util.percentile(sorted, p) -> number or nil, p between 0 and 1 over an ascending list.
function M.percentile(sorted, p)
  local n = #sorted
  if n == 0 then return nil end
  local idx = math.ceil(p * n)
  if idx < 1 then idx = 1 end
  if idx > n then idx = n end
  return sorted[idx]
end

--- util.summarise(samples) -> { min, med, p95, max } or nil
function M.summarise(samples)
  if type(samples) ~= "table" or #samples == 0 then return nil end
  local sorted = {}
  for i, v in ipairs(samples) do sorted[i] = v end
  table.sort(sorted)
  return {
    min = sorted[1],
    med = M.percentile(sorted, 0.5),
    p95 = M.percentile(sorted, 0.95),
    max = sorted[#sorted],
  }
end

--- util.downsample(samples, buckets) -> a fixed width list of means, oldest first.
--- A run answers as many latency samples as it happened to take, over a hundred in one real
--- run here, and storing that per run grows the file without growing what it says. A fixed
--- width strip keeps every record the same size forever, which is what makes a count cap an
--- honest bound on the file rather than a bound on the number of records alone.
function M.downsample(samples, buckets)
  if type(samples) ~= "table" or #samples == 0 then return nil end
  local n = #samples
  if n <= buckets then
    local out = {}
    for i, v in ipairs(samples) do out[i] = v end
    return out
  end
  local out = {}
  for b = 1, buckets do
    local from = math.floor((b - 1) * n / buckets) + 1
    local to = math.floor(b * n / buckets)
    if to < from then to = from end
    local sum, count = 0, 0
    for i = from, to do
      sum = sum + samples[i]
      count = count + 1
    end
    out[b] = sum / count
  end
  return out
end

--- util.median(values) -> number or nil
function M.median(values)
  local s = M.summarise(values)
  return s and s.med
end

--------------------------------------------------------------------------------
-- Time
--------------------------------------------------------------------------------

--- util.stamp(at) -> "1 Sep 15:48"
function M.stamp(at)
  if type(at) ~= "number" then return "" end
  local text = os.date("%d %b %H:%M", at)
  return (tostring(text):gsub("^0", ""))
end

--- util.relative(at, now) -> "2 minutes ago"
--- Falls back to the stamp past a week, since a run older than that is easier to place by
--- its date than by counting days back from today.
function M.relative(at, now)
  if type(at) ~= "number" then return "" end
  local delta = (now or os.time()) - at
  if delta < 45 then return "just now" end
  if delta < 90 then return "a minute ago" end
  local minutes = math.floor(delta / 60)
  -- Ninety seconds to two minutes floors to one, so the plural branch really is reachable with a
  -- one in it and really did print "1 minutes ago" before this line existed.
  if minutes == 1 then return "a minute ago" end
  if minutes < 60 then return minutes .. " minutes ago" end
  local hours = math.floor(delta / 3600)
  if hours < 24 then return hours == 1 and "an hour ago" or (hours .. " hours ago") end
  local days = math.floor(delta / 86400)
  if days == 1 then return "yesterday" end
  if days < 7 then return days .. " days ago" end
  return M.stamp(at)
end

--------------------------------------------------------------------------------
-- Which network this is
--------------------------------------------------------------------------------

-- A name macOS redacted comes back as blank or as spaces rather than as nil, so anything
-- with no visible character in it counts as absent. See this file's own header.
local function readable(text)
  if type(text) ~= "string" then return nil end
  if text:match("%S") == nil then return nil end
  return text
end

--- util.currentNetwork() -> { id, label, kind, iface, named }
--- id is stable and permission free, label is the best readable name available, and named
--- says whether that label is the network's real name or one this file made up. Answers a
--- none row rather than nil when nothing is connected, so every caller has a table.
function M.currentNetwork()
  local iface = hs.network.primaryInterfaces()
  if not iface then
    return { id = "none", label = "No network", kind = "none", named = false }
  end

  local details = hs.network.interfaceDetails(iface) or {}
  local air = details.AirPort
  if not air then
    return { id = "iface:" .. iface, label = iface, kind = "wired", iface = iface, named = true }
  end

  local ssid = readable(hs.wifi.currentNetwork()) or readable(air.SSID_STR)
  local profile = air.ProfileID
  local id = profile and ("wifi:" .. profile) or ("iface:" .. iface)
  local label = ssid
  if not label then
    -- Four characters of the profile hash, which is enough to tell two saved networks
    -- apart at a glance and short enough to sit in a row beside everything else.
    label = profile and ("Wi Fi " .. tostring(profile):sub(1, 4)) or "Wi Fi"
  end
  return { id = id, label = label, kind = "wifi", iface = iface, named = ssid ~= nil }
end

return M
