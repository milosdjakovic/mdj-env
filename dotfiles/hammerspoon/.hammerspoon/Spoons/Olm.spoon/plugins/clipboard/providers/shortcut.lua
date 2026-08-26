--- ClipboardHistory provider: Shortcut
---
--- A generic backend for any external clipboard manager that a global keyboard
--- shortcut reveals. show() presses a configured modifier combo, and whatever app
--- you bind that same combo to (a launcher's clipboard command, say) catches it
--- and shows its history. The provider names no app; the composition root supplies
--- the combo and the optional target, so switching clipboard managers is a config
--- change, not a code change. This is the one place the combo has to agree with
--- the app, keep the two in step.
---
--- An optional bundleID gates availability: pass your target app's id and the
--- chain falls back (to the native manager, say) whenever that app is not running,
--- logging the reason, the same way the Raycast backend does. Omit it and the
--- provider is always available, so place it accordingly in the chain.
---
--- Constructed with { mods, key, bundleID?, name? }. deferUntilHyperRelease is true
--- because show() posts a synthetic keystroke, which a held Hyper key's tap would
--- swallow, so it must wait for release, the same as the Spotlight backend.
return function(opts)
  opts = opts or {}
  local mods = opts.mods or {}
  local key = opts.key
  return {
    name = opts.name or "Shortcut",
    bundleID = opts.bundleID,
    deferUntilHyperRelease = true, -- sends a synthetic combo, swallowed while held
    -- The external app owns its own show and hide, so we cannot read its panel
    -- state and never claim it is showing. Each trigger just fires the combo, and
    -- the app itself decides whether a second press toggles it away.
    isShowing = function()
      return false
    end,
    -- Only gate when a target is named; without one the provider omits the available
    -- method entirely, so it is treated as always available, matching the spoon header.
    available = opts.bundleID and function(self)
      -- pathForBundleID answers an empty string rather than nil for an app it cannot
      -- place, so the absent case has to be tested for explicitly.
      local path = hs.application.pathForBundleID(self.bundleID)
      if path == nil or path == "" then
        return false, "not installed"
      end
      if not hs.application.get(self.bundleID) then
        return false, "not running"
      end
      return true
    end or nil,
    show = function()
      if key then
        hs.eventtap.keyStroke(mods, key, 0)
      end
    end,
  }
end
