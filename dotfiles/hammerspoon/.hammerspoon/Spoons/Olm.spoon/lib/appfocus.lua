--- === appfocus ===
---
--- Bringing an application forward, the two ways Olm does it. Focus or cycle reaches an app
--- by bundle id and walks its windows on a second press, and open by url lands an app on one
--- pane of itself through a url. Whether a press should hide the app instead is the caller's
--- decision, since only the caller knows which pane it last opened.
---
--- Core since phase three of the core split. Both behaviours used to live in the app toggler
--- plugin, and the launcher reached them as two siblings on that plugin, which meant a host in
--- core named a plugin and an app row did nothing at all on an install without the toggler.
--- Choosing an application is the launcher's own first job, so the behaviour belongs beside
--- the launcher rather than inside one plugin, and the toggler now asks for it through
--- needs.lib. Since phase 6 of the keymap plan the url form is System Settings' pane actions,
--- which ask for it the same way and decide themselves when a press hides the app, and the
--- launcher's app rows focus or cycle only.
---
--- One shared module with no instance, dot called, configured once by the composition root
--- with the dependency door's path resolver. The url form runs the launcher binary declared by
--- root/manifest.lua, since hs.urlevent.openURL refuses a pane scheme that carries a single
--- colon rather than a scheme separator. Every other path here runs through the accessibility
--- API and needs nothing from outside Hammerspoon.

local M = {}

local log = hs.logger.new("appfocus", "info")

-- The path resolver, the door's own path function, set by configure. Absent means the url
-- form cannot reach its binary and says so, while focus or cycle keeps working untouched.
local pathFor = nil

--- appfocus.configure(opts)
--- opts.path is a function answering the absolute path of a declared tool by name, the shared
--- door's own path. Called once by the composition root before any plugin is wired.
function M.configure(opts)
  opts = opts or {}
  pathFor = opts.path
  return M
end

--- appfocus.focusOrCycle(bundleID) -> outcome
--- Focus an app, or cycle through its windows if already frontmost. Never hides. First press
--- shows the last focused window, each subsequent press moves to the next window and wraps to
--- the first. Answers "launched", "focused", or "cycled", so a caller that also asked for
--- placement knows a cycle within an already frontmost app never counts as the outcome
--- placement fires on.
function M.focusOrCycle(bundleID)
  local app = hs.application.get(bundleID)

  -- Not running, so launch it.
  if not app then
    hs.application.launchOrFocusByBundleID(bundleID)
    return "launched"
  end

  -- Standard, non minimized windows in a deterministic order, so cycling is consistent, since
  -- the order allWindows answers is not stable on its own.
  local windows = {}
  for _, w in ipairs(app:allWindows()) do
    if w:isStandard() and not w:isMinimized() then
      table.insert(windows, w)
    end
  end
  table.sort(windows, function(a, b) return a:id() < b:id() end)

  -- No cyclable windows, so fall back to launch or focus.
  if #windows == 0 then
    hs.application.launchOrFocusByBundleID(bundleID)
    return "focused"
  end

  if app:isFrontmost() then
    -- Already focused, so move to the next window and wrap to the first.
    local focused = hs.window.focusedWindow()
    local index = nil
    if focused then
      for i, w in ipairs(windows) do
        if w:id() == focused:id() then
          index = i
          break
        end
      end
    end
    local nextIndex = index and (index % #windows) + 1 or 1
    windows[nextIndex]:focus()
    return "cycled"
  else
    -- Not focused, so bring the app forward with its last focused window.
    hs.application.launchOrFocusByBundleID(bundleID)
    return "focused"
  end
end

--- appfocus.openURL(bundleID, url) -> outcome
--- Land an app on a specific pane, launching it or navigating an already open window to that
--- pane, for apps like System Settings whose panes are reachable through a url scheme. It never
--- hides, a caller that wants a second press to hide decides that itself. Answers "focused" or
--- "launched", the same outcome words focus or cycle uses, for the same reason.
function M.openURL(bundleID, url)
  local app = hs.application.get(bundleID)
  local wasRunning = app ~= nil
  -- The launcher binary rather than hs.urlevent.openURL, because a pane url scheme such as
  -- x-apple.systempreferences carries a single colon and openURL rejects any url without a
  -- full scheme separator. Asked of the door by name rather than run as one, so an absent one
  -- says so instead of failing as an empty answer.
  local opener = pathFor and pathFor("open")
  if opener then
    hs.execute(opener .. " " .. ("%q"):format(url))
  else
    -- Said out loud rather than swallowed, because the failure is a key or a row that does
    -- nothing at all, and a toggle that silently declines is indistinguishable from a binding
    -- that never arrived.
    log.w("no open tool, so '" .. tostring(url) .. "' cannot be reached")
  end
  return wasRunning and "focused" or "launched"
end

return M
