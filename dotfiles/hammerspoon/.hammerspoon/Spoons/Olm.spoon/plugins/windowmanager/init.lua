--- === WindowManager ===
---
--- Window positioning and sizing operations
---
--- This is the olm side copy of WindowManager, made in the bundling pass, phase 6 of the
--- olm build plan, and the original this was copied from lived at
--- Spoons/WindowManager.spoon.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "WindowManager"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("WindowManager", "info")

-- Hold a value inside a travel range, whichever way round the two bounds arrive. A window
-- wider than the canvas inverts the range, since its left edge can then only sit at or left
-- of the canvas edge, and ordering the pair keeps that case a real range to slide along,
-- flush left through flush right, rather than an empty one that would pin the window where
-- it stands.
local function clampBetween(value, a, b)
  local low, high = math.min(a, b), math.max(a, b)
  if value < low then return low end
  if value > high then return high end
  return value
end

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
--- Adjust window size, `amount` being what the canvas's LONG edge grows by, with the short
--- edge taking its proportional share, so a window grows in the shape of the screen it is
--- growing inside.
---
--- A screen is almost never square and an ultrawide is nowhere near it, so a step applied
--- equally to both axes spends the same pixels on the short axis as on the long one, and a
--- growing window reaches the top and bottom of the canvas long before it reaches the sides.
--- Each axis therefore takes the step scaled by its own share of the longest one.
---
--- The LONG edge is the reference rather than the width, and that is the part portrait makes
--- necessary. Scaling from the width instead would still be proportional, but the step would
--- then mean the long edge on a landscape screen and the short edge on a rotated one, so the
--- same key would cover very different ground before and after a rotation. Anchoring on the
--- longest axis means one press always moves the long edge by `amount` whichever way the
--- screen is turned, and a square screen is simply the case where both shares are one.
---
--- Both axes are taken to whole pixels per side, since a window edge on a half pixel lines up
--- with nothing beside it.
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

  -- Each axis's share of the step, its own length over the longest, so the longest axis takes
  -- the step whole and the other one takes less. A zero longest means there is no usable
  -- canvas at all, where a share of one is as good an answer as any and nothing is about to be
  -- resized regardless.
  local longest = math.max(screenFrame.w, screenFrame.h)
  local shareW = longest > 0 and (screenFrame.w / longest) or 1
  local shareH = longest > 0 and (screenFrame.h / longest) or 1

  -- To whole pixels, and by an even number, since half of the step goes to each of the two
  -- opposing edges and a half pixel edge lines up with nothing beside it.
  local function wholePair(value)
    local half = value / 2
    local rounded = half >= 0 and math.floor(half + 0.5) or -math.floor(-half + 0.5)
    return rounded * 2
  end

  -- Growing has the canvas to stop at and shrinking has nothing, so it stops at a floor
  -- instead. Without one a held key walks a window down to a sliver and there is no keystroke
  -- that brings a lost window back. Per axis rather than one shared limit, since a window
  -- already at the floor on its height should still be able to lose width.
  local sizing = self._settings.windowSizing or {}
  local amountW, amountH = wholePair(amount * shareW), wholePair(amount * shareH)
  if amount < 0 then
    amountW = -math.min(-amountW, math.max(0, windowFrame.w - (sizing.minWidth or 400)))
    amountH = -math.min(-amountH, math.max(0, windowFrame.h - (sizing.minHeight or 300)))
    if amountW == 0 and amountH == 0 then return end
  end

  local roomLeft = math.max(0, windowFrame.x - screenFrame.x)
  local roomRight = math.max(0, (screenFrame.x + screenFrame.w) - (windowFrame.x + windowFrame.w))
  local roomTop = math.max(0, windowFrame.y - screenFrame.y)
  local roomBottom = math.max(0, (screenFrame.y + screenFrame.h) - (windowFrame.y + windowFrame.h))

  local increaseLeft = math.min(amountW / 2, roomLeft)
  local increaseRight = math.min(amountW / 2, roomRight)
  local increaseTop = math.min(amountH / 2, roomTop)
  local increaseBottom = math.min(amountH / 2, roomBottom)

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

