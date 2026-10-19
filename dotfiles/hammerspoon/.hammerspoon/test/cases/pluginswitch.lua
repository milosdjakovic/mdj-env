-- Unit case for the one plugin switch, phase five of the core split. A plugin is switched off by
-- a false entry in config/plugins.lua or by an identity a settings page saved, and the union of
-- the two decides, before anything loads, which plugins the loader never runs and which the plan
-- reports as a choice rather than a failure.
--
-- Everything here drives the real code. lib/pluginswitch.lua merges and answers the four root
-- words, lib/plugins.lua reads the real manifests off this checkout and answers which plugins go
-- off with a switched off one, and lib/resolve.lua plans over them. Nothing is loaded beyond the
-- manifests, nothing is written to hs.settings, and no reload is asked for, the writer and the
-- store being recorders handed in exactly where the root hands in the real ones.
--
-- What is asserted. The merge of a config false with the saved set, and which wins the lock. A
-- host refused from either source. A switched off plugin absent from what the loader is handed.
-- The window manager taking window size off with it, reported as a choice naming the window
-- manager rather than as a block, and the dry run cascade a settings page asks answering the
-- same thing both ways. A plugin that only optionally uses a switched off one loading with
-- nothing said, while the same need naming a plugin that does not exist is still reported, so
-- the silence is the switch's and not a check that stopped looking. Staging that writes nothing
-- and is cleared by toggling back, a preview and catalog that show the cascade of what is staged,
-- one save of the whole staged set with the line said after it, and the resume note written
-- once and taken once.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local spoonDir = caseDir .. "/../../Spoons/Olm.spoon/"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  elseif detail then
    print("FAIL " .. description .. ", " .. detail)
  else
    print("FAIL " .. description)
  end
end

local function eq(description, got, want)
  check(description, got == want, "wanted " .. tostring(want) .. ", got " .. tostring(got))
end

local function load(rel)
  local chunk, err = loadfile(spoonDir .. rel)
  if not chunk then error("could not load " .. rel .. ", " .. tostring(err)) end
  return chunk()
end

local function has(list, value)
  for _, item in ipairs(list or {}) do if item == value then return true end end
  return false
end

local switch = load("lib/pluginswitch.lua")
local plugins = load("lib/plugins.lua")
local resolveLib = load("lib/resolve.lua")
local resolver = resolveLib.new({ plugins = plugins, defaults = load("lib/defaults.lua"),
  surface = load("lib/surface.lua") })

