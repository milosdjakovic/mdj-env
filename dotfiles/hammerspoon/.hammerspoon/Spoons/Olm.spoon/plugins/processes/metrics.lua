--- Processes live metrics.
---
--- Samples CPU and memory for the rows the picker is showing, for exactly as long as
--- it is showing them. It knows nothing about the chooser and nothing about the
--- engine's sources. It is handed a supplier of targets, it samples, it keeps a short
--- history per target, and it hands the readings back. Dot called, like util and the
--- sources.
---
--- Nothing here runs while the picker is closed, and that is the shape of the module
--- rather than a detail of it. This config is always loaded, so a background poller
--- would burn battery every minute of every day to have numbers ready for the few
--- seconds the picker is actually open. So start and stop are the public lifecycle,
--- the surface owns them, and no sample is ever taken outside that window.
---
--- The CPU figure is a true instantaneous one, not the lifetime average ps prints in
--- its %cpu column. That column is total CPU time over total elapsed time since
--- launch, so a server that pinned a core during a build six hours ago still reports a
--- comfortable looking number, and one thrashing right now barely moves it. The only
--- honest reading is a difference, so two snapshots of cumulative CPU time are taken
--- and the delta is divided by the wall clock between them, which is what top does and
--- why top needs a moment before its first figure means anything.
---
--- Readings are aggregated over the process GROUP rather than the listening pid, for
--- the same reason a stop signals the group. A dev server is a supervisor chain and the
--- work rarely happens in the leaf holding the socket, the build worker beside it is
--- what pins a core, so a per pid figure would read as nearly idle for a tree busy
--- compiling. The group is also exactly the set a stop would take down, so the numbers
--- answer what you would reclaim. Summing resident memory across a group does double
--- count the pages its members share, overstating by roughly one runtime binary, and
--- that is the cheaper error than reporting one process out of five.

local metricsPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local util = loadfile(metricsPath .. "util.lua")()

local M = {}

local PS = "/bin/ps"

-- A plain ps with no command lines is a couple of tens of kilobytes and a dozen
-- milliseconds, and unlike the docker CLI it has no way to hang, so the timeout here
-- is a formality rather than the load bearing guard the scan timeout is. It stays a
-- constant instead of a knob because there is nothing to tune about it.
local SAMPLE_TIMEOUT = 4

-- Fallback policy, used when the composition root injects none. The weights in
-- particular are policy and belong in the config file, these values only keep the
-- module working on its own rather than standing in for a decision.
local DEFAULTS = {
  intervalSeconds = 1.5,
  historySamples = 60,
  cpuWeight = 0.7,
  memWeight = 0.3,
  memReferenceMb = 1024,
}

-- The first reading needs two snapshots, so a full interval of waiting would leave the
-- picker showing nothing at the moment it opens, which is the moment you look at it.
-- The second sample is therefore taken quickly and the cadence settles afterwards.
local WARMUP_SECONDS = 0.4

M._cfg = {}
for k, v in pairs(DEFAULTS) do M._cfg[k] = v end

M._running = false
M._timer = nil
M._targets = nil    -- injected supplier, called fresh on every tick
M._onTick = nil     -- injected, fired after each sample lands
M._prev = nil       -- the previous snapshot, the baseline every CPU delta is taken from
M._samples = 0
M._readings = {}    -- key -> { cpu, rss, score, at }
M._history = {}     -- key -> bounded list of readings, oldest first

--- metrics.configure(opts) - called by the composition root, never by the sampler's
--- consumer. Merged rather than replaced so a partial block still leaves the rest at
--- its default.
function M.configure(opts)
  for k, v in pairs(opts or {}) do
    if v ~= nil then M._cfg[k] = v end
  end
  return M
end

--------------------------------------------------------------------------------
-- Parsing
--------------------------------------------------------------------------------

