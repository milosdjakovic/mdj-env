--- === Workspaces.store ===
---
--- The layouts a person took, one JSON file this plugin alone writes. It holds a list of
--- layouts, each a name, the display topology it was taken under, when it was taken, and one
--- entry per app carrying every window that app had open at the time. It knows nothing about
--- screens, windows, or the chooser. The plugin composition root in init.lua gives it a path
--- and everything else reaches it through the api that root builds.
---
--- The shape on disk.
---
---     {
---       "version": 2,
---       "layouts": [
---         {
---           "id": "…", "name": "Dev", "taken": "2026-09-15 21:10",
---           "topology": { "internal": true, "externals": 1 },
---           "apps": [
---             { "bundle": "com.mitchellh.ghostty", "name": "Ghostty", "excluded": false,
---               "windows": [ { "title": "…", "display": "external",
---                              "unit": { "x": 0, "y": 0, "w": 0.5, "h": 1 } } ] }
---           ]
---         }
---       ]
---     }
---
--- A window is remembered by the display it was on, named by role rather than by monitor, and
--- by its frame as a fraction of that display's visible frame. That is what lets a layout taken
--- in front of one external monitor apply in front of another of a different size.
---
--- The file lives under the olm data root in the home directory, layouts.json in this plugin's
--- own directory there, beside the speed test history and away from the config tree. A layout
--- is this machine's own record of its desk and its apps, taken by hand but personal all the
--- same, so it is not configuration and never reaches git. It was inside the config tree for
--- one evening, and the earlier automatic store sat there git ignored for two weeks before
--- that, so the lesson is that a store a plugin writes belongs under the storage root however
--- it is written.
---
--- An app that was removed from a layout stays in the file with excluded set, keeping its
--- windows, so an update does not resurrect it and including it again does not need a fresh
--- snapshot to have anything to place.
---
--- The table is read once and cached, every mutation lands on the cache, and the composition
--- root flushes after each one, since every write here is a person's own act rather than a burst
--- of events worth coalescing. A hand edit to the file is not seen until the next reload, the
--- same trade the DisplayProfiles store documents.
---
--- Being outside the config tree, a write here never touches the pathwatcher, so nothing about
--- the auto reload ignore list applies to this file.

local S = {}
S.__index = S

local log = hs.logger.new("Workspaces", "info")

local VERSION = 2

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

--- store.new(opts)
--- opts.storage  lib/storage.lua, which owns the roots and the join, so nothing here assembles
---               a path from a root by hand.
--- opts.dir      this plugin's own directory name under the durable root.
--- opts.file     the file name inside it.
--- Without storage every read answers empty and every write is a no op, which is how the
--- plugin degrades to a list that forgets everything on reload rather than failing.
function S.new(opts)
  opts = opts or {}
  return setmetatable({ storage = opts.storage, dirName = opts.dir, file = opts.file,
                        dir = nil, path = nil, cache = nil, dirty = false, sealed = false }, S)
end

-- The directory and the file, joined on first use rather than at configure. The storage lib
-- refuses to answer before the composition root has configured its roots, and the dry gate
-- loads and configures this plugin under a stub where nothing has, so a store that asked at
-- configure would read as a plugin the gate cannot check. Asking on the first read or write
-- keeps configure pure and the gate answering.
function S:_resolve()
  if self.path or not self.storage then return end
  self.dir = self.storage.dataDir(self.dirName)
  self.path = self.dir .. "/" .. self.file
end

-- Move the file aside under a stamped name that can never collide with an earlier rescue, and
-- say where it went. When even that fails the store seals itself, reading as empty for the rest
-- of the session and refusing every write, because a memory that stops working is recoverable
-- and one that was overwritten is not.
function S:_setAside(why, suffix)
  local aside = self.path .. "." .. suffix .. "." .. os.date("%Y%m%d%H%M%S")
  if os.rename(self.path, aside) then
    log.w(why .. ", so " .. self.path .. " was moved to " .. aside .. " and a fresh one will be written")
  else
    self.sealed = true
    log.e(why .. ", and " .. self.path .. " could not be moved aside either, so nothing will be "
      .. "written over it and this session's layouts are lost on reload")
  end
end

-- The whole table, read from disk the first time and held after that. A missing file starts
-- from empty, which is what a first run looks like. The file is stat'd first, since hs.json.read
-- logs a noisy error on a missing file.
function S:_all()
  if self.cache then return self.cache end
  self:_resolve()
  local all = { version = VERSION, layouts = {} }
  if self.path and hs.fs.attributes(self.path) then
    local read = hs.json.read(self.path)
    if type(read) ~= "table" or type(read.layouts) ~= "table" then
      -- A FILE THAT IS THERE AND WILL NOT PARSE, OR IS NOT THIS SHAPE, IS NEVER SILENTLY
      -- REPLACED, it is the only copy of every layout a person ever took.
      self:_setAside("could not read the layouts file", "corrupt")
    else
      all = read
      if type(all.version) ~= "number" then all.version = VERSION end
    end
  end
  self.cache = all
  return all
end

--- S:flush()
--- Write the cached table back, pretty printed so a hand edit or a git diff reads cleanly.
--- Does nothing when nothing changed or when there is no path, and answers whether a write
--- actually happened.
function S:flush()
  if not self.dirty then return true end
  self:_resolve()
  if self.sealed or not self.path then
    self.dirty = false
    return false
  end
  -- The directory is made on the first write rather than at configure, since a fresh machine
  -- has no olm root yet and a plugin that never stores anything should leave none behind.
  self.storage.ensure(self.dir)
  local ok = hs.json.write(self:_all(), self.path, true, true) == true
  if ok then self.dirty = false else log.e("could not write " .. tostring(self.path)) end
  return ok
