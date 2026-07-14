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

obj.providers = {}

--- ClipboardHistory.providers.spotlightTahoe
--- Constant
--- Provider for the clipboard history built into Spotlight in macOS 26 (Tahoe).
--- Opens Spotlight (Cmd+Space) then selects its Clipboard category (Cmd+4),
--- skipping the open step when Spotlight is already showing (pressing Cmd+Space
--- again would close it). Spotlight's process always runs but only owns a window
--- while the panel is visible, which is how isShowing() detects it.
obj.providers.spotlightTahoe = {
  deferUntilHyperRelease = true, -- sends Cmd+Space / Cmd+4, swallowed while held
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

--- ClipboardHistory.providers.deck
--- Constant
--- Provider for the Deck clipboard manager (bundle com.yuzeguitar.Deck). Its
--- clipboard window opens only through a global shortcut, so show() fires the
--- shortcut assigned in Deck's settings, Shift+Ctrl+Option+Cmd+C.
--- Change the keystroke here if you rebind it in Deck. isAvailable() reports
--- Deck missing or quit so the chain can fall back and log the reason.
obj.providers.deck = {
  name = "Deck",
  bundleID = "com.yuzeguitar.Deck",
  deferUntilHyperRelease = true, -- sends a global shortcut, swallowed while held
  isAvailable = function(self)
    if not hs.application.pathForBundleID(self.bundleID) then
      return false, "not installed"
    end
    if not hs.application.get(self.bundleID) then
      return false, "not running"
    end
    return true
  end,
  show = function(self)
    hs.eventtap.keyStroke({ "shift", "ctrl", "alt", "cmd" }, "c", 0)
  end,
}

--- ClipboardHistory.providers.raycast
--- Constant
--- Provider for Raycast's clipboard history. Unlike Maccy and Deck, Raycast
--- exposes a deeplink, so show() opens the command URL directly rather than
--- firing a shortcut. This needs no configured hotkey and cannot be thrown off
--- by a rebind. isAvailable() reports Raycast missing or quit so the chain can
--- fall back and log the reason.
---
--- show() also toggles: a second press hides Raycast completely (one hide(),
--- since Raycast's own Escape only steps back to root search and needs a second
--- press to close). The hide fires only when Raycast is frontmost and this
--- provider is the one that opened it, tracked by _shown. So pressing the key
--- while the clipboard is up dismisses it, while pressing it with Raycast not
--- visible just opens it. _shown is validated against the live frontmost app,
--- so a Raycast closed by other means (Escape, click away) is reopened rather
--- than a stale hide firing into the wrong app.
obj.providers.raycast = {
  name = "Raycast",
  bundleID = "com.raycast.macos",
  url = "raycast://extensions/raycast/clipboard-history/clipboard-history",
  deferUntilHyperRelease = false, -- opens a URL / hides, neither is swallowed
  _shown = false,
  isAvailable = function(self)
    if not hs.application.pathForBundleID(self.bundleID) then
      return false, "not installed"
    end
    if not hs.application.get(self.bundleID) then
      return false, "not running"
    end
    return true
  end,
  show = function(self)
    local front = hs.application.frontmostApplication()
    local raycastFront = front ~= nil and front:bundleID() == self.bundleID
    if self._shown and raycastFront then
      local app = hs.application.get(self.bundleID)
      if app then
        app:hide()
      end
      self._shown = false
    else
      hs.urlevent.openURL(self.url)
      self._shown = true
    end
  end,
}

--- ClipboardHistory.providers.firstAvailable(chain)
--- Constructor
--- Build a provider that, on every show, delegates to the first provider in
--- `chain` whose isAvailable() returns true (a provider with no isAvailable() is
--- treated as always available, so place the guaranteed fallback last).
--- Availability is checked at dispatch, not at load, because a backend like
--- Deck can be quit while Hammerspoon keeps running. Each skipped provider is
--- logged with its reason, so an absent Deck explains itself instead of failing
--- silently.
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
