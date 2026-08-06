--- === CheatSheet ===
---
--- Shared on-screen overlay of key bindings laid out as a row-major grid. Purely
--- presentational, it draws whatever model it is handed and owns nothing
--- domain-specific. This spoon owns only the grid layout math, it computes the
--- content size and positions every badge, label, icon, and title with absolute
--- coordinates, and the chip and text colours.
---
--- It does NOT draw its own panel. The surface (fill, border, corners, padding,
--- placement) is the shared CanvasPanel atom, the same one behind the docked
--- shortcut hint bar and the clipboard preview, so the overlay reads as the same
--- family. This spoon is a CanvasPanel content strategy: it exposes
--- preferredSize/draw, CanvasPanel owns everything around it. CanvasPanel owns the
--- surface look itself, so the composition root injects only the factory, not any
--- fill or border, and there is one panel look in one place.
---
--- The callers build the model and keep
--- their own domain logic: resolving app icons and splitting running vs not, or
--- humanizing action names. They differ only in content and a few layout knobs
--- (column count, badge width, whether rows carry icons), all model fields here,
--- so one renderer serves both.
---
--- Content styling is global, set once via configure(), typically from
--- config/settings.lua. configure(opts) accepts:
---   theme        - the chooser palette ({ dark = {...}, light = {...} }); the chip
---                  and text colours track light and dark from it, matching the
---                  hint bar
---   fontSize     - text size (px); lineHeight follows unless set explicitly
---   padding      - inner panel padding (px), passed to CanvasPanel as padX/padY
---   badgeRadius  - key-badge corner roundness (px)
---   canvasPanel  - the CanvasPanel factory (spoon.CanvasPanel) to draw through; it
---                  owns the surface, so no fill or border is passed here
---
--- show(model) where model is:
---   columns, colWidth, rowHeight, badgeWidth, badgeHeight, iconSize, gap,
---   titleHeight, groupGap           -- per-overlay layout, all optional
---   sections = {                    -- one or more; empty sections are skipped
---     { title = "OPEN", alpha = 1.0, rows = {
---         { badge = "C", label = "Google Chrome", icon = <hs.image?> }, ... } },
---   }
--- Rows are filled left-to-right, top-to-bottom across `columns`. An icon is
--- drawn only when iconSize > 0 and the row carries one. A section's `alpha`
--- fades its whole rows group, and an optional `titleAlpha` fades its title
--- independently (defaulting to `alpha`) so a dimmed group can keep a full-weight
--- header. A section may also override any layout field
--- (columns, colWidth, iconSize, ...) for its own rows, inheriting the model-level
--- value for anything it omits. The panel takes the widest section's width and
--- narrower sections left-align within it, so one panel can mix a four-column icon
--- grid with a two-column text list without clipping the longer labels.
---
--- This is the olm side copy of CheatSheet, moved into the core as lib/cheatsheet.lua in
--- phase five of the build plan. It is a faithful copy, the colon methods and the model
--- shape are unchanged, so assigning it to the CheatSheet spoon global is a drop in. The
--- original this was copied from still lives at Spoons/CheatSheet.spoon.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "CheatSheet"
obj.version = "4.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

obj._theme = nil          -- effective content styling (DEFAULT_THEME + configure)
obj._layoutDefaults = nil -- effective layout defaults (DEFAULTS + configure)
obj._panelCfg = nil       -- injected: { factory, padding }
obj._panel = nil          -- the one CanvasPanel instance, built lazily
obj._model = nil          -- the model of the overlay currently being drawn
obj._built = nil          -- cached { els, w, h } from the last preferredSize pass

-- Per-overlay layout defaults. Any can be overridden per show(). The inner panel
-- padding is CanvasPanel's, set globally via configure({ padding = ... }).
local DEFAULTS = {
  columns = 2,
  colWidth = 250,
  rowHeight = 44,
  badgeWidth = 44,   -- wide enough for two glyphs like "⇧←"
  badgeHeight = 28,
  iconSize = 0,      -- 0 = no icons
  gap = 12,          -- horizontal gap around badge/icon
  titleHeight = 32,  -- section header line + gap below it
  groupGap = 20,     -- vertical gap between sections
}

-- Content styling defaults. configure() clones and overrides these. Colours are
-- not here; they come from the chooser palette per light/dark at draw time, the
-- same source and treatment as the shortcut hint bar.
local DEFAULT_THEME = {
  fontSize = 16,
  lineHeight = 20,
  badge = { radius = 5 },
}

local FONT = ".AppleSystemUIFont"
local PANEL_PADDING = 20 -- CanvasPanel padX/padY unless configure sets padding

