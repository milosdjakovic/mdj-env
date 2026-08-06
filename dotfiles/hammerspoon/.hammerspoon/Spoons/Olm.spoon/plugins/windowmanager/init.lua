--- === WindowManager ===
---
--- Window positioning and sizing operations
---
--- This is the olm side copy of WindowManager, made in the bundling pass, phase 6 of the
--- olm build plan, and the original this was copied from still lives at
--- Spoons/WindowManager.spoon.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "WindowManager"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("WindowManager", "info")

-- Dependencies (injected via configure)
obj._margins = {}
obj._settings = nil

--- WindowManager:init()
--- Method
--- Initialize the spoon
function obj:init()
  return self
end

--- WindowManager:configure(opts)
--- Method
--- Configure the spoon with dependencies
function obj:configure(opts)
  opts = opts or {}
  self._margins = opts.margins or {}
  self._settings = opts.settings or {}
  hs.window.animationDuration = self._settings.windowAnimationDuration or 0
  return self
end

--- WindowManager:_resolveMargin(value)
--- Method
--- Resolve a margin value (number or function returning number)
function obj:_resolveMargin(value)
  if type(value) == "function" then
    return value() or 0
  end
  return value or 0
end

--- WindowManager:_gap()
--- Method
--- The configured window gap in pixels (0 when disabled). The same value insets
--- the canvas (via the margins in init.lua) and forms the gutter between tiled
--- windows, so outer and inner spacing stay uniform.
function obj:_gap()
  return (self._settings and self._settings.gap) or 0
end

--- WindowManager:getScreenFrame(screen)
--- Method
--- Get screen frame adjusted for margins (canvas)
function obj:getScreenFrame(screen)
  screen = screen or (hs.window.focusedWindow() and hs.window.focusedWindow():screen()) or hs.screen.mainScreen()
  local f = screen:frame()

  local top = self:_resolveMargin(self._margins.top)
  local right = self:_resolveMargin(self._margins.right)
  local bottom = self:_resolveMargin(self._margins.bottom)
  local left = self:_resolveMargin(self._margins.left)

  return {
    x = f.x + left,
    y = f.y + top,
    w = f.w - left - right,
    h = f.h - top - bottom,
  }
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

--- WindowManager:fullHeight()
--- Method
--- Expand the focused window to full height, leaving its width and x untouched
--- (pure vertical fill). Distinct from fullHeightReasonableWidth(), which the
--- workspace automation uses to also set a centered reasonable width.
function obj:fullHeight()
  local win = hs.window.focusedWindow()
  if not win then return end

  local screen = win:screen()
  local screenFrame = self:getScreenFrame(screen)

  local frame = win:frame()
  frame.h = screenFrame.h
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
  local gap = self:_gap()

  local frame = win:frame()
  frame.w = (screenFrame.w - gap) / 2
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
  local gap = self:_gap()

  local frame = win:frame()
  frame.w = (screenFrame.w - gap) / 2
  frame.h = screenFrame.h
  frame.x = screenFrame.x + (screenFrame.w + gap) / 2
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
  -- Clamp to the gap-inset canvas so growing a window stops at the same border
  -- as maximize (rather than flushing to the raw screen edge). max(0, ...) keeps
  -- a window that is already outside the canvas from inverting on growth.
  local screenFrame = self:getScreenFrame(screen)

  local roomLeft = math.max(0, windowFrame.x - screenFrame.x)
  local roomRight = math.max(0, (screenFrame.x + screenFrame.w) - (windowFrame.x + windowFrame.w))
  local roomTop = math.max(0, windowFrame.y - screenFrame.y)
  local roomBottom = math.max(0, (screenFrame.y + screenFrame.h) - (windowFrame.y + windowFrame.h))

  local increaseLeft = math.min(amount / 2, roomLeft)
  local increaseRight = math.min(amount / 2, roomRight)
  local increaseTop = math.min(amount / 2, roomTop)
  local increaseBottom = math.min(amount / 2, roomBottom)

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

--- WindowManager:actions()
--- Method
--- Return the action-name -> handler map used by hotkey/leader binding.
function obj:actions()
  return {
    maximize =             function() self:maximize() end,
    center =               function() self:center() end,
    fullHeight =           function() self:fullHeight() end,
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
end

--- WindowManager:bindToLeader(windowLeader, mapping, predicates)
--- Method
--- Bind window actions onto a WindowLeader spoon. `mapping` is an ordered list;
--- each entry is { action = <name>, leader = <keycode>, key = <key>,
--- mods = <optional list>, when = <optional predicate name> }. `predicates` maps
--- a `when` name to a function() -> bool. An entry with a `when` is wrapped so it
--- runs only while its predicate holds; a false predicate makes the key a no-op
--- (still swallowed by the held leader, so no raw character leaks). This is the
--- same gate the overlay applies to rows, so the key and the overlay agree.
--- An unknown name is treated as always active, matching the overlay, so a typo
--- fails visibly rather than silently disabling a binding.
function obj:bindToLeader(windowLeader, mapping, predicates)
  predicates = predicates or {}
  local actionMap = self:actions()
  for _, binding in ipairs(mapping) do
    local action = actionMap[binding.action]
    if action then
      local when = binding.when
      local fn = action
      if when then
        local p = predicates[when]
        if not p then
          log.w("unknown predicate '" .. tostring(when) .. "'")
        else
          fn = function()
            if p() then action() end
          end
        end
      end
      windowLeader:bind(binding.leader, binding.key, fn, binding.mods)
    else
      log.w("Unknown action '" .. tostring(binding.action) .. "'")
    end
  end
  return self
end

return obj
