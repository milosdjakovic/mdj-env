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
-- plugin is, so naming ActionPanel, HyperCheatSheet, Launcher, QueryScope, or Stage here is
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
local navLib = load("lib/nav.lua")
local servicesLib = load("lib/services.lua")

local log = hs.logger.new("Olm.compose", "info")
-- Every sibling here has its own opinion about the shape a logger arrives in. Some read an
-- hs.logger style object, log.e(message), and are handed this file's own log directly.
-- Others, lib/wire.lua and lib/registrar.lua among them, read a plain callable, log(level,
-- message), since a stand in for a test case can be a bare function but cannot as easily
-- pretend to be a whole object. This one wrapper is what a callable shaped consumer gets,
-- so the difference is paid once here rather than once per call site.
local function logFn(level, message) log[level](message) end

-- The registry's own API version, the integer every registration is checked against. It
-- lives here, as a plain literal, because it names no plugin and is genuinely this
-- composition root's own contract with lib/registry.lua rather than anything a manifest
-- could propose.
local REGISTRY_API_VERSION = 1

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
local SHIPPED_POLICY = {
  chord = { holdDelay = 0.6, tapThreshold = 0.2, passthrough = true },
  hyperTrigger = { kind = "leader" },
  storage = { cacheRoot = "~/Library/Caches/Hammerspoon Olm", olmRoot = "~/.olm" },
  surface = {},
  chooserTheme = {},
  cheatSheet = {},
  matcher = "fuzzy",
  autoReload = { ignore = { "/config/[^/]+%.json$" } },

  -- The heading drawn over the window leader's rows on the hold overlay. What the leader does
  -- rather than what it is called, since the leader's own name, META, says nothing to anybody
  -- reading a list of window actions.
  windowSectionTitle = "WINDOW MANAGEMENT",

  -- The alias directory is the one scope Olm itself owns rather than any plugin, a list of
  -- every other scope, so its own presentation has nowhere else to be declared and ships from
  -- here. The retired root read these three off its own keys catalog under the same name,
  -- which made a scope Olm provides look like something the person had to describe. A title is
  -- not optional decoration either, QueryScope refuses a scope that has none, so leaving it
  -- unset dropped the directory silently on every run with one warning line among many.
  aliasDirectory = { title = "Aliases", glyph = "🏷️", aliases = { "?" } },
}

