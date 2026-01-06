--- === StageManager ===
---
--- macOS Stage Manager state detection
---

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "StageManager"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

--- StageManager:init()
--- Method
--- Initialize the spoon
---
--- Returns:
---  * The StageManager object
function obj:init()
  return self
end

--- StageManager:isActive()
--- Method
--- Check if Stage Manager is currently active (reads fresh from system)
---
--- Returns:
---  * true if active, false otherwise
function obj:isActive()
  local output = hs.execute("defaults read com.apple.WindowManager GloballyEnabled 2>/dev/null")
  return (output:gsub("%s+", "") == "1")
end

return obj
