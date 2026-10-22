-- Takes keyboard focus for a list opened over a password field, and gives it back.
--
-- Why this exists. The default chooser is a canvas that never takes focus and reads keys
-- through an event tap. While a password field has focus macOS secure input hides every key
-- from every tap, so a list opened then is drawn but deaf. Measured live on 2026-10-22 over a
-- Safari password field. hs.focus() did nothing and Safari kept focus. A borderless hs.webview
-- with text entry allowed, focused through hs.window focus, could not take focus either. A native
-- hs.chooser is a real window that becomes key, it took focus, secure input went off within a
-- tenth of a second, and hiding it then activating the previous application returned both the
-- focus and secure input. So a native chooser is the only mechanism proven, and this file is
-- the one place that knows it. Nothing else in the spoon names hs.chooser for this purpose.
--
-- The chooser shows with no rows and is moved off screen at once, so nothing of it is seen
-- beyond a brief flash before the move. It exists only to be the key window.
--
-- The security trade off, stated plainly. While a list is open over a password field secure
-- input is off, so any event tap on the machine could read what is typed into that list. That
-- is the price of a list that hears keys there. It lasts only while the list is open, and the
-- release function puts secure input back by returning focus to the password field.
--
-- hold() answers nil when secure input is off, so every ordinary open is untouched. When it is
-- on, hold() answers a release function, safe to call more than once.

local M = {}

-- Far enough above every display that the window is never on any of them.
local OFF_SCREEN_Y = -10000

function M.hold()
  if not hs.eventtap.isSecureInputEnabled() then return nil end

  local previous = hs.application.frontmostApplication()
  local picker = hs.chooser.new(function() end)
  picker:choices({})
  picker:rows(0)
  picker:show()

  -- The chooser's window is the focused one only once it is key, and only then is it ours.
  local window = hs.window.focusedWindow()
  local owner = window and window:application()
  if window and owner and owner:name() == "Hammerspoon" then
    local f = window:frame()
    window:setFrame({ x = f.x, y = OFF_SCREEN_Y, w = f.w, h = f.h }, 0)
  end

  local released = false
  return function()
    if released then return end
    released = true
    picker:hide()
    picker:delete()
    if previous then previous:activate() end
  end
end

return M
