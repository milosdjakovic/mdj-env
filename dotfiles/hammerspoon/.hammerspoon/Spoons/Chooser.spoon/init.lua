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
obj.author = "mdj-env"

-- Load the native provider by absolute path, the Capture idiom (a spoon dir is not
-- on package.path). It is self contained and already honors the full contract.
local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(spoonPath .. name)
  if not chunk then
    error("Chooser: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end

local native = load("providers/native.lua")

-- The screen policy every chooser resolves against, injected once by the composition
-- root so the five consumers never thread it through themselves. It is the same seam
-- CanvasPanel reads, so the choosers and the cheat sheets agree on which display they
-- use. Nil until configured, in which case an instance falls back to the native
-- provider's own default (hs.screen.mainScreen).
local DEFAULT_SCREEN = nil

--- Chooser:init() - nothing to build; the native provider is loaded above.
function obj:init()
  return self
end

--- Chooser.configure(opts) - module-level defaults every new() inherits. opts.screen is
--- a function returning the hs.screen a chooser should appear on. One call at the root
--- wires the shared overlay display policy into every chooser at once.
function obj.configure(opts)
  opts = opts or {}
  DEFAULT_SCREEN = opts.screen
  return obj
end

--- Chooser.new(config) -> picker instance. Dot called, matching the old atom. A
--- config.provider field is accepted and ignored, since native is the only backend.
--- The configured default screen policy is folded in unless the config names its own.
function obj.new(config)
  config = config or {}
  if config.screen == nil then config.screen = DEFAULT_SCREEN end
  return native.new(config)
end

return obj
