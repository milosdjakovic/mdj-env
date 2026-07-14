--- === CheatSheet ===
---
--- Shared on-screen overlay renderer: a rounded panel of key bindings laid out
--- as a row-major grid. Purely presentational -- it draws whatever model it is
--- handed and owns nothing domain-specific.
---
--- The two callers (HyperCheatSheet, WindowCheatSheet) build the model and keep
--- their own domain logic: resolving app icons and splitting running vs not, or
--- humanizing action names. They differ only in content and a few layout knobs
--- (column count, badge width, whether rows carry icons), all of which are model
--- fields here -- so one renderer serves both.
---
--- APPEARANCE (colour, opacity, corner radius, font, inner padding) is global:
--- set it once via configure() -- typically from config/settings.lua -- and both
--- overlays pick it up. LAYOUT that legitimately differs per overlay (columns,
--- badge width, icons) is passed per show(). configure(opts) accepts:
---   opacity      - panel background alpha (0-1)
---   background   - { red, green, blue } panel colour (0-1 each)
---   cornerRadius - panel corner roundness (px)
---   badgeRadius  - key-badge corner roundness (px)
---   badgeAlpha   - key-badge fill alpha (0-1)
---   fontSize     - text size (px); lineHeight follows unless set explicitly
---   padding      - inner margin around the content (px)
---
--- show(model) where model is:
---   columns, colWidth, rowHeight, badgeWidth, badgeHeight, iconSize, gap,
---   margin, titleHeight, groupGap  -- per-overlay layout, all optional
---   sections = {                    -- one or more; empty sections are skipped
---     { title = "OPEN", alpha = 1.0, rows = {
---         { badge = "C", label = "Google Chrome", icon = <hs.image?> }, ... } },
---   }
--- Rows are filled left-to-right, top-to-bottom across `columns`. An icon is
--- drawn only when iconSize > 0 and the row carries one. A section's `alpha`
--- multiplies the theme alphas, so the dimmed "not running" group fades whole.
--- A section may also override any layout field (columns, colWidth, iconSize,
--- ...) for its own rows, inheriting the model-level value for anything it omits.
--- The panel takes the widest section's width and narrower sections left-align
--- within it, so one panel can mix a four-column icon grid with a two-column
--- text list without clipping the longer labels.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "CheatSheet"
obj.version = "2.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

obj._canvas = nil
obj._theme = nil          -- effective appearance (DEFAULT_THEME + configure)
obj._layoutDefaults = nil -- effective layout defaults (DEFAULTS + configure)

-- Per-overlay layout defaults. Any can be overridden per show(); `margin` (the
-- inner padding) can also be set globally via configure({ padding = ... }).
local DEFAULTS = {
  columns = 2,
  colWidth = 250,
  rowHeight = 44,
  badgeWidth = 44,   -- wide enough for two glyphs like "⇧←"
  badgeHeight = 28,
  iconSize = 0,      -- 0 = no icons
  gap = 12,          -- horizontal gap around badge/icon
  margin = 28,       -- inner padding around content
  titleHeight = 32,  -- section header line + gap below it
  groupGap = 20,     -- vertical gap between sections
}

-- Global appearance defaults. configure() clones and overrides these; nothing
-- mutates this table, so it stays the pristine baseline.
local DEFAULT_THEME = {
  fontSize = 16,
  lineHeight = 20,
  -- panel.color carries its own alpha -- that alpha IS the modal's opacity.
  panel = { color = { red = 0.09, green = 0.09, blue = 0.11, alpha = 0.92 }, radius = 16 },
  badge = { alpha = 0.12, radius = 6 }, -- translucent key-badge fill
  text  = { badge = 1.0, label = 0.9, title = 0.5 }, -- white alphas per role
}

-- Key names -> display glyph, and sub-modifier names -> glyph prefixed onto it.
-- Turning a key plus its modifiers into a badge string is pure presentation, so
-- it lives here on the shared renderer rather than in each builder. Both callers
-- use it: HyperCheatSheet for its capture rows, WindowCheatSheet for every row.
-- Anything not mapped is uppercased (letters, =, and so on).
local KEY_GLYPH = {
  left = "←", right = "→", up = "↑", down = "↓",
  ["return"] = "↩", space = "␣", escape = "⎋", tab = "⇥", delete = "⌫",
}
local MOD_GLYPH = { shift = "⇧", ctrl = "⌃", alt = "⌥", cmd = "⌘" }

--- CheatSheet.glyphFor(key, mods) -> string
--- Render a binding as a badge glyph, so ("left", {"shift"}) becomes "⇧←". A
--- plain function with no state, called as CheatSheet.glyphFor(key, mods).
function obj.glyphFor(key, mods)
  local k = tostring(key):lower()
  local g = KEY_GLYPH[k] or tostring(key):upper()
  local prefix = ""
  for _, m in ipairs(mods or {}) do
    prefix = prefix .. (MOD_GLYPH[m] or "")
  end
  return prefix .. g
end

-- Vertical top for a lineH text box centered in a container of height h
local function centerY(top, h, lineH)
  return top + (h - lineH) / 2
end

local function rowsFor(n, columns)
  return math.ceil(n / columns)
end

-- Shallow copy of a table (one level)
local function shallow(t)
  local r = {}
  for k, v in pairs(t) do r[k] = v end
  return r
end

