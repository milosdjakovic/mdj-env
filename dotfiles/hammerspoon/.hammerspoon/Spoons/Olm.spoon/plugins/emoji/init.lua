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
--- first available one, so a backend that never wins never pays its setup cost.
---
--- Migrated onto host/stage, the trickle migration. Whichever backend wins, only the
--- hammerspoon backend ever owns a list, lists() below is exactly that question, and only
--- that backend is ever shown through the shared stage. show branches on it, presenting
--- through cfg.stagePresent when the winner lists and calling straight through to the
--- winner's own show otherwise, which is unchanged for the macos and custom backends, both
--- always having driven their own keys with no chooser and no navigation surface of their
--- own to route. The presentation itself belongs to this facade rather than to the
--- hammerspoon backend, plugins/emoji/providers/hammerspoon.lua, since the facade is the one
--- thing every launcher row, scope, and key already reaches, and its own rows and select
--- simply ask whichever backend won for the answer, the identical forwarding this file
--- already did for a scope's own rows and run before the stage existed to ask for it too.
---
--- This is the olm side copy of Emoji, copied into the plugins directory in phase six of
--- the build plan, the bundling pass. Its vendored data.lua travels unchanged as the
--- committed artifact it is, never regenerated from this side, and the original this was
--- copied from lived at Spoons/Emoji.spoon.

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

obj._active = nil        -- the resolved winning backend, set at configure
obj._stagePresent = nil  -- root published, the hotkey door onto the shared stage

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
--- needs from, onInsert among them. Only the winner is configured, so an unused backend
--- pays no setup cost. opts.stagePresent is the root published hotkey door onto the shared
--- stage, read here rather than only forwarded, since show below needs it directly and no
--- backend reaches for it on this facade's behalf.
function obj:configure(opts)
  opts = opts or {}
  local order = opts.providers
  if type(order) ~= "table" or #order == 0 then
    order = { self.providers.hammerspoon }
  end
  self._active = self:_resolve(order)
  self._active:configure(opts)
  self._stagePresent = opts.stagePresent
  return self
end

--- Emoji:show()
--- Method
--- Open the selected backend. When it owns a list, that list is presented through the
--- shared stage exactly as every other presenting tool's hotkey door is, cfg.stagePresent
--- asking the registry for this plugin's own presentation and handing it to Stage:present.
--- The macos and custom backends never own a list, lists() answering false for both, so
--- each is shown by calling straight through to its own show, unchanged, since neither has
--- ever had a chooser or a navigation surface to route through this host.
function obj:show()
  if self:lists() then
    if self._stagePresent then self._stagePresent("emoji") end
  elseif self._active then
    self._active:show()
  end
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
--- Insert a glyph the caller picked from rows above, through the same path a pick made via
--- the shared stage takes, so a pick made elsewhere is remembered too. Named on the
--- manifest's own presentation block as the contract's select, the word every presenting
--- plugin's own onSelect answers to.
function obj:insert(glyph)
  if not self:lists() then return end
  self._active:insert(glyph)
end

--- Emoji:placeholder() -> string
--- Method
--- The field hint while this plugin's own presentation is current, named on the manifest's
--- own presentation block. Resolved once, at register, since the presentation contract
--- wants a plain string a presentation carries rather than a function to call again later.
--- Only the hammerspoon backend is ever presented, lists() being what decides that in show
--- above, so this names that backend's own wording directly rather than asking a backend
--- that will never be shown through the stage at all.
function obj:placeholder()
  return "Search by name or keyword"
end

-- surface is gone, the trickle migration, deleted along with the Chooser.new block that
-- gave it something to answer for. The composition root now routes this plugin's own
-- navigation through host/stage's own surfaceFor once wiredRegistry.presentationFor("emoji")
-- answers a presentation, which is unconditional regardless of which backend won, matching
-- the old NOOP_SURFACE's own always-false isShowing for the macos and custom backends, since
-- show above never presents through the stage for either of them, so stage:current() is
-- simply never "emoji" while one of those two is what actually opened.

return obj
