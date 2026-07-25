--- Processes engine.
---
--- The Context in Strategy terms. It owns the source list, the merge, the labelling
--- and the ordering, and it talks only through the source contract, so it never
--- names a concrete source. Which sources exist and in what order is decided by
--- init.lua, the composition root, which is what keeps this file reusable.
---
--- The merge is the one rule worth understanding. Sources are an ordered list and a
--- row is dropped when every port it holds has already been claimed by an earlier
--- source. That single generic rule is what collapses a dozen identical container
--- proxy listeners into named containers, without the engine knowing what a
--- container is. Reordering the list in the root changes who wins, and a source
--- that finds nothing simply claims nothing and changes no other source's output.
---
--- Availability is checked LIVE on every scan and every stop rather than cached at
--- load, for the same reason Capture does it. A daemon can quit long after
--- Hammerspoon started, and Hammerspoon only reloads when a file changes, so a
--- cached decision goes stale and the engine would keep asking a dead backend. Each
--- source's reason is logged only when it CHANGES, so repeated opens stay quiet
--- while a backend is down.

-- util is loaded here rather than injected. It is a stateless set of helpers with
-- no policy in it, so injecting it would be indirection with nothing behind it, and
-- loading it directly keeps the engine from depending on the root remembering to
-- set a field.
local enginePath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local util = loadfile(enginePath .. "util.lua")()

local obj = {}
obj.__index = obj

obj.name = "Processes"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("Processes", "info")

-- Injected by init.lua (the composition root)
obj._contract = nil
obj._defaultSources = nil

-- Configured state
obj._sources = nil       -- active list, in claim priority order, contract checked
obj._genericDirs = nil   -- directory names too vague to label a project with
obj._lastReason = nil    -- source name -> last failing reason, for deduped logging

function obj:init()
  self._lastReason = {}
  self._genericDirs = {}
  return self
end

--- Processes:configure(opts)
--- opts.sources     ordered list of source tables, earlier ones claim ports first
--- opts.genericDirs list of directory names too generic to identify a project
function obj:configure(opts)
  opts = opts or {}
  self._sources = self:_validate(opts.sources or self._defaultSources or {})
  self._genericDirs = {}
  for _, d in ipairs(opts.genericDirs or {}) do
    self._genericDirs[d:lower()] = true
  end
  self:_logAvailability()
  return self
end

-- Keep only the sources that fulfil the contract. A source missing a method can
-- never be dispatched, so it is dropped here once, at load, with a line naming the
-- gap. This is the only static filtering, whether a valid source is usable right
-- now is decided live at scan time.
function obj:_validate(sources)
  local valid = {}
  for _, source in ipairs(sources or {}) do
    local ok, missing = self._contract.validate(source)
    if ok then
      table.insert(valid, source)
    else
      log.w((source and source.name or "?") .. " dropped, does not implement " .. tostring(missing) .. "()")
    end
  end
  return valid
end

function obj:_logAvailability()
  self._lastReason = {}
  for _, source in ipairs(self._sources or {}) do
    local name = source.name or "?"
    local ok, reason = source.available()
    if not ok then
      reason = reason or "unavailable"
      self._lastReason[name] = reason
      log.w(name .. " unavailable, " .. reason)
    end
  end
  return self
end

-- Log a source's reason only when it changed since the last check, recovery
-- included, so opening the picker repeatedly while docker is down logs once.
function obj:_noteAvailability(name, ok, reason)
  if ok then
    if self._lastReason[name] then
      log.i(name .. " available")
      self._lastReason[name] = nil
    end
    return
  end
  reason = reason or "unavailable"
  if self._lastReason[name] ~= reason then
    log.w(name .. " unavailable, " .. reason)
    self._lastReason[name] = reason
  end
end

-- Derive a display label from a working directory when the source did not name the
-- row itself. A bare directory basename is usually the project, but a server
-- commonly runs from a generic subdirectory whose name says nothing, so in that
-- case the label walks up one level and joins both. A row with neither a title nor
-- a cwd falls back to its runtime and pid, which is still better than nothing and
-- makes the gap visible rather than silent.
function obj:_label(row)
  if row.title and row.title ~= "" then return row.title end
  local base = util.basename(row.cwd)
  if base then
    if self._genericDirs[base:lower()] then
      local parent = util.basename(util.dirname(row.cwd))
      if parent then return parent .. " / " .. base end
    end
    return base
  end
  if row.runtime and row.pid then return row.runtime .. " " .. row.pid end
  return row.runtime or ("pid " .. tostring(row.pid))
end

-- Drop any row whose ports are all claimed by an earlier source, then label and
-- order what survives. A row holding no ports is never suppressed, since it can
-- collide with nothing.
function obj:_merge(perSource)
  local claimed, kept = {}, {}
  for _, rows in ipairs(perSource) do
    for _, row in ipairs(rows) do
      local ports = row.ports or {}
      local allClaimed = #ports > 0
      for _, port in ipairs(ports) do
        if not claimed[port] then allClaimed = false end
      end
      if not allClaimed then
        for _, port in ipairs(ports) do claimed[port] = true end
        row.title = self:_label(row)
        kept[#kept + 1] = row
      end
    end
  end
  -- Local processes above containers, newest first inside a tier, and the title
  -- breaking the remaining ties so the order is stable between scans rather than
  -- dependent on whatever order the shellouts happened to return in.
  table.sort(kept, function(a, b)
    if (a.tier or 0) ~= (b.tier or 0) then return (a.tier or 0) < (b.tier or 0) end
    if (a.startedAt or 0) ~= (b.startedAt or 0) then return (a.startedAt or 0) > (b.startedAt or 0) end
    return tostring(a.title) < tostring(b.title)
  end)
  return kept
end

--- Processes:scan(cb)
--- Method
--- Ask every available source at once and hand the merged, labelled, ordered rows
--- to cb. Sources run concurrently because none of them depends on another, so the
--- scan costs the slowest single source rather than their sum. An unavailable or
--- failing source contributes an empty list and never blocks the others, so docker
--- being down still gives you your local servers.
function obj:scan(cb)
  local sources = self._sources or {}
  if #sources == 0 then cb({}) return end

  local perSource, pending, finished = {}, #sources, false
  local function done()
    pending = pending - 1
    if pending > 0 or finished then return end
    finished = true
    cb(self:_merge(perSource))
  end

  for i, source in ipairs(sources) do
    perSource[i] = {}
    local name = source.name or "?"
    local ok, reason = source.available()
    self:_noteAvailability(name, ok, reason)
    if not ok then
      done()
    else
      source.scan(function(rows, err)
        perSource[i] = rows or {}
        if err then self:_noteAvailability(name, false, err) end
        done()
      end)
    end
  end
end

--- Processes:stop(row, opts, cb)
--- Method
--- Route the stop back to the source that produced the row, which is the whole
--- point of the contract carrying stop. Signalling a process group and stopping a
--- container are two implementations of one method, and the engine picks neither,
--- it only finds the owner and forwards. opts.force asks for the unconditional
--- kill, opts.confirmed acknowledges a group large enough that the source refused
--- to take it silently.
function obj:stop(row, opts, cb)
  cb = cb or function() end
  if not row or not row.source then cb(false, "no source on this row") return end
  for _, source in ipairs(self._sources or {}) do
    if source.name == row.source then
      local ok, reason = source.available()
      self:_noteAvailability(source.name, ok, reason)
      if not ok then cb(false, (source.name or "source") .. " unavailable, " .. (reason or "")) return end
      source.stop(row, opts or {}, cb)
      return
    end
  end
  cb(false, "no source named " .. tostring(row.source))
end

return obj
