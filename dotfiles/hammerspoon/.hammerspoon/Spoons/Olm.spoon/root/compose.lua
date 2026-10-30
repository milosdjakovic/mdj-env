-- The composition root itself.
--
-- This is the one file in the whole tree allowed to name a concretion, every shared atom,
-- every lib module above it, and the exact eight stage order lib/wire.lua already fixes,
-- plus the two things that have to happen before stage one and the three that have to
-- happen after stage six. Every other file in this tree answers a question about itself or
-- about the plugin set in general. This file is the only one allowed to say which real
-- module answers which question, because a portable spoon still needs exactly one place
-- that turns a plan into a running config, and scattering that across two files is how the
-- first attempt lost track of an ordering constraint that lived nowhere else.
--
-- Read this file top to bottom. Its body is one ordered sequence and the order is the whole
-- design, the same discipline lib/wire.lua already keeps inside its own eight stages. A
-- section here runs once, in this order, and nothing later in the file may run earlier code
-- again under a different name.
--
-- The rule that matters most. This file is part of a portable spoon. Someone installing Olm
-- with a different set of plugins still loads this file unchanged, so it must never name a
-- concrete plugin under plugins, never assume one exists, and never hold a roster of
-- anything a plugin set could answer for itself. The five modules under host are the one
-- exception, and it is a considered one rather than an oversight. They are Olm's own fixed
-- apparatus, shipped with the spoon itself rather than installed per person the way a
-- plugin is, so naming ActionPanel, LeaderSheet, Launcher, QueryScope, or Stage here is
-- not the leak naming a swappable plugin would be. Every such seam below is commented as one
-- and says why, and nowhere else in this file may a plugin's own identity appear as a literal.

local obj = {}

--------------------------------------------------------------------------------
-- Loading the siblings this file is allowed to name
--------------------------------------------------------------------------------

-- A spoon directory is not on package.path, so every sibling here is pulled in by absolute
-- path with loadfile rather than require, the same pattern every multi file plugin in this
-- tree already follows. A broken sibling fails loudly with its own name in the message
-- rather than leaving this file to guess why nothing wired.
local rootDir = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local spoonDir = rootDir .. "../"

local function load(relativePath)
  local chunk, err = loadfile(spoonDir .. relativePath)
  if not chunk then
    error("Olm compose, failed to load " .. relativePath .. ", " .. tostring(err))
  end
  return chunk()
end

local defaultsLib = load("lib/defaults.lua")
local pluginsLib = load("lib/plugins.lua")
local surfaceLib = load("lib/surface.lua")
local resolveLib = load("lib/resolve.lua")
local wireLib = load("lib/wire.lua")
local loaderLib = load("lib/loader.lua")
local leadersLib = load("lib/leaders.lua")
local overlayDisplayLib = load("lib/overlaydisplay.lua")
local hintsLib = load("lib/hints.lua")
local registrarLib = load("lib/registrar.lua")
-- The read model of every chord that gets bound, built once from declarations. A pure module
-- like the registrar, so the unit case drives the same code this file runs.
local keymapLib = load("lib/keymap.lua")
-- Hammerspoon's key names with the few it lacks, the Globe key among them, the one table every
-- keymap row, leader binding and list key is read against. Pure like the keymap.
local keycodesLib = load("lib/keycodes.lua")
-- The one place a global key is bound, walking the keymap's rows in order. Pure like the keymap,
-- with the engines handed in, so a plain case drives the same dispatch this file runs.
local binderLib = load("lib/binder.lua")
-- How rows other plugins contribute reach the launcher and how a chosen one runs, assembled
-- from the plan's set answers. A pure module like the registrar, so the unit case drives the
-- same code this file runs.
local contributionsLib = load("lib/contributions.lua")
-- The one spelling of a chord and of a set of aliases, whether a list is open, and what choosing a
-- launcher row does in place of closing it. Pure, every collaborator handed in from here.
local labelsLib = load("lib/labels.lua")
local listOpenLib = load("lib/listopen.lua")
local secureFocusLib = load("lib/securefocus.lua")
local secureNoticeLib = load("lib/securenotice.lua")
local rowInterceptLib = load("lib/rowintercept.lua")
-- The OLM keys page, every bound chord listed read only, a presentation the launcher's own row
-- pushes. Pure, the catalog and the stage's pop handed in from here.
local keyPageLib = load("lib/keypage.lua")
-- Which plugins are switched off, merged from the person's config and the saved set, and the
-- one switch a settings page writes through. Pure, every hs call is handed in from here.
local switchLib = load("lib/pluginswitch.lua")
-- The one shot note a reload leaves for the load after it, where to reopen and what to say.
local resumeLib = load("lib/resume.lua")
local navLib = load("lib/nav.lua")
local servicesLib = load("lib/services.lua")
-- The docked companion pane's lifecycle, one copy for every plugin that declares a pane, and
-- its canvas drawing backend, the one every pane draws through unless the swift chooser serves.
local dockedPaneLib = load("lib/dockedpane.lua")
local paneCanvasLib = load("lib/dockedpane/canvas.lua")
local uiSpecLib = load("root/uispec.lua")
local themesLib = load("lib/ui/themes.lua")
-- The icon engine and the units it is composed from. This file is the one that names the
-- concrete sources, the engine itself knows only lib/icons/contract.lua.
local iconsLib = load("lib/icons/init.lua")
local iconsConfigLib = load("lib/icons/config.lua")
local iconRowsLib = load("lib/icons/rows.lua")
local emojiSourceLib = load("lib/icons/sources/emoji.lua")
local sfSourceLib = load("lib/icons/sources/sf.lua")
-- The leader triggers, the concrete strategies lib/leader.lua runs behind its contract and never
-- names. Each answers new(spec) and holds nothing at file level, so loading them here beside the
-- published leader atom builds no second copy of anything shared. The composite holds a held and
-- a modifier trigger built here, for a leader listening on both. A further kind of trigger is a
-- file beside these and a line here.
local heldTriggerLib = load("lib/leader/triggers/held.lua")
local modifierTriggerLib = load("lib/leader/triggers/modifier.lua")
local compositeTriggerLib = load("lib/leader/triggers/composite.lua")

local log = hs.logger.new("Olm.compose", "info")

-- The timer that acts on a resume note once a load has finished, held at file level since a
-- Hammerspoon timer nobody refers to is collected before it fires.
local resumeTimer
-- Every sibling here has its own opinion about the shape a logger arrives in. Some read an
-- hs.logger style object, log.e(message), and are handed this file's own log directly.
-- Others, lib/wire.lua and lib/registrar.lua among them, read a plain callable, log(level,
-- message), since a stand in for a test case can be a bare function but cannot as easily
-- pretend to be a whole object. This one wrapper is what a callable shaped consumer gets,
-- so the difference is paid once here rather than once per call site.
local function logFn(level, message) log[level](message) end

--------------------------------------------------------------------------------
-- STEP A. Policy.
--------------------------------------------------------------------------------

-- What Olm ships on a machine with nothing configured. Every value here has to work with no
-- further configuration at all, the same admissibility rule a plugin's own defaults answer
-- to, because this is the composition root's own defaults table and nothing exempts it from
-- the rule it holds every plugin to.
--
-- The auto reload ignore list ships with the shape of a plugin's own JSON store in it, and
-- names no plugin to do it. Every store path this root hands out is the config directory plus
-- the declaring plugin's own name plus .json, so one pattern covers the whole set and keeps
-- covering it as plugins are added. It used to name one file outright, which meant the pattern
-- and the path were two separate decisions that had to agree, and a plugin capturing its own
-- state would then trigger the reload that threw the capture away. A person adding their own
-- runtime data file under the watched tree extends this list from their own configuration.
--
-- THE PATTERN DOES NOT END AT .json ON PURPOSE, AND ANCHORING IT THERE IS A REAL BUG. It used to
-- read "/config/[^/]+%.json$" and that looked exactly right and was wrong, found only by a live
-- load. hs.json.write is atomic, so it does not write the file, it writes a sibling temp named
-- for the target plus an sb suffix, workspaces.json.sb followed by hex and random, and renames
-- that into place. The temp path ends in the suffix rather than in .json, so it sailed past an
-- anchored pattern, the watcher saw a path nothing ignored, and every single capture reloaded the
-- whole configuration about two seconds later. The observed event order was the temp path first
-- and then the final path twice, so ignoring only the final name could never have been enough.
--
-- So the tail is [^/]* rather than nothing and rather than no anchor at all. Both fix the temp,
-- and this one is the tighter of the two. Dropping the anchor entirely would also ignore a file
-- inside a directory whose own name happens to end in .json, since anything at all could follow,
-- while [^/]* allows only a longer last path component. That also covers the store's own rescue
-- rename, the stamped .corrupt copy it moves a file it cannot parse to, which is another rename
-- inside this directory that must not throw away the session it is trying to protect.
--
-- This was latent for DisplayProfiles too, which writes the same way into the same directory. It
-- had simply never fired, because no profile has ever been captured on this machine.
local SHIPPED_POLICY = {
  chord = { holdDelay = 0.6, tapThreshold = 0.2, passthrough = true },
  storage = { cacheRoot = "~/.olm/cache", olmRoot = "~/.olm/data" },
  -- Where the colour theme files live, handed in from the person's config. Nothing ships
  -- here, since a theme is a file and the default one belongs beside the config that names it.
  -- The surface and chooserTheme tables below are views the root fills from the live theme,
  -- see the themes store in step B, so a person's config sets only the radius and width.
  themes = {},
  -- Where the typography file lives, fonts and sizes of the five type roles. Nothing ships
  -- here, the style carries the shipped values and a missing file falls back to them.
  typography = {},
  -- Where the icons file lives, the active icon set and its fallback. Nothing ships here, lib/
  -- icons/config.lua carries the shipped values and a missing file falls back to them.
  icons = {},
  surface = {},
  -- The outer and inner paddings, see root/uispec.lua. Empty keeps the kit's shipped steps.
  spacing = {},
  chooserTheme = {},
  cheatSheet = {},

  matcher = "fuzzy",
  -- Which picker provider every Chooser.new builds, a name from Chooser.providers. default is
  -- the default since 2026-10-14. swift draws the same engine in a native panel and serves
  -- default until its library is built, see decisions/olm-swift-chooser.md. legacy is deprecated,
  -- kept selectable as a fallback for now and warned about on every load that picks it, see
  -- decisions/olm-chooser-keys.md.
  chooserProvider = "default",
  -- The most rows a list shows before its last row offers the rest, when its presentation names
  -- no rowLimit of its own, false for every row. See chooser.rowLimit in config/settings.lua.
  chooserRowLimit = 50,
  autoReload = { ignore = { "/config/[^/]+%.json[^/]*$" } },

  -- The heading over a sheet's rows that name no group, per role, read by lib/leader.lua's
  -- sheetHeading. A held leader holding no role reads as its own name.
  roleTitles = { app = "ACTIONS", window = "WINDOW MANAGEMENT" },

  -- The alias directory is the one scope Olm itself owns rather than any plugin, a list of
  -- every other scope, so its own presentation has nowhere else to be declared and ships from
  -- here. The retired root read these three off its own keys catalog under the same name,
  -- which made a scope Olm provides look like something the person had to describe. A title is
  -- not optional decoration either, QueryScope refuses a scope that has none, so leaving it
  -- unset dropped the directory silently on every run with one warning line among many.
  aliasDirectory = { title = "Aliases", icon = "aliases", aliases = { "?" } },
}

-- The leaders Olm ships, keyed by lowercase name, in the same shape as an entry of the leaders
-- section of config/keymap.lua, which is laid over this table by lib/keymap.lua's readConfig. An
-- entry states its kind with key, a physical key Olm makes act as a modifier, with mods, a set of
-- real modifiers, or with triggers, one of each. A held key is remapped by lib/keyremap.lua, which
-- says which spare function key each source goes to, so this table names only the physical key.
--
-- HYPER and META listen on both since phase 1 of docs/PLAN-MACHINES.md, HYPER on Caps Lock and on
-- shift, ctrl, alt and cmd, META on Right Option and on shift, ctrl and alt. A machine without
-- kanata sends F18 for a Caps Lock hold and a machine with it sends the four modifiers, so each
-- reaches the same leader with nothing told which machine this is, and a kanata machine whose
-- kanata stopped still has Caps Lock as F18 through the remap. The cost is that every machine also
-- claims, machine wide, the modifier combinations its HYPER and META rows add up to. SUPER binds
-- nothing here and stays one held key. A leader is live only while
-- some bound row of the keymap uses it, so shipping all three costs nothing and moving a domain to
-- another physical key is one edit in the roles section of config/keymap.lua. Caps Lock, Right
-- Option and Right Command are the exact three keys the owner already wants HYPER, META and SUPER
-- to be, and they work on any keyboard.
--
-- The rest of an entry is how the leader behaves, read by lib/leader.lua, whose FIELDS says what
-- each field means. These reproduce the two adapters the merge in phase 3 of the keymap plan
-- replaced. HYPER rides the OS autorepeat, ranks the bindings on one key and reveals a sheet laid
-- out for its apps. Whether a tap toggles real Caps Lock is not a field, the held trigger does it
-- for the key capsLock and for no other. META drives its own repeats so a window step
-- knows how deep into a hold it is, and reveals a sheet laid out for its actions. What a leader
-- does over an open list is one rule for every held leader rather than a field, and which leader a
-- list key sits on is its chord's, its defaults riding the list role, so neither is policy since
-- phase A of the list keys addendum. A sheet is a boolean and its layout a table beside it, see
-- lib/leader.lua's SHEET_FIELDS, and a leader that states a sheet and no layout draws the
-- defaults. SUPER binds nothing on this machine, and it ships META's behaviour because it is the
-- documented other home of the window role, so pointing that role at it moves window management
-- whole. A leader with no behaviour fields has every field off, no ranking and no sheet.
--
-- No layout here states a title. The heading of a sheet's default section is what the leader
-- does, which is the role it holds, so it is keyed by role in roleTitles in the policy above and
-- follows the role to whichever leader the keymap puts it on. A layout titled per leader read
-- WINDOW MANAGEMENT on META after the window role had moved to SUPER, over rows a person had put
-- there. These lived in policy.leaderCatalog and policy.leaderPolicy until the leaders table
-- replaced both, and the root says so when a config still sets either.
local SHIPPED_LEADERS = {
  hyper = { triggers = { { key = "capsLock" }, { mods = { "shift", "ctrl", "alt", "cmd" } } },
    ranked = true, sheet = true,
    sheetLayout = { columns = 4, colWidth = 215, iconSize = 32, gap = 10, groupGap = 20 } },
  meta  = { triggers = { { key = "rightOption" }, { mods = { "shift", "ctrl", "alt" } } },
    drivenRepeat = true, sheet = true,
    sheetLayout = { columns = 2, colWidth = 250, badgeWidth = 44, gap = 12 } },
  super = { key = "rightCommand", drivenRepeat = true, sheet = true,
    sheetLayout = { columns = 2, colWidth = 250, badgeWidth = 44, gap = 12 } },
}

--------------------------------------------------------------------------------
-- run(olm, cfg), the one door into all of this
--------------------------------------------------------------------------------

-- Configures the swift chooser when it is the chosen provider and does nothing otherwise. It
-- loads its library when one is built for these sources, and otherwise starts the build and
-- serves the default chooser, already configured, for this session. It is handed no focus hold,
-- since its panel takes key itself, see lib/chooser/providers/swift/init.lua. It lives outside
-- obj.run, which sits near Lua 5.4's limit of two hundred active locals. opts carries the kit,
-- the icon resolver, the two field predicates, the resolved compiler, the cache directory and
-- the logger.
local function wireSwiftChooser(chooserAtom, chosen, opts)
  local swift = chooserAtom.providers and chooserAtom.providers.swift
  if not swift or chosen ~= swift then return end
  opts.fallback = chooserAtom.providers.default
  swift.configure(opts)
end

-- The drawing backend every docked pane is handed, the strategy lib/dockedpane.lua's header
-- describes. The swift chooser's native glass pane while that provider is the chosen one and its
-- library is loaded, so the pane is drawn in the native panel's window as one glass, and the canvas
-- backend otherwise, wrapped by the default provider's own, which draws a pane docked to an open
-- canvas list inside the list's surface, one shape as in swift, and leaves anything else to the
-- plain canvas. Asked each time a pane is
-- made, which is after wireSwiftChooser has run, and the answer cannot change within a session,
-- since the provider decides once at configure time. It lives outside obj.run for the same reason
-- wireSwiftChooser does.
local function dockedPaneBackend(chooserAtom, chosen)
  local swift = chooserAtom.providers and chooserAtom.providers.swift
  if swift and chosen == swift and swift.serving() == "swift" then
    local native = swift.paneBackend()
    if native then return native end
  end
  -- Whenever the native pane is not used, since the swift provider falls back to the canvas view
  -- when its library will not load, and the wrapper hosts only a pane placed on a spanning list.
  local default = chooserAtom.providers and chooserAtom.providers.default
  if default and default.paneBackend then
    return default.paneBackend(paneCanvasLib.new())
  end
  return paneCanvasLib.new()
end

-- Hands CanvasPanel the same drawing backend, so the leader sheets and the toasts follow the
-- chooser that serves the way every docked pane does, on the swift chooser's glass while it serves
-- and on the canvas otherwise. The factory resolves at each panel's first show, through
-- dockedPaneBackend, so a panel is never handed a backend before the swift chooser is wired, and
-- a panel shown while the library is not loaded draws on canvas. It lives outside obj.run for the
-- same reason wireSwiftChooser does.
local function wirePanelBackend(canvasPanel, chooserAtom, chosen)
  canvasPanel.configure({ backend = function(frame, window)
    return dockedPaneBackend(chooserAtom, chosen)(frame, window)
  end })
end

