--- === MenuBarAutoHide ===
---
--- Control menu bar auto-hide setting
---

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "MenuBarAutoHide"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

--- MenuBarAutoHide:init()
--- Method
--- Initialize the spoon
function obj:init()
  return self
end

--- MenuBarAutoHide:isEnabled()
--- Method
--- Check if menu bar auto-hide is enabled
function obj:isEnabled()
  local output = hs.execute("defaults -currentHost read NSGlobalDomain _HIHideMenuBar 2>/dev/null")
  return output:match("1") ~= nil
end

--- MenuBarAutoHide:enable()
--- Method
--- Enable menu bar auto-hide (menu bar hides when not in use)
function obj:enable()
  hs.execute("defaults -currentHost write NSGlobalDomain _HIHideMenuBar -bool true")
  hs.execute([[osascript -e 'tell application "System Events" to tell dock preferences to set autohide menu bar to true']])
  return self
end

--- MenuBarAutoHide:disable()
--- Method
--- Disable menu bar auto-hide (menu bar always visible)
function obj:disable()
  hs.execute("defaults -currentHost write NSGlobalDomain _HIHideMenuBar -bool false")
  hs.execute([[osascript -e 'tell application "System Events" to tell dock preferences to set autohide menu bar to false']])
  return self
end

--- MenuBarAutoHide:toggle()
--- Method
--- Toggle menu bar auto-hide state
function obj:toggle()
  if self:isEnabled() then
    self:disable()
  else
    self:enable()
  end
  return self
end

--- MenuBarAutoHide:bindHotkeys(mapping)
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