-- Key names -> display glyph, and sub-modifier names -> glyph prefixed onto it.
-- Turning a key plus its modifiers into a badge string is pure presentation, so
-- it lives here on the shared renderer rather than in each builder. Both callers
-- use it, one caller styles only its capture rows, the other every row.
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
  local sz = hs.drawing.getTextDrawingSize(tostring(text), { font = FONT, size = size })
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
-- Canvas content emission (elements only; CanvasPanel draws the surface)
--------------------------------------------------------------------------------

local function px(n) return math.floor(n + 0.5) end

-- A copy of a colour with its alpha scaled by `a`, so a section's group alpha
-- fades each element (canvas has no group opacity). Colours are either
-- { white, alpha } or { red, green, blue, alpha }; either shape is copied whole.
local function faded(color, a)
  if a >= 1 then return color end
  local c = shallow(color)
  c.alpha = (color.alpha or 1) * a
  return c
end

-- A filled, rounded rectangle element (the badge chip).
local function chipEl(x, y, w, h, color, radius)
  return { type = "rectangle", action = "fill", fillColor = color,
    roundedRectRadii = { xRadius = radius, yRadius = radius },
    frame = { x = px(x), y = px(y), w = px(w), h = px(h) } }
end

-- A text element. Canvas text is top-aligned in its frame, so callers pass a
-- frame already positioned to sit the glyphs where they want vertically.
local function textEl(text, x, y, w, h, size, color, align)
  return { type = "text", text = tostring(text), textFont = FONT, textSize = size,
    textColor = color, textAlignment = align or "left",
    frame = { x = px(x), y = px(y), w = px(w), h = px(h) } }
end

-- The chip and text colours for the current appearance, tracking light and dark
-- from the chooser palette exactly as the shortcut hint bar does.
local function palette(theme)
  local dark = hs.host.interfaceStyle() == "Dark"
  local side = (dark and theme.dark) or theme.light or theme.dark or {}
  return {
    fg = side.titleColor or { white = dark and 0.92 or 0.15 },       -- labels, badge glyphs
    meta = side.subColor or { white = dark and 0.55 or 0.42 },       -- section titles, separators
    badgeBg = { white = dark and 1 or 0, alpha = dark and 0.12 or 0.06 },
  }
end

