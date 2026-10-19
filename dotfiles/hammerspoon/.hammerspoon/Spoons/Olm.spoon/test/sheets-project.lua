-- The content model each leader cheat sheet would draw, written as lines, the projection behind
-- test/sheets.golden. Everything a sheet decides except pixels, its sections in order, each
-- section's title, fade and layout, and its rows with badge, label and whether an icon is drawn.
--
-- Two sheets exist while the keymap plan runs, one per held leader, and this reads each host's
-- own fields rather than drawing anything. It is the one place the format is spelled, shared by
-- the live probe and by the offline run, so the two cannot drift.
--
-- The Hyper sheet. Its own sections are built once at configure and written as they stand. A
-- section a plugin supplies is asked again on every show, and its rows are the person's data on
-- this machine, the app toggler's apps that are installed here, split by which are running. Any
-- line about them would make the golden describe one machine, so a supplier is written as the
-- headers of the sections it answers, each title, fade and layout, and nothing about its rows.
-- Those are checked by eye, see test/README.md.
--
--   hyper  section  n  title  alpha  titleAlpha  layout
--   hyper  row      n  badge  label  icon
--   hyper  supplied n  title  alpha  titleAlpha  layout
--
-- The window sheet. One group per leader it reveals, named as the host names it, and its rows in
-- the order the host keeps them, each with the predicate gating it.
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

--- obj.hyper(sheet, glyphFor) -> list of lines
--- sheet is the Hyper cheat sheet host module, its entries built at configure.
function obj.hyper(sheet, glyphFor)
  local lines = {}
  for n, entry in ipairs(sheet._entries or {}) do
    if type(entry) == "table" then
      lines[#lines + 1] = table.concat({ "hyper", "section", tostring(n), clean(entry.title),
        num(entry.alpha), num(entry.titleAlpha), layout(entry) }, "\t")
      for _, r in ipairs(entry.rows or {}) do
        lines[#lines + 1] = table.concat({ "hyper", "row", tostring(n), clean(r.badge),
          clean(r.label), iconText(r.icon) }, "\t")
      end
    elseif type(entry) == "function" then
      local ok, supplied = pcall(entry)
      for _, section in ipairs(ok and type(supplied) == "table" and supplied or {}) do
        if type(section) == "table" then
          lines[#lines + 1] = table.concat({ "hyper", "supplied", tostring(n), clean(section.title),
            num(section.alpha), num(section.titleAlpha), layout(section) }, "\t")
        end
      end
    end
  end
  return lines
end

--- obj.window(sheet) -> list of lines
--- sheet is the window cheat sheet host module, its groups keyed by leader keycode. Groups are
--- written sorted by name, since a keycode is a machine fact and the name is what is drawn.
function obj.window(sheet)
  local groups = {}
  for _, group in pairs(sheet._byLeader or {}) do groups[#groups + 1] = group end
  table.sort(groups, function(a, b) return tostring(a.name) < tostring(b.name) end)
  local lines = {}
  for _, group in ipairs(groups) do
    lines[#lines + 1] = table.concat({ "window", "group", clean(group.name) }, "\t")
    for n, r in ipairs(group.rows or {}) do
      lines[#lines + 1] = table.concat({ "window", "row", tostring(n), clean(r.badge),
        clean(r.label), clean(r.when) }, "\t")
    end
  end
  return lines
end

--- obj.lines(hyperSheet, windowSheet, glyphFor) -> list of lines
function obj.lines(hyperSheet, windowSheet, glyphFor)
  local lines = {}
  if hyperSheet then for _, l in ipairs(obj.hyper(hyperSheet, glyphFor)) do lines[#lines + 1] = l end end
  if windowSheet then for _, l in ipairs(obj.window(windowSheet)) do lines[#lines + 1] = l end end
  return lines
end

return obj
