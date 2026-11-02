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
--- bottom bar under every list. The badge radius is the kit's nested radius, the surface's corner less the panel
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
---         { badge = kbd.of(kbd.named("c")), label = "Google Chrome", icon = <hs.image?> }, ... } },
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

-- The one vocabulary of keys, lib/kbd.lua, see its header. A badge here is a chord of its keys.
local kbd = assert(loadfile(debug.getinfo(1, "S").source:sub(2):match("(.*/)") .. "kbd.lua"))()

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


--- CheatSheet.glyphFor(key, mods) -> chord
--- A binding as a badge, a key name and its modifier names as one kbd chord, so ("left",
--- {"shift"}) is Shift and Left and ("/", {"shift"}) is a question mark. The glyphs live in
--- lib/kbd.lua and nowhere else. A plain function with no state, called as
--- CheatSheet.glyphFor(key, mods).
function obj.glyphFor(key, mods)
  return kbd.binding(key, mods)
end

-- A row's keys are a kit key cap, lib/ui/keycap.lua, the one way a key is drawn, the same chips the
-- bottom bar and its floating panes draw. A row carries `badge`, one kbd chord, drawn in the square
-- column, or `badges`, a list of chords, the keys a person may press for one thing, drawn as one
-- chip each with the kit's separator between them and every label in the section aligned past
-- the widest block. A chip held to the column grows when its keys need more room.
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
      local total = ui.keycapWidth(T, r.badges, "cheat", { width = L.badgeHeight })
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
      self:_place(els, ui.keycap(r.badges, "cheat", { width = L.badgeHeight }), x, badgeTop, maxBlock,
        L.badgeHeight, alpha, T)
      labelX = x + maxBlock + L.gap
    else
      local w = math.max(L.badgeWidth, ui.keycapWidth(T, r.badge, "cheat", { width = L.badgeWidth }))
      self:_place(els, ui.keycap(r.badge, "cheat", { width = L.badgeWidth }), x, badgeTop, w,
        L.badgeHeight, alpha, T)
      labelX = x + w + L.gap
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