-- The icon engine and the sf source inside it. Every icon Olm draws, a launcher row, a panel
-- verb, a row a plugin names by key, a glyph in a pane, comes out of this one instance, so they
-- cannot drift. The sources are named here and nowhere else, one line each, and which is active
-- and which is the fallback is the one setting in config/icons.toml. color answers the foreground
-- role, the one a row title is drawn in, read from the kit on every draw so the light and dark
-- halves and a theme switch reach a tinted source with no watcher, and the engine keys its cache
-- on it for the sources that take a colour.
--
-- Answers the engine and a function the root calls once the manifests are read and the dependency
-- door has answered, see wireIconRenders below. It lives outside obj.run, which sits near Lua
-- 5.4's limit of two hundred active locals, so the sources and the config end with this call.
local function buildIcons(atoms, policy, color, warnLog)
  local sf = sfSourceLib.new({
    dir = function() return atoms.storage.ensure(atoms.storage.cacheDir("icons")) end,
    log = warnLog,
  })
  local iconSources = { emojiSourceLib.new(), sf }
  local iconKnown = {}
  for _, source in ipairs(iconSources) do iconKnown[source.name] = true end
  local iconConfig = iconsConfigLib.load((policy.icons or {}).file, function(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local text = file:read("a")
    file:close()
    return text
  end, warnLog, function(name) return iconKnown[name] end)
  local order = iconsConfigLib.order(iconConfig)
  local engine = iconsLib.new({ sources = iconSources, order = order, color = color })
  local sfInOrder = false
  for _, name in ipairs(order) do
    if name == sf.name then sfInOrder = true end
  end
  -- The sf source renders out of process, see lib/icons/sources/sf.lua. It is handed the
  -- osascript path from the door, the refresh to fire when a run has written pictures, and,
  -- where the order reaches it, every symbol the manifests declare at the current colour, so a
  -- fresh machine renders the declared set in one run at load rather than row by row.
  local function prepare(declared, osascript, refresh)
    sf.configure({ osascript = osascript, onReady = refresh })
    if not sfInOrder then return end
    local names, seen = {}, {}
    for _, icons in pairs(declared) do
      for _, spec in pairs(icons) do
        local name = type(spec) == "table" and spec[sf.name] or nil
        if type(name) == "string" and not seen[name] then
          seen[name] = true
          names[#names + 1] = name
        end
      end
    end
    table.sort(names)
    sf.prefetch(names, color())
  end
  return engine, prepare
end

-- Wires the icon renders once the manifests' icons are read and the door has answered. The
-- refresh repaints every list a provider is showing, asked of each provider that answers
-- iconsChanged, so a picture finished in the background appears without a reopen. It walks the
-- providers the chooser atom holds and names none of them. It lives outside obj.run for the same
-- reason buildIcons does.
local function wireIconRenders(prepareIcons, declared, depsScope, chooserAtom)
  prepareIcons(declared, depsScope.path("osascript"), function()
    for _, provider in pairs(chooserAtom.providers or {}) do
      if type(provider) == "table" and type(provider.iconsChanged) == "function" then
        provider.iconsChanged()
      end
    end
  end)
end

function obj.run(olm, cfg)
  cfg = cfg or {}

  -- The shared atoms are TAKEN from the spoon rather than loaded again here, and that is a
  -- correctness point rather than a saving. loadfile hands back a fresh module every call, so
  -- this file loading lib/chordkey.lua on its own produced a second, entirely separate engine
  -- from the one Olm.lib already published. Both existed, only this one was ever configured,
  -- and the published one sat there with no tap and no keys looking exactly like a leader that
  -- had failed to wire. Reading it that way cost a wrong diagnosis, and nothing about the code
  -- could have said which copy anyone was holding.
  --
  -- Only the atoms Olm.lib publishes are shared, because those are the only ones anybody can
  -- reach a second way. The pure factories this file loads above answer .new and hold nothing,
  -- so a second copy of one is indistinguishable from the first and there is no ambiguity to
  -- remove.
  local atoms = olm.lib or {}
  local registryLib = atoms.registry
  -- The one contract version, the spoon's own published apiVersion. Every manifest is read
  -- against it and every registry descriptor carries it, so the two checks cannot disagree
  -- about which contract this Olm speaks. It used to be a second literal kept here.
  local API_VERSION = olm.apiVersion
  local glyphIconLib = atoms.glyphicon

  local policy = defaultsLib.merge(SHIPPED_POLICY, cfg.policy)
  -- The person's keymap, config/keymap.lua, handed in as cfg.keymap beside cfg.plugins and read by
  -- nothing but this root, so no plugin ever learns a person's keys. lib/keymap.lua reads it into
  -- its four sections here, keys, leaders, roles and aliases, every entry it cannot read a problem
  -- line said once the wiring report exists. Read this early because the roles decide which leader
  -- a default lands on and the aliases are merged before the plan is resolved.
  local keyRemapAtom = atoms.keyremap
  -- The key table, built once and handed to every reader of a key name below and to the leader
  -- adapter, so a key Hammerspoon does not name is spelled the same way everywhere.
  local keyTable = keycodesLib.new(hs.keycodes.map)
  atoms.leader.keycodes = keyTable
  local keymapConfig = keymapLib.readConfig(cfg.keymap, {
    leaders = SHIPPED_LEADERS,
    sources = keyRemapAtom.sources(),
    allocate = keyRemapAtom.allocate,
    roleWords = { "app", "window", keymapLib.LIST_ROLE },
    keycodes = keyTable,
    standalone = keycodesLib.standalone,
  })
  local keymapProblems = {}
  for _, problem in ipairs(keymapConfig.problems) do keymapProblems[#keymapProblems + 1] = problem end
  -- The routine lines the keymap reader has, said as notes rather than problems.
  for _, note in ipairs(keymapConfig.notes) do log.i("Olm keymap, " .. note) end
  -- The two policy fields the leaders section replaced. A value still set there would otherwise be
  -- ignored in silence.
  for _, field in ipairs({ "leaderCatalog", "leaderPolicy" }) do
    if type(cfg.policy) == "table" and cfg.policy[field] ~= nil then
      keymapProblems[#keymapProblems + 1] = { where = "policy." .. field, why = "is retired, a leader's key and "
        .. "its behaviour are written in the leaders section of config/keymap.lua, so the field is ignored" }
    end
  end
  -- Which leader each role lands on, app on HYPER and window on META unless the keymap's roles
  -- section moves one. A leader's identity, here and in every reader of a role, is its name upper
  -- cased whichever kind it is, so a role names the same leader whether Hyper is Caps Lock or the
  -- four modifiers. cfg.leaders carried this from config/keys.lua until phase 5 of the
  -- keymap plan and is read by nothing now, so a value still passed is a problem line rather than
  -- a second way to say it.
  -- Merged by hand rather than through lib/defaults.lua, whose merge reads an empty table as a
  -- list and a list replaces outright, so an empty roles section would leave no role at all.
  -- The list role is kept apart from the two a plugin's global defaults name, since it places list
  -- keys and no global row, so a reader asking which role a global row's leader answers, or which
  -- heading a sheet wears, never meets it.
  local leaderRoles = { app = "HYPER", window = "META" }
  local listRoleCatalog = "HYPER"
  for role, catalogName in pairs(keymapConfig.roles) do
    if role == keymapLib.LIST_ROLE then listRoleCatalog = catalogName else leaderRoles[role] = catalogName end
  end
  -- The name a chord spells the list role's leader with, which every default list key is placed on.
  local listLeaderName = tostring(listRoleCatalog):lower()
  if cfg.leaders ~= nil then
    keymapProblems[#keymapProblems + 1] = { where = "cfg.leaders", why = "is retired, a role moves "
      .. "to another held leader in the roles section of config/keymap.lua, so the field is ignored" }
  end
  -- The leaders in use, built in step H, every held one in catalog name order and the plain
  -- combo leader last, and the held leaders among them. Declared this early because
  -- closures handed out long before step H, the chooser field's yield, the leader view a plugin
  -- may ask for and the stage word the BrowserTabs harness reads, all read them late.
  local leaderList = {}
  local heldLeaders = {}
  -- The modifier leaders in use that host a list key, which seal over an open list, read by the
  -- chooser field's claim below and filled once the leaders in use are known.
  local sealingModifierLeaders = {}
  -- The watcher for list keys the open list's own field answers, built once the dispatch table is,
  -- and read by the default chooser's field at each press.
  local fieldWatch = nil
  -- The same field keys as { mods, keycode } pairs, which the secure focus hold relays over Chrome.
  local relayFieldKeys = {}
  -- Whether any held leader in use answers fn, asked of each in turn.
  local function anyHeldLeader(fn)
    for _, leader in ipairs(heldLeaders) do
      if fn(leader) then return true end
    end
    return false
  end
  local decorate = defaultsLib.merge({ installedBy = "actionpanel" }, cfg.decorate)
  -- The person's per plugin entries, keyed by plugin identity, from config/plugins.lua. One entry
  -- holds that plugin's overrides, its person supplied data and its spoon global, or false to
  -- switch it off. Overrides go to the resolver as they are, and the resolver strips the data and
  -- global fields itself. The other two are read out below, once each.
  local pluginEntries = cfg.plugins or {}
  -- The other half of the one switch, the identities a settings page saved. Read here, before
  -- anything loads, and merged with the false entries above once step C knows which identities
  -- live under plugins, since only those may be switched off.
  local savedDisabled = hs.settings.get(switchLib.SETTINGS_KEY)
  -- What the resolver merges over each plugin's defaults. A false entry travels in the disabled
  -- set instead, so a false the merge refuses, one written for a host, switches nothing off. Every
  -- key field a person could once write per plugin, key, mods, leader, bindings, surface and
  -- aliases, is refused here with one problem line naming config/keymap.lua, which holds every key,
  -- list key and alias since phase 7 of the keymap plan, so a field left in config/plugins.lua is
  -- said out loud rather than merged or dropped in silence.
  local pluginOverrides, refusedKeyFields = keymapLib.refusePluginKeys(switchLib.overrides(pluginEntries))
  for _, problem in ipairs(refusedKeyFields) do keymapProblems[#keymapProblems + 1] = problem end
  local globals = {}
  for name, entry in pairs(pluginEntries) do
    if type(entry) == "table" and entry.global ~= nil then globals[name] = entry.global end
  end
  -- The root owned per identity presentation table, category, detail, keywords, chord, and
  -- the rest lib/registrar.lua's own describe reads, none of which a manifest could ever
  -- carry since none of it can be derived from what a plugin declares about itself. This is
  -- the one real per identity table this file hands off rather than builds, and it lives
  -- entirely in whoever assembles cfg for one particular Olm installation, never here.
  local registryMeta = cfg.registry or {}

  ------------------------------------------------------------------------------
  -- STEP B. The atom boot. Fact 2 lands here, the decorate hook is installed
  -- before the first Chooser.new anywhere, because this whole block runs before
  -- anything reads a manifest and before the loader dofiles anything.
  ------------------------------------------------------------------------------

  -- Forward declared and filled by steps D, E and F below. Every closure in this block that
  -- reaches through one of these names is only ever CALLED much later, at the moment
  -- something actually shows on screen, well after each local holds its real value, so
  -- capturing them now while they are still nil is safe and is the whole point, the same
  -- late binding the decorate hook already relies on.
  --
  -- plan is declared here rather than at step F, where it is assigned, for a reason that is
  -- pure Lua and easy to get wrong. A closure written ABOVE a local's declaration does not
  -- capture that local at all, it reads a global of the same name and finds nil forever. So
  -- every root owned closure that looks a plugin up through plan.identity has to be written
  -- below this line, and declaring it here is what lets those closures be built where they
  -- belong, beside the other values the root owes its plugins, rather than being scattered
  -- down the file at whatever point the plan happens to already exist.
  local modules
  local overlay
  local plan
  -- The registry and the stage join this forward declared set in phase three, so
  -- isShowingFor, the surface adapters loop, and rootValues, all of which are built well
  -- before either is actually assigned, can close over the real instance rather than a
  -- global of the same name that is nil forever, the identical reason plan itself sits here.
  -- Neither closure that reaches through these two is ever CALLED until long after this
  -- whole function has returned and Hammerspoon is idling on a key press, so it is safe for
  -- the real assignment to land later in this same file, at wherever building each of them
  -- already made sense before this phase existed.
  local wiredRegistry
  local stageModule
  -- The keymap built in step J, joining this set for the keys page's word in rootValues, which
  -- answers only when asked, long after the keymap exists.

  atoms.storage.configure(policy.storage)

  -- Loaded and initialised here, but deliberately NOT configured or started until step C has
  -- read the manifests, because what it probes for is aggregated out of them. Everything
  -- between here and there only holds the atom, nothing asks it a question yet.
  local depsAtom = atoms.deps
  depsAtom:init()

  -- The colour themes, one file each in the directory policy names, and the one that is
  -- live. The store is built before anything draws so the surface and the kit start from the
  -- live theme. Everything outside plain Lua is handed to it here, the directory listing, the
  -- file read, hs.settings for the persisted choice, and the kit with the function that turns
  -- colours into a spec, so a switch is the store handing the kit a new spec and the root
  -- rewriting the two views below. A draw asks the kit for its tokens every time, which is why
  -- the next one shows the switch with no reload.
  local uiAtom = atoms.ui
  -- The five type roles' fonts and sizes, read once from the file policy names. The style
  -- validates every key and falls back to its shipped value with one warning, so what comes
  -- back here is only ever valid keys, and a theme switch hands the same answer to the new
  -- spec rather than reading the file again.
  local typography = uiAtom and uiAtom.loadTypography and uiAtom.loadTypography(
    (policy.typography or {}).file,
    function(path)
      local file = io.open(path, "r")
      if not file then return nil end
      local text = file:read("a")
      file:close()
      return text
    end,
    { w = function(message) log.w(message) end })
  local themeLog = { w = function(message) log.w(message) end }
  local themes = themesLib.new({
    dir = (policy.themes or {}).dir,
    list = function(dir)
      local names = {}
      local ok, iterator, handle = pcall(hs.fs.dir, dir)
      if ok and iterator then
        for file in iterator, handle do names[#names + 1] = file end
      end
      return names
    end,
    read = function(path)
      local file = io.open(path, "r")
      if not file then return nil end
      local text = file:read("a")
      file:close()
      return text
    end,
    store = { get = function(key) return hs.settings.get(key) end,
              set = function(key, value) hs.settings.set(key, value) end },
    ui = uiAtom,
    specFor = function(colors) return uiSpecLib.spec(policy, colors, typography) end,
    onChange = function(_, colors)
      uiSpecLib.chooserView(policy.chooserTheme, colors)
      uiSpecLib.surfaceView(policy.surface, colors)
    end,
    log = themeLog,
  })
  -- The two views the readers outside the kit still hold, a chooserTheme shaped table for the
  -- legacy provider and the plugin panes and a surface shaped one for the panel. Filled in
  -- place and rewritten in place on every switch, so a reader holding a reference follows
  -- without a reload. Stage four of the kit retires both once those readers draw through it.
  uiSpecLib.chooserView(policy.chooserTheme, themes.colors())
  uiSpecLib.surfaceView(policy.surface, themes.colors())

  -- The icon engine, see buildIcons above obj.run. prepareIcons is called once the manifests'
  -- icons are read and the dependency door has answered, through wireIconRenders.
  local iconEngine, prepareIcons = buildIcons(atoms, policy, function()
    return uiAtom and uiAtom.tokens().colors.foreground or nil
  end, themeLog)

  local canvasPanel = atoms.panel
  canvasPanel:init()
  canvasPanel.configure({ surface = policy.surface })
  canvasPanel.configure({ screen = function() return overlay and overlay.screen() end })

  -- The UI kit's style, built once from the live theme and the cheat sheet block, so a pane
  -- drawn through the kit matches the chooser rows and the cheat sheet exactly.
  -- root/uispec.lua holds how those become a spec, a file of its own so the parity probes
  -- build the very spec this root does. The panel is handed the kit straight after, since its
  -- empty state draws through it and its surface asks it which half the system is on.
  if uiAtom then
    uiAtom.configure({
      spec = uiSpecLib.spec(policy, themes.colors(), typography),
      surfaceElements = canvasPanel.surfaceElements,
      surfaceInterior = canvasPanel.surfaceInterior,
      icon = iconEngine.image,
    })
    canvasPanel.configure({ ui = uiAtom })
  end

  local chooserAtom = atoms.chooser
  chooserAtom:init()
  local chooserProvider = chooserAtom.providers and chooserAtom.providers[policy.chooserProvider]
  if not chooserProvider then
    log.w("unknown chooserProvider " .. tostring(policy.chooserProvider) .. ", falling back to default")
    chooserProvider = chooserAtom.providers and chooserAtom.providers.default
  end
  if chooserAtom.providers and chooserProvider == chooserAtom.providers.legacy then
    log.w("chooserProvider legacy is deprecated and will be removed, default is the default chooser")
  end
  -- The one icon function both chooser providers draw a row's icon through, at paint. The
  -- resolver it reaches, lib/icons/rows.lua, needs every manifest's declared icons and so is
  -- built further down, once the manifests are read, which is why this is forward declared and
  -- read late. Nothing is asked of it before the first row is drawn, and by then it exists.
  local iconRows
  local function paintIcon(icon, owner)
    return iconRows and iconRows.image(icon, owner) or nil
  end
  -- The same icon as canvas elements, for the default chooser, which paints a row's icon into its
  -- own canvas and so can draw an emoji as text rather than keep a picture of it.
  local function paintIconElements(icon, owner, frame)
    return iconRows and iconRows.elements(icon, owner, frame) or nil
  end
  chooserAtom.configure({
    screen = function() return overlay and overlay.screen() end,
    matcher = chooserAtom.matchers and chooserAtom.matchers[policy.matcher],
    provider = chooserProvider,
    ui = uiAtom,
    icon = paintIcon,
    -- THE SEAM. ActionPanel is one of the five host modules this file is allowed to name.
    -- decorate has to be installed before the first Chooser.new call anywhere or every
    -- instance keeps its own rows and the panel decorates nothing, which is Fact 2, and
    -- landing it here, before a manifest is even read, is what stops that constraint from
    -- ever again holding only by the accident of load order. The installer is still named
    -- through cfg rather than as a literal, so a portable install without ActionPanel
    -- clears cfg.decorate and this hook simply finds nothing to call.
    decorate = function(instance, config)
      local installer = modules and decorate.installedBy and modules[decorate.installedBy]
      if installer and type(installer.decorate) == "function" then
        installer:decorate(instance, config)
      end
    end,
  })
  -- The default provider draws through the shared CanvasPanel chrome and reads its type and
  -- colours from the kit's tokens, and refuses to build until it is handed both, so the root
  -- gives it the ones already configured above.
  -- The default chooser's field tap claims every key down, which would swallow a list key
  -- before its dispatch ran, so the field is handed a predicate and told nothing else. It asks
  -- every held leader in use, Hyper and META here, and reads them late, since no leader is built
  -- until further down. A key pressed under a held leader therefore never types into the field,
  -- it falls to that leader's one rule over open lists, its list keys acting and every other key
  -- swallowed, which is what Milos asked for META over a list. The swift chooser's field asks the
  -- same two, so both are named once here, in one table, and handed to each.
  local chooserKeys = {
    yields = function(ev)
      return anyHeldLeader(function(leader) return leader:owns(ev) end)
    end,
    -- A list key with no held leader, Ctrl and J, is answered by the field itself while its list
    -- is up, so nothing global claims the chord. Read late, built after the dispatch table.
    listKeys = function(ev)
      if fieldWatch ~= nil and fieldWatch(ev) == true then return true end
      -- A modifier leader hosting list keys seals over this list. Its hotkey cannot fire
      -- beneath this field's tap, which sees a chord first, so the chord is claimed here as the
      -- no op the leader would have resolved it to, Hyper and a digit moving no row.
      for _, leader in ipairs(sealingModifierLeaders) do
        if leader:owns(ev) then return true end
      end
      return false
    end,
  }
  if chooserAtom.providers and chooserAtom.providers.default then
    chooserAtom.providers.default.configure({
      panel = canvasPanel,
      ui = uiAtom,
      icon = paintIcon,
      iconElements = paintIconElements,
      -- A list opened over a password field takes focus for as long as it is open, see
      -- lib/securefocus.lua. The provider only asks and never names the mechanism.
      focusHold = function(sink) return secureFocusLib.hold(sink, { keys = relayFieldKeys }) end,
      yields = chooserKeys.yields,
      listKeys = chooserKeys.listKeys,
      rowLimit = policy.chooserRowLimit,
    })
  end

  -- The cheat sheet's colours and badge radius reach it through the kit's tokens, and its type
  -- and geometry come from the five roles, so only an optional padding override and the two
  -- collaborators are handed over here.
  local cheatSheetAtom = atoms.cheatsheet
  cheatSheetAtom:init()
  cheatSheetAtom:configure({ canvasPanel = canvasPanel, ui = uiAtom,
    padding = (policy.cheatSheet or {}).padding })

  local chordKeyAtom = atoms.chordkey
  chordKeyAtom:init()
  chordKeyAtom:configure(policy.chord)

  -- The leader adapter and the remap, both core and published under Olm.lib. Step H builds one
  -- leader instance per leader in use from the adapter, and the remap is the root's alone,
  -- applied once from the leaders section further down.
  local leaderLib = atoms.leader

  ------------------------------------------------------------------------------
  -- STEP C. Manifests. Pure data, read before anything runs.
  ------------------------------------------------------------------------------

  local pluginRoots = { plugins = spoonDir .. "plugins", host = spoonDir .. "host" }
  local allManifests, skippedManifests, directories = pluginsLib.readAll({
    pluginRoots.plugins, pluginRoots.host,
  }, API_VERSION)
  for identity, why in pairs(skippedManifests or {}) do
    log.e("Olm compose, plugin '" .. identity .. "' was left out, " .. tostring(why))
  end

  -- The disabled set, the one switch. A plugin is switchable when its manifest was found under
  -- plugins, never under host, since core must not be switchable. A switch naming anything else
  -- is refused and named once per load rather than honoured.
  local function isSwitchable(identity)
    local path = directories[identity]
    return path ~= nil and path:sub(1, #pluginRoots.plugins + 1) == pluginRoots.plugins .. "/"
  end
  -- A plugin some host requires cannot be switched off either, since the host would go with it
  -- and a choice about a plugin must never take core down. Today no host requires one.
  local coreNeeded = pluginsLib.requiredByCore(allManifests, isSwitchable)
  local disabled, lockedBy, refusedSwitches = switchLib.merge({
    entries = pluginEntries,
    saved = savedDisabled,
    switchable = isSwitchable,
    coreNeeded = coreNeeded,
    known = function(identity) return allManifests[identity] ~= nil end,
  })
  -- A refused false in config is a person's own error, so it is an error. A refused saved
  -- identity was written by a page, possibly for a plugin that has since gone, and the next
  -- switch drops it, so it is only a warning.
  for _, refusal in ipairs(refusedSwitches) do
    if refusal.source == "config" then
      log.e("Olm compose, '" .. refusal.identity .. "' was not switched off, its false entry "
        .. "in config/plugins.lua " .. refusal.why)
    else
      log.w("Olm compose, '" .. refusal.identity .. "' was not switched off, the saved switch "
        .. refusal.why .. ", and it will be dropped on the next switch")
    end
  end
  -- What a page may not change, a false in config and a plugin the core needs, one table so the
  -- catalog and the setter read the same answer.
  local locks = {}
  for identity, why in pairs(lockedBy) do locks[identity] = why end
  for identity in pairs(coreNeeded) do locks[identity] = "core" end
  -- Every plugin that requires a switched off one goes off with it, answered by the same
  -- function the resolver asks below, so the loader and the plan cannot disagree about it.
  local offBecause = pluginsLib.offBecause(allManifests, disabled, isSwitchable)
  local switchedOff = {}
  for identity in pairs(disabled) do switchedOff[identity] = true end
  for identity in pairs(offBecause) do switchedOff[identity] = true end
  for _, line in ipairs(switchLib.reportLines(disabled, offBecause)) do log.i(line) end

  -- The plugin set everything below reads, without the ones switched off. Only the resolver
  -- sees allManifests, since it is the one that has to know a switched off plugin exists to
  -- report it as a choice rather than as a sibling nothing answers to. So its tools are not
  -- declared to the door, its icons and data are not read, and nothing below can reach it.
  local manifests = {}
  for identity, manifest in pairs(allManifests) do
    if not switchedOff[identity] then manifests[identity] = manifest end
  end

  -- The manifests are the one source of what this machine needs, so the resolver is told
  -- rather than left to go looking. It used to walk the tree for separate declaration files,
  -- which the manifests replaced, so it found almost nothing and then called every tool a
  -- plugin actually asked for undeclared, nine such errors on an otherwise clean run.
  --
  -- One consumer name for the whole set, matching the single shared scope handed out below,
  -- since every plugin here reads through the same adapter rather than one of its own.
  --
  -- The door is configured and probed BEFORE the plan is built, deliberately, because the plan
  -- has to know which tools are present and the door has just answered that for all of them in
  -- one login shell. This file used to carry a second probe of its own for the plan to read,
  -- which was the same shell call a second time and a second implementation of the same
  -- reasoning, and the login shell part of that reasoning is not optional. Hammerspoon's own
  -- environment carries a bare PATH holding none of the places a package manager installs
  -- into, so a probe without it reports every Homebrew tool absent, invisibly for an optional
  -- tool and fatally for a required one.
  -- The root declares its own two tools in root/manifest.lua and joins the set as a declarer
  -- beside the plugins, rather than shelling out for them by name. It is added to a COPY here,
  -- since the manifests table is the plugin set that everything downstream plans, resolves, and
  -- reports over, and the root is not a plugin. Declaring in the same shape is what lets the
  -- door answer for the root on the same terms, and what puts its two tools in the manifest the
  -- layer above reads.
  -- In a block of its own, since nothing later reads the set, see the icon engine's block.
  do
    local declarers = { root = load("root/manifest.lua") }
    for identity, manifest in pairs(manifests) do declarers[identity] = manifest end
    depsAtom:configure({ declared = pluginsLib.declarations(declarers, "Olm") })
  end
  depsAtom:start()
  -- The one shared scope every plugin earning the ambient deps grant is handed, unscoped by
  -- consumer, matching what services.perPlugin's own contract says it hands out, the same
  -- single adapter every plugin sharing it in the live root already reads today.
  local sharedDepsScope = depsAtom:scope("Olm")

  -- Bringing an application forward, core since phase three of the core split. Configured here,
  -- once, with the shared door's path resolver, since its url form runs the launcher binary
  -- root/manifest.lua declares, and before any plugin is wired, since the app toggler builds the
  -- functions its keys call in its own configure.
  local appFocusAtom = atoms.appfocus
  appFocusAtom.configure({ path = sharedDepsScope.path })

  -- The swift chooser, here rather than in step B because its compiler comes through the door,
  -- which is answered just above, and still before the first Chooser.new, which the stage makes
  -- when it is wired. See wireSwiftChooser above obj.run.
  wireSwiftChooser(chooserAtom, chooserProvider, {
    ui = uiAtom,
    icon = paintIcon,
    yields = chooserKeys.yields,
    listKeys = chooserKeys.listKeys,
    rowLimit = policy.chooserRowLimit,
    swiftc = sharedDepsScope.path("swiftc-clt"),
    dir = atoms.storage.cacheDir("swiftchooser"),
    log = log,
  })
  wirePanelBackend(canvasPanel, chooserAtom, chooserProvider)

  -- resolve.plan's existence question for one declared tool, which is the door's own answer
  -- rather than a probe of its own. A package kind is the exception, since presence for one is
  -- proven by asking the package manager and nothing at this layer can do that, so it is taken
  -- as present and the plugin finds out for itself rather than being blocked here on a question
  -- this file cannot answer honestly either way.
  local function presentTool(tool)
    if tool.kind == "package" then return true end
    return sharedDepsScope.have(tool.name)
  end

  -- The set of real lib module names, read off this directory rather than kept as a hand
  -- written list, so a lib file added later needs no edit here to be a valid needs.lib
  -- target. Existence only. What a name resolves TO for delivery is a separate question the
  -- generic needs.lib grant inside lib/wire.lua answers from the libs table below.
  local libNames = {}
  do
    local iter, dirObj = hs.fs.dir(spoonDir .. "lib")
    if iter then
      for entry in iter, dirObj do
        local name = entry:match("^(.+)%.lua$")
        if name then libNames[name] = true end
      end
    end
  end

  ------------------------------------------------------------------------------
  -- STEP D. Modules. Loaded, initialized, keyed by identity, then mirrored onto
  -- whichever spoon globals cfg asks for.
  --
  -- lib/loader.lua wants the raw directory entries and, for each one, which root it lives
  -- under, not the identity keyed map lib/plugins.lua already answered with, so both are
  -- rebuilt here from that same map's directories, the one place that already knows where
  -- every manifest actually sits, rather than scanned a second time from disk.
  ------------------------------------------------------------------------------

  -- A plugin switched off, or off because of one, is left out here, so its init.lua is never
  -- run, its predicates and live labels are never harvested, and no module of it exists.
  -- In a block of its own, since only the loader reads the three, see the icon engine's block.
  do
    local rawNames, baseFor, identityOfRaw = switchLib.loadList(directories, spoonDir, switchedOff)
    modules = loaderLib.modules(spoonDir, baseFor, rawNames, function(rawName)
      return identityOfRaw[rawName]
    end, log)
  end
  -- A global asked for under a name no plugin answers to mirrors nothing, silently, which is how
  -- the one door a test suite reaches its plugin through was shut while the whole config looked
  -- healthy. Same slip as the data block below, and the same answer, say so.
  for name in pairs(globals) do
    if modules[name] == nil and not switchedOff[name] then
      log.e("Olm compose, a global was asked for '" .. name
        .. "', which is not a plugin, so nothing was mirrored. Check the spelling against the "
        .. "name the plugin declares for itself, which is not always its directory.")
    end
  end
  loaderLib.mirror(modules, globals)

  -- Every real lib module a plugin might name through needs.lib, for two different readers.
  -- step F's plan checks a declared name against this table for existence alone, and lib/
  -- wire.lua's own generic grant hands the same table's values straight to opts for whatever
  -- a plugin declared. recency is the one name where those two readers must disagree, since
  -- a shared instance handed out flat would merge every plugin's remembered ordering into
  -- one, so the module sits here for the existence check to find, and services.perPlugin
  -- below still hands each declaring plugin its own fresh instance through deps.data, which
  -- wins there because that channel is read last and unconditionally.
  --
  -- What every plugin declared under icons in its manifest, by identity, and the one helper that
  -- turns an icon key into an image against it. The chooser providers draw through its image
  -- function when a row paints, and the stage, the query scope and the query row sources stamp
  -- the owner onto rows with its stampAll, so a key resolves one way wherever its row is shown. A broken declaration
  -- is refused loudly at register by the registrar, so this read stays quiet and only keeps a
  -- table that passed.
  local declaredIcons = {}
  for identity, manifest in pairs(manifests) do
    local icons = registrarLib.validateIcons(identity, manifest)
    if icons then declaredIcons[identity] = icons end
  end
  iconRows = iconRowsLib.new({
    engine = iconEngine,
    declared = function(owner) return declaredIcons[owner] end,
    points = glyphIconLib.POINTS,
    log = themeLog,
  })
  -- The sf source renders every declared symbol it lacks in the background, see wireIconRenders.
  wireIconRenders(prepareIcons, declaredIcons, sharedDepsScope, chooserAtom)
  -- The door a plugin may draw an icon through at its own draw time, over the same resolver, so
  -- an owner and a key resolve one way. No host uses it for a row any more, the chooser draws
  -- those, and the door stays as the lib a plugin can ask for.
  local glyphIcon = glyphIconLib.new(iconRows)

  -- storage joins this list for the menu search cache, docs/BRIEF-MENUSEARCH-CACHE.md,
  -- the first consumer lib/storage.lua ever had. Its own configure already ran above, atoms.
  -- storage.configure(policy.storage), so the module handed out here is the one already
  -- carrying its expanded roots, never a second copy a plugin's own loadfile would build
  -- unconfigured. A plugin that wants several instances of its own shape, the way menu
  -- search wants one recency per bundle id rather than the one per plugin services.perPlugin
  -- builds automatically, declares needs.lib under a field name other than the module's own,
  -- so the generic grant above hands over the raw module rather than tripping whatever
  -- automatic instance that module's own key would otherwise earn.
  local libs = {
    paste = atoms.paste,
    cheatsheet = cheatSheetAtom,
    registry = registryLib,
    glyphicon = glyphIcon,
    chordkey = chordKeyAtom,
    -- Not the adapter itself. A plugin asking for leader gets a view answering only whether any
    -- held leader is down right now, which is the one question a plugin that posts a keystroke
    -- has to ask, and it is answered for whichever leader that plugin's key sits on, so no plugin
    -- learns a leader's name or holds one to bind on. It replaced the hyperkey and windowleader
    -- grants in phase 3 of the keymap plan.
    leader = {
      isActive = function()
        for _, leader in ipairs(leaderList) do
          if leader:isActive() then return true end
        end
        return false
      end,
    },
    appfocus = appFocusAtom,
    recency = atoms.recency,
    queryassoc = atoms.queryassoc,
    storage = atoms.storage,
    ui = uiAtom,
  }
  -- A lib that is a directory rather than a file, lib/ui, is invisible to the scan in step C,
  -- which reads only lib/*.lua. Every name this table delivers is real by construction, so
  -- each one joins the existence set too, which admits ui without also admitting chooser, a
  -- directory whose module no plugin is handed through this door.
  for name in pairs(libs) do libNames[name] = true end

  ------------------------------------------------------------------------------
  -- STEP E. The overlay display resolver, and what the two screen closures in
  -- step B call through now that it exists.
  ------------------------------------------------------------------------------

  overlay = overlayDisplayLib.new()
  overlay.configure(policy.overlayDisplay or {})

  ------------------------------------------------------------------------------
  -- STEP F. The plan, in two passes.
  ------------------------------------------------------------------------------

  local resolver = resolveLib.new({ plugins = pluginsLib, defaults = defaultsLib, surface = surfaceLib })

  -- Two channels for the person's own values, and they are not the same shape on purpose.
  --
  -- cfg.shared is flat and keyed by FIELD NAME. A value in it reaches every plugin that
  -- declared a user sourced need of that name, which is what lets one application catalog
  -- serve whichever plugins ask for it without the person naming any of them. Nothing here says which plugins those are, and a plugin that stops needing a
  -- field simply stops receiving it.
  --
  -- cfg.plugins[name].data is per PLUGIN and merged over whatever the fan out reached, for the values
  -- that are genuinely about one plugin. It has to be per plugin because field names are not
  -- unique across the set, bundleID and settings each being wanted by more than one plugin
  -- meaning different things, and folding this into the flat table, as it was, meant one of
  -- them silently got the other's value.
  local sharedData = cfg.shared or {}
  local fannedData = servicesLib.fanOut(manifests, sharedData)
  for name, entry in pairs(pluginEntries) do
    local fields = type(entry) == "table" and entry.data or nil
    if type(fields) == "table" then
      -- A key naming no plugin is named out loud rather than merged into nothing.
      --
      -- Every manifest is keyed by the plugin's own name, the one it is known by outside its own
      -- folder, and eight of them spell that differently from the directory they sit in. So a key
      -- written as the folder, browsertabs rather than browserTabs, landed in this table under a
      -- name no plugin answered to, was merged, carried all the way through, and handed to
      -- nobody. Three real values went that way at once, and every check in the config still
      -- reported a clean run, because a table with an extra entry in it is not wrong about
      -- anything, it is just alone.
      if allManifests[name] == nil then
        log.e("Olm compose, data was supplied for '" .. name
          .. "', which is not a plugin. Check the spelling against the name the plugin declares "
          .. "for itself, which is not always its directory.")
      end
      if not switchedOff[name] then
        fannedData[name] = defaultsLib.merge(fannedData[name] or {}, fields)
      end
    end
  end

  -- Whatever each plugin ships for its own declared data needs, laid UNDERNEATH everything a
  -- person handed over. Until now a plugin could declare a need, describe what breaks without
  -- it, and have no way to answer it itself, so every such need went unmet until somebody wrote
  -- the value out by hand. That is backwards for a spoon meant to work on a machine that has
  -- configured nothing.
  --
  -- Combined with lib/defaults.lua's merge rather than servicesLib.merge, and the difference is
  -- the whole point. servicesLib.merge overwrites per field, so a person handing over a whole
  -- policy map would silently drop every shipped key they had not mentioned. defaults.merge
  -- reads the shape instead, merging a map key by key so their siblings survive, and letting a
  -- list replace outright because a list is a complete statement. That rule is already written
  -- down there and this must not grow a second copy of it.
  for name, fields in pairs(servicesLib.shipped(manifests)) do
    fannedData[name] = fannedData[name] or {}
    for field, shippedValue in pairs(fields) do
      fannedData[name][field] = defaultsLib.merge(shippedValue, fannedData[name][field])
    end
  end

  -- The keymap's aliases, merged over the person's overrides as that plugin's aliases, so the
  -- resolver, the registrar's collision check, the alias directory and every row hint read the one
  -- merged answer, marked as the person's like any override. A plugin named there takes exactly
  -- those words in place of its defaults.aliases, and config/plugins.lua holds no alias, its field
  -- refused above. An identity naming no plugin or host is a problem line and merges nothing.
  for _, identity in ipairs((function()
    local names = {}
    for name in pairs(keymapConfig.aliases) do names[#names + 1] = name end
    table.sort(names)
    return names
  end)()) do
    if allManifests[identity] == nil then
      keymapProblems[#keymapProblems + 1] = { where = "config/keymap.lua aliases " .. identity,
        why = "names no plugin or host in this load, so its words scope nothing" }
    else
      local entry = {}
      for k, v in pairs(pluginOverrides[identity] or {}) do entry[k] = v end
      entry.aliases = keymapConfig.aliases[identity]
      pluginOverrides[identity] = entry
    end
  end

  local firstPass = resolver.plan({
    manifests = allManifests,
    user = pluginOverrides,
    listKeys = keymapLib.listDefaults,
    disabled = disabled,
    switchable = isSwitchable,
    present = presentTool,
    libNames = libNames,
    modules = modules,
    libs = libs,
    data = fannedData,
  })

  -- The values only pass one's plan.effective can answer, computed once and reused rather
  -- than rebuilt, so the second pass, the register stage, and the wiring args below can
  -- never disagree about what they hold.
  -- The names remapped this load, filled once the keymap is built in step J, since a held leader
  -- is remapped exactly while some bound row uses it.
  local activeLeaderNames = {}
  -- The held leaders in use, each with the key it is remapped from, in the shape the remap takes.
  local remapRows = {}

  -- Every leader the leaders table holds, each with the name a keymap row spells it with, its kind,
  -- the keycode its key resolves to when it is held, and its policy checked once. Which of them are
  -- in use is known only once the keymap is built, after register, so every one is described here
  -- and step J keeps the ones some row binds on. This is the one list everything below loops over,
  -- so nothing here knows how many leaders there are or which one is which. The reader hands them
  -- over held first. A held leader's identity is its name upper cased, the shape the roles and the
  -- remap record spell it in. A policy field that is not one a leader reads, or is of the wrong
  -- type, is a problem line once the wiring report exists, kept here until then.
  local leaderSpecs, leaderProblems = {}, {}
  for _, entry in ipairs(keymapConfig.leaders) do
    local held = entry.key ~= nil
    local catalogName = entry.name:upper()
    local leaderPolicy, problems = leaderLib.checkPolicy(catalogName, entry.policy)
    for _, problem in ipairs(problems) do leaderProblems[#leaderProblems + 1] = problem end
    local spec = { name = entry.name, catalogName = catalogName, held = held, policy = leaderPolicy }
    if held then
      -- The function key the engine listens on and, for a key that is remapped, the target, both
      -- from the one allocation the keymap reader made over every held leader.
      local slot = keymapConfig.allocation.leaders[entry.name]
      spec.key = entry.key
      spec.keyCode = slot and leadersLib.keycode(slot.fkey)
      spec.remapTarget = slot and slot.target
      -- A held leader that also listens on modifiers, HYPER and META as they ship. It stays a held
      -- leader everywhere a leader's kind is read, the roles, the list keys and the sheet by
      -- keycode, and only step H and the keymap's collision check read the set.
      spec.mods = entry.mods
    else
      -- Behaviour is the leader's own whichever kind it is, so the policy stays as checked. A
      -- modifier leader has no tap, and its sheet is revealed by the modifier trigger.
      spec.mods = entry.mods
    end
    leaderSpecs[#leaderSpecs + 1] = spec
  end
  -- The heading each held leader's sheet wears over rows that name no group, which follows the
  -- role the leader holds on this load, so the window role moved to SUPER takes its heading along.
  -- The titles are merged by role here rather than taken from the merged policy, see roleTitles.
  local roleTitles, roleTitleProblems = leaderLib.roleTitles(SHIPPED_POLICY.roleTitles, (cfg.policy or {}).roleTitles)
  for _, problem in ipairs(roleTitleProblems) do leaderProblems[#leaderProblems + 1] = problem end
  for _, spec in ipairs(leaderSpecs) do
    spec.heading = leaderLib.sheetHeading(spec.catalogName, leaderRoles, roleTitles)
  end

  -- What each leader role is CALLED where a person reads it, a row subtitle or a hint. The
  -- role is the word a manifest uses, app or window, and the catalog name is what that role
  -- resolves to on this machine, so a tool moved to the other leader is described correctly
  -- with no second place to edit. Title cased because these are read as words in a sentence
  -- rather than as the shouted constants the catalog spells them with.
  local function displayName(catalogName)
    local word = tostring(catalogName)
    return word:sub(1, 1):upper() .. word:sub(2):lower()
  end
  -- The leaders of real modifiers, claimed through hs.hotkey, a name to its set.
  local modifierLeaderSets = {}
  -- The held leaders that also listen on a set of modifiers, a name to that set, which the keymap
  -- checks every other leader's rows against.
  local compositeLeaderSets = {}
  for _, spec in ipairs(leaderSpecs) do
    if not spec.held then modifierLeaderSets[spec.name] = spec.mods end
    if spec.held and spec.mods then compositeLeaderSets[spec.name] = spec.mods end
  end
  -- The same words keyed by the name a keymap row spells its leader with, so a surface spelling a
  -- row's chord spells that row's own leader rather than whichever leader it assumed. A leader the
  -- person named reads as its own name, title cased the way Hyper is.
  local leaderNamesByLeader = {}
  for _, spec in ipairs(leaderSpecs) do
    leaderNamesByLeader[spec.name] = displayName(spec.catalogName)
  end
  -- The launcher's words, every role and every leader by the name a row spells it with, since a
  -- row the person's keymap put on a leader no role answers names that leader directly. A role
  -- word and a leader name never meet, the keymap refuses a leader named like a role.
  local leaderDisplayNames = {}
  for role, catalogName in pairs(leaderRoles) do
    leaderDisplayNames[role] = displayName(catalogName)
  end
  for name, word in pairs(leaderNamesByLeader) do leaderDisplayNames[name] = word end
  -- The one spelling of a chord and of a set of aliases, lib/labels.lua, handed to every surface
  -- that states one so no surface spells its own. A chord is spelled with the shared renderer's
  -- glyph helper, reached when a chord is spelled rather than now, as it always was.
  local chordLabel = labelsLib.chordLabel(function(key, mods) return cheatSheetAtom.glyphFor(key, mods) end)
  local aliasLabel = labelsLib.aliasLabel

  -- A leader's cheat sheet rows are not built here. They are the keymap's rows on the leader, so
  -- they can only be built once the keymap is, after register, and step K hands them to the one
  -- sheet host. The launcher's window rows come from the same keymap, through the window manager's
  -- action descriptors, so a row and the sheet still read one answer.

  ------------------------------------------------------------------------------
  -- STEP I. Everything the root itself owes its plugins, in one table, keyed by
  -- FIELD NAME rather than by plugin.
  --
  -- This is the second half of a channel that only had a first half. A manifest may declare
  -- needs.data with source "root", which is a plugin stating that a value exists, that it
  -- cannot derive it, and that the composition root is the one that knows. Six such
  -- declarations were satisfied by nothing at all, because the root used to pay these debts
  -- through a table that named each owed plugin outright, so a plugin not written into that
  -- table was validated, reported satisfied, and handed nil.
  --
  -- Keyed by field name for two reasons. It is what lets one value serve every plugin that
  -- asked for that name, rather than each getting its own copy of the same answer, which is what
  -- the whole stage vocabulary below rests on. And it is what stops this file, which must never
  -- name a plugin under plugins, from having to name each of them to pay what it owes.
  --
  -- The worked example of the first reason used to be one display fingerprint serving every
  -- plugin that scoped remembered state by arrangement. That closure is gone with its two
  -- consumers, and the plugin that replaced them defines its own notion of a location rather
  -- than sharing one, so the reason stands on the stage words instead, which genuinely are one
  -- answer many plugins ask for.
  ------------------------------------------------------------------------------

  -- Every predicate this file owns outright, collected once. plan.predicates already
  -- answers every surface gate, so nothing here may repeat one of those names, and
  -- lib/wire.lua reports it rather than silently letting one win if it ever happens.
  --
  -- Built here, above the plan rather than below it, because it is one of the values the root
  -- owes and the table below has to be able to hand it over. Every closure in it is called
  -- long after everything it reaches for exists.
  local ownPredicates = {}
  for _, module in pairs(modules) do
    if type(module) == "table" and type(module.predicates) == "table" then
      for name, fn in pairs(module.predicates) do ownPredicates[name] = fn end
    end
  end
  -- The live relabelling table, harvested exactly the way the predicates above are and for the
  -- same reason. A word that changes with a plugin's own live state can only be answered by that
  -- plugin, and this file may not name one, so it takes whatever each module offers under its own
  -- liveLabels and merges them. That closes the gap the hints deps table below used to state
  -- outright, that it had nowhere generic to reach such a value from. An action claimed twice is
  -- reported rather than letting one quietly win, the same rule the predicates merge keeps.
  local ownLiveLabels = {}
  for name, module in pairs(modules) do
    if type(module) == "table" and type(module.liveLabels) == "table" then
      for action, fn in pairs(module.liveLabels) do
        if ownLiveLabels[action] then
          log.w(string.format(
            "live label for '%s' is claimed by more than one plugin, '%s' is being ignored",
            tostring(action), tostring(name)))
        else
          ownLiveLabels[action] = fn
        end
      end
    end
  end

  ownPredicates.multipleDisplays = function() return #hs.screen.allScreens() > 1 end

  -- Whether the launcher is holding somebody else's list rather than its own catalog, which is
  -- what decides whether the key that steps back out means anything. The launcher already
  -- answers this about itself, so this only names the host, which this file is allowed to do.
  --
  -- It was declared by a binding and defined nowhere, and an unknown predicate is treated as
  -- always active by design, so the way out was listed in the hint panel at all times, including
  -- when there was nothing to leave. Looked up inside the closure rather than captured, since
  -- predicates are built before the loader has filled that table.
  ownPredicates.launcherHostingList = function()
    local host = modules[plan.identity.launcher or "launcher"]
    return host ~= nil and type(host.isHostingList) == "function" and host:isHostingList() == true
  end

  -- Repaint whichever list is on screen, for a plugin whose own answer arrives later than the
  -- keystroke that asked for it. A tab list, a relay list and a file search all fetch from
  -- something slower than typing, and without this the rows stay as they were when nothing had
  -- arrived yet.
  --
  -- A closure rather than a value because the surface it repaints is the launcher, one of the
  -- five host modules this file may name, and the lookup happens INSIDE it because this runs
  -- before the plan exists. Supplying it from here is what keeps the plugins from ever learning
  -- the launcher exists. Each one only takes a function and calls it when its own fetch
  -- finishes, which is why that logic could move out of the retired root and onto the plugins.
  local function redrawSurface()
    local host = modules[plan.identity.launcher or "launcher"]
    if host and host.refresh then host:refresh() end
  end

  -- This machine's own short name, the one every per host answer is keyed by. Read from scutil
  -- rather than from hs.host, deliberately, since hs.host.localizedName answers the friendly
  -- computer name and the two are different strings on the same machine. A curated arrangement
  -- keyed by one of them cannot be found with the other.
  --
  -- Shelled out once here and handed to whoever declared it, never probed per plugin. The tool
  -- comes through the door from the root's own declaration rather than being named in a command
  -- string, which is what makes an absent one a console line naming what it costs instead of a
  -- silent empty answer that leaves every per host lookup keyed by nothing.
  local localHostName = nil
  local scutil = sharedDepsScope.path("scutil")
  if scutil then
    localHostName = (hs.execute(scutil .. " --get LocalHostName") or ""):gsub("%s+$", "")
    if localHostName == "" then localHostName = nil end
  end

  ------------------------------------------------------------------------------
  -- The two feedback surfaces, built here because the root owns how a message
  -- looks and where it lands, and a plugin owns only what it has to say.
  --
  -- lib/hints.lua already carries both content strategies, ported whole, and nothing anywhere
  -- called either of them. So the clipboard's append and paste walk, whose own comment says the
  -- message is the only feedback those actions have, ran in complete silence, and the colour
  -- sampler copied a hex with nothing shown at all. Both plugins were written correctly against a
  -- callback nobody passed, which is this whole class of defect in its purest form, a mechanism
  -- present, a caller absent, and no evidence anywhere.
  --
  -- One panel instance each, reused, with a small mutable state table the closure writes before
  -- showing it again. Stacking a fresh panel per message would pile them up on screen, and both
  -- of these fire in bursts, a walk through history being the obvious one.
  ------------------------------------------------------------------------------

  local toastContent = hintsLib.toast({ ui = uiAtom })

  local messageState = { text = "" }
  local messagePanel = canvasPanel.new({
    placement = canvasPanel.placements.center,
    content = toastContent.message(messageState),
  })
  local messageTimer
  local function notify(text)
    messageState.text = tostring(text or "")
    messagePanel:show()
    -- The timer is held in a local that outlives the call on purpose. A Hammerspoon timer nobody
    -- refers to is collected before it fires, so the panel would simply stay on screen.
    if messageTimer then messageTimer:stop() end
    messageTimer = hs.timer.doAfter(1.2, function() messagePanel:hide() end)
  end

  -- A hex string as a colour table. Here rather than in the plugin that samples, since the
  -- plugin's answer is the hex a person asked to copy and this is only about drawing it.
  local function colorOf(hex)
    local digits = tostring(hex or ""):gsub("^#", "")
    local r, g, b = digits:match("^(%x%x)(%x%x)(%x%x)$")
    if not r then return { white = 0.5 } end
    return {
      red = tonumber(r, 16) / 255,
      green = tonumber(g, 16) / 255,
      blue = tonumber(b, 16) / 255,
      alpha = 1,
    }
  end

  local colorState = { hex = "", color = { white = 0.5 } }
  local colorPanel = canvasPanel.new({
    placement = canvasPanel.placements.center,
    content = toastContent.color(colorState),
  })
  local colorTimer
  local function showColor(hex)
    colorState.hex = tostring(hex or "")
    colorState.color = colorOf(hex)
    colorPanel:show()
    if colorTimer then colorTimer:stop() end
    colorTimer = hs.timer.doAfter(1.1, function() colorPanel:hide() end)
  end

  -- A titled list, for an action that touched several things at once and owes a line per thing,
  -- the workspaces apply naming the apps in a layout that were not open. Sized like the Hyper
  -- cheat sheet so the two read as one instrument. It stays up five seconds with the count
  -- shown in its footer, a Dismiss chip takes it down early, and the panel is reused so a
  -- second apply replaces the first rather than stacking. The countdown redraws the panel once
  -- a second through its own show, since the number is content and nothing else on the panel
  -- changes while it sits there.
  local reportState = { title = "", rows = {}, secondsLeft = 0 }
  local reportPanel
  local reportTimer
  local function dismissReport()
    if reportTimer then reportTimer:stop() end
    reportTimer = nil
    if reportPanel then reportPanel:hide() end
  end
  reportPanel = canvasPanel.new({
    placement = canvasPanel.placements.center,
    content = toastContent.list(reportState, dismissReport),
  })
  local REPORT_SECONDS = 5
  local function report(model)
    model = model or {}
    reportState.title = tostring(model.title or "")
    reportState.rows = type(model.rows) == "table" and model.rows or {}
    reportState.secondsLeft = REPORT_SECONDS
    reportPanel:show()
    if reportTimer then reportTimer:stop() end
    reportTimer = hs.timer.doEvery(1, function()
      reportState.secondsLeft = reportState.secondsLeft - 1
      if reportState.secondsLeft <= 0 then
        dismissReport()
      else
        reportPanel:show()
      end
    end)
  end

  -- Whether the launcher is part of this plan at all, asked of the first pass since the
  -- launcher's two words below are built before the second one. A word over a launcher that is
  -- switched off or blocked would answer nil forever while reporting itself delivered, so it is
  -- not published, and a plugin requiring it gets the root's ordinary line naming what it
  -- costs rather than a closure that quietly answers nothing.
  -- The switch's reload, held so a second toggle before it fires asks for nothing more. The
  -- timer lives in a local that outlives the call, since a timer nobody refers to is collected
  -- before it fires, and a reload is scheduled rather than called because one called inside
  -- the callback that asked for it is unreliable.
  local switchReloadTimer
  local function scheduleSwitchReload()
    if switchReloadTimer then return end
    switchReloadTimer = hs.timer.doAfter(0.2, hs.reload)
  end

  -- The staged choices a settings page made this load, identity to its new off state, held in
  -- memory until apply. Not persisted as they are made. A staged choice is a draft the person
  -- is still looking at, and apply runs on the stage closing, which is the moment the person is
  -- done with it. Saving each one at once would let any other reload, a config file saved or a
  -- crash, apply a half made set nobody announced, while losing a draft to such a reload costs a
  -- few presses, and the page that showed it is gone with it anyway.
  local pendingSwitches = {}

  local resumeStore = {
    read = function() return hs.settings.get(resumeLib.KEY) end,
    write = function(note) hs.settings.set(resumeLib.KEY, note) end,
    clear = function() hs.settings.clear(resumeLib.KEY) end,
  }

  -- The dry run every page question asks, the cascade and the preview alike, so they agree.
  local function switchDryRun(extra)
    local opts = { plan = resolver.plan, manifests = allManifests, user = pluginOverrides,
      libNames = libNames, switchable = isSwitchable }
    for k, v in pairs(extra or {}) do opts[k] = v end
    return opts
  end

  -- Saves the staged set, leaves a resume note, and schedules the one reload, answering whether
  -- anything was applied. resume is the place a tool described for itself, reopened after the
  -- reload. announce asks instead for one routine line naming what changed, said once the load
  -- is done, for an apply the person did not ask to watch. Nothing staged, or a reload already
  -- on its way, applies nothing.
  local function applySwitches(resume, announce)
    if next(pendingSwitches) == nil or switchReloadTimer then return false end
    local after = switchLib.preview(switchDryRun({ disabled = disabled, pending = pendingSwitches }))
    local line = switchLib.appliedLine(switchLib.changes(switchedOff, after.off), function(identity)
      local manifest = allManifests[identity]
      return manifest and manifest.about and manifest.about.title or identity
    end)
    switchLib.save(pendingSwitches, {
      switchable = isSwitchable,
      lockedBy = locks,
      read = function()
        local saved = hs.settings.get(switchLib.SETTINGS_KEY)
        return type(saved) == "table" and saved or {}
      end,
      write = function(list) hs.settings.set(switchLib.SETTINGS_KEY, list) end,
    })
    -- The staged set is kept, not cleared, so the page still shows what is about to apply for
    -- the moment before the reload lands, and the scheduled reload is what refuses a second
    -- apply and any further staging.
    local note = {}
    if type(resume) == "table" then note.open = resume end
    if announce then note.notify = line end
    if (note.open or note.notify) and not resumeLib.write(resumeStore, note) then
      log.w("Olm compose, the place to reopen after the plugin switch was not a valid note, "
        .. "so the reload reopens nothing")
    end
    scheduleSwitchReload()
    return true
  end

  local launcherIdentity = (firstPass.identity or {}).launcher or "launcher"
  local launcherInPlan = (firstPass.effective or {})[launcherIdentity] ~= nil

  local rootValues = {
    -- Two words over the launcher, which is core, for plugins that work in the app the
    -- launcher opened over. coveredApp answers that app and the id of the open, and
    -- refreshLauncher asks the launcher to draw again once a late answer lands. Both were
    -- siblings naming the launcher until phase three of the core split, and a plugin must not
    -- name a host, so the root publishes them by field name like every other word here. The
    -- launcher is looked up when a closure is called rather than now, since the closures are
    -- handed out before the launcher is configured and a person typing is what calls them.
    -- Neither is published when the launcher is not in the plan, see launcherInPlan above.
    coveredApp = launcherInPlan and function()
      local launcher = modules[launcherIdentity]
      if launcher then return launcher:coveredApp() end
    end or nil,
    refreshLauncher = launcherInPlan and function()
      local launcher = modules[launcherIdentity]
      if launcher then launcher:refresh() end
    end or nil,

    -- The shared when name to predicate table every gated binding is resolved against.
    predicates = ownPredicates,

    -- Repaint, under one name, for every plugin whose answer lands after the keystroke.
    redraw = redrawSurface,

    -- Two words for a presenting plugin, phase three of the chooser stage build, both taking
    -- the identity a plugin was registered under, its own presentation.name, so the same
    -- closure serves every presenting plugin rather than one built per plugin by a file that
    -- must never name one. Neither exists for VPN specifically, they exist for the question
    -- decision one and decision eight of the handoff brief both ask, and VPN is only today's
    -- one answer.
    --
    -- stagePresent is the hotkey door from outside the launcher, decision one, a plugin's own
    -- leader key asking the registry for its own presentation and handing it to the stage
    -- fresh, exactly what stage.present already means for the launcher's own hotkey. Named
    -- stagePresent rather than presentTool, review finding six, since this same file already
    -- has a local called presentTool, the predicate answering whether a declared tool is
    -- installed on this machine, and one word meaning two unrelated questions in a file its
    -- own header asks to be read top to bottom is worth avoiding even though nothing actually
    -- shadows, the local never having been a table key. Nil when either the registry or the
    -- stage has nothing to answer, in which case the plugin asked before its own registration
    -- or the stage's own configure had run, which is a wiring defect rather than a state a key
    -- press should silently swallow, so it is left to read as an inert press rather than
    -- guarded into looking intentional.
    stagePresent = function(name)
      local presentation = wiredRegistry.presentationFor and wiredRegistry.presentationFor(name)
      if presentation and stageModule then stageModule:present(presentation) end
    end,

    -- redrawPresented is the async status seam, decision eight, VPN's own onChange asking to
    -- be redrawn once its status changes while its own presentation, and no other, is what
    -- the stage is actually showing. A plugin not currently presented is silently a no op,
    -- since a tool's own background status changing is not a reason to redraw whatever
    -- unrelated list a person happens to be looking at.
    --
    -- resetRow, the trickle migration's own addition, Processes' own sortByLoad, is optional
    -- and forwarded straight to Stage:refresh(resetRow), which already answers it, nil
    -- behaving exactly as before for VPN and MenuSearch, neither of which ever passes a
    -- second argument. A one shot reorder has no row left to preserve, every row having
    -- moved, so it asks for the highlight back at the top the same way a query source
    -- rebuilding what the field means already does.
    --
    -- token, review finding M2, rework, docs/BRIEF-CONTRACT-V3.md, is a third and optional
    -- argument, a presentation table, for an answer that belongs to one specific child level
    -- rather than to name's own top level. Without one, name alone used to match at any
    -- depth, since a child inherits its parent's own name, decision two, so an async answer
    -- meant for a tool's top level, VPN and every other still single level presentation
    -- among them, was already landing on whichever child happened to be current instead, a
    -- silent wrong target for any plugin whose child rows are expensive or read a status the
    -- child does not show. Named, no token, now means exactly name's own top level, checked
    -- by table identity against wiredRegistry.presentationFor(name), the same stable table
    -- stagePresent already reaches for, since that is the one thing every level of a tool
    -- can be compared against that a shared name cannot. Given a token, the check is
    -- Stage:isCurrent(token) instead, table identity against whatever presentation table the
    -- caller closed over while building the child, so a child's own async answer lands on
    -- itself specifically, or not at all, browsertabs' own settings child passing itself this
    -- way. An async answer lands on its own level or not at all, the rule this word now keeps
    -- for every caller, token or none. Without resetRow the stage keeps the highlight on the
    -- same item by its key, so an answer that inserts a row above the person never moves them.
    redrawPresented = function(name, resetRow, token)
      if not stageModule then return end
      if token ~= nil then
        if stageModule:isCurrent(token) then stageModule:refresh(resetRow) end
        return
      end
      local top = wiredRegistry.presentationFor and wiredRegistry.presentationFor(name)
      if top and stageModule:isCurrent(top) then stageModule:refresh(resetRow) end
    end,

    -- stageHide, the trickle migration's own addition, Processes' own stopForced. A forced
    -- stop wants the shared window gone at once, the same instant feedback the retired
    -- standalone picker's own chooser:hide() gave before an async stop even started, rather
    -- than leaving a stale row on screen until the next sample or rescan corrects it. One
    -- closure under one name, the identical shape stagePresent and redrawPresented already
    -- take, since the question is "hide the shared window" and never which plugin is asking.
    stageHide = function()
      if stageModule then stageModule:hide() end
    end,

    -- stagePop, DisplayProfiles' own addition, contract v3's own back door for the one thing
    -- a child cannot express on its own, leaving a level a row pushed rather than one Backspace
    -- was pressed to leave. A child that pops itself does so from inside its own intercept,
    -- decision three's reserved case, a row that mutates the list it is on and stands, since
    -- popping the stack out from under the row that asked is itself the mutation, the list
    -- left standing being the parent rather than the child. Stage:pop already restores
    -- whatever sits below the top of the stack and answers false at the bottom exactly as an
    -- ordinary Backspace does, so a presentation calling this and then answering true from its
    -- own intercept gets the identical outcome literal Backspace already gives a child that
    -- declares no back of its own, just reachable from a row rather than only from the field
    -- going empty. Called more than once in the same intercept for a level that must skip past
    -- a now stale sibling, DisplayProfiles' own delete leaving both the delete frame and the
    -- profile it just removed behind in one press.
    stagePop = function()
      return (stageModule and stageModule:pop()) or false
    end,

    -- stagePush, docs/PLAN-ACTION-PANEL.md. A verb run from the action panel opens a level of
    -- its own tool through this, the same push a row's onSelect answering a child gets, since a
    -- verb has no onSelect to answer one through. Rename in Workspaces is the first.
    stagePush = function(child)
      return (stageModule and stageModule:pushChild(child)) or false
    end,

    -- stageSetQuery, the trickle migration's own addition, FileSearch's own parent row
    -- intercept, which puts the query for the level above in the field and the presentation
    -- stays open, the identical "swap the list in place" shape host/launcher's own paging
    -- already performs through Stage:setQuery directly, since the launcher holds the stage.
    -- A presenting plugin has no such direct hold, so this is the one word letting it reach
    -- the identical field control. host/stage's own _intercept, and legacy.lua's contract
    -- underneath it, already call refresh(true) once an intercept answers true, so nothing
    -- here has to ask for a rebuild on top of what the atom already gives every intercept.
    stageSetQuery = function(text)
      if stageModule then stageModule:setQuery(text) end
    end,

    -- stageSetPlaceholder, review finding H2. Declared by the clipboard's own manifest from
    -- the day it migrated and published by nobody until this rework, the exact failure class
    -- lib/services.lua's own owed() exists to catch, a declaration that is right, validated,
    -- reported satisfied, and delivered nowhere. The manage history page changes what the
    -- field means, not only what it holds, so it needs the identical direct control
    -- stageSetQuery gives the field's own text, Stage:setPlaceholder already public for the
    -- launcher's own paging to reach.
    stageSetPlaceholder = function(text)
      if stageModule then stageModule:setPlaceholder(text) end
    end,

    -- stageSelectedItem, review finding H6. host/stage's own selectedItem() already reads the
    -- live widget rather than a cache, guarded now on the stack being current rather than on
    -- isShowing so a presentation's own onPositioned seed call, which fires before the atom's
    -- own isVisible() would answer true, still gets the real row. Every one of the three
    -- trickle migrations built its own module local cache instead, seeded only by the atom's
    -- own poll and never cleared on close, so a cold open answered whatever the previous
    -- session last highlighted for one poll interval, up to and including what the clipboard's
    -- own delete key removed. This word is what lets a presenting plugin ask the widget
    -- directly instead of keeping a cache that cannot answer the question the widget already
    -- answers.
    stageSelectedItem = function()
      return stageModule and stageModule:selectedItem() or nil
    end,

    -- stageQuery, the live field text on the stage, "" when nothing is up. The BrowserTabs
    -- harness reads it beside stageSelectedItem so a round can tell a query that never landed
    -- from a ranking that was wrong, and no plugin reads it for behaviour.
    stageQuery = function()
      return stageModule and stageModule:query() or ""
    end,

    -- leaderHeld, whether any held leader in use is currently believed held, false
    -- when there is none. The BrowserTabs harness reads it to trace the leader through a round's
    -- typing and to refuse typing while it is held, since the default chooser's field yields every
    -- key to that leader then, and no plugin reads it for behaviour.
    leaderHeld = function()
      return anyHeldLeader(function(leader) return leader:isActive() == true end)
    end,

    -- stageTextBudget and stageTextWidth, the trickle migration's own addition, FileSearch's
    -- own fitDir, which used to measure a row's own room straight off the picker instance it
    -- held and now has no instance left to ask. Both proxy host/stage's own public methods,
    -- the identical thin shape every other stage word here already takes, 0 before an
    -- instance exists rather than raising, since a caller measuring before configure has run
    -- is a wiring defect this word should degrade under rather than crash over.
    stageTextBudget = function()
      return stageModule and stageModule:textBudget() or 0
    end,
    stageTextWidth = function(str, which)
      return stageModule and stageModule:textWidth(str, which) or 0
    end,

    -- stageSelectedRow, the menu search cache's own addition, docs/BRIEF-MENUSEARCH-CACHE.md.
    -- A background correction landing while a list is on screen has to know whether the
    -- highlight is still sitting on row one before it is safe to redraw without disturbing a
    -- position a person is actively considering, and host/stage already exposes
    -- Stage:selectedRow() publicly for exactly this, a plain number a consumer with no
    -- instance of its own has nowhere else to reach. One closure under one name, the
    -- identical shape stagePresent and redrawPresented already take, since the question is
    -- "what is the shared window doing right now" and never which plugin is asking it.
    stageSelectedRow = function()
      return stageModule and stageModule:selectedRow() or nil
    end,

    -- One line of feedback, one sampled colour, and one titled list, all on the shared overlay
    -- so they read as part of the same interface as the cheat sheet and the action bar.
    notify = notify,
    showColor = showColor,
    report = report,

    -- This machine's identity, for anything keyed per host.
    host = localHostName,

    -- A scope closure used to sit here, the attached displays as one sorted string of screen
    -- UUIDs, published under the field name scope for whichever plugin remembered state per
    -- arrangement. Its two consumers, DisplayMemory and WindowMemory, are both gone, and the
    -- plugin that replaced them, Workspaces, keys on the point geometry of the attached screens
    -- rather than on their identity, so vendor, model, pixel resolution, and plug order all stop
    -- mattering and two identical panels can no longer be confused. That is a fingerprint only
    -- the plugin that reads it can define, so it computes its own rather than taking one from
    -- here, and a root value with no consumer left is a promise nobody is owed. Anything wanting
    -- a shared notion of a location again should say what it means by one before this comes back.

    -- Where a plugin keeps data a person is meant to be able to read, edit and commit. Per
    -- declaring plugin, since two plugins sharing one file would silently overwrite each
    -- other. Inside the live config directory on purpose rather than under the storage atom's
    -- own roots, because this is the tracked layer a person edits by hand. A store a plugin
    -- writes, whether on its own or when a person acts, belongs under the storage atom's
    -- durable root instead, which is where workspaces keeps its layouts, speedtest its runs.
    -- Workspaces sat here for a while, first git ignored while it recorded every window move
    -- by itself and then tracked for one evening as hand taken snapshots, and both were the
    -- same mistake, a machine's own record inside the configuration tree.
    storePath = servicesLib.perName(function(name)
      return hs.configdir .. "/config/" .. name .. ".json"
    end),

    -- The settings plugin's own two words, a reader and a writer over the overlay display
    -- resolver's live mode, backed by the one instance step E already built. Both are thin
    -- closures over overlay's own public self.mode and self.setMode, added there rather than
    -- duplicated here, so this file still never calls hs.settings for this policy itself.
    overlayPlacementMode = function()
      return overlay and overlay.mode and overlay.mode() or nil
    end,
    setOverlayPlacementMode = function(mode)
      if overlay and overlay.setMode then overlay.setMode(mode) end
    end,

    -- The theme switcher's three words over the themes store built in step B, the live name,
    -- the sorted names, and a writer that applies a theme at once and answers whether the
    -- name had a file. The store owns the persisted choice under its own hs.settings key.
    themeName = function() return themes.current() end,
    themeNames = function() return themes.names() end,
    setTheme = function(name) return themes.set(name) end,

    -- The plugins page's four words over the one switch, lib/pluginswitch.lua. The catalog lists
    -- only what lives under plugins, since core is not something a person switches, each row
    -- with what this load has and, while anything is staged, what applying would leave. The
    -- cascade is a dry run of the resolver's own plan with no modules and no probing, so asking
    -- it is free. Staging writes nothing, and apply saves the whole staged set and schedules
    -- one reload, since whether a plugin runs is decided once per load. The stage closing
    -- applies too, see the observer where the stage is wired.
    pluginCatalog = function()
      local preview = next(pendingSwitches) ~= nil
        and switchLib.preview(switchDryRun({ disabled = disabled, pending = pendingSwitches }))
        or nil
      return switchLib.catalog({ manifests = allManifests, directories = directories,
        switchable = isSwitchable, disabled = disabled, lockedBy = locks,
        offBecause = offBecause, pending = pendingSwitches, preview = preview })
    end,
    -- What the choice for identity brings with it, measured against every other staged choice.
    -- A staged choice answers what applying it does, an unstaged one what staging it would.
    pluginCascade = function(identity)
      local others = {}
      for name, off in pairs(pendingSwitches) do
        if name ~= identity then others[name] = off end
      end
      local base = switchLib.proposed(disabled, others)
      local off = pendingSwitches[identity]
      if off == nil then off = not base[identity] end
      return { off = off, staged = pendingSwitches[identity] ~= nil,
        others = switchLib.cascade(switchDryRun({ disabled = base, identity = identity, off = off })) }
    end,
    stagePluginSwitch = function(identity, off)
      if switchReloadTimer then return false, "the plugins are being applied, Olm is reloading" end
      return switchLib.stage(pendingSwitches, identity, off, {
        switchable = isSwitchable,
        lockedBy = locks,
        current = function(name) return disabled[name] == true end,
      })
    end,
    applyPluginSwitches = function(resume)
      return applySwitches(resume, false)
    end,
  }

  local rootFanned = servicesLib.fanOut(manifests, rootValues, "root")

  plan = resolver.plan({
    manifests = allManifests,
    user = pluginOverrides,
    disabled = disabled,
    switchable = isSwitchable,
    present = presentTool,
    libNames = libNames,
    modules = modules,
    libs = libs,
    data = servicesLib.merge(fannedData, rootFanned),
    -- Olm's own all layer, the key each list's shared verbs sit on, a core default the person
    -- moves in the lists section of config/keymap.lua and never here.
    listKeys = keymapLib.listDefaults,
  })

  -- The person's lists section, laid over every list's bindings once, here, before the action bar,
  -- the action panel, the keymap and the contexts read any of them, so a list key moved there
  -- shows its new chord everywhere it is bound. Every default is placed on the list role's leader
  -- first, and a person's chord may open with any held leader in the catalog, a chord opening with
  -- anything else being a problem line. A section naming the list of a
  -- plugin that exists and is not loaded this time is a routine line, the rule a keys entry for a
  -- plugin switched off follows.
  do
    -- Keyed the way the resolver keys plan.contexts, the declared context or else the identity,
    -- which is the key allManifests is keyed by.
    local listNames = {}
    for identity, manifest in pairs(allManifests) do
      if type(manifest.surface) == "table" then
        listNames[manifest.surface.context or identity] = true
      end
    end
    local heldLeaderNames = {}
    for _, spec in ipairs(leaderSpecs) do
      if spec.held then heldLeaderNames[spec.name] = true end
    end
    -- A list chord opening with no held leader belongs to the open list's own field, so it is
    -- checked against what that field already reads, asked of the provider that serves, whose
    -- field it is. The swift chooser answers for its native field, or for the default chooser
    -- while that serves in its place. A provider with no answer of its own, legacy, is checked
    -- against the default chooser's field as before.
    local fieldProvider = (chooserProvider and chooserProvider.uses) and chooserProvider
      or (chooserAtom.providers and chooserAtom.providers.default)
    local listProblems, listNotes = keymapLib.applyLists(plan.contexts, keymapConfig.lists, {
      listLeader = listLeaderName,
      heldLeaders = heldLeaderNames,
      modifierLeaders = modifierLeaderSets,
      fieldUses = fieldProvider and fieldProvider.uses and function(key, mods)
        return fieldProvider.uses(keyTable[key], mods)
      end or nil,
      keycodes = keyTable,
      known = function(name) return listNames[name] == true end,
    })
    for _, problem in ipairs(listProblems) do keymapProblems[#keymapProblems + 1] = problem end
    for _, note in ipairs(listNotes) do log.i("Olm keymap, " .. note) end
  end

  for _, p in ipairs(plan.problems or {}) do
    log.e("Olm compose, plan problem, " .. tostring(p.kind) .. " at " .. tostring(p.where) .. ", " .. tostring(p.why))
  end

  -- Degradation, said out loud. Every optional tool and optional value that did not arrive is
  -- already collected into plan.degraded, and nothing read it. lib/plugins.lua carries a report
  -- that would have printed it and has no callers, and test/spec.lua says of the same list that
  -- nothing asserts on it, so a plugin quietly losing part of itself was the one planning outcome
  -- this layer worked out and then dropped. A blocked plugin is loud and a degraded one was
  -- silent, which is backwards, because the degraded one still comes up and still looks fine.
  --
  -- Read off the final plan rather than the first pass on purpose. The first runs before the root
  -- has handed over its own values, so every root sourced optional need looks absent there, and
  -- reporting that pass would announce a dozen losses on a perfectly healthy config. The required
  -- branch of resolve's own data check already makes this distinction, recording a root sourced
  -- absence as an obligation rather than a failure, and this is the same fact read at the point
  -- where it has stopped being true.
  for name, losses in pairs(plan.degraded or {}) do
    for _, loss in ipairs(losses) do
      log.w("plugin '" .. name .. "' loaded degraded, " .. loss)
    end
  end

  ------------------------------------------------------------------------------
  -- STEP G. Leaders, continued. The leader specs above, keycodes and policies, are
  -- reused here for the leaders rather than resolved a second time.
  ------------------------------------------------------------------------------

  -- The one cheat sheet host, named outright since it is core. Every leader whose policy states a
  -- sheet reveals it, and step K hands it each leader's rows and layout.
  local leaderSheetModule = modules[plan.identity.leadersheet or "leadersheet"]

  -- The flat root argument namespace, deps.args, the only channel a non configure wiring
  -- step can read a value through when that step's own signature is not opts shaped. Nothing
  -- is owed through it now, the window leader owns the predicate gate and is handed the table
  -- when it is configured, but the namespace stays for a plugin that needs one.
  local wiringArgs = {}

  -- Assigned rather than declared, joining the forward declared set at the top of this
  -- function in phase three. Needed here, synchronously, rather than only inside a later
  -- closure, because the surface adapters loop a little further down builds its answer NOW,
  -- not the moment a key is pressed, so stageModule has to be real before that loop runs
  -- rather than merely before Hammerspoon starts idling. wiredRegistry, assigned further
  -- down this file, is not moved, since the surface adapters loop still runs after that
  -- assignment in this function's own sequence and only isShowingFor, a closure, reaches it
  -- ahead of that point in the source.
  stageModule = modules[plan.identity.stage or "stage"]

  -- Staged plugin choices apply when the stage goes away, by whatever route, since that is the
  -- person saying they are done. Leaving a page for the level above is not the stage going away,
  -- so it applies nothing. Dismissing means done, so nothing is reopened, and one line after the
  -- reload says what changed.
  if stageModule and stageModule.onClosed then
    stageModule:onClosed(function() applySwitches(nil, true) end)
  end

  local contextOwners = hintsLib.contextOwners(plan, manifests)

  -- Whether a list is open, lib/listopen.lua, one named list for the wiring, the action panel and
  -- the surface adapters, and any list for every leader, since no hold reveals a sheet over an
  -- open list and a leader whose policy goes quiet over lists reads the same answer. Both walk the
  -- contextOwners table the predicates route through, so this gate and the modal rule on the
  -- leader with contexts can never disagree about what an open list is. The registry is built
  -- after the leaders that close over this, so the presentation is asked through it at each call.
  local surfaceOf = listOpenLib.surfaceOf
  local listOpenDeps = {
    owners = contextOwners,
    identity = plan.identity,
    presentationFor = function(identity)
      return wiredRegistry and wiredRegistry.presentationFor and wiredRegistry.presentationFor(identity)
    end,
    stage = stageModule,
    modules = modules,
    manifests = manifests,
  }
  local function isShowingFor(contextName) return listOpenLib.isShowing(contextName, listOpenDeps) end
  local function anyListShowing() return listOpenLib.anyShowing(listOpenDeps) end

  ------------------------------------------------------------------------------
  -- STEP H. The leaders.
  ------------------------------------------------------------------------------

  -- One leader per entry of the leaders table, from the specs built in step F, and the plain
  -- leader a keymap row with no leader binds on. Each gets its trigger, its policy and the module
  -- its hold reveals, and this loop is the only place a trigger is chosen, a held one for an entry
  -- stating a key, a modifier one for an entry stating mods, and a composite of the two for an
  -- entry stating both, so nothing below knows how many leaders there are. They are built here and kept as
  -- candidates, and step J keeps only those some bound row uses, once the keymap says which, so a
  -- leader nothing uses is never bound, started or remapped. A held leader whose key
  -- resolves to no keycode is not built, and step J names it when a row needs it.
  --
  -- The open list test is anyListShowing above. The hold reveal used to be the root's own pair of
  -- closures for Hyper and the window leader's own pair for itself. It is the adapter's now, which
  -- keeps the one rule both pairs followed, nothing is revealed over an open list.
  local leadersByName = {}
  -- The leaders hosting at least one list key, by name, read off the lists as applyLists left them.
  -- A chord opening with no leader is false there and names none. A modifier leader in this set
  -- seals over an open list, which is only known here, once the lists are laid out.
  local hostsListKey = {}
  for _, block in pairs(plan.contexts or {}) do
    for _, b in ipairs(block.bindings or {}) do
      if b.chord ~= false and type(b.leader) == "string" then hostsListKey[b.leader] = true end
    end
  end
  local candidateLeaders, candidateList = {}, {}
  for _, spec in ipairs(leaderSpecs) do
    local leader = nil
    if spec.held then
      -- A leader on two triggers is built even when its key resolved to no keycode, since its
      -- modifiers still work, and its held half then says once at start that it did not start.
      if spec.keyCode ~= nil or spec.mods ~= nil then
        local sheet = nil
        if spec.policy.sheet then
          -- THE SEAM. LeaderSheet is one of the host modules this file may name.
          sheet = leaderSheetModule
          if not sheet then
            log.w("Olm compose, the " .. spec.catalogName .. " leader states a sheet, and the leader sheet "
              .. "host did not load, so a hold reveals nothing")
          end
        end
        local trigger = heldTriggerLib.new({ chord = chordKeyAtom, keyCode = spec.keyCode, key = spec.key })
        if spec.mods ~= nil then
          -- The modifier half seals over an open list on the terms a modifier leader does, when its
          -- leader hosts a list key, and leaves a row asking for a modifier its set already holds to
          -- the held half, which tells the two apart. The held half seals as it always does.
          trigger = compositeTriggerLib.new({ triggers = {
            trigger,
            modifierTriggerLib.new({ mods = spec.mods, sealsOverLists = hostsListKey[spec.name] == true,
              skipOverlap = true }),
          } })
        end
        leader = leaderLib.new({
          name = spec.name,
          trigger = trigger,
          policy = spec.policy,
          sheet = sheet,
          keyCode = spec.keyCode,
          listOpen = anyListShowing,
          predicates = ownPredicates,
          holdDelay = policy.chord.holdDelay,
          tapThreshold = policy.chord.tapThreshold,
        })
      end
    else
      -- A leader of modifiers is the modifier trigger handed its set as the base, with the policy
      -- its entry states, and it seals over an open list when it hosts a list key. It has no tap,
      -- since holding real modifiers is ordinary typing. A sheet is opt in, and it is revealed by
      -- the trigger once exactly that set has been held for the hold delay.
      local sheet = nil
      if spec.policy.sheet then
        -- THE SEAM. LeaderSheet is one of the host modules this file may name.
        sheet = leaderSheetModule
        if not sheet then
          log.w("Olm compose, the " .. spec.catalogName .. " leader states a sheet, and the leader sheet "
            .. "host did not load, so holding it reveals nothing")
        end
      end
      leader = leaderLib.new({
        name = spec.name,
        trigger = modifierTriggerLib.new({ mods = spec.mods, sealsOverLists = hostsListKey[spec.name] == true }),
        policy = spec.policy,
        sheet = sheet,
        listOpen = anyListShowing,
        predicates = ownPredicates,
        holdDelay = policy.chord.holdDelay,
      })
    end
    if leader then
      candidateLeaders[spec.name] = leader
      candidateList[#candidateList + 1] = leader
    end
  end
  -- The plain leader, a modifier trigger with an empty base set, so a keymap row with no leader is
  -- claimed through hs.hotkey on its own modifiers exactly as the binder used to claim it itself.
  -- Its policy is empty, no tap, no sheet, and it is never held, so a waiting action
  -- on a plain combo runs at once.
  local plainLeader = leaderLib.new({
    trigger = modifierTriggerLib.new({ mods = {} }),
    policy = {},
    listOpen = anyListShowing,
    predicates = ownPredicates,
  })
  candidateList[#candidateList + 1] = plainLeader

  -- Runs fn once no held leader is down, for a launcher row whose action waits for release.
  local function afterLeadersRelease(fn)
    return leaderLib.afterAllReleased(leaderList, fn)
  end

  ------------------------------------------------------------------------------
  -- Presentation deps, one shared table for every lib/hints.lua call this file
  -- makes, the action bar's model and the action panel's rows among them.
  ------------------------------------------------------------------------------

  -- Takes down whichever leader's sheet a hold put up, which each leader answers only for its
  -- own, so an action that runs while a sheet shows clears it whichever leader revealed it.
  local function hideSharedOverlay()
    for _, leader in ipairs(leaderList) do leader:conceal() end
  end

  -- The kind derivation reads a binding's position and the fixed generic navigation set,
  -- and gets these four wrong on that evidence alone, since each sits below the first
  -- binding in its own context yet moves the view or leaves a page rather than acting on
  -- anything selected. The retired root called the first three navigation by hand, and this
  -- table is the override seam actionKinds reserves for exactly that one small correction.
  --
  -- The fourth is the same shape as leavePage above, a step back out of a swapped list, and it
  -- earns the same correction for the same reason. The action panel draws its own Back row, so
  -- a step out classified as a verb would be listed twice, once as the panel's Back and once as
  -- a row of its own. These are action names and no plugin is named, which is the only reason
  -- this table may sit in this file at all.
  local actionKindOverrides = {
    scrollPreviewDown = "navigation",
    scrollPreviewUp = "navigation",
    leavePage = "navigation",
    leaveManageHistory = "navigation",
  }

  -- The action panel borrows the one list instance and leaves current() naming the list, so the
  -- action bar and the list's field keys ask this rather than the stage. It answers the panel row
  -- under the highlight, an empty table with none, or nil while the panel is closed. ActionPanel is
  -- one of the host modules this file may name.
  local function actionPanelShowingRow()
    local ap = modules[plan.identity.actionpanel or "actionpanel"]
    if not (ap and type(ap.isOpen) == "function" and ap:isOpen()) then return nil end
    return (stageModule and stageModule:selectedItem()) or {}
  end

  local hintsDeps = {
    predicates = ownPredicates,
    glyphFor = cheatSheetAtom.glyphFor,
    owners = contextOwners,
    -- The identity whose manifest icons the panel's own Back row reads its key against.
    panelOwner = plan.identity.actionpanel or "actionpanel",
    -- The key panel's header, this Olm's name and version.
    title = "Olm " .. tostring(olm.version),
    ui = uiAtom,
    chordLabel = chordLabel,
    -- leaderNames hands over each leader's already resolved word rather than the catalog
    -- itself, keyed by the name a row spells its leader with, since deciding what a leader is
    -- called belongs to this file and lib/hints.lua must not learn it by name any more than it
    -- learns any other plugin's name. leaderName is the word for a list binding that names no
    -- leader, one built by hand rather than through applyLists, the list role's leader.
    leaderNames = leaderNamesByLeader,
    leaderName = leaderNamesByLeader[listLeaderName],
    -- kinds carries the same action kind overrides the actionKinds call below is given,
    -- since rowsFor derives kinds a second time inside hints.lua, and it must see the same
    -- overrides the panel's own kindOf uses or the panel rows and verbsIn drift apart.
    kinds = actionKindOverrides,
    -- liveLabels, harvested above off whatever each module offers rather than written here, so
    -- a word that follows a plugin's own live state reaches the action bar and the action panel
    -- with this file still naming no plugin. It was absent, on the grounds that the only case
    -- then in existence, the launcher's Run reading as Open over an application row, was that
    -- plugin's own business and there was nowhere generic to reach it from. The generic place is
    -- the same one the predicates already use, one screen up, and a picker whose primary key
    -- means something else on a second page is what made the difference worth paying. The
    -- launcher's own case is still its own and is not routed through here.
    liveLabels = ownLiveLabels,
    -- The words the level on screen gives its primary and its secondary, asked of the stage for
    -- the presentation it shows, its labels member, and answered only for the context that is
    -- showing, since a level's words mean nothing for any other list. Asked live on every call,
    -- so a word follows the highlighted row. Read late, since the stage is built further down.
    labelsFor = function(contextName)
      if not stageModule or stageModule:current() ~= contextName then return nil end
      return stageModule:labels()
    end,
    -- Whether Backspace on an empty field leaves the level showing, a level pushed over another,
    -- so the key panel lists Back only when it does something.
    backs = function(contextName)
      return stageModule ~= nil and stageModule:current() == contextName and stageModule:depth() > 1
    end,
    -- The panel row under the highlight while the action panel is open over the list, an empty
    -- table when it is open on no row, and nil while it is closed, so the action bar describes the
    -- panel the person is looking at rather than the list it borrowed. Read late, like the stage.
    actionPanel = function() return actionPanelShowingRow() end,
    -- The title of a level a verb opened in the action panel, which heads it in the popover.
    actionPanelTitle = function()
      local panel = modules and modules[plan.identity.actionpanel or "actionpanel"]
      return panel and panel.levelTitle and panel:levelTitle() or nil
    end,
  }

  -- LeaderSheet and QueryScope both keep what configure gave them across calls, and the sheet
  -- takes the renderer from this first one, so the base opts built here are reused verbatim for
  -- the post register second call in step K, instead of being recomputed and risking two
  -- slightly different tables answering for the same plugin in the same run.
  -- The sheet reads no person data since phase four of the core split. The app toggles reach
  -- it as keymap rows like every other key, assembled in step K with everything else.
  local leaderSheetOpts = {
    cheatSheet = cheatSheetAtom,
  }

  -- The leader sheet's root owned values are NOT all built here. It declares sheets and
  -- predicates. predicates reaches it through the root fan out above, a root value other plugins
  -- ask for by the same name. sheets is each leader's own rows from the keymap, which exist only
  -- once the keymap is built after register, so step K builds it and configures the host a second
  -- time with both.
  local queryScopeOpts = {
    matcher = chooserAtom.matchers and chooserAtom.matchers[policy.matcher],
    rank = chooserAtom.rank,
    stampIcons = iconRows.stampAll,
  }

  -- ActionPanel's own three, built here rather than only in step K because the ordinary stage
  -- two configure reaches every plugin in the plan and this one REFUSES to be configured
  -- without kindOf. Handing it nothing there and everything later meant one raised problem on
  -- every single run for a plugin that was going to be configured properly a moment later.
  --
  -- All three are derivable this early. kindOf reads the plan alone. rowsFor reads the plan and
  -- the presentation deps, both of which exist. run is the one that does not, since the dispatch
  -- table is not built until between stages six and seven, so it is forward declared just above
  -- and reached through the closure at the moment a verb is actually run, which is always long
  -- after the whole pipeline has finished.
  -- surfaceAdapters is declared here and filled further down, the same forward declaration as
  -- dispatchTable, so the action panel's call below reaches the real list once it exists.
  -- surfaceByOwner is the same adapters keyed by the plugin that owns them, filled beside them.
  local dispatchTable, surfaceAdapters, surfaceByOwner
  local actionKinds = hintsLib.actionKinds(plan, actionKindOverrides)
  local actionPanelOpts = {
    kindOf = function(action) return actionKinds[action] end,
    rowsFor = function(contextName, hosted) return hintsLib.rowsFor(contextName, plan, hintsDeps, hosted) end,
    -- value is a choice made in a level the verb opened, handed to the plugin's method,
    -- docs/PLAN-ACTION-PANEL.md, and nil for a verb run plainly.
    run = function(action, _, value)
      local fn = dispatchTable and dispatchTable[action]
      if fn then fn(value) end
    end,
    -- Calls a named method of the plugin owning the context the panel opened for, what a
    -- verb's applies and choices name, through the same adapters the dispatch routes every verb
    -- through. The owner rather than whichever list is showing, since a hosted list is showing
    -- inside the launcher while its verbs belong to the tool that made its rows, and the row is
    -- handed over as that tool made it, through the query scope that wrapped it. The second
    -- answer says whether the method exists, so the panel can tell a verb that does not apply
    -- from one whose surface cannot say.
    call = function(method, item, contextName)
      local owner = contextName and contextOwners[contextName]
      local surface = (owner and surfaceByOwner and surfaceByOwner[owner])
        or navLib.activeSurface(surfaceAdapters)
      if not (surface and type(surface[method]) == "function") then return nil, false end
      local queryScopeModule = modules[plan.identity.queryscope or "queryscope"]
      if queryScopeModule and type(queryScopeModule.payloadOf) == "function" then
        item = queryScopeModule:payloadOf(item)
      end
      return surface[method](item), true
    end,
    -- The panel filters its own rows through the one rank engine when the list under it owns
    -- its filtering. substring is what it always did there, kept until phase three of
    -- docs/PLAN-UNIFIED-SEARCH.md moves every list onto the one search.
    rank = chooserAtom.rank,
    ownRowsMatcher = chooserAtom.matchers and chooserAtom.matchers.substring,
  }

  -- What services.perPlugin builds a plugin's own data from, its scoped tool path adapter and
  -- its recency instance. It once also took the hints deps to build a docked hint panel per
  -- surfaced plugin, which the action bar inside the chooser's own canvas replaced.
  local perPluginDeps = { libs = libs, deps = sharedDepsScope }

  local perPluginData = servicesLib.perPlugin(plan, manifests, perPluginDeps)

  -- THE SEAM. Stage's own data, built here for the same reason ActionPanel's own three are at
  -- actionPanelOpts above, source root in its manifest for a value only the root can compute,
  -- delivered by hand into wireData.stage below rather than through the fan out, the identical
  -- door ActionPanel's own kindOf, rowsFor, and run already go through and are declared the
  -- same way at host/actionpanel/manifest.lua. chooser and theme are exactly what a surfaced
  -- plugin already receives ambiently, handed over explicitly because this host opens no
  -- context of its own and so earns nothing through that entitlement.
  --
  -- No placeholder here. It was added once, briefly, and reverted, finding eleven of the phase
  -- two adversarial review. SHIPPED_POLICY is read by the ambient grant every surfaced plugin
  -- inherits, not only by this host, so a value shipped there for the stage's own construction
  -- time field silently rewrote what five other tools say on their own empty field, the
  -- launcher, processes, emoji, textcase, and filesearch among them, every one of them falling
  -- back to that grant precisely because it used to answer nil. The stage never even shows the
  -- value it was fixing, Stage:present sets a presentation's own placeholder before every show,
  -- so the construction time field is never on screen for a single frame, and host/stage/
  -- init.lua now writes a literal there instead of asking anyone for one.
  --
  -- THE SEAM, its second half. The action bar under the stage's one window answers for whichever
  -- presentation is actually up, VPN's own keys while VPN is presented and the launcher's again
  -- after pop, decision seven of phase three, contexts and hints follow current(). So this builds
  -- ONE footer collaborator for the stage, here, naming no plugin, asking stageModule:current()
  -- each time the instance asks for the model, and the stage's labels through hintsDeps above.
  -- It replaced the docked hint panel on 2026-10-23, docs/PLAN-ACTION-BAR.md, a CanvasPanel
  -- under the window that appeared after a pause, built here the same way for the same reason.
  local function stageFooter()
    local contextName = (stageModule and stageModule:current()) or (plan.identity.launcher or "launcher")
    return hintsLib.footerModel(contextName, plan, hintsDeps)
  end
  local stageOpts = {
    chooser = chooserAtom,
    theme = policy.chooserTheme,
    stampIcons = iconRows.stampAll,
    footer = stageFooter,
    -- A press on an entry of the bar runs that entry's action, the same dispatch a verb chosen in
    -- the action panel runs, so Actions opens the panel and the primary chooses the row.
    footerAction = actionPanelOpts.run,
  }

  -- fannedData WINS, and its absence here altogether was the single worst defect in this build.
  --
  -- Everything a person supplies arrives in it, cfg.shared fanned out by field name and
  -- cfg.plugins data per plugin, and it was handed to resolver.plan and then to nothing else. So
  -- every one of those declarations was read, validated, reported as satisfied, and then
  -- dropped on the floor before any plugin was configured. The report said no problems because
  -- as far as the plan was concerned there were none.
  --
  -- What it actually cost. The Hyper overlay had no application registry and no toggle list,
  -- so the whole app half of it was empty, which is most of what that overlay is for. Display
  -- profiles lost the person's own profiles, the clipboard lost its shortcut, browser tabs
  -- lost its Chrome bundle id, display memory lost its terminal, and window management lost
  -- its own settings and margins and ran on shipped defaults close enough to look right.
  --
  -- It comes LAST, so it wins, which is the order lib/services.lua's own merge documents and
  -- the reverse of what this call did once it was added back. Mechanism derived data sits under
  -- root computed data, and root computed data sits under the person's own choice. The reason is
  -- the same one this whole session has been about. A value a person sets and a plugin never
  -- receives, and a value a person sets that something else quietly overrules, are the same
  -- defect wearing different clothes, and neither leaves any evidence. In practice the two
  -- barely overlap, since a root computed field is one nobody is asked to supply, and where they
  -- do overlap the person said it on purpose.
  local wireData = servicesLib.merge(perPluginData, rootFanned, {
    leadersheet = leaderSheetOpts,
    queryscope = queryScopeOpts,
    actionpanel = actionPanelOpts,
    stage = stageOpts,
  }, fannedData)

  -- What step K hands over in its own later calls, recorded as it goes so the delivery check at
  -- the very end of this file can see it. Three host modules are configured a second time down
  -- there, with values that only exist once registration has run, and those values never pass
  -- through wireData at all. Auditing before they were made would report five perfectly
  -- delivered needs as missing, and a check that cries wolf is worse than no check, since the
  -- next real line in the same list gets read as noise too.
  local lateData = {}

  local ambientServices = servicesLib.ambient({
    chooser = chooserAtom,
    theme = policy.chooserTheme,
    placeholder = policy.placeholder,
    matcher = chooserAtom.matchers and chooserAtom.matchers[policy.matcher],
    matchers = chooserAtom.matchers,
    -- The docked companion pane, one per plugin that asks, so the factory is what is shared.
    -- Its chrome and its quiet state are CanvasPanel's and its text is the kit's, named here
    -- and nowhere else, so a pane in a plugin draws only its own content. Its drawing backend
    -- follows the chooser that serves, see dockedPaneBackend above obj.run.
    dockedPane = function(spec)
      return dockedPaneLib.new({
        ui = uiAtom,
        surface = canvasPanel.surfaceElements,
        emptyState = canvasPanel.emptyStateElements,
        backend = dockedPaneBackend(chooserAtom, chooserProvider),
      }, spec)
    end,
    log = log,
  })

  wiredRegistry = registryLib.new({ apiVersion = API_VERSION, log = log })

  local function describeForRegistry(name, planArg)
    -- matchers, contract v2 decision one, docs/BRIEF-CONTRACT-V2.md, is what lets the
    -- registrar refuse a presentation.matcher naming a strategy the Chooser atom does not
    -- export, loudly, at register, rather than have host/stage/init.lua's own _resolveMatcher
    -- discover the typo at runtime and quietly fall back to the root default. The identical
    -- table ambientServices.matcher above is already resolved against for every unmigrated
    -- consumer, so this names no new concretion, only hands the registrar the same map.
    return registrarLib.describe(name, planArg, modules, manifests, registryMeta,
      API_VERSION, { merge = defaultsLib.merge, redraw = redrawSurface, log = logFn,
        matchers = chooserAtom.matchers })
  end

  -- Which context actions repeat while held, rather than firing once per press, a small
  -- root owned set of generic navigation verbs rather than a fact about any one plugin.
  local repeatableActions = {
    selectNext = true, selectPrev = true,
    scrollPreviewDown = true, scrollPreviewUp = true,
  }

  -- Named rather than written inline at the one call site, so it can be recorded and read back.
  -- Whether an action routes to a differently named method is exactly what somebody checking
  -- whether a bound key reaches anything has to know, and with the map buried in a call
  -- argument the only way to find out was to press the key.
  local navMethodFor = {
    closeChooser = "hide",
    refreshList = "refresh",
    revealInFinder = "reveal",
  }
  -- The action names satisfied by a closure this file builds rather than by any surface. Kept
  -- beside the map for the same reason, since an action in here needing no surface method is
  -- the difference between a key that is fine and a key that is dead.
  local navExceptionNames = { openActionPanel = true }
  local bindOneInContext = navLib.bindOne(repeatableActions)

  -- A dot called control surface for every plugin this plan actually built a context for,
  -- wrapping whichever calling convention that plugin's own module happens to use. lib/
  -- nav.lua calls every surface method with a bare dot, by design, so a colon style module
  -- handed over unwrapped would fail on arity the moment its own isShowing or selectNext
  -- ran, the exact defect three real surfaces shipped with once already. Ordered by
  -- plan.order, this file's own answer to which surface wins if two are ever open at once,
  -- since nothing here proves that can never happen and something has to decide.
  --
  -- Every method is looked for on the DECLARED SURFACE first and on the plugin root second,
  -- and that order is the whole fix for a disjoint that made no sense from the outside. This
  -- read the root and only the root, so a plugin keeping its list on a submodule answered
  -- nothing here. Two separate consequences followed and both were silent.
  --
  -- lib/nav.lua picks whichever surface answers isShowing first and then calls the action on
  -- it. A root with no isShowing is never picked at all, so the clipboard and menu search were
  -- invisible to routing even while open. Emoji was picked, having isShowing on its root, and
  -- then had no selectNext there to call. VPN keeps every one of these on its root, so VPN
  -- alone worked, and the result a person sees is navigation that works in one list and does
  -- nothing in three others with no error anywhere and no way to guess why.
  --
  -- Nothing is cached. The surface may be a member that BUILDS the adapter when asked, so a
  -- picker rebuilt after a reconfigure would leave a cached holder pointing at a dead one, and
  -- a table walk per key press costs nothing worth protecting.
  -- identity, phase three, is asked of the registry INSIDE the proxy, every single access,
  -- rather than once by the caller building it, review finding one. w.register has not run
  -- yet at the point this whole loop executes, stage five of the eight fixed stages, so an
  -- eager question asked out here always answers nil for a presenting plugin, forever,
  -- since nothing ever asks again. This file's own comment already states the rule the eager
  -- version broke, nothing here is cached and a table walk per key press costs nothing worth
  -- protecting, so the presenting question belongs inside __index with everything else this
  -- proxy already resolves lazily, not outside it as a one time decision.
  local function surfaceAdapterFor(module, spec, identity)
    return setmetatable({}, {
      __index = function(_, methodName)
        if identity and stageModule and wiredRegistry and wiredRegistry.presentationFor
          and wiredRegistry.presentationFor(identity) then
          -- Wrapped in the identical pcall guard the non presenting branch below already
          -- gives every method it resolves, phase three review's own residue on finding
          -- one. Returning the raw closure here meant a raise inside the stage's own
          -- isShowing or selectNext propagated straight out of a key handler for a
          -- presenting plugin, where the exact same raise would have been swallowed for
          -- every other one. No dot and colon fallback is needed, unlike the branch below,
          -- since every function surfaceFor hands back is already a plain closure over the
          -- stage's own self, dot called on purpose, so one pcall is the whole of what
          -- consistency asks for here.
          local fn = stageModule:surfaceFor(identity)[methodName]
          if fn then
            return function(...)
              local ok, result = pcall(fn, ...)
              return ok and result
            end
          end
          -- Falls through to the ordinary lookup below rather than answering nil here, the
          -- trickle migration's own fix, found the moment a presenting plugin first carried
          -- an extra verb beyond the five generic ones stageFor's own adapter answers.
          -- isShowing, selectNext, selectPrev, insertSelected, and hide are the stage's own
          -- business now and never reach this point, but refresh, sortByLoad, and stopForced,
          -- Processes' own three, are not, and stageFor answering nil for a name it was never
          -- asked to carry is not the same claim as this plugin having nothing to answer it.
          -- Before this fix a presenting plugin's own extra verbs were unreachable no matter
          -- what registry.surface named, silently, since the branch below never ran for one.
        end
        local owner, fn = nil, nil
        local holder = surfaceOf(module, spec)
        if type(holder) == "table" and type(holder[methodName]) == "function" then
          owner, fn = holder, holder[methodName]
        elseif type(module[methodName]) == "function" then
          owner, fn = module, module[methodName]
        end
        if not fn then return nil end
        return function(...)
          local ok, result = pcall(fn, owner, ...)
          if ok then return result end
          local dotOk, dotResult = pcall(fn, ...)
          return dotOk and dotResult
        end
      end,
    })
  end

  surfaceAdapters = {}
  surfaceByOwner = {}
  local seenOwner = {}
  for _, name in ipairs(plan.order) do
    local owns = false
    for _, owner in pairs(contextOwners) do
      if owner == name then owns = true end
    end
    if owns and not seenOwner[name] then
      seenOwner[name] = true
      local identity = plan.identity[name] or name
      local module = modules[identity]
      -- Its own declared surface travels with it, so the adapter knows where this plugin
      -- actually keeps the list rather than assuming the root is it. Looked up under both
      -- spellings, since a manifest is found by directory here and by identity elsewhere and
      -- seven of the tools spell the two differently.
      local manifest = manifests[name] or manifests[identity] or {}
      -- surface.member wins over registry.surface where a plugin states it, because the two
      -- answer subtly different questions and one plugin needs them to differ. registry.surface
      -- is what a launcher row opens, while this is the object that answers the navigation verbs
      -- while the list is up. For eleven tools they are the same object and only the second is
      -- declared. The launcher is the twelfth, has no registry entry at all being a host, and
      -- builds a purpose made navigation adapter whose own comment says the root should drive it
      -- through exactly this path. Nothing did, so the most used list in the config was the one
      -- list whose j and k reached nothing.
      local spec = (manifest.surface or {}).member or (manifest.registry or {}).surface
      if module then
        -- A presenting plugin, phase three, is routed a third way, ahead of the manifest
        -- spelling above, decided lazily inside surfaceAdapterFor's own proxy rather than
        -- here, review finding one, since the registry has not registered anything yet at
        -- the moment this loop runs. identity travels into the proxy so it can ask again on
        -- every access instead of once, now, too early to ever be true.
        surfaceAdapters[#surfaceAdapters + 1] = surfaceAdapterFor(module, spec, identity)
        surfaceByOwner[name] = surfaceAdapters[#surfaceAdapters]
      end
    end
  end

  ------------------------------------------------------------------------------
  -- STEP J. Drive the eight fixed stages, in their own order, unchanged.
  ------------------------------------------------------------------------------

  local w = wireLib.new({
    plan = plan,
    services = ambientServices,
    log = logFn,
    libs = libs,
    -- The loaded modules, so a plugin's declared sibling need is actually delivered rather
    -- than only checked. The table is passed by reference and the loader has already filled
    -- it, so every plugin sees the whole set regardless of where it sits in the order, which
    -- is what makes a need marked ordering false work at all.
    modules = modules,
    data = wireData,
    args = wiringArgs,
    isShowing = isShowingFor,
  })

  -- What step F and step H found wrong with a leader, said now that the wiring report exists.
  for _, problem in ipairs(leaderProblems) do w.problem("leaders", problem.where, problem.why) end
  -- policy.hyperTrigger was how a person made Hyper a modifier chord. A held leader's trigger is
  -- its key now, and a named set of modifiers becomes a leader of its own with the person's
  -- keymap in phase 5 of the keymap plan, so the field is read by nothing and a value
  -- left in a config would otherwise be ignored in silence.
  if type(cfg.policy) == "table" and cfg.policy.hyperTrigger ~= nil then
    w.problem("leaders", "policy.hyperTrigger", "is retired, a held leader is its key and its "
      .. "behaviour in the leaders section of config/keymap.lua, so the field is ignored")
  end

  -- What the keymap's own file got wrong, said now too, each naming the entry.
  for _, problem in ipairs(keymapProblems) do w.problem("keymap", problem.where, problem.why) end

  w.configure(modules, manifests)
  w.steps(modules, manifests)
  -- Every candidate leader gets the predicate table, since which of them are in use is known only
  -- once the keymap is built below, and configuring one nothing uses costs nothing.
  w.predicates(candidateList, ownPredicates)
  -- Every tool that registered is activated, since the plan already left out every plugin that
  -- is switched off and there is no second switch.
  local forWire = registrarLib.forWire(wiredRegistry)
  w.register(forWire, describeForRegistry)

  -- What every plugin can run, its provides.actions descriptors, fixed in code or built from the
  -- plugin's own data, an app the toggler serves or a System Settings pane. They are asked once,
  -- here, after every plugin's configure and wiring have run and every tool has registered, so a
  -- list built in configure is already there. A malformed descriptor is refused with one problem
  -- line and costs only itself.
  --
  -- The same walk names every retired field a manifest still declares, registry.commands,
  -- defaults.key, defaults.mods, provides.bindings, provides.cheatSheetSections and
  -- provides.launcherAppDetails, with what replaced each. Nothing reads a retired field, so
  -- without the line a manifest written to the old contract would lose that key, that row or
  -- that section in silence.
  local pluginActions, refusedActions, actionOrder = {}, {}, {}
  -- The kinds the launcher keys specially, asked of the launcher itself, and the registered tool
  -- names, so a descriptor cannot claim a row the launcher would remember or route as its own.
  -- THE SEAM. The launcher is one of the host modules this file may name.
  local launcherForKinds = modules[plan.identity.launcher or "launcher"]
  local toolNames = {}
  for _, entry in ipairs(wiredRegistry.all() or {}) do toolNames[entry.name] = true end
  local actionOpts = { reservedKinds = launcherForKinds and launcherForKinds.reservedKinds,
    toolNames = toolNames }
  for _, directory in ipairs(plan.order) do
    local identity = plan.identity[directory] or directory
    local manifest = manifests[directory] or manifests[identity] or {}
    local module = modules[identity] or modules[directory]
    for _, problem in ipairs(registrarLib.retiredFields(identity, manifest)) do
      w.problem("retired", problem.where, problem.why)
    end
    if (manifest.provides or {}).actions ~= nil then
      local answered, refused, problems, order = registrarLib.validateActions(identity, manifest, module, actionOpts)
      pluginActions[directory], refusedActions[directory], actionOrder[directory] = answered, refused, order
      for _, problem in ipairs(problems) do w.problem("actions", problem.where, problem.why) end
    end
  end

  -- What a host's key calls. A host is shown, by the one rule lib/hints.lua keeps for a host that
  -- carries a key. Locking and sleeping were special rows the root ran here until phase 5 of the
  -- keymap plan, and they are the launcher's own descriptors now, run like any action.
  local claimedShortcuts = {}
  for _, entry in ipairs(wiredRegistry.shortcuts() or {}) do claimedShortcuts[entry.name] = true end
  local function hostRun(directory)
    local identity = plan.identity[directory] or directory
    local module = modules[identity]
    local role = hintsLib.hostKeyBinding((plan.effective or {})[directory], module, claimedShortcuts[identity])
    if not role then return nil end
    return function() module:show() end
  end

  -- What a tool's cycle row calls, the stage cycling that tool's own presentation, the one the
  -- registry holds for it and stagePresent shows, or nil for an identity with none, which the
  -- keymap refuses by name. The key's code travels with it, since a press of the same key while
  -- the list is up steps the highlight rather than reaching the binding.
  local function cycleRun(identity, keyCode)
    if not (wiredRegistry.presentationFor and wiredRegistry.presentationFor(identity)) then return nil end
    return function()
      local presentation = wiredRegistry.presentationFor(identity)
      if presentation and stageModule then stageModule:cycle(presentation, { keyCode = keyCode }) end
    end
  end

  -- The keymap, every chord Olm binds as one list of rows, built once now that the plan, the
  -- registry and every plugin's actions exist. Each global row carries the function it calls and
  -- its place in the binding order, and the binder below binds exactly that list, so the keymap
  -- is the binding rather than a picture of it. Anything it finds goes into the wiring report
  -- through the same problem channel the stages use, and the whole list is kept on the record so
  -- a probe can read it from a running config.
  --
  -- A raise is reported loudly and leaves every global key unbound. There is no second binding
  -- path to fall back on, since no plugin binds a key of its own any more and the keymap is the
  -- only list of what to bind, so a partial fallback would bind some keys and not others with
  -- nothing saying which. The lists' own keys, the leaders' taps and the remap are untouched, so
  -- Caps Lock still toggles and every open list still answers its keys.
  local built, keymap = pcall(keymapLib.build, {
    plan = plan,
    roles = leaderRoles,
    keycodes = keyTable,
    shortcuts = wiredRegistry.shortcuts(),
    actions = pluginActions,
    refusedActions = refusedActions,
    hostRun = hostRun,
    cycleRun = cycleRun,
    standalone = keycodesLib.standalone,
    personKeys = keymapConfig.keys,
    modifierLeaders = modifierLeaderSets,
    compositeLeaders = compositeLeaderSets,
    listLeader = listLeaderName,
    known = function(identity) return allManifests[identity] ~= nil end,
  })
  if not built then
    w.problem("keymap", "build", tostring(keymap) .. ", so no global key is bound this load")
    keymap = { rows = {}, bound = {}, problems = {}, notes = {} }
  end
  for _, problem in ipairs(keymap.problems) do
    w.problem("keymap", problem.where, problem.why)
  end
  -- A default the person's chord displaced, or a chord false freed, is the person's own call, said
  -- once as a routine line and never as a problem.
  for _, note in ipairs(keymap.notes or {}) do log.i("Olm keymap, " .. note) end

  -- The leaders in use, every one some bound row of the keymap uses, so a held leader is remapped
  -- and started exactly while a chord needs it. Writing super and V is what claims Right Command,
  -- and moving every window default onto super frees Right Option. A keymap that failed to build
  -- binds no global key, so the leaders in use fall back to the ones its roles name plus every
  -- leader a list key names, which the contexts still bind on, so every list keeps its keys and
  -- Caps Lock its tap even where a role moved off it. The leader list, the engines the binder
  -- reaches, the sheets and the leaders hosting list keys all follow this one answer.
  local listLeaderNames = {}
  do
    local seen = {}
    local known = {}
    for _, spec in ipairs(leaderSpecs) do known[spec.name] = true end
    for _, block in pairs(plan.contexts or {}) do
      for _, b in ipairs(block.bindings or {}) do
        if b.chord ~= false and b.leader and known[b.leader] and not seen[b.leader] then
          seen[b.leader] = true
          listLeaderNames[#listLeaderNames + 1] = b.leader
        end
      end
    end
    table.sort(listLeaderNames)
  end
  local inUse = {}
  local names = built and keymapLib.leadersInUse(keymap)
    or keymapLib.fallbackLeaders(leaderRoles, listLeaderNames)
  for _, name in ipairs(names) do inUse[name] = true end
  for _, spec in ipairs(leaderSpecs) do
    if inUse[spec.name] then
      local leader = candidateLeaders[spec.name]
      if not leader then
        w.problem("leaders", spec.catalogName, "its key resolves to no keycode, so the leader is not built and none of its keys is bound")
      else
        spec.inUse = true
        leaderList[#leaderList + 1] = leader
        leadersByName[spec.name] = leader
        if not spec.held and hostsListKey[spec.name] then
          sealingModifierLeaders[#sealingModifierLeaders + 1] = leader
        end
        if spec.held then
          activeLeaderNames[#activeLeaderNames + 1] = spec.catalogName
          -- A leader on a function key is heard as it is and has no target, so it is no row.
          if spec.remapTarget then
            remapRows[#remapRows + 1] = { name = spec.catalogName, key = spec.key, target = spec.remapTarget }
          end
        end
      end
    end
  end
  leaderList[#leaderList + 1] = plainLeader
  w.leaders(leaderList)
  -- The held leaders in use, by name for the contexts and in catalog name order for the chooser
  -- field's yield and the harness word.
  local heldInUse = {}
  for _, spec in ipairs(leaderSpecs) do
    if spec.inUse and spec.held then
      heldInUse[spec.name] = leadersByName[spec.name]
      heldLeaders[#heldLeaders + 1] = leadersByName[spec.name]
    end
  end

  -- The binder, the one place a global key is bound. Each row lands on the leader named the way
  -- the row spells it, the catalog name lowercased, and a row with no leader lands on the plain
  -- leader. The order the leaders receive the rows in is the order the paths it replaced bound
  -- them in, which is the order of the keymap's bound list. Two roles naming one catalog leader
  -- share that one leader and its policy, which a keymap collision would name if two rows met.
  for _, problem in ipairs(binderLib.bind(keymap.bound, {
    engines = leadersByName,
    plain = plainLeader,
  })) do
    w.problem("keymap", problem.where, problem.why)
  end

  -- lib/nav.lua's own dispatch table has to be built, and its side effect of stamping
  -- binding.fn onto every context binding has to have already happened, before stage seven
  -- runs, since lib/nav.lua's own bindOne reads that exact field rather than asking this
  -- table again by name. It is built here, between stages six and seven, rather than left
  -- until step K, for that one reason alone.
  -- Assigned rather than declared, since it was forward declared far above so ActionPanel's
  -- own run closure could be built before the pipeline started and still reach the real table
  -- once it exists.
  dispatchTable = navLib.actions(plan, {
    surfaces = surfaceAdapters,
    hideShortcuts = hideSharedOverlay,
    -- Every list key that acts closes the action bar's key panel first, the spec's rule, in the
    -- one place every handler passes through. showKeys is the one that toggles it instead.
    onAction = function(name)
      if name ~= "showKeys" and stageModule then stageModule:closeKeys() end
    end,
    -- The three action names that do not equal the surface method answering them. Everything
    -- else routes by its own name, which is why lib/nav.lua defaults to that and this table is
    -- three lines rather than twenty six.
    --
    -- Passing NOTHING here, which is what this did, meant each of these three routed to a
    -- method no surface has, and lib/nav.lua leaves an unanswered method alone in silence by
    -- design. So closing a list with its own close key did nothing in all twelve lists, reveal
    -- in Finder did nothing in file search, and rescan did nothing in processes. Every one of
    -- them bound, eligible, routed and dropped. The retired root carried these three mappings
    -- explicitly and the restructure read the action name as the method name for all of them.
    methodFor = navMethodFor,
    exceptions = {
      -- THE SEAM. openActionPanel cannot be a routed method on any one surface, since it
      -- toggles a panel that borrows whichever list is currently open rather than being a
      -- verb that list answers itself, so this is the one closure lib/nav.lua's own design
      -- hands back to this file to build rather than resolving generically.
      -- THE SEAM, the key panel's own verb. Like the action panel it belongs to whichever list
      -- is open rather than to that list's surface, and the one list instance is the stage's,
      -- so it is the stage that is asked, and a provider drawing no action bar does nothing.
      showKeys = function()
        if stageModule then stageModule:toggleKeys() end
      end,
      openActionPanel = function()
        local actionPanelModule = modules[plan.identity.actionpanel or "actionpanel"]
        if not actionPanelModule then return end
        for contextName in pairs(plan.contexts) do
          if isShowingFor(contextName) then
            -- The hosted argument's meaning moved into the caller when hints.lua stopped
            -- reading globals, and the rebuilt seam never picked that duty up, so the panel
            -- over a hosted list silently answered Back alone rather than the scope's own
            -- verbs. This branch restores the retired root's behavior, with the verbs table
            -- resolved here, because here is the one caller that knows a list is hosted.
            if contextOwners[contextName] == (plan.identity.launcher or "launcher") then
              local queryScopeModule = modules[plan.identity.queryscope or "queryscope"]
              local launcherModule = modules[plan.identity.launcher or "launcher"]
              if queryScopeModule and launcherModule then
                local scope = queryScopeModule:resolve(launcherModule:currentQuery())
                if scope then
                  actionPanelModule:toggle(scope.name, scope.verbs or {})
                  return
                end
              end
            end
            actionPanelModule:toggle(contextName)
            return
          end
        end
      end,
    },
  })

  -- Every list key binds on the held leader its chord names, a default on the list role's leader.
  -- One opening with no held leader binds on none, false here, since the open list's field answers
  -- it through the watcher built below.
  w.contexts(function(binding)
    if binding.leader == false or modifierLeaderSets[binding.leader] ~= nil then return false end
    return heldInUse[binding.leader]
  end, bindOneInContext)
  -- The list keys the open list's own field answers, phase B of the list keys addendum. The field
  -- asks the watcher at each key down while it is up, and the watcher runs the open list's binding,
  -- read off binding.fn, which the dispatch table above stamped. A held key's autorepeat runs only
  -- a binding whose action repeats, the same table the leaders read. Only the default chooser has
  -- such a field, so with the legacy chooser chosen the keys are said once as not live.
  --
  -- While the action panel is open over a list the field's keys are inert, so Command and Return
  -- in the panel chooses the panel row rather than running the list's secondary on whatever the
  -- panel was opened over. That is said through the watcher's own gate. Each list's predicate is
  -- handed over wrapped, answering false while the panel is open, so the watcher keeps knowing
  -- only predicates and the key falls through to the field, which chooses the highlighted row.
  local fieldPredicates = setmetatable({}, { __index = function(_, name)
    local pred = (w._predicates or ownPredicates)[name]
    if type(pred) ~= "function" then return pred end
    return function() return actionPanelShowingRow() == nil and pred() end
  end })
  local fieldKeyList
  fieldWatch, fieldKeyList = navLib.fieldKeys(plan.contexts, {
    keycodes = keyTable,
    modifierLeaders = modifierLeaderSets,
    predicates = fieldPredicates,
    repeats = repeatableActions,
    isRepeat = function(ev)
      return ev:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat) ~= 0
    end,
  })
  for _, k in ipairs(fieldKeyList) do
    local code = keyTable[k.key]
    if type(code) == "number" then relayFieldKeys[#relayFieldKeys + 1] = { k.mods, code } end
  end
  if #fieldKeyList > 0 and chooserAtom.providers and chooserProvider == chooserAtom.providers.legacy then
    log.i("Olm keymap, " .. #fieldKeyList .. " list key(s) with no held leader are answered by the default "
      .. "chooser's field, and the legacy chooser is chosen, so none of them is live this load")
  end

  -- The remap is applied here, after every binding has been stored and immediately before the
  -- engines start listening, and that placement is the point. The remap is machine wide and
  -- takes Caps Lock and Right Option away from the system, so if anything raised earlier in
  -- this load, a failed load must leave the native keys alone rather than two dead ones with
  -- no chord engine behind them until the next reload. It was a plugin's wiring step until
  -- phase two of the core split, and the root reading a plugin's catalog by name was the leak
  -- that move closed. The binary comes through the dependency door from the root's own
  -- declaration in root/manifest.lua, the same way scutil does, so this names no prefix. An
  -- unresolved path is passed on as nil, and the engine answers by remapping nothing and
  -- saying so, which leaves every leader its own native key.
  keyRemapAtom:apply(remapRows, sharedDepsScope.path("hidutil"))
  w.start(leaderList, chordKeyAtom)

  -- A held leader is deaf while another application holds secure input, so its press there says
  -- which one, see lib/securenotice.lua. ioreg comes through the door from root/manifest.lua.
  local noticeKeys = {}
  for _, spec in ipairs(leaderSpecs) do
    if spec.inUse and spec.held and spec.keyCode then
      noticeKeys[#noticeKeys + 1] = { code = spec.keyCode, name = displayName(spec.catalogName) }
    end
  end
  secureNoticeLib.start({ keys = noticeKeys, ioreg = sharedDepsScope.path("ioreg"), notify = notify })

  ------------------------------------------------------------------------------
  -- ActionPanel's own configure. Deferred to here for the identical reason step
  -- K's three calls are, deps.rowsFor and deps.run both read plan and registry
  -- state the earlier stages had not produced yet.
  ------------------------------------------------------------------------------

  -- ActionPanel is configured by the ordinary stage two path alone now. Its three values are
  -- built far above and carried in on wireData, so the second call that used to sit here would
  -- only restate what the plugin already holds, and a second call that adds nothing is exactly
  -- the kind of step that later drifts from the first one.

  ------------------------------------------------------------------------------
  -- STEP K. The post register pass. A few second configure calls the fixed
  -- pipeline genuinely cannot express, since each needs a value that exists
  -- only once stage five has already run.
  ------------------------------------------------------------------------------

  -- Every leader whose policy states a sheet, one record each for the sheet host. A leader's rows
  -- are the global chords the keymap holds on it, read by lib/hints.lua's sheetRows and filed into
  -- sections by the host under each descriptor's group, in blocks placed by each owner's declared
  -- cheatSheetOrder, the app toggles first on the Hyper sheet today. A tool row with no
  -- description borrows the detail its launcher row wears, from the registry handed over here,
  -- the raw instance rather than the zero argument wire adapter, since rowFor is the one call that
  -- needs it. A row standing for an app wears that app's name and icon, resolved here once, and
  -- an app not on this machine is left off. The sheet draws by the leader's own keycode, which the
  -- adapter hands it, or by its name for a leader of modifiers.
  if leaderSheetModule then
    local sheetIdentity = plan.identity.leadersheet or "leadersheet"
    local directoryOfIdentity = {}
    for _, directory in ipairs(plan.order or {}) do
      directoryOfIdentity[plan.identity[directory] or directory] = directory
    end
    local function sheetOrderOf(owner)
      local directory = directoryOfIdentity[owner]
      return directory and ((plan.effective or {})[directory] or {}).cheatSheetOrder or nil
    end
    local function appInfo(bundleID)
      local path = hs.application.pathForBundleID(bundleID)
      if not path or path == "" then return nil end
      return { name = hs.application.nameForBundleID(bundleID), icon = hs.image.imageFromAppBundle(bundleID) }
    end
    local sheets = {}
    for _, spec in ipairs(leaderSpecs) do
      if spec.policy.sheet and spec.inUse then
        local layout = leaderLib.sheetLayout(spec.policy, cheatSheetAtom.DEFAULTS, spec.heading)
        local rows = hintsLib.sheetRows(keymap, plan, spec.name, { registry = wiredRegistry })
        sheets[#sheets + 1] = {
          name = spec.name,
          -- Nil on a leader of modifiers, whose sheet the host finds by name.
          keyCode = spec.keyCode,
          layout = layout,
          entries = leaderSheetModule.ownSections(rows, {
            glyphFor = cheatSheetAtom.glyphFor,
            layout = layout,
            appInfo = appInfo,
            orderOf = sheetOrderOf,
            ownOrder = ((plan.effective or {})[sheetIdentity] or {}).cheatSheetOrder,
          }),
        }
      end
    end
    -- The renderer and the predicates are given again beside the sheets, and the table is keyed
    -- by DIRECTORY in lateData rather than by identity, since that is how a manifest is keyed and
    -- the delivery check reads the two side by side.
    local leaderSheetLate = {
      sheets = sheets,
      predicates = rootValues.predicates,
      cheatSheet = cheatSheetAtom,
    }
    leaderSheetModule:configure(leaderSheetLate)
    lateData.leadersheet = leaderSheetLate
  end

  local queryScopeModule = modules[plan.identity.queryscope or "queryscope"]
  -- The alias directory scope's own run, kept for the launcher's special row fallback below, which
  -- is built after the block that makes the scope.
  local aliasDirectoryRun = nil
  if queryScopeModule then
    -- Membership from the plan's own set answer, which is the question this host declared
    -- rather than a roster anyone here keeps, and the scope itself from the live registry. A
    -- plugin that was switched off, or went off with one, is never loaded or registered, so the
    -- plan's set leaves it out and the registry holds nothing for it, which is how it keeps no
    -- word.
    local scopeNames = (plan.sets[plan.identity.queryscope or "queryscope"] or {}).scopes
      or (plan.sets.queryscope or {}).scopes
    local scopes = registrarLib.scopeSpec(plan, wiredRegistry, scopeNames, registryMeta) or {}

    -- Two scopes claiming one typed word, named rather than ranked.
    --
    -- The retired root settled these with a hand written order of every scope, and porting that
    -- list would have meant this config carrying a roster of plugin names outside every plugin,
    -- which is the one shape this design exists to remove. It also hid what it was for. Across
    -- the whole set exactly one word was ever contested, so the list read as policy over eleven
    -- tools while answering a question about two.
    for _, hit in ipairs(scopes.collisions or {}) do
      log.e("Olm compose, both " .. tostring(hit.first) .. " and " .. tostring(hit.second)
        .. " answer to the typed word '" .. tostring(hit.alias)
        .. "', so one of them can never be reached by it, and which one is not decided anywhere. "
        .. "Change one of the two aliases.")
    end

    -- THE SEAM. The alias directory is QueryScope's own last scope, and it is fundamentally
    -- a policy over that host and over Launcher's own way of seeding a field, so both are
    -- named here rather than hidden behind another indirection, exactly the exception this
    -- file's own brief asks to be marked rather than papered over.
    local launcherIconOwner = plan.identity.launcher or "launcher"
    local launcherModuleForAlias = modules[launcherIconOwner]
    local aliasPolicy = policy.aliasDirectory or {}
    local aliasScope = registrarLib.aliasDirectory({
      catalog = function() return queryScopeModule:catalog() end,
      queryFor = function(name) return queryScopeModule:queryFor(name) end,
      show = function(query) if launcherModuleForAlias then launcherModuleForAlias:show(query) end end,
      title = aliasPolicy.title,
      icon = aliasPolicy.icon,
      iconOwner = launcherIconOwner,
      aliases = aliasPolicy.aliases,
      aliasLabel = aliasLabel,
      log = logFn,
    })
    -- The scopes that narrow the launcher's own catalog rather than reaching a tool. Declared
    -- by that host in its own defaults and built here, because the two calls behind them are
    -- the host's own methods and this file is the one allowed to name it. An install without a
    -- launcher declares none and gets none, with nothing here to remove.
    if launcherModuleForAlias then
      local launcherEff = (plan.effective or {})[plan.identity.launcher or "launcher"] or {}
      for _, spec in ipairs(launcherEff.catalogScopes or {}) do
        scopes[#scopes + 1] = {
          name = spec.name,
          title = spec.description,
          icon = spec.icon,
          iconOwner = launcherIconOwner,
          aliases = spec.aliases,
          rows = function() return launcherModuleForAlias:rowsOfKind(spec.kind) end,
          run = function(payload) launcherModuleForAlias:runItem(payload) end,
        }
      end
    end

    if aliasScope then
      scopes[#scopes + 1] = aliasScope
      aliasDirectoryRun = aliasScope.run
    end

    -- Two scopes claiming one typed word, named rather than ranked, and asked here because this
    -- is the first point at which the whole list exists.
    --
    -- The retired root settled these with a hand written order of every scope, and porting that
    -- would have meant this config carrying a roster of plugin names held outside every plugin,
    -- the one shape this design exists to remove. It also hid what it was for. Across the whole
    -- set exactly one word has ever actually been contested, so an eleven name list read as
    -- policy over eleven tools while answering a question about two.
    for _, hit in ipairs(registrarLib.aliasCollisions(scopes)) do
      log.e("Olm compose, both " .. tostring(hit.first) .. " and " .. tostring(hit.second)
        .. " answer to the typed word '" .. tostring(hit.alias)
        .. "', so one of them can never be reached by it and nothing decides which. Change one "
        .. "of the two declarations.")
    end

    local queryScopeLate = { matcher = queryScopeOpts.matcher, rank = queryScopeOpts.rank,
      stampIcons = iconRows.stampAll, scopes = scopes }
    queryScopeModule:configure(queryScopeLate)
    lateData.queryscope = queryScopeLate
  end

  local launcherModule = modules[plan.identity.launcher or "launcher"]
  if launcherModule then
    -- The ordered query row sources. QueryScope leads, since it is the one that CLAIMS a
    -- query outright rather than only computing a row for it, then every plugin the plan's
    -- own set answer says provides queryRows, in the order the plan already settled on.
    --
    -- The example field hints ride along on the same walk, each one a source's own proposal
    -- for what the launcher's empty field may say about it, read off that plugin's effective
    -- defaults so a person may reword one. Gathered here and not in the launcher because the
    -- launcher must never learn which plugins compute rows, and gathered inside this loop and
    -- not beside it because a source excluded for a missing tool has no module, and a hint
    -- advertising a capability this machine does not have is worse than no hint. A source
    -- proposing nothing contributes nothing, which is the feature degrading rather than
    -- breaking, and a source added later joins the rotation with no edit here or there.
    --
    -- example may be one string or a list of strings, a plugin with several capabilities
    -- worth teaching having no reason to pick just one, and this flattens either shape into
    -- the same flat list the launcher receives, so the launcher still only ever sees strings
    -- and never learns that a source offered more than one.
    local queryProviders = {}
    local placeholderExamples = {}
    if queryScopeModule then queryProviders[#queryProviders + 1] = queryScopeModule end
    for _, identity in ipairs((plan.sets.launcher or {}).queryRows or {}) do
      if modules[identity] then
        -- Wrapped so the rows it answers carry this plugin as the owner of their icon keys, the
        -- same helper the stage and the query scope run, which is what lets a computed row name
        -- an icon and never draw one. The launcher still sees
        -- only a table answering rows(query) and learns nothing of who it came from.
        queryProviders[#queryProviders + 1] =
          contributionsLib.queryProvider(modules[identity], identity, iconRows.stampAll)
        local example = ((plan.effective or {})[identity] or {}).example
        local hints = type(example) == "table" and example or { example }
        for _, hint in ipairs(hints) do
          if type(hint) == "string" and hint ~= "" then
            placeholderExamples[#placeholderExamples + 1] = hint
          end
        end
      end
    end

    local launcherEffective = (plan.effective or {})[plan.identity.launcher or "launcher"] or {}

    -- The rows other plugins add to the launcher's own catalog, and the runners that take a
    -- chosen one back, both answered by the plan rather than named here. lib/contributions.lua
    -- turns the launcherRows and launcherRun set answers into one supplier per contributor and
    -- one runner per owner identity, each row stamped with its owner, its icon owner and its
    -- place, so the launcher routes a chosen row by one plain word and never learns which
    -- plugin built it.
    -- A plugin's action descriptors are rows too, built by Olm with the chord the keymap binds
    -- each one to, so a plugin with actions supplies no rows of its own.
    local rowSuppliers, runners = contributionsLib.assemble({
      host = plan.identity.launcher or "launcher",
      plan = plan,
      manifests = manifests,
      modules = modules,
      registrar = registrarLib,
      actions = pluginActions,
      actionOrder = actionOrder,
      keymap = keymap,
      stampIcons = iconRows.stampAll,
      log = function(message) log.e("Olm compose, " .. message) end,
      afterRelease = afterLeadersRelease,
    })

    -- What an app row shows beyond the app, the chord of an action whose descriptor names that
    -- app, built from the descriptors and the keymap, so the launcher reads no person data, names
    -- no plugin, and no plugin answers anything for an app row.
    local appDetails = contributionsLib.appChords({
      plan = plan,
      actions = pluginActions,
      actionOrder = actionOrder,
      keymap = keymap,
    })

    -- The launcher's own Aliases row is root policy with no tool behind it, a catalog row of kind
    -- special with no owner, so the registry has no presentation for it. This is the one place the
    -- name and the row's shape are written. It answers the word the directory scope answers to
    -- when the item is that row, and nil for every other, so rowIntercept can replace the open
    -- list with it and the special fallback can name the same row.
    local aliasRowName = "aliasDirectory"

    -- The launcher's own OLM keys row, root policy with no tool behind it like the Aliases row, and
    -- the one place its name is written. Choosing it pushes the keys page over the open launcher,
    -- answered below where a registered tool's presentation is, so the launcher's list becomes the
    -- keys list in place and Back or Backspace on an empty field brings the launcher back. The
    -- page is a level of the launcher, so it carries the launcher's name, the stage's own rule for
    -- a child, and its icons are the launcher's.
    --
    -- Its rows are every chord the keymap binds as words, lib/hints.lua's keyEntries, held leaders
    -- in catalog order then the leaders the person named, then plain combinations and list keys.
    -- The keymap is fixed for the load, so the words are built on the first open and kept. Only
    -- words leave the root, so nothing the page holds could bind a key, and the person's file stays
    -- read by this root alone.
    local keysRowName = "keys"
    local keyCatalogCache = nil
    local function keyCatalog()
      if keyCatalogCache then return keyCatalogCache end
      local leaders = {}
      for _, spec in ipairs(leaderSpecs) do leaders[#leaders + 1] = spec.name end
      keyCatalogCache = hintsLib.keyEntries(keymap, plan, {
        bindable = binderLib.bindable,
        leaders = leaders,
        leaderNames = leaderNamesByLeader,
        chordLabel = chordLabel,
        glyphFor = cheatSheetAtom and cheatSheetAtom.glyphFor,
        manifests = manifests,
        registry = wiredRegistry,
        appName = function(bundleID) return hs.application.nameForBundleID(bundleID) end,
      })
      return keyCatalogCache
    end
    local function keysPresentation()
      return keyPageLib.presentation({
        name = plan.identity.launcher or "launcher",
        catalog = keyCatalog,
        pop = function() stageModule:pop() end,
      })
    end
    local function aliasRowQuery(item)
      if not queryScopeModule then return nil end
      if type(item) ~= "table" or item.owner ~= nil then return nil end
      if item.kind ~= "special" or item.name ~= aliasRowName then return nil end
      return queryScopeModule:queryFor(aliasRowName)
    end

    -- THE SEAM. Stage is one of the five host modules this file may name. It is fully
    -- configured already, in the ordinary stage two pass above. stageModule itself was
    -- assigned earlier in this same function, ahead of the surface adapters loop which
    -- needs it synchronously, phase three's own note beside that assignment says why, so
    -- this is only the reference the launcher presents into, the same shape chooser used to
    -- be handed here before this host existed.

    local launcherOpts = {
      stage = stageModule,
      placeholder = ambientServices.placeholder,
      appDetails = appDetails,
      predicates = ownPredicates,
      queryProviders = queryProviders,
      placeholderExamples = placeholderExamples,
      -- The identity the launcher's own manifest icons are declared under.
      iconOwner = plan.identity.launcher or "launcher",

      -- Without this the catalogue asks nothing about any tool and draws no tool row at all,
      -- which is exactly what it did.
      registry = wiredRegistry,
      glyphFor = cheatSheetAtom and cheatSheetAtom.glyphFor,
      -- What every leader role is called, app and window alike, so a contributed row that names
      -- its leader by role reads the same word the action bar prints, and every leader by the
      -- name a keymap row spells it with, for a row the person put on a leader no role answers.
      leaderNames = leaderDisplayNames,
      -- The shared speller rather than one the launcher owns for itself, so a row states the
      -- same chord the action bar already agreed on.
      chordLabel = chordLabel,
      -- The chord a registered tool's row names, its open row in the keymap, a leader role, else
      -- the leader's own name for a leader no role answers, or false for a plain combination, a key
      -- and the modifiers as a person reads them.
      chordOf = function(name)
        for _, row in ipairs(keymap.bound or {}) do
          if row.owner == name and row.source == "tool" then
            return { leader = row.role or row.leader or false, key = row.key, mods = row.shownMods }
          end
        end
        return nil
      end,
      rowSuppliers = rowSuppliers,
      runners = runners,
      specialRows = launcherEffective.specialRows,
      -- Where the launcher's own special rows sit among the contributed ones, its own shipped
      -- number, which a person may move in config/plugins.lua like any default.
      launcherOrder = launcherEffective.launcherOrder,

      -- What a row says about being reachable by a typed word, asked of the resolver that owns
      -- the grammar rather than restated here.
      aliasHint = function(name)
        if not queryScopeModule then return "" end
        local aliases = queryScopeModule:aliasesOf(name)
        local words = aliasLabel(aliases)
        if words == "" then return "" end
        return " " .. words
      end,

      -- The leaf dispatch. The catalogue owns the kind switch for the rows it states itself,
      -- these are the calls it routes to, and every one closes over core or is a plain macOS
      -- call, so none of them names a plugin. A row a plugin contributed runs through that
      -- plugin's own runner above instead.
      actions = {
        -- An app row, core naming core. It focuses or cycles, the same call the app toggler's
        -- plain toggles make. A row landing an app on a pane through a url went with the toggler's
        -- url field in phase 6 of the keymap plan, since a pane is System Settings' own action.
        app = function(bundleID) appFocusAtom.focusOrCycle(bundleID) end,
        -- A computed result lands on the pasteboard plainly, so it joins clipboard history
        -- like any other copy, unlike the hidden writes the insertion paths use.
        copy = function(value) hs.pasteboard.setContents(value) end,
        scope = function(item) if queryScopeModule then queryScopeModule:run(item) end end,
        scopePeek = function(item) if queryScopeModule then queryScopeModule:peek(item) end end,
        scopeCanPeek = function(item)
          return queryScopeModule ~= nil and queryScopeModule:canPeek(item) == true
        end,
        -- What choosing a row does in place of closing the launcher, lib/rowintercept.lua, with
        -- the calls only this file can make handed in. Decision two of the handoff brief, a
        -- special row naming a tool on the stage pushes its presentation, and the alias row and
        -- scope rows seed or act. The push is followed by a second rebuild, since the provider's
        -- own intercept refreshes once more when the callable is answered, harmless and left.
        rowIntercept = function(item)
          return rowInterceptLib.forRow(item, {
            aliasQuery = aliasRowQuery,
            seed = function(query) launcherModule:seedQuery(query) end,
            presentationFor = function(name)
              if name == keysRowName then return keysPresentation() end
              return wiredRegistry.presentationFor and wiredRegistry.presentationFor(name)
            end,
            push = function(presentation) stageModule:push(presentation) end,
            actFor = queryScopeModule and function(row) return queryScopeModule:actFor(row) end or nil,
            redirectFor = queryScopeModule and function(row) return queryScopeModule:redirectFor(row) end or nil,
          })
        end,
        -- The one name with no tool behind it. Reached only when the registry does not already
        -- run the name, which registration itself makes safe since one name cannot belong to
        -- both. The System Settings search row was another until phase three of the core split,
        -- and it is owned and run by that plugin now, and lock and sleep were two more until
        -- phase 5 of the keymap plan, the launcher's own descriptors since, run by its runner.
        special = {
          -- Reached only when the stage has already closed, so seeding the field would write to
          -- a hidden one that show then clears. The directory scope's own run opens the launcher
          -- with the word typed, which is what an unresolved click needs.
          [aliasRowName] = function()
            if aliasDirectoryRun then aliasDirectoryRun(aliasRowName) end
          end,
          -- The same fallback for the OLM keys row. A push that finds the stage hidden opens the
          -- page on a fresh stack, so the keys still come up after the launcher has gone.
          [keysRowName] = function() stageModule:push(keysPresentation()) end,
        },
      },
    }
    launcherModule:configure(launcherOpts)
    lateData.launcher = launcherOpts
  end

  ------------------------------------------------------------------------------
  -- STEP L. The tail.
  ------------------------------------------------------------------------------

  -- Every root sourced declaration that nothing actually delivered, named out loud.
  --
  -- This is the check that was missing, and its absence is why plugin after plugin could declare
  -- a value, be told the plan had no problems, and then run on nil. A root sourced need is a
  -- promise made inside this repository rather than a request of the person, so an unkept one is a
  -- defect identical on every machine, and it belongs in the console as an error carrying the
  -- plugin's own sentence about what it costs.
  --
  -- Asked here, at the very end, and of both channels at once. Delivery is the question rather
  -- than declaration, so it can only be asked once everything that delivers has run, which
  -- includes step K's three later calls just above.
  for _, owed in ipairs(servicesLib.owed(manifests, servicesLib.merge(wireData, lateData), "root")) do
    log.e("Olm compose, nothing supplied the root value '" .. owed.field .. "' that "
      .. owed.plugin .. " declares as " .. owed.policy
      .. (owed.breaks and (", so " .. owed.breaks) or ""))
  end

  olm.registry = wiredRegistry

  -- Ported from the live root, so the user's own file no longer carries this block. Skips a
  -- reload for a path matching the shipped or configured ignore list, a runtime data file
  -- something Olm itself ships already writes inside the watched tree.
  hs.pathwatcher.new(hs.configdir .. "/", function(paths)
    for _, p in ipairs(paths or {}) do
      local ignored = false
      for _, pattern in ipairs(policy.autoReload.ignore or {}) do
        if p:match(pattern) then ignored = true break end
      end
      if not ignored then
        hs.reload()
        return
      end
    end
  end):start()

  -- A load that ran before Accessibility was given has no working event taps or hotkeys, and
  -- macOS does not restart them when the grant arrives, so the config looks alive and answers
  -- no key. That is the first launch on every fresh machine, since the grants step opens
  -- Hammerspoon so it can ask. So a load made without the grant reloads itself once the grant
  -- is given, scheduled for the same reason as the switch's reload above, and held so it fires.
  local loadedWithAccess = hs.accessibilityState()
  local accessReloadTimer
  hs.accessibilityStateCallback = function()
    if loadedWithAccess or accessReloadTimer or not hs.accessibilityState() then return end
    log.i("Olm compose, Accessibility was given after this load, reloading so the taps start")
    accessReloadTimer = hs.timer.doAfter(0.5, hs.reload)
  end

  local record = w.record

  -- The seam init.lua reads through self._composed, so Olm:start's own handle answers
  -- report, module and screen for real rather than the nil all three used to be, since
  -- w.record on its own carries only stages, problems and skipped, none of which init.lua
  -- promises to any caller. report is wire.lua's own report function with the switch lines
  -- put ahead of it, and record.text is its answer taken once. modules is loader.lua's own table, keyed by plugin
  -- identity, the exact table Olm:module indexes. screen is the overlay display resolver's
  -- own resolving function, handed over unpicked rather than called here, because the
  -- resolver resolves its effective mode fresh on every call rather than caching a screen
  -- once, so a screen taken now would go stale the moment the focused window, the cursor
  -- position, or the stored mode changes, and every caller must call it fresh at its own
  -- time, which Olm:screen is what actually does.
  -- The wiring report, with the switches said first. A switched off plugin and the ones off
  -- because of it are choices rather than problems, so they are named here and never reach the
  -- problem lines, and a load whose only differences are choices still reports no problems.
  local switchLines = switchLib.reportLines(plan.disabled, plan.offBecause)
  record.report = function()
    local text = w.report()
    if #switchLines == 0 then return text end
    return table.concat(switchLines, "\n") .. "\n" .. text
  end
  record.text = record.report()
  record.modules = modules
  record.screen = overlay.screen

  -- What this run actually decided, kept so something can INSPECT it afterwards rather than
  -- having to compose a second time to ask a question about the first. The test suite is the
  -- caller that made this necessary, since deriving a check from what a plugin declared means
  -- reading the plan and the manifests that produced the live config rather than reading the
  -- files again and hoping the two agree, which is exactly the self agreement that let a
  -- manifest naming a deleted capability pass for weeks.
  --
  -- Every one of these is the table itself rather than a copy. Nothing here should be written to,
  -- and a defensive copy would only make an inspector disagree with the config it is inspecting.
  record.plan = plan
  record.keymap = keymap
  -- Every held leader in use by the name a keymap row spells it with, so the key probe and the
  -- inventory read what each one holds. The plain leader is left out, since what it claims is
  -- every plain combo and hs.hotkey.getHotkeys already answers those.
  record.leaders = leadersByName
  -- The name the list role's leader is spelled with, so the inventory finds the leader every
  -- default list key binds on in leaders above without naming it.
  record.listLeaderName = listLeaderName
  -- The list keys the open list's field answers, context, key, modifiers, when and priority, which
  -- no engine and no hotkey holds. The offline bound recording, drygate-composerun.lua, writes them
  -- into a fixture's golden from here, and the live key probe does not read them yet.
  record.fieldKeys = fieldKeyList
  -- The catalog names the remap was applied with, so the key inventory's last line can say which
  -- held leaders this load claimed without reading the hardware.
  record.remap = activeLeaderNames
  record.manifests = manifests
  record.dispatch = dispatchTable
  -- The dependency door's own scope, so anything inspecting this config asks IT whether a tool
  -- is present rather than probing again and comparing two answers. The suite carried its own
  -- third probe of the same question, which is a test deriving the truth in parallel instead of
  -- checking what the config concluded, and the whole lesson of this layer is that a second
  -- answer to one question is where drift lives.
  record.tools = sharedDepsScope
  -- The MERGED table the engine was actually configured with, every surface gate plus every
  -- root owned one, rather than the root's own dozen. Recording only the root's own meant
  -- anything looking in here could not see a context gate at all, so the twelve answers that
  -- decide whether an in list chord fires were invisible to inspection while being the very
  -- thing most worth inspecting.
  record.predicates = w._predicates or ownPredicates
  -- Exposed for the same reason the predicates above are, so what a plugin offered and what the
  -- action bar was actually handed can be read from outside rather than only inferred from this
  -- file. A harvest that silently collected nothing looks exactly like a config with nothing to
  -- collect, which is the failure this one line makes answerable.
  record.liveLabels = ownLiveLabels

  -- The routed control surfaces, in the order lib/nav.lua consults them, so the question every
  -- in list chord depends on can be asked from outside. That question is not whether a list is
  -- open, it is whether the surface that is open ANSWERS the action the key is bound to, and
  -- nothing could ask it before. Which is why navigation being dead in three lists out of
  -- twelve was invisible to every check while being obvious to anybody pressing a key.
  record.surfaces = surfaceAdapters
  record.navMethodFor = navMethodFor
  record.navExceptions = navExceptionNames
  -- What each plugin was actually handed, from BOTH channels, since the question anybody asks of
  -- this table is what a plugin received rather than which call it came through. Step K's three
  -- later calls hand over values that never pass through the wiring table at all, so a record of
  -- the wiring table alone reported five perfectly delivered needs as missing, and the derived
  -- check in the suite that reads this is the one that has to be able to tell.
  record.data = servicesLib.merge(wireData, lateData)

  -- The note the reload before this one left, taken once, here at the end, since a place can
  -- only be reopened once every tool is registered and the stage is wired. Taken before acting,
  -- so a load that fails while acting on it does not act on it again. Acted on a moment later
  -- rather than now, so the rest of start finishes before a window appears.
  local note = resumeLib.take(resumeStore)
  if note then
    if resumeTimer then resumeTimer:stop() end
    resumeTimer = hs.timer.doAfter(0.3, function()
      resumeTimer = nil
      local open = note.open
      if open and stageModule and wiredRegistry.presentationFor then
        local presentation = wiredRegistry.presentationFor(open.tool)
        if presentation then
          stageModule:presentAt(presentation, open.path, open.highlight)
        else
          log.w("Olm compose, nothing is registered as '" .. open.tool
            .. "' any more, so the place before the reload was not reopened")
        end
      end
      if note.notify then notify(note.notify) end
    end)
  end

  return record
end

return obj
