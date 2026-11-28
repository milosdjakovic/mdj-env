--- The keep awake row, the grammar and the words, pure, so test/fixtures/keepawake/rows.json is
--- recorded from it and Olm.app's port, app/Plugins/KeepAwake/Grammar.swift, is checked against it.
--- AGENTS.md beside this file has why each rule is what it is. It reads the time only through the
--- clock it is handed, now, date and time shaped as os.time and os.date, so a check can name its
--- zone. Rows.localClock is the Mac's.

local Rows = {}

Rows.localClock = {
  now = function() return os.time() end,
  date = function(fmt, ts) return os.date(fmt, ts) end,
  time = function(t) return os.time(t) end,
}

--- Rows.utcClock(now) -> a clock standing at now in UTC, for the fixture and its checks, so a
--- recording reads the same on a Mac in any zone. time is os.time's, a missing hour noon.
function Rows.utcClock(now)
  local function days(y, m, d)
    y = m <= 2 and y - 1 or y
    local era = (y >= 0 and y or y - 399) // 400
    local yoe = y - era * 400
    local doy = (153 * (m + (m > 2 and -3 or 9)) + 2) // 5 + d - 1
    local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
    return era * 146097 + doe - 719468
  end
  return {
    now = function() return now end,
    date = function(fmt, ts) return os.date("!" .. fmt, ts) end,
    time = function(t)
      return days(t.year, t.month, t.day) * 86400 + (t.hour or 12) * 3600 + (t.min or 0) * 60 + (t.sec or 0)
    end,
  }
end

-- The safety rail on a duration, a month. Not a product limit but a bound so an absurd number like
-- 999999m never reaches os.date, which the visible resolved value already makes self correcting
-- long before this.
local MAX_SECS = 31 * 86400

-- The format examples as a subtitle fragment, shared by the Activate row and the two hint rows so
-- the wording lives in one place. The clock is 24 hour so the format is unambiguous.
local EXAMPLES = "a time like 18:45, or 2h30m as a duration"

-- Render an absolute end time as a label that names the day once it is not today, so a long hold
-- reads honestly rather than as a bare clock that could be any day. The time alone when it lands
-- today, "tomorrow HH:MM" the next day, and the full date beyond that. The typed rows and the
-- running status share this, so the wording lives in one place.
local function endLabel(ts, clock)
  local function dayStart(t) return clock.time({ year = t.year, month = t.month, day = t.day, hour = 0 }) end
  local now = clock.now()
  local days = math.floor((dayStart(clock.date("*t", ts)) - dayStart(clock.date("*t", now))) / 86400 + 0.5)
  if days <= 0 then return clock.date("%H:%M", ts) end
  if days == 1 then return "tomorrow " .. clock.date("%H:%M", ts) end
  return clock.date("%a %d %b %Y, %H:%M", ts)
end

-- The live status as a short line for the primary row subtitle. Off when nothing is held, On with
-- no bound when indefinite, and On until the clock with the minutes left while a timed session runs,
-- collapsing to just the clock once more than an hour remains.
function Rows.statusText(s, clock)
  clock = clock or Rows.localClock
  if not s.active then return "Currently off. Stays awake for good." end
  if not s.expiry then return "On, indefinite" end
  local rem = s.expiry - clock.now()
  if rem <= 0 then return "Ending" end
  local hh = endLabel(s.expiry, clock)
  local mins = math.floor(rem / 60)
  if mins < 60 then
    return string.format("On until %s, %d min left", hh, math.max(1, mins))
  end
  return "On until " .. hh
end

-- The next occurrence of a 24 hour clock time, rolling to tomorrow when it already passed today, so
-- 09:00 typed in the afternoon means tomorrow morning.
local function nextOccurrence(h, m, clock)
  local now = clock.now()
  local t = clock.date("*t", now)
  t.hour, t.min, t.sec = h, m, 0
  local ts = clock.time(t)
  if ts <= now then ts = ts + 86400 end
  return ts
end

-- Parse a clock value, HH:MM or H:MM, into hours and minutes, or nil when it is not a valid time.
-- The colon is required, which is what keeps a clock from colliding with a duration.
local function parseClock(q)
  local h, m = q:match("^(%d%d?):(%d%d)$")
  if not h then return nil end
  h, m = tonumber(h), tonumber(m)
  if h > 23 or m > 59 then return nil end
  return h, m
end

