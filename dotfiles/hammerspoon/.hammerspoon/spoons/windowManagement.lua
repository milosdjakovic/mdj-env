local WindowManagement = {}
local StageManager = require("spoons.stageManager")

local MARGIN = 66

-- Function to get the adjusted screen frame based on StageManager status
local function getScreenFrame(screen)
  local screenFrame = screen:frame()
  if StageManager.active then
    screenFrame.x = screenFrame.x + MARGIN
    screenFrame.w = screenFrame.w - MARGIN
  end
  return screenFrame
end

function WindowManagement.maximizeWindow()
  local win = hs.window.focusedWindow()
  if win then
    local screen = win:screen()
    local screenFrame = getScreenFrame(screen)
    local newFrame = hs.geometry.rect(screenFrame.x, screenFrame.y, screenFrame.w, screenFrame.h)
    win:setFrame(newFrame)
  end
end

function WindowManagement.center()
  local win = hs.window.focusedWindow()
  if win then
    local screen = win:screen()
    local frame = win:frame()
    local screenFrame = getScreenFrame(screen)

    frame.x = screenFrame.x + (screenFrame.w - frame.w) / 2
    frame.y = screenFrame.y + (screenFrame.h - frame.h) / 2

    win:setFrame(frame)
  end
end

function WindowManagement.fullHeightReasonableWidth()
  local screen = hs.screen.mainScreen()
  local screenFrame = getScreenFrame(screen)
  local win = hs.window.focusedWindow()

  if win then
    local frame = win:frame()
    frame.h = screenFrame.h
    frame.w = math.min(screenFrame.w - 140, 2400) -- Subtracting 40px from both left and right sides, capped at 1600px
    frame.x = screenFrame.x + (screenFrame.w - frame.w) / 2
    frame.y = screenFrame.y
    win:setFrame(frame)
  end
end

function WindowManagement.resizeActiveWindowToPercentage(widthPercentage, heightPercentage)
  local screen = hs.screen.mainScreen()
  local screenFrame = getScreenFrame(screen)
  local win = hs.window.focusedWindow()

  if win then
    local frame = win:frame()

    -- Calculate the new frame dimensions based on the percentage
    frame.w = (widthPercentage / 100) * screenFrame.w
    frame.h = (heightPercentage / 100) * screenFrame.h
    frame.x = screenFrame.x + (screenFrame.w - frame.w) / 2
    frame.y = screenFrame.y + (screenFrame.h - frame.h) / 2

    win:setFrame(frame)
  end
end

function WindowManagement.resizeActiveWindowByPixels(dimensions)
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

function WindowManagement.moveToLeftHalf()
  local screen = hs.screen.mainScreen()
  local screenFrame = getScreenFrame(screen)
  local win = hs.window.focusedWindow()

  if win then
    local frame = win:frame()

    -- Set dimensions for left half
    frame.w = screenFrame.w / 2
    frame.h = screenFrame.h
    frame.x = screenFrame.x
    frame.y = screenFrame.y

    win:setFrame(frame)
  end
end

function WindowManagement.moveToRightHalf()
  local screen = hs.screen.mainScreen()
  local screenFrame = getScreenFrame(screen)
  local win = hs.window.focusedWindow()

  if win then
    local frame = win:frame()

    -- Set dimensions for right half
    frame.w = screenFrame.w / 2
    frame.h = screenFrame.h
    frame.x = screenFrame.x + (screenFrame.w / 2)
    frame.y = screenFrame.y

    win:setFrame(frame)
  end
end

WindowManagement.windowInfoStorage = {}

function WindowManagement.storeWindowInfo(displayId, windowId, windowDimensions)
  -- Check if the display table exists in storage, else create it
  if not WindowManagement.windowInfoStorage[displayId] then
    WindowManagement.windowInfoStorage[displayId] = {}
  end

  -- Store window information under the corresponding display and windowId
  WindowManagement.windowInfoStorage[displayId][windowId] = windowDimensions
end

function WindowManagement.getWindowInfo(displayId, windowId)
  if WindowManagement.windowInfoStorage[displayId] and WindowManagement.windowInfoStorage[displayId][windowId] then
    return WindowManagement.windowInfoStorage[displayId][windowId]
  else
    return nil
  end
end

