--- === Emoji.macos backend ===
---
--- The macOS Character Viewer as an emoji backend. show triggers it with the system Ctrl
--- Cmd Space shortcut, which opens the panel at the cursor and inserts the chosen glyph
--- straight into the focused field, so this backend needs no dataset, no icons, and no
--- onInsert. It is a system panel we do not drive, so isShowing is always false and its
--- surface is a no op, which keeps it out of the shared navigation registry where our own
--- j k i keys would fight the panel.

local obj = {}
obj.__index = obj

-- The backend name, used by the facade when it logs which backend it selected.
obj.name = "macos"

-- A navigation surface that reports itself closed and does nothing, so the facade can
-- register it in the shared choosers list without our keys ever routing to the panel.
local NOOP_SURFACE = {
  isShowing = function() return false end,
  selectNext = function() end,
  selectPrev = function() end,
  insertSelected = function() end,
  hide = function() end,
}

--- Emoji.macos:isAvailable()
--- Method
--- Always available. The Character Viewer ships with every macOS, so the panel exists.
--- Note this reports that the panel exists, not that the Ctrl Cmd Space shortcut is still
--- bound, since a user can remap it in System Settings and we cannot detect that.
function obj:isAvailable()
  return true
end

--- Emoji.macos:configure(opts)
--- Method
--- Nothing to wire, the panel inserts into the focused field itself. Kept so this backend
--- honors the same contract as the others and the facade configures every backend the
--- same way.
function obj:configure(_)
  return self
end

--- Emoji.macos:show()
--- Method
--- Open the Character Viewer with its system shortcut. The post is deferred a moment so the
--- Hyper chord that opened us has lifted, otherwise a modifier still held would merge into
--- the posted combo and the system would not read it as Ctrl Cmd Space. keyStroke posts to
--- the frontmost app, which is the field the user was in before Hyper, so the panel opens
--- against it.
---
--- The timer is held in a field, since a Hammerspoon timer is userdata whose finalizer
--- stops it and one nothing refers to can be collected before it fires, which would leave
--- the shortcut unposted and the panel simply never opening. A second show inside that
--- moment replaces the first, because posting the same shortcut twice would toggle the
--- panel back shut.
function obj:show()
  if self._showTimer then self._showTimer:stop() end
  self._showTimer = hs.timer.doAfter(0.05, function()
    hs.eventtap.keyStroke({ "ctrl", "cmd" }, "space", 0)
  end)
end

--- Emoji.macos:isShowing()
--- Method
--- Always false. The panel is a system window we do not own or track, and reporting false
--- keeps it out of the navigation registry.
function obj:isShowing()
  return false
end

--- Emoji.macos:surface()
--- Method
--- The no op navigation adapter, so the facade can register this backend uniformly.
function obj:surface()
  return NOOP_SURFACE
end

return obj
