--- === Workspaces.store ===
---
--- The persistent half of the memory, one JSON file the plugin alone writes. It holds, per
--- display configuration, the name that configuration goes by and one remembered frame per app
--- bundle id. It knows nothing about windows, screens, episodes, or the chooser. The plugin
--- composition root in init.lua gives it a path and everything else reaches it through the api
--- that root builds.
---
--- The shape on disk is a map from fingerprint to a table of name and apps, where apps is a
--- map from bundle id to a frame of x, y, w, h.
---
---     {
---       "0,0,1512x982": {
---         "name": "1512x982",
---         "apps": { "com.apple.Safari": { "x": 0, "y": 38, "w": 1512, "h": 944 } }
---       }
---     }
---
--- One frame per app rather than one per window is a deliberate simplification of this first
--- version. A window id means nothing after a reboot and a fresh window can be handed an id an
--- old entry still names, so persisting by window id would place the wrong window, which is a
--- worse memory than none. A bundle id survives everything, so the persistent layer keys on it
--- and accepts that a multi window app gets one frame. Exact per window treatment comes from
--- the session layer instead, which is where window ids are still meaningful.
---
--- No host key, unlike the DisplayProfiles store beside it, and the difference is real rather
--- than an oversight. DisplayProfiles keys by host because an arrangement of monitors names
--- physical panels that belong to one desk. A fingerprint here is pure geometry, so two
--- machines showing the same rectangles genuinely are the same configuration as far as window
--- placement is concerned, and that collision was accepted deliberately when the fingerprint
--- was chosen.
---
--- The table is read once and cached, and every mutation goes to the cache and marks it dirty,
--- with the caller deciding when to flush. That is what lets the engine coalesce a burst of
--- window moves into one write instead of rewriting the whole file on every drag. The cost is
--- that a hand edit to the file, or one arriving through git, is not seen until the next
--- reload, which is the same trade the DisplayProfiles store already documents and is correct,
--- a data file should not force a code reload.
---
--- The file lives under the config directory, inside the watched tree, so a write would
--- ordinarily trip the pathwatcher and reload. The composition root's auto reload ignore list
--- already covers any JSON under config by pattern rather than by name, so this store needed no
--- entry added for it and knows nothing about any of that. It just reads and writes its path.

local S = {}
S.__index = S

--- store.new(opts)
--- opts.path  absolute path to the JSON file, resolved by the composition root from the live
---            config directory, so nothing here hardcodes a location. A nil path makes every
---            read answer empty and every write a no op, which is how the plugin degrades to
---            the session layer alone rather than failing.
function S.new(opts)
  opts = opts or {}
  return setmetatable({ path = opts.path, cache = nil, dirty = false }, S)
end

-- The whole table, read from disk the first time and held after that. A missing or unreadable
-- file simply starts from empty, which is what a first run on a fresh machine looks like. The
-- file is stat'd first, since hs.json.read logs a noisy error on a missing file.
function S:_all()
  if self.cache then return self.cache end
  local all = {}
  if self.path and hs.fs.attributes(self.path) then
    local read = hs.json.read(self.path)
    if type(read) == "table" then all = read end
  end
  self.cache = all
  return all
end

--- S:flush()
--- Write the cached table back, pretty printed so a hand edit or a git diff reads cleanly.
--- Does nothing when nothing changed or when there is no path, and answers whether a write
--- actually happened, so a caller can log a failure rather than assume success.
function S:flush()
  if not self.dirty then return true end
  if not self.path then
    self.dirty = false
    return false
  end
  local ok = hs.json.write(self:_all(), self.path, true, true) == true
  if ok then self.dirty = false end
  return ok
end

