--- === WindowManager ===
---
--- Window positioning and sizing operations
---

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "WindowManager"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- Dependencies (injected via configure)
obj._stageManager = nil
obj._settings = nil

--- WindowManager:init()
--- Method
--- Initialize the spoon
function obj:init()
  hs.window.animationDuration = 0
  return self
end

--- WindowManager:configure(opts)
--- Method
--- Configure the spoon with dependencies
function obj:configure(opts)
  opts = opts or {}
  self._stageManager = opts.stageManager
  self._settings = opts.settings or {}
  hs.window.animationDuration = self._settings.windowAnimationDuration or 0
  return self
end

--- WindowManager:getScreenFrame(screen)
--- Method
--- Get screen frame adjusted for Stage Manager
function obj:getScreenFrame(screen)
  screen = screen or (hs.window.focusedWindow() and hs.window.focusedWindow():screen()) or hs.screen.mainScreen()
  local screenFrame = screen:frame()

  if self._stageManager and self._stageManager:isActive() then
    local margin = self._settings.stageManagerMargin or 66
    screenFrame.x = screenFrame.x + margin
    screenFrame.w = screenFrame.w - margin
  end

  return screenFrame
end

--- WindowManager:maximize()
--- Method
--- Maximize the focused window
function obj:maximize()
  local win = hs.window.focusedWindow()
  if win then
    local screen = win:screen()
    local screenFrame = self:getScreenFrame(screen)
    win:setFrame(hs.geometry.rect(screenFrame.x, screenFrame.y, screenFrame.w, screenFrame.h))
  end
end

--- WindowManager:center()
--- Method
--- Center the focused window on screen
function obj:center()
  local win = hs.window.focusedWindow()
  if win then
    local screen = win:screen()
    local frame = win:frame()
    local screenFrame = self:getScreenFrame(screen)

    frame.x = screenFrame.x + (screenFrame.w - frame.w) / 2
    frame.y = screenFrame.y + (screenFrame.h - frame.h) / 2

    win:setFrame(frame)
  end
end

--- WindowManager:fullHeightReasonableWidth()
--- Method
--- Make window full height with reasonable width
function obj:fullHeightReasonableWidth()
  local win = hs.window.focusedWindow()
  if not win then return end

  local screen = win:screen()
  local screenFrame = self:getScreenFrame(screen)
  local maxWidth = (self._settings.windowSizing and self._settings.windowSizing.fullHeightMaxWidth) or 2400

  local frame = win:frame()
  frame.h = screenFrame.h
  frame.w = math.min(screenFrame.w - 140, maxWidth)
  frame.x = screenFrame.x + (screenFrame.w - frame.w) / 2
  frame.y = screenFrame.y

  win:setFrame(frame)
end

--- WindowManager:resizeToPercentage(widthPercentage, heightPercentage)
--- Method
--- Resize window to percentage of screen
function obj:resizeToPercentage(widthPercentage, heightPercentage)
  local win = hs.window.focusedWindow()
  if not win then return end

  local screen = win:screen()
  local screenFrame = self:getScreenFrame(screen)

  local frame = win:frame()
  frame.w = (widthPercentage / 100) * screenFrame.w
  frame.h = (heightPercentage / 100) * screenFrame.h
  frame.x = screenFrame.x + (screenFrame.w - frame.w) / 2
  frame.y = screenFrame.y + (screenFrame.h - frame.h) / 2

  win:setFrame(frame)
end

--- WindowManager:resizeDefault(maxWidth, maxHeight)
--- Method
--- Resize window to default size
function obj:resizeDefault(maxWidth, maxHeight)
  local sizing = self._settings.windowSizing or {}
  maxWidth = maxWidth or sizing.maxWidth or 1800
  maxHeight = maxHeight or sizing.maxHeight or 1200

  local win = hs.window.focusedWindow()
  if not win then return end

  local screen = win:screen()
  local screenFrame = self:getScreenFrame(screen)

  local newWidth = math.min(maxWidth, screenFrame.w - 80)
  local newHeight = math.min(maxHeight, screenFrame.h - 80)
  local newX = (screenFrame.w - newWidth) / 2
  local newY = (screenFrame.h - newHeight) / 2

  win:setFrame(hs.geometry.rect(screenFrame.x + newX, screenFrame.y + newY, newWidth, newHeight))
