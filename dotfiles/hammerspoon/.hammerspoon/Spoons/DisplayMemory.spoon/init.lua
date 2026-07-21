--- === DisplayMemory ===
---
--- Remember which display an app's window was last moved to, per machine.
---
--- The reusable mechanism only. It watches one app's windows for moves across
--- displays, records the display the window lands on, and can answer with that
--- display later. It never decides a default and never names a machine; the
--- composition root injects the app to watch and this machine's name, and layers
--- its own default under `rememberedScreen()` returning nil. Identity is the
--- display UUID, stable across reboots, and the value is stored per machine via
--- `hs.settings` so each Mac remembers independently and the choice survives a
--- reload or a reboot.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "DisplayMemory"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- Dependencies and config (injected via configure)
obj._bundleID = nil
obj._settingsKey = nil
obj._host = nil
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
--- opts.settingsKey is the hs.settings base key, opts.host is this machine's
--- name (the per-machine scope, resolved once in the composition root).
function obj:configure(opts)
  opts = opts or {}
  self._bundleID = opts.bundleID
  self._settingsKey = opts.settingsKey or "displayMemory"
  self._host = opts.host or "default"
  return self
end

--- DisplayMemory:_key()
--- Method
--- The per-machine settings key.
function obj:_key()
  return self._settingsKey .. "." .. self._host
end

--- DisplayMemory:_remember(win)
--- Method
--- Record the display the given window currently sits on, if it changed.
function obj:_remember(win)
  if not win then return end
  local screen = win:screen()
  if not screen then return end
  local uuid = screen:getUUID()
  if not uuid then return end
  if hs.settings.get(self:_key()) ~= uuid then
    hs.settings.set(self:_key(), uuid)
  end
end

--- DisplayMemory:start()
--- Method
--- Begin watching the configured app for window moves. Idempotent.
function obj:start()
  if self._filter or not self._bundleID then return self end

  local bundleID = self._bundleID
  self._filter = hs.window.filter.new(function(win)
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
--- The remembered display if it is still attached, else nil so a caller can
--- fall back to its own default.
function obj:rememberedScreen()
  local uuid = hs.settings.get(self:_key())
  if not uuid then return nil end
  for _, s in ipairs(hs.screen.allScreens()) do
    if s:getUUID() == uuid then return s end
  end
  return nil
end

return obj
