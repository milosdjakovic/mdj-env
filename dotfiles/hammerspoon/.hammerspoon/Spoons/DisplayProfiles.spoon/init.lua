--- === DisplayProfiles ===
---
--- Keep display arrangements deterministic. macOS remembers arrangements per
--- hardware set, but a dock waking monitors in a different order can still leave
--- the wrong main display, wrong scaling, or windows on the wrong screen, and the
--- Settings UI gives no way to force it back. This spoon watches for screen
--- changes and reapplies the saved arrangement that fits whatever is attached,
--- through the displayplacer command line tool.
---
--- This is the mechanism half only. It knows how to read the attached displays,
--- match them against a list of profiles, and apply the winning one. It does not
--- know which machine it runs on or which layouts exist. The composition root in
--- init.lua resolves this machine and injects its profiles, so this spoon and the
--- catalog it drives both point at the same small idea of a profile, a name plus
--- a displayplacer command, and neither points at the other.
---
--- A profile matches when the number of screens it names equals the number
--- attached and every id it names is currently attached. Ids may be persistent or
--- serial, both are compared, so a profile written with portable serial ids
--- matches on any machine those same monitors reach. The first match in the list
--- wins.
---
--- Applying a layout changes resolution, which fires the watcher again, so a
--- naive apply would loop. The guard is that applying never changes the set of
--- attached displays, only their arrangement, so we skip when the matched profile
--- is the one already applied. A reload clears that memory, which is why saving a
--- tweak reapplies at once.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "DisplayProfiles"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- Configured state
obj._profiles = nil     -- active list for this machine, each with precomputed ids and count
obj._binary = nil       -- displayplacer invocation used for the list query
obj._settleDelay = nil  -- seconds to coalesce a burst of screen events
obj._watcher = nil      -- hs.screen.watcher instance
obj._debounce = nil     -- delayed timer that fires one reconcile per settled burst
obj._lastApplied = nil  -- signature of the last profile applied, the loop guard

--- DisplayProfiles:init()
--- Method
--- Initialize the spoon.
function obj:init()
  return self
end

-- Collect the id tokens a displayplacer command names, as a set plus a count.
-- Each screen spec is `id:<token> ...`, and the token runs to the next space, so
-- origin values with parentheses do not interfere.
local function commandIds(command)
  local set, count = {}, 0
  for id in command:gmatch("id:(%S+)") do
    if not set[id] then
      set[id] = true
      count = count + 1
    end
  end
  return set, count
end

-- A stable signature for a profile, its sorted ids joined, used only to tell
-- whether the same profile was just applied.
local function signatureOf(idSet)
  local list = {}
  for id in pairs(idSet) do list[#list + 1] = id end
  table.sort(list)
  return table.concat(list, "+")
end

--- DisplayProfiles:configure(opts)
--- Method
--- opts.profiles    - ordered list of { name, command }, the layouts for this
---                    machine; defaults to empty, which just means nothing is
---                    applied automatically.
--- opts.settleDelay - seconds to wait for displays to settle after a change
---                    before applying; defaults to 1.5.
--- opts.binary      - the displayplacer command used to query attached displays;
---                    defaults to "displayplacer", found on PATH in a login shell.
function obj:configure(opts)
  opts = opts or {}
  self._binary = opts.binary or "displayplacer"
  self._settleDelay = opts.settleDelay or 1.5
  self._profiles = {}
  for _, p in ipairs(opts.profiles or {}) do
    local ids, count = commandIds(p.command or "")
    if count == 0 then
      print("DisplayProfiles: profile '" .. tostring(p.name) .. "' names no id, ignored")
    else
      self._profiles[#self._profiles + 1] = {
        name = p.name or "?",
        command = p.command,
        ids = ids,
        count = count,
        signature = signatureOf(ids),
      }
    end
  end
  return self
end

-- Read the displays attached right now. Returns the union of persistent and
-- serial ids as a set, plus the screen count. Both id types go in the set so a
-- profile written with either kind matches.
function obj:_attached()
  local out = hs.execute(self._binary .. " list", true) or ""
  local ids, count = {}, 0
  for id in out:gmatch("Persistent screen id: (%S+)") do
    ids[id] = true
    count = count + 1
  end
  for id in out:gmatch("Serial screen id: (%S+)") do
    ids[id] = true
  end
  return ids, count
end

-- The first profile whose screen count equals the attached count and all of
-- whose ids are attached, or nil.
function obj:_match(attachedIds, attachedCount)
  for _, p in ipairs(self._profiles) do
    if p.count == attachedCount then
      local all = true
      for id in pairs(p.ids) do
        if not attachedIds[id] then
          all = false
          break
        end
      end
      if all then return p end
    end
  end
  return nil
end

--- DisplayProfiles:reconcile(force)
--- Method
--- Read the attached displays, pick the matching profile, and apply it. Skips
--- when the match is the profile already applied, so reapplying after our own
--- change does not loop. Pass force to apply regardless, which is what a manual
--- fix invokes when nothing about the displays changed. Logs the attached ids
--- when nothing matches, so you can see what to capture.
function obj:reconcile(force)
  local attachedIds, attachedCount = self:_attached()
  local p = self:_match(attachedIds, attachedCount)
  if not p then
    print("DisplayProfiles: no profile for " .. attachedCount
      .. " screens (" .. signatureOf(attachedIds) .. ")")
    return self
  end
  if not force and self._lastApplied == p.signature then
    return self
  end
  hs.execute(p.command, true)
  self._lastApplied = p.signature
  print("DisplayProfiles: applied '" .. p.name .. "'")
  return self
end

--- DisplayProfiles:apply(name)
--- Method
--- Apply a named profile unconditionally, ignoring what is attached. Useful from
--- the console or a hotkey to force a specific layout.
function obj:apply(name)
  for _, p in ipairs(self._profiles) do
    if p.name == name then
      hs.execute(p.command, true)
      self._lastApplied = p.signature
      print("DisplayProfiles: applied '" .. p.name .. "'")
      return self
    end
  end
  print("DisplayProfiles: no profile named '" .. tostring(name) .. "'")
  return self
end

--- DisplayProfiles:capture(toClipboard)
--- Method
--- Print the current arrangement as a displayplacer command, ready to paste into
--- config/displays.lua as a new profile. Pass true to also copy it to the
--- clipboard. This is the capture helper referenced from the console.
function obj:capture(toClipboard)
  local out = hs.execute(self._binary .. " list", true) or ""
  local command = out:match("\n(displayplacer [^\n]+)%s*$")
  if not command then
    print("DisplayProfiles: could not read a command from displayplacer list")
    return self
  end
  print(command)
  if toClipboard then
    hs.pasteboard.setContents(command)
    print("DisplayProfiles: copied to clipboard")
  end
  return self
end

--- DisplayProfiles:start()
--- Method
--- Apply the matching profile once, then watch for screen changes and reapply on
--- each settled change. Screen events arrive in bursts, so they arm a delayed
--- timer and one reconcile runs once the burst stops.
function obj:start()
  self:reconcile()
  self._debounce = hs.timer.delayed.new(self._settleDelay, function()
    self:reconcile()
  end)
  self._watcher = hs.screen.watcher.new(function()
    self._debounce:start()
  end)
  self._watcher:start()
  return self
end

--- DisplayProfiles:stop()
--- Method
--- Stop watching. The current display arrangement is left untouched, since the
--- point is to keep a layout, not to revert one.
function obj:stop()
  if self._watcher then
    self._watcher:stop()
    self._watcher = nil
  end
  if self._debounce then
    self._debounce:stop()
    self._debounce = nil
  end
  return self
end

return obj
