-- Unit case for the one plugin switch, phase five of the core split. A plugin is switched off by
-- a false entry in config/plugins.lua or by an identity a settings page saved, and the union of
-- the two decides, before anything loads, which plugins the loader never runs and which the plan
-- reports as a choice rather than a failure.
--
-- Everything here drives the real code. lib/pluginswitch.lua merges and answers the four root
-- words, lib/plugins.lua reads the real manifests off this checkout and answers which plugins go
-- off with a switched off one, and lib/resolve.lua plans over them. Nothing is loaded beyond the
-- manifests, nothing is written to hs.settings, and no reload is asked for, the writer and the
-- reload being recorders handed in exactly where the root hands in the real ones.
--
-- What is asserted. The merge of a config false with the saved set, and which wins the lock. A
-- host refused from either source. A switched off plugin absent from what the loader is handed.
-- The window manager taking window size off with it, reported as a choice naming the window
-- manager rather than as a block, and the dry run cascade a settings page asks answering the
-- same thing both ways. And a plugin that only optionally uses a switched off one loading with
-- nothing said, while the same need naming a plugin that does not exist is still reported, so
-- the silence is the switch's and not a check that stopped looking.

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
for name in pairs({ windowleader = true, hyperkey = true, appfocus = true, recency = true,
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
eq("window size is off because of the window manager", plan.offBecause.windowsize, "windowmanager")
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

-- The setter, with a recorder where the root hands hs.settings and the scheduled reload.
local store, reloads = { "tmuxSessions" }, 0
local function setOpts()
  return { switchable = isSwitchable, lockedBy = { vpn = "config" },
    read = function() return store end,
    write = function(list) store = list end,
    reload = function() reloads = reloads + 1 end }
end
local ok, why = switch.set("launcher", true, setOpts())
check("a host cannot be switched off from a page", ok == false and why ~= nil)
ok = switch.set("vpn", false, setOpts())
check("a plugin switched off in config cannot be switched on from a page", ok == false)
eq("neither refusal wrote or reloaded", reloads, 0)
ok = switch.set("windowmanager", true, setOpts())
check("switching a plugin off is accepted", ok == true)
eq("the saved set is written sorted", table.concat(store, ","), "tmuxSessions,windowmanager")
eq("one switch asks for one reload", reloads, 1)
switch.set("tmuxSessions", false, setOpts())
eq("switching one back on removes only it", table.concat(store, ","), "windowmanager")

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
