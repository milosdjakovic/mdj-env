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
-- init.lua, plus the tool registry itself and, since phase seven's fourth
-- packet, the assembled scope catalog QueryScope actually built from it. It
-- never reads hs.hotkey.getHotkeys, which the design records as blind to
-- almost everything this config actually binds.
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
    -- kind, phase eight's first packet, asked of the live wiring through
    -- spoon.ActionPanel:kindOf, the public door that carries its own unconfigured guard,
    -- rather than of a copy kept in this file, so what the golden records is what the
    -- composition root actually injected. Unlike ChordKey._keys and HyperKey._bindings, which
    -- have no public form at all, what an action classifies as is an ordinary question this
    -- module already answers for anyone asking, so it is asked through that door rather than
    -- through the private field behind it.
    local kind = spoon.ActionPanel and spoon.ActionPanel:kindOf(b.action)
    bindingLines[#bindingLines + 1] = string.format(
      "hypercontexts.binding context=%s key=%s mods=%s action=%s kind=%s when=%s chord=%s needs=%s description=%s",
      field(name), field(b.key), join(mods), field(b.action), field(kind), field(b.when),
      field(chord), field(b.needs), field(b.description))
  end
  table.sort(bindingLines)
  for _, l in ipairs(bindingLines) do add(l) end
end

-- The verb list per context, phase eight's first packet, asked of the live module rather than
-- recomputed here, so this measures what spoon.ActionPanel:verbsIn actually answers for the
-- same context.bindings the section above already walked, contextNames and byName reused
-- rather than read a second time. This is deliberately not filtered by needs or by a live
-- predicate, since verbsIn itself knows neither, and a later packet that adds those filters to
-- the panel must not read this section as stale and change it, it measures the declarations
-- rather than a moment.
local verbsByContext = {}
for _, name in ipairs(contextNames) do
  local ctx = byName[name]
  verbsByContext[name] = spoon.ActionPanel and spoon.ActionPanel:verbsIn(ctx.bindings or {}) or {}
