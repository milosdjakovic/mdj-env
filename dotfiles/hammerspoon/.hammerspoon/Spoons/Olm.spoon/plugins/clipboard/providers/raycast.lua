--- ClipboardHistory provider: Raycast
---
--- Raycast's clipboard history. Raycast exposes a deeplink, so show() opens the
--- command URL directly rather than firing a shortcut. This needs no configured
--- hotkey and cannot be thrown off by a rebind. available() reports Raycast
--- missing or quit so the chain can fall back and log the reason.
---
--- show() also toggles: a second press hides Raycast completely (one hide(),
--- since Raycast's own Escape only steps back to root search and needs a second
--- press to close). The hide fires only when Raycast is frontmost and this
--- provider is the one that opened it, tracked by _shown. So pressing the key
--- while the clipboard is up dismisses it, while pressing it with Raycast not
--- visible just opens it. _shown is validated against the live frontmost app, so
--- a Raycast closed by other means (Escape, click away) is reopened rather than
--- a stale hide firing into the wrong app.
return {
  name = "Raycast",
  bundleID = "com.raycast.macos",
  url = "raycast://extensions/raycast/clipboard-history/clipboard-history",
  deferUntilHyperRelease = false, -- opens a URL / hides, neither is swallowed
  _shown = false,
  available = function(self)
    -- pathForBundleID answers an empty string rather than nil for an app it cannot
    -- place, so the absent case has to be tested for explicitly.
    local path = hs.application.pathForBundleID(self.bundleID)
    if path == nil or path == "" then
      return false, "not installed"
    end
    if not hs.application.get(self.bundleID) then
      return false, "not running"
    end
    return true
  end,
  show = function(self)
    local front = hs.application.frontmostApplication()
    local raycastFront = front ~= nil and front:bundleID() == self.bundleID
    if self._shown and raycastFront then
      local app = hs.application.get(self.bundleID)
      if app then
        app:hide()
      end
      self._shown = false
    else
      hs.urlevent.openURL(self.url)
      self._shown = true
    end
  end,
}
