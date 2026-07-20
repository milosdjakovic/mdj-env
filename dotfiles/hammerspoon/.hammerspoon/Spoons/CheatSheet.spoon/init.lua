--- === CheatSheet ===
---
--- Shared on-screen overlay renderer: a rounded panel of key bindings laid out
--- as a row-major grid. Purely presentational, it draws whatever model it is
--- handed and owns nothing domain-specific. This spoon owns the layout math, it
--- computes the panel size and positions every badge, label, icon, and title with
--- absolute coordinates.
---
--- The drawing primitive was a Surface webview grid, removed with the rest of the
--- web stack. Until a canvas renderer is wired back in, show() builds the model
--- and computes the geometry but has nothing to draw with, so it is inert (the
--- self._grid guard returns early). The layout math, the model contract, and the
--- two callers are left intact, so restoring the overlay is a matter of giving
--- this spoon a renderer, not rebuilding the callers.
---
--- The two callers (HyperCheatSheet, WindowCheatSheet) build the model and keep
--- their own domain logic: resolving app icons and splitting running vs not, or
--- humanizing action names. They differ only in content and a few layout knobs
--- (column count, badge width, whether rows carry icons), all of which are model
--- fields here, so one renderer serves both.
---
--- CONTENT styling (font size, inner padding, badge radius) is global: set it once
--- via configure(), typically from config/settings.lua. configure(opts) accepts:
---   theme        - the palette source ({ dark = {...}, light = {...} })
---   fontSize     - text size (px); lineHeight follows unless set explicitly
---   padding      - inner margin around the content (px)
---   badgeRadius  - key-badge corner roundness (px)
--- Legacy appearance keys (opacity, background, cornerRadius) are accepted and
--- ignored.
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
--- fades its whole rows group. A section may also override any layout field
--- (columns, colWidth, iconSize, ...) for its own rows, inheriting the model-level
--- value for anything it omits. The panel takes the widest section's width and
--- narrower sections left-align within it, so one panel can mix a four-column icon
--- grid with a two-column text list without clipping the longer labels.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "CheatSheet"
obj.version = "3.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

obj._grid = nil           -- the renderer this draws through; nil since the web grid was removed, so show() is inert
obj._theme = nil          -- effective content styling (DEFAULT_THEME + configure)
obj._layoutDefaults = nil -- effective layout defaults (DEFAULTS + configure)
obj._iconMemo = nil       -- hs.image -> data URI, so an icon is encoded once

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

-- Content styling defaults. configure() clones and overrides these; nothing
-- mutates this table, so it stays the pristine baseline. Colours are not here,
-- they come from the grid palette.
local DEFAULT_THEME = {
  fontSize = 16,
  lineHeight = 20,
  badge = { radius = 6 },
}

