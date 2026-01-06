local WindowManagement = require("spoons.windowManagement")
local AppToggler = require("spoons.appToggler")
local AppIdentifiers = require("spoons.appIdentifiers")

local Vicert = {}

-- Apps to manage in the workspace (order matters for z-index)
local workspaceApps = {
  AppIdentifiers.Claude, -- Will be on top
  AppIdentifiers.Slack,
  AppIdentifiers.Ghostty,
  AppIdentifiers.Docker,
  AppIdentifiers.Bruno,
  AppIdentifiers.GoogleChrome,
  AppIdentifiers.Safari -- Will be at the bottom
}

-- Apps that should go to secondary display
local secondaryDisplayApps = {
  [AppIdentifiers.GoogleChrome] = true,
  [AppIdentifiers.Safari] = true
}

-- Window arrangement strategies
local PrimaryScreenStrategy = {
  [AppIdentifiers.Claude] = function() WindowManagement.resizeActiveWindowToPercentage(90, 90) end,
  [AppIdentifiers.Slack] = function() WindowManagement.resizeActiveWindowToPercentage(80, 90) end,
  [AppIdentifiers.Ghostty] = function() end, -- Just launch, don't resize
  [AppIdentifiers.Docker] = function() WindowManagement.resizeActiveWindowToPercentage(80, 80) end,
  [AppIdentifiers.Bruno] = function() WindowManagement.resizeActiveWindowToPercentage(80, 90) end,
  [AppIdentifiers.GoogleChrome] = function() WindowManagement.resizeActiveWindowToPercentage(97, 100) end,
  [AppIdentifiers.Safari] = function() WindowManagement.resizeActiveWindowToPercentage(80, 90) end
}

local SecondaryScreenStrategy = {
  [AppIdentifiers.Claude] = function() WindowManagement.resizeActiveWindowToPercentage(90, 90) end,
  [AppIdentifiers.Slack] = function() WindowManagement.resizeActiveWindowToPercentage(80, 90) end,
  [AppIdentifiers.Ghostty] = function() end, -- Just launch, don't resize
  [AppIdentifiers.Docker] = function() WindowManagement.resizeActiveWindowToPercentage(80, 80) end,
  [AppIdentifiers.Bruno] = function() WindowManagement.resizeActiveWindowToPercentage(80, 90) end,
  [AppIdentifiers.GoogleChrome] = function() WindowManagement.resizeActiveWindowToPercentage(90, 90) end,
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
  local primaryScreen = hs.screen.primaryScreen()

  for i = #workspaceApps, 1, -1 do
    local bundleID = workspaceApps[i]
    if readyApps[bundleID] then
      local app = hs.application.get(bundleID)
      if app then
        -- Move to appropriate screen
        if secondaryScreen and secondaryDisplayApps[bundleID] then
          moveAppToScreen(bundleID, secondaryScreen)
        else
          moveAppToScreen(bundleID, primaryScreen)
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

function Vicert.handleWorkspaceSetup()
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
      if Vicert.checkTimer then
        Vicert.checkTimer:stop()
        Vicert.checkTimer = nil
      end

      -- Arrange all windows
      arrangeWindows(readyApps, strategy, secondaryScreen)
    end
  end

  -- Create and start the timer
  Vicert.checkTimer = hs.timer.new(0.5, checkApps)
  Vicert.checkTimer:start()
end

function Vicert.closeWorkspaceApps()
  for _, bundleID in ipairs(workspaceApps) do
    local app = hs.application.get(bundleID)
    if app then
      app:kill()
    end
  end
end

function Vicert.initialize()
  hs.hotkey.bind({ "shift", "alt" }, "V", Vicert.handleWorkspaceSetup)
end

return Vicert