end

--- S:list()
--- Every layout, sorted by name so two reads answer the same order. The live tables rather than
--- copies, since the engine reads windows off them and the chooser reads only through the api,
--- and copying a whole layout per keystroke is a cost with no caller that needs it.
function S:list()
  local out = {}
  for _, layout in ipairs(self:_all().layouts) do
    if type(layout) == "table" and type(layout.id) == "string" then out[#out + 1] = layout end
  end
  table.sort(out, function(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end)
  return out
end

--- S:get(id)
--- One layout by id, or nil.
function S:get(id)
  if not id then return nil end
  for _, layout in ipairs(self:_all().layouts) do
    if type(layout) == "table" and layout.id == id then return layout end
  end
  return nil
end

--- S:nameExists(name)
--- Whether any layout already goes by this name, so a rename or a new snapshot never produces
--- two rows a person cannot tell apart.
function S:nameExists(name)
  for _, layout in ipairs(self:_all().layouts) do
    if type(layout) == "table" and layout.name == name then return true end
  end
  return false
end

-- Whether the snapshot the engine handed over has the shape this file stores. A snapshot is
-- built by the engine from live screens and windows, so a wrong shape here is a defect in the
-- engine rather than a state to tolerate, and it is refused with a message rather than written.
local function validSnapshot(snapshot)
  if type(snapshot) ~= "table" then return false end
  if type(snapshot.topology) ~= "table" then return false end
  if type(snapshot.apps) ~= "table" then return false end
  return true
end

--- S:add(name, snapshot)
--- A new layout named by the person and filled from a snapshot the engine took. Returns the new
--- layout's id, or nil plus a message when the name is empty, already used, or the snapshot is
--- not one.
function S:add(name, snapshot)
  name = trim(name)
  if name == "" then return nil, "name is empty" end
  if self:nameExists(name) then return nil, "name already used" end
  if not validSnapshot(snapshot) then return nil, "not a snapshot" end
  local layout = {
    id = hs.host.uuid(),
    name = name,
    taken = os.date("%Y-%m-%d %H:%M"),
    topology = { internal = snapshot.topology.internal == true, externals = snapshot.topology.externals or 0 },
    apps = {},
  }
  for _, app in ipairs(snapshot.apps) do
    layout.apps[#layout.apps + 1] = { bundle = app.bundle, name = app.name, excluded = false, windows = app.windows }
  end
  local all = self:_all()
  all.layouts[#all.layouts + 1] = layout
  self.dirty = true
  return layout.id
end

--- S:update(id, snapshot)
--- Replace what a layout records with a fresh snapshot, keeping its name and its exclusions. An
--- app excluded before stays excluded, with the new windows when it is open now and the old ones
--- when it is not, so an update never resurrects a pruned app and including it again always has
--- something to place. An app that was included and is not open now leaves the layout, which is
--- what replacing the record means.
function S:update(id, snapshot)
  local layout = self:get(id)
  if not layout then return false, "layout not found" end
  if not validSnapshot(snapshot) then return false, "not a snapshot" end
  local excludedBefore = {}
  for _, app in ipairs(layout.apps or {}) do
    if app.excluded then excludedBefore[app.bundle] = app end
  end
  local apps, seen = {}, {}
  for _, app in ipairs(snapshot.apps) do
    seen[app.bundle] = true
    apps[#apps + 1] = { bundle = app.bundle, name = app.name,
      excluded = excludedBefore[app.bundle] ~= nil, windows = app.windows }
  end
  for bundle, app in pairs(excludedBefore) do
    if not seen[bundle] then apps[#apps + 1] = app end
  end
  layout.apps = apps
  layout.topology = { internal = snapshot.topology.internal == true, externals = snapshot.topology.externals or 0 }
  layout.taken = os.date("%Y-%m-%d %H:%M")
  self.dirty = true
  return true
end

--- S:setExcluded(id, bundle, excluded)
--- Mark one app as left out of a layout, or bring it back. Returns true, or false plus a message
--- when the layout or the app is not there.
function S:setExcluded(id, bundle, excluded)
  local layout = self:get(id)
  if not layout then return false, "layout not found" end
  for _, app in ipairs(layout.apps or {}) do
    if app.bundle == bundle then
      app.excluded = excluded == true
      self.dirty = true
      return true
    end
  end
  return false, "that app is not in this layout"
end

--- S:rename(id, newName)
--- Give a layout a different name. Returns true, or false plus a message when the name is
--- empty, already used, or the layout is not there.
function S:rename(id, newName)
  newName = trim(newName)
  if newName == "" then return false, "name is empty" end
  local layout = self:get(id)
  if not layout then return false, "layout not found" end
  if layout.name == newName then return true end
  if self:nameExists(newName) then return false, "name already used" end
  layout.name = newName
  self.dirty = true
  return true
end

--- S:remove(id)
--- Delete a layout for good. Returns true, or false plus a message when it is not there.
function S:remove(id)
  local all = self:_all()
  for i, layout in ipairs(all.layouts) do
    if type(layout) == "table" and layout.id == id then
      table.remove(all.layouts, i)
      self.dirty = true
      return true
    end
  end
  return false, "layout not found"
end

return S
