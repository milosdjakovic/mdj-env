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

-- What a press on an app would do, read from the app as it stands and changing nothing. Answers
-- the outcome, "launched", "focused", "cycled" or "hidden", and for a cycle the window it reaches.
-- hides true is the show and hide form, a press on an app in front with a window hiding it, and
-- otherwise focus or cycle. One decision for acting and for the plan the app's shadow is handed,
-- docs/DESIGN-APP-APPS.md, so the two can never drift apart.
local function decide(bundleID, hides)
  local app = hs.application.get(bundleID)
  if not app then return "launched" end
  if hides then
    if app:isFrontmost() and #app:allWindows() > 0 then return "hidden", nil, app end
    return "focused", nil, app
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

  -- No cyclable windows, or not in front, so launch or focus brings it forward.
  if #windows == 0 or not app:isFrontmost() then return "focused", nil, app end

  -- Already in front, so move to the next window and wrap to the first. The window a cycle steps
  -- from is the app's own focused window, or its main window when the focused one is not a window
  -- the cycle walks, a popup or a sheet. Never the system's focused window, which at a press could
  -- answer none of the app's, so every press after the first landed on the first window again and
  -- Chrome swapped once and then stood still, 2026-11-23.
  local function indexOf(win)
    if not win then return nil end
    for i, w in ipairs(windows) do
      if w:id() == win:id() then return i end
    end
  end
  local index = indexOf(app:focusedWindow()) or indexOf(app:mainWindow())
  return "cycled", windows[index and (index % #windows) + 1 or 1], app
end

--- appfocus.plan(bundleID, hides) -> { outcome, window }
--- What a press would do, the window a cycle reaches by its id, changing nothing. Handed to the
--- app beside each press it runs, so its shadow compares its own decision with this one.
function M.plan(bundleID, hides)
  local outcome, window = decide(bundleID, hides)
  return { outcome = outcome, window = window and window:id() or nil }
end

-- Who runs a press in Olm.app, set by the root, step 6.2. Called with the press, { id, bundle,
-- hides, placement }, it answers true when the app took it and false when Lua runs it as before.
local forward = nil

--- appfocus.forwardTo(fn) sets the forwarder, nil taking it away, docs/DESIGN-APP-APPS.md.
function M.forwardTo(fn)
  forward = type(fn) == "function" and fn or nil
  return M
end

--- appfocus.toApp(press) -> whether Olm.app took the press, { id, bundle, hides, placement }, a
--- placement handed only as a table. A raise in the forwarder is a press Lua runs.
function M.toApp(press)
  if not forward or type(press) ~= "table" or type(press.bundle) ~= "string" then return false end
  local ok, took = pcall(forward, press)
  if not ok then log.w("the app did not take a press, " .. tostring(took)) end
  return ok and took == true
end

--- appfocus.focusOrCycle(bundleID, id) -> outcome
--- Focus an app, or cycle through its windows if already frontmost. Never hides. First press
--- shows the last focused window, each subsequent press moves to the next window and wraps to
--- the first. Answers "launched", "focused", or "cycled", so a caller that also asked for
--- placement knows a cycle within an already frontmost app never counts as the outcome
--- placement fires on, and "app" when Olm.app took the press, id naming who pressed for its
--- shadow, the launcher when none is handed. here true runs it in Lua whatever the forwarder says,
--- for a caller whose own part of the press, a placement written as a function, stays in Lua.
function M.focusOrCycle(bundleID, id, here)
  if not here and M.toApp({ id = id or "launcher", bundle = bundleID, hides = false }) then return "app" end
  local outcome, window = decide(bundleID, false)
  if outcome == "cycled" then
    window:focus()
  else
    hs.application.launchOrFocusByBundleID(bundleID)
  end
  return outcome
end

--- appfocus.toggle(bundleID) -> outcome
--- Show or hide, a press on an app in front with a window hiding it and any other launching or
--- focusing it. Answers "hidden", "launched" or "focused", the app toggler's `hides` form.
function M.toggle(bundleID)
  local outcome, _, app = decide(bundleID, true)
  if outcome == "hidden" then
    app:hide()
  else
    hs.application.launchOrFocusByBundleID(bundleID)
  end
  return outcome
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