end

--- WindowManager:leftHalf()
--- Method
--- Move window to left half of screen
function obj:leftHalf()
  local win = hs.window.focusedWindow()
  if not win then return end

  local screen = win:screen()
  local screenFrame = self:getScreenFrame(screen)

  local frame = win:frame()
  frame.w = screenFrame.w / 2
  frame.h = screenFrame.h
  frame.x = screenFrame.x
  frame.y = screenFrame.y

  win:setFrame(frame)
end

--- WindowManager:rightHalf()
--- Method
--- Move window to right half of screen
function obj:rightHalf()
  local win = hs.window.focusedWindow()
  if not win then return end

  local screen = win:screen()
  local screenFrame = self:getScreenFrame(screen)

  local frame = win:frame()
  frame.w = screenFrame.w / 2
  frame.h = screenFrame.h
  frame.x = screenFrame.x + (screenFrame.w / 2)
  frame.y = screenFrame.y

  win:setFrame(frame)
end

--- WindowManager:moveToDisplay(direction)
--- Method
--- Move window to next or previous display
function obj:moveToDisplay(direction)
  local window = hs.window.focusedWindow()
  if not window then return end

  local screen = window:screen()
  local nextScreen = nil

  if direction == "next" then
    nextScreen = screen:next()
  elseif direction == "previous" then
    nextScreen = screen:previous()
  end

  if nextScreen then
    window:moveToScreen(nextScreen)
  end
end

--- WindowManager:moveToScreen(screen)
--- Method
--- Move focused window to specific screen
function obj:moveToScreen(screen)
  local window = hs.window.focusedWindow()
  if window and screen then
    window:moveToScreen(screen, true, true, 0)
  end
end

--- WindowManager:adjustSize(amount)
--- Method
--- Adjust window size by amount
function obj:adjustSize(amount)
  amount = amount or 100

  local win = hs.window.focusedWindow()
  if not win then
    hs.alert.show("No focused window!")
    return
  end

  local screen = win:screen()
  local windowFrame = win:frame()
  local screenFrame = screen:frame()

  local increaseLeft = math.min(amount / 2, windowFrame.x - screenFrame.x)
  local increaseRight = math.min(amount / 2, (screenFrame.x + screenFrame.w) - (windowFrame.x + windowFrame.w))
  local increaseTop = math.min(amount / 2, windowFrame.y - screenFrame.y)
  local increaseBottom = math.min(amount / 2, (screenFrame.y + screenFrame.h) - (windowFrame.y + windowFrame.h))

  local newWidth = windowFrame.w + increaseLeft + increaseRight
  local newLeft = windowFrame.x - increaseLeft
  if newLeft < screenFrame.x then
    increaseRight = increaseRight + (screenFrame.x - newLeft)
    increaseLeft = windowFrame.x - screenFrame.x
  end

  local newHeight = windowFrame.h + increaseTop + increaseBottom
  local newTop = windowFrame.y - increaseTop
  if newTop < screenFrame.y then
    increaseBottom = increaseBottom + (screenFrame.y - newTop)
    increaseTop = windowFrame.y - screenFrame.y
  end

  windowFrame.x = windowFrame.x - increaseLeft
  windowFrame.y = windowFrame.y - increaseTop
  windowFrame.w = windowFrame.w + increaseLeft + increaseRight
  windowFrame.h = windowFrame.h + increaseTop + increaseBottom

  win:setFrame(windowFrame)
end

--- WindowManager:increaseSize()
--- Method
--- Increase window size
function obj:increaseSize()
  local pixels = (self._settings.windowSizing and self._settings.windowSizing.resizePixels) or 50
  self:adjustSize(pixels)
end

--- WindowManager:decreaseSize()
--- Method
--- Decrease window size
function obj:decreaseSize()
  local pixels = (self._settings.windowSizing and self._settings.windowSizing.resizePixels) or 50
  self:adjustSize(-pixels)
end