--- WindowManager:_holdStep(press, held, hold)
--- Method
--- How far one press travels, which is one of two amounts and never anything in between.
---
--- A key pressed on its own moves `press`, small enough to place a window by eye. A key that
--- is being held moves `held`, far enough that crossing a screen is a hold rather than an
--- errand. `hold` is the depth the engine calls a repeating action with, 0 for the press
--- itself, and the first `holdGrace` of them count as the press.
---
--- Two amounts rather than a ramp between them, deliberately. A distance that keeps growing
--- under a held finger is a distance you cannot aim with, since where the window ends up
--- depends on exactly when you let go, and the timing underneath is steady for the same
--- reason. So a hold has one speed, it just is not the speed of a single press.
function obj:_holdStep(press, held, hold)
  hold = hold or 0
  local grace = (self._settings.windowSizing or {}).holdGrace or 1
  if hold < grace then return press end
  return held
end

--- WindowManager:_moveStep(hold)
--- Method
--- The move step, movePixels for a press and movePixelsHeld while the key is held.
function obj:_moveStep(hold)
  local sizing = self._settings.windowSizing or {}
  local press = sizing.movePixels or 20
  return self:_holdStep(press, sizing.movePixelsHeld or (press * 2), hold)
end

--- WindowManager:_resizeStep(hold)
--- Method
--- The resize step, resizePixels for a press and resizePixelsHeld while held.
---
--- Its own pair rather than the move's, and a larger one, because the two keys are not doing
--- the same amount of work with the same number. A move slides a window one distance, where a
--- resize spends its step across two axes and moves an edge rather than the whole window, so
--- the same figure covers less apparent ground. What the step means for each axis is
--- adjustSize's business, not this one's.
function obj:_resizeStep(hold)
  local sizing = self._settings.windowSizing or {}
  local press = sizing.resizePixels or 30
  return self:_holdStep(press, sizing.resizePixelsHeld or (press + 20), hold)
end

--- WindowManager:increaseSize(hold)
--- Method
--- Increase window size, by the held amount while the key is held
function obj:increaseSize(hold)
  self:adjustSize(self:_resizeStep(hold))
end

--- WindowManager:decreaseSize(hold)
--- Method
--- Decrease window size, by the held amount while the key is held
function obj:decreaseSize(hold)
  self:adjustSize(-self:_resizeStep(hold))
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
--- Move window by pixels in direction, stopping at the gap-inset canvas.
---
--- The step stops flush against the same border maximize uses, so a window slides to the
--- edge and stays on screen. It used to walk as far as it was asked to, which nothing
--- noticed while one press was one step of twenty pixels, and a held key that keeps stepping
--- turns that into a window pushed off the display and then off the next one. Crossing to
--- another display is what the display switch keys are for, and they sit on adjacent keys.
function obj:moveByPixels(direction, pixels)
  local win = hs.window.focusedWindow()
  if not win then return end

  pixels = pixels or (self._settings.windowSizing and self._settings.windowSizing.movePixels) or 20
  local frame = win:frame()
  local canvas = self:getScreenFrame(win:screen())

  -- Only the axis this key moved is clamped. Clamping both would let a press meant to move a
  -- window right also pull it down onto the canvas, which reads as the window drifting on its
  -- own, so a key changes the one thing it was pressed for and nothing else.
  if direction == "left" or direction == "right" then
    frame.x = frame.x + (direction == "right" and pixels or -pixels)
    frame.x = clampBetween(frame.x, canvas.x, canvas.x + canvas.w - frame.w)
  elseif direction == "up" or direction == "down" then
    frame.y = frame.y + (direction == "down" and pixels or -pixels)
    frame.y = clampBetween(frame.y, canvas.y, canvas.y + canvas.h - frame.h)
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

