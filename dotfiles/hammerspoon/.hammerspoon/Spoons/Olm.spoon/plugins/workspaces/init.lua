--- === Workspaces ===
---
--- Remember where windows belong per display configuration, and put them back automatically.
--- One plugin replacing both DisplayMemory and WindowMemory, which each remembered half of this
--- and neither of which was ever started.
---
--- A configuration is identified by the point geometry of the attached screens rather than by
--- monitor identity, so vendor, model, pixel resolution, and plug order all stop mattering.
--- Capture is automatic and continuous, restore is automatic on a configuration change and on a
--- fresh app launch. DisplayProfiles owns the physical arrangement through displayplacer and
--- this plugin never talks to displayplacer, the two staying independent and ordering themselves
--- through the shared screen event rather than through any coupling.
---
--- This file is the plugin composition root, following the composition root, engine, store,
--- chooser layout the settled plugins use. It loads three siblings by loadfile and wires them,
--- and names no policy of its own beyond building the seam between them. engine.lua is the
--- mechanism, it watches, remembers, and restores, and knows nothing about a chooser.
--- store.lua persists the durable half in one JSON file. chooser.lua is the inspect and prune
--- surface, pure command policy over an injected api. The api this root builds is that one seam,
--- so the chooser never reaches the engine or the store directly and the engine never learns
--- that a surface exists.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Workspaces"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("Workspaces", "info")

-- Load the siblings by absolute path off this file's own location, loadfile rather than require
-- since a spoon directory is not on package.path. The helper wraps loadfile so a broken sibling
-- fails with a Workspaces prefixed message rather than a bare Lua error. The chooser is exposed
-- so the wiring layer can reach its own configure step and the registrar can resolve its
-- presentation members.
local pluginPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(pluginPath .. name)
  if not chunk then
    error("Workspaces: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end
local engine = load("engine.lua")
local store = load("store.lua")
obj.chooser = load("chooser.lua")

-- Owned state
obj._store = nil  -- the persistent layer, or nil when no path arrived

--- Workspaces:init()
--- Method
--- Initialize the plugin. No side effects, per the lifecycle contract.
function obj:init()
  return self
end

-- Everything the chooser is allowed to know, and the one place the engine and the store are
-- joined. Read methods are cheap, both layers are already in memory. Every write goes through
-- here so the two layers can never disagree, which is why forgetting an app drops it from the
-- session layer as well, and deleting a configuration drops its whole session slot. Forgetting
-- only the durable half would not be forgetting, since the session layer wins on restore and
-- would put the app back from a memory nobody can see.
function obj:_buildApi()
  return {
    -- Every configuration, active first and marked, each carrying how many apps it remembers.
    list = function()
      local active = engine:current()
      local out = {}
      for _, entry in ipairs(self._store and self._store:list() or {}) do
        local apps = 0
        for _ in pairs(entry.apps or {}) do apps = apps + 1 end
        out[#out + 1] = {
          fingerprint = entry.fingerprint,
          name = entry.name,
          apps = apps,
          active = entry.fingerprint == active,
        }
      end
      table.sort(out, function(a, b)
        if a.active ~= b.active then return a.active end
        return a.name < b.name
      end)
      return out
    end,

    -- Whether there is a durable layer at all, so the surface can say what is missing rather
    -- than showing an empty list that looks like nothing was ever remembered.
    persists = function() return self._store ~= nil end,

    active = function() return engine:current() end,

    -- One configuration's remembered apps, each with the name a person would recognise, sorted
    -- so the list does not reshuffle between keystrokes.
    apps = function(fingerprint)
      local entry = self._store and self._store:get(fingerprint)
      local out = {}
      for bundleID, frame in pairs((entry or {}).apps or {}) do
        out[#out + 1] = {
          bundleID = bundleID,
          name = hs.application.nameForBundleID(bundleID) or bundleID,
          frame = frame,
        }
      end
      table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
      return out
    end,

    -- Whether a name is taken, so a rename never produces two configurations a person cannot
    -- tell apart in a list.
    exists = function(name) return self._store ~= nil and self._store:nameExists(name) end,

    restore = function() engine:restoreNow() end,

    rename = function(fingerprint, newName)
      if not self._store then return false, "nothing is persisted, so there is no name to change" end
      local ok, err = self._store:rename(fingerprint, newName)
      if ok then self._store:flush() end
      return ok, err
    end,

    remove = function(fingerprint)
      if not self._store then return false, "nothing is persisted, so there is nothing to remove" end
      local ok, err = self._store:remove(fingerprint)
      if ok then
        engine:forgetSession(fingerprint)
        self._store:flush()
      end
      return ok, err
    end,

    forget = function(fingerprint, bundleID)
      if not self._store then return false, "nothing is persisted, so there is nothing to forget" end
      local ok, err = self._store:forgetApp(fingerprint, bundleID)
      if ok then
        engine:forgetSessionApp(fingerprint, bundleID)
        self._store:flush()
      end
      return ok, err
    end,
  }
end

--- Workspaces:configure(opts)
--- Method
--- opts.storePath  absolute path to the JSON file, supplied by the root since only it knows
---                 where a person's own editable data lives. Without it the durable layer is
---                 disabled and the plugin runs on the session layer alone, which still covers
---                 docking and undocking within one login.
--- Builds the store, injects it into the engine along with the callback that lets a
--- configuration change correct whatever the chooser is showing, and hands the chooser its api.
--- The chooser's stage words arrive separately, through its own wiring step, so this is safe to
--- call before or after that.
function obj:configure(opts)
  opts = opts or {}
  if opts.storePath then
    self._store = store.new({ path = opts.storePath })
  end
  engine:configure({
    store = self._store,
    onChange = function() self.chooser.refresh() end,
  })
  self.chooser:configure({ api = self:_buildApi() })
  return self
end

--- Workspaces:start()
--- Method
--- Start watching and run the first restore pass. THIS IS THE STEP THE TWO PLUGINS THIS ONE
--- REPLACES BOTH LACKED. Configure alone builds an engine that watches nothing, so the manifest
--- declares this as a wiring step and that declaration is the whole difference between a plugin
--- that works and one that loads, reports success, and does nothing for a year.
function obj:start()
  engine:start()
  local configurations = self._store and #self._store:list() or 0
  log.i(string.format("%d configuration(s) remembered, persistence %s",
    configurations, self._store and "on" or "off"))
  return self
end

--- Workspaces:stop()
--- Method
--- Stop watching and flush whatever was pending. Whatever is remembered is kept.
function obj:stop()
  engine:stop()
  return self
end

--- Workspaces:current()
--- Method
--- The fingerprint of the configuration attached right now, for the console and for anything
--- that later wants to ask.
function obj:current()
  return engine:current()
end

return obj