--------------------------------------------------------------------------------
-- run(olm, cfg), the one door into all of this
--------------------------------------------------------------------------------

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
  local glyphIconLib = atoms.glyphicon

  local policy = defaultsLib.merge(SHIPPED_POLICY, cfg.policy)
  local leaderRoles = defaultsLib.merge({ app = "HYPER", window = "META" }, cfg.leaders)
  local decorate = defaultsLib.merge({ installedBy = "actionpanel" }, cfg.decorate)
  local globals = cfg.globals or {}
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

  atoms.storage.configure(policy.storage)

  -- Loaded and initialised here, but deliberately NOT configured or started until step C has
  -- read the manifests, because what it probes for is aggregated out of them. Everything
  -- between here and there only holds the atom, nothing asks it a question yet.
  local depsAtom = atoms.deps
  depsAtom:init()

  local canvasPanel = atoms.panel
  canvasPanel:init()
  canvasPanel.configure({ surface = policy.surface })
  canvasPanel.configure({ screen = function() return overlay and overlay.screen() end })

  local chooserAtom = atoms.chooser
  chooserAtom:init()
  chooserAtom.configure({
    screen = function() return overlay and overlay.screen() end,
    matcher = chooserAtom.matchers and chooserAtom.matchers[policy.matcher],
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

  local cheatSheetAtom = atoms.cheatsheet
  cheatSheetAtom:init()
  local cheatSheetOpts = { canvasPanel = canvasPanel, theme = policy.chooserTheme }
  for k, v in pairs(policy.cheatSheet or {}) do cheatSheetOpts[k] = v end
  cheatSheetAtom:configure(cheatSheetOpts)

  local chordKeyAtom = atoms.chordkey
  chordKeyAtom:init()
  chordKeyAtom:configure(policy.chord)

  -- Loaded here, ahead of step H's own init and configure, purely so the libs table two
  -- sections down can name it as a lib capability. Existence checking in step F's plan runs
  -- before step H does, so a lib module a plugin may declare needs.lib against has to exist
  -- as a loaded module this early even though it is not actually configured until later.
  local hyperKeyAtom = atoms.hyperkey

  local glyphIcon = glyphIconLib.new()

  ------------------------------------------------------------------------------
  -- STEP C. Manifests. Pure data, read before anything runs.
  ------------------------------------------------------------------------------

  local pluginRoots = { plugins = spoonDir .. "plugins", host = spoonDir .. "host" }
  local manifests, skippedManifests, directories = pluginsLib.readAll({
    pluginRoots.plugins, pluginRoots.host,
  })
  for identity, why in pairs(skippedManifests or {}) do
    log.e("Olm compose, plugin '" .. identity .. "' was left out, " .. tostring(why))
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
  local declarers = { root = load("root/manifest.lua") }
  for identity, manifest in pairs(manifests) do declarers[identity] = manifest end

  depsAtom:configure({ declared = pluginsLib.declarations(declarers, "Olm") })
  depsAtom:start()
  -- The one shared scope every plugin earning the ambient deps grant is handed, unscoped by
  -- consumer, matching what services.perPlugin's own contract says it hands out, the same
  -- single adapter every plugin sharing it in the live root already reads today.
  local sharedDepsScope = depsAtom:scope("Olm")

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

  local rawNames, baseFor, identityOfRaw = {}, {}, {}
  for identity, absolutePath in pairs(directories) do
    local base, rawName = absolutePath:match("^(.*/)([^/]+)$")
    if base and rawName then
      rawNames[#rawNames + 1] = rawName
      -- loader concatenates configdir directly onto this, and configdir below is spoonDir,
      -- so the base recorded here is only the part between spoonDir and the plugin root,
      -- plugins/ or host/, never the absolute path directories itself already carries.
      baseFor[rawName] = base:sub(#spoonDir + 1)
      identityOfRaw[rawName] = identity
    end
  end

  modules = loaderLib.modules(spoonDir, baseFor, rawNames, function(rawName)
    return identityOfRaw[rawName]
  end, log)
  -- A global asked for under a name no plugin answers to mirrors nothing, silently, which is how
  -- the one door a test suite reaches its plugin through was shut while the whole config looked
  -- healthy. Same slip as the data block below, and the same answer, say so.
  for name in pairs(globals) do
    if modules[name] == nil then
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
    hyperkey = hyperKeyAtom,
    recency = atoms.recency,
    storage = atoms.storage,
  }

  ------------------------------------------------------------------------------
  -- STEP E. The overlay display resolver, and what the two screen closures in
  -- step B call through now that it exists.
  ------------------------------------------------------------------------------

  overlay = overlayDisplayLib.new({
    canvasPanel = canvasPanel,
    -- The resolved tool rather than a name in a command string, declared by the root in
    -- root/manifest.lua since this lib module is the root's own apparatus and has no manifest of
    -- its own to declare with. It used to run the command by bare name, which worked and was
    -- still a second door, and an absent tool there was a silent empty answer.
    displayplacer = sharedDepsScope.path("displayplacer"),
    -- currentProfile answers a set question rather than naming a plugin, so a portable
    -- install with no display arrangement plugin simply always answers nil here, and fixed
    -- mode falls back to the active window the same way an unpinned arrangement already does.
    currentProfile = function()
      for identity, m in pairs(manifests) do
        if (m.provides or {}).profile and modules[identity] and type(modules[identity].current) == "function" then
          local ok, name = pcall(modules[identity].current, modules[identity])
          if ok then return name end
        end
      end
      return nil
    end,
    -- Contract v3's own addition, docs/BRIEF-CONTRACT-V3.md, a plain closure over
    -- stageModule rather than a manifest granted root word, since this lib module has no
    -- manifest to declare needs.data against at all. stageModule is a forward declared
    -- upvalue this closure only ever calls long after the ordinary wiring pass has made it
    -- real, the identical lateness every other root owned closure in this file already
    -- relies on. Lets the pin level's own Back row, and a pin just written, leave that
    -- level and restore root, the one thing a child pushed from overlay.select cannot
    -- express on its own.
    stagePop = function() return (stageModule and stageModule:pop()) or false end,
  })
  overlay.configure(policy.overlayDisplay or {})

  ------------------------------------------------------------------------------
  -- STEP F. The plan, in two passes.
  ------------------------------------------------------------------------------

  local resolver = resolveLib.new({ plugins = pluginsLib, defaults = defaultsLib, surface = surfaceLib })

  -- Two channels for the person's own values, and they are not the same shape on purpose.
  --
  -- cfg.shared is flat and keyed by FIELD NAME. A value in it reaches every plugin that
  -- declared a user sourced need of that name, which is what makes one application catalog
  -- serve the app toggles, the cheat sheet and the launcher without the person naming any of
  -- the three. Nothing here says which plugins those are, and a plugin that stops needing a
  -- field simply stops receiving it.
  --
  -- cfg.data is keyed by PLUGIN and merged over whatever the fan out reached, for the values
  -- that are genuinely about one plugin. It has to be per plugin because field names are not
  -- unique across the set, bundleID and settings each being wanted by more than one plugin
  -- meaning different things, and folding this into the flat table, as it was, meant one of
  -- them silently got the other's value.
  local sharedData = cfg.shared or {}
  local fannedData = servicesLib.fanOut(manifests, sharedData)
  for name, fields in pairs(cfg.data or {}) do
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
      if manifests[name] == nil then
        log.e("Olm compose, data was supplied for '" .. name
          .. "', which is not a plugin. Check the spelling against the name the plugin declares "
          .. "for itself, which is not always its directory.")
      end
      fannedData[name] = defaultsLib.merge(fannedData[name] or {}, fields)
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

  local firstPass = resolver.plan({
    manifests = manifests,
    user = cfg,
    present = presentTool,
    libNames = libNames,
    modules = modules,
    libs = libs,
    data = fannedData,
  })

  -- The values only pass one's plan.effective can answer, computed once and reused rather
  -- than rebuilt, so the second pass, the register stage, and the wiring args below can
  -- never disagree about what they hold.
  local keymapCatalog = firstPass.effective.keyremap and firstPass.effective.keyremap.catalog
  local appKeycode = leadersLib.keycode(keymapCatalog, leaderRoles.app)
  local windowKeycode = leadersLib.keycode(keymapCatalog, leaderRoles.window)
  local activeLeaderNames = leadersLib.activeNames(keymapCatalog, leaderRoles)

  -- What each leader role is CALLED where a person reads it, a row subtitle or a hint. The
  -- role is the word a manifest uses, app or window, and the catalog name is what that role
  -- resolves to on this machine, so a tool moved to the other leader is described correctly
  -- with no second place to edit. Title cased because these are read as words in a sentence
  -- rather than as the shouted constants the catalog spells them with.
  local leaderDisplayNames = {}
  for role, catalogName in pairs(leaderRoles) do
    local word = tostring(catalogName)
    leaderDisplayNames[role] = word:sub(1, 1):upper() .. word:sub(2):lower()
  end

  -- The one spelling of a chord, a leader's name then a space then the key glyph. Human
  -- wording is this file's answer, and two surfaces state the same chord, every launcher row
  -- and the docked hint bar, so spelling it in each is how one key comes to read two ways
  -- depending on where you met it. It did, one writing a plus where the other wrote a space.
  local function chordLabel(leader, key, mods)
    return leader .. " " .. cheatSheetAtom.glyphFor(key, mods)
  end

  -- The one spelling of a set of aliases, the words alone. Two surfaces state these as well,
  -- a launcher row and the alias directory's own rows, and each had written its own copy
  -- differing by a leading space. That space is the joiner rather than part of the wording,
  -- so it belongs to whichever caller is joining and not to this.
  local function aliasLabel(aliases)
    if not aliases or #aliases == 0 then return "" end
    return "(" .. table.concat(aliases, ", ") .. ")"
  end

  -- THE SEAM, Fact 1. WindowManager and WindowCheatSheet must dispatch and display the
  -- identical physical key, so this stamped table is built exactly once, right here, and
  -- the same local is handed to both consumers below rather than two calls that would only
  -- happen to agree today.
  local stampedWindowBindings = leadersLib.stampBindings(
    firstPass.effective.windowmanager and firstPass.effective.windowmanager.windowManagement,
    windowKeycode)

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
  -- Migrated onto host/stage. overlay owns no picker of its own any more, so this asks
  -- whichever presentation is actually current, the identical isShowingFor shape every
  -- presenting plugin's own context predicate already resolves through, named by hand here
  -- since this tool has no manifest and so builds no context of its own for isShowingFor to
  -- be asked about. Referenced by a when now, consumer map surprise 9.2's other half closed
  -- in the chooser stage close out, a root contributed context block below building exactly
  -- the manifest.surface declaration this lib module cannot make itself, docs/REVIEW-FINAL-
  -- BATCH.md's own recommended shape, "a root contributed context block plus a root
  -- contributed adapter". Named "overlayDisplayOpen" here first regardless, since it was kept
  -- correct even while nothing referenced it, so surfaceLib.context's own default when name
  -- for this context, name .. "Open", would find this predicate already installed rather than
  -- the two drifting apart.
  ownPredicates.overlayDisplayOpen = function()
    return stageModule ~= nil and stageModule:current() == "overlayDisplay" and stageModule:isShowing() == true
  end

  -- Whether the launcher is holding somebody else's list rather than its own catalog, which is
  -- what decides whether the key that steps back out means anything. The launcher already
  -- answers this about itself, so this only names the host, which this file is allowed to do.
  --
  -- It was declared by a binding and defined nowhere, and an unknown predicate is treated as
  -- always active by design, so the way out was listed in the hint panel at all times including
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

  local toastContent = hintsLib.toast({ theme = policy.chooserTheme })

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

  local rootValues = {
    -- Which leader names are actually live on this keyboard, KeyRemap's own contract.
    activeNames = activeLeaderNames,

    -- THE SEAM, Fact 1's other half. Both window consumers receive the IDENTICAL stamped
    -- table, under the two different field names their own configure calls happen to read,
    -- because a row that names a key and the dispatch that acts on it can never be allowed to
    -- disagree. Two entries pointing at one object is what makes that structural rather than a
    -- thing that only happens to be true today.
    mapping = stampedWindowBindings,
    windowManagement = stampedWindowBindings,

    -- The shared when name to predicate table every gated binding is resolved against.
    predicates = ownPredicates,

    -- What the window leader's own overlay section is CALLED. Policy rather than anything
    -- derivable, since the leader's own name, META, says nothing to somebody reading a list of
    -- window actions, so it ships as a default a person may override.
    leaders = windowKeycode and { [windowKeycode] = policy.windowSectionTitle } or nil,

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
    -- itself specifically, or not at all, browsertabs' own settings and browser children
    -- passing themselves this way. An async answer lands on its own level or not at all, the
    -- rule this word now keeps for every caller, token or none.
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

    -- stageSetQuery, the trickle migration's own addition, FileSearch's own parent row
    -- intercept, which puts the query for the level above in the field and the presentation
    -- stays open, the identical "swap the list in place" shape host/launcher's own paging
    -- already performs through Stage:setQuery directly, since the launcher holds the stage.
    -- A presenting plugin has no such direct hold, so this is the one word letting it reach
    -- the identical field control. host/stage's own _intercept, and native.lua's contract
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

    -- One line of feedback, and one sampled colour, both on the shared overlay so they read as
    -- part of the same interface as the cheat sheet and the docked hint bars.
    notify = notify,
    showColor = showColor,

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
    -- own roots, because this is the tracked layer a person edits by hand.
    storePath = servicesLib.perName(function(name)
      return hs.configdir .. "/config/" .. name .. ".json"
    end),
  }

  local rootFanned = servicesLib.fanOut(manifests, rootValues, "root")

  plan = resolver.plan({
    manifests = manifests,
    user = cfg,
    present = presentTool,
    libNames = libNames,
    modules = modules,
    libs = libs,
    data = servicesLib.merge(fannedData, rootFanned),
  })

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
  -- STEP G. Leaders, continued. The app and window keycodes above are reused
  -- here for the two engines rather than resolved a second time.
  ------------------------------------------------------------------------------

  -- windowLeaderIdentity is kept as its own local, rather than folded straight into the
  -- lookup below, because it is read a second time a few lines down, to find windowleader's
  -- own manifest. WindowLeader itself still has to be named here, one of the fixed leader
  -- engines the eight stage pipeline registers and starts directly, stage one and stage
  -- eight below, and no manifest field yet exists that would let this file discover which
  -- plugin plays that role rather than being told outright.
  local windowLeaderIdentity = plan.identity.windowleader or "windowleader"
  local windowLeaderModule = modules[windowLeaderIdentity]

  -- The hold and release callbacks windowLeaderModule:configure receives further down used
  -- to be built right here, two closures each reaching straight for
  -- modules[plan.identity.windowcheatsheet or "windowcheatsheet"], a second plugin under
  -- plugins named as a literal, exactly the leak this file's own header forbids nowhere else
  -- may do. WindowLeader's own manifest.lua now declares that coupling itself,
  -- needs.siblings.windowCheatSheet, ordering false, because the collaborator is only ever
  -- closed over inside a callback that fires long after every plugin's own configure has
  -- already run, never read at configure time itself, the same distinction MenuSearch's own
  -- Launcher closures already rest on. This file's job shrinks to resolving that one declared
  -- field against the real module set, the same way lib/wire.lua's own needs.lib grant
  -- already resolves a lib capability, bound to its own module when it names a method so the
  -- plugin never receives a bare colon method with no self to call it against. Written as a
  -- function of one manifest and one field rather than a walk over every manifest's own
  -- siblings, because a blanket walk would start handing values to plugins whose own coupling
  -- to the same identity is already resolved a different way, Launcher's own windowActions
  -- among them, and turning that on by accident is a decision for whoever owns that seam to
  -- make on purpose rather than one this fix should make by accident.
  local function resolveDeclaredSibling(manifest, field)
    local decl = ((manifest or {}).needs or {}).siblings or {}
    decl = decl[field]
    if not decl or not decl.plugin then return nil end
    local siblingModule = modules[plan.identity[decl.plugin] or decl.plugin]
    if not siblingModule then return nil end
    if not decl.member then return siblingModule end
    local fn = siblingModule[decl.member]
    if type(fn) == "function" and decl.call ~= "dot" then
      return function(...) return fn(siblingModule, ...) end
    end
    return fn
  end
  local windowCheatSheetForLeader =
    resolveDeclaredSibling(manifests[windowLeaderIdentity], "windowCheatSheet")

  -- The flat root argument namespace, deps.args, the only channel a non configure wiring
  -- step can read a value through when that step's own signature is not opts shaped.
  -- mapping and activeNames close Fact 1's other half and KeyRemap's own contract. leader
  -- and predicates exist here, named directly, for the identical reason, bindToLeader takes
  -- the WindowLeader module and the predicate table as plain positional arguments rather
  -- than reading them off an opts table, so nothing generic can hand them over, and this
  -- file is the only place that may still say which module answers "the window leader".
  local wiringArgs = {
    activeNames = activeLeaderNames,
    mapping = stampedWindowBindings,
    leader = windowLeaderModule,
    predicates = ownPredicates,
  }

  -- Assigned rather than declared, joining the forward declared set at the top of this
  -- function in phase three. Needed here, synchronously, rather than only inside a later
  -- closure, because the surface adapters loop a little further down builds its answer NOW,
  -- not the moment a key is pressed, so stageModule has to be real before that loop runs
  -- rather than merely before Hammerspoon starts idling. wiredRegistry, assigned further
  -- down this file, is not moved, since the surface adapters loop still runs after that
  -- assignment in this function's own sequence and only isShowingFor, a closure, reaches it
  -- ahead of that point in the source.
  stageModule = modules[plan.identity.stage or "stage"]

  local contextOwners = hintsLib.contextOwners(plan, manifests)

  -- Walk to wherever a plugin actually keeps its picker, which is what its manifest already
  -- says through registry.surface. Five plugins keep it on a submodule, the clipboard on
  -- manager and four more on chooser, and asking their root alone answered nothing.
  local function surfaceOf(module, spec)
    if spec == nil or spec == true then return module end
    local owner, value = module, module
    for part in tostring(spec):gmatch("[^.]+") do
      if type(value) ~= "table" then return nil end
      owner, value = value, value[part]
    end
    -- A surface may be a member that ANSWERS the adapter rather than being it, which is how
    -- three of these are written, so the value is called when it is a function. Both calling
    -- conventions are tried for the same reason the caller below tries both.
    if type(value) == "function" then
      local ok, answer = pcall(value, owner)
      if ok and type(answer) == "table" then return answer end
      local dotOk, dotAnswer = pcall(value)
      if dotOk and type(dotAnswer) == "table" then return dotAnswer end
      return nil
    end
    return value
  end

  -- Whether a named context's surface is currently open, tried both calling conventions a
  -- surface's own isShowing might use, since no manifest field states which one a plugin
  -- picked and getting it wrong resolves to something that fails on arity rather than
  -- cleanly, the exact defect the first attempt shipped for three surfaces at once.
  --
  -- This asked the plugin ROOT and stopped there, and for five of the twelve pickers the root
  -- has no isShowing at all, so the answer was a flat false forever. Every chord inside those
  -- five was bound, gated on this, and therefore dead, and because the gate failed rather than
  -- errored the plain Hyper binding on the same key fired instead. So pressing j in the
  -- clipboard to move down opened the emoji picker, which is the behaviour a person reports as
  -- the shortcut not working, and nothing anywhere logged a thing.
  --
  -- A presenting plugin, phase three of the chooser stage build, is asked a third way, ahead
  -- of both of the above, since its own module may no longer carry an isShowing at all, VPN's
  -- own surface adapter having been deleted in favour of the shared stage. wiredRegistry
  -- already knows which plugins present, presentationFor answers nil for one that does not,
  -- so this asks the registry rather than probing the module for a method that used to be
  -- there. Routes through stage:current() plus stage:isShowing(), decision seven of the
  -- handoff brief, exactly what host/stage's own surfaceFor already answers for the nav
  -- registry, so a context's predicate and its navigation adapter can never disagree about
  -- whether it is open.
  local function isShowingFor(contextName)
    local owner = contextOwners[contextName]
    if not owner then return false end
    local ownerIdentity = plan.identity[owner] or owner
    if stageModule and wiredRegistry and wiredRegistry.presentationFor
      and wiredRegistry.presentationFor(ownerIdentity) then
      return stageModule:current() == ownerIdentity and stageModule:isShowing() == true
    end
    local module = modules[owner]
    if not module then return false end
    local manifest = manifests[owner] or {}
    local spec = (manifest.surface or {}).member or (manifest.registry or {}).surface
    local holder = module
    if type(module.isShowing) ~= "function" then
      holder = surfaceOf(module, spec)
    end
    if type(holder) ~= "table" or type(holder.isShowing) ~= "function" then return false end
    local ok, answer = pcall(holder.isShowing, holder)
    if ok then return answer == true end
    local dotOk, dotAnswer = pcall(holder.isShowing)
    return dotOk and dotAnswer == true
  end

  ------------------------------------------------------------------------------
  -- STEP H. The engines.
  ------------------------------------------------------------------------------

  -- Ported from the live root's onHold and onHoldEnd. contextOverlays stays the same empty
  -- seam the live root still carries, a modal context reveals nothing of its own here, its
  -- hints already live on the docked panel, and the base layer alone reveals the apps sheet.
  local heldHyperLayer = nil
  local function revealHyperLayer()
    local activeCtx = hintsLib.activeContext(plan, isShowingFor)
    if activeCtx then
      heldHyperLayer = "none"
    else
      -- THE SEAM. HyperCheatSheet is one of the five host modules this file may name.
      local sheet = modules[plan.identity.hypercheatsheet or "hypercheatsheet"]
      if sheet then sheet:show() end
      heldHyperLayer = "apps"
    end
  end
  local function hideHyperLayer()
    if heldHyperLayer == "apps" then
      local sheet = modules[plan.identity.hypercheatsheet or "hypercheatsheet"]
      if sheet then sheet:hide() end
    end
    heldHyperLayer = nil
  end

  -- hyperKeyAtom itself was already loaded in step B, purely so the libs table could name it
  -- early. Loading it a second time here would build a second, separate module table, the
  -- one every needs.lib.hyperKey grant already points at staying forever uninitialized while
  -- this second copy alone received init and configure, which is not a hidden defect this
  -- comment papers over, it is the reason there is only one load site and this is not it.
  hyperKeyAtom:init()
  local trigger = leadersLib.mergeTrigger(policy.hyperTrigger, appKeycode)
  hyperKeyAtom:configure({
    chord = chordKeyAtom,
    trigger = trigger,
    tapThreshold = policy.chord.tapThreshold,
    holdDelay = policy.chord.holdDelay,
    onTap = function() hs.hid.capslock.toggle() end,
    onHold = revealHyperLayer,
    onHoldEnd = hideHyperLayer,
  })

  -- No init call here. lib/loader.lua already called it uniformly on every loaded module,
  -- windowLeaderModule included, so calling it again would run its reset twice for no
  -- reason and is exactly the parity gap that module exists to close rather than repeat.
  --
  -- Guarded, unlike the call this replaced. A portable install can genuinely carry no
  -- windowleader plugin at all, and calling configure on a nil module is not a degraded
  -- window leader, it is this whole composition root going down before a single other
  -- plugin has wired, which is worse than the dead surface a missing required tool already
  -- earns a plugin elsewhere in this file. windowCheatSheet is windowCheatSheetForLeader,
  -- resolved above from windowleader's own declared sibling need rather than looked up here
  -- by name, and windowleader/init.lua builds the actual hold and release closures itself
  -- now, this file only ever hands over the collaborator.
  if windowLeaderModule then
    windowLeaderModule:configure({
      chord = chordKeyAtom,
      holdDelay = policy.chord.holdDelay,
      windowCheatSheet = windowCheatSheetForLeader,
    })
  end

  ------------------------------------------------------------------------------
  -- Presentation deps, one shared table for every lib/hints.lua call this file
  -- makes directly or hands to services.perPlugin to make on its behalf.
  ------------------------------------------------------------------------------

  local function hideSharedOverlay() hideHyperLayer() end

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

  local hintsDeps = {
    predicates = ownPredicates,
    glyphFor = cheatSheetAtom.glyphFor,
    owners = contextOwners,
    canvasPanel = canvasPanel,
    theme = policy.chooserTheme,
    settings = policy,
    hideShortcuts = hideSharedOverlay,
    chordLabel = chordLabel,
    -- leaderName hands over this leader's already resolved word rather than the catalog
    -- itself, since deciding what a leader is called belongs to this file and lib/hints.lua
    -- must not learn it by name any more than it learns any other plugin's name.
    leaderName = leaderDisplayNames.app,
    -- kinds carries the same action kind overrides the actionKinds call below is given,
    -- since rowsFor derives kinds a second time inside hints.lua, and it must see the same
    -- overrides the panel's own kindOf uses or the panel rows and verbsIn drift apart.
    kinds = actionKindOverrides,
    -- liveLabels, harvested above off whatever each module offers rather than written here, so
    -- a word that follows a plugin's own live state reaches the hint bar and the action panel
    -- with this file still naming no plugin. It was absent, on the grounds that the only case
    -- then in existence, the launcher's Run reading as Open over an application row, was that
    -- plugin's own business and there was nowhere generic to reach it from. The generic place is
    -- the same one the predicates already use, one screen up, and a picker whose primary key
    -- means something else on a second page is what made the difference worth paying. The
    -- launcher's own case is still its own and is not routed through here.
    liveLabels = ownLiveLabels,
  }

  -- HyperCheatSheet and QueryScope both reset the whole of what configure gave them on
  -- every call rather than merging, so the base opts built here are reused verbatim for
  -- their post register second call in step K, instead of being recomputed and risking two
  -- slightly different tables answering for the same plugin in the same run.
  -- Read off sharedData, which is where a person actually puts these two, cfg.shared. They
  -- were read as cfg.apps and cfg.appToggles, fields nothing has ever sent, so both were nil
  -- on every run and the overlay's whole application half was empty. It looked like a
  -- rendering fault and was a spelling one, and the second configure call in step K reuses
  -- this same table, so the wrong names were applied twice rather than once.
  local hyperCheatSheetOpts = {
    apps = sharedData.apps,
    toggles = sharedData.toggles,
    cheatSheet = cheatSheetAtom,
  }

  -- The window overlay's own three root owned values are NOT built here any more, and that is
  -- the point rather than an omission. It declares windowManagement, leaders and predicates,
  -- every one of them a root value another plugin also asks for by the same name, so all three
  -- now reach it through the root fan out above with this file never naming it. Building them
  -- here was what made a plugin under plugins appear as a literal in a file whose own header
  -- forbids exactly that, and being on the hand written list is what every plugin that went
  -- without was missing.
  local queryScopeOpts = {
    matcher = chooserAtom.matchers and chooserAtom.matchers[policy.matcher],
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
  local dispatchTable
  local actionKinds = hintsLib.actionKinds(plan, actionKindOverrides)
  local actionPanelOpts = {
    kindOf = function(action) return actionKinds[action] end,
    rowsFor = function(contextName, hosted) return hintsLib.rowsFor(contextName, plan, hintsDeps, hosted) end,
    run = function(action)
      local fn = dispatchTable and dispatchTable[action]
      if fn then fn() end
    end,
    icon = glyphIcon.icon,
  }

  -- deps.hints receives this same table forwarded whole into shortcutPanelFor for whichever
  -- plugin earns a docked panel, which is why the fields above sit next to deps.libs and
  -- deps.deps here rather than in a table of their own.
  local perPluginDeps = {}
  for k, v in pairs(hintsDeps) do perPluginDeps[k] = v end
  perPluginDeps.hints = hintsLib
  perPluginDeps.libs = libs
  perPluginDeps.deps = sharedDepsScope

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
  -- THE SEAM, its second half. The panel triple used to be the launcher's own, read straight
  -- off perPluginData, correct only for as long as the launcher was the one presentation there
  -- was. Phase three's own decision seven, contexts and hints follow current(), means the
  -- docked hint bar beneath the stage's one window has to answer for whichever presentation is
  -- actually up, VPN's own keys while VPN is presented and the launcher's again after pop, not
  -- the launcher's forever. lib/hints.lua's own shortcutPanelFor now accepts a function for the
  -- context name it renders hints for, asked fresh on every reveal rather than fixed once, so
  -- this builds ONE dedicated panel for the stage, here, naming no plugin, asking only
  -- stageModule:current() at the moment a hint is actually about to be drawn. The generic
  -- panel services.perPlugin still builds for the launcher's own identity, because
  -- host/launcher/manifest.lua still declares a surface and earns one automatically, is left
  -- unused rather than suppressed, since nothing in this contract lets one plugin's manifest
  -- opt out of an entitlement its own declared surface earns, and an unarmed CanvasPanel nobody
  -- ever positions costs nothing worth a deeper change to avoid.
  local stagePanel = hintsLib.shortcutPanelFor(
    function() return (stageModule and stageModule:current()) or (plan.identity.launcher or "launcher") end,
    plan, hintsDeps)
  local stageOpts = {
    chooser = chooserAtom,
    theme = policy.chooserTheme,
    onPositioned = stagePanel.onPositioned,
    onActivity = stagePanel.onActivity,
    onClose = stagePanel.onClose,
  }

  -- fannedData WINS, and its absence here altogether was the single worst defect in this build.
  --
  -- Everything a person supplies arrives in it, cfg.shared fanned out by field name and
  -- cfg.data keyed by plugin, and it was handed to resolver.plan and then to nothing else. So
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
    hypercheatsheet = hyperCheatSheetOpts,
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
    paneElements = canvasPanel.surfaceElements,
    log = log,
    -- onPositioned, onActivity and onClose are deliberately never passed here. Each
    -- surfaced plugin needs its OWN docked panel closure, never one shared function every
    -- plugin would otherwise receive identically, so that triple travels through
    -- services.perPlugin above, into wireData, the one channel built to carry a value the
    -- flat ambient grant structurally cannot.
  })

  wiredRegistry = registryLib.new({ apiVersion = REGISTRY_API_VERSION, log = log })

  local function describeForRegistry(name, planArg)
    -- matchers, contract v2 decision one, docs/BRIEF-CONTRACT-V2.md, is what lets the
    -- registrar refuse a presentation.matcher naming a strategy the Chooser atom does not
    -- export, loudly, at register, rather than have host/stage/init.lua's own _resolveMatcher
    -- discover the typo at runtime and quietly fall back to the root default. The identical
    -- table ambientServices.matcher above is already resolved against for every unmigrated
    -- consumer, so this names no new concretion, only hands the registrar the same map.
    return registrarLib.describe(name, planArg, modules, manifests, registryMeta,
      REGISTRY_API_VERSION, { merge = defaultsLib.merge, redraw = redrawSurface, log = logFn,
        matchers = chooserAtom.matchers })
  end

  local function bindShortcut(entry)
    return registrarLib.bind(entry, plan, {
      log = logFn,
      bindLeader = function(key, mods, fn) hyperKeyAtom:bind(key, fn, mods) end,
      bindGlobal = function(mods, key, fn) hs.hotkey.bind(mods, key, fn) end,
      -- A command belongs to no plugin, appendCopy and pasteNext being the concrete example,
      -- so its key is root policy with nowhere else to live. registryMeta is exactly that
      -- policy table, keyed the same way for a command's own name as for a tool's identity.
      rootKey = function(name)
        -- An override for this command's own name wins, the same way it does for a tool.
        local info = registryMeta[name]
        if info and info.key then return { key = info.key, mods = info.mods } end

        -- Otherwise whichever manifest declares a command by this name ships its key. Walked
        -- rather than looked up because a command is named inside its owner's registry block
        -- and nothing anywhere records which plugin owns which command name, which is right,
        -- since a command is deliberately not a tool of its own.
        for _, m in pairs(manifests) do
          local declared = ((m.registry or {}).commands or {})[name]
          if declared and declared.key then
            return { key = declared.key, mods = declared.mods }
          end
        end
        return nil
      end,
    })
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

  local surfaceAdapters, seenOwner = {}, {}
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
      end
    end
  end

  -- THE SEAM. Overlay display has no manifest, being a lib module rather than a plugin, so it
  -- never appears in plan.order and the loop above, which walks that order looking for a
  -- context owner, can never find it and can never build it an adapter. Its predicate already
  -- exists by the identical route, ownPredicates.overlayDisplayOpen above, named by hand for
  -- the same reason. Two joins, mirroring that precedent rather than inventing a second
  -- mechanism for one tool. lib/resolve.lua itself is untouched, plan.contexts and
  -- surfaceAdapters are both plain tables a root is already free to add to, so both joins are
  -- root policy contributed into the same structures a plugin's own surface would have fed,
  -- never a plugin pretending to be one and never a change to how either structure is built.
  --
  -- One, the context block itself, built through the identical lib/surface.lua a plugin's own
  -- declared surface already goes through, so the bindings, the when name, and the priority
  -- read exactly as they would for a real plugin. primary is the only field this needs to
  -- state, i inserts the highlighted row, matching config/keys.lua's own long standing
  -- overlayDisplay block, review finding L3, docs/REVIEW-FINAL-BATCH.md. nav defaults true, so
  -- j and k move the highlight, which is the dead pair this join exists to answer for. close
  -- defaults to x, and when defaults to "overlayDisplayOpen", the exact name ownPredicates
  -- already installs above, so the binding this produces is gated correctly with nothing
  -- further to wire.
  --
  -- surfaceLib.context also appends ACTION_PANEL_BINDING, Hyper and period, to every block it
  -- builds, unconditionally, so this join newly binds that key here too, not only i, j, k, and
  -- x. It is newly bound and inert, both true at once rather than the second standing in for
  -- the first. root/compose.lua's own isShowingFor requires a contextOwners entry to recognise
  -- a context as showing, contextOwners is built from plan.order and manifest.surface, and
  -- overlay display is in neither, so openActionPanel's own scan finds no match and does
  -- nothing. That gap predates this join and this join does not close it, but the key itself is
  -- new, where before nothing bound Hyper and period in this context at all.
  plan.contexts.overlayDisplay = surfaceLib.context("overlayDisplay", {
    primary = { action = "insertSelected", description = "Select" },
  })

  -- Two, the adapter. Stage:surfaceFor already answers the five generic verbs scoped to
  -- whether THIS name is current, the identical call every presenting plugin's own adapter
  -- makes inside surfaceAdapterFor above, so overlay display asks for the same thing by hand
  -- rather than through the loop that can never reach it. Appended after the loop rather than
  -- inside it, since it owns no plan.order entry to be found at.
  --
  -- THE SEAM. Laziness here is mandatory, not stylistic, the exact defect a live probe found,
  -- the config dying before ipc ever came up. stageModule:surfaceFor("overlayDisplay") reads
  -- self.surface, host/stage/init.lua's own field built inside Stage:configure, stage two of
  -- the eight fixed stages below, w.configure(modules, manifests), which has not run yet at
  -- the point this line executes, this whole join sitting well before STEP J even starts.
  -- Calling surfaceFor here, eagerly, at wire time, indexes a nil self.surface and crashes the
  -- whole config load. The identical class of defect phase three review finding one already
  -- named for the ordinary presenting plugin path above, resolved eagerly before the thing
  -- being resolved existed, and surfaceAdapterFor's own lazy __index immediately above this
  -- is the fix that was already written for it, so this mirrors that precedent rather than
  -- inventing a second shape. The whole call is deferred, not only the field read after it,
  -- since Stage:surfaceFor itself indexes self.surface the moment IT runs, so a proxy that
  -- resolved surfaceFor eagerly and only deferred the methodName lookup would still crash at
  -- the same line. Nav asking whether this context is showing, lib/nav.lua's own
  -- activeSurface, is what triggers resolution now, which never happens before every stage
  -- has run, since nothing dispatches a key until w.start, the very last one.
  if stageModule then
    surfaceAdapters[#surfaceAdapters + 1] = setmetatable({}, {
      __index = function(_, methodName)
        local fn = stageModule:surfaceFor("overlayDisplay")[methodName]
        if not fn then return nil end
        return function(...)
          local ok, result = pcall(fn, ...)
          return ok and result
        end
      end,
    })
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

  w.leaders({ windowLeaderModule }, { windowKeycode })
  w.configure(modules, manifests)
  w.steps(modules, manifests)
  w.predicates(hyperKeyAtom, ownPredicates)
  -- forWire's own activate reads a persisted roster ahead of anything passed here, and
  -- falls all the way back to every name that registered this run when nothing else was
  -- given, which is the safest default and the reason nil is handed for both remaining
  -- arguments rather than plan.order, most of which never registers as a tool at all.
  local forWire = registrarLib.forWire(wiredRegistry, nil, nil)
  w.register(forWire, describeForRegistry, bindShortcut)

  -- The two system actions that belong to no plugin and therefore to no registration, so the
  -- one loop that binds every registered tool's key never sees them. Locking and sleeping are
  -- plain macOS calls with nothing behind them worth a plugin, and inventing one just to give
  -- them a home would be ceremony, so the leader binds them here from whatever the launcher's
  -- own special rows declared. They were bound by the retired root and by nothing here, which
  -- is how two working keys became two rows in a list and nothing else.
  -- The open key of anything that declares one and does NOT register. Every registered tool's
  -- key is bound by the loop above, off registry.shortcuts, and a host is not a tool, so a host
  -- that declares a key had nothing anywhere binding it. The launcher is that case, and its own
  -- key is the one every other surface is reached from, so losing it takes most of the config
  -- with it while every check still reports a clean wiring run.
  --
  -- Derived rather than named. Anything with a key, a leader, and a way to be shown, that the
  -- registry did not already claim, gets its key bound, so a second host answering the same
  -- description needs no edit here.
  do
    local claimed = {}
    for _, entry in ipairs(wiredRegistry.shortcuts() or {}) do claimed[entry.name] = true end

    for directory, eff in pairs(plan.effective or {}) do
      local identity = plan.identity[directory] or directory
      local module = modules[identity]
      if eff.key and eff.leader and module and not claimed[identity]
        and type(module.show) == "function" then
        local code = leadersLib.keycode(keymapCatalog, leaderRoles[eff.leader] or eff.leader)
        -- Only the app leader's own engine binds by key today, which is what hyperKeyAtom is,
        -- so a host on another leader is left alone rather than bound to the wrong engine.
        if code == appKeycode then
          hyperKeyAtom:bind(eff.key, function() module:show() end, eff.mods)
        end
      end
    end
  end

  do
    local systemCalls = {
      lock = function() hs.caffeinate.lockScreen() end,
      sleep = function() hs.caffeinate.systemSleep() end,
    }
    local launcherEff = (plan.effective or {})[plan.identity.launcher or "launcher"] or {}
    for _, row in ipairs(launcherEff.specialRows or {}) do
      local call = systemCalls[row.name]
      if call and row.key then hyperKeyAtom:bind(row.key, call) end
    end
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

  w.contexts(hyperKeyAtom, bindOneInContext)
  w.start({ hyperKeyAtom, windowLeaderModule }, chordKeyAtom)

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
  -- STEP K. The post register pass. Three second configure calls the fixed
  -- pipeline genuinely cannot express, since each needs a value that exists
  -- only once stage five has already run.
  ------------------------------------------------------------------------------

  local hyperCheatSheetModule = modules[plan.identity.hypercheatsheet or "hypercheatsheet"]
  if hyperCheatSheetModule then
    -- Closes Fact 3. sections enumerates every tool that actually owns a Hyper chord by
    -- reading the registry hints.sections was handed, rather than a hand kept list that is
    -- already stale by the live root's own admission. The raw registry instance is handed
    -- here rather than the zero argument wire adapter, since sections reads rowFor and
    -- shortcuts, neither of which the wire adapter promises to carry.
    local opts = { apps = hyperCheatSheetOpts.apps, toggles = hyperCheatSheetOpts.toggles,
      cheatSheet = hyperCheatSheetOpts.cheatSheet }
    -- Told which leader's overlay this is, so a tool bound to the window leader stays off the
    -- Hyper one, and so the plugins that carry their own binding list rather than a launcher
    -- row are picked up for this leader too.
    opts.sections = hintsLib.sections(wiredRegistry, plan, { leader = "app" })
    hyperCheatSheetModule:configure(opts)
    -- Keyed by DIRECTORY rather than by identity, since that is how a manifest is keyed and the
    -- delivery check reads the two side by side. This host spells the two the same way, and four
    -- others in this set do not, so using the identity here would quietly stop matching the day
    -- one of them was renamed.
    lateData.hypercheatsheet = opts
  end

  local queryScopeModule = modules[plan.identity.queryscope or "queryscope"]
  if queryScopeModule then
    -- Membership from the plan's own set answer, which is the question this host declared
    -- rather than a roster anyone here keeps, and the scope itself from the live registry, so
    -- a tool that is present but switched off keeps no word.
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
    local launcherModuleForAlias = modules[plan.identity.launcher or "launcher"]
    local aliasPolicy = policy.aliasDirectory or {}
    local aliasScope = registrarLib.aliasDirectory({
      catalog = function() return queryScopeModule:catalog() end,
      queryFor = function(name) return queryScopeModule:queryFor(name) end,
      show = function(query) if launcherModuleForAlias then launcherModuleForAlias:show(query) end end,
      title = aliasPolicy.title,
      glyph = aliasPolicy.glyph,
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
          glyph = spec.glyph,
          aliases = spec.aliases,
          rows = function() return launcherModuleForAlias:rowsOfKind(spec.kind) end,
          run = function(payload) launcherModuleForAlias:runItem(payload) end,
        }
      end
    end

    if aliasScope then scopes[#scopes + 1] = aliasScope end

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

    local queryScopeLate = { matcher = queryScopeOpts.matcher, scopes = scopes }
    queryScopeModule:configure(queryScopeLate)
    lateData.queryscope = queryScopeLate
  end

  local launcherModule = modules[plan.identity.launcher or "launcher"]
  if launcherModule then
    -- The ordered query row sources. QueryScope leads, since it is the one that CLAIMS a
    -- query outright rather than only computing a row for it, then every plugin the plan's
    -- own set answer says provides queryRows, in the order the plan already settled on.
    local queryProviders = {}
    if queryScopeModule then queryProviders[#queryProviders + 1] = queryScopeModule end
    for _, identity in ipairs((plan.sets.launcher or {}).queryRows or {}) do
      if modules[identity] then queryProviders[#queryProviders + 1] = modules[identity] end
    end

    -- Every leaf this catalogue dispatches to, resolved from its OWN manifest's sibling
    -- declarations rather than written out here. That is what keeps this block from naming a
    -- plugin, the names live in the manifest of the host that wants them, and an install
    -- missing one of those plugins simply gets nil for that leaf and never builds a row of
    -- that kind. The same resolution wire.lua's stage two already does, repeated here because
    -- Launcher's own configure resets every field it reads rather than merging, so a second
    -- call has to restate everything the first one gave it.
    local kin = {}
    do
      local launcherManifest = manifests[plan.identity.launcher or "launcher"] or {}
      for field, decl in pairs(((launcherManifest.needs or {}).siblings) or {}) do
        if type(decl) == "table" and decl.plugin then
          local mod = modules[plan.identity[decl.plugin] or decl.plugin]
          if mod and decl.member then
            local fn = mod[decl.member]
            if type(fn) == "function" then
              kin[field] = (decl.call ~= "dot") and function(...) return fn(mod, ...) end or fn
            end
          end
        end
      end
    end

    local launcherEffective = (plan.effective or {})[plan.identity.launcher or "launcher"] or {}

    -- The rows for capture's own actions, built from whatever that plugin's effective
    -- bindings turned out to be rather than from a copy of them kept here, so moving one of
    -- its keys moves the row with it. The set query answers which plugin provides them, so
    -- this names none.
    local captureRows = {}
    for _, identity in ipairs((plan.sets.launcher or {}).actionRows or {}) do
      local directory = identity
      for dirName, id in pairs(plan.identity or {}) do
        if id == identity then directory = dirName break end
      end
      local eff = (plan.effective or {})[directory] or {}
      for _, b in ipairs(eff.bindings or {}) do
        captureRows[#captureRows + 1] = {
          action = b.action, key = b.key, mods = b.mods,
          description = b.description, leader = eff.leader, glyph = b.glyph,
        }
      end
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
      toggles = sharedData and sharedData.toggles,
      apps = sharedData and sharedData.apps,
      predicates = ownPredicates,
      queryProviders = queryProviders,
      -- The drawer itself, not its icon function. This host stores what it is given and then
      -- calls .icon on it, so handing over the function alone made every row build raise the
      -- moment it asked for an icon, which is every row.
      glyphIcon = glyphIcon,

      -- Without this the catalogue asks nothing about any tool and draws no tool row at all,
      -- which is exactly what it did.
      registry = wiredRegistry,
      glyphFor = cheatSheetAtom and cheatSheetAtom.glyphFor,
      leaderNames = leaderDisplayNames,
      windowLeaderName = leaderDisplayNames.window,
      -- The shared speller rather than one the launcher owns for itself, so a row states the
      -- same chord the docked hint bar already agreed on.
      chordLabel = chordLabel,
      windowActions = kin.windowActions and kin.windowActions() or {},
      -- The SAME stamped table both window consumers already hold, Fact 1's own object, so a
      -- row in this list can never name a different physical key than the one that acts.
      windowBindings = stampedWindowBindings,
      settingsPanes = kin.settingsPaneRows and kin.settingsPaneRows() or {},
      captureRows = captureRows,
      specialRows = launcherEffective.specialRows,

      -- What a row says about being reachable by a typed word, asked of the resolver that owns
      -- the grammar rather than restated here.
      aliasHint = function(name)
        if not queryScopeModule then return "" end
        local aliases = queryScopeModule:aliasesOf(name)
        local words = aliasLabel(aliases)
        if words == "" then return "" end
        return " " .. words
      end,

      -- The leaf dispatch. The catalogue owns the kind switch, these are the calls it routes
      -- to, and every one either goes through a declared sibling above or is a plain macOS
      -- call this file can make without knowing about any plugin.
      actions = {
        app = function(bundleID, url)
          if url then
            if kin.appToggleURL then kin.appToggleURL(bundleID, url) end
          elseif kin.appFocus then
            kin.appFocus(bundleID)
          end
        end,
        capture = function(name) if kin.runCapture then kin.runCapture(name) end end,
        settingsPane = function(url) if kin.openSettingsPane then kin.openSettingsPane(url) end end,
        -- A computed result lands on the pasteboard plainly, so it joins clipboard history
        -- like any other copy, unlike the hidden writes the insertion paths use.
        copy = function(value) hs.pasteboard.setContents(value) end,
        scope = function(item) if queryScopeModule then queryScopeModule:run(item) end end,
        scopePeek = function(item) if queryScopeModule then queryScopeModule:peek(item) end end,
        scopeCanPeek = function(item)
          return queryScopeModule ~= nil and queryScopeModule:canPeek(item) == true
        end,
        -- Decision two of the handoff brief, the first branch added in phase three. A
        -- special row names a registered tool, and wiredRegistry.presentationFor answers a
        -- presentation for one that has migrated onto the stage, nil for every one that has
        -- not, which is the whole of what lets an unmigrated tool fall through to the second
        -- branch below completely untouched. The callable itself does nothing but push, no
        -- hide, no deferral, decision two's own words, since Stage:push already does the
        -- query clear and the refresh(true) that redraw means. It is genuinely two rebuilds
        -- rather than the one decision two names, phase three review finding seven, since
        -- Chooser:_intercept in lib/chooser/providers/native.lua calls refresh(true) itself,
        -- by its own documented contract, the moment push's own answer of true comes back to
        -- it, on top of the refresh push already ran. Harmless, a rebuild is idempotent and
        -- cheap for the launcher, left as is rather than reworked to save five milliseconds
        -- nothing can see, but the code should not be described as doing what the intercept
        -- path itself always adds a second pass of regardless of what this callable does.
        -- Promoting the row to recency still happens the ordinary way, one level up in
        -- host/launcher/init.lua's own intercept, which promotes anything this function hands
        -- back a callable for, so this file learns nothing new about recency to make VPN's row
        -- remember itself.
        rowIntercept = function(item)
          if item.kind == "special" and wiredRegistry.presentationFor then
            local presentation = wiredRegistry.presentationFor(item.name)
            if presentation then
              return function() stageModule:push(presentation) end
            end
          end
          if item.kind ~= "scope" or not queryScopeModule then return nil end
          local act = queryScopeModule:actFor(item)
          if act then return act end
          local query = queryScopeModule:redirectFor(item)
          if not query then return nil end
          return function() launcherModule:seedQuery(query) end
        end,
        -- The four names with no tool behind them. Reached only when the registry does not
        -- already run the name, which registration itself makes safe since one name cannot
        -- belong to both.
        special = {
          lock = function() hs.caffeinate.lockScreen() end,
          sleep = function() hs.caffeinate.systemSleep() end,
          searchSettings = function() if kin.focusSettingsSearch then kin.focusSettingsSearch() end end,
          -- Migrated onto host/stage, contract v3. This tool has no manifest and so no
          -- registration for stagePresent to look a presentation up by name for, root
          -- policy over a lib module needing none, so the table Stage:present wants is
          -- built right here instead, the one place that still reaches both overlay and
          -- stageModule. Reached the identical way it always was, this special row, since
          -- overlay was never part of wiredRegistry.presentationFor's own fast path and
          -- still is not, the whole reason rowIntercept's own presenting branch never
          -- touches it and this unconditional 0.1 second deferral still applies exactly as
          -- it always has.
          overlayDisplay = function()
            if not (overlay and stageModule) then return end
            stageModule:present({
              name = "overlayDisplay",
              rows = overlay.rows,
              onSelect = overlay.select,
              placeholder = "Overlay display",
              matcher = false,
            })
          end,
          aliasDirectory = function()
            if not queryScopeModule then return end
            local query = queryScopeModule:queryFor("aliasDirectory")
            if query then launcherModule:seedQuery(query) end
          end,
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

  local record = w.record
  record.text = w.report()

  -- The seam init.lua reads through self._composed, so Olm:start's own handle answers
  -- report, module and screen for real rather than the nil all three used to be, since
  -- w.record on its own carries only stages, problems and skipped, none of which init.lua
  -- promises to any caller. report is wire.lua's own report function, handed over rather
  -- than called a second time, since record.text above already answers the identical
  -- question once and a caller reaching for it again through the handle wants the same
  -- accounting rather than a fresh run. modules is loader.lua's own table, keyed by plugin
  -- identity, the exact table Olm:module indexes. screen is the overlay display resolver's
  -- own resolving function, handed over unpicked rather than called here, because the
  -- resolver watches for display changes and a screen taken now would go stale the moment
  -- one is attached or removed, so every caller must call it fresh at its own time, which
  -- Olm:screen is what actually does.
  record.report = w.report
  record.modules = modules
  record.screen = overlay.screen

  -- What this run actually decided, kept so something can INSPECT it afterwards rather than
  -- having to compose a second time to ask a question about the first. The test suite is the
  -- caller that made this necessary, since deriving a check from what a plugin declared means
  -- reading the plan and the manifests that produced the live config rather than reading the
  -- files again and hoping the two agree, which is exactly the self agreement that let a
  -- manifest naming a deleted capability pass for weeks.
  --
  -- All five are the tables themselves rather than copies. Nothing here should be written to,
  -- and a defensive copy would only make an inspector disagree with the config it is inspecting.
  record.plan = plan
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
  -- hint bar was actually handed can be read from outside rather than only inferred from this
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

  return record
end

return obj
