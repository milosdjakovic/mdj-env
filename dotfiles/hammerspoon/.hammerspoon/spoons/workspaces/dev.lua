local WindowManagement = require("spoons.windowManagement")
local AppToggler = require("spoons.appToggler")
local AppIdentifiers = require("spoons.appIdentifiers")

local Dev = {}

-- Apps to manage in the workspace (order matters for z-index)
local workspaceApps = {
  AppIdentifiers.GoogleChrome, -- Will be on top
  AppIdentifiers.VisualStudioCode,
  AppIdentifiers.Ghostty,
  AppIdentifiers.GoogleChat,
  AppIdentifiers.Safari -- Will be at the bottom
}

-- Window arrangement strategies
local PrimaryScreenStrategy = {
  [AppIdentifiers.VisualStudioCode] = function() WindowManagement.resizeActiveWindowToPercentage(97, 100) end,
  [AppIdentifiers.GoogleChrome] = function() WindowManagement.resizeActiveWindowToPercentage(97, 100) end,
  [AppIdentifiers.Ghostty] = function() WindowManagement.resizeActiveWindowToPercentage(90, 90) end,
  [AppIdentifiers.GoogleChat] = function() WindowManagement.resizeActiveWindowToPercentage(80, 90) end,
  [AppIdentifiers.Safari] = function() WindowManagement.resizeActiveWindowToPercentage(80, 90) end
}

local SecondaryScreenStrategy = {
  [AppIdentifiers.VisualStudioCode] = WindowManagement.fullHeightReasonableWidth,
  [AppIdentifiers.GoogleChrome] = function() WindowManagement.resizeActiveWindowToPercentage(90, 90) end,
  [AppIdentifiers.Ghostty] = WindowManagement.resizeActiveWindow,
  [AppIdentifiers.GoogleChat] = function()
    local window = hs.window.get(AppIdentifiers.GoogleChat)
    if window then
      window:moveToScreen(hs.screen.primaryScreen())
      WindowManagement.resizeActiveWindowToPercentage(80, 90)
    end
  end,
  [AppIdentifiers.Safari] = WindowManagement.fullHeightReasonableWidth
}

-- Helper function to check if app has windows without focusing
local function appHasWindows(bundleID)
  local app = hs.application.get(bundleID)
  return app and #(app:allWindows()) > 0
end

-- Helper function to move app to screen without focusing
local function moveAppToScreen(bundleID, screen)
  local app = hs.application.get(bundleID)
  if app then
    for _, window in ipairs(app:allWindows()) do
      window:moveToScreen(screen)
    end
  end
end

-- Helper function to arrange windows in proper order
local function arrangeWindows(readyApps, strategy, secondaryScreen)
  for i = #workspaceApps, 1, -1 do
    local bundleID = workspaceApps[i]
    if readyApps[bundleID] then
      local app = hs.application.get(bundleID)
      if app then
        -- Move to appropriate screen
        if secondaryScreen and bundleID ~= AppIdentifiers.GoogleChat then
          moveAppToScreen(bundleID, secondaryScreen)
        elseif bundleID == AppIdentifiers.GoogleChat then
          moveAppToScreen(bundleID, hs.screen.primaryScreen())
        end

        -- Arrange windows
        for _, window in ipairs(app:allWindows()) do
          window:focus()
          strategy[bundleID]()
        end
      end
    end
  end
end

function Dev.handleWorkspaceSetup()
  local screens = hs.screen.allScreens()
  local secondaryScreen = screens[2]
  local strategy = secondaryScreen and SecondaryScreenStrategy or PrimaryScreenStrategy

  -- Track apps and their states
  local pendingApps = {}
  local readyApps = {}
  local startTimes = {}

  -- Initialize pending apps and their start times
  for _, bundleID in ipairs(workspaceApps) do
    pendingApps[bundleID] = true
    startTimes[bundleID] = hs.timer.secondsSinceEpoch()
    -- Launch app if not already running
    if not appHasWindows(bundleID) then
      AppToggler.toggle(bundleID)
    end
  end

  local function checkApps()
    local currentTime = hs.timer.secondsSinceEpoch()
    local remainingApps = false

    -- Check each pending app
    for bundleID in pairs(pendingApps) do
      -- Check if app has timed out or is ready
      if currentTime - startTimes[bundleID] > 30 then
        -- App timed out
        pendingApps[bundleID] = nil
      elseif appHasWindows(bundleID) then
        -- App is ready
        readyApps[bundleID] = true
        pendingApps[bundleID] = nil
      else
        remainingApps = true
      end
    end

    -- If no more pending apps or all have timed out
    if not remainingApps then
      -- Stop the timer
      if Dev.checkTimer then
        Dev.checkTimer:stop()
        Dev.checkTimer = nil
      end

      -- Arrange all windows
      arrangeWindows(readyApps, strategy, secondaryScreen)
    end
  end

  -- Create and start the timer
  Dev.checkTimer = hs.timer.new(0.5, checkApps)
  Dev.checkTimer:start()
end

function Dev.closeWorkspaceApps()
  for _, bundleID in ipairs(workspaceApps) do
    local app = hs.application.get(bundleID)
    if app then
      app:kill()
    end
  end
end

function Dev.initialize()
  hs.hotkey.bind({ "shift", "alt" }, "D", Dev.handleWorkspaceSetup)
  -- hs.hotkey.bind({ "shift", "cmd" }, "D", Dev.closeWorkspaceApps) -- used for dev
end

return Dev
