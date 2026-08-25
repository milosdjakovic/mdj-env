-- The inventory dump. inventory.sh loads this file through dofile inside a live
-- Hammerspoon, and this is the only Lua that ever runs there for this tool. It
-- takes no argument and its return value is not read by anything, since the only
-- door back to the caller allowed by the packet is one dofile call and nothing
-- else crossing the shell boundary. So every choice this file needs to make,
-- where to write its answer and what to read, is made in here rather than passed
-- in from outside.
--
-- What it actually reads, now that the config folded from many separate spoons
-- into one bundled Olm spoon, is the loaded spoon table, the chord key and hyper
-- key atoms reached through spoon.Olm.lib, the launcher, action panel, query
-- scope, and hyper cheat sheet hosts each reached through spoon.Olm module, the
-- hyperContexts bindings in config/keys.lua, the tool registry published at
-- spoon.Olm.registry, the assembled scope catalog the query scope host actually
-- built from it, and hs.hotkey.getHotkeys, the global hotkey table Hammerspoon
-- itself keeps for the two combinations that never touch a leader at all.
--
-- Every one of those sources resolves through the must helper defined next to
-- join and field. Most are resolved together in one block right below, since
-- reaching them needs the loaded core spoon first. hs.hotkey.getHotkeys needs
-- nothing else to reach, so its own must sits at its point of use near the
-- bottom instead, the same rule applied where the reach actually happens rather
-- than moved early for no reason. An unreachable source is an error at its own
-- must, never an empty section further down, because a snapshot that cannot
-- tell nothing registered apart from I could not look is worse than no
-- snapshot at all, and answering silently for a source nobody could reach any
-- more is exactly the rot this rewrite exists to end.
--
-- Every listing below is sorted before it is written, and nothing here is a
-- timestamp, a memory address, or a table identity, so two runs against the same
-- tree produce the exact same bytes. The chord tree is the one place this took
-- real care, since the chord key atom keeps live hold state alongside its
-- configuration in the same entry, active, used, shown, downTime, holdTimer, and
-- so on, and that state depends on whether a key happens to be physically held at
-- the moment of the dump rather than on anything this config decided. Only the
-- configuration a key was registered with is printed, never that runtime state.

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

-- Fails loudly the moment a source cannot be reached, rather than letting a
-- caller fall back to an empty table that prints exactly like a source that was
-- reached and genuinely holds nothing. A snapshot that cannot tell nothing
-- registered apart from I could not look is worse than no snapshot at all, and
-- the silent guards this replaces, the X and X colon method or empty table shape
-- that used to sit at every reach in this file, are exactly how fourteen of its
-- sixteen sections rotted unnoticed once the globals they reached for were
-- deleted. Errors in the file's own convention, so a failure here reads the same
-- way as the other errors already below.
local function must(value, description)
  if value == nil then
    error("inventory, could not reach " .. description)
  end
  return value
end

-- Every source this file reads, resolved exactly once, right here, so a host
-- that never started or a name the composition root no longer wires fails the
-- run at this line rather than as an empty section well below it.
local olm = must(spoon.Olm, "spoon.Olm, the loaded core spoon")
local launcher = must(olm:module("launcher"), "the launcher host through spoon.Olm module")
local actionPanel = must(olm:module("actionpanel"), "the action panel host through spoon.Olm module")
local queryScope = must(olm:module("queryscope"), "the query scope host through spoon.Olm module")
local cheatSheet = must(olm:module("hypercheatsheet"), "the hyper cheat sheet host through spoon.Olm module")
local chordKey = must(olm.lib and olm.lib.chordkey, "the chord key atom at spoon.Olm.lib.chordkey")
local hyperKey = must(olm.lib and olm.lib.hyperkey, "the hyper key atom at spoon.Olm.lib.hyperkey")
local registry = must(olm.registry, "spoon.Olm.registry, the tool registry the composition root published")

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

