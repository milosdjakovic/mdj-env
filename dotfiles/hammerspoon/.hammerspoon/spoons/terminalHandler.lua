local keyBindings = require("spoons.keyBindings")
local AppToggler = require("spoons.appToggler")
local WindowManagement = require('spoons.windowManagement')
local AppIdentifiers = require('spoons.appIdentifiers')

local TerminalHandler = {}

-- Configuration
TerminalHandler.config = {
  timing = {
    initialDelay = 0.1,  -- Initial delay after app toggle
    checkInterval = 0.25, -- Interval between ready checks
    maxAttempts = 20     -- Maximum number of attempts to check
  }
}

-- Helper functions
function TerminalHandler.isAppReady(bundleID)
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

function TerminalHandler.handleWindowPlacement(app)
  local screens = hs.screen.allScreens()
  local screenToMove = screens[2] or screens[1]

  WindowManagement.moveToScreen(screenToMove)
  WindowManagement.resizeActiveWindow()
  WindowManagement.center()
end

function TerminalHandler.setupWindowManagement(bundleID)
  hs.timer.doAfter(TerminalHandler.config.timing.initialDelay, function()
    hs.timer.waitUntil(
      function() return TerminalHandler.isAppReady(bundleID) end,
      function()
        local app = hs.application.get(bundleID)
        app:activate()
        TerminalHandler.handleWindowPlacement(app)
      end,
      TerminalHandler.config.timing.checkInterval,
      TerminalHandler.config.timing.maxAttempts
    )
  end)
end

-- Main initialization
function TerminalHandler.initialize()
  local preferredTerminal = AppIdentifiers.Ghostty

  hs.hotkey.bind(
    keyBindings.terminalHandlerBindings.modifiers,
    keyBindings.terminalHandlerBindings.key,
    function()
      AppToggler.toggle(preferredTerminal)
      TerminalHandler.setupWindowManagement(preferredTerminal)
    end
  )
end

return TerminalHandler