-- Key names -> display glyph, and sub-modifier names -> glyph prefixed onto it.
-- Turning a key plus its modifiers into a badge string is pure presentation, so
-- it lives here on the shared renderer rather than in each builder. Both callers
-- use it: HyperCheatSheet for its capture rows, WindowCheatSheet for every row.
-- Anything not mapped is uppercased (letters, =, and so on).
local KEY_GLYPH = {
  left = "←", right = "→", up = "↑", down = "↓",
  ["return"] = "↩", space = "␣", escape = "esc", tab = "⇥", delete = "⌫",
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

-- Content-sized badges. A row may carry `badges`, a list of key strings, instead
-- of a single `badge`. Each is drawn as its own box hugging its text, with a
-- separator between, so alternate keys read as distinct boxes rather than one
-- wide badge. This is opt-in: rows with a plain `badge` string keep the fixed
-- width path, so the other overlays are unchanged.
local BADGE_PAD_X = 10 -- horizontal padding inside a content-sized badge
local BADGE_SEP = "or" -- default word between a row's badges, overridable per row
local SEP_GAP = 8 -- gap on each side of the separator

-- Rendered width of text in the system UI font at `size`, so a box can hug its
-- key. Falls back to a rough estimate if the measurement is unavailable.
local function measureW(text, size)
  local sz = hs.drawing.getTextDrawingSize(tostring(text), { font = ".AppleSystemUIFont", size = size })
  return (sz and sz.w) or (#tostring(text) * size * 0.6)
end

-- Boxes for a `badges` row and the total block width, so labels can align past
-- the widest block. Each box is at least `minH` wide, so a lone glyph stays
-- square rather than a sliver.
local function badgeBoxes(r, size, minH)
  local boxes, total = {}, 0
  for _, b in ipairs(r.badges) do
    local w = math.max(minH, math.floor(measureW(b, size) + 2 * BADGE_PAD_X + 0.5))
    boxes[#boxes + 1] = { text = b, w = w }
    total = total + w
  end
  local sep = r.sep or BADGE_SEP
  local sepW = math.floor(measureW(sep, size) + 0.5)
  total = total + (#boxes - 1) * (SEP_GAP + sepW + SEP_GAP)
  return boxes, total, sep, sepW
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

--------------------------------------------------------------------------------
-- HTML emission
--------------------------------------------------------------------------------

local function px(n) return math.floor(n + 0.5) end

local function esc(s)
  return (tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- One absolutely positioned box. Flexbox in the grid CSS centres the content, so
-- a full row-height or badge-height box lines its text up vertically.
local function box(cls, x, y, w, h, inner)
  return string.format(
    '<div class="%s" style="left:%dpx;top:%dpx;width:%dpx;height:%dpx;">%s</div>',
    cls, px(x), px(y), px(w), px(h), inner)
end

-- The data URI for a row icon, encoded once and memoized by image identity, so
-- the app icons are not re-encoded on every overlay show.
function obj:_iconURI(image)
  if not image then return nil end
  self._iconMemo = self._iconMemo or {}
  local hit = self._iconMemo[image]
  if hit == nil then
    hit = image:encodeAsURLString() or false
    self._iconMemo[image] = hit
  end
  return hit or nil
end

-- The HTML for one section's rows, positioned from contentY, filled row-major
-- across L.columns. Mirrors the old canvas layout exactly, only emitting divs.
function obj:_rowsHtml(rows, contentY, L)
  local T = self._theme
  local parts = {}

  -- For content-sized `badges` rows, align every label past the widest badge
  -- block in this section, so a short row and a two-box row still line up.
  local maxBlock = 0
  for _, r in ipairs(rows) do
    if r.badges then
      local _, total = badgeBoxes(r, T.fontSize, L.badgeHeight)
      if total > maxBlock then maxBlock = total end
    end
  end

  for i, r in ipairs(rows) do
    local col = (i - 1) % L.columns
    local row = math.floor((i - 1) / L.columns)
    local x = L.margin + col * L.colWidth
    local y = contentY + row * L.rowHeight
    local badgeTop = y + (L.rowHeight - L.badgeHeight) / 2
    local labelX

    if r.badges then
      local boxes, _, sep, sepW = badgeBoxes(r, T.fontSize, L.badgeHeight)
      local bx = x
      for bi, b in ipairs(boxes) do
        parts[#parts + 1] = box("badge", bx, badgeTop, b.w, L.badgeHeight, esc(b.text))
        bx = bx + b.w
        if bi < #boxes then
          parts[#parts + 1] = box("sep", bx + SEP_GAP, badgeTop, sepW, L.badgeHeight, esc(sep))
          bx = bx + SEP_GAP + sepW + SEP_GAP
        end
      end
      labelX = x + maxBlock + L.gap
    else
      parts[#parts + 1] = box("badge", x, badgeTop, L.badgeWidth, L.badgeHeight, esc(r.badge))
      labelX = x + L.badgeWidth + L.gap
    end

    if L.iconSize > 0 and r.icon then
      local uri = self:_iconURI(r.icon)
      if uri then
        local iy = y + (L.rowHeight - L.iconSize) / 2
        parts[#parts + 1] = string.format(
          '<img class="ico" style="left:%dpx;top:%dpx;width:%dpx;height:%dpx;" src="%s">',
          px(labelX), px(iy), px(L.iconSize), px(L.iconSize), uri)
      end
      labelX = labelX + L.iconSize + L.gap
    end

    local labelW = L.colWidth - (labelX - x) - L.gap
    parts[#parts + 1] = box("label", labelX, y, labelW, L.rowHeight, esc(r.label or ""))
  end

  return table.concat(parts)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- CheatSheet:init()
function obj:init()
  self._theme = DEFAULT_THEME
  self._layoutDefaults = DEFAULTS
  self._iconMemo = {}
  return self
end

--- CheatSheet:configure(opts)
--- Content styling plus the injected grid (see the header for the full list). Any
--- omitted field keeps its default, so configure(nil) is valid.
function obj:configure(opts)
  opts = opts or {}

  local t = shallow(DEFAULT_THEME)
  t.badge = shallow(DEFAULT_THEME.badge)
  if opts.badgeRadius ~= nil then t.badge.radius = opts.badgeRadius end
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

  -- No renderer is wired: the Surface grid was removed with the web stack, so
  -- self._grid stays nil and show() is inert. The theme is kept for whatever
  -- canvas renderer replaces it. See the header.
  self._theme.palette = opts.theme or self._theme.palette

  return self
end

--- CheatSheet:show(model)
--- Compute the panel size, position every element, emit the HTML, and hand it to
--- the grid to draw.
function obj:show(model)
  self:hide()
  model = model or {}
  if not self._grid then return self end
  local T = self._theme
  local L = layoutOf(self._layoutDefaults, model)
  local sections = nonEmpty(model.sections)
  if #sections == 0 then
    return self
  end

  -- Each section may override the panel layout (columns, colWidth, ...) for its
  -- own rows, inheriting the model-level L for anything it omits.
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

  local parts = {}
  local cursor = L.margin
  for i, s in ipairs(sections) do
    local SL = layouts[i]
    if i > 1 then cursor = cursor + L.groupGap end
    if s.title then
      parts[#parts + 1] = box("title", L.margin, cursor, SL.columns * SL.colWidth, T.lineHeight, esc(s.title))
      cursor = cursor + SL.titleHeight
    end
    local rowsHtml = self:_rowsHtml(s.rows, cursor, SL)
    -- A section's alpha fades its whole rows group, the dimmed "not running" set.
    parts[#parts + 1] = string.format('<div class="sec" style="opacity:%s">%s</div>', s.alpha or 1.0, rowsHtml)
    cursor = cursor + rowsFor(#s.rows, SL.columns) * SL.rowHeight
  end

  self._grid:render({
    body = table.concat(parts),
    w = w,
    h = h,
    fontSize = T.fontSize,
    badgeRadius = T.badge.radius,
    -- A model may ask to stay passive, the peek shown over an open picker, so the
    -- overlay does not steal the picker's focus. A standalone sheet omits it and
    -- activates, holding its frosted backdrop.
    passive = model.passive,
  })
  return self
end

--- CheatSheet:hide()
--- Remove the overlay
function obj:hide()
  if self._grid then self._grid:hide() end
  return self
end

return obj
