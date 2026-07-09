--- === CheatSheet ===
---
--- Shared on-screen overlay renderer: a dark rounded panel of key bindings laid
--- out as a row-major grid. Purely presentational -- it draws whatever model it
--- is handed and owns nothing domain-specific.
---
--- The two callers (HyperCheatSheet, WindowCheatSheet) build the model and keep
--- their own domain logic: resolving app icons and splitting running vs not, or
--- humanizing action names. They differ only in content and a few layout knobs
--- (column count, badge width, whether rows carry icons), all of which are model
--- fields here -- so one renderer serves both.
---
--- show(model) where model is:
---   columns, colWidth, rowHeight, badgeWidth, badgeHeight, iconSize, gap,
---   margin, titleHeight, groupGap  -- layout, all optional (defaults below)
---   sections = {                    -- one or more; empty sections are skipped
---     { title = "OPEN", alpha = 1.0, rows = {
---         { badge = "C", label = "Google Chrome", icon = <hs.image?> }, ... } },
---   }
--- Rows are filled left-to-right, top-to-bottom across `columns`. An icon is
--- drawn only when iconSize > 0 and the row carries one. `alpha` fades a whole
--- section (used for the dimmed "not running" group).

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "CheatSheet"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

obj._canvas = nil

-- Layout defaults (tuned for 16px text). Any can be overridden per show().
local DEFAULTS = {
  columns = 2,
  colWidth = 250,
  rowHeight = 44,
  badgeWidth = 44,   -- wide enough for two glyphs like "⇧←"
  badgeHeight = 28,
  iconSize = 0,      -- 0 = no icons
  gap = 12,          -- horizontal gap around badge/icon
  margin = 28,
  titleHeight = 32,  -- section header line + gap below it
  groupGap = 20,     -- vertical gap between sections
}

local TEXT = 16   -- font size for every text element
local LINE_H = 20 -- line box used to vertically center TEXT

-- Vertical top for a LINE_H text box centered in a container of height h
local function centerY(top, h)
  return top + (h - LINE_H) / 2
end

local function rowsFor(n, columns)
  return math.ceil(n / columns)
end

--- CheatSheet:init()
function obj:init()
  return self
end

-- Merge a model's layout fields over DEFAULTS
local function layoutOf(model)
  local l = {}
  for k, v in pairs(DEFAULTS) do
    l[k] = model[k] ~= nil and model[k] or v
  end
  return l
end

-- Sections that actually have rows (empty ones are skipped entirely)
local function nonEmpty(sections)
  local out = {}
  for _, s in ipairs(sections or {}) do
    if s.rows and #s.rows > 0 then
      out[#out + 1] = s
    end
  end
  return out
end

-- Push the elements for one section's rows starting at contentY
function obj:_appendRows(elements, rows, contentY, alpha, L)
  for i, r in ipairs(rows) do
    local col = (i - 1) % L.columns
    local row = math.floor((i - 1) / L.columns)
    local x = L.margin + col * L.colWidth
    local y = contentY + row * L.rowHeight
    local badgeTop = y + (L.rowHeight - L.badgeHeight) / 2

    -- key glyph badge
    elements[#elements + 1] = {
      type = "rectangle",
      action = "fill",
      fillColor = { white = 1.0, alpha = 0.12 * alpha },
      roundedRectRadii = { xRadius = 6, yRadius = 6 },
      frame = { x = x, y = badgeTop, w = L.badgeWidth, h = L.badgeHeight },
    }
    elements[#elements + 1] = {
      type = "text",
      text = r.badge,
      textColor = { white = 1.0, alpha = alpha },
      textSize = TEXT,
      textAlignment = "center",
      frame = { x = x, y = centerY(badgeTop, L.badgeHeight), w = L.badgeWidth, h = LINE_H },
    }

    -- optional icon
    local labelX = x + L.badgeWidth + L.gap
    if L.iconSize > 0 and r.icon then
      elements[#elements + 1] = {
        type = "image",
        image = r.icon,
        imageScaling = "scaleProportionally",
        imageAlpha = alpha,
        frame = { x = labelX, y = y + (L.rowHeight - L.iconSize) / 2, w = L.iconSize, h = L.iconSize },
      }
      labelX = labelX + L.iconSize + L.gap
    end

    -- label
    elements[#elements + 1] = {
      type = "text",
      text = r.label,
      textColor = { white = 1.0, alpha = 0.9 * alpha },
      textSize = TEXT,
      frame = { x = labelX, y = centerY(y, L.rowHeight), w = L.colWidth - (labelX - x) - L.gap, h = LINE_H },
    }
  end
end

--- CheatSheet:show(model)
--- Build and display the overlay for `model`
function obj:show(model)
  self:hide()
  model = model or {}
  local L = layoutOf(model)
  local sections = nonEmpty(model.sections)
  if #sections == 0 then
    return self
  end

  -- Panel size: sum section heights, with groupGap between and titles included.
  local w = L.columns * L.colWidth + L.margin * 2
  local h = L.margin
  for i, s in ipairs(sections) do
    if i > 1 then h = h + L.groupGap end
    if s.title then h = h + L.titleHeight end
    h = h + rowsFor(#s.rows, L.columns) * L.rowHeight
  end
  h = h + L.margin

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

  local cursor = L.margin
  for i, s in ipairs(sections) do
    if i > 1 then cursor = cursor + L.groupGap end
    if s.title then
      elements[#elements + 1] = {
        type = "text",
        text = s.title,
        textColor = { white = 1.0, alpha = 0.5 },
        textSize = TEXT,
        frame = { x = L.margin, y = cursor, w = L.columns * L.colWidth, h = LINE_H },
      }
      cursor = cursor + L.titleHeight
    end
    self:_appendRows(elements, s.rows, cursor, s.alpha or 1.0, L)
    cursor = cursor + rowsFor(#s.rows, L.columns) * L.rowHeight
  end

  self._canvas = hs.canvas.new({ x = x, y = y, w = w, h = h })
  self._canvas:level(hs.canvas.windowLevels.overlay)
  self._canvas:appendElements(elements)
  self._canvas:show()
  return self
end

--- CheatSheet:hide()
--- Remove the overlay
function obj:hide()
  if self._canvas then
    self._canvas:delete()
    self._canvas = nil
  end
  return self
end

return obj
