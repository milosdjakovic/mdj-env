--- === ClipboardHistory ===
---
--- Open the macOS Tahoe clipboard history.
---
--- Tahoe's clipboard history lives inside Spotlight, with no dedicated system
--- shortcut. This opens Spotlight (Cmd+Space) then presses Cmd+4 to select its
--- Clipboard category.
---
--- When a HyperKey spoon is provided, the action binds into its modal and waits
--- for the Hyper key to be released before posting: HyperKey's event tap
--- swallows every key while held, which would otherwise eat these synthetic
--- keystrokes.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "ClipboardHistory"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- Configuration
obj._hyperKey = nil

--- ClipboardHistory:init()
--- Method
--- Initialize the spoon
function obj:init()
  return self
end

--- ClipboardHistory:configure(opts)
--- Method
--- opts.hyperKey - optional HyperKey spoon; when present the open action binds
---                 into its modal and defers keystrokes until the Hyper key is
---                 released
function obj:configure(opts)
  opts = opts or {}
  self._hyperKey = opts.hyperKey
  return self
end

--- ClipboardHistory:open()
--- Method
--- Open Spotlight and select its Clipboard category
function obj:open()
  local function fire()
    hs.eventtap.keyStroke({ "cmd" }, "space", 0)
    hs.timer.doAfter(0.12, function()
      hs.eventtap.keyStroke({ "cmd" }, "4", 0)
    end)
  end

  if self._hyperKey and self._hyperKey:isActive() then
    -- Wait for release so HyperKey's tap stops swallowing synthetic keystrokes
    hs.timer.waitUntil(function()
      return not self._hyperKey:isActive()
    end, fire, 0.02)
  else
    fire()
  end
end

--- ClipboardHistory:bindHotkeys(mapping)
--- Method
--- mapping.open - { modifiers = ..., key = ... }. Binds into the Hyper key when
---                one is wired, otherwise the literal modifier combo.
function obj:bindHotkeys(mapping)
  local binding = mapping and mapping.open
  if not binding then
    return self
  end
  local action = function()
    self:open()
  end
  if self._hyperKey then
    self._hyperKey:bind(binding.key, action)
  else
    hs.hotkey.bind(binding.modifiers, binding.key, action)
  end
  return self
end

return obj
