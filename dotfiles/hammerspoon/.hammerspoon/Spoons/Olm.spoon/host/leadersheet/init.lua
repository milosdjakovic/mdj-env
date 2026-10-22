--- === LeaderSheet ===
---
--- Content builder for every leader's hold overlay, the one host that replaced the Hyper and the
--- window cheat sheets in phase 4 of the keymap plan. A held leader asks it to show its own
--- keycode, and it draws that leader's sheet, the rows the keymap holds on the leader, laid out as
--- that leader's policy says. It names no leader, no plugin and no layout of its own, so a new
--- leader gets a sheet by policy alone.
---
--- What the root hands it, per leader, is the leader's keycode, its layout and an ordered list of
--- entries. An entry is a section table, built once at configure, or a function answering
--- sections when the sheet is shown, which is how a plugin's live state reaches the sheet. Both
--- are built by ownSections below from the keymap's rows and the descriptor behind each, filed
--- under the descriptor's group or under the layout's title, and a row standing for an app wears
--- that app's icon and name. A row whose when is false is hidden at every show, exactly while its
--- key is gated.
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

obj._sheets = nil      -- key to { name, layout, entries }, the key a keycode or, for a leader with none, its name, and the same records in order below
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

-- One section a live block answered at a show, as the renderer wants it, or nil for one that is
-- not usable. A section carries `rows`, each { badge or key and mods, label, icon, when }. A row
-- that states its own badge keeps it, anything else is spelled by the shared glyph helper so
-- Shift and 4 reads as a shift glyph then 4. `icons = true` asks for the icon grid, `alpha` fades
-- the whole group and `titleAlpha` its title alone.
--
-- A live block runs a plugin's group functions, so its answer is checked before anything is
-- drawn from it. A row that is not a table, or one with neither a badge nor a key, is dropped
-- with one log line, and a section that is not a table is dropped the same way, so a malformed
-- answer costs only itself and never blanks the whole sheet on a key hold.
local function buildLive(section, glyphFor, layout)
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

-- How a section a group asks to be faded is drawn, the whole group dimmed with its title kept
-- bright, so a person still reads what the group is while its rows recede. The app toggler's apps
-- that are not running are the case, and these are the numbers its own section always drew with.
local FADED_ALPHA = 0.55
local FADED_TITLE_ALPHA = 1.0

