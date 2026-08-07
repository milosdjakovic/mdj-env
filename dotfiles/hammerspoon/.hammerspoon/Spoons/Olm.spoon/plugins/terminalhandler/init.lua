--- === TerminalHandler ===
---
--- Specialized terminal app handling with auto-placement
---
--- This is the olm side copy of TerminalHandler, made in the bundling pass, phase 6 of the
--- olm build plan, and the original this was copied from still lives at
--- Spoons/TerminalHandler.spoon.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "TerminalHandler"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- Dependencies (injected via configure)
obj._appToggler = nil
obj._windowManager = nil
obj._terminalBundleID = nil
obj._timing = nil
obj._size = nil
obj._minPadding = nil
-- targetScreen() returns the hs.screen to place the terminal on. Injected from
-- the composition root, so the engine never decides where itself. Optional; when
-- absent the engine falls back to the first attached screen.
obj._targetScreen = nil

--- TerminalHandler:init()
--- Method
--- Initialize the spoon
function obj:init()
  return self
end

--- TerminalHandler:configure(opts)
--- Method
--- Configure the spoon with dependencies
function obj:configure(opts)
  opts = opts or {}
  self._appToggler = opts.appToggler
  self._windowManager = opts.windowManager
  self._terminalBundleID = opts.terminalBundleID
  self._timing = opts.timing or {
    initialDelay = 0.1,
    checkInterval = 0.25,
    maxAttempts = 20,
  }
  self._size = opts.size or { width = 2400, height = 1350 }
  self._minPadding = opts.minPadding or { x = 20, y = 20 }
  self._targetScreen = opts.targetScreen
  return self
end

--- TerminalHandler:_isAppReady(bundleID)
--- Method
--- Check if app is ready (has windows and is focused)
function obj:_isAppReady(bundleID)
  local app = hs.application.get(bundleID)
  if not app then return false end

  local win = app:mainWindow()
  if not win then return false end

  local focusedWindow = hs.window.focusedWindow()
  if not focusedWindow or focusedWindow:application():bundleID() ~= bundleID then
    return false
  end

  return true
end

--- TerminalHandler:_handleWindowPlacement(app)
--- Method
--- Handle window placement for terminal with padding-aware sizing.
--- Uses frame (below menu bar, above dock) with minimum padding on
--- all sides.
function obj:_handleWindowPlacement(app)
  local screenToMove = self._targetScreen and self._targetScreen()
  screenToMove = screenToMove or hs.screen.allScreens()[1]

  self._windowManager:moveToScreen(screenToMove)

  local win = hs.window.focusedWindow()
  if not win then return end

  local screen = win:screen()
  local frame = screen:frame()

  local availX = frame.x
  local availY = frame.y
  local availW = frame.w
  local availH = frame.h

  local padX = self._minPadding.x
  local padY = self._minPadding.y
  local paddedW = availW - (padX * 2)
  local paddedH = availH - (padY * 2)

  local targetW = math.min(self._size.width, paddedW)
  local targetH = math.min(self._size.height, paddedH)

  local newX = availX + (availW - targetW) / 2
  local newY = availY + (availH - targetH) / 2

  win:setFrame(hs.geometry.rect(newX, newY, targetW, targetH))
end

--- TerminalHandler:_setupWindowManagement(bundleID)
--- Method
--- Set up async window management after toggle
---
--- Both stages are held in fields on the spoon. A Hammerspoon timer is userdata whose
--- finalizer stops it, so a pending one nothing refers to can be collected before it fires,
--- and the window would then never be placed with nothing said about it. The two stages are
--- strictly sequential so one field each is enough, and a fresh toggle stops whichever stage
--- is outstanding, since it is waiting on a window the newer toggle has superseded.
function obj:_setupWindowManagement(bundleID)
  local timing = self._timing
  local self_ref = self

  if self._setupDelay then self._setupDelay:stop() end
  if self._readyWait then self._readyWait:stop() end
  self._setupDelay = hs.timer.doAfter(timing.initialDelay, function()
    self_ref._readyWait = hs.timer.waitUntil(
      function() return self_ref:_isAppReady(bundleID) end,
      function()
        local app = hs.application.get(bundleID)
        if app then
          app:activate()
          self_ref:_handleWindowPlacement(app)
        end
      end,
      timing.checkInterval,
      timing.maxAttempts
    )
  end)
end

--- TerminalHandler:toggle()
--- Method
--- Toggle the terminal app with window management
function obj:toggle()
  if not self._terminalBundleID then
    hs.alert.show("Terminal not configured")
    return
  end

  self._appToggler:toggle(self._terminalBundleID)
  self:_setupWindowManagement(self._terminalBundleID)
end

--- TerminalHandler:bindHotkeys(mapping)
--- Method
--- Bind hotkeys for terminal handler
function obj:bindHotkeys(mapping)
  if mapping.terminal then
    hs.hotkey.bind(mapping.terminal.modifiers, mapping.terminal.key, function()
      self:toggle()
    end)
  end
  return self
end

return obj
