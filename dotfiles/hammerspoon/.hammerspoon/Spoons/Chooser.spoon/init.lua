--- === Chooser ===
---
--- The picker facade. One backend, native, wrapping the built in hs.chooser.
--- Every consumer calls the same Chooser.new(config) and gets an instance that
--- honors the picker contract, show, hide, isShowing, refresh, selectNext,
--- selectPrev, insertSelected, selectedItem, query, setFieldMode, setPlaceholder,
--- activeTheme.
---
--- This was once a provider registry with a second, webview backend built on a
--- Surface spoon, kept behind this facade so a consumer could swap backends with
--- one word. Every consumer settled on native, so the web backend was removed and
--- the facade collapsed to this thin passthrough. The seam stays here, so a future
--- backend is a new provider file plus a branch in new, not a change to any
--- consumer. A config.provider field is still accepted and ignored, since only the
--- native backend exists.

local obj = {}
obj.__index = obj
obj.name = "Chooser"
obj.version = "3.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- Load the native provider by absolute path, the loadfile pattern the spoons use
-- (a spoon dir is not on package.path). It is self contained and already honors
-- the full contract.
local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(spoonPath .. name)
  if not chunk then
    error("Chooser: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end

local native = load("providers/native.lua")

--- Chooser.matchers - the shared matching strategies, exposed so the composition root
--- names one and injects it, keeping the concrete policy in one place. Each is a
--- match(query, hay) -> score or nil. See match.lua.
obj.matchers = load("match.lua")

-- The screen policy every chooser resolves against, injected once by the composition
-- root so the consumers never thread it through themselves. It is the same seam
-- CanvasPanel reads, so the choosers and the cheat sheets agree on which display they
-- use. Nil until configured, in which case an instance falls back to the native
-- provider's own default (hs.screen.mainScreen).
local DEFAULT_SCREEN = nil

-- The matching strategy every filter-mode chooser inherits, injected once at the root
-- so fuzzy versus substring is decided in a single edit and applies uniformly. Nil
-- means the atom does no matching and the consumer's supplier owns filtering, the
-- pre-injection behaviour. A consumer passing matcher = false in its own config opts
-- out even when a default is set, for a tool whose query is not a plain filter.
local DEFAULT_MATCHER = nil

--- Chooser:init() - nothing to build; the native provider is loaded above.
function obj:init()
  return self
end

--- Chooser.configure(opts) - module-level defaults every new() inherits. opts.screen is
--- a function returning the hs.screen a chooser should appear on. opts.matcher is the
--- shared filter strategy from Chooser.matchers. One call at the root wires the overlay
--- display policy and the matching policy into every chooser at once.
function obj.configure(opts)
  opts = opts or {}
  DEFAULT_SCREEN = opts.screen
  DEFAULT_MATCHER = opts.matcher
  return obj
end

--- Chooser.new(config) -> picker instance. Dot called, matching the old atom. A
--- config.provider field is accepted and ignored, since native is the only backend.
--- The configured default screen and matcher policies are folded in unless the config
--- names its own. config.matcher = false opts out of the default so the supplier keeps
--- owning filtering; nil inherits the default.
function obj.new(config)
  config = config or {}
  if config.screen == nil then config.screen = DEFAULT_SCREEN end
  if config.matcher == nil then config.matcher = DEFAULT_MATCHER end
  return native.new(config)
end

return obj
