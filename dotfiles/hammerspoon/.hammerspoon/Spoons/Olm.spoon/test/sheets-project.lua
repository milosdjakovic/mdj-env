-- The content model each leader cheat sheet would draw, written as lines, the projection behind
-- test/sheets.golden. Everything a sheet decides except pixels, its sections in order, each
-- section's title, fade and layout, and its rows with badge, label and whether an icon is drawn.
--
-- One sheet host draws every held leader since phase 4 of the keymap plan, and this reads that
-- host's own records rather than drawing anything. It is the one place the format is spelled,
-- shared by the live probe and by the offline run, so the two cannot drift.
--
-- The format is the one the two hosts it replaced wrote, kept byte for byte so the golden proves
-- the merge changed nothing. Two line families survive, chosen by the leader's name. The hyper
-- family is the section shape, used for any leader this file has no family for under its own name.
-- The window family is the group shape, which META keeps.
--
-- The section family. A leader's own sections are built once at configure and written as they
-- stand. A section a plugin supplies is asked again on every show, and its rows are the person's
-- data on this machine, the app toggler's apps that are installed here, split by which are
-- running. Any line about them would make the golden describe one machine, so a supplier is
-- written as the headers of the sections it answers, each title, fade and layout, and nothing
-- about its rows. Those are checked by eye, see test/README.md.
--
--   hyper  section  n  title  alpha  titleAlpha  layout
--   hyper  row      n  badge  label  icon
--   hyper  supplied n  title  alpha  titleAlpha  layout
--
-- The group family. One group per section, named as the host names it, and its rows in the order
-- the host keeps them, each with the predicate gating it.
--
--   window group   name
--   window row     n  badge  label  when
--
-- icon is image for a drawn picture and a dash for none. It is pure Lua and touches no hs global.

local obj = {}

local DASH = "-"

local function clean(s)
  if s == nil then return DASH end
  return (tostring(s):gsub("[\t\n]", " "))
end

local function num(v)
  if v == nil then return DASH end
  return tostring(v)
end

local function layout(section)
  if section.icons == true then return "icons" end
  if section.columns ~= nil or section.iconSize ~= nil then
    return "plain columns=" .. num(section.columns) .. " colWidth=" .. num(section.colWidth)
      .. " iconSize=" .. num(section.iconSize)
  end
  return DASH
end

local function iconText(v)
  if v == nil then return DASH end
  if type(v) == "string" then return clean(v) end
  return "image"
end

-- The family word each leader's lines are spelled with, and the shape that family takes.
local FAMILY = {
  hyper = { word = "hyper", shape = "section" },
  meta = { word = "window", shape = "group" },
}

local function sectionLines(word, record)
  local lines = {}
  for n, entry in ipairs(record.entries or {}) do
    if type(entry) == "table" then
      lines[#lines + 1] = table.concat({ word, "section", tostring(n), clean(entry.title),
        num(entry.alpha), num(entry.titleAlpha), layout(entry) }, "\t")
      for _, r in ipairs(entry.rows or {}) do
        lines[#lines + 1] = table.concat({ word, "row", tostring(n), clean(r.badge),
          clean(r.label), iconText(r.icon) }, "\t")
      end
    elseif type(entry) == "function" then
      local ok, supplied = pcall(entry)
      for _, section in ipairs(ok and type(supplied) == "table" and supplied or {}) do
        if type(section) == "table" then
          lines[#lines + 1] = table.concat({ word, "supplied", tostring(n), clean(section.title),
            num(section.alpha), num(section.titleAlpha), layout(section) }, "\t")
        end
      end
    end
  end
  return lines
end

local function groupLines(word, record)
  local lines = {}
  for _, entry in ipairs(record.entries or {}) do
    if type(entry) == "table" then
      lines[#lines + 1] = table.concat({ word, "group", clean(entry.title) }, "\t")
      for n, r in ipairs(entry.rows or {}) do
        lines[#lines + 1] = table.concat({ word, "row", tostring(n), clean(r.badge),
          clean(r.label), clean(r.when) }, "\t")
      end
    end
  end
  return lines
end

--- obj.lines(host) -> list of lines
--- host is the leader sheet host module, one record per leader that shows a sheet. Records are
--- written sorted by leader name, since a keycode is a machine fact and the name is not.
function obj.lines(host)
  local records = {}
  for _, record in ipairs(host:models()) do records[#records + 1] = record end
  table.sort(records, function(a, b) return tostring(a.name) < tostring(b.name) end)
  local lines = {}
  for _, record in ipairs(records) do
    local family = FAMILY[record.name] or { word = tostring(record.name), shape = "section" }
    local these = family.shape == "group" and groupLines(family.word, record) or sectionLines(family.word, record)
    for _, l in ipairs(these) do lines[#lines + 1] = l end
  end
  return lines
end

return obj
