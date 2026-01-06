--- === WorkspaceEngine ===
---
--- Generic workspace orchestration engine
---

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "WorkspaceEngine"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- Dependencies (injected via configure)
obj._appToggler = nil
obj._windowManager = nil
obj._apps = nil
obj._settings = nil

-- State
obj._workspaces = {}
obj._activeTimer = nil

--- WorkspaceEngine:init()
--- Method
--- Initialize the spoon
function obj:init()
  self._workspaces = {}
  return self
end

--- WorkspaceEngine:configure(opts)
--- Method
--- Configure the spoon with dependencies
function obj:configure(opts)
  opts = opts or {}
  self._appToggler = opts.appToggler
  self._windowManager = opts.windowManager
  self._apps = opts.apps or {}
  self._settings = opts.settings or {}
  return self
end

--- WorkspaceEngine:registerWorkspace(config)
--- Method
--- Register a workspace from config
function obj:registerWorkspace(config)
  table.insert(self._workspaces, config)
  return self
end

--- WorkspaceEngine:start()
--- Method
--- Bind hotkeys for all registered workspaces
function obj:start()
  for _, ws in ipairs(self._workspaces) do
    hs.hotkey.bind(ws.hotkey.modifiers, ws.hotkey.key, function()
      self:_activateWorkspace(ws)
    end)
  end
  return self
end

--- WorkspaceEngine:_appHasWindows(bundleID)
--- Method
--- Check if app has windows
function obj:_appHasWindows(bundleID)
  local app = hs.application.get(bundleID)
  return app and #(app:allWindows()) > 0
end

--- WorkspaceEngine:_moveAppToScreen(bundleID, screen)
--- Method
--- Move all windows of an app to a screen
function obj:_moveAppToScreen(bundleID, screen)
  local app = hs.application.get(bundleID)
  if app then
    for _, window in ipairs(app:allWindows()) do
      window:moveToScreen(screen)
    end
  end
end

--- WorkspaceEngine:_shouldGoToSecondary(ws, appName)
--- Method
--- Check if an app should go to secondary display
function obj:_shouldGoToSecondary(ws, appName)
  -- Check if explicitly set to stay on primary
  if ws.primaryDisplayApps then
    for _, name in ipairs(ws.primaryDisplayApps) do
      if name == appName then
        return false
      end
    end
  end

  -- Check if explicitly set for secondary
  if ws.secondaryDisplayApps then
    for _, name in ipairs(ws.secondaryDisplayApps) do
      if name == appName then
        return true
      end
    end
  end

  return false
end

--- WorkspaceEngine:_applyStrategy(strategyDef)
--- Method
--- Apply a sizing strategy to the focused window
function obj:_applyStrategy(strategyDef)
  if not strategyDef then return end

  local action = strategyDef.action

  if action == "percentage" then
    self._windowManager:resizeToPercentage(strategyDef.width, strategyDef.height)
  elseif action == "fullHeightReasonableWidth" then
    self._windowManager:fullHeightReasonableWidth()
  elseif action == "resizeDefault" then
    self._windowManager:resizeDefault()
  elseif action == "none" then
    -- Do nothing
  end
end

--- WorkspaceEngine:_arrangeWindows(ws, readyApps, strategyKey, secondaryScreen)
--- Method
--- Arrange windows for a workspace
function obj:_arrangeWindows(ws, readyApps, strategyKey, secondaryScreen)
  local primaryScreen = hs.screen.primaryScreen()
  local strategy = ws.strategies[strategyKey]

  -- Iterate in reverse order for proper z-index (last in list = on top)
  for i = #ws.apps, 1, -1 do
    local appName = ws.apps[i]
    local bundleID = self._apps[appName]

    if bundleID and readyApps[bundleID] then
      local app = hs.application.get(bundleID)
      if app then
        -- Determine target screen
        local targetScreen = primaryScreen
        if secondaryScreen and self:_shouldGoToSecondary(ws, appName) then
          targetScreen = secondaryScreen
        end

        -- Move to screen
        self:_moveAppToScreen(bundleID, targetScreen)

        -- Focus and apply strategy
        for _, window in ipairs(app:allWindows()) do
          window:focus()
          if strategy and strategy[appName] then
            self:_applyStrategy(strategy[appName])
          end
        end
      end
    end
  end
end

--- WorkspaceEngine:_activateWorkspace(ws)
--- Method
--- Activate a workspace
function obj:_activateWorkspace(ws)
  local screens = hs.screen.allScreens()
  local secondaryScreen = screens[2]
  local strategyKey = secondaryScreen and "secondary" or "primary"

  -- Track apps and their states
  local pendingApps = {}
  local readyApps = {}
  local startTimes = {}

  -- Get timing settings
  local timing = self._settings.workspace or {}
  local checkInterval = timing.checkInterval or 0.5
  local timeout = timing.timeout or 30

  -- Initialize pending apps and launch them
  for _, appName in ipairs(ws.apps) do
    local bundleID = self._apps[appName]
    if bundleID then
      pendingApps[bundleID] = appName
      startTimes[bundleID] = hs.timer.secondsSinceEpoch()

      -- Launch app if not already running
      if not self:_appHasWindows(bundleID) then
        self._appToggler:launchOrFocus(bundleID)
      end
    else
      print("WorkspaceEngine: Unknown app '" .. appName .. "' in workspace '" .. ws.name .. "'")
    end
  end

  -- Create self reference for timer callback
  local self_ref = self

  local function checkApps()
    local currentTime = hs.timer.secondsSinceEpoch()
    local remainingApps = false

    -- Check each pending app
    for bundleID, appName in pairs(pendingApps) do
      if currentTime - startTimes[bundleID] > timeout then
        -- App timed out
        pendingApps[bundleID] = nil
      elseif self_ref:_appHasWindows(bundleID) then
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
      if self_ref._activeTimer then
        self_ref._activeTimer:stop()
        self_ref._activeTimer = nil
      end

      -- Arrange all windows
      self_ref:_arrangeWindows(ws, readyApps, strategyKey, secondaryScreen)
    end
  end

  -- Stop any existing timer
  if self._activeTimer then
    self._activeTimer:stop()
  end

  -- Create and start the timer
  self._activeTimer = hs.timer.new(checkInterval, checkApps)
  self._activeTimer:start()
end

return obj
