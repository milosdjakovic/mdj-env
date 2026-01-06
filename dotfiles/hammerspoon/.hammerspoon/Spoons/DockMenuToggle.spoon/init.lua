--- === DockMenuToggle ===
---
--- Toggle dock and menu bar auto-hide together
---

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "DockMenuToggle"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

--- DockMenuToggle:init()
--- Method
--- Initialize the spoon
---
--- Returns:
---  * The DockMenuToggle object
function obj:init()
  return self
end

--- DockMenuToggle:_readSetting(domain, key)
--- Method
--- Read a setting from system defaults
function obj:_readSetting(domain, key)
  return hs.execute("defaults -currentHost read " .. domain .. " " .. key .. " 2>/dev/null")
end

--- DockMenuToggle:_writeSetting(domain, key, value)
--- Method
--- Write a setting to system defaults
function obj:_writeSetting(domain, key, value)
  hs.execute("defaults -currentHost write " .. domain .. " " .. key .. " -int " .. value)
end

--- DockMenuToggle:_toggleDock(newState)
--- Method
--- Toggle dock auto-hide
function obj:_toggleDock(newState)
  self:_writeSetting("com.apple.dock", "autohide", newState)
  hs.execute([[osascript -e 'tell application "System Events" to tell dock preferences to set autohide to ]] ..
    (newState == "1" and "true" or "false") .. "'")
end

--- DockMenuToggle:_toggleMenuBar(newState)
--- Method
--- Toggle menu bar auto-hide
function obj:_toggleMenuBar(newState)
  self:_writeSetting("NSGlobalDomain", "_HIHideMenuBar", newState)
  hs.execute([[osascript -e 'tell application "System Events" to tell dock preferences to set autohide menu bar to ]] ..
    (newState == "1" and "true" or "false") .. "'")
end

--- DockMenuToggle:toggle()
--- Method
--- Toggle both dock and menu bar auto-hide
function obj:toggle()
  local currentState = self:_readSetting("com.apple.dock", "autohide")
  local newState = currentState:match("1") and "0" or "1"

  self:_toggleDock(newState)
  self:_toggleMenuBar(newState)
end

--- DockMenuToggle:bindHotkeys(mapping)
--- Method
--- Bind hotkeys for DockMenuToggle
---
--- Parameters:
---  * mapping - Table with 'toggle' key containing {modifiers, key}
---
--- Returns:
---  * The DockMenuToggle object
function obj:bindHotkeys(mapping)
  if mapping.toggle then
    hs.hotkey.bind(mapping.toggle.modifiers, mapping.toggle.key, function()
      self:toggle()
    end)
  end
  return self
end

return obj
