-- The inventory dump. inventory.sh loads this file through dofile inside a live
-- Hammerspoon, and this is the only Lua that ever runs there for this tool. It
-- takes no argument and its return value is not read by anything, since the only
-- door back to the caller allowed by the packet is one dofile call and nothing
-- else crossing the shell boundary. So every choice this file needs to make,
-- where to write its answer and what to read, is made in here rather than passed
-- in from outside.
--
-- What it reads is exactly the five registries the design names as the honest
-- source of this config's binding surface, the loaded spoon table, the chord
-- tree in ChordKey._keys, the cheat sheet models in HyperCheatSheet, the
-- hyperContexts bindings in config/keys.lua, and the choosers registry in
-- init.lua. It never reads hs.hotkey.getHotkeys, which the design records as
-- blind to almost everything this config actually binds.
--
-- Every listing below is sorted before it is written, and nothing here is a
-- timestamp, a memory address, or a table identity, so two runs against the same
-- tree produce the exact same bytes. The chord tree is the one place this took
-- real care, since ChordKey keeps live hold state alongside its configuration in
-- the same entry, active, used, shown, downTime, holdTimer, and so on, and that
-- state depends on whether a key happens to be physically held at the moment of
-- the dump rather than on anything this config decided. Only the configuration a
-- key was registered with is printed, never that runtime state.

