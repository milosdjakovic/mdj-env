--- === DockAutoHide ===
---
--- Control dock auto-hide setting
---

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "DockAutoHide"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

--- DockAutoHide:init()
--- Method
--- Initialize the spoon
function obj:init()
  return self
end

--- DockAutoHide:isEnabled()
--- Method
--- Check if dock auto-hide is enabled
function obj:isEnabled()
  local output = hs.execute("defaults read com.apple.dock autohide 2>/dev/null")
  return output:match("1") ~= nil
end

--- DockAutoHide:enable()
--- Method
--- Enable dock auto-hide (dock hides when not in use)
function obj:enable()
  hs.execute("defaults write com.apple.dock autohide -bool true")
  hs.execute([[osascript -e 'tell application "System Events" to tell dock preferences to set autohide to true']])
  return self
end

--- DockAutoHide:disable()
--- Method
--- Disable dock auto-hide (dock always visible)
function obj:disable()
  hs.execute("defaults write com.apple.dock autohide -bool false")
  hs.execute([[osascript -e 'tell application "System Events" to tell dock preferences to set autohide to false']])
  return self
end

--- DockAutoHide:toggle()
--- Method
--- Toggle dock auto-hide state
function obj:toggle()
  if self:isEnabled() then
    self:disable()
  else
    self:enable()
  end
  return self
end

--- DockAutoHide:bindHotkeys(mapping)
--- Method
--- Bind hotkeys
function obj:bindHotkeys(mapping)
  local actions = {
    toggle = function() self:toggle() end,
    enable = function() self:enable() end,
    disable = function() self:disable() end,
  }

  for action, binding in pairs(mapping) do
    if actions[action] then
      hs.hotkey.bind(binding.modifiers, binding.key, actions[action])
    end
  end

  return self
end

return obj
