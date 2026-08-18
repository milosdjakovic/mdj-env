--- === DisplayProfiles ===
---
--- Keep display arrangements deterministic, and inspect and manage the saved ones. macOS
--- remembers arrangements per hardware set, but a dock waking monitors in a different order
--- can still leave the wrong main display, wrong scaling, or windows on the wrong screen, and
--- the Settings UI gives no way to force it back. This spoon watches for screen changes and
--- reapplies the saved arrangement that fits whatever is attached, through displayplacer.
---
--- This file is the spoon composition root, following the composition root, engine, provider layout. It loads
--- three siblings and wires them, and names no policy of its own beyond the merge. engine.lua
--- is the mechanism, it watches, matches, and applies, and knows nothing about machines or a
--- catalog. store.lua persists the captured profiles in a git tracked JSON file. chooser.lua
--- is the inspect and manage surface, pure command policy over an injected api. The api this
--- root builds is the one seam that joins them, the merge of the curated profiles from
--- config/displays.lua, injected by the main root, with the captured ones from the store.
---
--- The public contract stays what the rest of the config already calls, the colon methods
--- current, reconcile, apply, capture, configure, start, and stop, all delegating to the
--- engine, so the overlay display policy that reads current() and the main root that starts
--- the spoon are untouched. The new surface hangs off obj.chooser, dot called, a shape the
--- main root can register and gate like the other list tools.
---
--- A profile matches when the number of screens it names equals the number attached and
--- every id it names is attached, comparing persistent and serial ids, so a profile written
--- with portable serial ids matches on any machine those same monitors reach. The first
--- match wins. Only captured profiles are editable from the tool, the curated ones are read
--- only, so the tool never rewrites the hand maintained config/displays.lua.
---
--- This is the olm side copy of DisplayProfiles, phase six of the olm build plan, and the
--- original this was copied from lived at Spoons/DisplayProfiles.spoon.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "DisplayProfiles"
obj.version = "2.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("DisplayProfiles", "info")

