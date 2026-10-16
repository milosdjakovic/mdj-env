--- === Settings.pluginspage ===
---
--- What the Plugins page shows, as plain data and UI kit nodes and nothing else. It holds no
--- canvas and no state of its own, one function for the rows, one for the state words a row says
--- and one for the detail block the docked pane draws, so init.lua can decide when each is
--- needed without knowing how any of it is built. The kit arrives as an argument, since this file
--- never loads it, which also lets the unit case drive it with a bare kit and no canvas.
---
--- The catalog is the root's own answer and reflects this load. A switch made on the page only
--- takes effect after the reload it schedules, so the page keeps a small overlay of what was just
--- chosen, handed in as pending, and draws the marker from that until the reload lands. The
--- overlay only ever answers for the identity the person just flipped.

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

--- M.isOff(entry, pending) -> bool
--- Whether the plugin is off, counting a switch just made on this page that the reload has not
--- applied yet.
function M.isOff(entry, pending)
  local chosen = pending and pending[entry.identity]
  if chosen ~= nil then return chosen end
  return entry.disabled == true or entry.offBecause ~= nil
end

--- M.toggleable(entry) -> bool
--- A plugin switched off in config, or off because a sibling it requires is off, cannot be
--- flipped from here. The first is a line in a file only the person can change, and the second
--- comes back on its own when the sibling does.
function M.toggleable(entry)
  return entry.lockedBy == nil and entry.offBecause == nil
end

--- M.words(entry, catalog, pending) -> string
--- The state in plain words, the row's subtitle.
function M.words(entry, catalog, pending)
  if entry.lockedBy == "config" then return "locked off in config" end
  if entry.offBecause ~= nil then
    local cause = byIdentity(catalog)[entry.offBecause]
    return "off because " .. (cause and titleOf(cause) or tostring(entry.offBecause)) .. " is off"
  end
  return M.isOff(entry, pending) and "off" or "on"
end

--- M.rows(catalog, pending, row) -> rows
--- One row per catalog entry, the catalog's own order, which the root already sorted by title.
--- row is the plugin's own row constructor, so this file never decides what a row's fields are.
function M.rows(catalog, pending, row)
  local rows = {}
  for _, entry in ipairs(catalog or {}) do
    rows[#rows + 1] = row(titleOf(entry), M.words(entry, catalog, pending),
      M.isOff(entry, pending) and M.ICON_OFF or M.ICON_ON,
      { plugin = entry.identity, toggle = M.toggleable(entry) }, true)
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

-- The line about what else moves with this switch, nothing when nothing does. cascade is the
-- root's list of identities, mapped to titles here since the root never sees a title.
local function cascadeLine(entry, catalog, cascade, pending)
  if not cascade or #cascade == 0 then return nil end
  -- The root answers the cascade for the state of this load, so a switch just made here would
  -- be described in the wrong direction until the reload, and saying nothing is the honest line.
  if pending and pending[entry.identity] ~= nil then return nil end
  local map = byIdentity(catalog)
  local titles = {}
  for _, identity in ipairs(cascade) do
    local other = map[identity]
    titles[#titles + 1] = other and titleOf(other) or identity
  end
  local lead = (entry.disabled == true) and "Turning this on also brings back "
    or "Turning this off also turns off "
  return lead .. table.concat(titles, ", ") .. "."
end

--- M.detail(ui, entry, catalog, cascade, pending) -> node
--- The detail block for one plugin, built from kit nodes. The heading is the title with the
--- version flush right, then the about facts, then the needs in short labelled groups, then the
--- cascade line when there is one. Every piece of text names a role and never a font or colour.
function M.detail(ui, entry, catalog, cascade, pending)
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
  blocks[#blocks + 1] = ui.text(M.words(entry, catalog, pending), "caption")
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

  local line = cascadeLine(entry, catalog, cascade, pending)
  if line then blocks[#blocks + 1] = ui.text(line, "caption", { wrap = true }) end

  return ui.stack(blocks, { gap = "m" })
end

return M
