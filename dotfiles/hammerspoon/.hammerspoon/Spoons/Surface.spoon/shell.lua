--- The webview shell, the reusable surface engine.
---
--- One borderless, transparent, top level webview and the invariant scaffolding
--- around it, geometry, the message bridge, theme selection, focus and the
--- frosted backdrop, click away dismissal, and the previous window restore. It
--- knows nothing about lists, search, or previews. A concrete surface type
--- (list.lua) injects the page HTML, a message handler, and the geometry, and
--- reads back the active theme side.
---
--- Focus is the delicate part. The native chooser restored focus to the app
--- underneath for free, which is what let the clipboard paste land. A webview
--- holds key focus for its own search field, so the shell owns that restore, it
--- records the window that was frontmost on a fresh open and focuses it back on
--- close, exactly as Panel does, so a consumer that pastes can defer its action
--- past close and hit the right window.

local Shell = {}
Shell.__index = Shell

local FALLBACK_SIDE = {
  bgDark = true,
  preview = { bg = "#1e1e22", fg = "#dcdcdc", meta = "#8a8a8a", path = "#7a7a7a", note = "#c8a86a" },
  titleColor = { white = 0.92 },
  subColor = { white = 0.55 },
}

--------------------------------------------------------------------------------
-- Theme
--------------------------------------------------------------------------------

-- Point at the palette side matching the live appearance, reselected on each
-- show so the surface tracks the automatic light and dark switch. interfaceStyle
-- is "Dark" in dark mode and nil in light, and a missing light side falls back to
-- dark, then to the built in fallback so a themeless instance still renders.
function Shell:selectTheme()
  local p = self.config.theme or {}
  local dark = hs.host.interfaceStyle() == "Dark"
  self.side = (dark and p.dark) or p.light or p.dark or FALLBACK_SIDE
  return self.side
end

function Shell:activeSide()
  return self.side or FALLBACK_SIDE
end

--------------------------------------------------------------------------------
-- Geometry
--------------------------------------------------------------------------------

-- A frame centered horizontally and biased toward the top by topFrac, never
-- closer than minVPad to either screen edge, the same rule the old Chooser used.
-- The caller passes the pane width and height; the shell owns placement so every
-- surface type sits consistently.
function Shell:placeCentered(w, h, topFrac, minVPad)
  local f = hs.screen.mainScreen():frame()
  local floor, max, min = math.floor, math.max, math.min
  topFrac = topFrac or 0.06
  minVPad = minVPad or 60
  local lo = f.y + minVPad
  local hi = f.y + f.h - minVPad - h
  if hi < lo then hi = lo end
  local y = max(lo, min(f.y + floor(f.h * topFrac), hi))
  local x = f.x + floor((f.w - w) / 2)
  return { x = x, y = y, w = w, h = h }
end

function Shell:setFrame(frame)
  self.frame = frame
  if self.wv then self.wv:frame(frame) end
end

function Shell:currentFrame()
  return self.frame
end

--------------------------------------------------------------------------------
-- Page content
--------------------------------------------------------------------------------

function Shell:html(content)
  if self.wv then self.wv:html(content) end
end

-- Run JS in the page. Guarded so a call after teardown is a harmless no op.
function Shell:eval(js)
  if self.wv and self.active then self.wv:evaluateJavaScript(js) end
end

--------------------------------------------------------------------------------
-- Click away dismissal
--------------------------------------------------------------------------------

local function pointInFrame(p, fr)
  return fr and p.x >= fr.x and p.x <= fr.x + fr.w and p.y >= fr.y and p.y <= fr.y + fr.h
end

-- A single frame check, simpler than the old two rect chooser plus companion,
-- because the list and its preview now share one window. A click inside passes
-- through; a click outside dismisses.
function Shell:_startClickWatcher()
  if self.clickWatcher then self.clickWatcher:stop() end
  self.clickWatcher = hs.eventtap.new(
    { hs.eventtap.event.types.leftMouseDown, hs.eventtap.event.types.rightMouseDown },
    function(e)
      if not self.active then return false end
      if pointInFrame(e:location(), self.frame) then return false end
      self:hide()
      return false
    end)
  self.clickWatcher:start()
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

