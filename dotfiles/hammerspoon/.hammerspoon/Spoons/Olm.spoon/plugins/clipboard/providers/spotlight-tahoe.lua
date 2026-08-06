--- ClipboardHistory provider: Spotlight (Tahoe)
---
--- The clipboard history built into Spotlight in macOS 26 (Tahoe). There is no
--- dedicated system shortcut for it, so show() opens Spotlight (Cmd+Space) then
--- selects its Clipboard category (Cmd+4), skipping the open step when Spotlight
--- is already showing (pressing Cmd+Space again would close it). Spotlight's
--- process always runs but only owns a window while the panel is visible, which
--- is how isShowing() detects it. It omits available(), so it is always
--- available and belongs last in the chain, the guaranteed fallback.
-- The pending category keystroke, held until it fires. A Hammerspoon timer is userdata
-- whose finalizer stops it, so one nothing refers to can be collected inside the wait, and
-- Spotlight would then open on its own default tab rather than the clipboard, which looks
-- like the shortcut changed. A second open inside that window replaces the first, since the
-- panel is already coming up and one Cmd+4 is all it needs.
local categoryKey = nil

return {
  deferUntilHyperRelease = true, -- sends Cmd+Space / Cmd+4, swallowed while held
  isShowing = function()
    local sp = hs.application.get("com.apple.Spotlight")
    return sp ~= nil and #sp:allWindows() > 0
  end,
  show = function(self)
    if self:isShowing() then
      hs.eventtap.keyStroke({ "cmd" }, "4", 0)
    else
      hs.eventtap.keyStroke({ "cmd" }, "space", 0)
      if categoryKey then categoryKey:stop() end
      categoryKey = hs.timer.doAfter(0.12, function()
        hs.eventtap.keyStroke({ "cmd" }, "4", 0)
      end)
    end
  end,
}
