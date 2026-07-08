--- === HyperCheatSheet ===
---
--- On-screen overlay of the Hyper app-toggle bindings, split into apps that are
--- currently running and apps that are not. Meant to be triggered from
--- HyperKey.spoon's onHold hook. Reads the same appToggles/apps config that
--- AppToggler uses, so it never drifts from the real bindings.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "HyperCheatSheet"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

obj._apps = nil    -- name -> bundleID
obj._toggles = nil -- list of { app, key, modifiers }
obj._items = nil   -- precomputed { key, name, bundleID, icon }, built once
obj._canvas = nil

-- Layout constants
local COLS = 4
local COL_W = 190
local ROW_H = 40
local MARGIN = 24
local TITLE_H = 26
local GROUP_GAP = 16
local BADGE = 24
local ICON = 22

--- HyperCheatSheet:init()
function obj:init()
  return self
end

--- HyperCheatSheet:configure(opts)
--- opts.apps    - app name -> bundleID registry (config/apps.lua)
--- opts.toggles - appToggles list (config/keys.lua)
function obj:configure(opts)
  opts = opts or {}
  self._apps = opts.apps or {}
  self._toggles = opts.toggles or {}
  -- Resolve name + icon once (disk I/O), so show() stays instant. Only the
  -- running check happens per-show, which is cheap. Apps that are not installed
  -- (no bundle path) are dropped here so they never appear in the overlay.
  self._items = {}
  for _, t in ipairs(self._toggles) do
    local bundleID = self._apps[t.app]
    -- pathForBundleID returns "" (not nil) when the app is not installed, and
    -- "" is truthy in Lua -- so test for a non-empty path explicitly.
    local path = bundleID and hs.application.pathForBundleID(bundleID)
    if path and path ~= "" then
      self._items[#self._items + 1] = {
        key = tostring(t.key),
        name = hs.application.nameForBundleID(bundleID) or t.app,
        bundleID = bundleID,
        icon = hs.image.imageFromAppBundle(bundleID),
      }
    end
  end
  return self
end

-- Split precomputed items into running / not-running, preserving order.
-- Enumerate running apps once (a single NSWorkspace call) rather than calling
-- hs.application.get() per item -- the latter costs ~20ms each and dominated
-- the overlay's show latency.
function obj:_entries()
  local running = {}
  for _, app in ipairs(hs.application.runningApplications()) do
    local bid = app:bundleID()
    if bid then
      running[bid] = true
    end
  end

  local open, closed = {}, {}
  for _, item in ipairs(self._items or {}) do
    if running[item.bundleID] then
      table.insert(open, item)
    else
      table.insert(closed, item)
    end
  end
  return open, closed
end

local function rowsFor(n)
  return math.ceil(n / COLS)
end

-- Push the elements for one group's entries starting at contentY
function obj:_appendEntries(elements, entries, contentY, alpha)
  for i, e in ipairs(entries) do
    local col = (i - 1) % COLS
    local row = math.floor((i - 1) / COLS)
    local x = MARGIN + col * COL_W
    local y = contentY + row * ROW_H

    -- key badge
    elements[#elements + 1] = {
      type = "rectangle",
      action = "fill",
      fillColor = { white = 1.0, alpha = 0.12 * alpha },
      roundedRectRadii = { xRadius = 6, yRadius = 6 },
      frame = { x = x, y = y + (ROW_H - BADGE) / 2, w = BADGE, h = BADGE },
    }
    elements[#elements + 1] = {
      type = "text",
      text = e.key,
      textColor = { white = 1.0, alpha = alpha },
      textSize = 14,
      textAlignment = "center",
      frame = { x = x, y = y + (ROW_H - BADGE) / 2 + 3, w = BADGE, h = BADGE },
    }

    -- app icon (if resolvable)
    local iconX = x + BADGE + 8
    if e.icon then
      elements[#elements + 1] = {
        type = "image",
        image = e.icon,
        imageScaling = "scaleProportionally",
        imageAlpha = alpha,
        frame = { x = iconX, y = y + (ROW_H - ICON) / 2, w = ICON, h = ICON },
      }
    end

    -- app name
    local nameX = iconX + ICON + 8
    elements[#elements + 1] = {
      type = "text",
      text = e.name,
      textColor = { white = 1.0, alpha = 0.9 * alpha },
      textSize = 14,
      frame = { x = nameX, y = y + (ROW_H - 20) / 2, w = COL_W - (nameX - x) - 8, h = 20 },
    }
  end
end

local function sectionTitle(elements, text, y)
  elements[#elements + 1] = {
    type = "text",
    text = text,
    textColor = { white = 1.0, alpha = 0.5 },
    textSize = 11,
    frame = { x = MARGIN, y = y, w = COLS * COL_W, h = TITLE_H },
  }
end

--- HyperCheatSheet:show()
--- Build and display the overlay for the current running state
function obj:show()
  self:hide()

  local open, closed = self:_entries()
  if #open == 0 and #closed == 0 then
    return
  end

  -- Compute panel height
  local h = MARGIN
  if #open > 0 then
    h = h + TITLE_H + rowsFor(#open) * ROW_H
  end
  if #open > 0 and #closed > 0 then
    h = h + GROUP_GAP
  end
  if #closed > 0 then
    h = h + TITLE_H + rowsFor(#closed) * ROW_H
  end
  h = h + MARGIN

  local w = COLS * COL_W + MARGIN * 2
  local screen = hs.screen.mainScreen():frame()
  local x = screen.x + (screen.w - w) / 2
  local y = screen.y + (screen.h - h) / 2

  local elements = {}
  -- background panel
  elements[#elements + 1] = {
    type = "rectangle",
    action = "fill",
    fillColor = { red = 0.09, green = 0.09, blue = 0.11, alpha = 0.92 },
    roundedRectRadii = { xRadius = 16, yRadius = 16 },
    frame = { x = 0, y = 0, w = w, h = h },
  }

  local cursor = MARGIN
  if #open > 0 then
    sectionTitle(elements, "OPEN", cursor)
    self:_appendEntries(elements, open, cursor + TITLE_H, 1.0)
    cursor = cursor + TITLE_H + rowsFor(#open) * ROW_H + GROUP_GAP
  end
  if #closed > 0 then
    sectionTitle(elements, "NOT RUNNING", cursor)
    self:_appendEntries(elements, closed, cursor + TITLE_H, 0.55)
  end

  self._canvas = hs.canvas.new({ x = x, y = y, w = w, h = h })
  self._canvas:level(hs.canvas.windowLevels.overlay)
  self._canvas:appendElements(elements)
  self._canvas:show()
  return self
end

--- HyperCheatSheet:hide()
--- Remove the overlay
function obj:hide()
  if self._canvas then
    self._canvas:delete()
    self._canvas = nil
  end
  return self
end

return obj
