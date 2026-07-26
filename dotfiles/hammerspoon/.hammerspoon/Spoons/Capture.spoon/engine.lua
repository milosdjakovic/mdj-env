--- Capture engine.
---
--- The Context in Strategy terms. It owns the provider chain and the dispatch,
--- and talks only through the provider contract (see contract.lua), so it never
--- names a concrete provider. macshot, native, and the default chain order are
--- all wired in by init.lua, the composition root. That is what keeps this file
--- reusable, swap or reorder providers without touching it.
---
--- The chain is an ordered list tried front to back (Chain of Responsibility).
--- For a given action the first provider that supports it, is available right
--- now, and whose trigger does not return false, handles it; the rest are
--- skipped. So a preferred backend sits first and an always-available one sits
--- last as the fallback.
---
--- Availability is checked LIVE on every keypress, not cached at load. An app can
--- be quit, or its scheme toggled, long after Hammerspoon loaded, and Hammerspoon
--- only reloads on file changes, so a cached decision would go stale and the
--- chain would keep firing a dead backend instead of falling through. The checks
--- are cheap Launch Services and process lookups, so running them per press costs
--- nothing noticeable. A load-time snapshot is logged once (so a reload shows the
--- current state), and after that each provider's reason is logged only when it
--- CHANGES, so pressing the key while a backend stays down does not spam.
---
--- Dispatch waits for the Hyper key to be released before running. The native
--- provider types real keystrokes, and the shared hold tap swallows every key
--- while a leader is held, so firing mid-hold would eat those keystrokes (a
--- consumer that types keystrokes must wait the same way). Waiting also means any capture overlay
--- appears with no leader held, so its own Escape/Enter work. This is the one
--- Capture-specific seam left in the engine, kept here on purpose rather than
--- abstracted behind another indirection.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Capture"
obj.version = "3.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("Capture", "info")

-- Injected by init.lua (the composition root)
obj._contract = nil          -- provider contract, used to validate the chain
obj._defaultProviders = nil  -- chain used when configure is given no providers

-- Configured state
obj._providers = nil     -- active chain, in priority order, contract-checked
obj._hyperKey = nil
obj._lastReason = nil    -- name -> last failing reason, for deduped live logging
obj._deps = nil          -- injected per consumer dependency adapter, handed to each available()

--- Capture:init()
--- Method
--- Initialize the spoon
function obj:init()
  self._lastReason = {}
  return self
end

--- Capture:configure(opts)
--- Method
--- opts.providers - ordered list of provider tables, tried front to back;
---                  defaults to the chain wired up in init.lua
--- opts.hyperKey  - optional HyperKey spoon; when present, bindHotkeys binds
---                  into its modal and dispatch waits for its release
--- opts.deps      - the per consumer dependency adapter, injected by the composition root
---                  and handed to each provider's available(). A provider backed by an
---                  external tool asks it rather than probing, so the probing happens once
---                  for the whole config and no provider names an install method. Absent
---                  only when the root did not wire it, which such a provider reports as
---                  its own reason for standing aside.
function obj:configure(opts)
  opts = opts or {}
  self._hyperKey = opts.hyperKey
  self._deps = opts.deps
  self._providers = self:_validate(opts.providers or self._defaultProviders or {})
  self:_logAvailability()
  return self
end

--- Capture:_validate(providers)
--- Method
--- Keep only the providers that fulfill the contract, in priority order. A
--- provider missing any required method can never be dispatched, so it is dropped
--- here (once, at load) with a log line naming the missing method. This is the
--- only static filtering; whether a valid provider is USABLE right now is decided
--- live at dispatch, since that can change while Hammerspoon runs.
function obj:_validate(providers)
  local valid = {}
  for _, provider in ipairs(providers or {}) do
    local name = provider.name or "?"
    local ok, missing = self._contract.validate(provider)
    if ok then
      table.insert(valid, provider)
    else
      log.w(name .. " dropped, does not implement " .. missing .. "()")
    end
  end
  return valid