--- Shell:show(frame) - place at frame, reveal, take focus, and arm dismissal.
--- Records the frontmost window on a fresh open so hide can hand focus back. A
--- passive shell (a cheat sheet grid held under a modifier) skips all of that, it
--- never takes key focus, never records or restores a window, and arms no click
--- watcher, so it can float over an open picker without stealing its search field.
function Shell:show(frame)
  if not self.wv then return end
  if not self.active and not self.passive then
    self.prevWindow = hs.window.focusedWindow()
  end
  self.active = true
  self.frame = frame
  self.wv:frame(frame)
  self.wv:show()
  self.wv:bringToFront(true)
  if self.passive then
    if self.config.onShown then self.config.onShown() end
    return
  end
  hs.timer.doAfter(0.04, function()
    if not self.active then return end
    local win = self.wv:hswindow()
    if win then win:focus() end
    if self.config.onShown then self.config.onShown() end
  end)
  if self.config.clickAway ~= false then self:_startClickWatcher() end
end

--- Shell:setPassive(passive) - switch the window between activating and passive at
--- runtime, so one shell can host both a focused overlay that holds its frosted
--- backdrop and a passive peek that never steals focus. Passive is borderless and
--- nonactivating with text entry off; activating drops nonactivating and allows
--- text entry, so an in page field can hold focus and keep the backdrop alive.
function Shell:setPassive(passive)
  self.passive = passive and true or false
  if not self.wv then return end
  local masks = hs.webview.windowMasks.borderless
  if self.passive then masks = masks | hs.webview.windowMasks.nonactivating end
  self.wv:windowStyle(masks)
  self.wv:allowTextEntry(not self.passive)
end

--- Shell:hide() - hide the webview (kept warm), restore focus to the recorded
--- window, and fire onClose once. Idempotent. A passive shell has no focus to
--- restore and no click watcher to stop.
function Shell:hide()
  if not self.active then return end
  self.active = false
  if self.clickWatcher then self.clickWatcher:stop(); self.clickWatcher = nil end
  if self.wv then self.wv:hide() end
  if not self.passive then
    local prev = self.prevWindow
    self.prevWindow = nil
    if prev then prev:focus() end
  end
  if self.config.onClose then self.config.onClose() end
end

function Shell:isShowing()
  return self.active == true
end

--- Shell:previousWindow() - the window that had focus before this opened, for a
--- consumer that must act on it after close (the clipboard paste target).
function Shell:previousWindow()
  return self.prevWindow
end

--------------------------------------------------------------------------------
-- Factory
--------------------------------------------------------------------------------

--- Shell.new(config) -> shell. config: name (bridge id, unique per surface),
--- theme, onMessage(body), onShown, onClose, passive. Builds the webview once and
--- reuses it across shows, hiding rather than destroying so it stays warm like
--- Panel. A passive shell is a display only overlay, it takes no key focus and is
--- nonactivating, so text entry is off and no window is disturbed when it appears.
local function new(config)
  config = config or {}
  local passive = config.passive == true
  local self = setmetatable({
    config = config,
    bridge = config.name or "surface",
    active = false,
    passive = passive,
    frame = { x = 0, y = 0, w = 480, h = 400 },
  }, Shell)
  self:selectTheme()

  local ucc = hs.webview.usercontent.new(self.bridge)
  ucc:setCallback(function(msg)
    local body = (msg and msg.body) or {}
    if config.onMessage then config.onMessage(body) end
  end)

  local masks = hs.webview.windowMasks.borderless
  if passive then masks = masks | hs.webview.windowMasks.nonactivating end
  local wv = hs.webview.new(self.frame, {}, ucc)
  wv:windowStyle(masks)
  wv:level(hs.canvas.windowLevels.modalPanel)
  wv:transparent(true)
  wv:allowTextEntry(not passive)
  wv:allowNewWindows(false)
  wv:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  self.wv = wv
  self.ucc = ucc
  return self
end

return { new = new }
