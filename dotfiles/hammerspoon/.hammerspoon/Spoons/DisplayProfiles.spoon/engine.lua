--- === DisplayProfiles.engine ===
---
--- The mechanism half of DisplayProfiles, the Context in the Capture and Vpn layout.
--- It reads the attached displays, matches them against an injected list of profiles,
--- applies the winning one, and watches for screen changes to reapply. It knows how a
--- profile is shaped, a name plus a displayplacer command, and nothing else. It never
--- names a machine, a catalog, a store, or the chooser. The spoon composition root in
--- init.lua injects this machine's merged profile list and wires the rest.
---
--- A profile matches when the number of screens it names equals the number attached and
--- every id it names is currently attached. Ids may be persistent or serial, both are
--- compared, so a profile written with portable serial ids matches on any machine those
--- same monitors reach. The first match in the list wins.
---
--- Applying a layout changes resolution, which fires the watcher again, so a naive apply
--- would loop. The guard is that applying never changes the set of attached displays, only
--- their arrangement, so we skip when the matched profile is the one already applied. A
--- reload clears that memory, which is why saving a tweak reapplies at once.
---
--- The attached id set is read from displayplacer and cached, since the chooser row
--- supplier asks current() on every keystroke. The cache is cleared on each settled screen
--- change, the one event that can change what is attached, so a keystroke never shells out
--- and a real dock or undock is still seen.

local E = {}
E.__index = E

-- Configured state
E._profiles = nil     -- active list for this machine, each with precomputed ids and count
E._binary = nil       -- displayplacer invocation used for the list query
E._settleDelay = nil  -- seconds to coalesce a burst of screen events
E._watcher = nil      -- hs.screen.watcher instance
E._debounce = nil     -- delayed timer that fires one reconcile per settled burst
E._lastApplied = nil  -- signature of the last profile applied, the loop guard
E._onChange = nil     -- injected, called after a settled screen change so a view can redraw
E._attachedCache = nil -- cached { ids, count } from displayplacer, cleared on a screen change

-- Collect the id tokens a displayplacer command names, as a set plus a count. Each screen
-- spec is `id:<token> ...`, and the token runs to the next space, so origin values with
-- parentheses do not interfere.
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

