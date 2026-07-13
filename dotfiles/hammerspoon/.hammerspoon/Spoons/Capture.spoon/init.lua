--- === Capture ===
---
--- Trigger screen capture and recording on a hotkey, backed by an ordered chain
--- of providers so the underlying screenshot tool can be replaced, or fallen
--- back on, without touching the bindings.
---
--- The spoon speaks only a small, app-agnostic action vocabulary -- today
--- `captureArea` and `recordArea`. WHICH tool runs each action is decided by the
--- provider chain (opts.providers), an ordered list tried front to back. For a
--- given action the first provider that knows the action (supports) handles it;
--- the rest are skipped. So a preferred app sits first and the always-present
--- native provider sits last as the fallback.
---
--- Every provider fulfills the same contract, three methods it MUST implement:
---   :available()      -> boolean[, reason]  is this backend usable on this
---                        machine. This is the invariant. Each provider checks
---                        something different -- macshot checks it is installed
---                        and owns its URL scheme, native just returns true
---                        because it is the baseline that always works. On
---                        failure it returns false plus a short reason string,
---                        which is logged so you can see WHY it dropped out.
---   :supports(action) -> boolean            does it implement this action
---   :trigger(action)  -> boolean            run it; return false to fall through
---                        to the next provider (nil/true means handled)
--- plus an optional `name` string used in the load-time log. A provider missing
--- any of the three methods is logged and dropped, so the contract is visibly
--- enforced.
---
--- Availability is resolved ONCE, when configure runs at load: each provider's
--- :available() is checked then and unavailable ones are dropped from the chain.
--- When everything present is usable, nothing is logged. If any provider drops
--- out, each failure is logged with its reason and a final line reports which
--- providers remain active, so a chain like flameshot, macshot, native prints why
--- flameshot and macshot fell out and that native is carrying the load. Dispatch
--- on a keypress walks the pre-filtered list and never touches :available()
--- again. Installing or removing a backend takes effect on the next reload.
---
--- Two built-in providers ship here. `macshot` fires macshot's `macshot://` URL
--- scheme and is available only while macshot is installed. `native` synthesizes
--- the macOS screenshot shortcuts (Cmd+Shift+4 / Cmd+Shift+5) and is always
--- available, so it is the baseline tail of the chain. Leave native alone and
--- comment macshot out of opts.providers to run on native only, with no check.
---
--- Dispatch waits for the Hyper key to be released before running. The native
--- provider types real keystrokes, and the shared ChordKey tap swallows every
--- key while a leader is held, so firing mid-hold would eat those keystrokes
--- (the same reason ClipboardHistory defers). Waiting also means any capture
--- overlay appears with no leader held, so its own Escape/Enter work.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Capture"
obj.version = "2.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- Configuration
obj._providers = nil        -- configured chain, in priority order
obj._activeProviders = nil  -- chain filtered to available providers (set at load)
obj._hyperKey = nil

--------------------------------------------------------------------------------
-- Providers
--------------------------------------------------------------------------------

obj.providers = {}

--- Capture.urlProvider(opts)
--- Constructor
--- Build a provider from a table of action -> macOS URL. Triggering an action
--- opens its URL, which is how macshot (and most capture apps) expose their
--- commands. opts.urls is the action->URL map. opts.bundleID, when set, gates
--- availability on that app being installed. opts.scheme, when set, additionally
--- verifies that app is the registered handler for the scheme, a pure Launch
--- Services lookup with no UI. Note this checks scheme REGISTRATION, which for an
--- app whose "enable URL scheme" toggle registers the handler will track that
--- toggle, but cannot see a toggle that leaves a statically declared handler in
--- place. opts.name labels it in the load-time log.
function obj.urlProvider(opts)
  return {
    name = opts.name,
    urls = opts.urls,
    bundleID = opts.bundleID,
    scheme = opts.scheme,
    available = function(self)
      if self.bundleID and not hs.application.pathForBundleID(self.bundleID) then
        return false, "not installed"
      end
      if self.scheme then
        local handler = hs.urlevent.getDefaultHandler(self.scheme)
        if not handler then
          return false, "no app owns the " .. self.scheme .. ":// URL scheme (enable it in the app settings)"
        end
        if self.bundleID and handler:lower() ~= self.bundleID:lower() then
          return false, "the " .. self.scheme .. ":// scheme is handled by " .. handler .. ", not this app"
        end
      end
      return true
    end,
    supports = function(self, action)
      return self.urls[action] ~= nil
    end,
    trigger = function(self, action)
      local url = self.urls[action]
      if not url then
        return false
      end
      return hs.urlevent.openURL(url)
    end,
  }
end

--- Capture.providers.macshot
--- Constant
--- Provider for macshot, driven by its `macshot://` URL scheme (enable it in
--- macshot settings). Availability requires macshot to be installed AND to own
--- the macshot:// scheme, so it drops out of the chain on machines without it,
--- or if the scheme is not registered. Add entries here as new actions are bound
--- (see macshot settings for the full command list).
obj.providers.macshot = obj.urlProvider({
  name = "macshot",
  bundleID = "com.sw33tlie.macshot.macshot",
  scheme = "macshot",
  urls = {
    captureArea = "macshot://capture",
    recordArea = "macshot://record",
  },
})

