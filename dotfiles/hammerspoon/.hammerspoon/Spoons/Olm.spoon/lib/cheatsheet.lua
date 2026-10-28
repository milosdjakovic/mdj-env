--- === CheatSheet ===
---
--- Shared on-screen overlay of key bindings laid out as a row-major grid. Purely
--- presentational, it draws whatever model it is handed and owns nothing
--- domain-specific. This spoon owns only the grid layout math, it computes the
--- content size and positions every badge, label, icon, and title with absolute
--- coordinates, and the chip and text colours.
---
--- It does NOT draw its own panel. The surface (fill, border, corners, padding,
--- placement) is the shared CanvasPanel atom, the same one behind the toasts
--- and the clipboard preview, so the overlay reads as the same
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
--- Content styling comes from the UI kit. Every badge, separator, icon, label and
--- title is a kit node laid out where this file's grid arithmetic puts it. The row label
--- and the key badge glyph are the body role, the separator word between alternate keys is
--- caption, and a section title is the section role in its own colour, so the type, the
--- chip and the text colours track light and dark through the kit's tokens, matching the
--- action bar under every list. The badge radius is the kit's nested radius, the surface's corner less the panel
--- padding, and there is no font size setting, since the roles carry the sizes.
---
--- The three heights are derived, never literal. The key badge is a body line with the small
--- space above and below, a row is a badge with the medium space added, and a title is a
--- section line with the medium space below it. A host may still pass rowHeight,
--- badgeHeight or titleHeight in a model, or in one section, and that wins.
--- configure(opts) accepts:
---   ui           - the UI kit, lib/ui, everything here is drawn through it
---   padding      - inner panel padding (px), passed to CanvasPanel as padX/padY
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
--- original this was copied from lived at Spoons/CheatSheet.spoon.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "CheatSheet"
obj.version = "4.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

obj._ui = nil             -- injected: the UI kit every element is drawn through
obj._layoutDefaults = nil -- effective layout defaults (DEFAULTS + configure)
obj._panelCfg = nil       -- injected: { factory, padding }
obj._panel = nil          -- the one CanvasPanel instance, built lazily
obj._model = nil          -- the model of the overlay currently being drawn
obj._built = nil          -- cached { els, w, h } from the last preferredSize pass

-- Per-overlay layout defaults. Any can be overridden per show(). The inner panel
-- padding is CanvasPanel's, set globally via configure({ padding = ... }).
--
-- rowHeight, badgeHeight, badgeWidth and titleHeight are not here, they are derived from the
-- kit's tokens by derivedLayout below and a model or section field of the same name still
-- overrides them.
local DEFAULTS = {
  columns = 2,
  colWidth = 250,
  iconSize = 0,      -- 0 = no icons
  gap = 12,          -- horizontal gap around badge/icon
  groupGap = 20,     -- vertical gap between sections
}

-- The sizes the roles decide, as numbers from the resolved tokens. The badge is its glyph's
-- body line plus the badge token's own padding, which the kit derives, and square unless a
-- model gives a width, a row is that badge with the medium space added, and the title band is
-- a section line with the medium space below.
local function derivedLayout(T)
  local badge = T.badge.cheat.height
  return {
    badgeHeight = badge,
    badgeWidth = badge,
    rowHeight = badge + T.space.m,
    titleHeight = T.text.section.lineHeight + T.space.m,
  }
end


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
-- A key whose shifted character is what a person reads, spelled as that character with Shift
-- folded into it, so slash with Shift reads as a question mark rather than as Shift and slash.
local SHIFTED_GLYPH = { ["/"] = "?" }