-- Parse a duration value into a positive second span, or nil when it is not one. Accepts an hours
-- part, a minutes part, or both in that order and at most one of each, so 2h, 90m, and 1h30m pass
-- while a repeat or a swapped order like 18h20h, 20m30m, or 30m2h fails, each pattern anchored so
-- nothing is silently dropped. A lone minutes part may exceed 59, since 120m is two hours, but when
-- hours are also written the minutes must be under 60, since 2h90m is a typo, not a value. A span
-- past the safety rail is rejected.
local function parseDuration(q)
  local h, m = q:match("^(%d+)h(%d+)m$")
  if h then
    m = tonumber(m)
    if m > 59 then return nil end
    local secs = tonumber(h) * 3600 + m * 60
    return (secs > 0 and secs <= MAX_SECS) and secs or nil
  end
  h = q:match("^(%d+)h$")
  if h then
    local secs = tonumber(h) * 3600
    return (secs > 0 and secs <= MAX_SECS) and secs or nil
  end
  m = q:match("^(%d+)m$")
  if m then
    local secs = tonumber(m) * 60
    return (secs > 0 and secs <= MAX_SECS) and secs or nil
  end
  return nil
end

-- A bare number, digits only with no colon and no unit, read as a duration in hours, but only once
-- it cannot be a clock hour, meaning 24 and up, since 24:00 is not a valid time. A number 0 to 23
-- returns nil, since it may still be the start of a clock like 18:45, and the caller then shows a
-- keep typing hint rather than guessing. A span past the rail is rejected so the caller can mark it
-- an error rather than a value.
local function parseBareHours(q)
  local n = q:match("^(%d+)$")
  if not n then return nil end
  n = tonumber(n)
  if n < 24 then return nil end
  local secs = n * 3600
  return secs <= MAX_SECS and secs or nil
end

-- Whether a query is still forming toward a value rather than malformed, which the caller shows as
-- a keep typing hint instead of an error. A bare hour under 24 that could still gain a colon or a
-- unit, or a clock in progress like 18: or 18:4 that has the colon but not yet both minute digits,
-- its hour in range.
local function isIncomplete(q)
  local n = q:match("^(%d+)$")
  if n then return tonumber(n) < 24 end
  local hh = q:match("^(%d%d?):(%d?)$")
  return hh ~= nil and tonumber(hh) <= 23
end

-- A second span as a compact human label, 1h 30m, 2h, or 45m, dropping a zero part.
local function humanSpan(secs)
  local h = math.floor(secs / 3600)
  local m = math.floor((secs % 3600) / 60)
  if h > 0 and m > 0 then return string.format("%dh %dm", h, m) end
  if h > 0 then return string.format("%dh", h) end
  return string.format("%dm", m)
end

--- Rows.line(query, status, clock) -> row
--- The single row, whose shape follows the field. An empty field is the state toggle, Stop Keeping
--- Awake while a session runs with the live status beneath, and Keep Awake Indefinitely while off
--- with the format examples beneath. A valid clock morphs it into a hold until that time and a valid
--- duration, an h or m span or a bare number of hours too large to be a clock, into a hold for that
--- span, each naming the concrete end and its day once it is not today. A value still forming is a
--- disabled keep typing hint, and anything malformed a disabled error row, which keeps Return from
--- applying an empty or half typed value.
function Rows.line(query, s, clock)
  clock = clock or Rows.localClock
  local q = (query or ""):gsub("%s+", "")

  if q == "" then
    if s.active then
      return { title = "Stop Keeping Awake", subTitle = Rows.statusText(s, clock), icon = "off", item = { id = "off" } }
    end
    return { title = "Keep Awake Indefinitely", subTitle = "Specify " .. EXAMPLES, icon = "on", item = { id = "indefinite" } }
  end

  local now = clock.now()
  local h, m = parseClock(q)
  if h then
    local ts = nextOccurrence(h, m, clock)
    return { title = "Keep Awake until " .. endLabel(ts, clock), subTitle = "In " .. humanSpan(ts - now), icon = "clock",
      item = { id = "until", ts = ts } }
  end

  local secs = parseDuration(q) or parseBareHours(q)
  if secs then
    return { title = "Keep Awake for " .. humanSpan(secs), subTitle = "Ends " .. endLabel(now + secs, clock),
      icon = "duration", item = { id = "for", secs = secs } }
  end

  if isIncomplete(q) then
    return { title = "Keep typing", subTitle = EXAMPLES, icon = "hint", enabled = false, item = { id = "hint" } }
  end

  return { title = "Not a time or duration", subTitle = EXAMPLES, icon = "error", enabled = false, item = { id = "hint" } }
end

return Rows
