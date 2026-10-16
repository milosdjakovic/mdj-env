--- === HyperCheatSheet ===
---
--- Content builder for the Hyper overlay, everything reachable while the Hyper key is held.
--- It renders an ordered list of sections the composition root hands it and knows nothing
--- about who supplied them. Some are the sheet's own, every chord the root found bound on the
--- app leader, built once. Others come from plugins that declare provides.cheatSheetSections,
--- asked again on every show, which is how the app toggler's running and dormant split reaches
--- the sheet while this host names no plugin and reads no plugin's data.
---
--- Turning a key into a badge glyph and the actual drawing are both delegated to the shared
--- CheatSheet renderer injected through configure. This host owns only the layout of a
--- section, an icon grid for a section that asks for icons and a plain grid for one that does
--- not.
---
--- Until phase four of the core split this host read the person's appToggles list and the app
--- registry itself and did the running split here, which was a host knowing one plugin's data
--- and its shape. The split is app knowledge and moved into that plugin with the list.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "HyperCheatSheet"
obj.version = "3.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

obj._entries = nil     -- ordered, each a built section or a function answering sections
obj._cheatSheet = nil  -- shared CheatSheet renderer

local log = hs.logger.new("HyperCheatSheet", "info")

-- Layout knobs for this overlay, four columns and room for an app icon. The badge is square and
-- its size and the row height are not here, the cheat sheet derives them from the type roles.
local LAYOUT = {
  columns = 4,
  colWidth = 215,   -- wide enough for names like "Activity Monitor"
  iconSize = 32,
  gap = 10,
  groupGap = 20,
}

-- A section that asks for no icons renders without the icon gutter. Four columns keep the
-- four capture actions (OCR, Screenshot, Screenshot copy, Record screen) on the first row,
-- with the remaining commands falling to the next. They reuse the icon grid's column width,
-- freeing the gutter as extra label room, so the columns keep the same tight rhythm as the
-- icon rows instead of spreading across the whole panel.
local PLAIN_COLUMNS = 4
local PLAIN_COLWIDTH = LAYOUT.colWidth

--- HyperCheatSheet:init()
function obj:init()
  return self
end

-- One section as the renderer wants it, or nil for one that is not usable. A section carries either `bindings`, the chords the
-- root collected, each { key, mods, action, description }, or `rows`, each { badge or key and
-- mods, label, icon }. A row that states its own badge keeps it, anything else is spelled by
-- the shared glyph helper so Hyper+Shift+4 reads "⇧4". `icons = true` asks for the icon grid,
-- `alpha` fades the whole group and `titleAlpha` its title alone.
--
-- A supplier is a plugin's code, so its answer is checked before anything is built from it. A
-- row that is not a table, or one with neither a badge nor a key, is dropped with one log line,
-- and a section that is not a table is dropped the same way, so a malformed answer costs only
-- itself and never blanks the whole sheet on a key hold.
local function drop(what, why)
  log.w("dropped " .. what .. " from the Hyper sheet, " .. why)
end

local function build(section, glyphFor)
  if type(section) ~= "table" then
    drop("a section", "it is a " .. type(section) .. " and not a table")
    return nil
  end
  local name = tostring(section.title or "untitled")
  local rows = {}
  for _, b in ipairs(section.bindings or {}) do
    if type(b) == "table" and b.key ~= nil then
      local badge = glyphFor and glyphFor(b.key, b.mods) or tostring(b.key)
      rows[#rows + 1] = { badge = badge, label = b.description or b.action or tostring(b.key) }
    else
      drop("a binding of section '" .. name .. "'", "it is not a table with a key")
    end
  end
  for _, r in ipairs(section.rows or {}) do
    if type(r) == "table" and (r.badge ~= nil or r.key ~= nil) then
      local badge = r.badge or (glyphFor and glyphFor(r.key, r.mods)) or tostring(r.key)
      rows[#rows + 1] = { badge = badge, label = r.label or tostring(r.key), icon = r.icon }
    else
      drop("a row of section '" .. name .. "'", "it is not a table with a badge or a key")
    end
  end
  local out = {
    title = section.title,
    alpha = section.alpha or 1.0,
    titleAlpha = section.titleAlpha,
    rows = rows,
  }
  if not section.icons then
    -- Override the panel layout for these rows, fewer, wider columns and no icon gutter, so
    -- long labels like "Screenshot to clipboard" are not cut.
    out.columns = PLAIN_COLUMNS
    out.colWidth = PLAIN_COLWIDTH
    out.iconSize = 0
  end
  return out
end

--- HyperCheatSheet:configure(opts)
--- opts.cheatSheet is the shared CheatSheet renderer to draw with.
--- opts.sections is the ordered list the root assembles through lib/contributions.lua, each
--- entry a section table or a function answering a list of them when the sheet is shown.
--- Absent means the overlay has nothing to show.
function obj:configure(opts)
  opts = opts or {}
  self._cheatSheet = opts.cheatSheet or self._cheatSheet
  local glyphFor = self._cheatSheet and self._cheatSheet.glyphFor
  -- A plain section carries no live state, so it is built once here and only a supplier is
  -- asked again on every show.
  self._entries = {}
  for _, entry in ipairs(opts.sections or {}) do
    if type(entry) == "function" then
      self._entries[#self._entries + 1] = entry
    elseif type(entry) == "table" then
      local built = build(entry, glyphFor)
      if built then self._entries[#self._entries + 1] = built end
    end
  end
  return self
end

--- HyperCheatSheet:_sections()
--- Every section in order, each supplier asked now. A supplier that fails is the root's to
--- contain, lib/contributions.lua wraps every one so a plugin that raises costs its own
--- sections and is named, and this host only skips an answer that is not a list.
function obj:_sections()
  local glyphFor = self._cheatSheet and self._cheatSheet.glyphFor
  local out = {}
  for _, entry in ipairs(self._entries or {}) do
    if type(entry) == "function" then
      local supplied = entry()
      if type(supplied) == "table" then
        for _, section in ipairs(supplied) do
          local built = build(section, glyphFor)
          if built then out[#out + 1] = built end
        end
      end
    else
      out[#out + 1] = entry
    end
  end
  return out
end

--- HyperCheatSheet:show()
--- Hand every section to the renderer. Empty sections are dropped by the renderer, so a group
--- with no rows, no running app for instance, simply does not appear.
function obj:show()
  if not self._cheatSheet then return self end
  self._cheatSheet:show({
    columns = LAYOUT.columns,
    colWidth = LAYOUT.colWidth,
    iconSize = LAYOUT.iconSize,
    gap = LAYOUT.gap,
    groupGap = LAYOUT.groupGap,
    sections = self:_sections(),
  })
  return self
end

--- HyperCheatSheet:hide()
function obj:hide()
  if self._cheatSheet then self._cheatSheet:hide() end
  return self
end

--- HyperCheatSheet:isShowing()
--- Whether this overlay is on screen, asked of the shared renderer rather than tracked here,
--- so this can never disagree with what is actually drawn. See lib/cheatsheet.lua for why an
--- observer had to exist at all.
function obj:isShowing()
  return self._cheatSheet ~= nil and self._cheatSheet:isShowing() == true
end

return obj