--- WindowManager:hideAllExceptFocused()
--- Method
--- Hide all windows except the focused one
function obj:hideAllExceptFocused()
  local focusedWindow = hs.window.focusedWindow()
  if not focusedWindow then return end

  local focusedApp = focusedWindow:application()
  local allWindows = hs.window.allWindows()

  for _, window in ipairs(allWindows) do
    local app = window:application()
    if app:pid() ~= focusedApp:pid() then
      app:hide()
    end
  end
end

--- WindowManager:moveByPixels(direction, pixels)
--- Method
--- Move window by pixels in direction
function obj:moveByPixels(direction, pixels)
  local win = hs.window.focusedWindow()
  if not win then return end

  pixels = pixels or (self._settings.windowSizing and self._settings.windowSizing.movePixels) or 20
  local frame = win:frame()

  if direction == "left" then
    frame.x = frame.x - pixels
  elseif direction == "right" then
    frame.x = frame.x + pixels
  elseif direction == "up" then
    frame.y = frame.y - pixels
  elseif direction == "down" then
    frame.y = frame.y + pixels
  end

  win:setFrame(frame)
end

--- WindowManager:screenRecording()
--- Method
--- Move to secondary screen and resize for screen recording
function obj:screenRecording()
  local screens = hs.screen.allScreens()
  local targetScreen = screens[2] or screens[1]
  local sizing = self._settings.windowSizing and self._settings.windowSizing.screenRecording or { width = 2400, height = 1350 }

  self:moveToScreen(targetScreen)
  self:resizeByPixels(sizing)
end

--- WindowManager:resizeByPixels(dimensions)
--- Method
--- Resize window to specific pixel dimensions
function obj:resizeByPixels(dimensions)
  local win = hs.window.focusedWindow()
  if not win then return end

  local screen = win:screen()
  local screenFrame = screen:frame()

  local targetWidth = dimensions.width or screenFrame.w
  local targetHeight = dimensions.height or screenFrame.h

  local newWidth = math.min(targetWidth, screenFrame.w)
  local newHeight = math.min(targetHeight, screenFrame.h)

  local newX = screenFrame.x + (screenFrame.w - newWidth) / 2
  local newY = screenFrame.y + (screenFrame.h - newHeight) / 2

  win:setFrame(hs.geometry.rect(newX, newY, newWidth, newHeight))
end

--- WindowManager:smallSize()
--- Method
--- Resize window to small size
function obj:smallSize()
  local sizing = self._settings.windowSizing and self._settings.windowSizing.smallSize or { width = 700, height = 800 }
  self:resizeByPixels(sizing)
  self:center()
end

--- WindowManager:bindHotkeys(mapping)
--- Method
--- Bind hotkeys for window management
function obj:bindHotkeys(mapping)
  local actionMap = {
    maximize =             function() self:maximize() end,
    center =               function() self:center() end,
    fullHeightReasonable = function() self:fullHeightReasonableWidth() end,
    almostMaximize =       function() self:resizeToPercentage(97, 100) end,
    leftHalf =             function() self:leftHalf() end,
    rightHalf =            function() self:rightHalf() end,
    reasonableSize =       function() self:resizeDefault() end,
    smallSize =            function() self:smallSize() end,
    increaseSize =         function() self:increaseSize() end,
    decreaseSize =         function() self:decreaseSize() end,
    nextDisplay =          function() self:moveToDisplay("next") end,
    previousDisplay =      function() self:moveToDisplay("previous") end,
    hideAllExceptFocused = function() self:hideAllExceptFocused() end,
    screenRecording =      function() self:screenRecording() end,
    moveLeft =             function() self:moveByPixels("left") end,
    moveRight =            function() self:moveByPixels("right") end,
    moveUp =               function() self:moveByPixels("up") end,
    moveDown =             function() self:moveByPixels("down") end,
  }

  for actionName, binding in pairs(mapping) do
    local action = actionMap[actionName]
    if action then
      hs.hotkey.bind(binding.modifiers, binding.key, action)
    else
      print("WindowManager: Unknown action '" .. actionName .. "'")
    end
  end

  return self
end

return obj
