--- === ClipboardHistory ===
---
--- Reveal a clipboard-history UI on a hotkey.
---
--- HOW the history is revealed is pluggable via a provider (opts.provider). The
--- built-in default, `ClipboardHistory.providers.spotlightTahoe`, drives the
--- clipboard history that Spotlight gained in macOS 26 (Tahoe): there is no
--- dedicated system shortcut for it, so the provider presses Cmd+Space to open
--- Spotlight and then Cmd+4 to select its Clipboard category. Point opts.provider
--- at a different table (e.g. a launcher's own clipboard command) to swap the
--- backend without touching the binding logic.
---
--- A provider is a table implementing:
---   :isShowing() -> boolean          is the UI already visible (avoids a toggle)
---   :show()                          reveal the UI
---   :isAvailable() -> boolean, string  (optional) can this backend run right
---                                    now; a false return may include a reason.
---                                    A provider with no isAvailable() is always
---                                    available, so a built-in backend placed
---                                    last is the guaranteed fallback.
---   .deferUntilHyperRelease -> bool  (optional, default true) whether show()
---                                    must wait for the Hyper key to be released
---                                    before firing. See below.
---
--- ClipboardHistory.providers.firstAvailable chains providers so a preferred
--- backend (e.g. Raycast) is used when present and a built-in one takes over
--- when it is not, logging every skip.
---
--- When a HyperKey spoon is provided, a provider fires while the Hyper key is
--- still held unless it sets deferUntilHyperRelease. Keystroke providers set it,
--- because HyperKey's event tap swallows every key while held and would eat
--- their synthetic keystrokes, so they must wait for release. A provider that
--- triggers without a keystroke (Raycast opens a URL and hides the app) leaves
--- it false and fires at once, so holding Caps Lock and tapping the key shows
--- the UI immediately and tapping again, still holding, toggles it away.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "ClipboardHistory"
obj.version = "2.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- Configuration
obj._hyperKey = nil
obj._provider = nil

local log = hs.logger.new("ClipboardHistory", "info")

--------------------------------------------------------------------------------
-- Providers
--------------------------------------------------------------------------------
-- The mechanism and the provider adapters each live in their own file, loaded by
-- absolute path since a spoon dir is not on package.path. Each provider is a
-- self-contained table satisfying the contract above. Raycast and Spotlight wrap
-- external apps; the Hammerspoon one is a thin adapter over the manager/
-- mechanism in this spoon, built by passing that mechanism in. To add a backend,
-- drop a file in providers/ and name it in the chain.

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(spoonPath .. name)
  if not chunk then
    error("ClipboardHistory: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end

--- ClipboardHistory.manager
--- The Hammerspoon clipboard mechanism, exposing configure/start/show/isShowing/
--- clear. The composition root starts it once; see manager/init.lua.
obj.manager = load("manager/init.lua")

obj.providers = {
  spotlightTahoe = load("providers/spotlight-tahoe.lua"),
  raycast = load("providers/raycast.lua"),
  hammerspoon = load("providers/hammerspoon.lua")(obj.manager),
}

--- ClipboardHistory.providers.firstAvailable(chain)
--- Constructor
--- Build a provider that, on every show, delegates to the first provider in
--- `chain` whose isAvailable() returns true (a provider with no isAvailable() is
--- treated as always available, so place the guaranteed fallback last).
--- Availability is checked at dispatch, not at load, because a backend like
--- Raycast can be quit while Hammerspoon keeps running. Each skipped provider is
--- logged with its reason, so an absent Raycast explains itself instead of
--- failing silently.
function obj.providers.firstAvailable(chain)
  local function pick()
    for _, p in ipairs(chain) do
      if not p.isAvailable then
        return p
      end
      local ok, reason = p:isAvailable()
      if ok then
        return p
      end
      log.f("%s unavailable (%s), falling back", p.name or "provider", reason or "unavailable")
    end
    return nil
  end
  return {
    -- Expose the live pick so the engine can read the chosen backend's
    -- deferUntilHyperRelease before deciding whether to wait for release.
    resolve = function()
      return pick()
    end,
    isShowing = function()
      local p = pick()
      return p ~= nil and p.isShowing ~= nil and p:isShowing()
    end,
    show = function()
      local p = pick()
      if p then
        p:show()
      end
    end,
  }
end

--------------------------------------------------------------------------------
-- Spoon
--------------------------------------------------------------------------------

--- ClipboardHistory:init()
--- Method
--- Initialize the spoon
function obj:init()
  return self
end

--- ClipboardHistory:configure(opts)
--- Method
--- opts.provider - table implementing :isShowing() and :show(); defaults to
---                 ClipboardHistory.providers.spotlightTahoe
--- opts.hyperKey - optional HyperKey spoon; when present the action binds into
---                 its modal, and each provider decides via
---                 deferUntilHyperRelease whether to wait for the Hyper key to
---                 be released before firing
function obj:configure(opts)
  opts = opts or {}
  self._hyperKey = opts.hyperKey
  self._provider = opts.provider or self.providers.spotlightTahoe
  return self
end

--- ClipboardHistory:open()
--- Method
--- Reveal clipboard history via the configured provider. The provider is
--- resolved once here (at the key press), so a chained backend's availability is
--- still checked at dispatch. Whether to wait for the Hyper key to be released
--- is the resolved provider's call via deferUntilHyperRelease: keystroke
--- backends must wait so their synthetic keys are not swallowed, while a
--- URL/hide backend like Raycast fires while the key is still held, which is
--- what lets a second press toggle it away without releasing Caps Lock.
function obj:open()
  local provider = self._provider
  local chosen = provider.resolve and provider:resolve() or provider
  if not chosen then
    return
  end
  local defer = chosen.deferUntilHyperRelease
  if defer == nil then
    defer = true
  end
  local function fire()
    chosen:show()
  end

  if defer and self._hyperKey and self._hyperKey:isActive() then
    -- Wait for release so HyperKey's tap stops swallowing synthetic keystrokes
    hs.timer.waitUntil(function()
      return not self._hyperKey:isActive()
    end, fire, 0.02)
  else
    fire()
  end
end

--- ClipboardHistory:bindHotkeys(mapping)
--- Method
--- mapping.open - { modifiers = ..., key = ... }. Binds into the Hyper key when
---                one is wired, otherwise the literal modifier combo.
function obj:bindHotkeys(mapping)
  local binding = mapping and mapping.open
  if not binding then
    return self
  end
  local action = function()
    self:open()
  end
  if self._hyperKey then
    self._hyperKey:bind(binding.key, action)
  else
    hs.hotkey.bind(binding.modifiers, binding.key, action)
  end
  return self
end

return obj