local lines = {}
local function add(line)
  lines[#lines + 1] = line
end

-- Joins a list of strings the caller already sorted, so this never introduces an
-- ordering of its own, and answers a single dash for an empty list, the same
-- convention field uses below, so an absent set of modifiers reads the same way
-- as any other absent value rather than as a blank that could be mistaken for
-- one space or one empty word.
local function join(list, sep)
  if #list == 0 then return "-" end
  return table.concat(list, sep or "+")
end

-- Renders a scalar the way every field below wants it, and an absent one as a
-- single dash, so a missing field reads the same everywhere rather than as an
-- empty string that is easy to mistake for present but blank.
local function field(v)
  if v == nil then return "-" end
  return tostring(v)
end

-- The loaded spoon table.
local spoonNames = {}
for name in pairs(spoon) do
  spoonNames[#spoonNames + 1] = name
end
table.sort(spoonNames)
add("registry spoon count=" .. #spoonNames)
for _, name in ipairs(spoonNames) do
  add("spoon " .. name)
end

-- The chord tree, ChordKey._keys.
local chordCodes = {}
local ck = (spoon.ChordKey and spoon.ChordKey._keys) or {}
for code in pairs(ck) do
  chordCodes[#chordCodes + 1] = code
end
table.sort(chordCodes)
add("registry chordkey count=" .. #chordCodes)
for _, code in ipairs(chordCodes) do
  local k = ck[code]
  add(string.format(
    "chordkey key=%s holdDelay=%s tapThreshold=%s passthrough=%s onTap=%s onHold=%s onHoldEnd=%s onKey=%s",
    field(code), field(k.holdDelay), field(k.tapThreshold), field(k.passthrough),
    field(k.onTap ~= nil), field(k.onHold ~= nil), field(k.onHoldEnd ~= nil), field(k.onKey ~= nil)))
end

-- The cheat sheet models, the pure data HyperCheatSheet was configured with,
-- apps and toggles, plus items, what it precomputed from them. Icons are left
-- out of the item line on purpose, since an hs.image carries no stable text form
-- of its own, only an address.
local hcs = spoon.HyperCheatSheet or {}

local appNames = {}
for name in pairs(hcs._apps or {}) do
  appNames[#appNames + 1] = name
end
table.sort(appNames)
add("registry hypercheatsheet.apps count=" .. #appNames)
for _, name in ipairs(appNames) do
  add("hypercheatsheet.app name=" .. name .. " bundleID=" .. field((hcs._apps or {})[name]))
end

local toggleLines = {}
for _, t in ipairs(hcs._toggles or {}) do
  local mods = {}
  for _, m in ipairs(t.modifiers or {}) do mods[#mods + 1] = m end
  table.sort(mods)
  toggleLines[#toggleLines + 1] = string.format(
    "hypercheatsheet.toggle app=%s key=%s mods=%s url=%s",
    field(t.app), field(t.key), join(mods), field(t.url))
end
table.sort(toggleLines)
add("registry hypercheatsheet.toggles count=" .. #toggleLines)
for _, l in ipairs(toggleLines) do add(l) end

local itemLines = {}
for _, it in ipairs(hcs._items or {}) do
  itemLines[#itemLines + 1] = string.format(
    "hypercheatsheet.item key=%s name=%s bundleID=%s",
    field(it.key), field(it.name), field(it.bundleID))
end
table.sort(itemLines)
add("registry hypercheatsheet.items count=" .. #itemLines)
for _, l in ipairs(itemLines) do add(l) end

-- The hyperContexts bindings, read from config/keys.lua through require, which
-- answers from the module cache this live config already populated rather than
-- reading the file a second time.
local keysConfig = require("config.keys")
local contexts = keysConfig.hyperContexts or {}

local contextNames = {}
local byName = {}
for _, ctx in ipairs(contexts) do
  contextNames[#contextNames + 1] = ctx.name
  byName[ctx.name] = ctx
end
table.sort(contextNames)
add("registry hypercontexts count=" .. #contextNames)
for _, name in ipairs(contextNames) do
  local ctx = byName[name]
  add(string.format(
    "hypercontexts.context name=%s when=%s priority=%s bindingCount=%s",
    field(ctx.name), field(ctx.when), field(ctx.priority), field(#(ctx.bindings or {}))))
end
for _, name in ipairs(contextNames) do
  local ctx = byName[name]
  local bindingLines = {}
  for _, b in ipairs(ctx.bindings or {}) do
    local mods = {}
    for _, m in ipairs(b.mods or {}) do mods[#mods + 1] = m end
    table.sort(mods)
    local chord = b.chord
    if chord == nil then chord = true end
    bindingLines[#bindingLines + 1] = string.format(
      "hypercontexts.binding context=%s key=%s mods=%s action=%s when=%s chord=%s needs=%s description=%s",
      field(name), field(b.key), join(mods), field(b.action), field(b.when),
      field(chord), field(b.needs), field(b.description))
  end
  table.sort(bindingLines)
  for _, l in ipairs(bindingLines) do add(l) end
end

-- The choosers registry in init.lua. It is a local table in the composition
-- root, never handed to anything global, so there is no live handle to read it
-- through. The honest way to read it is the way it is written, as one literal
-- line in this config's own init.lua, so this reads that line as text rather
-- than guessing at a live table this file was never given. That keeps the
-- listing a fingerprint of which expressions are registered and in what order,
-- which is what the surface actually is, rather than a reading of live table
-- state nothing here has a handle on anyway.
local function readFile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("a")
  f:close()
  return content
end

local initPath = hs.configdir .. "/init.lua"
local initSource = readFile(initPath)
if not initSource then
  error("inventory, could not read this config's own init.lua at " .. initPath)
end
local choosersLine = initSource:match("local%s+choosers%s*=%s*{(.-)}")
if not choosersLine then
  error("inventory, could not find the choosers registry line in init.lua, the pattern needs updating")
end
local chooserEntries = {}
for entry in choosersLine:gmatch("[^,]+") do
  local trimmed = entry:match("^%s*(.-)%s*$")
  if trimmed ~= "" then
    chooserEntries[#chooserEntries + 1] = trimmed
  end
end
table.sort(chooserEntries)
add("registry choosers count=" .. #chooserEntries)
for _, e in ipairs(chooserEntries) do
  add("choosers.entry " .. e)
end

-- Write the whole dump to one fixed file outside the watched config tree, the
-- same reasoning BrowserTabs' own test channel already follows, since a file
-- written inside the config directory would trigger a reload on every run. This
-- is the only door back to inventory.sh, the dofile call itself carries no
-- argument and its return value is not read by anything.
local outPath = os.getenv("HOME") .. "/Library/Caches/hammerspoon-inventory/snapshot.txt"
local out = io.open(outPath, "w")
if not out then
  error("inventory, could not open " .. outPath .. " for writing, does its directory exist")
end
out:write(table.concat(lines, "\n"))
out:write("\n")
out:close()
