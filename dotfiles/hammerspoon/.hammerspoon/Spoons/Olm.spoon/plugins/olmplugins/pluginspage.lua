--- === OlmPlugins.pluginspage ===
---
--- What the Plugins page shows, as plain data and UI kit nodes and nothing else. It holds no
--- canvas and no state of its own, one function for the rows, one for the state words a row says
--- and one for the detail block the docked pane draws, so init.lua can decide when each is
--- needed without knowing how any of it is built. The kit arrives as an argument, since this file
--- never loads it, which also lets the unit case drive it with a bare kit and no canvas.
---
--- The catalog is the root's own answer. A choice made on the page is staged in the root and
--- nothing runs differently until it is applied, so each catalog row carries what this load has
--- and, while anything is staged, what applying would leave, and the page draws the second. A
--- row that changes on apply says so in words, off after apply or on after apply.

local M = {}

-- The icon keys, declared with their glyphs in the manifest.
M.ICON_ON = "selected"
M.ICON_OFF = "notSelected"

local function titleOf(entry)
  return tostring((entry.about or {}).title or entry.identity)
end

local function byIdentity(catalog)
  local map = {}
  for _, entry in ipairs(catalog or {}) do map[entry.identity] = entry end
  return map
end

-- Whether the plugin is off in this load.
local function offNow(entry)
  return entry.disabled == true or entry.offBecause ~= nil
end

--- M.isOff(entry) -> bool
--- Whether the plugin is off once what is staged is applied, which is what the marker shows.
function M.isOff(entry)
  if entry.after then return entry.after.off == true end
  return offNow(entry)
end

--- M.changes(entry) -> bool
--- Whether applying what is staged changes this plugin, staged on its own row or carried along
--- by another.
function M.changes(entry)
  return entry.after ~= nil and (entry.after.off == true) ~= offNow(entry)
end

--- M.toggleable(entry, selfIdentity) -> bool
--- A plugin switched off in config, off because a sibling it requires is off, needed by the core,
--- or this plugin itself cannot be flipped from here. The first is a line in a file only the
--- person can change, the second comes back on its own when the sibling does, the third would
--- take a host down, and the last would switch off the only page that can switch it back. The
--- plugin knows its own identity, so the root names no plugin to protect it.
function M.toggleable(entry, selfIdentity)
  if entry.identity == selfIdentity or entry.lockedBy ~= nil or entry.offBecause ~= nil then
    return false
  end
  -- Going off with a staged choice on another row is the same case as being off because of it
  -- now, it comes back when that choice is undone.
  return not (entry.pending == nil and entry.after and entry.after.offBecause ~= nil)
end