-- The chord tree, read from the chord key atom's own _keys field at
-- spoon.Olm.lib.chordkey. A host that exists but was never configured, so this
-- field stayed nil, fails loudly here rather than dumping an empty section.
local chordCodes = {}
local chordKeys = must(chordKey._keys, "chordkey._keys, the chord tree the chord key atom was configured with")
for code in pairs(chordKeys) do
  chordCodes[#chordCodes + 1] = code
end
table.sort(chordCodes)
add("registry chordkey count=" .. #chordCodes)
for _, code in ipairs(chordCodes) do
  local k = chordKeys[code]
  add(string.format(
    "chordkey key=%s holdDelay=%s tapThreshold=%s passthrough=%s onTap=%s onHold=%s onHoldEnd=%s onKey=%s",
    field(code), field(k.holdDelay), field(k.tapThreshold), field(k.passthrough),
    field(k.onTap ~= nil), field(k.onHold ~= nil), field(k.onHoldEnd ~= nil), field(k.onKey ~= nil)))
end

-- The cheat sheet models, the pure data the hyper cheat sheet host was
-- configured with, apps and toggles, plus items, what it precomputed from them.
-- Icons are left out of the item line on purpose, since an hs.image carries no
-- stable text form of its own, only an address.
local hcsApps = must(cheatSheet._apps, "hypercheatsheet._apps, the app roster the hyper cheat sheet host was configured with")
local hcsToggles = must(cheatSheet._toggles, "hypercheatsheet._toggles, the toggle list the hyper cheat sheet host was configured with")
local hcsItems = must(cheatSheet._items, "hypercheatsheet._items, the items the hyper cheat sheet host precomputed")

local appNames = {}
for name in pairs(hcsApps) do
  appNames[#appNames + 1] = name
end
table.sort(appNames)
add("registry hypercheatsheet.apps count=" .. #appNames)
for _, name in ipairs(appNames) do
  add("hypercheatsheet.app name=" .. name .. " bundleID=" .. field(hcsApps[name]))
end

local toggleLines = {}
for _, t in ipairs(hcsToggles) do
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
for _, it in ipairs(hcsItems) do
  itemLines[#itemLines + 1] = string.format(
    "hypercheatsheet.item key=%s name=%s bundleID=%s",
    field(it.key), field(it.name), field(it.bundleID))
end
table.sort(itemLines)
add("registry hypercheatsheet.items count=" .. #itemLines)
for _, l in ipairs(itemLines) do add(l) end

-- The hyperContexts bindings, read from config/keys.lua through require, which
-- answers from the module cache this live config already populated rather than
-- reading the file a second time. This is a source exactly like the module doors
-- above, since it feeds five sections below, hypercontexts, actionpanel,
-- panelrows, hostedrows, and the counts each one prints, so a renamed or deleted
-- hyperContexts key would otherwise leave all five silently empty rather than
-- failing where the rename actually happened.
local keysConfig = require("config.keys")
local contexts = must(keysConfig.hyperContexts, "hyperContexts, the table in config/keys.lua")

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
    -- kind, phase eight's first packet, asked of the live wiring through the action
    -- panel host's own kindOf, the public door that carries its own unconfigured guard,
    -- rather than of a copy kept in this file, so what the golden records is what the
    -- composition root actually injected. Unlike the chord key and hyper key atoms,
    -- reached through spoon.Olm.lib because Olm documents that table as never having
    -- been a boundary, what an action classifies as is an ordinary question this
    -- module already answers for anyone asking, so it is asked through that public
    -- door rather than through a private field.
    local kind = actionPanel:kindOf(b.action)
    bindingLines[#bindingLines + 1] = string.format(
      "hypercontexts.binding context=%s key=%s mods=%s action=%s kind=%s when=%s chord=%s needs=%s description=%s",
      field(name), field(b.key), join(mods), field(b.action), field(kind), field(b.when),
      field(chord), field(b.needs), field(b.description))
  end
  table.sort(bindingLines)
  for _, l in ipairs(bindingLines) do add(l) end
end

-- The verb list per context, phase eight's first packet, asked of the live action
-- panel host rather than recomputed here, so this measures what its own verbsIn
-- actually answers for the same context.bindings the section above already walked,
-- contextNames and byName reused rather than read a second time. This is deliberately
-- not filtered by needs or by a live predicate, since verbsIn itself knows neither, and
-- a later packet that adds those filters to the panel must not read this section as
-- stale and change it, it measures the declarations rather than a moment.
local verbsByContext = {}
for _, name in ipairs(contextNames) do
  local ctx = byName[name]
  verbsByContext[name] = actionPanel:verbsIn(ctx.bindings or {})
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

-- The panel's own row list per context, phase eight's second packet, asked of the live
-- action panel host through its own rowsFor rather than recomputed here, the same public
-- door kindOf and verbsIn above already carry, so this measures exactly what the panel's
-- toggle would show through the composition root's own rowsFor, through the exact same
-- call, rather than a second opinion built in this file. Unlike the actionpanel section
-- above, this section DOES read the root's bindingApplies filter, since rowsFor applies
-- it, and it always carries a Back row the panel itself builds, so a context with no
-- verbs at all still answers one row rather than none. contextNames and byName are
-- reused rather than read a second time, though rowsFor only needs the name, never
-- ctx.bindings itself.
--
-- glyph joined this line in phase eight's third packet, alongside a glyph on every verb row in
-- config/keys.lua, so a glyph going missing from a binding is a diff here rather than something
-- noticed by eye months later. Back leading the list rather than trailing it, phase eight's
-- third packet too, is NOT visible in this section, since panelRowLines is sorted before it is
-- written, the same as every other listing in this file, so ordering is deliberately not part
-- of what this section proves.
local panelRowsByContext = {}
for _, name in ipairs(contextNames) do
  panelRowsByContext[name] = actionPanel:rowsFor(name)
end
add("registry panelrows count=" .. #contextNames)
for _, name in ipairs(contextNames) do
  add(string.format("panelrows.context name=%s rowCount=%s", field(name), field(#panelRowsByContext[name])))
end
local panelRowLines = {}
for _, name in ipairs(contextNames) do
  for _, r in ipairs(panelRowsByContext[name]) do
    panelRowLines[#panelRowLines + 1] = string.format(
      "panelrows.row context=%s action=%s title=%s chord=%s glyph=%s",
      field(name), field(r.action), field(r.title), field(r.chord), field(r.glyph))
  end
end
table.sort(panelRowLines)
for _, l in ipairs(panelRowLines) do add(l) end

-- The hosted row list per context, phase eight's fourth packet, asked of the live action
-- panel host through the exact same rowsFor door the panelrows section above uses. The
-- second argument is no longer a flag, it is the scope's own verbs table resolved by the
-- caller, so this file resolves it through registry.scopeFor exactly as the composition
-- root's own seam does, rather than passing the retired true that now crashes inside
-- hints once it gets indexed as though it were a verbs table. This is the only measurement
-- of the hosted path that exists, the one place a scope's verb could quietly disappear or a
-- chord could quietly stop being qualified with nothing else catching it.
--
-- Only file search answers anything beyond Back today, since it is the only tool a scope
-- declares verbs on, so this section is mostly Back rows and one interesting entry, and that
-- is exactly what it should be. contextNames and byName are reused rather than read again,
-- though rowsFor only needs the name here too, never ctx.bindings itself. A context with no
-- scope at all resolves an empty table, which keeps the old measurement, such a context
-- answers Back alone.
--
-- closes joins the row line here too, the fix beside this one, since whether a verb closes
-- the list it ran against was invisible in every direction before it, and a snapshot recording
-- the verb without recording that property would leave a future flip of it just as silent as
-- the defect that prompted adding it. field(nil) renders the dash the Back row already answers
-- for action, title, and chord, so a row with no closes at all, the Back row, reads no
-- differently for this field than for any other it does not carry.
local hostedRowsByContext = {}
for _, name in ipairs(contextNames) do
  local scope = registry.scopeFor(name)
  hostedRowsByContext[name] = actionPanel:rowsFor(name, (scope and scope.verbs) or {})
end
add("registry hostedrows count=" .. #contextNames)
for _, name in ipairs(contextNames) do
  add(string.format("hostedrows.context name=%s rowCount=%s", field(name), field(#hostedRowsByContext[name])))
end
local hostedRowLines = {}
for _, name in ipairs(contextNames) do
  for _, r in ipairs(hostedRowsByContext[name]) do
    hostedRowLines[#hostedRowLines + 1] = string.format(
      "hostedrows.row context=%s action=%s title=%s chord=%s glyph=%s closes=%s",
      field(name), field(r.action), field(r.title), field(r.chord), field(r.glyph), field(r.closes))
  end
end
table.sort(hostedRowLines)
for _, l in ipairs(hostedRowLines) do add(l) end

-- How many instances decorate has actually wrapped, asked of the live action panel host
-- through the small public door built for exactly this, rather than trusted from the fact
-- that config/keys.lua and the panelrows section above both look right. Neither of those
-- proves the decorate seam ever ran on a given chooser, only that it would answer correctly if
-- it had, and a chooser built before Chooser.configure installed that seam, or one that stopped
-- going through the Chooser facade at all, would leave the panel silently dead on it with every
-- other line in this file still reading exactly as if nothing were wrong. This reads twelve
-- today, one per context, and would read fewer the moment that stopped being true.
add("registry actionpaneldecorated count=" .. actionPanel:decoratedCount())

-- The choosers registry section that used to live here read one literal line in
-- init.lua as text, local choosers = registry.surfaces, since that line was once
-- the entire surface. That line no longer exists, the surface list is now
-- computed from plan order inside the composition root and held privately,
-- deliberately, so there is nothing sanctioned left to read there any more.
-- Fingerprinting the private internals that replaced it would only rot again the
-- next time the root reorganizes, so this section is deleted rather than pointed
-- at a new private shape, and this comment records why rather than leaving the
-- gap unexplained.

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
local registryTools = registry.all()
local toolLines = {}
for _, tool in ipairs(registryTools) do
  toolLines[#toolLines + 1] = string.format(
    "tools.entry name=%s active=%s surface=%s hosted=%s scope=%s",
    field(tool.name), field(tool.active), field(tool.surface), field(tool.hosted), field(tool.scope))
end
table.sort(toolLines)
add("registry tools count=" .. #registryTools)
for _, l in ipairs(toolLines) do add(l) end

-- The query scope host's own catalog(), the assembled scope list actually built, which is
-- not the same fact tools.entry's scope field records. That field reports whether a tool's
-- own descriptor declares a scope, and a spec entry that resolves to nothing, a misspelled
-- name chief among the ways that happens, is skipped in silence by design, so a
-- descriptor can read scope=true while the scope it describes never made it into the
-- live list at all. Nothing before this packet measured the assembled list, only what
-- was declared, and this section is what closes that gap. One line per scope actually
-- entered, its name and its aliases, sorted by name for a stable snapshot. Aliases
-- matter as much as the name, since the query scope host gives a contested word to
-- whichever scope claims it first, so the order the root's spec lists scopes in decides
-- who keeps a shared alias, and a mistake in that order shows up here as an alias moving
-- from one scope's line to another's rather than as anything disappearing outright.
local scopeCatalog = queryScope:catalog()
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

-- The launcher host's own command rows, read live through its own rowsOfKind for the
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
local launcherRows = launcher:rowsOfKind("special")
local rowLines = {}
for _, row in ipairs(launcherRows) do
  rowLines[#rowLines + 1] = string.format(
    "launcherrows.entry name=%s subTitle=%s",
    field(row.item and row.item.name), field(row.subTitle))
end
table.sort(rowLines)
add("registry launcherrows count=" .. #launcherRows)
for _, l in ipairs(rowLines) do add(l) end

-- The hyper key atom's own _bindings field, reached through spoon.Olm.lib.hyperkey,
-- phase seven's fifth packet. Nothing before this measured a binding at all, so the
-- snapshot recorded the two physical leader keys and never which letter reaches which
-- tool, and a deleted bind line would have passed every gate this repository had. Read
-- live, keyed by key code, which is the private field the atom itself keeps its whole
-- binding table in, the same kind of reach this file already makes into the chord key
-- atom's own _keys field and the hyper cheat sheet host's own models above. Sorted by
-- key code since the table carries no order of its own. Per key this records how many
-- bindings sit on it in total and how many of those are base bindings, meaning the ones
-- carrying no `when`, since a base binding is what a plain Hyper press to that key
-- resolves to while no modal context owns Hyper, and a base binding vanishing is exactly
-- the shape a deleted chord would take.
local hyperKeyBindings = must(hyperKey._bindings, "hyperkey._bindings, the binding table the hyper key atom was configured with")
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
-- than the leader's own binding table would be if read unsorted. Wrapped in must right here
-- rather than in the top block, since this source needs no host and no lib to reach, only the
-- call itself, and an unexpected nil here would otherwise print a zero count section
-- indistinguishable from a machine that genuinely has no hotkeys.
local hotkeys = must(hs.hotkey.getHotkeys(), "hs.hotkey.getHotkeys, the global hotkey table Hammerspoon itself keeps")
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