--- CheatSheet.glyphFor(key, mods) -> string
--- Render a binding as a badge glyph, so ("left", {"shift"}) becomes "⇧←" and
--- ("/", {"shift"}) becomes "?". A plain function with no state, called as
--- CheatSheet.glyphFor(key, mods).
function obj.glyphFor(key, mods)
  local k = tostring(key):lower()
  local g = KEY_GLYPH[k] or tostring(key):upper()
  local shifted = SHIFTED_GLYPH[k]
  local prefix = ""
  for _, m in ipairs(mods or {}) do
    if m == "shift" and shifted then g = shifted else prefix = prefix .. (MOD_GLYPH[m] or "") end
  end
  return prefix .. g
end

-- Content-sized badges. A row may carry `badges`, a list of key strings, instead
-- of a single `badge`. Each is drawn as its own box hugging its text, with a
-- separator between, so alternate keys read as distinct boxes rather than one
-- wide badge. This is opt-in: rows with a plain `badge` string keep the fixed
-- width path, so the other overlays are unchanged.
local BADGE_SEP = "or" -- default word between a row's badges, overridable per row
local SEP_GAP = 8 -- gap on each side of the separator

-- Rendered width of text in one of the kit's text variants, measured whole through the kit,
-- so a box can hug its key.
local function measureW(ui, text, variant)
  return ui.measure:exact(tostring(text), variant.font, variant.size)
end

