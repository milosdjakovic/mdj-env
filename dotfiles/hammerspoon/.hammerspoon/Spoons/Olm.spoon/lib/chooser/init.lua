--- === Chooser ===
---
--- The picker facade. Two providers, default, the hand drawn canvas picker, and legacy,
--- wrapping the built in hs.chooser and deprecated.
--- Every consumer calls the same Chooser.new(config) and gets an instance validated
--- against the picker contract in contract.lua, the full twenty five names documented in
--- docs/CONTRACT-PICKER.md, show, hide, isShowing, isActive, refresh, selectNext,
--- selectPrev, insertSelected, selectedItem, selectedRow, selectRow, query,
--- setPlaceholder, setRows, rowCount, textBudget, textWidth, reposition,
--- settleDelay, matcher, setMatcher, titleLineBreak, setTitleLineBreak, setPaneWidth.
--- selectedRow and selectRow, phase eight of the build plan, are the plain public
--- counterpart of selectedItem, added for ActionPanel, which restores a highlight
--- by row number rather than by item. setRows, the geometry phase of the chooser
--- stage build, docs/BRIEF-GEOMETRY.md, remembers a row count for this instance's
--- next show, the one lib/chooser change that phase permits, host/stage/init.lua
--- being its one caller.
---
--- This was once a provider registry with a second, webview backend built on a
--- Surface spoon, kept behind this facade so a consumer could swap backends with
--- one word. Every consumer settled on the native hs.chooser, so the web backend was removed and
--- the facade collapsed to this thin passthrough. The seam stays here, so a future
--- backend is a new provider file plus a branch in new, not a change to any
--- consumer. A config.provider field is still accepted and ignored, since the
--- providers are chosen by configure alone.
---
--- This is the olm side copy of Chooser, moved into the core as lib/chooser in phase five of
--- the build plan, a directory rather than a single file because it loads two siblings. It
--- is a faithful copy, the module api and the instance contract are unchanged, so assigning
--- it to the Chooser spoon global is a drop in. The original this was copied from
--- lived at Spoons/Chooser.spoon.

local obj = {}
obj.__index = obj
obj.name = "Chooser"
obj.version = "3.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- Load the providers by absolute path, the loadfile pattern the spoons use
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

local legacy = load("providers/legacy.lua")
local default = load("providers/default/init.lua")

--- Chooser.providers - the picker providers, exposed the same way matchers are, so the
--- composition root names one and injects it through configure. The root picks default.
obj.providers = { default = default, legacy = legacy }

--- Chooser.matchers - the shared matching strategies, exposed so the composition root
--- names one and injects it, keeping the concrete policy in one place. Each is a
--- match(query, hay) -> score or nil. See match.lua.
obj.matchers = load("match.lua")

-- The picker contract, docs/CONTRACT-PICKER.md, added by the contract freeze phase. Every
-- instance new below builds is validated against it before decorate ever runs, so a
-- provider missing a method fails at construction with a reason naming the gap, rather
-- than surfacing later as a decorator wrapping a broken instance, which would bury it.
local contract = load("contract.lua")

-- The screen policy every chooser resolves against, injected once by the composition
-- root so the consumers never thread it through themselves. It is the same seam
-- CanvasPanel reads, so the choosers and the cheat sheets agree on which display they
-- use. Nil until configured, in which case an instance falls back to the legacy
-- provider's own default (hs.screen.mainScreen).
local DEFAULT_SCREEN = nil

-- The matching strategy every filter-mode chooser inherits, injected once at the root
-- so fuzzy versus substring is decided in a single edit and applies uniformly. Nil
-- means the atom does no matching and the consumer's supplier owns filtering, the
-- pre-injection behaviour. A consumer passing matcher = false in its own config opts
-- out even when a default is set, for a tool whose query is not a plain filter.
local DEFAULT_MATCHER = nil

-- The provider every new() builds through, injected once at the root so default versus
-- legacy is decided in a single edit. Nil falls back to legacy, since the default provider refuses to build until it is
-- configured, which differs from the screen and matcher defaults only in what nil means.
local DEFAULT_PROVIDER = nil

-- The one seam ActionPanel, phase eight of the build plan, installs through, so a
-- decorator wraps every consumer's config functions without any of the twelve call
-- sites to Chooser.new changing. Nil until configured, in which case new hands the
-- instance back undecorated, the pre-injection behaviour.
--
-- This is legal rather than a trick. legacy.new stores the config table it is handed
-- BY REFERENCE and never copies it, and every key a decorator here would touch, rows,
-- intercept, back, onSelect, onHighlight, onClose, is read live through self.config on
-- each use rather than captured at construction. Only matcher and layout are captured
-- once at construction, and nothing this seam is for touches those. new
-- below already mutates the caller's own config table in place for screen and matcher,
-- so decorating it too before handing the instance back follows this file's own idiom
-- rather than inventing a second one.
local DEFAULT_DECORATE = nil

--- Chooser:init() - nothing to build; the providers are loaded above.
function obj:init()
  return self
end

--- Chooser.configure(opts) - module-level defaults every new() inherits. opts.screen is
--- a function returning the hs.screen a chooser should appear on. opts.matcher is the
--- shared filter strategy from Chooser.matchers. opts.decorate is function(instance,
--- config), called with the instance new just built and its own config table right
--- after the provider's new returns and before new hands the instance back, allowed to mutate
--- config in place (see the note above DEFAULT_DECORATE for why that reaches the
--- instance's live behaviour). One call at the root wires the overlay display policy,
--- the matching policy, and the panel decorator into every chooser at once. opts.provider
--- is a provider module from Chooser.providers, nil meaning legacy. opts.ui is the UI kit,
--- forwarded to the legacy provider so its rows are styled from the body and caption roles.
--- opts.icon is the icon resolver, function(icon, owner) -> hs.image or nil, forwarded to the
--- legacy provider the same way. The default provider is handed it by its own configure.
function obj.configure(opts)
  opts = opts or {}
  DEFAULT_SCREEN = opts.screen
  DEFAULT_MATCHER = opts.matcher
  DEFAULT_PROVIDER = opts.provider
  DEFAULT_DECORATE = opts.decorate
  -- The UI kit reaches the legacy provider here, since it has no other door. The default
  -- provider is handed it by its own configure, which also takes the panel.
  if opts.ui ~= nil then legacy.configure({ ui = opts.ui }) end
  if opts.icon ~= nil then legacy.configure({ icon = opts.icon }) end
  return obj
end

--- Chooser.new(config) -> picker instance. Dot called, matching the old atom. The
--- instance is built by the provider configure injected, legacy when none was. A
--- config.provider field is still accepted and ignored.
--- The configured default screen and matcher policies are folded in unless the config
--- names its own. config.matcher = false opts out of the default so the supplier keeps
--- owning filtering; nil inherits the default. When a decorate policy is configured, it
--- runs on the freshly built instance before this hands it back; this file learns
--- nothing about what that function does, only that it is called with what it gave it.
function obj.new(config)
  config = config or {}
  if config.screen == nil then config.screen = DEFAULT_SCREEN end
  if config.matcher == nil then config.matcher = DEFAULT_MATCHER end
  local instance = (DEFAULT_PROVIDER or legacy).new(config)
  local ok, reason = contract.validate(instance)
  if not ok then
    error("Chooser: the provider does not satisfy the picker contract, " .. tostring(reason))
  end
  if DEFAULT_DECORATE then DEFAULT_DECORATE(instance, config) end
  return instance
end

return obj
