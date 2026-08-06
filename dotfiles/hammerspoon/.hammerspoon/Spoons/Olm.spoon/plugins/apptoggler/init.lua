--- === AppToggler ===
---
--- Smart application toggle (show/hide)
---
--- This is the olm side copy of AppToggler, made in the bundling pass, phase 6 of the
--- olm build plan, and the original this was copied from still lives at
--- Spoons/AppToggler.spoon.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "AppToggler"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("AppToggler", "info")

-- Configuration
obj._apps = nil
obj._hyperKey = nil

--- AppToggler:init()
--- Method
--- Initialize the spoon
function obj:init()
  return self
end

--- AppToggler:configure(opts)
--- Method
--- Configure the spoon
function obj:configure(opts)
  opts = opts or {}
  self._apps = opts.apps or {}
  -- When a HyperKey spoon is provided, toggles bind into its modal (fired by
  -- holding the physical Hyper key) instead of a literal modifier combination.
  self._hyperKey = opts.hyperKey
  return self
end

--- AppToggler:toggle(bundleID)
--- Method
--- Toggle an app (show if hidden/not frontmost, hide if frontmost)
function obj:toggle(bundleID)
  local app = hs.application.get(bundleID)

  if app and app:isFrontmost() and #app:allWindows() > 0 then
    app:hide()
  else
    hs.application.launchOrFocusByBundleID(bundleID)
  end
end

--- AppToggler:toggleURL(bundleID, url)
--- Method
--- Toggle an app that should land on a specific pane. Opens the URL when the app
--- is not frontmost (launching it, or navigating an already-open window to that
--- pane); hides the app when it is frontmost. Used for apps like System Settings
--- whose panes are reachable via a URL scheme.
function obj:toggleURL(bundleID, url)
  local app = hs.application.get(bundleID)

  if app and app:isFrontmost() and #app:allWindows() > 0 then
    app:hide()
  else
    -- Use `open` rather than hs.urlevent.openURL: pane URL schemes like
    -- x-apple.systempreferences: use a single colon and openURL rejects any URL
    -- without '://'.
    hs.execute("open " .. ("%q"):format(url))
  end
end

--- AppToggler:launchOrFocus(bundleID)
--- Method
--- Launch or focus an app (for workspace engine)
function obj:launchOrFocus(bundleID)
  hs.application.launchOrFocusByBundleID(bundleID)
end

--- AppToggler:focusOrCycle(bundleID)
--- Method
--- Focus an app, or cycle through its windows if already frontmost.
--- Never hides. First press shows the last focused window, each
--- subsequent press moves to the next window and wraps to the first.
function obj:focusOrCycle(bundleID)
  local app = hs.application.get(bundleID)

  -- Not running: launch it
  if not app then
    hs.application.launchOrFocusByBundleID(bundleID)
    return
  end

  -- Collect standard, non-minimized windows in a deterministic order so
  -- cycling is consistent (allWindows order is not stable on its own)
  local windows = {}
  for _, w in ipairs(app:allWindows()) do
    if w:isStandard() and not w:isMinimized() then
      table.insert(windows, w)
    end
  end
  table.sort(windows, function(a, b) return a:id() < b:id() end)

  -- No cyclable windows: fall back to launch or focus
  if #windows == 0 then
    hs.application.launchOrFocusByBundleID(bundleID)
    return
  end

  if app:isFrontmost() then
    -- Already focused: move to the next window, wrapping to the first
    local focused = hs.window.focusedWindow()
    local index = nil
    if focused then
      for i, w in ipairs(windows) do
        if w:id() == focused:id() then
          index = i
          break
        end
      end
    end
    local nextIndex = index and (index % #windows) + 1 or 1
    windows[nextIndex]:focus()
  else
    -- Not focused: bring the app forward with its last focused window
    hs.application.launchOrFocusByBundleID(bundleID)
  end
end

--- AppToggler:bindHotkeys(toggles)
--- Method
--- Bind app toggle hotkeys from config
function obj:bindHotkeys(toggles)
  for _, toggle in ipairs(toggles) do
    local bundleID = self._apps[toggle.app]
    if bundleID then
      local action
      if toggle.url then
        -- Pane-specific apps (e.g. System Settings) open via a URL scheme so the
        -- app lands on the right pane instead of wherever it was last.
        action = function()
          self:toggleURL(bundleID, toggle.url)
        end
      else
        action = function()
          self:focusOrCycle(bundleID)
        end
      end
      if self._hyperKey then
        -- Fires while the physical Hyper key is held (HyperKey.spoon eventtap)
        self._hyperKey:bind(toggle.key, action)
      else
        -- Fallback when no HyperKey is wired: the literal modifier combo
        hs.hotkey.bind(toggle.modifiers, toggle.key, action)
      end
    else
      log.w("Unknown app '" .. toggle.app .. "' in config")
    end
  end
  return self
end

return obj
