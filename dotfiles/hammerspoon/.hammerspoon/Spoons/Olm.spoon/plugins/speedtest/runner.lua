--- === Speedtest.runner ===
---
--- One measurement, from flags to a finished record, plus the live figures that arrive while it
--- is still being taken. It owns the task, the timeout, and the parse, and it knows nothing
--- about lists, panes, or history. The list asks it to start and is told as it goes and once at
--- the end.
---
--- THE RUN OUTLIVES THE LIST, deliberately. A measurement takes ten to twenty seconds and nobody
--- stands in front of a picker for that long, so the task lives here rather than on the surface,
--- and closing the window leaves it running.
---
--- THE TOOL IS RUN UNDER A PTY AND THAT IS THE WHOLE REASON THERE IS A LIVE GRAPH. networkQuality
--- decides whether to report progress by asking whether its output is a terminal. Piped, which is
--- what a task gives it, it prints nothing at all until it finishes and then emits everything at
--- once, which is what an earlier version of this file measured and wrongly concluded was the
--- tool's only behaviour. Given a terminal it prints a downlink figure, an uplink figure and a
--- responsiveness figure about four times a second for the whole run. `script` is what provides
--- that terminal, and it exists for exactly this, running a program with a pty attached.
---
--- The final numbers still come from the machine readable JSON rather than from those progress
--- lines, because the progress lines carry three figures and the JSON carries twenty seven,
--- including the idle latency, the latency samples taken under load, the endpoint, the protocol
--- and the L4S state. The tool will write that JSON to a FILE while still printing progress to
--- its terminal, which is what lets this have both at once, and the flag has to be written
--- attached to its value, -cPATH, since the spaced form is read as a missing argument and prints
--- usage instead of running anything.

local M = {}

local cfg = {}

local task = nil        -- the live task, nil when nothing is running
local startedAt = nil   -- os.time when the current run began
local guard = nil       -- the timeout that terminates a run that never answers
local pendingNet = nil  -- the network the current run started on
local listener = nil    -- who to tell when a run lands
local watcher = nil     -- who to tell as figures arrive
local samples = nil     -- the live trail, one entry per progress line
local jsonPath = nil    -- where this run is writing its machine readable answer

-- How far past the tool's own maximum runtime a run may go before it is killed. The tool bounds
-- its measuring phases with -M but has setup either side of them, so a bound equal to -M would
-- kill healthy runs. This is a backstop against a task that never returns at all.
local GRACE_SECONDS = 25

-- How many points of the live trail a finished run keeps. The trail arrives at about four a
-- second, so a twenty second run takes eighty, and keeping every one of them would put the
-- largest thing in the whole record in a file bounded by a count of records. Forty is more than
-- a pane a few hundred points wide can draw distinctly and small enough that a record stays a
-- record.
local CURVE_POINTS = 40

local function log(message)
  if cfg.log and cfg.log.e then cfg.log.e(message) end
end

-- Where this run writes its machine readable answer, resolved on first use and kept. Guarded
-- rather than trusted, since a storage module that was never configured raises by design, and a
-- run that cannot reach a cache directory should still take a measurement rather than refuse.
local resolvedDir = nil
local function workDir()
  if resolvedDir then return resolvedDir end
  if cfg.storage then
    local ok, dir = pcall(function()
      return cfg.storage.ensure(cfg.storage.cacheDir("speedtest"))
    end)
    if ok and dir then
      resolvedDir = dir
      return resolvedDir
    end
  end
  resolvedDir = "/tmp"
  return resolvedDir
end

--- runner.configure(opts)
--- opts.path      where networkQuality is, resolved by the root through the deps adapter.
--- opts.pty       where script is, the program that gives the tool a terminal. Without it a run
---                still happens and still lands, with no live figures at all, so it degrades to
---                exactly what this plugin did before the graph existed.
--- opts.storage   lib/storage.lua, asked for a cache directory on the first run rather than at
---                configure, see this plugin's own init.lua for why the timing matters.
--- opts.util      the shared formatting and sampling helpers.
--- opts.log       the shared logger.
function M.configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  return M
end

--- runner.isAvailable() -> whether a run can be started at all.
function M.isAvailable()
  return cfg.path ~= nil
end

--- runner.isLive() -> whether a run can report figures while it is being taken.
--- False means no pty, so the graph has nothing to draw and the list says elapsed time instead.
function M.isLive()
  return cfg.pty ~= nil
end

--- runner.isRunning() -> whether a measurement is in flight right now.
function M.isRunning()
  return task ~= nil
end

--- runner.elapsed() -> whole seconds since the current run began, zero when idle.
function M.elapsed()
  if not startedAt then return 0 end
  return os.time() - startedAt
end

--- runner.samples() -> the live trail so far, oldest first, or nil when nothing is running.
--- Each entry carries down and up in Mbps and rpm, exactly the three figures the tool prints.
function M.samples()
  return samples
end