--- Capture.providers.native
--- Constant
--- Provider backed by the built-in macOS screenshot shortcuts, synthesized with
--- hs.eventtap.keyStroke. Always available, so it belongs last in the chain as
--- the universal fallback. `captureArea` sends Cmd+Shift+4 (area to file);
--- `recordArea` sends Cmd+Shift+5 (the capture toolbar, which includes
--- recording, since macOS has no shortcut that starts an area recording
--- directly).
obj.providers.native = {
  name = "native",
  chords = {
    captureArea = { mods = { "cmd", "shift" }, key = "4" },
    recordArea = { mods = { "cmd", "shift" }, key = "5" },
  },
  -- The baseline: the OS shortcuts are always present, so this is always true.
  available = function()
    return true
  end,
  supports = function(self, action)
    return self.chords[action] ~= nil
  end,
  trigger = function(self, action)
    local chord = self.chords[action]
    if not chord then
      return false
    end
    hs.eventtap.keyStroke(chord.mods, chord.key, 0)
    return true
  end,
}

--------------------------------------------------------------------------------
-- Spoon
--------------------------------------------------------------------------------

--- Capture:init()
--- Method
--- Initialize the spoon
function obj:init()
  return self
end

--- Capture:configure(opts)
--- Method
--- opts.providers - ordered list of provider tables, tried front to back;
---                  defaults to { macshot, native }
--- opts.hyperKey  - optional HyperKey spoon; when present, bindHotkeys binds
---                  into its modal and dispatch waits for its release
function obj:configure(opts)
  opts = opts or {}
  self._providers = opts.providers or { self.providers.macshot, self.providers.native }
  self._hyperKey = opts.hyperKey
  self:_resolveProviders()
  return self
end

-- Methods every provider must implement (the contract enforced at load).
local REQUIRED_METHODS = { "available", "supports", "trigger" }

--- Capture:_resolveProviders()
--- Method
--- Cache the usable providers once, keeping priority order. A provider that does
--- not fulfill the contract is dropped, and a provider whose :available() returns
--- false is dropped with its reason. Failures are logged; if any occurred, a
--- final line names the providers still active. All present and usable means no
--- output. Run from configure, so it re-runs on every Hammerspoon reload.
function obj:_resolveProviders()
  self._activeProviders = {}
  local activeNames = {}
  local anyFailed = false
  for _, provider in ipairs(self._providers or {}) do
    local name = provider.name or "?"
    local missing
    for _, method in ipairs(REQUIRED_METHODS) do
      if type(provider[method]) ~= "function" then
        missing = method
        break
      end
    end
    if missing then
      anyFailed = true
      print("Capture: " .. name .. " dropped, does not implement " .. missing .. "()")
    else
      local ok, reason = provider:available()
      if ok then
        table.insert(self._activeProviders, provider)
        table.insert(activeNames, name)
      else
        anyFailed = true
        print("Capture: " .. name .. " unavailable" .. (reason and (", " .. reason) or ""))
      end
    end
  end
  if anyFailed then
    print("Capture: active, " .. (next(activeNames) and table.concat(activeNames, ", ") or "no providers"))
  end
  return self
end

--- Capture:capture(action)
--- Method
--- Run an action (e.g. "captureArea", "recordArea") through the resolved chain:
--- the first available provider that supports the action, and whose trigger does
--- not return false, handles it. Availability was settled at load, so this only
--- checks support. Deferred until the Hyper key is released so synthetic
--- keystrokes are not swallowed.
function obj:capture(action)
  local function dispatch()
    -- Every provider here fulfilled the contract at load, so supports/trigger
    -- are guaranteed present.
    for _, provider in ipairs(self._activeProviders or {}) do
      if provider:supports(action) and provider:trigger(action) ~= false then
        return
      end
    end
    print("Capture: no provider handled action '" .. tostring(action) .. "'")
  end

  if self._hyperKey and self._hyperKey:isActive() then
    -- Wait for release so ChordKey's tap stops swallowing keys; otherwise the
    -- native provider's synthetic chord is eaten and overlays ignore Escape.
    hs.timer.waitUntil(function()
      return not self._hyperKey:isActive()
    end, dispatch, 0.02)
  else
    dispatch()
  end
end

--- Capture:bindHotkeys(mapping)
--- Method
--- mapping - an ordered list of { action = ..., modifiers = ..., key = ... }.
--- Each binds into the Hyper key when one is wired, otherwise the literal
--- modifier combo (the `modifiers` field is that fallback, matching appToggles).
function obj:bindHotkeys(mapping)
  for _, binding in ipairs(mapping or {}) do
    local action = binding.action
    local fn = function()
      self:capture(action)
    end
    if self._hyperKey then
      self._hyperKey:bind(binding.key, fn)
    else
      hs.hotkey.bind(binding.modifiers, binding.key, fn)
    end
  end
  return self
end

return obj
