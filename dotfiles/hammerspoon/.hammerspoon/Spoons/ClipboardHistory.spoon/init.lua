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
---   :isShowing() -> boolean   is the UI already visible (used to avoid a toggle)
---   :show()                   reveal the UI
---
--- When a HyperKey spoon is provided, the action binds into its modal and waits
--- for the Hyper key to be released before firing: HyperKey's event tap swallows
--- every key while held, which would otherwise eat a provider's synthetic
--- keystrokes.

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

--------------------------------------------------------------------------------
-- Providers
--------------------------------------------------------------------------------

obj.providers = {}

--- ClipboardHistory.providers.spotlightTahoe
--- Constant
--- Provider for the clipboard history built into Spotlight in macOS 26 (Tahoe).
--- Opens Spotlight (Cmd+Space) then selects its Clipboard category (Cmd+4),
--- skipping the open step when Spotlight is already showing (pressing Cmd+Space
--- again would close it). Spotlight's process always runs but only owns a window
--- while the panel is visible, which is how isShowing() detects it.
obj.providers.spotlightTahoe = {
  isShowing = function()
    local sp = hs.application.get("com.apple.Spotlight")
    return sp ~= nil and #sp:allWindows() > 0
  end,
  show = function(self)
    if self:isShowing() then
      hs.eventtap.keyStroke({ "cmd" }, "4", 0)
    else
      hs.eventtap.keyStroke({ "cmd" }, "space", 0)
      hs.timer.doAfter(0.12, function()
        hs.eventtap.keyStroke({ "cmd" }, "4", 0)
      end)
    end
  end,
}

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
---                 its modal and defers keystrokes until the Hyper key is
---                 released
function obj:configure(opts)
  opts = opts or {}
  self._hyperKey = opts.hyperKey
  self._provider = opts.provider or self.providers.spotlightTahoe
  return self
end

--- ClipboardHistory:open()
--- Method
--- Reveal clipboard history via the configured provider
function obj:open()
  local provider = self._provider
  local function fire()
    provider:show()
  end

  if self._hyperKey and self._hyperKey:isActive() then
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