--- S:list()
--- Every configuration as a list of { fingerprint, name, apps }, sorted by fingerprint so two
--- reads answer the same order. Fresh tables rather than the live ones, since a caller walking
--- this list must not be able to mutate what is stored by accident.
function S:list()
  local out = {}
  for fingerprint, entry in pairs(self:_all()) do
    if type(entry) == "table" then
      out[#out + 1] = { fingerprint = fingerprint, name = entry.name or fingerprint, apps = entry.apps or {} }
    end
  end
  table.sort(out, function(a, b) return a.fingerprint < b.fingerprint end)
  return out
end

--- S:get(fingerprint)
--- One configuration's stored entry, or nil.
function S:get(fingerprint)
  if not fingerprint then return nil end
  local entry = self:_all()[fingerprint]
  if type(entry) ~= "table" then return nil end
  return entry
end

--- S:ensure(fingerprint, name)
--- The entry for this fingerprint, created with the given name when it is not there yet. A
--- fingerprint never seen before silently becomes a new configuration, which is the whole
--- promise, arriving at a new desk should cost nobody a setup step.
function S:ensure(fingerprint, name)
  if not fingerprint then return nil end
  local all = self:_all()
  local entry = all[fingerprint]
  if type(entry) ~= "table" then
    entry = { name = name or fingerprint, apps = {} }
    all[fingerprint] = entry
    self.dirty = true
  end
  if type(entry.apps) ~= "table" then
    entry.apps = {}
    self.dirty = true
  end
  return entry
end

--- S:appFrame(fingerprint, bundleID)
--- The remembered frame for one app under one configuration, or nil.
function S:appFrame(fingerprint, bundleID)
  local entry = self:get(fingerprint)
  if not entry or type(entry.apps) ~= "table" or not bundleID then return nil end
  local f = entry.apps[bundleID]
  if type(f) ~= "table" then return nil end
  return f
end

--- S:setAppFrame(fingerprint, bundleID, frame)
--- Remember where one app's window sits under one configuration. Marks the cache dirty rather
--- than writing, so the caller coalesces a burst of moves into one write.
function S:setAppFrame(fingerprint, bundleID, frame)
  if not fingerprint or not bundleID or type(frame) ~= "table" then return false end
  local entry = self:ensure(fingerprint)
  entry.apps[bundleID] = { x = frame.x, y = frame.y, w = frame.w, h = frame.h }
  self.dirty = true
  return true
end

--- S:forgetApp(fingerprint, bundleID)
--- Drop one app from one configuration. Returns true, or false plus a message when it was not
--- remembered there, so a caller can say why nothing happened.
function S:forgetApp(fingerprint, bundleID)
  local entry = self:get(fingerprint)
  if not entry or type(entry.apps) ~= "table" or entry.apps[bundleID] == nil then
    return false, "that app is not remembered here"
  end
  entry.apps[bundleID] = nil
  self.dirty = true
  return true
end

--- S:nameExists(name)
--- Whether any configuration already goes by this name, so a rename never produces two
--- configurations a person cannot tell apart in a list.
function S:nameExists(name)
  for _, entry in pairs(self:_all()) do
    if type(entry) == "table" and entry.name == name then return true end
  end
  return false
end

--- S:rename(fingerprint, newName)
--- Give a configuration a name of the person's own. Returns true, or false plus a message when
--- the name is empty, already used, or the configuration is not there.
function S:rename(fingerprint, newName)
  newName = newName and newName:gsub("^%s+", ""):gsub("%s+$", "") or ""
  if newName == "" then return false, "name is empty" end
  local entry = self:get(fingerprint)
  if not entry then return false, "configuration not found" end
  if entry.name == newName then return true end
  if self:nameExists(newName) then return false, "name already used" end
  entry.name = newName
  self.dirty = true
  return true
end

--- S:remove(fingerprint)
--- Forget a whole configuration. Returns true, or false plus a message when it is not there.
--- Removing the configuration you are standing in is allowed, it simply forgets this desk, and
--- the engine recreates an empty one the next time it recomputes the fingerprint.
function S:remove(fingerprint)
  local all = self:_all()
  if all[fingerprint] == nil then return false, "configuration not found" end
  all[fingerprint] = nil
  self.dirty = true
  return true
end

return S
