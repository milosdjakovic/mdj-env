--- === AppToggler ===
---
--- Smart application toggle (show/hide)
---

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "AppToggler"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- Configuration
obj._apps = nil

--- AppToggler:init()
--- Method
--- Initialize the spoon
function obj:init()
  return self
end

--- AppToggler:configure(opts)
--- Method
--- Configure the spoon
function obj:configure(opts)
  opts = opts or {}
  self._apps = opts.apps or {}
  return self
end

--- AppToggler:toggle(bundleID)
--- Method
--- Toggle an app (show if hidden/not frontmost, hide if frontmost)
function obj:toggle(bundleID)
  local app = hs.application.get(bundleID)

  if app and app:isFrontmost() and #app:allWindows() > 0 then
    app:hide()
  else
    hs.application.launchOrFocusByBundleID(bundleID)
  end
end

--- AppToggler:launchOrFocus(bundleID)
--- Method
--- Launch or focus an app (for workspace engine)
function obj:launchOrFocus(bundleID)
  hs.application.launchOrFocusByBundleID(bundleID)
end

--- AppToggler:bindHotkeys(toggles)
--- Method
--- Bind app toggle hotkeys from config
function obj:bindHotkeys(toggles)
  for _, toggle in ipairs(toggles) do
    local bundleID = self._apps[toggle.app]
    if bundleID then
      hs.hotkey.bind(toggle.modifiers, toggle.key, function()
        self:toggle(bundleID)
      end)
    else
      print("AppToggler: Unknown app '" .. toggle.app .. "' in config")
    end
  end
  return self
end

return obj