end
add("registry actionpanel count=" .. #contextNames)
for _, name in ipairs(contextNames) do
  add(string.format("actionpanel.context name=%s verbCount=%s", field(name), field(#verbsByContext[name])))
end
local verbLines = {}
for _, name in ipairs(contextNames) do
  for _, b in ipairs(verbsByContext[name]) do
    local mods = {}
    for _, m in ipairs(b.mods or {}) do mods[#mods + 1] = m end
    table.sort(mods)
    verbLines[#verbLines + 1] = string.format(
      "actionpanel.verb context=%s key=%s mods=%s action=%s description=%s",
      field(name), field(b.key), join(mods), field(b.action), field(b.description))
  end
end
table.sort(verbLines)
for _, l in ipairs(verbLines) do add(l) end

-- The choosers registry in init.lua. It is a local table in the composition
-- root, never handed to anything global, so there is no live handle to read it
-- through. The honest way to read it is the way it is written, as one literal
-- line in this config's own init.lua, so this reads that line as text rather
-- than guessing at a live table this file was never given. That keeps the
-- listing a fingerprint of which expressions are registered and in what order,
-- which is what the surface actually is, rather than a reading of live table
-- state nothing here has a handle on anyway.
--
-- Phase seven's second packet moved nine of the twelve entries into the tool
-- registry, so the line this reads is now the call to registry.surfaces rather
-- than a bare table literal, and the pattern below is pointed at that call
-- instead. What it captures is unchanged in kind, one entry per line below,
-- read as text and not as live state, now a mix of the nine tool names the
-- registry resolves and the three expressions that stay outside it.
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
local choosersLine = initSource:match("local%s+choosers%s*=%s*registry%.surfaces%s*%(%s*{(.-)}")
if not choosersLine then
  error("inventory, could not find the choosers registry call in init.lua, the pattern needs updating")
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

-- spoon.Olm.registry itself, read live rather than as text, since the composition root
-- now publishes the instance it built. One line per registered tool with its active
-- flag and, since active alone cannot see one going missing, whether it declared a
-- surface, whether it declared hosted, and, since phase seven's fourth packet, whether
-- it declared a scope, all presence rather than a resolved value, matching what all()
-- itself reports, so this stays a fingerprint of what each descriptor declared rather
-- than a second opinion on what the live surface or scope answers at the moment of the
-- dump. scope beside hosted is the cross check that packet adds, a tool that is hosted
-- with no scope behind it reads plainly as hosted=true scope=false in this committed
-- file, which is legitimate for a tool whose scope registers only under a condition,
-- emoji today, and stable rather than a warning nobody is watching for. See
-- Spoons/Olm.spoon/CLAUDE.md's Registry section for why a warning was considered and
-- rejected.
local registryTools = spoon.Olm.registry and spoon.Olm.registry.all() or {}
local toolLines = {}
for _, tool in ipairs(registryTools) do
  toolLines[#toolLines + 1] = string.format(
    "tools.entry name=%s active=%s surface=%s hosted=%s scope=%s",
    field(tool.name), field(tool.active), field(tool.surface), field(tool.hosted), field(tool.scope))
end
table.sort(toolLines)
add("registry tools count=" .. #registryTools)
for _, l in ipairs(toolLines) do add(l) end

-- spoon.QueryScope:catalog(), the assembled scope list actually built, which is not the
-- same fact tools.entry's scope field records. That field reports whether a tool's own
-- descriptor declares a scope, and a spec entry that resolves to nothing, a misspelled
-- name chief among the ways that happens, is skipped in silence by design, so a
-- descriptor can read scope=true while the scope it describes never made it into the
-- live list at all. Nothing before this packet measured the assembled list, only what
-- was declared, and this section is what closes that gap. One line per scope actually
-- entered, its name and its aliases, sorted by name for a stable snapshot. Aliases
-- matter as much as the name, since QueryScope gives a contested word to whichever
-- scope claims it first, so the order the root's spec lists scopes in decides who keeps
-- a shared alias, and a mistake in that order shows up here as an alias moving from one
-- scope's line to another's rather than as anything disappearing outright.
local scopeCatalog = (spoon.QueryScope and spoon.QueryScope:catalog()) or {}
local scopeLines = {}
for _, s in ipairs(scopeCatalog) do
  local aliases = {}
  for _, a in ipairs(s.aliases or {}) do aliases[#aliases + 1] = a end
  scopeLines[#scopeLines + 1] = string.format(
    "scopes.entry name=%s aliases=%s", field(s.name), join(aliases))
end
table.sort(scopeLines)
add("registry scopes count=" .. #scopeCatalog)
for _, l in ipairs(scopeLines) do add(l) end

-- The launcher's own command rows, read live through spoon.Launcher:rowsOfKind for the
-- special kind, which is every row a registered tool or one of its commands builds.
-- Phase seven's third packet moves the presentation data behind these rows, the
-- category, the glyph, the detail, the keywords, and the chord, off the launcher and
-- onto the registry descriptor, and this section is the instrumentation that packet
-- commits first, before anything moves, so a row that vanished in the fold or came back
-- with a changed subtitle fails this snapshot rather than passing every other gate this
-- config has. The subtitle is recorded whole rather than summarised, since it is the
-- part most likely to break quietly, carrying the chord label, the category, and the
-- alias hint together. Sorted by name so the snapshot is stable regardless of the order
-- the rows were built in.
local launcherRows = spoon.Launcher and spoon.Launcher:rowsOfKind("special") or {}
local rowLines = {}
for _, row in ipairs(launcherRows) do
  rowLines[#rowLines + 1] = string.format(
    "launcherrows.entry name=%s subTitle=%s",
    field(row.item and row.item.name), field(row.subTitle))
end
table.sort(rowLines)
add("registry launcherrows count=" .. #launcherRows)
for _, l in ipairs(rowLines) do add(l) end

-- spoon.HyperKey._bindings, phase seven's fifth packet. Nothing before this measured a
-- binding at all, so the snapshot recorded the two physical leader keys and never which
-- letter reaches which tool, and a deleted bind line would have passed every gate this
-- repository had. Read live, keyed by key code, which is the private field the atom itself
-- keeps its whole binding table in, the same kind of reach this file already makes into
-- ChordKey._keys and HyperCheatSheet's own models above. Sorted by key code since the table
-- carries no order of its own. Per key this records how many bindings sit on it in total and
-- how many of those are base bindings, meaning the ones carrying no `when`, since a base
-- binding is what a plain Hyper press to that key resolves to while no modal context owns
-- Hyper, and a base binding vanishing is exactly the shape a deleted chord would take.
local hyperKeyBindings = (spoon.HyperKey and spoon.HyperKey._bindings) or {}
local hyperKeyCodes = {}
for code in pairs(hyperKeyBindings) do
  hyperKeyCodes[#hyperKeyCodes + 1] = code
end
table.sort(hyperKeyCodes)
add("registry hyperkey count=" .. #hyperKeyCodes)
for _, code in ipairs(hyperKeyCodes) do
  local list = hyperKeyBindings[code]
  local base = 0
  for _, b in ipairs(list) do
    if not b.when then base = base + 1 end
  end
  add(string.format("hyperkey.key code=%s total=%s base=%s", field(code), field(#list), field(base)))
end

-- hs.hotkey.getHotkeys(), the global hotkey table Hammerspoon itself keeps, which is the one
-- registry that sees the two global combinations that never touch the leader at all, append
-- copy and paste next. Sorted by msg, the printable combo each hotkey answers with, rather than
-- trusting the table's own order, which is registration order and no more stable a fingerprint
-- than the leader's own binding table would be if read unsorted.
local hotkeys = hs.hotkey.getHotkeys() or {}
local hotkeyLines = {}
for _, h in ipairs(hotkeys) do
  hotkeyLines[#hotkeyLines + 1] = string.format(
    "hotkeys.entry msg=%s enabled=%s", field(h.msg), field(h.enabled))
end
table.sort(hotkeyLines)
add("registry hotkeys count=" .. #hotkeys)
for _, l in ipairs(hotkeyLines) do add(l) end

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