function WindowManagement.fitFocusedWindowIntoScreen()
  local window = hs.window.focusedWindow()
  if not window then
    hs.alert.show("No focused window")
    return
  end

  local screen = window:screen()
  local screenFrame = getScreenFrame(screen)
  local windowFrame = window:frame()

  -- Adjust window width
  if windowFrame.w <= screenFrame.w then
    if windowFrame.x < screenFrame.x then
      windowFrame.x = screenFrame.x
    elseif (windowFrame.x + windowFrame.w) > (screenFrame.x + screenFrame.w) then
      windowFrame.x = screenFrame.x + screenFrame.w - windowFrame.w
    end
  else
    windowFrame.w = screenFrame.w
    windowFrame.x = screenFrame.x
  end

  -- Adjust window height
  if windowFrame.h <= screenFrame.h then
    if windowFrame.y < screenFrame.y then
      windowFrame.y = screenFrame.y
    elseif (windowFrame.y + windowFrame.h) > (screenFrame.y + screenFrame.h) then
      windowFrame.y = screenFrame.y + screenFrame.h - windowFrame.h
    end
  else
    windowFrame.h = screenFrame.h
    windowFrame.y = screenFrame.y
  end

  -- Apply the adjusted frame to the window
  window:setFrame(windowFrame)
end

function WindowManagement.moveWindowToDisplay(direction)
  local window = hs.window.focusedWindow()
  if not window then
    return
  end

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

function WindowManagement.moveToScreen(screen)
  local window = hs.window.focusedWindow()
  if window and screen then
    window:moveToScreen(screen, true, true, 0)
  end
end

function WindowManagement.resizeActiveWindow(maxWidth, maxHeight)
  -- Set default values for maxWidth and maxHeight if not provided
  maxWidth = maxWidth or 1800
  maxHeight = maxHeight or 1200

  -- Get the active window
  local win = hs.window.focusedWindow()
  if not win then return end

  -- Get the screen frame
  local screen = win:screen()
  local screenFrame = getScreenFrame(screen)

  -- Calculate the new size and position for the window
  local newWidth = math.min(maxWidth, screenFrame.w - 80)
  local newHeight = math.min(maxHeight, screenFrame.h - 80)
  local newX = (screenFrame.w - newWidth) / 2
  local newY = (screenFrame.h - newHeight) / 2

  -- Set the new frame for the window
  win:setFrame(hs.geometry.rect(screenFrame.x + newX, screenFrame.y + newY, newWidth, newHeight))
end

function WindowManagement.adjustWindowSize(amount)
  -- Default size adjustment if amount is not provided
  amount = amount or 100

  -- Get the currently focused window
  local win = hs.window.focusedWindow()
  if not win then
    hs.alert.show("No focused window!")
    return
  end

  -- Get the current screen, window frame, and screen frame
  local screen = win:screen()
  local windowFrame = win:frame()
  local screenFrame = screen:frame()

  -- Calculate new dimensions and positions
  local increaseLeft = math.min(amount / 2, windowFrame.x - screenFrame.x)
  local increaseRight = math.min(amount / 2, (screenFrame.x + screenFrame.w) - (windowFrame.x + windowFrame.w))
  local increaseTop = math.min(amount / 2, windowFrame.y - screenFrame.y)
  local increaseBottom = math.min(amount / 2, (screenFrame.y + screenFrame.h) - (windowFrame.y + windowFrame.h))

  -- Adjust left and right independently
  local newWidth = windowFrame.w + increaseLeft + increaseRight
  local newLeft = windowFrame.x - increaseLeft
  if newLeft < screenFrame.x then
    increaseRight = increaseRight + (screenFrame.x - newLeft)
    increaseLeft = windowFrame.x - screenFrame.x
  end

  -- Adjust top and bottom independently
  local newHeight = windowFrame.h + increaseTop + increaseBottom
  local newTop = windowFrame.y - increaseTop
  if newTop < screenFrame.y then
    increaseBottom = increaseBottom + (screenFrame.y - newTop)
    increaseTop = windowFrame.y - screenFrame.y
  end

  -- Set the new adjusted window frame
  windowFrame.x = windowFrame.x - increaseLeft
  windowFrame.y = windowFrame.y - increaseTop
  windowFrame.w = windowFrame.w + increaseLeft + increaseRight
  windowFrame.h = windowFrame.h + increaseTop + increaseBottom

  -- Apply the new frame to the window
  win:setFrame(windowFrame)
end

function WindowManagement.increaseWindowSize()
  WindowManagement.adjustWindowSize(50)
end

function WindowManagement.decreaseWindowSize()
  WindowManagement.adjustWindowSize(-50)
end

function WindowManagement.hideAllExceptFocused()
  -- Get the currently focused window
  local focusedWindow = hs.window.focusedWindow()

  -- Get the application of the focused window
  local focusedApp = focusedWindow:application()

  -- Get all open windows
  local allWindows = hs.window.allWindows()

  -- Iterate through all windows
  for _, window in ipairs(allWindows) do
    -- Get the application of the current window
    local app = window:application()

    -- Hide the application if it's not the focused application
    if app:pid() ~= focusedApp:pid() then
      app:hide()
    end
  end
end

-- Move window by specified pixels in given direction
function WindowManagement.moveWindowByPixels(direction, pixels)
  local win = hs.window.focusedWindow()
  if not win then return end

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

return WindowManagement
