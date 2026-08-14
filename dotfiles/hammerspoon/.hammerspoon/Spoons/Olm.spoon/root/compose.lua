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
-- anything a plugin set could answer for itself. The four modules under host are the one
-- exception, and it is a considered one rather than an oversight. They are Olm's own fixed
-- apparatus, shipped with the spoon itself rather than installed per person the way a
-- plugin is, so naming ActionPanel, HyperCheatSheet, Launcher, or QueryScope here is not the
-- leak naming a swappable plugin would be. Every such seam below is commented as one and
-- says why, and nowhere else in this file may a plugin's own identity appear as a literal.

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
local registryLib = load("lib/registry.lua")
local glyphIconLib = load("lib/glyphicon.lua")
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
-- The auto reload ignore list ships with the display profiles store path baked in, not
-- because this file knows a plugin called displayprofiles exists, but because that plugin's
-- JSON store is part of what Olm itself ships and watches, the same way the shared chord
-- timing or the shared cheat sheet padding is. A person adding their own runtime data file
-- under the watched tree extends this list from their own configuration, this default only
-- covers what Olm's own bundled apparatus already writes there.
local SHIPPED_POLICY = {
  chord = { holdDelay = 0.6, tapThreshold = 0.2, passthrough = true },
  hyperTrigger = { kind = "leader" },
  storage = { cacheRoot = "~/Library/Caches/Hammerspoon Olm", olmRoot = "~/.olm" },
  surface = {},
  chooserTheme = {},
  cheatSheet = {},
  matcher = "fuzzy",
  autoReload = { ignore = { "display%-profiles%.json$" } },

  -- The alias directory is the one scope Olm itself owns rather than any plugin, a list of
  -- every other scope, so its own presentation has nowhere else to be declared and ships from
  -- here. The retired root read these three off its own keys catalog under the same name,
  -- which made a scope Olm provides look like something the person had to describe. A title is
  -- not optional decoration either, QueryScope refuses a scope that has none, so leaving it
  -- unset dropped the directory silently on every run with one warning line among many.
  aliasDirectory = { title = "Aliases", glyph = "🏷️", aliases = { "?" } },
}