-- Boxes for a `badges` row and the total block width, so labels can align past
-- the widest block. Each box is at least `minH` wide, so a lone glyph stays
-- square rather than a sliver. padX is the cheat badge's own padding token, glyph the text
-- variant the key is drawn in and sepVariant the one the separator word is.
local function badgeBoxes(ui, r, glyph, sepVariant, padX, minH)
  local boxes, total = {}, 0
  for _, b in ipairs(r.badges) do
    local w = math.max(minH, math.floor(measureW(ui, b, glyph) + 2 * padX + 0.5))
    boxes[#boxes + 1] = { text = b, w = w }
    total = total + w
  end
  local sep = r.sep or BADGE_SEP
  local sepW = math.floor(measureW(ui, sep, sepVariant) + 0.5)
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

-- One kit node laid out in one rect, its elements appended to els. The rect is where this
-- file's own arithmetic put the leaf, rounded to whole points the way every frame here was,
-- and the group around the node carries the section's fade, which multiplies every colour
-- and image alpha inside it, since a canvas has no group opacity of its own.
function obj:_place(els, node, x, y, w, h, alpha, T)
  local ui = self._ui
  local rect = { x = px(x), y = px(y), w = px(w), h = px(h) }
  for _, el in ipairs((ui.layout(ui.group({ node }, { alpha = alpha }), rect, { tokens = T }))) do
    els[#els + 1] = el
  end
end

-- One section's rows appended to `els`, positioned from contentY and filled
-- row-major across L.columns. `alpha` fades the whole group. Every badge, separator,
-- icon and label is a kit node, the label and the key glyph in the body role and the
-- separator in caption, so the type, the colours and the chip come from the tokens. Each
-- text is placed by its line band and the kit centres the glyphs in it.
function obj:_rowsElements(els, rows, contentY, L, alpha, T)
  local ui = self._ui
  local v = T.text.body
  local sepV = T.text.caption
  local wordWrap = ui.lineBreaks.wordWrap

  -- The model owns the badge height and the icon size, so the tokens this section draws
  -- with carry the model's numbers in the two slots its badges and icons are sized from.
  -- The groups in T are shared with the style cache, so the three this changes are copied
  -- first and nothing outside this draw sees the change.
  local cheat = {}
  for k, v in pairs(T.badge.cheat) do cheat[k] = v end
  cheat.height = L.badgeHeight
  -- The badge corner nests in the panel's own corner across this panel's own padding, which
  -- is wider than every other panel's, so it is derived here rather than read as radius.nested.
  local radius = {}
  for k, v in pairs(T.radius) do radius[k] = v end
  radius.sheet = ui.nestedRadius(radius.surface, self:_padding())
  T.radius = radius
  cheat.radius = "sheet"
  local badge = {}
  for k, v in pairs(T.badge) do badge[k] = v end
  badge.cheat = cheat
  T.badge = badge
  local icon = {}
  for k, v in pairs(T.icon) do icon[k] = v end
  icon.sheet = L.iconSize
  T.icon = icon

  -- For content-sized `badges` rows, align every label past the widest badge
  -- block in this section, so a short row and a two-box row still line up.
  local maxBlock = 0
  for _, r in ipairs(rows) do
    if r.badges then
      local _, total = badgeBoxes(ui, r, v, sepV, T.badge.cheat.padX, L.badgeHeight)
      if total > maxBlock then maxBlock = total end
    end
  end

  for i, r in ipairs(rows) do
    local col = (i - 1) % L.columns
    local row = math.floor((i - 1) / L.columns)
    local x = col * L.colWidth
    local y = contentY + row * L.rowHeight
    local badgeTop = y + (L.rowHeight - L.badgeHeight) / 2
    local labelX

    if r.badges then
      local boxes, _, sep, sepW = badgeBoxes(ui, r, v, sepV, T.badge.cheat.padX, L.badgeHeight)
      local bx = x
      for bi, b in ipairs(boxes) do
        self:_place(els, ui.badge(b.text, "cheat", { fill = true }), bx, badgeTop, b.w,
          L.badgeHeight, alpha, T)
        bx = bx + b.w
        if bi < #boxes then
          self:_place(els, ui.text(sep, "caption", { align = ui.aligns.center,
            lineBreak = wordWrap }), bx + SEP_GAP,
            badgeTop + (L.badgeHeight - sepV.lineHeight) / 2, sepW, sepV.lineHeight, alpha, T)
          bx = bx + SEP_GAP + sepW + SEP_GAP
        end
      end
      labelX = x + maxBlock + L.gap
    else
      self:_place(els, ui.badge(r.badge, "cheat", { fill = true }), x, badgeTop, L.badgeWidth,
        L.badgeHeight, alpha, T)
      labelX = x + L.badgeWidth + L.gap
    end

    if L.iconSize > 0 and r.icon then
      local iy = y + (L.rowHeight - L.iconSize) / 2
      self:_place(els, ui.icon(r.icon, "sheet"), labelX, iy, L.iconSize, L.iconSize, alpha, T)
      labelX = labelX + L.iconSize + L.gap
    end

    local labelW = L.colWidth - (labelX - x) - L.gap
    self:_place(els, ui.text(r.label or "", "body", { lineBreak = wordWrap }), labelX,
      y + (L.rowHeight - v.lineHeight) / 2, labelW, v.lineHeight, alpha, T)
  end
end

-- Compute the whole overlay: the content element list and its size, at origin
-- (0, 0). CanvasPanel offsets it by its padding and draws the surface behind it,
-- so there is no outer margin here. Cached in self._built so preferredSize and
-- the draw that follows it agree without recomputing.
function obj:_build()
  local model = self._model or {}
  local sections = nonEmpty(model.sections)
  if #sections == 0 or not self._ui then
    return { els = {}, w = 0, h = 0 }
  end

  -- The defaults are the fixed ones with the three derived heights under them, so a model
  -- or a section that names a height wins over what the roles decide.
  local T = self._ui.tokens()
  local base = derivedLayout(T)
  for k, v in pairs(self._layoutDefaults) do base[k] = v end
  local L = layoutOf(base, model)

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

  -- The panel pads by one value on every side, so the content box is trimmed to its ink. A row
  -- centres its badge with half the row spacing above and below it, and a title line box
  -- carries leading above its capitals, so the last row's half and the first line's slack
  -- would otherwise add to the padding at the bottom and the top.
  local function rowSlack(SL) return (SL.rowHeight - SL.badgeHeight) / 2 end
  local topTrim
  if sections[1].title then
    local v = T.text.section
    local cap = self._ui.measure and self._ui.measure:metrics(v.font, v.size).capHeight
    topTrim = cap and (v.lineHeight - cap) / 2 or 0
  else
    topTrim = rowSlack(layouts[1])
  end
  local bottomTrim = #sections[#sections].rows > 0 and rowSlack(layouts[#sections]) or 0
  h = h - topTrim - bottomTrim

  local els = {}
  local cursor = -topTrim
  for i, s in ipairs(sections) do
    local SL = layouts[i]
    if i > 1 then cursor = cursor + L.groupGap end
    if s.title then
      self:_place(els, self._ui.text(s.title, "section",
        { lineBreak = self._ui.lineBreaks.wordWrap }), 0, cursor, SL.columns * SL.colWidth,
        T.text.section.lineHeight, s.titleAlpha or s.alpha or 1.0, T)
      cursor = cursor + SL.titleHeight
    end
    self:_rowsElements(els, s.rows, cursor, SL, s.alpha or 1.0, T)
    cursor = cursor + rowsFor(#s.rows, SL.columns) * SL.rowHeight
  end

  return { els = els, w = w, h = h }
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- CheatSheet:init()
function obj:init()
  self._layoutDefaults = DEFAULTS
  return self
end

--- CheatSheet:configure(opts)
--- The injected CanvasPanel factory and UI kit plus the panel padding (see the header for
--- the full list). Any omitted field keeps its default, so configure(nil) is valid.
function obj:configure(opts)
  opts = opts or {}

  self._ui = opts.ui or self._ui
  self._layoutDefaults = shallow(DEFAULTS)

  -- The panel factory, injected. CanvasPanel owns the surface look, so only the
  -- factory and the padding are held here. Rebuilt on the next show if it changed.
  self._panelCfg = {
    factory = opts.canvasPanel or (self._panelCfg and self._panelCfg.factory),
    -- nil takes PADDING_SCALE times the kit's inset, see obj:_padding.
    padding = opts.padding,
  }
  -- The old panel is destroyed rather than dropped, since a native backend's window outlives a
  -- dropped instance until the next reload, and a sheet up at this moment would stay on screen.
  if self._panel then self._panel:destroy() end
  self._panel = nil

  return self
end

-- The cheat sheet pads PADDING_SCALE times the kit's panel pad on every side, an overlay
-- that holds a whole grid reading better with more room around it, unless configure set a
-- padding of its own.
local PADDING_SCALE = 2
function obj:_padding()
  local cfg = self._panelCfg or {}
  if cfg.padding then return cfg.padding end
  return PADDING_SCALE * self._ui.tokens().pad
end

-- Build the one CanvasPanel instance the first time it is needed, a centered
-- panel whose content is this spoon's live model. Returns nil when no factory was
-- injected, so show() is inert rather than erroring.
function obj:_ensurePanel()
  if self._panel then return self._panel end
  local cfg = self._panelCfg
  if not (cfg and cfg.factory) then return nil end
  self._panel = cfg.factory.new({
    placement = cfg.factory.placements.center,
    padX = self:_padding(), padY = self:_padding(),
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

--- CheatSheet:isShowing()
--- Whether an overlay is on screen right now. Delegated to the shared panel, which is the
--- thing that actually knows, so this cannot drift from what is drawn.
---
--- It exists because this overlay could not be OBSERVED. show and hide were the whole surface,
--- so nothing could ask whether holding a leader had produced anything, and a cheat sheet that
--- silently stopped appearing looked exactly like one that was working. That is not a
--- hypothetical, both sheets went dead in a rewrite and every automated check still passed,
--- because every check was asking whether wiring calls returned rather than whether anything
--- was on screen. A mechanism with no observer cannot be tested, and this is the observer.
function obj:isShowing()
  return self._panel ~= nil and self._panel:isShowing() == true
end

-- The renderer's own layout defaults, for a host that wants the same numbers by default.
obj.DEFAULTS = DEFAULTS

return obj
