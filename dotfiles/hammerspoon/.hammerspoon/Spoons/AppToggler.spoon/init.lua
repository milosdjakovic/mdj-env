--- === AppToggler ===
---
--- Smart application toggle with optional "hide others" functionality
---

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "AppToggler"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- State constants
obj.AppState = {
  ACTIVE = "active",
  HIDDEN = "hidden"
}

-- Configuration
obj._hideOthers = false
obj._apps = nil

--- AppToggler:init()
--- Method
--- Initialize the spoon
function obj:init()
  return self
end

--- AppToggler:configure(opts)
--- Method
--- Configure the spoon with dependencies
function obj:configure(opts)
  opts = opts or {}
  self._apps = opts.apps or {}
  self._hideOthers = opts.hideOthersDefault or false
  return self
end

--- AppToggler:getAppScreen(app)
--- Method
--- Determine which screen an app will appear on
function obj:getAppScreen(app)
  if not app then
    return hs.screen.mainScreen()
  end

  local windows = app:allWindows()

  for _, window in ipairs(windows) do
    if not window:isMinimized() then
      return window:screen()
    end
  end

  if #windows > 0 then
    return windows[1]:screen()
  end

  return hs.screen.mainScreen()
end

--- AppToggler:hideAllWindowsOnDisplay(appName, targetScreen)
--- Method
--- Hide all windows on a specific display except for the specified app
function obj:hideAllWindowsOnDisplay(appName, targetScreen)
  if not targetScreen then
    targetScreen = hs.screen.mainScreen()
  end

  local allWindows = hs.window.visibleWindows()
  local hiddenApps = {}

  for _, window in ipairs(allWindows) do
    local app = window:application()
    local appBundleID = app:bundleID()

    if app:name() ~= appName and window:screen() == targetScreen and not hiddenApps[appBundleID] then
      app:hide()
      hiddenApps[appBundleID] = true
    end
  end
end

--- AppToggler:toggleSimple(bundleID)
--- Method
--- Simple toggle without hiding other apps
function obj:toggleSimple(bundleID)
  local app = hs.application.get(bundleID)

  if app and app:isFrontmost() and #app:allWindows() > 0 then
    app:hide()
    return self.AppState.HIDDEN
  else
    hs.application.launchOrFocusByBundleID(bundleID)
    return self.AppState.ACTIVE
  end
end

--- AppToggler:toggleWithHideOthers(bundleID)
--- Method
--- Toggle with hiding other apps on the same screen
function obj:toggleWithHideOthers(bundleID)
  local app = hs.application.get(bundleID)

  if app and app:isFrontmost() and #app:allWindows() > 0 then
    app:hide()
    return self.AppState.HIDDEN
  else
    if app then
      local targetScreen = self:getAppScreen(app)
      self:hideAllWindowsOnDisplay(app:name(), targetScreen)
    else
      self:hideAllWindowsOnDisplay("", hs.screen.mainScreen())
    end
    hs.application.launchOrFocusByBundleID(bundleID)
    return self.AppState.ACTIVE
  end
end

--- AppToggler:toggle(bundleID)
--- Method
--- Toggle an app (respects hideOthers setting)
function obj:toggle(bundleID)
  if self._hideOthers then
    return self:toggleWithHideOthers(bundleID)
  else
    return self:toggleSimple(bundleID)
  end
end

--- AppToggler:launchOrFocus(bundleID)
--- Method
--- Launch or focus an app (for workspace engine)
function obj:launchOrFocus(bundleID)
  hs.application.launchOrFocusByBundleID(bundleID)
end

--- AppToggler:bindHotkeys(toggles)
--- Method
--- Bind app toggle hotkeys from config
function obj:bindHotkeys(toggles)
  for _, toggle in ipairs(toggles) do
    local bundleID = self._apps[toggle.app]
    if bundleID then
      hs.hotkey.bind(toggle.modifiers, toggle.key, function()
        self:toggle(bundleID)
      end)
    else
      print("AppToggler: Unknown app '" .. toggle.app .. "' in config")
    end
  end
  return self
end

--- AppToggler:bindHideOthersToggle(binding)
--- Method
--- Bind the hide others toggle hotkey
function obj:bindHideOthersToggle(binding)
  if binding then
    hs.hotkey.bind(binding.modifiers, binding.key, function()
      self._hideOthers = not self._hideOthers
      hs.alert.closeAll()
      hs.alert.show("Hide others: " .. (self._hideOthers and "ON" or "OFF"))
    end)
  end
  return self
end

return obj
