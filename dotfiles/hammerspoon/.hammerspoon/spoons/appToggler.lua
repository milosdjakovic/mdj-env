local AppToggler = {}

AppToggler.AppState = {
  ACTIVE = "active",
  HIDDEN = "hidden"
}

-- Add a global property for hideOthers
AppToggler.hideOthers = false

-- Function to determine which screen an app will appear on
function AppToggler.getAppScreen(app)
  if not app then
    return hs.screen.mainScreen()
  end

  -- Get all windows of the app
  local windows = app:allWindows()

  -- If the app has windows, use the screen of the first visible window
  for _, window in ipairs(windows) do
    if not window:isMinimized() then
      return window:screen()
    end
  end

  -- If all windows are minimized, use the screen of the first minimized window
  if #windows > 0 then
    return windows[1]:screen()
  end

  -- If no windows, use main screen
  return hs.screen.mainScreen()
end

-- Function to hide all windows on a specific display except for the specified app
function AppToggler.hideAllWindowsOnDisplay(appName, targetScreen)
  if not targetScreen then
    targetScreen = hs.screen.mainScreen()
  end

  local allWindows = hs.window.visibleWindows()

  -- Track which apps have been hidden
  local hiddenApps = {}

  for _, window in ipairs(allWindows) do
    local app = window:application()
    local appBundleID = app:bundleID()

    -- Only hide an app if:
    -- 1. It's not the app we're showing
    -- 2. The window is on the target display
    -- 3. We haven't already hidden this app
    if app:name() ~= appName and window:screen() == targetScreen and not hiddenApps[appBundleID] then
      app:hide()
      hiddenApps[appBundleID] = true
    end
  end
end

-- Function to hide all windows of an app
function AppToggler.hideAllWindows(appName)
  local app = hs.application.get(appName)
  if app then
    local windows = app:allWindows()
    for _, window in ipairs(windows) do
      window:hide()
    end
  end
end

-- Function to handle application activation
function AppToggler.activateApp(app)
  if AppToggler.hideOthers then
    -- Determine which screen the app will appear on
    local targetScreen = AppToggler.getAppScreen(app)
    AppToggler.hideAllWindowsOnDisplay(app:name(), targetScreen)
  end
  app:activate(true)
end

-- Simple toggle function
function AppToggler.toggleSimple(appName)
  local app = hs.application.get(appName)

  if app and app:isFrontmost() and #app:allWindows() > 0 then
    -- Application is active and has windows, hide it
    app:hide()
    return AppToggler.AppState.HIDDEN
  else
    -- Everything else: not running, hidden, minimized, not focused, or no windows
    hs.application.launchOrFocusByBundleID(appName)
    return AppToggler.AppState.ACTIVE
  end
end

-- Toggle function with hideOthers functionality
function AppToggler.toggleWithHideOthers(appName)
  local app = hs.application.get(appName)

  if app and app:isFrontmost() and #app:allWindows() > 0 then
    -- Application is active and has windows, hide it
    app:hide()
    return AppToggler.AppState.HIDDEN
  else
    -- Hide others first, then launch/focus
    if app then
      local targetScreen = AppToggler.getAppScreen(app)
      AppToggler.hideAllWindowsOnDisplay(app:name(), targetScreen)
    else
      -- App doesn't exist yet, use main screen
      AppToggler.hideAllWindowsOnDisplay("", hs.screen.mainScreen())
    end
    hs.application.launchOrFocusByBundleID(appName)
    return AppToggler.AppState.ACTIVE
  end
end

-- Main toggle function that chooses between the two
function AppToggler.toggle(appName)
  if AppToggler.hideOthers then
    return AppToggler.toggleWithHideOthers(appName)
  else
    return AppToggler.toggleSimple(appName)
  end
end

function AppToggler.bindToggle(appIdentifier, modifiers, key)
  hs.hotkey.bind(modifiers, key, function()
    AppToggler.toggle(appIdentifier)
  end)
end

-- Initialize AppToggler with a list of toggle configurations
function AppToggler.initialize(options)
  options = options or {}
  AppToggler.hideOthers = options.hideOthers or false
  local toggles = options.toggles or {}

  hs.hotkey.bind({ "ctrl", "alt" }, "o", function()
    AppToggler.hideOthers = not AppToggler.hideOthers
    hs.alert.closeAll()
    hs.alert.show("Hide others: " .. (AppToggler.hideOthers and "ON" or "OFF"))
  end)

  for _, toggle in ipairs(toggles) do
    AppToggler.bindToggle(toggle.appIdentifier, toggle.modifiers, toggle.key)
  end
end

return AppToggler