-- Parse the accumulated CPU time ps prints into seconds. Kept local rather than put
-- beside util.etimeSeconds because this is the only consumer, and the two formats are
-- not the same shape despite looking alike. etime counts wall clock and rolls into
-- hours and days, while ps prints cputime as unbounded minutes then seconds and
-- hundredths, so a process that has burned six hours of CPU reads "365:41.80" with no
-- hours field at all. The leading day and hour fields are still handled, since another
-- ps could print them and a wrong figure would be worse than a missing one.
local function cpuSeconds(s)
  if not s then return nil end
  s = s:gsub("%s", "")
  local total = 0
  local days, rest = s:match("^(%d+)%-(.*)$")
  if days then
    total = tonumber(days) * 86400
  else
    rest = s
  end
  local fields = {}
  for field in rest:gmatch("[^:]+") do fields[#fields + 1] = field end
  if #fields == 0 then return nil end
  for i, field in ipairs(fields) do
    local n = tonumber(field)
    if not n then return nil end
    total = total + n * 60 ^ (#fields - i)
  end
  return total
end

-- One snapshot of the whole process table, with a pgid index so a group can be
-- resolved without a second pass. Command lines are deliberately not asked for, which
-- is what keeps this an order of magnitude smaller than the scan's process table and
-- cheap enough to repeat every second and a half.
--
-- The clock is the monotonic one rather than the wall clock. The elapsed time between
-- two snapshots is the denominator of every CPU figure, so a clock correction landing
-- between them would not just skew a reading, it could make it negative or enormous.
local function snapshot(out)
  local cpu, rss, group = {}, {}, {}
  for line in util.lines(out) do
    local pid, pgid, kb, time = line:match("^%s*(%d+)%s+(%d+)%s+(%d+)%s+(%S+)%s*$")
    if pid then
      pid, pgid = tonumber(pid), tonumber(pgid)
      cpu[pid] = cpuSeconds(time) or 0
      rss[pid] = tonumber(kb) or 0
      local members = group[pgid]
      if members then
        members[#members + 1] = pid
      else
        group[pgid] = { pid }
      end
    end
  end
  return { at = hs.timer.absoluteTime() / 1e9, cpu = cpu, rss = rss, group = group }
end

--------------------------------------------------------------------------------
-- Readings
--------------------------------------------------------------------------------

-- The pids one target covers, re-read from the live snapshot rather than trusted from
-- the scan, the same reason the stop re-reads the group before signalling it. A tree
-- grows and shrinks while the picker sits open, and a fixed member list would keep
-- charging a target for a worker that exited.
local function membersOf(snap, target)
  if target.pgid and snap.group[target.pgid] then return snap.group[target.pgid] end
  if target.pid and snap.rss[target.pid] then return { target.pid } end
  return nil
end

-- Blend the two figures into the one number the heat ordering sorts on. Each side is
-- normalised to its own unit first, one fully saturated core counts as 1.0 and
-- memReferenceMb of resident memory counts as 1.0, which is what makes two weights
-- over a percentage and a byte count mean anything at all. Without that step the
-- weights would be comparing 12.4 against 320000 and memory would win every time.
local function scoreOf(cpu, rssKb)
  local cfg = M._cfg
  local reference = (cfg.memReferenceMb or DEFAULTS.memReferenceMb) * 1024
  local cpuPart = (cfg.cpuWeight or DEFAULTS.cpuWeight) * ((cpu or 0) / 100)
  local memPart = (cfg.memWeight or DEFAULTS.memWeight) * ((rssKb or 0) / reference)
  return cpuPart + memPart
end

-- Bounded history, oldest first. A plain list with the front dropped rather than a
-- wrapped ring, because at this cap the shift costs nothing and the list is already in
-- the order a sparkline wants to draw it, while a real ring would hand its consumer a
-- wrapped array to unwrap first.
local function remember(key, reading)
  local ring = M._history[key]
  if not ring then
    ring = {}
    M._history[key] = ring
  end
  ring[#ring + 1] = reading
  local cap = M._cfg.historySamples or DEFAULTS.historySamples
  while #ring > cap do table.remove(ring, 1) end
end

-- Turn a snapshot into one reading per target, against the previous snapshot.
--
-- CPU is summed as per pid deltas rather than as the difference of two group totals,
-- and that is not a stylistic choice. A member that exited takes its accumulated time
-- out of the current total, so differencing the totals would report a large negative
-- spike every time a build worker finished. Only a pid present in both snapshots
-- contributes, so a member that appeared since the last tick contributes from the next
-- one, and a member that left simply stops contributing.
--
-- Memory needs no baseline, so it is published from the very first snapshot while CPU
-- waits for the second. A row therefore shows its footprint immediately on open and
-- gains its CPU figure a moment later, rather than showing nothing at all until two
-- samples are in.
local function apply(snap)
  local prev = M._prev
  local elapsed = prev and (snap.at - prev.at) or 0
  local readings, seen = {}, {}

  for _, target in ipairs(M._targets and M._targets() or {}) do
    local key = target.key
    local members = key and membersOf(snap, target)
    if members then
      seen[key] = true
      local rss, cpuDelta, paired = 0, 0, false
      for _, pid in ipairs(members) do
        rss = rss + (snap.rss[pid] or 0)
        local before = prev and prev.cpu[pid]
        local after = snap.cpu[pid]
        if before and after then
          paired = true
          -- Clamped rather than trusted. Cumulative CPU time cannot fall, so a
          -- negative delta means the pid was reused by a different process between
          -- snapshots and the two figures are not comparable at all.
          if after > before then cpuDelta = cpuDelta + (after - before) end
        end
      end
      local cpu = (paired and elapsed > 0) and (cpuDelta / elapsed * 100) or nil
      local reading = { cpu = cpu, rss = rss, score = scoreOf(cpu, rss), at = snap.at }
      readings[key] = reading
      if cpu then remember(key, reading) end
    end
  end

  -- Rebuilt rather than merged, so a row that has gone away takes its reading with it
  -- instead of leaving a stale figure behind, and its history is dropped with it so a
  -- long session cannot accumulate the remains of every server it ever saw.
  M._readings = readings
  for key in pairs(M._history) do
    if not seen[key] then M._history[key] = nil end
  end
  M._prev = snap
  M._samples = M._samples + 1
end

--------------------------------------------------------------------------------
-- The sampling loop
--------------------------------------------------------------------------------

local tick

-- Chained rather than hs.timer.doEvery, for two reasons that both matter. A sample is
-- an asynchronous shellout, so a fixed period timer could fire again while one is
-- still in flight and the deltas would be taken against a baseline that has already
-- moved. And because the next tick is only ever armed once the last one has landed,
-- a stop can never leave a timer behind, whichever point of the cycle it arrives at.
local function schedule()
  local interval = M._cfg.intervalSeconds or DEFAULTS.intervalSeconds
  local delay = (M._samples < 2) and WARMUP_SECONDS or interval
  M._timer = hs.timer.doAfter(delay, tick)
end

tick = function()
  M._timer = nil
  if not M._running then return end
  util.run(PS, { "-Ao", "pid=,pgid=,rss=,time=" }, SAMPLE_TIMEOUT, function(out)
    -- The picker can close while the shellout is in flight, and everything after this
    -- line is work for a surface that no longer exists.
    if not M._running then return end
    if out then
      apply(snapshot(out))
      if M._onTick then M._onTick() end
    end
    if M._running then schedule() end
  end)
end

--------------------------------------------------------------------------------
-- Public surface (dot-called)
--------------------------------------------------------------------------------

--- metrics.start(targets, onTick)
--- targets  supplier function() -> list of { key, pid, pgid }, called fresh on every
---          tick so a rescan that replaces the rows needs no restart here
--- onTick   optional, fired after each sample lands so the surface can redraw
---
--- Idempotent. Calling it again while running only re-points the two collaborators,
--- which is what a rescan wants, since restarting would throw away the baseline and
--- blank every CPU figure for a tick.
function M.start(targets, onTick)
  M._targets = targets
  M._onTick = onTick
  if M._running then return M end
  M._running = true
  M._prev = nil
  M._samples = 0
  tick()
  return M
end

--- metrics.stop() - end sampling and forget everything.
---
--- The history goes with it deliberately. Sampling only happens while the picker is
--- open, so keeping a trail across a close would leave a hole in the middle of it that
--- a sparkline has no way to draw honestly, and the last readings would be minutes
--- stale by the next open while still looking live.
function M.stop()
  M._running = false
  if M._timer then
    M._timer:stop()
    M._timer = nil
  end
  M._prev = nil
  M._readings = {}
  M._history = {}
  M._samples = 0
  return M
end

--- metrics.reading(key) -> { cpu, rss, score, at } or nil
--- The latest reading for a target. cpu is nil until two snapshots exist, rss is a
--- group total in kilobytes, score is the blended figure the heat ordering sorts on.
function M.reading(key)
  return key and M._readings[key] or nil
end

--- metrics.history(key) -> list of readings, oldest first, or nil
--- The recent trail for a target, bounded by historySamples. Only readings carrying a
--- CPU figure are in it, so it is safe to plot without holes.
function M.history(key)
  return key and M._history[key] or nil
end

--- metrics.isRunning() -> boolean
function M.isRunning()
  return M._running
end

return M