-- A stable signature for a profile, its sorted ids joined, used only to tell whether the
-- same profile was just applied.
local function signatureOf(idSet)
  local list = {}
  for id in pairs(idSet) do list[#list + 1] = id end
  table.sort(list)
  return table.concat(list, "+")
end
E.signatureOf = signatureOf

--- E:configure(opts)
--- opts.profiles    ordered list of { name, command }, the layouts for this machine,
---                  defaults to empty, which just means nothing is applied automatically.
--- opts.settleDelay seconds to wait for displays to settle after a change before applying,
---                  defaults to 1.5.
--- opts.binary      the displayplacer command used to query attached displays, defaults to
---                  "displayplacer", found on PATH in a login shell.
--- opts.onChange    optional, called after each settled screen change so a live view can
---                  redraw against the new arrangement.
--- Safe to call again after a store edit to swap the profile list in place.
function E:configure(opts)
  opts = opts or {}
  self._binary = opts.binary or "displayplacer"
  self._settleDelay = opts.settleDelay or 1.5
  if opts.onChange ~= nil then self._onChange = opts.onChange end
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

-- Read the displays attached right now, cached until the next screen change. Returns the
-- union of persistent and serial ids as a set, plus the screen count. Both id types go in
-- the set so a profile written with either kind matches.
function E:_attached()
  if self._attachedCache then
    return self._attachedCache.ids, self._attachedCache.count
  end
  local out = hs.execute(self._binary .. " list", true) or ""
  local ids, count = {}, 0
  for id in out:gmatch("Persistent screen id: (%S+)") do
    ids[id] = true
    count = count + 1
  end
  for id in out:gmatch("Serial screen id: (%S+)") do
    ids[id] = true
  end
  self._attachedCache = { ids = ids, count = count }
  return ids, count
end

-- The first profile whose screen count equals the attached count and all of whose ids are
-- attached, or nil.
function E:_match(attachedIds, attachedCount)
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

--- E:reconcile(force)
--- Read the attached displays, pick the matching profile, and apply it. Skips when the
--- match is the profile already applied, so reapplying after our own change does not loop.
--- Pass force to apply regardless, which is what a manual fix invokes when nothing about
--- the displays changed. Logs the attached ids when nothing matches, so you can see what to
--- capture.
function E:reconcile(force)
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

--- E:current()
--- The name of the profile that matches the displays attached right now, or nil when none
--- matches. The read side of the same match reconcile uses, exposed so a view can ask which
--- arrangement is live. Uses the cached attached set, so it is cheap to call per keystroke.
function E:current()
  local attachedIds, attachedCount = self:_attached()
  local p = self:_match(attachedIds, attachedCount)
  return p and p.name or nil
end

--- E:apply(name)
--- Apply a named profile unconditionally, ignoring what is attached. Useful from the
--- console to force a specific layout.
function E:apply(name)
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

--- E:currentCommand()
--- The current arrangement as a displayplacer command string, ready to store as a new
--- profile, or nil when displayplacer prints none. This is the read half of the old capture
--- helper, now returning the string so the command policy decides what to do with it.
function E:currentCommand()
  local out = hs.execute(self._binary .. " list", true) or ""
  return out:match("\n(displayplacer [^\n]+)%s*$")
end

--- E:capture(toClipboard)
--- Print the current arrangement as a displayplacer command, and optionally copy it. Kept
--- for console use, the same helper config/displays.lua documents.
function E:capture(toClipboard)
  local command = self:currentCommand()
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

--- E:parseDisplays(command)
--- Parse a displayplacer command into a list of per screen descriptors, so a view can list
--- a profile's monitors without re-detecting anything. Each entry is { id, res, hz, origin,
--- main }, where main is the screen at origin (0,0), which is how these commands place the
--- primary display. Returns an empty list for a command it cannot read.
function E:parseDisplays(command)
  local out = {}
  if not command then return out end
  for spec in command:gmatch('"([^"]+)"') do
    local id = spec:match("id:(%S+)")
    if id then
      local origin = spec:match("origin:%(([^)]+)%)") or ""
      out[#out + 1] = {
        id = id,
        res = spec:match("res:(%S+)"),
        hz = spec:match("hz:(%S+)"),
        origin = origin,
        main = origin == "0,0",
      }
    end
  end
  return out
end

--- E:start()
--- Apply the matching profile once, then watch for screen changes and reapply on each
--- settled change. Screen events arrive in bursts, so they arm a delayed timer and one
--- reconcile runs once the burst stops. Each settled change clears the attached cache first,
--- since the set may have changed, then reconciles and notifies the injected onChange. If
--- displayplacer is missing, log an error and do nothing, since nothing here works without
--- it.
function E:start()
  -- Resolve the one dependency and log the result at init, so the console shows plainly
  -- whether displayplacer was found and how many profiles are being managed, rather than
  -- leaving a missing tool to look like nothing ever matched.
  local path, ok = hs.execute("command -v " .. self._binary, true)
  if ok ~= true then
    print("DisplayProfiles: dependency displayplacer NOT found on PATH, displays will not be managed; run brew bundle to install it")
    return self
  end
  print(string.format("DisplayProfiles: dependency displayplacer found at %s, managing %d profile(s)",
    (path or "?"):gsub("%s+$", ""), #self._profiles))
  self:reconcile()
  self._debounce = hs.timer.delayed.new(self._settleDelay, function()
    self._attachedCache = nil
    self:reconcile()
    if self._onChange then self._onChange() end
  end)
  self._watcher = hs.screen.watcher.new(function()
    self._debounce:start()
  end)
  self._watcher:start()
  return self
end

--- E:stop()
--- Stop watching. The current arrangement is left untouched, since the point is to keep a
--- layout, not to revert one.
function E:stop()
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

return E
