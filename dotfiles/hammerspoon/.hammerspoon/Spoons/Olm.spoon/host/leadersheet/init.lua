--- === LeaderSheet ===
---
--- Content builder for every leader's hold overlay, the one host that replaced the Hyper and the
--- window cheat sheets in phase 4 of the keymap plan. A held leader asks it to show its own
--- keycode, and it draws that leader's sheet, rows the keymap holds on the leader plus the
--- sections plugins contribute for it, laid out as that leader's policy says. It names no leader,
--- no plugin and no layout of its own, so a new leader gets a sheet by policy alone.
---
--- What the root hands it, per leader, is the leader's keycode, its layout and an ordered list of
--- entries. An entry is a section table, built once at configure, or a function answering
--- sections when the sheet is shown, which is how a plugin's live state reaches the sheet. The
--- leader's own rows are one such block, built by ownSections below from the keymap's rows and
--- the descriptor behind each, filed under the descriptor's group or under the layout's title. A
--- row whose when is false is hidden at every show, exactly while its key is gated.
---
--- Turning a key into a badge glyph and the drawing itself are both delegated to the shared
--- CheatSheet renderer injected through configure. This host owns the layout of a section, an
--- icon grid for a section that asks for icons and a plain grid for one that does not, and it
--- holds the one rule shared by every leader that a sheet is never drawn empty.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "LeaderSheet"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("LeaderSheet", "info")

obj._sheets = nil      -- keycode to { name, layout, entries }, and the same records in order below
obj._order = nil
obj._cheatSheet = nil  -- shared CheatSheet renderer
obj._predicates = nil  -- name to function answering a bool, for rows with a when

-- The layout fields the renderer takes, copied into a show only where the leader's layout states
-- them, so a leader that states fewer draws with the renderer's own numbers for the rest.
local RENDERER_FIELDS = { "columns", "colWidth", "iconSize", "gap", "groupGap", "badgeWidth" }

-- camelCase action name to a Title Case label, for a row that carries no description.
local function humanize(name)
  local s = tostring(name):gsub("(%l)(%u)", "%1 %2")
  s = s:gsub("^%l", string.upper)
  return s
end

local function drop(what, why)
  log.w("dropped " .. what .. " from a leader sheet, " .. why)
end

-- A section that asks for no icons renders without the icon gutter, in the leader's own columns
-- and column width, so a long label is not cut and the columns keep one rhythm across sections.
local function plainLayout(section, layout, icons)
  if icons then return end
  section.columns = layout.columns
  section.colWidth = layout.colWidth
  section.iconSize = 0
end

