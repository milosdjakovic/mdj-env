--- === DisplayMemory ===
---
--- Remember which display an app's window was last moved to, scoped by location.
---
--- The reusable mechanism only. It watches one app's windows for moves across
--- displays, records the display the window lands on, and can answer with that
--- display later. It never decides a default and never decides what a "location"
--- is; the composition root injects the app to watch and a `scope` that names the
--- current location, and layers its own default under `rememberedScreen()`
--- returning nil. Identity is the display UUID, stable across reboots, and the
--- memory is a table from scope to display UUID stored under one `hs.settings`
--- key, so each location remembers independently and switching location switches
--- the slot with no extra wiring. hs.settings is per machine, so nothing here has
--- to name a machine for the memory to stay distinct across Macs.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "DisplayMemory"
obj.version = "2.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- Dependencies and config (injected via configure)
obj._bundleID = nil
obj._settingsKey = nil
obj._scope = nil
obj._filter = nil

--- DisplayMemory:init()
--- Method
--- Initialize the spoon
function obj:init()
  return self
end

--- DisplayMemory:configure(opts)
--- Method
--- Configure the spoon. opts.bundleID is the app whose windows to watch,
--- opts.settingsKey is the hs.settings key holding the scope-to-display map, and
--- opts.scope names the current location, either a string or a function returning
--- one (evaluated live, so it tracks docking and undocking). The composition root
--- decides what a location is; this spoon only keys on the string it returns.
function obj:configure(opts)
  opts = opts or {}
  self._bundleID = opts.bundleID
  self._settingsKey = opts.settingsKey or "displayMemory"
  self._scope = opts.scope
  return self
end

--- DisplayMemory:_scopeKey()
--- Method
--- The current location scope as a string. A function scope is called live, a
--- string is used as is, and nil collapses to one shared slot.
function obj:_scopeKey()
  local s = self._scope
  if type(s) == "function" then s = s() end
  if type(s) ~= "string" or s == "" then return "default" end
  return s
end

--- DisplayMemory:_remember(win)
--- Method
--- Record, under the current scope, the display the given window sits on, if it
--- changed.
function obj:_remember(win)
  if not win then return end
  local screen = win:screen()
  if not screen then return end
  local uuid = screen:getUUID()
  if not uuid then return end
  local scope = self:_scopeKey()
  local mem = hs.settings.get(self._settingsKey) or {}
  if mem[scope] ~= uuid then
    mem[scope] = uuid
    hs.settings.set(self._settingsKey, mem)
  end
end

--- DisplayMemory:start()
--- Method
--- Begin watching the configured app for window moves. Idempotent.
function obj:start()
  if self._filter or not self._bundleID then return self end

  local bundleID = self._bundleID
  self._filter = hs.window.filter.new(function(win)
    if not win then return false end
    local app = win:application()
    return app ~= nil and app:bundleID() == bundleID
  end)

  self._filter:subscribe(hs.window.filter.windowMoved, function(win)
    self:_remember(win)
  end)

  return self
end

--- DisplayMemory:stop()
--- Method
--- Stop watching.
function obj:stop()
  if self._filter then
    self._filter:unsubscribeAll()
    self._filter = nil
  end
  return self
end

--- DisplayMemory:rememberedScreen()
--- Method
--- The display remembered for the current scope if it is still attached, else nil
--- so a caller can fall back to its own default.
function obj:rememberedScreen()
  local mem = hs.settings.get(self._settingsKey) or {}
  local uuid = mem[self:_scopeKey()]
  if not uuid then return nil end
  for _, s in ipairs(hs.screen.allScreens()) do
    if s:getUUID() == uuid then return s end
  end
  return nil
end

return obj