-- Every command kind tool the whole set declares, asked for in ONE login shell, once, and the
-- answers kept. Two things forced this shape and both are worth stating.
--
-- The login shell is not optional. Hammerspoon's own environment carries a bare PATH holding
-- none of the places a package manager installs into, so a probe without it reports every
-- Homebrew tool absent. That is invisible for an optional tool, which simply degrades, and
-- fatal for a required one, which blocks its whole plugin from planning with nothing said.
-- tmux is the case that exposed it, and convert had been blocked the same way over qalc for as
-- long as this file has existed, silently, on a machine where qalc is installed.
--
-- And it is one call rather than one per tool because a login shell costs tens of milliseconds
-- and the plan runs twice, so asking separately turned startup into seconds of shelling out.
-- lib/deps.lua's own probe batches for exactly this reason and says so.
local function probeCommands(manifests)
  local names, seen = {}, {}
  for _, manifest in pairs(manifests or {}) do
    for _, tool in ipairs(((manifest or {}).needs or {}).tools or {}) do
      if tool.kind == "path" and not seen[tool.name] then
        seen[tool.name] = true
        names[#names + 1] = tool.name
      end
    end
  end
  local found = {}
  if #names == 0 then return found end
  -- The names were written by hand in a manifest rather than typed by anyone at runtime, and
  -- the answers are mapped back by their last path segment, so no quoting is needed and none
  -- is used, which is the same reasoning lib/deps.lua's own probe records.
  local answer = hs.execute("command -v " .. table.concat(names, " "), true) or ""
  for line in answer:gmatch("[^\n]+") do
    -- Absolute paths only. A login shell also answers here with aliases and shell builtins,
    -- and neither is a thing that can be run as a command.
    if line:sub(1, 1) == "/" then
      local base = line:match("([^/]+)$")
      if base then found[base] = true end
    end
  end
  return found
end

-- resolve.plan's own existence question for one declared tool, answered directly from the
-- four probeable kinds the contract defines. This is not the door a plugin reaches through
-- for a resolved path at runtime, that stays lib/deps.lua's alone. It is the simpler yes or
-- no the plan needs before any plugin, and before lib/deps.lua itself, has been configured,
-- so it cannot be answered through a per consumer scope that does not exist yet.
local function toolPresent(tool, commands)
  local kind = tool.kind
  if kind == "path" then
    return (commands or {})[tool.name] == true
  elseif kind == "system" or kind == "manual" then
    return tool.locator ~= nil and hs.fs.attributes(tool.locator) ~= nil
  elseif kind == "app" then
    local path = tool.locator and hs.application.pathForBundleID(tool.locator)
    return path ~= nil and path ~= ""
  end
  -- A "package" kind proves presence by asking the package manager rather than by probing a
  -- path, which nothing at this layer can do generically. Treated as present so the plugin
  -- wires and finds out for itself, rather than blocked here on a question this file cannot
  -- answer honestly either way.
  return true
end

--------------------------------------------------------------------------------
-- run(olm, cfg), the one door into all of this
--------------------------------------------------------------------------------

function obj.run(olm, cfg)
  cfg = cfg or {}

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

  -- Forward declared and filled by steps D and E below. Every closure in this block that
  -- reaches through one of these two names is only ever CALLED much later, at the moment
  -- something actually shows on screen, well after both locals hold their real value, so
  -- capturing them now while they are still nil is safe and is the whole point, the same
  -- late binding the decorate hook already relies on.
  local modules
  local overlay

  load("lib/storage.lua").configure(policy.storage)

  -- Loaded and initialised here, but deliberately NOT configured or started until step C has
  -- read the manifests, because what it probes for is aggregated out of them. Everything
  -- between here and there only holds the atom, nothing asks it a question yet.
  local depsAtom = load("lib/deps.lua")
  depsAtom:init()

  local canvasPanel = load("lib/panel.lua")
  canvasPanel:init()
  canvasPanel.configure({ surface = policy.surface })
  canvasPanel.configure({ screen = function() return overlay and overlay.screen() end })

  local chooserAtom = load("lib/chooser/init.lua")
  chooserAtom:init()
  chooserAtom.configure({
    screen = function() return overlay and overlay.screen() end,
    matcher = chooserAtom.matchers and chooserAtom.matchers[policy.matcher],
    -- THE SEAM. ActionPanel is one of the four host modules this file is allowed to name.
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

  local cheatSheetAtom = load("lib/cheatsheet.lua")
  cheatSheetAtom:init()
  local cheatSheetOpts = { canvasPanel = canvasPanel, theme = policy.chooserTheme }
  for k, v in pairs(policy.cheatSheet or {}) do cheatSheetOpts[k] = v end
  cheatSheetAtom:configure(cheatSheetOpts)

  local chordKeyAtom = load("lib/chordkey.lua")
  chordKeyAtom:init()
  chordKeyAtom:configure(policy.chord)

  -- Loaded here, ahead of step H's own init and configure, purely so the libs table two
  -- sections down can name it as a lib capability. Existence checking in step F's plan runs
  -- before step H does, so a lib module a plugin may declare needs.lib against has to exist
  -- as a loaded module this early even though it is not actually configured until later.
  local hyperKeyAtom = load("lib/hyperkey.lua")

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
  -- One shell for every command the whole set names, before either planning pass asks
  -- about any of them, so the two passes share one answer and neither pays for it twice.
  local commandsPresent = probeCommands(manifests)
  local function presentTool(tool) return toolPresent(tool, commandsPresent) end

  depsAtom:configure({ declared = pluginsLib.declarations(manifests, "Olm") })
  depsAtom:start()
  -- The one shared scope every plugin earning the ambient deps grant is handed, unscoped by
  -- consumer, matching what services.perPlugin's own contract says it hands out, the same
  -- single adapter every plugin sharing it in the live root already reads today.
  local sharedDepsScope = depsAtom:scope("Olm")

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
  loaderLib.mirror(modules, globals)

  -- Every real lib module a plugin might name through needs.lib, for two different readers.
  -- step F's plan checks a declared name against this table for existence alone, and lib/
  -- wire.lua's own generic grant hands the same table's values straight to opts for whatever
  -- a plugin declared. recency is the one name where those two readers must disagree, since
  -- a shared instance handed out flat would merge every plugin's remembered ordering into
  -- one, so the module sits here for the existence check to find, and services.perPlugin
  -- below still hands each declaring plugin its own fresh instance through deps.data, which
  -- wins there because that channel is read last and unconditionally.
  local libs = {
    paste = load("lib/paste.lua"),
    cheatsheet = cheatSheetAtom,
    registry = registryLib,
    glyphicon = glyphIcon,
    chordkey = chordKeyAtom,
    hyperkey = hyperKeyAtom,
    recency = load("lib/recency.lua"),
  }

  ------------------------------------------------------------------------------
  -- STEP E. The overlay display resolver, and what the two screen closures in
  -- step B call through now that it exists.
  ------------------------------------------------------------------------------

  overlay = overlayDisplayLib.new({
    chooser = chooserAtom,
    canvasPanel = canvasPanel,
    theme = policy.chooserTheme,
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
      fannedData[name] = defaultsLib.merge(fannedData[name] or {}, fields)
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

  -- THE SEAM, Fact 1. WindowManager and WindowCheatSheet must dispatch and display the
  -- identical physical key, so this stamped table is built exactly once, right here, and
  -- the same local is handed to both consumers below rather than two calls that would only
  -- happen to agree today.
  local stampedWindowBindings = leadersLib.stampBindings(
    firstPass.effective.windowmanager and firstPass.effective.windowmanager.windowManagement,
    windowKeycode)

  local rootOwnedData = {
    keyremap = { activeNames = activeLeaderNames },
    windowmanager = { mapping = stampedWindowBindings },
    windowcheatsheet = { windowManagement = stampedWindowBindings },
  }

  local plan = resolver.plan({
    manifests = manifests,
    user = cfg,
    present = presentTool,
    libNames = libNames,
    modules = modules,
    libs = libs,
    data = servicesLib.merge(fannedData, rootOwnedData),
  })

  for _, p in ipairs(plan.problems or {}) do
    log.e("Olm compose, plan problem, " .. tostring(p.kind) .. " at " .. tostring(p.where) .. ", " .. tostring(p.why))
  end

  ------------------------------------------------------------------------------
  -- STEP I (computed here, before wiring, since stage 3 needs it as soon as it
  -- runs, well before stage 4 assembles the merged table).
  --
  -- Every predicate this file owns outright, collected once. plan.predicates already
  -- answers every surface gate, so nothing here may repeat one of those names, and
  -- lib/wire.lua reports it rather than silently letting one win if it ever happens.
  ------------------------------------------------------------------------------

  local ownPredicates = {}
  for _, module in pairs(modules) do
    if type(module) == "table" and type(module.predicates) == "table" then
      for name, fn in pairs(module.predicates) do ownPredicates[name] = fn end
    end
  end
  ownPredicates.multipleDisplays = function() return #hs.screen.allScreens() > 1 end
  ownPredicates.overlayDisplayOpen = function() return overlay.isShowing() == true end

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

  local contextOwners = hintsLib.contextOwners(plan, manifests)

  -- Whether a named context's surface is currently open, tried both calling conventions a
  -- surface's own isShowing might use, since no manifest field states which one a plugin
  -- picked and getting it wrong resolves to something that fails on arity rather than
  -- cleanly, the exact defect the first attempt shipped for three surfaces at once.
  local function isShowingFor(contextName)
    local owner = contextOwners[contextName]
    local module = owner and modules[owner]
    if not module or type(module.isShowing) ~= "function" then return false end
    local ok, answer = pcall(module.isShowing, module)
    if ok then return answer == true end
    local dotOk, dotAnswer = pcall(module.isShowing)
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
      -- THE SEAM. HyperCheatSheet is one of the four host modules this file may name.
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

  local hintsDeps = {
    predicates = ownPredicates,
    glyphFor = cheatSheetAtom.glyphFor,
    owners = contextOwners,
    canvasPanel = canvasPanel,
    theme = policy.chooserTheme,
    settings = policy,
    hideShortcuts = hideSharedOverlay,
    -- liveLabels is absent. The one live relabelling case that exists today, the launcher's
    -- Run reading as Open over an application row, is that plugin's own business, and this
    -- file has nowhere generic to reach it from without naming Launcher for a value lib/
    -- hints.lua itself is careful never to ask this file to name.
  }

  -- HyperCheatSheet and QueryScope both reset the whole of what configure gave them on
  -- every call rather than merging, so the base opts built here are reused verbatim for
  -- their post register second call in step K, instead of being recomputed and risking two
  -- slightly different tables answering for the same plugin in the same run.
  local hyperCheatSheetOpts = {
    apps = cfg.apps,
    toggles = cfg.appToggles,
    cheatSheet = cheatSheetAtom,
  }
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
  local actionKinds = hintsLib.actionKinds(plan)
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

  local wireData = servicesLib.merge(perPluginData, rootOwnedData, {
    hypercheatsheet = hyperCheatSheetOpts,
    queryscope = queryScopeOpts,
    actionpanel = actionPanelOpts,
  })

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

  local wiredRegistry = registryLib.new({ apiVersion = REGISTRY_API_VERSION, log = log })

  -- What a scope calls once a late answer lands, so its rows are drawn again rather than the
  -- list staying as it was when nothing had arrived yet. Two scopes need it, the relay list
  -- and the browser tab list, both of which read from something slower than a keystroke.
  --
  -- It is a closure rather than a value because the surface it repaints is the launcher, one
  -- of the four host modules this file is allowed to name, and it is looked up INSIDE the
  -- closure rather than out here because this runs long before the loader has filled that
  -- table. Supplying it from here is what keeps the plugins themselves from ever learning
  -- the launcher exists, each one only takes a function and calls it when its own fetch
  -- finishes, which is the whole reason that logic moved out of the retired root's own
  -- scope tables and onto the plugins.
  local function redrawSurface()
    local host = modules[plan.identity.launcher or "launcher"]
    if host and host.refresh then host:refresh() end
  end

  local function describeForRegistry(name, planArg)
    return registrarLib.describe(name, planArg, modules, manifests, registryMeta,
      REGISTRY_API_VERSION, { merge = defaultsLib.merge, redraw = redrawSurface })
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
  local bindOneInContext = navLib.bindOne(repeatableActions)

  -- A dot called control surface for every plugin this plan actually built a context for,
  -- wrapping whichever calling convention that plugin's own module happens to use. lib/
  -- nav.lua calls every surface method with a bare dot, by design, so a colon style module
  -- handed over unwrapped would fail on arity the moment its own isShowing or selectNext
  -- ran, the exact defect three real surfaces shipped with once already. Ordered by
  -- plan.order, this file's own answer to which surface wins if two are ever open at once,
  -- since nothing here proves that can never happen and something has to decide.
  local function surfaceAdapterFor(module)
    return setmetatable({}, {
      __index = function(_, methodName)
        local fn = module[methodName]
        if type(fn) ~= "function" then return nil end
        return function(...)
          local ok, result = pcall(fn, module, ...)
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
      local module = modules[plan.identity[name] or name]
      if module then surfaceAdapters[#surfaceAdapters + 1] = surfaceAdapterFor(module) end
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
    opts.sections = hintsLib.sections(wiredRegistry, plan, {})
    hyperCheatSheetModule:configure(opts)
  end

  local queryScopeModule = modules[plan.identity.queryscope or "queryscope"]
  if queryScopeModule then
    -- Membership from the plan's own set answer, which is the question this host declared
    -- rather than a roster anyone here keeps, and the scope itself from the live registry, so
    -- a tool that is present but switched off keeps no word.
    local scopeNames = (plan.sets[plan.identity.queryscope or "queryscope"] or {}).scopes
      or (plan.sets.queryscope or {}).scopes
    local scopes = registrarLib.scopeSpec(plan, wiredRegistry, scopeNames, registryMeta) or {}

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

    queryScopeModule:configure({ matcher = queryScopeOpts.matcher, scopes = scopes })
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

    launcherModule:configure({
      chooser = ambientServices.chooser,
      theme = ambientServices.theme,
      placeholder = ambientServices.placeholder,
      toggles = sharedData and sharedData.toggles,
      apps = sharedData and sharedData.apps,
      predicates = ownPredicates,
      shortcutPanel = perPluginData.launcher and perPluginData.launcher.shortcutPanel,
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
        if not aliases or #aliases == 0 then return "" end
        return " (" .. table.concat(aliases, ", ") .. ")"
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
        rowIntercept = function(item)
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
          overlayDisplay = function() if overlay and overlay.show then overlay.show() end end,
          aliasDirectory = function()
            if not queryScopeModule then return end
            local query = queryScopeModule:queryFor("aliasDirectory")
            if query then launcherModule:seedQuery(query) end
          end,
        },
      },
    })
  end

  ------------------------------------------------------------------------------
  -- STEP L. The tail.
  ------------------------------------------------------------------------------

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

  return record
end

return obj
