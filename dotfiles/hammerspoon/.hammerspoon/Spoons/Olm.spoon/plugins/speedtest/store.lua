--- === Speedtest.store ===
---
--- The history, the network names a person has given, and the run settings, all in one JSON
--- file under the olm data root. Durable rather than cached, because a run cannot be
--- recreated once its moment has passed, so deleting this file loses something real.
---
--- Nothing here expires by age, deliberately. A run from months ago is the most useful
--- record in the file the day something changes, since it is the only evidence of what this
--- network used to do. The bound is a count per network instead, which caps the file without
--- ever throwing away the one thing that makes a trend worth having.
---
--- The cap is per network rather than overall for the same reason the trend is per network.
--- One busy week on a hotel connection must not push a year of home readings out of the file.
---
--- State is read once and held, since every read here happens while a list is on screen and
--- rereading a file per keystroke would be the one expensive thing in an otherwise instant
--- list. Every write goes straight to disk, since a run is worth losing nothing over.

local M = {}

local cfg = {}
local state = nil

-- What a settings page starts from before anybody changes anything. Ten seconds is short
-- enough that taking a reading is not a thing to plan around, and the tool reaches a stable
-- figure well inside it, so the longer runs are there for when a number is being argued over
-- rather than for ordinary use. Parallel is the realistic case rather than the flattering one,
-- and fifty runs per network is well over a year for a person who tests a few times a month.
local DEFAULTS = {
  direction = "both",
  sequential = false,
  maxSeconds = 10,
  protocol = "auto",
  privateRelay = false,
  cap = 50,
}

M.DEFAULTS = DEFAULTS

local function log(message)
  if cfg.log and cfg.log.e then cfg.log.e(message) end
end

local function dir()
  return cfg.storage.dataDir("speedtest")
end

local function path()
  return dir() .. "/history.json"
end

-- An empty table encodes as an empty JSON object and decodes back as an empty table, so the
-- three slots survive a round trip whether or not anything has been written into them yet.
local function blank()
  return { runs = {}, names = {}, settings = {} }
end

local function load()
  if state then return state end
  state = blank()
  local file = io.open(path(), "r")
  if not file then return state end
  local raw = file:read("a")
  file:close()
  local ok, decoded = pcall(hs.json.decode, raw)
  if not ok or type(decoded) ~= "table" then
    -- A file this cannot read is left exactly where it is rather than overwritten, so a
    -- person still has whatever is in it. The next write replaces it, which is the only
    -- honest outcome once the contents cannot be understood.
    log("Speedtest could not read its history file, starting from nothing")
    return state
  end
  state.runs = type(decoded.runs) == "table" and decoded.runs or {}
  state.names = type(decoded.names) == "table" and decoded.names or {}
  state.settings = type(decoded.settings) == "table" and decoded.settings or {}
  return state
end

local function save()
  local current = load()
  cfg.storage.ensure(dir())
  local encoded = hs.json.encode(current, true)
  local file = io.open(path(), "w")
  if not file then
    log("Speedtest could not write its history file at " .. path())
    return false
  end
  file:write(encoded)
  file:close()
  return true
end

--- store.configure(opts)
--- opts.storage  lib/storage.lua itself, for the one data directory this plugin owns.
--- opts.log      the shared logger, used only for a disk failure a person would otherwise
---               never learn about.
function M.configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  state = nil
  return M
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

--- store.settings() -> the run settings, every key present, defaults filled in.
function M.settings()
  local saved = load().settings
  local out = {}
  for k, v in pairs(DEFAULTS) do out[k] = v end
  for k, v in pairs(saved) do
    if DEFAULTS[k] ~= nil then out[k] = v end
  end
  return out
end

--- store.setSetting(key, value) - write one setting, ignoring a key this does not own.
function M.setSetting(key, value)
  if DEFAULTS[key] == nil then return false end
  load().settings[key] = value
  return save()
end

--------------------------------------------------------------------------------
-- Names
--------------------------------------------------------------------------------

--- store.nameOf(netId) -> the name a person gave this network, or nil.
function M.nameOf(netId)
  if not netId then return nil end
  local name = load().names[netId]
  if type(name) ~= "string" or name:match("%S") == nil then return nil end
  return name
end

--- store.setName(netId, name) - name a network, or clear the name when handed nothing.
function M.setName(netId, name)
  if not netId then return false end
  if type(name) ~= "string" or name:match("%S") == nil then
    load().names[netId] = nil
  else
    load().names[netId] = name
  end
  return save()
end

--- store.label(netId, fallback) -> what to call a network on screen.
--- A name the person gave wins over everything, since they chose it against exactly this
--- identity. The fallback is whatever the caller already knows, the live label for the
--- network in use and the stored snapshot for one that is not.
function M.label(netId, fallback)
  return M.nameOf(netId) or fallback or "Unknown network"
end

--------------------------------------------------------------------------------
-- Runs
--------------------------------------------------------------------------------

local function byNewest(a, b)
  return (a.at or 0) > (b.at or 0)
end

--- store.add(record) - keep a finished run, newest first, capped per network.
function M.add(record)
  if type(record) ~= "table" or not record.net then return false end
  local runs = load().runs
  runs[#runs + 1] = record

  local cap = M.settings().cap
  local seen, kept = {}, {}
  local ordered = {}
  for i, r in ipairs(runs) do ordered[i] = r end
  table.sort(ordered, byNewest)
  for _, r in ipairs(ordered) do
    local net = r.net or "unknown"
    seen[net] = (seen[net] or 0) + 1
    if seen[net] <= cap then kept[#kept + 1] = r end
  end
  load().runs = kept
  return save()
end

--- store.forNetwork(netId) -> that network's runs, newest first.
function M.forNetwork(netId)
  local out = {}
  for _, r in ipairs(load().runs) do
    if r.net == netId then out[#out + 1] = r end
  end
  table.sort(out, byNewest)
  return out
end

--- store.byId(at) -> one run by its timestamp, which is its identity.
--- Two runs cannot finish in the same second on one machine, since only one runs at a time
--- and every run takes many seconds, so the timestamp is a safe key and a row can carry a
--- plain number rather than a table.
function M.byId(at)
  if type(at) ~= "number" then return nil end
  for _, r in ipairs(load().runs) do
    if r.at == at then return r end
  end
  return nil
end

--- store.networks() -> every network with runs, newest activity first.
function M.networks()
  local index = {}
  for _, r in ipairs(load().runs) do
    local net = r.net or "unknown"
    local entry = index[net]
    if not entry then
      entry = { id = net, label = r.label, kind = r.kind, count = 0, latest = 0 }
      index[net] = entry
    end
    entry.count = entry.count + 1
    if (r.at or 0) > entry.latest then
      entry.latest = r.at or 0
      -- The newest run's own snapshot is the freshest thing this file knows about what a
      -- network was called, which matters for one nobody is connected to now.
      entry.label = r.label or entry.label
    end
  end
  local out = {}
  for _, entry in pairs(index) do out[#out + 1] = entry end
  table.sort(out, function(a, b) return a.latest > b.latest end)
  return out
end

--- store.clear(netId) - forget one network's runs, or every run when handed nothing.
--- A name a person gave is left alone either way, since clearing a history is about the
--- readings rather than about undoing the naming.
function M.clear(netId)
  if not netId then
    load().runs = {}
    return save()
  end
  local kept = {}
  for _, r in ipairs(load().runs) do
    if r.net ~= netId then kept[#kept + 1] = r end
  end
  load().runs = kept
  return save()
end

return M