-- One section a plugin supplied, as the renderer wants it, or nil for one that is not usable. A
-- section carries `rows`, each { badge or key and mods, label, icon, when }. A row that states
-- its own badge keeps it, anything else is spelled by the shared glyph helper so Shift and 4
-- reads as a shift glyph then 4. `icons = true` asks for the icon grid, `alpha` fades the whole
-- group and `titleAlpha` its title alone.
--
-- A supplier is a plugin's code, so its answer is checked before anything is built from it. A
-- row that is not a table, or one with neither a badge nor a key, is dropped with one log line,
-- and a section that is not a table is dropped the same way, so a malformed answer costs only
-- itself and never blanks the whole sheet on a key hold.
local function buildSupplied(section, glyphFor, layout)
  if type(section) ~= "table" then
    drop("a section", "it is a " .. type(section) .. " and not a table")
    return nil
  end
  local name = tostring(section.title or "untitled")
  local rows = {}
  for _, r in ipairs(section.rows or {}) do
    if type(r) == "table" and (r.badge ~= nil or r.key ~= nil) then
      local badge = r.badge or (glyphFor and glyphFor(r.key, r.mods)) or tostring(r.key)
      rows[#rows + 1] = { badge = badge, label = r.label or tostring(r.key), icon = r.icon, when = r.when }
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
  plainLayout(out, layout, section.icons)
  return out
end

-- The section a row is filed under, the descriptor's group word, or the word its group function
-- answers once resolve is on, or the layout's title for a row with neither. A group function is
-- asked with nothing and a failure or a non word answer files the row under the title.
local function titleOf(row, layout, resolve)
  local group = row.group
  if type(group) == "function" then
    if not resolve then return nil end
    local ok, word = pcall(group)
    group = ok and word or nil
  end
  if type(group) == "string" and group ~= "" then return group end
  return layout.title
end

-- Sections from rows, one per title in the order each title first appears. Rows are the entries
-- lib/hints.lua's sheetRows answers. A row with no key is skipped and a row keeps its `when` so
-- the gate can be asked at every show.
local function sectionsFromRows(rows, glyphFor, layout, resolve)
  local out, byTitle = {}, {}
  for _, row in ipairs(rows) do
    if type(row) == "table" and row.key ~= nil then
      local title = titleOf(row, layout, resolve)
      local section = byTitle[title]
      if not section then
        section = { title = title, alpha = 1.0, rows = {} }
        plainLayout(section, layout)
        byTitle[title] = section
        out[#out + 1] = section
      end
      local badge = glyphFor and glyphFor(row.key, row.mods) or tostring(row.key)
      section.rows[#section.rows + 1] = { badge = badge,
        label = row.description or (row.action and humanize(row.action)) or tostring(row.key), when = row.when }
    else
      drop("a row", "it is not a table with a key")
    end
  end
  return out
end

--- LeaderSheet.ownSections(rows, deps) -> entries
--- A leader's own rows as sheet entries, the block the root places among the sections plugins
--- contribute. deps.glyphFor spells a chord as a badge, deps.layout is the leader's layout, whose
--- title heads rows with no group. Rows are the entries lib/hints.lua's sheetRows answers. When
--- every group is a word the sections are built once and returned as they stand. When any group
--- is a function the whole block is one function, asked at every show, since the section a row
--- belongs to may change with live state. Pure, it touches no hs global but the logger.
function obj.ownSections(rows, deps)
  deps = deps or {}
  local glyphFor, layout = deps.glyphFor, deps.layout or {}
  for _, row in ipairs(rows or {}) do
    if type(row) == "table" and type(row.group) == "function" then
      return { function() return sectionsFromRows(rows, glyphFor, layout, true) end }
    end
  end
  return sectionsFromRows(rows or {}, glyphFor, layout, false)
end

--- LeaderSheet:init()
function obj:init()
  self._sheets = {}
  self._order = {}
  self._predicates = {}
  return self
end

--- LeaderSheet:_active(when)
--- Is a row carrying this `when` predicate name currently active? A row with no `when` is always
--- active. An unknown name is treated as active so a typo fails visibly, the row shown, rather
--- than silently hiding a binding. Said once per name, the way the leader adapter says it. Called per row at show time, so it tracks live state such as
--- the display count.
function obj:_active(when)
  if not when then return true end
  local p = (self._predicates or {})[when]
  if not p then
    self._unknownSeen = self._unknownSeen or {}
    if not self._unknownSeen[when] then
      self._unknownSeen[when] = true
      log.w("unknown predicate '" .. tostring(when) .. "'")
    end
    return true
  end
  return p() and true or false
end

--- LeaderSheet:configure(opts)
--- opts.cheatSheet  the shared CheatSheet renderer to draw with
--- opts.predicates  name to function answering a bool, for rows with a `when`
--- opts.sheets      the leaders that show a sheet, a list, each { name, keyCode, layout, entries }.
---                  name is the leader as a keymap row spells it, keyCode the key a hold shows the
---                  sheet for, layout the leader's resolved layout and entries the ordered list the
---                  root assembles through lib/contributions.lua, each a section table or a
---                  function answering a list of them at every show. Absent leaves the sheets as
---                  they were, so a first configure that holds only the renderer changes none.
function obj:configure(opts)
  opts = opts or {}
  self._cheatSheet = opts.cheatSheet or self._cheatSheet
  self._predicates = opts.predicates or self._predicates or {}
  if opts.sheets ~= nil then
    self._sheets, self._order = {}, {}
    for _, spec in ipairs(opts.sheets) do
      if type(spec) == "table" and spec.keyCode ~= nil then
        -- A plain section carries no live state, so it was built once before it got here and only
        -- a supplier is asked again on every show. Anything else in the list is left out.
        local entries = {}
        for _, entry in ipairs(spec.entries or {}) do
          if type(entry) == "function" or type(entry) == "table" then entries[#entries + 1] = entry end
        end
        local record = { name = spec.name, keyCode = spec.keyCode, layout = spec.layout or {}, entries = entries }
        self._sheets[spec.keyCode] = record
        self._order[#self._order + 1] = record
      else
        drop("a leader", "it names no keycode")
      end
    end
  end
  return self
end

--- LeaderSheet:model(keyCode) -> record or nil
--- What the host holds for one leader, its name, layout and ordered entries, before any supplier
--- is asked and before any `when` is. The offline projection and the plain cases read it.
function obj:model(keyCode)
  return (self._sheets or {})[keyCode]
end

--- LeaderSheet:modelNamed(name) -> record or nil
--- The record of the leader a keymap row spells as this name, hyper or meta here, for a reader that
--- knows the leader and not its keycode.
function obj:modelNamed(name)
  for _, record in ipairs(self._order or {}) do
    if record.name == name then return record end
  end
  return nil
end

--- LeaderSheet:models() -> list
--- Every leader's record, in the order configure was given them.
function obj:models()
  return self._order or {}
end

--- LeaderSheet:sections(keyCode) -> list
--- Every section the sheet would draw for one leader right now. Each supplier is asked now, a
--- supplier that fails is the root's to contain, lib/contributions.lua wraps every one so a
--- plugin that raises costs its own sections and is named, and this host only skips an answer
--- that is not a list. A row whose `when` is false is left out. A section left with no rows is
--- kept, since the renderer drops an empty one, a group with no running app for instance.
function obj:sections(keyCode)
  local sheet = (self._sheets or {})[keyCode]
  if not sheet then return {} end
  local glyphFor = self._cheatSheet and self._cheatSheet.glyphFor
  local built = {}
  for _, entry in ipairs(sheet.entries) do
    if type(entry) == "function" then
      local supplied = entry()
      if type(supplied) == "table" then
        for _, section in ipairs(supplied) do
          -- A section a supplier answers is a plugin's, so it is checked. The leader's own block,
          -- when a group is a function, passes through the same check and comes out unchanged,
          -- since its rows already carry their badges.
          local ready = buildSupplied(section, glyphFor, sheet.layout)
          if ready then built[#built + 1] = ready end
        end
      end
    else
      built[#built + 1] = entry
    end
  end
  local out = {}
  for _, section in ipairs(built) do
    local rows = {}
    for _, row in ipairs(section.rows or {}) do
      if self:_active(row.when) then rows[#rows + 1] = row end
    end
    local copy = {}
    for k, v in pairs(section) do copy[k] = v end
    copy.rows = rows
    out[#out + 1] = copy
  end
  return out
end

--- LeaderSheet:show(keyCode)
--- Hand one leader's sections to the renderer. Nothing is drawn for a leader this host holds
--- nothing for, or one whose every row is hidden right now.
function obj:show(keyCode)
  if not self._cheatSheet then return self end
  local sheet = (self._sheets or {})[keyCode]
  if not sheet then return self end
  local sections = self:sections(keyCode)
  local drawn = 0
  for _, section in ipairs(sections) do drawn = drawn + #section.rows end
  if drawn == 0 then return self end
  local model = { sections = sections }
  for _, field in ipairs(RENDERER_FIELDS) do
    if sheet.layout[field] ~= nil then model[field] = sheet.layout[field] end
  end
  self._cheatSheet:show(model)
  return self
end

--- LeaderSheet:hide()
function obj:hide()
  if self._cheatSheet then self._cheatSheet:hide() end
  return self
end

--- LeaderSheet:isShowing()
--- Whether this overlay is on screen, asked of the shared renderer rather than tracked here,
--- so this can never disagree with what is actually drawn. See lib/cheatsheet.lua for why an
--- observer had to exist at all.
function obj:isShowing()
  return self._cheatSheet ~= nil and self._cheatSheet:isShowing() == true
end

return obj