--- WindowManager:exactSizePlan(width, height, screen)
--- Method
--- What an exact size request WOULD do, without doing any of it, so a surface can say so
--- before a person commits to it. Answers the size that would land plus whether anything was
--- taken off it, and nothing else, since a caller wording a row needs those two facts and no
--- geometry. Nil for a request that is not two usable numbers.
---
--- The ceiling is the screen's visible frame, which is the same frame resizeByPixels applies
--- against, so the answer and the action agree by reading one thing. A request taller than the
--- space under the menu bar is therefore reported as trimmed rather than quietly placing a
--- window edge behind it, which is the honest answer even though a person asking for a round
--- number rarely expects the menu bar to come out of it.
---
--- The screen is resolved the way every other method here resolves it, the focused window's
--- own and the main screen otherwise. A LIST ASKING THIS WHILE IT IS SHOWING has no ordinary
--- focused window, so it reads the main screen, while the resize that follows runs once focus
--- is back and reads the real one. The two disagree only on a multiple display desk whose
--- screens are different sizes, where a row's trim wording can name a ceiling the action does
--- not use, which is why the caller is expected to hand the action the size as it was asked
--- for and let it trim against the screen it actually finds.
function obj:exactSizePlan(width, height, screen)
  local w, h = tonumber(width), tonumber(height)
  if not w or not h or w <= 0 or h <= 0 then return nil end

  screen = screen or (hs.window.focusedWindow() and hs.window.focusedWindow():screen()) or hs.screen.mainScreen()
  if not screen then return nil end
  local f = screen:frame()

  -- To whole pixels, since a window edge on a half pixel lines up with nothing beside it and a
  -- size read off a row should be a number a person recognises.
  local fitW = math.floor(math.min(w, f.w))
  local fitH = math.floor(math.min(h, f.h))
  return { width = fitW, height = fitH, clamped = fitW < w or fitH < h }
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
    increaseSize =         function(hold) self:increaseSize(hold) end,
    decreaseSize =         function(hold) self:decreaseSize(hold) end,
    nextDisplay =          function() self:moveToDisplay("next") end,
    previousDisplay =      function() self:moveToDisplay("previous") end,
    hideAllExceptFocused = function() self:hideAllExceptFocused() end,
    screenRecording =      function() self:screenRecording() end,
    -- An exact size a surface parsed, sizing the window to it and centring it. The argument
    -- is a table and never the hold depth the repeating actions below take, so a non table is
    -- refused rather than read as a width. Nothing binds a key to this, since a size has to
    -- come from somewhere and a key carries none, and a person who bound one anyway would be
    -- handing it that depth, which is exactly the case the guard exists for.
    --
    -- The size arrives as it was ASKED FOR rather than already trimmed, so the trim happens
    -- against the screen the window is actually on at the moment of the press. exactSizePlan
    -- is the same answer computed ahead of time for a row to read, and it says why the two
    -- can differ.
    exactSize =            function(size)
      if type(size) ~= "table" then return end
      local w, h = tonumber(size.width), tonumber(size.height)
      if not w or not h then return end
      -- The one hard failure worth an alert, the same shape adjustSize already uses. A chosen
      -- row that silently does nothing reads as a broken feature, and the ordinary way to get
      -- here with nothing focused is a desktop with no window on it.
      if not hs.window.focusedWindow() then
        hs.alert.show("No focused window!")
        return
      end
      self:resizeByPixels({ width = w, height = h })
    end,
    -- The four moves and the two resizes above take the hold depth the leader calls a
    -- repeating action with, and read their step off it, the press amount or the held one.
    -- Every other action here ignores the argument, since none of them repeats and a
    -- placement is the same wherever in a hold it is asked for.
    moveLeft =             function(hold) self:moveByPixels("left", self:_moveStep(hold)) end,
    moveRight =            function(hold) self:moveByPixels("right", self:_moveStep(hold)) end,
    moveUp =               function(hold) self:moveByPixels("up", self:_moveStep(hold)) end,
    moveDown =             function(hold) self:moveByPixels("down", self:_moveStep(hold)) end,
  }
end

--- WindowManager:bindToLeader(windowLeader, mapping, predicates)
--- Method
--- Bind window actions onto a WindowLeader spoon. `mapping` is an ordered list;
--- each entry is { action = <name>, leader = <keycode>, key = <key>,
--- mods = <optional list>, when = <optional predicate name>,
--- repeats = <optional bool> }. `repeats` says the action keeps firing while its key is
--- held, which only some of these want. A step is worth repeating and a placement is not, so
--- moving and resizing carry it while maximize, the halves and the display switch do not,
--- since holding a key that puts a window somewhere exact would only put it there again. `predicates` maps
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
          fn = function(hold)
            if p() then action(hold) end
          end
        end
      end
      windowLeader:bind(binding.leader, binding.key, fn, binding.mods, binding.repeats)
    else
      log.w("Unknown action '" .. tostring(binding.action) .. "'")
    end
  end
  return self
end

return obj