end

--- Capture:_logAvailability()
--- Method
--- Log a one-time snapshot of the chain at load, so a reload shows the current
--- state (this is what prints when you quit macshot and reload). Each unavailable
--- provider is logged with its reason and a final line names those still active.
--- When everything is usable nothing is logged. This also seeds _lastReason, so
--- the live check at dispatch only re-logs a provider whose reason has CHANGED
--- since this snapshot, keeping repeated keypresses quiet.
function obj:_logAvailability()
  self._lastReason = {}
  local active = {}
  local anyFailed = false
  for _, provider in ipairs(self._providers or {}) do
    local name = provider.name or "?"
    local ok, reason = provider:available(self._deps)
    if ok then
      table.insert(active, name)
    else
      anyFailed = true
      reason = reason or "unavailable"
      self._lastReason[name] = reason
      log.w(name .. " unavailable, " .. reason)
    end
  end
  if anyFailed then
    log.i("active, " .. (next(active) and table.concat(active, ", ") or "no providers"))
  end
  return self
end

--- Capture:capture(action)
--- Method
--- Run an action (e.g. "captureArea", "recordArea") through the chain. For each
--- provider that supports the action, its :available() is checked LIVE right now,
--- and the first one both available and whose trigger does not return false
--- handles it; unavailable providers are skipped so a closed macshot falls
--- through to native. A provider's reason is logged only when it changed since
--- the last check (recovering to available logs once too), so holding the key
--- while macshot stays shut does not spam. Deferred until the Hyper key is
--- released so synthetic keystrokes are not swallowed.
function obj:capture(action)
  local function dispatch()
    -- Every provider here fulfilled the contract at load, so supports/available/
    -- trigger are guaranteed present.
    for _, provider in ipairs(self._providers or {}) do
      if provider:supports(action) then
        local name = provider.name or "?"
        local ok, reason = provider:available(self._deps)
        if ok then
          if self._lastReason[name] then
            log.i(name .. " available")
            self._lastReason[name] = nil
          end
          if provider:trigger(action) ~= false then
            return
          end
        else
          reason = reason or "unavailable"
          if self._lastReason[name] ~= reason then
            log.w(name .. " unavailable, " .. reason)
            self._lastReason[name] = reason
          end
        end
      end
    end
    log.w("no provider handled action '" .. tostring(action) .. "'")
  end

  if self._hyperKey and self._hyperKey:isActive() then
    -- Wait for release so the shared tap stops swallowing keys; otherwise the
    -- native provider's synthetic chord is eaten and overlays ignore Escape.
    --
    -- The waiter is held in a field, because a Hammerspoon timer is userdata whose
    -- finalizer stops it and one nothing refers to can be collected before it fires, which
    -- here would lose the capture entirely with nothing said. A second capture requested
    -- while the leader is still down replaces this one rather than queueing behind it,
    -- since two capture overlays arriving together on release is not a usable outcome.
    if self._releaseWait then self._releaseWait:stop() end
    self._releaseWait = hs.timer.waitUntil(function()
      return not self._hyperKey:isActive()
    end, dispatch, 0.02)
  else
    dispatch()
  end
end

--- Capture:bindHotkeys(mapping)
--- Method
--- mapping - an ordered list of { action, key, modifiers, mods }. Each binds into
--- the Hyper key when one is wired, otherwise the literal `modifiers` combo (the
--- fallback, matching appToggles). Optional `mods` is a list of sub-modifiers
--- within the Hyper modal ({"shift"} for Hyper+Shift+key), so one key can host
--- two actions; it is only meaningful on the Hyper path.
function obj:bindHotkeys(mapping)
  for _, binding in ipairs(mapping or {}) do
    local action = binding.action
    local fn = function()
      self:capture(action)
    end
    if self._hyperKey then
      self._hyperKey:bind(binding.key, fn, binding.mods)
    else
      hs.hotkey.bind(binding.modifiers, binding.key, fn)
    end
  end
  return self
end

return obj
