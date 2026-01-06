local keyBindings = require('spoons.keyBindings')
local WindowManagement = require('spoons.windowManagement')

hs.window.animationDuration = 0

local actionMap = {
  ["Maximize"] = WindowManagement.maximizeWindow,
  ["Center"] = WindowManagement.center,
  ["Full Height Reasonable Width"] = WindowManagement.fullHeightReasonableWidth,
  ["Almost maximize"] = function() WindowManagement.resizeActiveWindowToPercentage(90, 90) end,
  ["Left half"] = WindowManagement.moveToLeftHalf,
  ["Right half"] = WindowManagement.moveToRightHalf,
  ["Next display"] = function() WindowManagement.moveWindowToDisplay('next') end,
  ["Previous display"] = function() WindowManagement.moveWindowToDisplay('previous') end,
  ["Reasonable size"] = function() WindowManagement.resizeActiveWindowToPercentage(90, 90) end,
  ["Small size"] = function() WindowManagement.resizeActiveWindowByPixels({ width = 700, height = 800 }) end,
  ["Increase size"] = WindowManagement.increaseWindowSize,
  ["Decrease size"] = WindowManagement.decreaseWindowSize,
  ["Hide all except focused"] = WindowManagement.hideAllExceptFocused,
  ["Move left"] = function() WindowManagement.moveWindowByPixels("left", 20) end,
  ["Move right"] = function() WindowManagement.moveWindowByPixels("right", 20) end,
  ["Move up"] = function() WindowManagement.moveWindowByPixels("up", 20) end,
  ["Move down"] = function() WindowManagement.moveWindowByPixels("down", 20) end,
  ["Screen recording"] = function()
    local secondaryScreen = hs.screen.allScreens()[2]
    local dimensions = {
      width = 2400,
      height = 1350,
    }
    WindowManagement.moveToScreen(secondaryScreen)
    WindowManagement.resizeActiveWindowByPixels(dimensions)
    WindowManagement.center()
    hs.alert.show("Window resized to " .. dimensions.width .. "x" .. dimensions.height)
  end
}

local WindowManagementBindings = {}

function WindowManagementBindings.initialize()
  for _, binding in ipairs(keyBindings.windowBindings) do
    local action = actionMap[binding.description]
    if action then
      hs.hotkey.bind(binding.modifiers, binding.key, action)
    else
      hs.alert.show("No action found for " .. binding.description)
    end
  end
end

return WindowManagementBindings
