--- === Emoji ===
---
--- The emoji picker facade. It owns no picker of its own, it selects one backend from a
--- priority ordered list and delegates to it, so the same Hyper+J opens whichever emoji
--- picker you prefer. The composition root names the order, so this facade is the only
--- place that knows the set of backends and the root is the only place that names them,
--- the Strategy pattern selected by a Chain of Responsibility and wired through injection.
---
--- Three backends ship, each a provider under providers/ honoring one small contract,
--- isAvailable, configure, show, isShowing, and surface. The hammerspoon backend is the
--- picker built over the Chooser atom, the macos backend triggers the system Character
--- Viewer, and the custom backend runs an injected callback so any external picker reached
--- by a URL scheme, a remapped key, or a remote trigger becomes a backend with no file of
--- its own. The root imports these from Emoji.providers and lists them by reference, not by
--- name, so a swap is one edit and a bad reference is a load error rather than a silent miss.
---
--- configure walks the list, logs any backend it finds unavailable, and configures only the
--- first available one, so a backend that never wins never pays its setup cost. show,
--- isShowing, and surface all delegate to that winner, and the winner's surface is what the
--- root registers in the shared choosers list, a real navigation adapter for the hammerspoon
--- backend and a no op for the macos and custom ones since those drive their own keys.

local obj = {}
obj.__index = obj
obj.name = "Emoji"
obj.version = "2.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- Load the backends by absolute path, the loadfile pattern the spoons use, since a spoon directory is not on
-- package.path. Each file returns a provider object honoring the contract, except custom,
-- which returns a factory taking the injected behavior and returning such an object.
local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(spoonPath .. name)
  if not chunk then
    error("Emoji: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end

--- Emoji.providers - the available backends, for the composition root to list by reference
--- in its configure call. macos and hammerspoon are ready provider objects, custom is a
--- factory called with the behavior to run, custom(fn) or custom({ name, show, isAvailable,
--- isShowing }). Populated by init.
obj.providers = nil

-- A no op navigation surface, the facade's own guard for a call before configure or a
-- backend that returns no surface, so the shared navigation registry never sees a nil.
local NOOP_SURFACE = {
  isShowing = function() return false end,
  selectNext = function() end,
  selectPrev = function() end,
  insertSelected = function() end,
  hide = function() end,
}

obj._active = nil   -- the resolved winning backend, set at configure

--- Emoji:init()
--- Method
--- Load the backends and expose them on Emoji.providers, so the root can list them by
--- reference. No backend is configured yet, that waits for configure to pick the winner.
function obj:init()
  self.providers = {
    macos = load("providers/macos.lua"),
    hammerspoon = load("providers/hammerspoon.lua"),
    custom = load("providers/custom.lua"),
  }
  return self
end

-- Walk the priority order and return the first backend whose isAvailable is true, logging
-- any it skips so a missing external picker is visible in the console rather than silent. A
-- non backend entry is ignored with a warning. Falls back to the built in hammerspoon
-- backend, which is always available, when the order resolves to nothing.
function obj:_resolve(order)
  for _, p in ipairs(order) do
    if type(p) ~= "table" or type(p.isAvailable) ~= "function" then
      print("Emoji: an entry in providers is not a backend, skipping it")
    elseif not p:isAvailable() then
      print("Emoji: backend '" .. (p.name or "?") .. "' is not available, falling back")
    else
      print("Emoji: using backend '" .. (p.name or "?") .. "'")
      return p
    end
  end
  print("Emoji: no listed backend was available, using the built in hammerspoon backend")
  return self.providers.hammerspoon
end

--- Emoji:configure(opts)
--- Method
--- Pick the backend and wire it. opts.providers is the priority ordered list of backends by
--- reference, and the rest of opts is the shared wiring the winning backend reads what it
--- needs from, the Chooser factory, the theme, the placeholder, the docked shortcut panel,
--- and onInsert. Only the winner is configured, so an unused backend pays no setup cost.
function obj:configure(opts)
  opts = opts or {}
  local order = opts.providers
  if type(order) ~= "table" or #order == 0 then
    order = { self.providers.hammerspoon }
  end
  self._active = self:_resolve(order)
  self._active:configure(opts)
  return self
end

--- Emoji:show()
--- Method
--- Open the selected backend.
function obj:show()
  if self._active then self._active:show() end
end

--- Emoji:isShowing()
--- Method
--- Whether the selected backend reports itself open. A system backend we do not drive always
--- reports false, which keeps it out of the navigation registry.
function obj:isShowing()
  return self._active ~= nil and self._active:isShowing()
end

--- Emoji:lists()
--- Method
--- Whether the selected backend can hand its rows to another surface, which is an optional
--- part of the contract. Only a backend that owns its own list can, so a system picker or an
--- external one cannot, and the caller asks before assuming. This keeps the answer with the
--- facade rather than making every caller reason about which backend won.
function obj:lists()
  local p = self._active
  return p ~= nil and type(p.rows) == "function" and type(p.insert) == "function"
end

--- Emoji:rows(query) -> rows
--- Method
--- The selected backend's rows for a query, or an empty list when it cannot list. Forwarded
--- rather than interpreted, so the facade stays a facade.
function obj:rows(query)
  if not self:lists() then return {} end
  return self._active:rows(query)
end

--- Emoji:insert(glyph)
--- Method
--- Insert a glyph the caller picked from rows above, through the same path a pick in the
--- backend's own chooser takes, so a pick made elsewhere is remembered too.
function obj:insert(glyph)
  if not self:lists() then return end
  self._active:insert(glyph)
end

--- Emoji:surface()
--- Method
--- The navigation adapter of the selected backend for the shared choosers registry, or a no
--- op when the backend drives its own keys or before configure has run.
function obj:surface()
  if self._active and self._active.surface then
    return self._active:surface() or NOOP_SURFACE
  end
  return NOOP_SURFACE
end

return obj
