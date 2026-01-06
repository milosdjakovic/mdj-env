--- === StageManager ===
---
--- macOS Stage Manager state tracking and toggle
---

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "StageManager"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- State
obj._active = false
obj._onToggleCallback = nil

--- StageManager:init()
--- Method
--- Initialize the spoon
---
--- Returns:
---  * The StageManager object
function obj:init()
  self._active = self:_readStatus()
  return self
end

--- StageManager:_readStatus()
--- Method
--- Read Stage Manager status from system defaults
---
--- Returns:
---  * true if Stage Manager is enabled, false otherwise
function obj:_readStatus()
  local output = hs.execute("defaults read com.apple.WindowManager GloballyEnabled 2>/dev/null")
  return (output:gsub("%s+", "") == "1")
end

--- StageManager:isActive()
--- Method
--- Check if Stage Manager is currently active
---
--- Returns:
---  * true if active, false otherwise
function obj:isActive()
  return self._active
end

--- StageManager:refresh()
--- Method
--- Refresh Stage Manager status from system
---
--- Returns:
---  * The StageManager object
function obj:refresh()
  self._active = self:_readStatus()
  if self._onToggleCallback then
    self._onToggleCallback(self._active)
  end
  return self
end

--- StageManager:setCallback(callback)
--- Method
--- Set callback to be called when Stage Manager status changes
---
--- Parameters:
---  * callback - Function to call with new status (boolean)
---
--- Returns:
---  * The StageManager object
function obj:setCallback(callback)
  self._onToggleCallback = callback
  return self
end

--- StageManager:bindHotkeys(mapping)
--- Method
--- Bind hotkeys for Stage Manager
---
--- Parameters:
---  * mapping - Table with 'toggle' key containing {modifiers, key}
---
--- Returns:
---  * The StageManager object
function obj:bindHotkeys(mapping)
  if mapping.toggle then
    hs.hotkey.bind(mapping.toggle.modifiers, mapping.toggle.key, function()
      self:refresh()
    end)
  end
  return self
end

return obj