-- Merge a model's layout fields over the effective defaults
local function layoutOf(base, model)
  local l = {}
  for k, v in pairs(base) do
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

--- CheatSheet:init()
function obj:init()
  self._theme = DEFAULT_THEME
  self._layoutDefaults = DEFAULTS
  return self
end

--- CheatSheet:configure(opts)
--- Global appearance overrides applied to every overlay (see the header for the
--- full list). Any omitted field keeps its default, so configure(nil) is valid.
function obj:configure(opts)
  opts = opts or {}

  -- Clone the theme down to the tables we mutate, so DEFAULT_THEME stays clean.
  local t = shallow(DEFAULT_THEME)
  t.panel = shallow(DEFAULT_THEME.panel)
  t.panel.color = shallow(DEFAULT_THEME.panel.color)
  t.badge = shallow(DEFAULT_THEME.badge)
  t.text = shallow(DEFAULT_THEME.text)

  if opts.opacity ~= nil then t.panel.color.alpha = opts.opacity end
  if opts.background then
    if opts.background.red ~= nil then t.panel.color.red = opts.background.red end
    if opts.background.green ~= nil then t.panel.color.green = opts.background.green end
    if opts.background.blue ~= nil then t.panel.color.blue = opts.background.blue end
  end
  if opts.cornerRadius ~= nil then t.panel.radius = opts.cornerRadius end
  if opts.badgeRadius ~= nil then t.badge.radius = opts.badgeRadius end
  if opts.badgeAlpha ~= nil then t.badge.alpha = opts.badgeAlpha end
  if opts.fontSize ~= nil then
    t.fontSize = opts.fontSize
    -- Keep the line box proportional to the font unless caller pins it.
    t.lineHeight = opts.lineHeight or math.floor(opts.fontSize * 1.25 + 0.5)
  elseif opts.lineHeight ~= nil then
    t.lineHeight = opts.lineHeight
  end
  self._theme = t

  -- Padding is the one layout knob that reads globally (the inner margin).
  local l = shallow(DEFAULTS)
  if opts.padding ~= nil then l.margin = opts.padding end
  self._layoutDefaults = l

  return self
end

-- Push the elements for one section's rows starting at contentY
function obj:_appendRows(elements, rows, contentY, alpha, L)
  local T = self._theme
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
      fillColor = { white = 1.0, alpha = T.badge.alpha * alpha },
      roundedRectRadii = { xRadius = T.badge.radius, yRadius = T.badge.radius },
      frame = { x = x, y = badgeTop, w = L.badgeWidth, h = L.badgeHeight },
    }
    elements[#elements + 1] = {
      type = "text",
      text = r.badge,
      textColor = { white = 1.0, alpha = T.text.badge * alpha },
      textSize = T.fontSize,
      textAlignment = "center",
      frame = { x = x, y = centerY(badgeTop, L.badgeHeight, T.lineHeight), w = L.badgeWidth, h = T.lineHeight },
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
      textColor = { white = 1.0, alpha = T.text.label * alpha },
      textSize = T.fontSize,
      frame = { x = labelX, y = centerY(y, L.rowHeight, T.lineHeight), w = L.colWidth - (labelX - x) - L.gap, h = T.lineHeight },
    }
  end
end

--- CheatSheet:show(model)
--- Build and display the overlay for `model`
function obj:show(model)
  self:hide()
  model = model or {}
  local T = self._theme
  local L = layoutOf(self._layoutDefaults, model)
  local sections = nonEmpty(model.sections)
  if #sections == 0 then
    return self
  end

  -- Each section may override the panel layout (columns, colWidth, ...) for its
  -- own rows, inheriting the model-level L for anything it omits. Precompute the
  -- merged layout per section so width, height, and placement all agree.
  local layouts = {}
  for i, s in ipairs(sections) do
    layouts[i] = layoutOf(L, s)
  end

  -- Panel width is the widest section's content; narrower sections left-align
  -- within it. Height sums each section's own rows, with groupGap between and
  -- titles included.
  local contentW = 0
  for i = 1, #sections do
    contentW = math.max(contentW, layouts[i].columns * layouts[i].colWidth)
  end
  local w = contentW + L.margin * 2
  local h = L.margin
  for i, s in ipairs(sections) do
    if i > 1 then h = h + L.groupGap end
    if s.title then h = h + layouts[i].titleHeight end
    h = h + rowsFor(#s.rows, layouts[i].columns) * layouts[i].rowHeight
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
    fillColor = T.panel.color,
    roundedRectRadii = { xRadius = T.panel.radius, yRadius = T.panel.radius },
    frame = { x = 0, y = 0, w = w, h = h },
  }

  local cursor = L.margin
  for i, s in ipairs(sections) do
    local SL = layouts[i]
    if i > 1 then cursor = cursor + L.groupGap end
    if s.title then
      elements[#elements + 1] = {
        type = "text",
        text = s.title,
        textColor = { white = 1.0, alpha = T.text.title },
        textSize = T.fontSize,
        frame = { x = L.margin, y = cursor, w = SL.columns * SL.colWidth, h = T.lineHeight },
      }
      cursor = cursor + SL.titleHeight
    end
    self:_appendRows(elements, s.rows, cursor, s.alpha or 1.0, SL)
    cursor = cursor + rowsFor(#s.rows, SL.columns) * SL.rowHeight
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
