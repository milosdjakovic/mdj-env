--- === Chooser ===
---
--- The picker facade and provider registry. One contract, two swappable
--- backends. `native` wraps the built in hs.chooser, the original atom, and
--- `web` is the themed webview list built on the Surface spoon. Every consumer
--- calls the same Chooser.new(config); the only thing that changes between
--- backends is which one is wired.
---
--- This is the Strategy pattern behind a provider seam, the same shape the other
--- spoons use. The engine (a consumer's picker code) depends only on the
--- contract, show, hide, isShowing, refresh, selectNext, selectPrev,
--- insertSelected, selectedItem, query, setFieldMode, setPlaceholder,
--- activeTheme, and the composition root names the concrete backend. Swapping is
--- one line, and the old native chooser stays as a fallback rather than being
--- deleted.
---
--- Wiring from the composition root:
---   spoon.Chooser:configure({ provider = "web", surface = spoon.Surface })
--- provider is the default backend, "native" or "web". The web backend needs the
--- Surface spoon injected, since it builds its list on it. A single instance can
--- override the default with config.provider, so one picker can be web while the
--- rest stay native during a migration.

local obj = {}
obj.__index = obj
obj.name = "Chooser"
obj.version = "2.0"
obj.author = "mdj-env"

-- Load providers by absolute path, the Capture idiom (a spoon dir is not on
-- package.path). native.lua is self contained; web.lua is a builder that takes
-- the injected Surface spoon and returns the provider.
local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(spoonPath .. name)
  if not chunk then
    error("Chooser: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end

local native = load("providers/native.lua")
local buildWeb = load("providers/web.lua")

obj._provider = "native" -- the default backend until configure names another
obj._web = nil           -- built once a surface is injected

--- Chooser:init() - nothing to build; providers are resolved lazily.
function obj:init()
  return self
end

--- Chooser:configure(opts) - opts.provider sets the default backend, opts.surface
--- injects the Surface spoon the web backend builds on. Safe to call before any
--- picker is created.
function obj:configure(opts)
  opts = opts or {}
  if opts.provider then obj._provider = opts.provider end
  if opts.surface then obj._web = buildWeb(opts.surface) end
  return self
end

local function providerFor(name)
  if name == "web" then
    if not obj._web then
      error("Chooser: the web provider needs a surface; call Chooser:configure({ surface = spoon.Surface })")
    end
    return obj._web
  end
  return native
end

--- Chooser.new(config) -> picker instance. Dot called, matching the old atom.
--- config.provider overrides the configured default for this one instance.
function obj.new(config)
  config = config or {}
  return providerFor(config.provider or obj._provider).new(config)
end

return obj