--- runner.latest() -> the most recent live reading, or nil.
function M.latest()
  return samples and samples[#samples] or nil
end

--- runner.network() -> the network the run in flight started on, nil when idle.
function M.network()
  return pendingNet
end

--------------------------------------------------------------------------------
-- Flags
--------------------------------------------------------------------------------

-- Two of these read backwards at a glance and are worth naming, -u means run no upload test and
-- -d means run no download test, so a download only run passes -u.
local function toolArgs(settings, outPath)
  local args = { "-c" .. outPath, "-M", tostring(settings.maxSeconds or 10) }
  if settings.sequential then args[#args + 1] = "-s" end
  if settings.direction == "down" then args[#args + 1] = "-u" end
  if settings.direction == "up" then args[#args + 1] = "-d" end
  if settings.protocol and settings.protocol ~= "auto" then
    args[#args + 1] = "-f"
    args[#args + 1] = settings.protocol
  end
  if settings.privateRelay then args[#args + 1] = "-p" end
  if settings.interface then
    args[#args + 1] = "-I"
    args[#args + 1] = settings.interface
  end
  return args
end

-- The whole command, either wrapped in a pty or not. -q keeps script's own session chatter out,
-- and the typescript it insists on writing goes to /dev/null since the output this cares about is
-- the one flowing through the terminal it just created.
local function commandFor(settings, outPath)
  local args = toolArgs(settings, outPath)
  if not M.isLive() then
    return cfg.path, args
  end
  local wrapped = { "-q", "/dev/null", cfg.path }
  for _, arg in ipairs(args) do wrapped[#wrapped + 1] = arg end
  return cfg.pty, wrapped
end

--------------------------------------------------------------------------------
-- Reading the live figures
--------------------------------------------------------------------------------

-- One progress line looks like
--   Downlink: 15.465 Mbps, 138 RPM - Uplink: 29.262 Mbps, 138 RPM
-- redrawn in place, so a chunk carries carriage returns and terminal escapes around however many
-- lines arrived together. Matching the figures rather than splitting the chunk means none of that
-- has to be understood, and a partial line at the end of a chunk simply does not match and is
-- picked up whole in the next one.
local PROGRESS = "Downlink:%s*([%d%.]+)%s*Mbps,%s*(%d+)%s*RPM%s*%-%s*Uplink:%s*([%d%.]+)%s*Mbps,%s*(%d+)%s*RPM"

--- runner.readProgress(chunk) -> a list of readings, oldest first, possibly empty.
--- Split out so the parse can be checked against real captured output without a pty.
function M.readProgress(chunk)
  local found = {}
  if type(chunk) ~= "string" then return found end
  for down, downRpm, up, upRpm in chunk:gmatch(PROGRESS) do
    -- The tool prints the same responsiveness figure on both halves of the line. Reading the
    -- larger of the two rather than picking a side means a future version printing them
    -- separately still gives the honest worst case rather than whichever half was hardcoded.
    local rpm = math.max(tonumber(downRpm) or 0, tonumber(upRpm) or 0)
    found[#found + 1] = {
      down = tonumber(down) or 0,
      up = tonumber(up) or 0,
      rpm = rpm,
    }
  end
  return found
end

--------------------------------------------------------------------------------
-- Reading the finished run
--------------------------------------------------------------------------------

-- The tool reports several of its facts as a table of observed values against how many times each
-- was seen, so the answer is whichever was seen most rather than the only one present.
local function dominant(counted)
  if type(counted) ~= "table" then return nil end
  local best, bestCount = nil, -1
  for key, count in pairs(counted) do
    if type(count) == "number" and count > bestCount then
      best, bestCount = key, count
    end
  end
  return best
end

local function shortEndpoint(host)
  if type(host) ~= "string" then return nil end
  return host:match("^([^.]+)") or host
end

-- Latency measured while the link is loaded, the figure responsiveness is built from and the one
-- that decides how the network feels. The foreign samples are new connections opened during the
-- load, so they model a page opened while something else is downloading, which is the case a
-- person actually notices. The self samples are the test's own already open connections and are
-- the fallback when a direction was skipped and no foreign samples exist.
local function loadedSamples(parsed)
  local foreign = parsed.lud_foreign_h2_req_resp
  if type(foreign) == "table" and #foreign > 0 then return foreign end
  local own = parsed.lud_self_h2_req_resp
  if type(own) == "table" and #own > 0 then return own end
  return nil
end

-- The live trail as a finished run keeps it, three fixed width series rather than a list of
-- readings, since that is the shape a pane draws and it stores smaller.
local function curveOf(trail)
  if type(trail) ~= "table" or #trail == 0 then return nil end
  local down, up, rpm = {}, {}, {}
  for i, s in ipairs(trail) do
    down[i], up[i], rpm[i] = s.down, s.up, s.rpm
  end
  return {
    down = cfg.util.downsample(down, CURVE_POINTS),
    up = cfg.util.downsample(up, CURVE_POINTS),
    rpm = cfg.util.downsample(rpm, CURVE_POINTS),
  }
end

--- runner.parse(text, net, settings, trail) -> record or nil, reason
--- Split out from the callback so it can be read, and checked, against a real captured run
--- without launching anything.
function M.parse(text, net, settings, trail)
  if type(text) ~= "string" or text:match("^%s*$") then
    return nil, "the tool wrote no result"
  end
  local ok, parsed = pcall(hs.json.decode, text)
  if not ok or type(parsed) ~= "table" then
    return nil, "the tool wrote something this could not read"
  end
  if not (parsed.dl_throughput or parsed.ul_throughput) then
    return nil, "the run finished without measuring anything"
  end

  local other = type(parsed.other) == "table" and parsed.other or {}
  local latency = loadedSamples(parsed)
  local interfaceType = dominant(other["interface-type"])

  return {
    at = os.time(),
    net = net.id,
    -- A snapshot of what this network was called, so a run still reads sensibly years later on a
    -- machine nowhere near it. A name the person gives overrides this at read time.
    label = net.label,
    kind = interfaceType or net.kind,
    iface = parsed.interface_name or net.iface,

    down = parsed.dl_throughput,
    up = parsed.ul_throughput,
    rpm = parsed.responsiveness,
    idleMs = parsed.base_rtt,

    lat = cfg.util.summarise(latency),
    strip = cfg.util.downsample(latency, 12),
    -- The run's own shape over its own lifetime, which is the one graph that is never flat
    -- however few runs a network has, since it is made of this run alone.
    curve = curveOf(trail),

    proto = dominant(other.protocols_seen),
    l4s = dominant(other.l4s_enablement),
    proxied = dominant(other.proxy_state),
    endpoint = shortEndpoint(parsed.test_endpoint),
    secs = parsed.dl_phase_duration or parsed.ul_phase_duration,
    direction = settings.direction,
    sequential = settings.sequential and true or false,
  }
end

--------------------------------------------------------------------------------
-- Running
--------------------------------------------------------------------------------

local function readAndRemove(path)
  if not path then return nil end
  local file = io.open(path, "r")
  local text = nil
  if file then
    text = file:read("a")
    file:close()
  end
  os.remove(path)
  return text
end

-- Everything that has to happen exactly once when a run ends, however it ended. Held in one place
-- because there are several ways out, a clean finish, a bad exit, a launch that never happened,
-- the timeout, and a stop, and each of them has to leave this file idle and tell whoever asked.
local function finish(record, reason)
  if guard then
    guard:stop()
    guard = nil
  end
  task = nil
  startedAt = nil
  pendingNet = nil
  samples = nil
  watcher = nil
  if jsonPath then
    os.remove(jsonPath)
    jsonPath = nil
  end
  local tell = listener
  listener = nil
  if tell then tell(record, reason) end
end

--- runner.start(settings, net, cb, onProgress) -> whether a run actually began.
--- cb(record) on a finished run, cb(nil, reason) on anything else, called exactly once on the
--- main thread. onProgress is optional and is called with no arguments each time fresh figures
--- land, so a caller can read runner.samples() and redraw whatever it is showing.
function M.start(settings, net, cb, onProgress)
  if task then return false end
  if not M.isAvailable() then
    if cb then cb(nil, "networkQuality is not on this machine") end
    return false
  end

  settings = settings or {}
  listener = cb
  watcher = onProgress
  startedAt = os.time()
  pendingNet = net
  samples = {}
  jsonPath = workDir() .. "/run-" .. tostring(startedAt) .. ".json"

  local program, args = commandFor(settings, jsonPath)
  local mine = jsonPath

  task = hs.task.new(program, function(code)
    -- A terminated run has already been reported by whoever terminated it, so this callback has
    -- nothing left to say and must not report a second time.
    if not task then return end
    local trail = samples
    local text = readAndRemove(mine)
    jsonPath = nil
    if not text then
      log("Speedtest run exited " .. tostring(code) .. " and wrote no result")
      finish(nil, "the run did not finish")
      return
    end
    local record, reason = M.parse(text, net, settings, trail)
    if not record then
      log("Speedtest could not read a finished run, " .. tostring(reason))
      finish(nil, reason)
      return
    end
    finish(record)
  end, function(_, stdout)
    if not task then return false end
    for _, reading in ipairs(M.readProgress(stdout)) do
      samples[#samples + 1] = reading
    end
    if watcher then watcher() end
    return true
  end, args)

  -- start answers nil rather than raising when a task never actually launches, so a caller that
  -- trusts the object it was handed would wait forever for a callback that can never come.
  if not task:start() then
    task = nil
    finish(nil, "the run could not be started")
    return false
  end

  local limit = (settings.maxSeconds or 10) + GRACE_SECONDS
  guard = hs.timer.doAfter(limit, function()
    if not task then return end
    local dying = task
    task = nil
    dying:terminate()
    finish(nil, "the run gave no answer in " .. limit .. " seconds")
  end)

  return true
end

--- runner.stop() - end a run in flight, telling whoever asked for it that it was stopped.
--- A stopped run is never kept, since a half measurement drawn into a trend is a low point that
--- was never about the network.
function M.stop()
  if not task then return false end
  local dying = task
  task = nil
  dying:terminate()
  finish(nil, "stopped")
  return true
end

return M
