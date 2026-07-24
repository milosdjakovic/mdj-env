--- === HyperCheatSheet ===
---
--- Content builder for the Hyper overlay: everything reachable while the Hyper
--- key is held. The app toggles come first, split into apps that are currently
--- running and apps that are not, followed by any static service sections
--- (the app bindings) passed in from the composition root. Meant to be
--- triggered by the onHold hook the root wires. Reads the same appToggles and apps
--- config the bindings use, so the app rows never drift.
---
--- This spoon owns only the domain logic -- resolving icons, filtering
--- uninstalled apps, the running/not-running split, and building the service
--- rows. Turning a key into a badge glyph and the actual drawing are both
--- delegated to the shared CheatSheet.spoon renderer (injected via configure).

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "HyperCheatSheet"
obj.version = "2.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

obj._apps = nil            -- name -> bundleID
obj._toggles = nil         -- list of { app, key, modifiers }
obj._items = nil           -- precomputed { key, name, bundleID, icon }, built once
obj._staticSections = nil  -- precomputed service sections { title, rows }, built once
obj._cheatSheet = nil      -- shared CheatSheet renderer

-- Layout knobs for this overlay: four columns, square badge, app icons.
local LAYOUT = {
  columns = 4,
  colWidth = 215,   -- wide enough for names like "Activity Monitor"
  rowHeight = 48,
  badgeWidth = 28,
  badgeHeight = 28,
  iconSize = 32,
  gap = 10,
  groupGap = 20,
}

-- Static (non-app) sections carry no icons, so they render without the app
-- grid's icon gutter. Four columns keep the four capture actions (OCR,
-- Screenshot, Screenshot copy, Record screen) on the first row, with the remaining
-- commands falling to the next. They reuse the app column width, freeing the
-- icon gutter as extra label room, so the columns keep the same tight rhythm as
-- the app rows instead of spreading across the whole panel.
local SERVICE_COLUMNS = 4
local SERVICE_COLWIDTH = LAYOUT.colWidth

--- HyperCheatSheet:init()
function obj:init()
  return self
end

--- HyperCheatSheet:configure(opts)
--- opts.apps       - app name -> bundleID registry (config/apps.lua)
--- opts.toggles    - appToggles list (config/keys.lua)
--- opts.cheatSheet - shared CheatSheet renderer to draw with
--- opts.sections   - optional list of static service sections appended after the
---                   app split, each { title, bindings }, where a binding is a
---                   { key, mods, action, description } table. The badge is
---                   rendered through the shared glyph helper and the label is
---                   the description (falling back to the action, then the key).
function obj:configure(opts)
  opts = opts or {}
  self._apps = opts.apps or {}
  self._toggles = opts.toggles or {}
  self._cheatSheet = opts.cheatSheet or self._cheatSheet
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
  -- Order by key: alphanumeric first (0-9, a-z), then non-alphanumeric symbols
  -- (`, /, ...) at the end. Case-insensitive. The running/not-running split
  -- below preserves this order, so each group ends up sorted the same way.
  local function rank(k)
    return k:match("^%w$") and 0 or 1 -- 0 = alphanumeric, 1 = symbol
  end
  table.sort(self._items, function(a, b)
    local ra, rb = rank(a.key), rank(b.key)
    if ra ~= rb then
      return ra < rb
    end
    return a.key:lower() < b.key:lower()
  end)
  -- Build the static service sections once. They carry no running state, so
  -- unlike the app split there is nothing to recompute per show. The badge is
  -- rendered through the shared glyph helper so Hyper+Shift+4 reads "⇧4".
  self._staticSections = {}
  for _, section in ipairs(opts.sections or {}) do
    local rows = {}
    for _, b in ipairs(section.bindings or {}) do
      local badge = self._cheatSheet and self._cheatSheet.glyphFor(b.key, b.mods) or tostring(b.key)
      rows[#rows + 1] = { badge = badge, label = b.description or b.action or tostring(b.key) }
    end
    self._staticSections[#self._staticSections + 1] = { title = section.title, rows = rows }
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

-- Turn precomputed items into CheatSheet rows
local function toRows(items)
  local rows = {}
  for _, e in ipairs(items) do
    rows[#rows + 1] = { badge = e.key, label = e.name, icon = e.icon }
  end
  return rows
end

--- HyperCheatSheet:show()
--- Build the running/not-running model, append the static service sections, and
--- hand the whole thing to the renderer. Empty sections are dropped by the
--- renderer, so a service group with no bindings simply does not appear.
function obj:show()
  if not self._cheatSheet then return self end
  local open, closed = self:_entries()
  local sections = {
    { title = "RUNNING", alpha = 1.0, rows = toRows(open) },
    { title = "DORMANT", alpha = 0.55, titleAlpha = 1.0, rows = toRows(closed) },
  }
  for _, s in ipairs(self._staticSections or {}) do
    sections[#sections + 1] = {
      title = s.title,
      alpha = 1.0,
      rows = s.rows,
      -- Override the panel layout for these rows: fewer, wider columns and no
      -- icon gutter, so long labels like "Screenshot to clipboard" are not cut.
      columns = SERVICE_COLUMNS,
      colWidth = SERVICE_COLWIDTH,
      iconSize = 0,
    }
  end
  self._cheatSheet:show({
    columns = LAYOUT.columns,
    colWidth = LAYOUT.colWidth,
    rowHeight = LAYOUT.rowHeight,
    badgeWidth = LAYOUT.badgeWidth,
    badgeHeight = LAYOUT.badgeHeight,
    iconSize = LAYOUT.iconSize,
    gap = LAYOUT.gap,
    groupGap = LAYOUT.groupGap,
    sections = sections,
  })
  return self
end

--- HyperCheatSheet:hide()
function obj:hide()
  if self._cheatSheet then self._cheatSheet:hide() end
  return self
end

return obj