-- The titles of a list of identities, said as one phrase, A, A and B, or A, B and C.
local function titleList(identities, catalog)
  local map = byIdentity(catalog)
  local titles = {}
  for _, identity in ipairs(identities or {}) do
    local other = map[identity]
    titles[#titles + 1] = other and titleOf(other) or tostring(identity)
  end
  if #titles <= 1 then return titles[1] or "", #titles end
  return table.concat(titles, ", ", 1, #titles - 1) .. " and " .. titles[#titles], #titles
end

-- The plugins a switched off one depends on, said as one phrase, A is off, A and B are off.
local function causeWords(causes, catalog)
  local joined, count = titleList(causes, catalog)
  return joined .. (count > 1 and " are off" or " is off")
end

--- M.words(entry, catalog, selfIdentity) -> string
--- The state in plain words, the row's subtitle, saying what applying will do when it changes
--- anything for this row.
function M.words(entry, catalog, selfIdentity)
  if entry.identity == selfIdentity then return "this page" end
  if entry.lockedBy == "core" then return "needed by the core" end
  if entry.lockedBy == "config" then return "locked off in config" end
  if M.changes(entry) then
    if not entry.after.off then return "on after apply" end
    if entry.pending == nil and entry.after.offBecause then
      return "off after apply, because " .. causeWords(entry.after.offBecause, catalog)
    end
    return "off after apply"
  end
  if entry.offBecause ~= nil then return "off because " .. causeWords(entry.offBecause, catalog) end
  return M.isOff(entry) and "off" or "on"
end

--- M.pendingSummary(catalog) -> string or nil
--- What applying would change, every plugin it changes as its title and on or off, in the
--- catalog's own order. Nil when nothing is staged, which is when the page shows no Apply row.
function M.pendingSummary(catalog)
  local parts = {}
  for _, entry in ipairs(catalog or {}) do
    if M.changes(entry) then
      parts[#parts + 1] = titleOf(entry) .. (entry.after.off and " off" or " on")
    end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, ", ")
end

--- M.rows(catalog, row, selfIdentity) -> rows
--- One row per catalog entry, the catalog's own order, which the root already sorted by title.
--- row is the plugin's own row constructor, so this file never decides what a row's fields are.
--- Each row filters on its title and identity only, never the state words, so staging a row
--- never changes whether it matches a typed query and the stay redraw keeps its row number.
--- Each item states its identity as key, so the stage holds the highlight on the same plugin
--- when a row above it comes or goes.
function M.rows(catalog, row, selfIdentity)
  local rows = {}
  for _, entry in ipairs(catalog or {}) do
    rows[#rows + 1] = row(titleOf(entry), M.words(entry, catalog, selfIdentity),
      M.isOff(entry) and M.ICON_OFF or M.ICON_ON,
      { plugin = entry.identity, key = entry.identity, toggle = M.toggleable(entry, selfIdentity) },
      true, titleOf(entry) .. " " .. tostring(entry.identity))
  end
  return rows
end

--- M.find(catalog, identity) -> entry or nil
function M.find(catalog, identity)
  return byIdentity(catalog)[identity]
end

-- The needs groups in the order a person reads them, each a label and the entry's own field.
local GROUPS = {
  { label = "Tools", field = "tools" },
  { label = "Libraries", field = "libs" },
  { label = "Siblings", field = "siblings" },
  { label = "Data", field = "data" },
}

-- The line about what else moves with this plugin's choice, nothing when nothing does. cascade
-- is the root's answer, { off, staged, others }, the identities mapped to titles here since the
-- root never sees a title. A staged choice says what applying does, an unstaged one what
-- choosing this row would.
local function cascadeLine(cascade, catalog)
  if type(cascade) ~= "table" or not cascade.others or #cascade.others == 0 then return nil end
  local names = titleList(cascade.others, catalog)
  local lead
  if cascade.staged then
    lead = cascade.off and "Applying this also turns off " or "Applying this also brings back "
  else
    lead = cascade.off and "Turning this off also turns off " or "Turning this on also brings back "
  end
  return lead .. names .. "."
end

--- M.detail(ui, entry, catalog, cascade, selfIdentity) -> node
--- The detail block for one plugin, built from kit nodes. The heading is the title with the
--- version flush right, then the description, then the about facts, then the needs in short labelled groups, then the
--- cascade line when there is one. Every piece of text names a role and never a font or colour.
function M.detail(ui, entry, catalog, cascade, selfIdentity)
  local about = entry.about or {}
  local blocks = {}

  local function fact(label, value)
    if value == nil or value == "" then return end
    blocks[#blocks + 1] = ui.stack({
      ui.text(label, "caption"),
      ui.text(tostring(value), "body", { wrap = true }),
    }, { gap = "xs" })
  end

  blocks[#blocks + 1] = ui.heading(string.upper(titleOf(entry)), about.version and ("v" .. about.version) or nil)
  -- What the plugin does comes first, since it is what a person scrolling the list is reading for.
  if about.description and about.description ~= "" then
    blocks[#blocks + 1] = ui.text(about.description, "body", { wrap = true })
  end
  blocks[#blocks + 1] = ui.text(M.words(entry, catalog, selfIdentity), "caption")
  fact("Author", about.author)
  fact("License", about.license)
  fact("Homepage", about.homepage)

  local needs = entry.needs or {}
  local any = false
  for _, group in ipairs(GROUPS) do
    local names = needs[group.field] or {}
    if #names > 0 then
      any = true
      fact(group.label, table.concat(names, ", "))
    end
  end
  if not any then
    blocks[#blocks + 1] = ui.text("Needs nothing beyond the core.", "caption", { wrap = true })
  end

  local line = cascadeLine(cascade, catalog)
  if line then blocks[#blocks + 1] = ui.text(line, "caption", { wrap = true }) end

  return ui.stack(blocks, { gap = "m" })
end

return M