-- Load the siblings by absolute path off this file's own location, the loadfile pattern the spoons use
-- (loadfile, not require, since a spoon directory is not on package.path). The load helper
-- wraps loadfile so a broken sibling fails with a DisplayProfiles-prefixed message rather
-- than a bare Lua error. The chooser is exposed so the main root can reach its surface.
local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(spoonPath .. name)
  if not chunk then
    error("DisplayProfiles: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end
local engine = load("engine.lua")
local store = load("store.lua")
obj.chooser = load("chooser.lua")

-- Owned state
obj._store = nil        -- the captured profile persistence, or nil when no path was given
obj._curated = nil      -- the read only reference profiles injected by the main root
obj._settleDelay = nil  -- kept so a rebuild re-injects it rather than resetting the engine

--- DisplayProfiles:init()
--- Method
--- Initialize the spoon. No side effects, per the lifecycle contract.
function obj:init()
  return self
end

-- The current merged view, curated first then captured, each entry carrying whether it is
-- editable. Curated profiles are never editable from the tool, captured ones always are.
function obj:_merged()
  local out = {}
  for _, p in ipairs(self._curated or {}) do
    out[#out + 1] = { name = p.name, command = p.command, editable = false }
  end
  if self._store then
    for _, p in ipairs(self._store:list()) do
      out[#out + 1] = { name = p.name, command = p.command, editable = true }
    end
  end
  return out
end

-- Re-inject the merged list into the engine and force a reapply. Called after a store write,
-- so a capture, rename, or delete takes effect in the running config without a reload. The
-- settle delay is passed again since configure defaults it when omitted.
function obj:_rebuild()
  engine:configure({ profiles = self:_merged(), settleDelay = self._settleDelay, binary = self._binary })
  engine:reconcile(true)
end

-- Whether a name is used by any profile, curated or captured, so a capture or rename never
-- collides with a curated name either.
function obj:_nameExists(name)
  for _, p in ipairs(self:_merged()) do
    if p.name == name then return true end
  end
  return false
end

-- The api the chooser policy talks through, the one seam over the engine and the store. Read
-- methods are cheap, the engine caches the attached set. The write methods guard uniqueness
-- across the whole merged set, delegate the persistence to the store, and rebuild the engine
-- on success so the change is live at once.
function obj:_buildApi()
  return {
    list = function() return self:_merged() end,
    active = function() return engine:current() end,
    displays = function(command) return engine:parseDisplays(command) end,
    exists = function(name) return self:_nameExists(name) end,
    reapply = function() engine:reconcile(true) end,
    capture = function(name)
      if not self._store then return false, "no store configured" end
      if self:_nameExists(name) then return false, "name already used" end
      local command = engine:currentCommand()
      if not command then return false, "could not read the current arrangement" end
      local ok, err = self._store:add(name, command)
      if ok then self:_rebuild() end
      return ok, err
    end,
    rename = function(oldName, newName)
      if not self._store then return false, "no store configured" end
      if newName ~= oldName and self:_nameExists(newName) then return false, "name already used" end
      local ok, err = self._store:rename(oldName, newName)
      if ok then self:_rebuild() end
      return ok, err
    end,
    remove = function(name)
      if not self._store then return false, "no store configured" end
      local ok, err = self._store:remove(name)
      if ok then self:_rebuild() end
      return ok, err
    end,
  }
end

--- DisplayProfiles:configure(opts)
--- Method
--- opts.profiles    the curated reference profiles, KEYED BY HOST, straight out of
---                  config/displays.lua, read only from the tool. This plugin takes the slice
---                  belonging to opts.host itself, since an arrangement of monitors is a fact
---                  about one desk and a person with two machines has two sets. Defaults to
---                  empty.
--- opts.settleDelay seconds to coalesce a burst of screen events before applying.
--- opts.host        LocalHostName, both the key the curated profiles are looked up under and the
---                  key the captured JSON is stored under. Without it the store is disabled and
---                  no curated profile can be found either.
--- opts.storePath   absolute path to the captured profiles JSON, supplied by the root since only
---                  it knows where a person's own editable data lives. Without it the store is
---                  disabled.
--- opts.deps        the scoped tool path adapter, earned by declaring displayplacer. The
---                  resolved path is asked for HERE rather than arriving ready made, which is
---                  what declaring a tool actually entitles a plugin to.
--- Builds the store, merges curated and captured, injects the merged list into the engine,
--- and hands the chooser its api. The chooser's view deps (theme, factory, panel callbacks)
--- come separately from the main root, so this is safe to call before or after that.
function obj:configure(opts)
  opts = opts or {}

  -- The person's own file is keyed by host and this takes its own machine's slice, which the
  -- retired root used to do before injecting. Nothing did it afterwards, so what arrived was the
  -- whole hostname keyed table, and every walk of it with ipairs found zero entries, so the tool
  -- came up with no curated profile at all on a machine that has four.
  --
  -- Done here rather than back in the root deliberately. That a curated arrangement belongs to
  -- one desk is this plugin's own domain knowledge, it already receives the host for the store,
  -- and doing it here means a person's own configuration stays one plain table they can read.
  local curated = opts.profiles or {}
  if opts.host and type(curated[opts.host]) == "table" then
    curated = curated[opts.host]
  end
  self._curated = curated

  self._settleDelay = opts.settleDelay
  -- Asked of the scope adapter rather than read off a field nobody fills.
  --
  -- opts.binary was what this read, and no channel anywhere supplies it. Declaring a tool earns
  -- the ADAPTER, under opts.deps, never a resolved path under a name of the plugin's own choosing,
  -- so the path was nil however the tool was installed and every arrangement the engine tried to
  -- apply did nothing. The same mistake was in three plugins at once, each with its own field
  -- name, which is what makes it a class rather than a typo.
  self._binary = opts.deps and opts.deps.path("displayplacer") or nil
  if opts.host and opts.storePath then
    self._store = store.new({ path = opts.storePath, host = opts.host })
  end
  engine:configure({
    profiles = self:_merged(),
    settleDelay = opts.settleDelay,
    binary = self._binary,
    onChange = function() self.chooser.refresh() end,
  })
  self.chooser:configure({ api = self:_buildApi() })
  return self
end

--- DisplayProfiles:start()
--- Method
--- Start the engine watcher and its first reconcile. The chooser is built by the main root
--- once its view deps are injected, so it is not started here.
function obj:start()
  engine:start()
  local nCurated = #(self._curated or {})
  local nCaptured = self._store and #self._store:list() or 0
  log.i(string.format("%d curated, %d captured profile(s) merged for this host", nCurated, nCaptured))
  return self
end

--- DisplayProfiles:stop()
--- Method
--- Stop watching. The current arrangement is left untouched.
function obj:stop()
  engine:stop()
  return self
end

--- DisplayProfiles:current()
--- Method
--- The name of the profile matching the displays attached right now, or nil. Read by the
--- overlay display policy in the main root, so this contract is kept.
function obj:current()
  return engine:current()
end

--- DisplayProfiles:profiles()
--- Method
--- The merged profiles as an ordered list of { name, ids }, curated first then captured,
--- where ids are the displayplacer id tokens in the profile's command order, deduped. Read
--- by the overlay display picker in the main root so it can offer each setup's displays to
--- pin, without re-detecting anything. Reuses the engine's command parse rather than adding
--- a second one, and returns fresh tables so a caller cannot mutate any internal state.
function obj:profiles()
  local out = {}
  for _, p in ipairs(self:_merged()) do
    local ids, seen = {}, {}
    for _, d in ipairs(engine:parseDisplays(p.command)) do
      if d.id and not seen[d.id] then
        seen[d.id] = true
        ids[#ids + 1] = d.id
      end
    end
    out[#out + 1] = { name = p.name, ids = ids }
  end
  return out
end

--- DisplayProfiles:reconcile(force)
--- Method
--- Reapply the matching profile, forcing it when force is set.
function obj:reconcile(force)
  engine:reconcile(force)
  return self
end

--- DisplayProfiles:apply(name)
--- Method
--- Force a named layout, ignoring what is attached.
function obj:apply(name)
  engine:apply(name)
  return self
end

--- DisplayProfiles:capture(toClipboard)
--- Method
--- Print the current arrangement as a displayplacer command, optionally to the clipboard,
--- the console helper config/displays.lua documents.
function obj:capture(toClipboard)
  engine:capture(toClipboard)
  return self
end

return obj