-- The real set, plugins and hosts, read the way the composition root reads them.
local pluginRoot = spoonDir .. "plugins"
local manifests, _, directories = plugins.readAll({ pluginRoot, spoonDir .. "host" }, nil)
local function isSwitchable(identity)
  local path = directories[identity]
  return path ~= nil and path:sub(1, #pluginRoot + 1) == pluginRoot .. "/"
end
local function known(identity) return manifests[identity] ~= nil end

check("the real set holds the window manager, window size, vpn and the launcher host",
  manifests.windowmanager ~= nil and manifests.windowsize ~= nil and manifests.vpn ~= nil
    and manifests.launcher ~= nil)
check("a plugin under plugins is switchable and a host is not",
  isSwitchable("vpn") and not isSwitchable("launcher"))

-- The merge. vpn is off in config and also saved, tmuxSessions only saved, the launcher written
-- false in config, the stage saved, and one saved word naming nothing.
local entries = { vpn = false, launcher = false, emoji = { key = "x" } }
local saved = { "tmuxSessions", "vpn", "stage", "nosuchplugin" }
local disabled, lockedBy, refused = switch.merge({ entries = entries, saved = saved,
  switchable = isSwitchable, known = known })

check("a config false is in the disabled set", disabled.vpn == true)
check("a saved identity is in the disabled set", disabled.tmuxSessions == true)
eq("config wins the lock when the same plugin is also saved", lockedBy.vpn, "config")
eq("a plugin only saved carries no lock", lockedBy.tmuxSessions, nil)
check("a host written false in config is not switched off", disabled.launcher == nil)
check("a host saved by a page is not switched off", disabled.stage == nil)
check("a saved word naming nothing is not switched off", disabled.nosuchplugin == nil)

local refusedBy = {}
for _, r in ipairs(refused) do refusedBy[r.identity] = r end
eq("the host written false is refused as config", (refusedBy.launcher or {}).source, "config")
check("the refusal of a host says it is core",
  tostring((refusedBy.launcher or {}).why):find("core", 1, true) ~= nil)
eq("the saved host is refused as saved", (refusedBy.stage or {}).source, "saved")
eq("the unknown word is refused as naming no plugin", (refusedBy.nosuchplugin or {}).why,
  "names no plugin here")
eq("vpn is refused nowhere, saved twice still counts once", refusedBy.vpn, nil)

local overrides = switch.overrides(entries)
check("the overrides the resolver merges carry no false entry",
  overrides.vpn == nil and overrides.launcher == nil)
eq("an override table survives", (overrides.emoji or {}).key, "x")

-- What the loader is handed.
local off = {}
for identity in pairs(disabled) do off[identity] = true end
local rawNames, baseFor = switch.loadList(directories, spoonDir, off)
check("a switched off plugin is absent from the load list", not has(rawNames, "vpn")
  and not has(rawNames, "tmuxsessions"))
check("a host and an untouched plugin are still loaded", has(rawNames, "launcher")
  and has(rawNames, "emoji"))
eq("a loaded plugin's base is the part under the spoon", baseFor.emoji, "plugins/")

-- The window manager switched off takes window size with it.
local libNames = {}
for name in pairs({ leader = true, appfocus = true, recency = true,
  storage = true, paste = true, cheatsheet = true, registry = true, glyphicon = true,
  chordkey = true, queryassoc = true, ui = true }) do libNames[name] = true end
local wmOff = { windowmanager = true }
local before = switch.loadList(directories, spoonDir, (function()
  local set = { windowmanager = true }
  for name in pairs(plugins.offBecause(manifests, wmOff)) do set[name] = true end
  return set
end)())
check("window size is not loaded while the window manager is off", not has(before, "windowsize"))

local plan = resolver.plan({ manifests = manifests, user = {}, disabled = wmOff,
  present = function() return true end, libNames = libNames })
check("the plan marks the window manager disabled", plan.disabled.windowmanager == true)
eq("window size is off because of the window manager only",
  table.concat(plan.offBecause.windowsize or {}, ","), "windowmanager")
eq("window size is not reported as blocked", plan.blocked.windowsize, nil)
check("neither is in the wiring order", not has(plan.order, "windowmanager")
  and not has(plan.order, "windowsize"))
local mentions = {}
for _, p in ipairs(plan.problems) do
  local text = tostring(p.where) .. " " .. tostring(p.why)
  if text:find("windowmanager", 1, true) or text:find("windowsize", 1, true) then
    mentions[#mentions + 1] = text
  end
end
eq("no problem names either", #mentions, 0)
check("the explanation says why window size is off",
  resolver.explain(plan):find("windowsize, off because windowmanager is switched off", 1, true) ~= nil)

local lines = switch.reportLines(plan.disabled, plan.offBecause)
eq("the report names the switched off plugin", lines[1], "switched off, windowmanager")
eq("the report names its dependent and why", lines[2],
  "off because windowmanager is switched off, windowsize")
eq("nothing switched off reports nothing", #switch.reportLines({}, {}), 0)

-- Every cause is named, sorted, and a host is never taken off. Four synthetic manifests, one
-- plugin requiring two others, one chain through a third, and a host requiring a plugin.
local function need(plugin) return { plugin = plugin, member = "thing" } end
local synth = {
  alpha = {}, beta = {},
  both = { needs = { siblings = { a = need("beta"), b = need("alpha") } } },
  chain = { needs = { siblings = { a = need("both") } } },
  gate = { needs = { siblings = { a = need("alpha") } } },
  corehost = { needs = { siblings = { a = need("alpha") } } },
  lone = {},
}
local function synthSwitchable(identity) return identity ~= "corehost" end
local causes = plugins.offBecause(synth, { alpha = true, beta = true }, synthSwitchable)
eq("a plugin on two switched off ones names both, sorted", table.concat(causes.both or {}, ","),
  "alpha,beta")
eq("a plugin down a chain names the roots, not the link between", table.concat(causes.chain or {}, ","),
  "alpha,beta")
eq("a plugin on one switched off one names it", table.concat(causes.gate or {}, ","), "alpha")
eq("a host is never marked off", causes.corehost, nil)
eq("an unrelated plugin is untouched", causes.lone, nil)
local needed = plugins.requiredByCore(synth, synthSwitchable)
check("a plugin a host requires is reported as needed by the core",
  needed.alpha == true and needed.beta == nil and needed.lone == nil)
local mergedDisabled, _, mergedRefused = switch.merge({ entries = { alpha = false },
  saved = { "beta", "alpha" }, switchable = synthSwitchable,
  known = function(identity) return synth[identity] ~= nil end, coreNeeded = needed })
check("a plugin a host requires is refused from config and from the saved set",
  mergedDisabled.alpha == nil and mergedDisabled.beta == true and #mergedRefused == 2
    and tostring(mergedRefused[1].why):find("needed by the core", 1, true) ~= nil)
local corePending = {}
local coreOk, coreWhy = switch.stage(corePending, "alpha", true, { switchable = synthSwitchable,
  lockedBy = { alpha = "core" } })
check("staging refuses a plugin a host requires and says why",
  coreOk == false and tostring(coreWhy):find("needed by the core", 1, true) ~= nil
    and next(corePending) == nil)
local coreCatalog = switch.catalog({ manifests = synth, directories = {}, switchable = synthSwitchable,
  disabled = {}, lockedBy = { alpha = "core" }, offBecause = causes })
local synthRows = {}
for _, row in ipairs(coreCatalog) do synthRows[row.identity] = row end
eq("the catalog marks a plugin a host requires as locked by the core", synthRows.alpha.lockedBy, "core")
eq("the catalog carries every cause as a list", table.concat(synthRows.both.offBecause, ","),
  "alpha,beta")
local synthLines = switch.reportLines({ alpha = true, beta = true }, causes)
eq("the report says which plugins are off because of one", synthLines[2],
  "off because alpha is switched off, gate")
eq("and which because of two", synthLines[3],
  "off because alpha and beta are switched off, both, chain")

-- The cascade a settings page asks, both ways.
local goes = switch.cascade({ plan = resolver.plan, manifests = manifests, user = {},
  libNames = libNames, disabled = {}, identity = "windowmanager", off = true })
check("switching off the window manager would take window size too", has(goes, "windowsize"))
check("the cascade never names the plugin asked about", not has(goes, "windowmanager"))
local comes = switch.cascade({ plan = resolver.plan, manifests = manifests, user = {},
  libNames = libNames, disabled = wmOff, identity = "windowmanager", off = false })
check("switching the window manager back on brings window size back", has(comes, "windowsize"))
eq("a plugin nothing requires takes nothing with it", #switch.cascade({ plan = resolver.plan,
  manifests = manifests, user = {}, libNames = libNames, disabled = {}, identity = "vpn",
  off = true }), 0)

-- An optional user stays silent. Two small manifests, one optionally naming the other.
local pair = {
  user = { needs = { siblings = { extra = { plugin = "provider", member = "thing",
    policy = "optional" } } } },
  provider = {},
}
local quiet = resolver.plan({ manifests = pair, disabled = { provider = true },
  modules = { user = {} }, libs = {} })
eq("an optional user of a switched off plugin raises no problem", #quiet.problems, 0)
check("an optional user of a switched off plugin still loads", has(quiet.order, "user")
  and quiet.offBecause.user == nil and quiet.blocked.user == nil)
local loud = resolver.plan({ manifests = { user = pair.user }, modules = { user = {} }, libs = {} })
local named = false
for _, p in ipairs(loud.problems) do
  if tostring(p.why):find("which is not a plugin here", 1, true) then named = true end
end
check("the same need naming a plugin that does not exist is still reported", named)

-- Staging, with nothing written until the whole staged set is saved. The current state is this
-- load's disabled set, tmuxSessions switched off and vpn locked off in config.
local current = { tmuxSessions = true }
local pending = {}
local function stageOpts()
  return { switchable = isSwitchable, lockedBy = { vpn = "config" },
    current = function(identity) return current[identity] == true end }
end
local ok, why = switch.stage(pending, "launcher", true, stageOpts())
check("a host cannot be staged off from a page", ok == false and why ~= nil)
ok = switch.stage(pending, "vpn", false, stageOpts())
check("a plugin switched off in config cannot be staged on from a page", ok == false)
eq("neither refusal staged anything", next(pending), nil)
ok = switch.stage(pending, "windowmanager", true, stageOpts())
check("staging a plugin off is accepted", ok == true and pending.windowmanager == true)
switch.stage(pending, "windowmanager", false, stageOpts())
eq("toggling it back to the current state clears its pending entry", pending.windowmanager, nil)
switch.stage(pending, "windowmanager", true, stageOpts())
switch.stage(pending, "tmuxSessions", false, stageOpts())
check("staging a switched off plugin on is held as on", pending.tmuxSessions == false)
switch.stage(pending, "tmuxSessions", true, stageOpts())
eq("and toggling that back clears it too", pending.tmuxSessions, nil)

-- What the staged set would leave, from the same dry run the cascade uses.
local dry = { plan = resolver.plan, manifests = manifests, user = {}, libNames = libNames,
  switchable = isSwitchable }
local function with(extra)
  local out = {}
  for k, v in pairs(dry) do out[k] = v end
  for k, v in pairs(extra) do out[k] = v end
  return out
end
local preview = switch.preview(with({ disabled = current, pending = { windowmanager = true } }))
check("the preview has the window manager off", preview.off.windowmanager == true)
check("and window size off with it", preview.off.windowsize == true)
eq("naming the window manager as the cause", table.concat(preview.offBecause.windowsize or {}, ","),
  "windowmanager")
check("and keeps what this load already had off", preview.off.tmuxSessions == true)
local proposed = switch.proposed(current, { windowmanager = true, tmuxSessions = false })
check("the proposed set applies both directions", proposed.windowmanager == true
  and proposed.tmuxSessions == nil)
eq("without touching the current set", current.tmuxSessions, true)

local previewCatalog = switch.catalog({ manifests = manifests, directories = directories,
  switchable = isSwitchable, disabled = current, lockedBy = {}, pending = { windowmanager = true },
  preview = preview })
local previewRows = {}
for _, row in ipairs(previewCatalog) do previewRows[row.identity] = row end
check("the catalog carries the staged choice on its row", previewRows.windowmanager.pending == true
  and previewRows.windowmanager.after.off == true)
check("and the cascade on the dependent's row, unstaged itself",
  previewRows.windowsize.pending == nil and previewRows.windowsize.after.off == true
    and has(previewRows.windowsize.after.offBecause, "windowmanager"))
eq("with nothing staged a row carries no after", switch.catalog({ manifests = manifests,
  directories = directories, switchable = isSwitchable, disabled = current })[1].after, nil)

local before = {}
for name in pairs(current) do before[name] = true end
local changes = switch.changes(before, preview.off)
eq("applying changes two plugins", #changes, 2)
eq("the line names each by title and state, sorted by title",
  switch.appliedLine(changes, function(identity)
    return (manifests[identity].about or {}).title or identity
  end), "Plugins applied, " .. table.concat((function()
    local a = { (manifests.windowmanager.about or {}).title or "windowmanager",
      (manifests.windowsize.about or {}).title or "windowsize" }
    table.sort(a, function(x, y) return x:lower() < y:lower() end)
    return { a[1] .. " off", a[2] .. " off" }
  end)(), ", "))
eq("nothing changed says nothing", switch.appliedLine({}, tostring), nil)

-- The save, with a recorder where the root hands hs.settings.
local store, writes = { "gone", "launcher", "tmuxSessions" }, 0
local function saveOpts()
  return { switchable = isSwitchable, lockedBy = { vpn = "config" },
    read = function() return store end,
    write = function(list) store = list writes = writes + 1 end }
end
switch.save({ windowmanager = true, tmuxSessions = false, vpn = false }, saveOpts())
eq("one save writes once", writes, 1)
eq("the whole staged set is written sorted, a stale or refused saved identity dropped, a locked one skipped",
  table.concat(store, ","), "windowmanager")

-- The resume note a reload leaves for the load after it.
local resume = load("lib/resume.lua")
local slot, clears = nil, 0
local resumeStore = {
  read = function() return slot end,
  write = function(note) slot = note end,
  clear = function() slot = nil clears = clears + 1 end,
}
check("a note with no tool and no line is refused", not resume.write(resumeStore, { open = {} })
  and slot == nil)
check("a note whose step is not flat is refused", not resume.write(resumeStore,
  { open = { tool = "t", path = { { nested = {} } } } }))
check("a place to reopen is written", resume.write(resumeStore, { open = { tool = "t",
  path = { { nav = true, to = "page" } }, highlight = { key = "row" } } }))
local taken = resume.take(resumeStore)
check("the note is taken with its tool, path and highlight", taken ~= nil and taken.open.tool == "t"
  and taken.open.path[1].to == "page" and taken.open.highlight.key == "row")
check("taking it clears it", slot == nil and clears == 1)
eq("a second take finds nothing", resume.take(resumeStore), nil)
eq("and clears nothing more", clears, 1)
check("a line alone is a note", resume.write(resumeStore, { notify = "Plugins applied" })
  and resume.take(resumeStore).notify == "Plugins applied")
slot = { open = { tool = 7 } }
eq("a note of the wrong shape is ignored", resume.take(resumeStore), nil)
check("and cleared all the same", slot == nil)

-- The catalog a page lists.
local catalog = switch.catalog({ manifests = manifests, directories = directories,
  switchable = isSwitchable, disabled = disabled, lockedBy = lockedBy })
local byIdentity, hostListed, sorted = {}, false, true
for i, row in ipairs(catalog) do
  byIdentity[row.identity] = row
  if not isSwitchable(row.identity) then hostListed = true end
  if i > 1 then
    local a = tostring(catalog[i - 1].about.title or catalog[i - 1].identity):lower()
    local b = tostring(row.about.title or row.identity):lower()
    if a > b then sorted = false end
  end
end
check("the catalog lists no host", not hostListed and byIdentity.launcher == nil)
check("the catalog is sorted by title", sorted)
eq("the catalog marks a config switch as locked", (byIdentity.vpn or {}).lockedBy, "config")
check("the catalog marks a saved switch as disabled and unlocked",
  (byIdentity.tmuxSessions or {}).disabled == true and byIdentity.tmuxSessions.lockedBy == nil)
eq("the catalog names the directory", (byIdentity.tmuxSessions or {}).directory, "tmuxsessions")
check("the catalog summarises a sibling need", has(((byIdentity.windowsize or {}).needs or {}).siblings,
  "windowmanager"))