-- One section's rows appended to `els`, positioned from contentY and filled
-- row-major across L.columns. `alpha` fades the whole group.
function obj:_rowsElements(els, rows, contentY, L, alpha, C)
  local sz = self._theme.fontSize
  local radius = self._theme.badge.radius
  local fg = faded(C.fg, alpha)
  local meta = faded(C.meta, alpha)
  local badgeBg = faded(C.badgeBg, alpha)

  -- For content-sized `badges` rows, align every label past the widest badge
  -- block in this section, so a short row and a two-box row still line up.
  local maxBlock = 0
  for _, r in ipairs(rows) do
    if r.badges then
      local _, total = badgeBoxes(r, sz, L.badgeHeight)
      if total > maxBlock then maxBlock = total end
    end
  end

  -- Badge glyph and label text, both sat vertically centred in their box.
  local function glyphEl(text, x, top, w)
    return textEl(text, x, top + (L.badgeHeight - sz) / 2 - 1, w, sz + 4, sz, fg, "center")
  end

  for i, r in ipairs(rows) do
    local col = (i - 1) % L.columns
    local row = math.floor((i - 1) / L.columns)
    local x = col * L.colWidth
    local y = contentY + row * L.rowHeight
    local badgeTop = y + (L.rowHeight - L.badgeHeight) / 2
    local labelX

    if r.badges then
      local boxes, _, sep, sepW = badgeBoxes(r, sz, L.badgeHeight)
      local bx = x
      for bi, b in ipairs(boxes) do
        els[#els + 1] = chipEl(bx, badgeTop, b.w, L.badgeHeight, badgeBg, radius)
        els[#els + 1] = glyphEl(b.text, bx, badgeTop, b.w)
        bx = bx + b.w
        if bi < #boxes then
          els[#els + 1] = textEl(sep, bx + SEP_GAP, badgeTop + (L.badgeHeight - sz) / 2 - 1,
            sepW, sz + 4, sz, meta, "center")
          bx = bx + SEP_GAP + sepW + SEP_GAP
        end
      end
      labelX = x + maxBlock + L.gap
    else
      els[#els + 1] = chipEl(x, badgeTop, L.badgeWidth, L.badgeHeight, badgeBg, radius)
      els[#els + 1] = glyphEl(r.badge, x, badgeTop, L.badgeWidth)
      labelX = x + L.badgeWidth + L.gap
    end

    if L.iconSize > 0 and r.icon then
      local iy = y + (L.rowHeight - L.iconSize) / 2
      els[#els + 1] = { type = "image", image = r.icon, imageScaling = "scaleProportionally",
        imageAlpha = alpha, frame = { x = px(labelX), y = px(iy), w = px(L.iconSize), h = px(L.iconSize) } }
      labelX = labelX + L.iconSize + L.gap
    end

    local labelW = L.colWidth - (labelX - x) - L.gap
    els[#els + 1] = textEl(r.label or "", labelX, y + (L.rowHeight - sz) / 2 - 1, labelW, sz + 4, sz, fg, "left")
  end
end

-- Compute the whole overlay: the content element list and its size, at origin
-- (0, 0). CanvasPanel offsets it by its padding and draws the surface behind it,
-- so there is no outer margin here. Cached in self._built so preferredSize and
-- the draw that follows it agree without recomputing.
function obj:_build()
  local model = self._model or {}
  local T = self._theme
  local L = layoutOf(self._layoutDefaults, model)
  local sections = nonEmpty(model.sections)
  if #sections == 0 then
    return { els = {}, w = 0, h = 0 }
  end

  -- Each section may override the panel layout (columns, colWidth, ...) for its
  -- own rows, inheriting the model-level L for anything it omits.
  local layouts = {}
  for i, s in ipairs(sections) do
    layouts[i] = layoutOf(L, s)
  end

  -- Width is the widest section's content; narrower sections left-align within
  -- it. Height sums each section's own rows, with groupGap between and titles
  -- included.
  local w = 0
  for i = 1, #sections do
    w = math.max(w, layouts[i].columns * layouts[i].colWidth)
  end
  local h = 0
  for i, s in ipairs(sections) do
    if i > 1 then h = h + L.groupGap end
    if s.title then h = h + layouts[i].titleHeight end
    h = h + rowsFor(#s.rows, layouts[i].columns) * layouts[i].rowHeight
  end

  local C = palette(T.palette or {})
  local els = {}
  local cursor = 0
  for i, s in ipairs(sections) do
    local SL = layouts[i]
    if i > 1 then cursor = cursor + L.groupGap end
    if s.title then
      els[#els + 1] = textEl(s.title, 0, cursor, SL.columns * SL.colWidth, T.lineHeight,
        T.fontSize, faded(C.meta, s.titleAlpha or s.alpha or 1.0), "left")
      cursor = cursor + SL.titleHeight
    end
    self:_rowsElements(els, s.rows, cursor, SL, s.alpha or 1.0, C)
    cursor = cursor + rowsFor(#s.rows, SL.columns) * SL.rowHeight
  end

  return { els = els, w = w, h = h }
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- CheatSheet:init()
function obj:init()
  self._theme = DEFAULT_THEME
  self._layoutDefaults = DEFAULTS
  return self
end

--- CheatSheet:configure(opts)
--- Content styling plus the injected CanvasPanel factory (see the header for the
--- full list). Any omitted field keeps its default, so configure(nil) is valid.
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
  t.palette = opts.theme or t.palette
  self._theme = t

  self._layoutDefaults = shallow(DEFAULTS)

  -- The panel factory, injected. CanvasPanel owns the surface look, so only the
  -- factory and the padding are held here. Rebuilt on the next show if it changed.
  self._panelCfg = {
    factory = opts.canvasPanel or (self._panelCfg and self._panelCfg.factory),
    padding = opts.padding or PANEL_PADDING,
  }
  self._panel = nil

  return self
end

-- Build the one CanvasPanel instance the first time it is needed, a centered
-- panel whose content is this spoon's live model. Returns nil when no factory was
-- injected, so show() is inert rather than erroring.
function obj:_ensurePanel()
  if self._panel then return self._panel end
  local cfg = self._panelCfg
  if not (cfg and cfg.factory) then return nil end
  self._panel = cfg.factory.new({
    placement = "center",
    padX = cfg.padding, padY = cfg.padding,
    content = {
      preferredSize = function()
        self._built = self:_build()
        return { w = self._built.w, h = self._built.h }
      end,
      draw = function()
        return (self._built or self:_build()).els
      end,
    },
  })
  return self._panel
end

--- CheatSheet:show(model)
--- Store the model and draw it through the shared panel, centered on screen.
function obj:show(model)
  self._model = model or {}
  self._built = nil
  local panel = self:_ensurePanel()
  if panel then panel:show() end
  return self
end

--- CheatSheet:hide()
--- Remove the overlay
function obj:hide()
  if self._panel then self._panel:hide() end
  return self
end

return obj