-- Order by key, letters and digits first, then symbols such as ` and \ at the end, ignoring case,
-- the order the app sections have always had, so a person finds an app by its letter.
local function keyRank(k)
  return tostring(k):match("^%w$") and 0 or 1
end
local function byKey(a, b)
  local ra, rb = keyRank(a.key), keyRank(b.key)
  if ra ~= rb then return ra < rb end
  return tostring(a.key):lower() < tostring(b.key):lower()
end

-- The section a row is filed under, as a title and whether it is faded. A group is a word, a table
-- with a title and an optional faded, or a function answering either, asked with nothing and only
-- once resolve is on. A failure, or an answer that is neither, files the row under the layout's
-- title, unfaded, as does a row with no group.
local function sectionOf(row, layout, resolve)
  local group = row.group
  if type(group) == "function" then
    if not resolve then return layout.title, false end
    local ok, answer = pcall(group)
    group = ok and answer or nil
  end
  if type(group) == "table" and type(group.title) == "string" and group.title ~= "" then
    return group.title, group.faded == true
  end
  if type(group) == "string" and group ~= "" then return group, false end
  return layout.title, false
end

-- Sections from rows, one per title in the order each title first appears, with every faded
-- section after every section in full colour, so a group that recedes never leads one that does
-- not. Rows are the entries lib/hints.lua's sheetRows answers, each already carrying the app's
-- name and icon where it stands for an app, see resolveApps. A section whose every row stands for
-- an app is drawn as an icon grid ordered by key, the way the app sections always were, and any
-- other section as a plain grid in the sheet's own order. A row with no key is skipped and a row
-- keeps its `when` so the gate can be asked at every show.
local function sectionsFromRows(rows, glyphFor, layout, resolve)
  local found, byTitle = {}, {}
  for _, row in ipairs(rows) do
    if type(row) == "table" and row.key ~= nil then
      local title, faded = sectionOf(row, layout, resolve)
      local section = byTitle[title]
      if not section then
        section = { title = title, faded = faded, rows = {}, apps = true }
        byTitle[title] = section
        found[#found + 1] = section
      end
      section.rows[#section.rows + 1] = row
      if row.appIcon == nil then section.apps = false end
    else
      drop("a row", "it is not a table with a key")
    end
  end
  local out = {}
  for _, pass in ipairs({ false, true }) do
    for _, found1 in ipairs(found) do
      if found1.faded == pass then
        local section = {
          title = found1.title,
          alpha = pass and FADED_ALPHA or 1.0,
          titleAlpha = pass and FADED_TITLE_ALPHA or nil,
          rows = {},
        }
        local list = found1.rows
        if found1.apps then
          section.icons = true
          list = {}
          for i, r in ipairs(found1.rows) do list[i] = r end
          table.sort(list, byKey)
        else
          plainLayout(section, layout)
        end
        for _, row in ipairs(list) do
          local badge = glyphFor and glyphFor(row.key, row.mods) or tostring(row.key)
          section.rows[#section.rows + 1] = { badge = badge,
            label = row.description or (row.action and humanize(row.action)) or tostring(row.key),
            icon = found1.apps and row.appIcon or nil, when = row.when }
        end
        out[#out + 1] = section
      end
    end
  end
  return out
end

-- Each row standing for an app, resolved once to the app's name and icon, since both are disk
-- work and the sheet opens on a key hold that must feel instant. A row whose app is not on this
-- machine is left off the sheet, so a sheet never lists something that is not installed. The
-- description a descriptor states wins over the app's own name, and an app macOS answers no name
-- for wears its action's name, the catalog name it was declared under, as the toggler's own
-- sheet rows always did. Without appInfo an app row is an ordinary row. Copies, so nothing reaches back into the rows a caller holds.
local function resolveApps(rows, appInfo)
  local out = {}
  for _, row in ipairs(rows or {}) do
    if type(row) == "table" and row.app ~= nil and appInfo then
      local ok, info = pcall(appInfo, row.app)
      if ok and type(info) == "table" then
        local copy = {}
        for k, v in pairs(row) do copy[k] = v end
        copy.description = row.description or info.name or row.action or tostring(row.app)
        copy.appIcon = info.icon or false
        out[#out + 1] = copy
      elseif not ok then
        drop("the row for " .. tostring(row.app), "resolving its app raised, " .. tostring(info))
      end
    else
      out[#out + 1] = row
    end
  end
  return out
end

--- LeaderSheet.ownSections(rows, deps) -> entries
--- A leader's rows as sheet entries, in the order the sheet draws them. deps.glyphFor spells a
--- chord as a badge, deps.layout is the leader's layout, whose title heads rows with no group.
--- deps.appInfo, optional, answers a bundle id's { name, icon }, or nil for an app not on this
--- machine. deps.orderOf, optional, answers the number a row's owner places its rows at on a
--- sheet, its defaults.cheatSheetOrder, and deps.ownOrder the number every other row sits at.
--- Rows are the entries lib/hints.lua's sheetRows answers.
---
--- Rows sharing a number form one block, blocks in ascending order with a row of no number last,
--- which is how the app toggler's apps lead the Hyper sheet. A block whose every group is a word
--- or a table is built once and returned as its sections. A block holding a group function is one
--- function, asked at every show, since the section a row belongs to may change with live state.
--- Pure, it touches no hs global but the logger.
function obj.ownSections(rows, deps)
  deps = deps or {}
  local glyphFor, layout = deps.glyphFor, deps.layout or {}
  local orderOf = deps.orderOf or function() return nil end
  local blocks, byOrder = {}, {}
  for _, row in ipairs(resolveApps(rows, deps.appInfo)) do
    local order = (type(row) == "table" and orderOf(row.owner)) or deps.ownOrder
    local mark = order == nil and "none" or order
    local block = byOrder[mark]
    if not block then
      block = { order = order, position = #blocks + 1, rows = {}, live = false }
      byOrder[mark] = block
      blocks[#blocks + 1] = block
    end
    block.rows[#block.rows + 1] = row
    if type(row) == "table" and type(row.group) == "function" then block.live = true end
  end
  table.sort(blocks, function(a, b)
    if a.order ~= b.order then
      if a.order == nil then return false end
      if b.order == nil then return true end
      return a.order < b.order
    end
    return a.position < b.position
  end)
  local out = {}
  for _, block in ipairs(blocks) do
    if block.live then
      out[#out + 1] = function() return sectionsFromRows(block.rows, glyphFor, layout, true) end
    else
      for _, section in ipairs(sectionsFromRows(block.rows, glyphFor, layout, false)) do
        out[#out + 1] = section
      end
    end
  end
  return out
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
---                  sheet for, absent on a leader of modifiers, which is shown by its name instead,
---                  layout the leader's resolved layout and entries the ordered list
---                  ownSections answered, each a section table or a function answering a list of
---                  them at every show. Absent leaves the sheets as
---                  they were, so a first configure that holds only the renderer changes none.
function obj:configure(opts)
  opts = opts or {}
  self._cheatSheet = opts.cheatSheet or self._cheatSheet
  self._predicates = opts.predicates or self._predicates or {}
  if opts.sheets ~= nil then
    self._sheets, self._order = {}, {}
    for _, spec in ipairs(opts.sheets) do
      if type(spec) == "table" and (spec.keyCode ~= nil or spec.name ~= nil) then
        -- A plain section carries no live state, so it was built once before it got here and only
        -- a live block is asked again on every show. Anything else in the list is left out.
        local entries = {}
        for _, entry in ipairs(spec.entries or {}) do
          if type(entry) == "function" or type(entry) == "table" then entries[#entries + 1] = entry end
        end
        local record = { name = spec.name, keyCode = spec.keyCode, layout = spec.layout or {}, entries = entries }
        -- A held leader is found by its keycode and a leader of modifiers, which has none, by its
        -- name. The two cannot meet, a keycode is a number and a name is a word.
        self._sheets[spec.keyCode ~= nil and spec.keyCode or spec.name] = record
        self._order[#self._order + 1] = record
      else
        drop("a leader", "it names neither a keycode nor a name")
      end
    end
  end
  return self
end

--- LeaderSheet:model(keyCode) -> record or nil
--- What the host holds for one leader, its name, layout and ordered entries, before any live block
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
--- Every section the sheet would draw for one leader right now. Each live block is asked now, one
--- that raises costs its own sections with one log line, and an answer that is not a list is
--- skipped. A row whose `when` is false is left out. A section left with no rows is kept, since
--- the renderer drops an empty one.
function obj:sections(keyCode)
  local sheet = (self._sheets or {})[keyCode]
  if not sheet then return {} end
  local glyphFor = self._cheatSheet and self._cheatSheet.glyphFor
  local built = {}
  for _, entry in ipairs(sheet.entries) do
    if type(entry) == "function" then
      local ok, answered = pcall(entry)
      if not ok then
        drop("a live block", "it raised, " .. tostring(answered))
      elseif type(answered) == "table" then
        for _, section in ipairs(answered) do
          -- Checked, since a live block ran a plugin's group functions. A well formed section
          -- comes out unchanged, its rows already carrying their badges.
          local ready = buildLive(section, glyphFor, sheet.layout)
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
