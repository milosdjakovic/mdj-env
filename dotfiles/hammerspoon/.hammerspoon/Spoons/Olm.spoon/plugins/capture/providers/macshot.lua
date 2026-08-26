--- Capture provider, macshot.
---
--- Driven by macshot's `macshot://` URL scheme (enable it in macshot settings).
--- Triggering an action opens its URL. All macshot knowledge lives here, its
--- bundle id, its scheme, and its action -> URL map, so the Capture engine stays
--- ignorant of URLs. Add entries to `urls` as new actions are bound (see macshot
--- settings for the full command list).
---
--- Availability requires macshot to be installed, to own the macshot:// scheme,
--- AND to be running, so it steps aside for native on a machine without it, with
--- the scheme unregistered, or simply when macshot is closed. A URL fired at an
--- app that is not running would just relaunch it, which is not the fallback we
--- want. Each failure returns its own reason so the log says which one it was.
--- Whether it is installed comes from the injected dependency adapter, since that
--- is a declared dependency probed once for the whole config, while the scheme and
--- the running check stay live here because both change while Hammerspoon runs.
--- Honest limit, the scheme check sees Launch Services REGISTRATION only, so a
--- scheme switched off inside macshot may still read as available if macshot
--- leaves a statically declared handler in place.

return {
  name = "macshot",
  bundleID = "com.sw33tlie.macshot.macshot",
  scheme = "macshot",
  urls = {
    captureArea = "macshot://capture",
    captureAreaClipboard = "macshot://quick-capture",
    recordArea = "macshot://record",
  },

  -- Absolute path to open, handed over by available() and consumed by trigger(), the
  -- same seam macocr keeps for its own tool. open is what delivers the URL in the
  -- background, so an unresolved open belongs beside every other reason this provider
  -- declines rather than turning trigger into a second place that can fail.
  _resolvedOpen = nil,

  available = function(self, deps)
    if not deps then
      self._resolvedOpen = nil
      return false, "no dependency adapter injected"
    end
    if not deps.have(self.name) then
      self._resolvedOpen = nil
      return false, "not installed"
    end
    local handler = hs.urlevent.getDefaultHandler(self.scheme)
    if not handler then
      self._resolvedOpen = nil
      return false, self.scheme .. ":// URLs not available (enable the URL scheme in macshot settings)"
    end
    if handler:lower() ~= self.bundleID:lower() then
      self._resolvedOpen = nil
      return false, "the " .. self.scheme .. ":// scheme is handled by " .. handler .. ", not macshot"
    end
    if #hs.application.applicationsForBundleID(self.bundleID) == 0 then
      self._resolvedOpen = nil
      return false, "not running"
    end
    local openPath = deps.path("open")
    if not openPath then
      self._resolvedOpen = nil
      return false, "open is not resolved, so the url cannot be delivered in the background"
    end
    self._resolvedOpen = openPath
    return true
  end,
  supports = function(self, action)
    return self.urls[action] ~= nil
  end,
  trigger = function(self, action)
    local url = self.urls[action]
    if not url then
      return false
    end
    if not self._resolvedOpen then
      return false
    end
    -- Deliver the URL through `open` in the background instead of
    -- hs.urlevent.openURL, which foregrounds macshot. Foregrounding steals key
    -- focus from whatever is front, and an hs.chooser like the clipboard list
    -- dismisses itself the moment it loses focus. The `-g` flag hands macshot the
    -- URL without bringing it forward, matching how its own global hotkey fires.
    local t = hs.task.new(self._resolvedOpen, nil, { "-g", url })
    if not t then
      return false
    end
    t:start()
    return true
  end,
}
