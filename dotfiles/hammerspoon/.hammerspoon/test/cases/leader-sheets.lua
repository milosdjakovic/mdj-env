-- Unit case for the leader cheat sheets, phase four of the core split, one host since phase 4 of
-- the keymap plan. The promise is that
-- every key bound on a leader appears on that leader's sheet and that nothing appears there
-- which is not bound.
--
-- A plan is built over the real manifests, every plugin and every host, the way the composition
-- root builds one, with nothing switched off and no person overrides, so what is checked is
-- what the shipped declarations produce.
--
-- What is bound is found by running the code that binds, with a recorder standing in for each
-- leader engine. Every global key is bound by lib/binder.lua from the rows lib/keymap.lua builds,
-- the same two modules the root runs, over a real lib/registry.lua instance holding one
-- registration per manifest that declares a registry block. What a plugin can run comes from the
-- registrar's own
-- validateActions, asked of a fresh copy of each plugin that declares provides.actions, the app
-- toggler's and System Settings' configured first since theirs are built from data. A person's
-- keys reach the keymap from a config/keymap.lua shaped table, read by lib/keymap.lua's own
-- readConfig. No wiring step may bind a key any more, so a step whose
-- method starts with bind fails the case. Two inputs the root builds inline, which no unit case
-- can load, are restated small. A host's key calls its show through lib/hints.lua's own rule,
-- which the case calls rather than restates, and the launcher's lock and sleep rows call a
-- system function, here a stand in.
--
-- What the sheet shows is read off the real host. Since phase 4 of the keymap plan one host draws
-- every leader, so it is configured once with a record per leader, each holding that leader's
-- layout and the entries the host builds from lib/hints.lua's sheetRows over the keymap, in
-- blocks by each owner's cheatSheetOrder with the app toggler's apps split by whether they run,
-- and then shown for each leader into a recorder. A badge is spelled by a glyph function
-- that keeps the key and its modifiers readable, so a bound chord and a sheet row compare as one
-- plain string.
--
-- Then the defect phase four was asked to check, in the shape phase 2b of the keymap plan gave it.
-- A registry command on a leader was bound and dropped by the sheet, since the sheet looked its
-- key up through the plan. Commands are action descriptors now, so a probe bindings row puts one
-- of the clipboard's actions on the app leader, and it must reach both the binding and the sheet,
-- labelled with the descriptor's own description.
--
-- Last, a registry tool declaring the window leader with a leader shortcut. It was refused at
-- wiring while the registrar bound a tool's key on the app leader alone. The keymap binds every
-- row on its own leader, so such a key lands on the window leader and nowhere else, and since the
-- leader sheet reads the keymap's rows the open key is on that sheet too.
--
-- Under a plain lua interpreter with no Hammerspoon at all, a small stub stands in. Inside the
-- running Hammerspoon nothing here touches the live config, every module is a fresh copy loaded
-- with loadfile, and no key is handed to hs.hotkey, since the binder is given a recorder.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local spoonDir = caseDir .. "/../../Spoons/Olm.spoon/"

if hs == nil then
  local quiet = function()
    return setmetatable({}, { __index = function() return function() end end })
  end
  hs = {
    logger = { new = quiet },
    settings = { get = function() return nil end, set = function() end },
    fs = {
      dir = function(path)
        local p = io.popen('ls -a "' .. path .. '"')
        local names = {}
        for line in p:lines() do names[#names + 1] = line end
        p:close()
        local i = 0
        return function() i = i + 1 return names[i] end, nil
      end,
      attributes = function(path)
        local ok = os.execute('test -d "' .. path .. '"')
        if ok == true or ok == 0 then return { mode = "directory" } end
        local f = io.open(path, "r")
        if f then f:close() return { mode = "file" } end
        return nil
      end,
    },
    application = {
      pathForBundleID = function() return "/Applications/stub.app" end,
      nameForBundleID = function() return nil end,
      -- Finder, the one app every Mac always runs, so the sheet's running section has a row.
      runningApplications = function()
        return { { bundleID = function() return "com.apple.finder" end } }
      end,
    },
    timer = { secondsSinceEpoch = function() return os.time() end },
    image = { imageFromAppBundle = function() return "icon" end },
    hotkey = { bind = function() end },
    keycodes = { map = {} },
  }
end

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  elseif detail then
    print("FAIL " .. description .. ", " .. detail)
  else
    print("FAIL " .. description)
  end
end

local function load(rel)
  local chunk, err = loadfile(spoonDir .. rel)
  if not chunk then error("could not load " .. rel .. ", " .. tostring(err)) end
  return chunk()
end

local function noop() end

-- A chord as one readable string, the key lowered since the engines match a letter either way,
-- then the modifiers sorted. A toggle's own badge is its key as written, so a chord with no
-- modifiers spells as the bare lowered key and the two compare equal.
local function mark(key, mods)
  local m = {}
  for _, x in ipairs(mods or {}) do m[#m + 1] = x end
  table.sort(m)
  local k = tostring(key):lower()
  return #m > 0 and (k .. "+" .. table.concat(m, "+")) or k
end

local function sorted(set)
  local out = {}
  for k in pairs(set) do out[#out + 1] = k end
  table.sort(out)
  return out
end

-- Chords are counted, never collapsed, so two rows on one chord are two and not one. Every chord
-- that appears more often in one list than in the other, as one line a failure can print.
local function tally(into, key)
  into[key] = (into[key] or 0) + 1
end

local function missing(from, against)
  local out = {}
  for _, k in ipairs(sorted(from)) do
    if from[k] > (against[k] or 0) then
      out[#out + 1] = k .. " x" .. from[k] .. " against x" .. (against[k] or 0)
    end
  end
  return out
end

local plugins = load("lib/plugins.lua")
local resolver = load("lib/resolve.lua").new({ plugins = plugins, defaults = load("lib/defaults.lua"),
  surface = load("lib/surface.lua") })
local hints = load("lib/hints.lua")
local registrar = load("lib/registrar.lua")
local keymapLib = load("lib/keymap.lua")
local binderLib = load("lib/binder.lua")
local keycodesLib = load("lib/keycodes.lua")
local contributions = load("lib/contributions.lua")
local leaderLib = load("lib/leader.lua")

local realManifests = plugins.readAll({ spoonDir .. "plugins", spoonDir .. "host" }, nil)
local libNames = {}
for _, name in ipairs({ "leader", "appfocus", "recency", "storage", "paste",
  "cheatsheet", "registry", "glyphicon", "chordkey", "queryassoc", "ui" }) do
  libNames[name] = true
end


-- The module a host key rule asks whether it can be shown. compose.lua hands the rule the real
-- loaded module, so this loads the same file without calling it, and a file that cannot load
-- here is answered as a stand-in that can show, which is only what the rule asks of it.
local function hostModule(directory)
  for _, rel in ipairs({ "plugins/" .. directory .. "/init.lua", "host/" .. directory .. "/init.lua" }) do
    local chunk = loadfile(spoonDir .. rel)
    if chunk then
      local ok, module = pcall(chunk)
      if ok and type(module) == "table" then return module end
      return { show = function() end }
    end
  end
  return nil
end

-- One full pass, bound keys against sheet rows, over the manifests given. The person's own
-- configuration is the second argument, empty for every probe and the real files for the last.
local function run(manifests, person)
  person = person or {}
  local plan = resolver.plan({ manifests = manifests, user = person.user or {}, data = person.data,
    present = function() return true end,
    libNames = libNames, listKeys = keymapLib.listDefaults })
  local result = { plan = plan, bound = { app = {}, window = {}, global = {} },
    sheet = { app = {}, window = {} }, undriven = {}, problems = plan.problems, bindProblems = {} }

  local function bindOn(leader)
    return function(key, mods) tally(result.bound[leader], mark(key, mods)) end
  end
  local appLeader = { bind = function(_, key, _, mods) bindOn("app")(key, mods) end,
    isActive = function() return false end }
  local windowLeader = { bind = function(_, key, _, mods) bindOn("window")(key, mods) end }

  -- The registry, one registration per plugin in the plan that declares a registry block.
  local registry = load("lib/registry.lua").new({ apiVersion = 1, log = { w = noop, i = noop, e = noop } })
  for _, directory in ipairs(plan.order) do
    local identity = plan.identity[directory] or directory
    local block = (manifests[identity] or {}).registry
    if block then
      registry.register({ name = identity, apiVersion = 1, open = noop, shortcut = block.shortcut,
        row = block.row })
    end
  end
  local names = {}
  for _, entry in ipairs(registry.all()) do names[#names + 1] = entry.name end
  registry.activate(names)

  -- No wiring step binds a key. Olm binds every one from the keymap.
  for _, directory in ipairs(plan.order) do
    local identity = plan.identity[directory] or directory
    for _, step in ipairs((manifests[identity] or {}).wiring or {}) do
      if type(step.method) == "string" and step.method:match("^bind") then
        result.undriven[#result.undriven + 1] = identity .. "." .. step.method
      end
    end
  end

  -- What each plugin can run, asked of a fresh copy of its module the way the root asks after
  -- wiring. The toggler and System Settings are configured first, since their actions are built
  -- from their data in configure. The window manager and capture answer their actions with
  -- nothing configured.
  local modules, actions, refused = {}, {}, {}
  for _, directory in ipairs(plan.order) do
    local identity = plan.identity[directory] or directory
    local manifest = manifests[identity] or {}
    local provides = manifest.provides or {}
    if provides.actions ~= nil then
      local eff = plan.effective[directory] or {}
      local module
      if identity == "apptoggler" then
        module = load("plugins/apptoggler/init.lua")
        module:init()
        -- The person's catalog and variants, handed over as that plugin's data, win over the
        -- shipped defaults the way config/plugins.lua's entry does for the running config.
        local given = (person.data or {}).apptoggler or {}
        local apps = given.apps or eff.apps
        -- A variant bound as a plain combination, so one is added to prove it stays off every
        -- sheet, with its key in the keys below.
        local variants = {}
        for name, v in pairs(given.variants or eff.variants or {}) do variants[name] = v end
        variants.ProbePlaced = { app = "Finder", hides = true }
        module:configure({ apps = apps, variants = variants, appFocus = {} })
      elseif identity == "systemsettings" then
        module = load("plugins/systemsettings/init.lua")
        module:init()
        module:configure({ panes = eff.panes, appFocus = {} })
      elseif identity == "capture" then
        module = load("plugins/capture/engine.lua")
      elseif loadfile(spoonDir .. "plugins/" .. directory .. "/init.lua") then
        module = load("plugins/" .. directory .. "/init.lua")
      else
        -- A host answering actions of its own, the launcher's lock and sleep since phase 5 of the
        -- keymap plan, lives under host rather than plugins.
        module = load("host/" .. directory .. "/init.lua")
      end
      modules[identity] = module
      local answered, refusedNames, problems = registrar.validateActions(identity, manifest, module)
      actions[directory], refused[directory] = answered, refusedNames
      for _, pr in ipairs(problems) do result.bindProblems[#result.bindProblems + 1] = pr end
    end
  end

  -- The person's keys, read the way the root reads config/keymap.lua, plus the probe variant's
  -- plain combination when the app toggler is in the plan.
  local keys = {}
  for chord, id in pairs((person.keymap or {}).keys or {}) do keys[chord] = id end
  if manifests.apptoggler then keys["ctrl+alt+8"] = "apptoggler.ProbePlaced" end
  local personKeys = keymapLib.readConfig({ keys = keys },
    { catalog = { HYPER = true, META = true, SUPER = true }, roleWords = { "app", "window" } })
  for _, pr in ipairs(personKeys.problems) do result.bindProblems[#result.bindProblems + 1] = pr end

  local claimed = {}
  for _, entry in ipairs(registry.shortcuts()) do claimed[entry.name] = true end
  local keymap = keymapLib.build({
    plan = plan, roles = { app = "HYPER", window = "META" },
    shortcuts = registry.shortcuts(),
    actions = actions, refusedActions = refused, personKeys = personKeys.keys,
    hostRun = function(directory)
      local identity = plan.identity[directory] or directory
      return hints.hostKeyBinding(plan.effective[directory], hostModule(directory), claimed[identity])
        and noop or nil
    end,
    -- A cycle row runs the stage, which this case has none of, so every presentation's cycle is the
    -- no op a host's key is, and the Globe key may be bound bare as the root allows.
    cycleRun = function() return noop end,
    standalone = keycodesLib.standalone,
    specialRun = function(owner, name)
      if owner == (plan.identity.launcher or "launcher") and (name == "lock" or name == "sleep") then return noop end
      return nil
    end,
  })
  for _, pr in ipairs(keymap.problems) do result.bindProblems[#result.bindProblems + 1] = pr end
  for _, pr in ipairs(binderLib.bind(keymap.bound, {
    engines = { hyper = appLeader, meta = windowLeader },
    plain = { bind = function(_, key, _, mods) bindOn("global")(key, mods) end },
  })) do
    result.bindProblems[#result.bindProblems + 1] = pr
  end

  -- The one sheet host, configured the way step K configures it, one record per leader, and shown
  -- for each leader into a recorder that tallies what the renderer was handed. Every predicate is
  -- open, so a gated row is shown.
  local target = "app"
  local function recorder()
    return {
      glyphFor = mark,
      show = function(_, model)
        for _, section in ipairs(model.sections or {}) do
          for _, row in ipairs(section.rows or {}) do tally(result.sheet[target], tostring(row.badge):lower()) end
        end
      end,
      hide = noop,
    }
  end
  local predicates = setmetatable({}, { __index = function() return function() return true end end })
  local sheetIdentity = plan.identity.leadersheet or "leadersheet"
  local host = load("host/leadersheet/init.lua")
  host:init()
  local policies = {
    hyper = { role = "app", code = 101, policy = { sheet = true,
      sheetLayout = { title = "ACTIONS", columns = 4, colWidth = 215, iconSize = 32, gap = 10, groupGap = 20 } } },
    meta = { role = "window", code = 106, policy = { sheet = true,
      sheetLayout = { title = "WINDOW", columns = 2, colWidth = 250, badgeWidth = 44, gap = 12 } } },
  }
  -- The two answers the root hands the host, restated small since the root builds them inline.
  local directoryOf = {}
  for _, directory in ipairs(plan.order) do directoryOf[plan.identity[directory] or directory] = directory end
  local function orderOf(owner)
    local directory = directoryOf[owner]
    return directory and (plan.effective[directory] or {}).cheatSheetOrder or nil
  end
  local function appInfo(bundleID)
    local path = hs.application.pathForBundleID(bundleID)
    if not path or path == "" then return nil end
    return { name = hs.application.nameForBundleID(bundleID), icon = hs.image.imageFromAppBundle(bundleID) }
  end
  local sheets = {}
  for _, name in ipairs({ "hyper", "meta" }) do
    local spec = policies[name]
    local layout = leaderLib.sheetLayout(spec.policy)
    local rows = hints.sheetRows(keymap, plan, name, { registry = registry })
    sheets[#sheets + 1] = { name = name, keyCode = spec.code, layout = layout,
      entries = host.ownSections(rows, { glyphFor = mark, layout = layout, appInfo = appInfo,
        orderOf = orderOf, ownOrder = (plan.effective[sheetIdentity] or {}).cheatSheetOrder }) }
  end
  host:configure({ cheatSheet = recorder(), predicates = predicates, sheets = sheets })
  for _, name in ipairs({ "hyper", "meta" }) do
    target = policies[name].role
    host:show(policies[name].code)
  end
  result.host = host
  result.hyperCode = policies.hyper.code
  result.entries = host:model(policies.hyper.code).entries
  return result
end

--------------------------------------------------------------------------------
-- The shipped set.
--------------------------------------------------------------------------------

local real = run(realManifests)

check("the plan over the real manifests has no problems", #real.problems == 0,
  #real.problems > 0 and (tostring(real.problems[1].kind) .. " at " .. tostring(real.problems[1].where)) or nil)
check("no wiring step binds a key, the keymap binds every one", #real.undriven == 0,
  "binding steps, " .. table.concat(real.undriven, ", "))
check("the keymap and the binder report nothing over the shipped set", #real.bindProblems == 0,
  real.bindProblems[1] and (tostring(real.bindProblems[1].where) .. ", " .. tostring(real.bindProblems[1].why)) or nil)

for _, leader in ipairs({ "app", "window" }) do
  local bound, shown = real.bound[leader], real.sheet[leader]
  local n = #sorted(bound)
  check("the " .. leader .. " leader binds something", n > 0)
  local hidden = missing(bound, shown)
  check("every key bound on the " .. leader .. " leader is on its sheet", #hidden == 0,
    "bound and not shown, " .. table.concat(hidden, " "))
  local dead = missing(shown, bound)
  check("every key on the " .. leader .. " sheet is bound on that leader", #dead == 0,
    "shown and not bound, " .. table.concat(dead, " "))
end

for _, k in ipairs(sorted(real.bound.global)) do
  check("the global combo " .. k .. " is on no leader's sheet",
    not real.sheet.app[k] and not real.sheet.window[k])
end
check("the variant bound as a plain combination was bound as a global combo", real.bound.global["8+alt+ctrl"])

-- The app toggles come first, as they always have, a block of the toggler's own rows asked at
-- every show, since each row's group answers whether its app runs.
check("the Hyper sheet's first entry is a live block", type(real.entries[1]) == "function")
local drawn = real.host:sections(real.hyperCode)
check("the app section leads the sheet, the running Finder first",
  drawn[1] ~= nil and drawn[1].title == "RUNNING")
check("the app section keeps the icon grid and the bound chords drop it",
  drawn[1].iconSize == nil and drawn[#drawn].iconSize == 0)
check("the shipped Finder toggle is on the sheet", real.sheet.app["f"] == 1)

--------------------------------------------------------------------------------
-- The person's own configuration. Every run above has an empty user, which is a machine that
-- configured nothing, so one run is made with the real config/plugins.lua as the user, its
-- entries' data handed over as each plugin's own, and the real config/keymap.lua as the person's
-- keys. Loaded by path from this checkout, since a require inside the live Hammerspoon would
-- return the running config's cached modules.
--------------------------------------------------------------------------------

do
  local configRoot = caseDir .. "/../../"
  -- The units run inside the live Hammerspoon, whose own config is already in package.loaded
  -- under the same config.* names. A plain require would hand back that cached copy instead of
  -- this checkout's files, so every config.* entry is set aside, the files are loaded from this
  -- checkout by path, and the cache is put back exactly as it was afterwards.
  local savedPath = package.path
  local setAside = {}
  for name, mod in pairs(package.loaded) do
    if type(name) == "string" and name:match("^config%.") then
      setAside[name] = mod
      package.loaded[name] = nil
    end
  end
  package.path = configRoot .. "?.lua;" .. configRoot .. "?/init.lua;" .. package.path
  -- config/plugins.lua pulls in config/apps.lua itself, since its apptoggler entry carries the
  -- catalog as that plugin's data.
  local loaded, personPlugins = pcall(function()
    return dofile(configRoot .. "config/plugins.lua")
  end)
  local keymapLoaded, personKeymap = pcall(dofile, configRoot .. "config/keymap.lua")
  package.path = savedPath
  for name in pairs(package.loaded) do
    if type(name) == "string" and name:match("^config%.") then package.loaded[name] = nil end
  end
  for name, mod in pairs(setAside) do package.loaded[name] = mod end
  check("the person's config/plugins.lua and the files it points at load", loaded,
    not loaded and tostring(personPlugins) or nil)
  if loaded then
    local data = {}
    for name, entry in pairs(personPlugins) do
      if type(entry) == "table" and entry.data then data[name] = entry.data end
    end
    check("the person's config/keymap.lua loads", keymapLoaded, not keymapLoaded and tostring(personKeymap) or nil)
    local person = run(realManifests, { user = personPlugins, data = data, keymap = keymapLoaded and personKeymap or nil })
    check("with the person's config the plan has no problems", #person.problems == 0,
      #person.problems > 0 and (tostring(person.problems[1].kind) .. " at " .. tostring(person.problems[1].where)) or nil)
    for _, leader in ipairs({ "app", "window" }) do
      local hidden = missing(person.bound[leader], person.sheet[leader])
      check("with the person's config every key bound on the " .. leader .. " leader is on its sheet",
        #hidden == 0, "bound and not shown, " .. table.concat(hidden, " "))
      local dead = missing(person.sheet[leader], person.bound[leader])
      check("with the person's config every key on the " .. leader .. " sheet is bound there",
        #dead == 0, "shown and not bound, " .. table.concat(dead, " "))
    end
    check("the person's toggles reach the app sheet", person.sheet.app["b"] == 1 and person.sheet.app["`"] == 1)
    check("the person's placed terminal toggle is a global combo on no sheet",
      person.bound.global["`+alt"] == 1 and not person.sheet.app["`+alt"])
    check("Hyper and comma is bound on the app leader and on its sheet",
      person.bound.app[","] == 1 and person.sheet.app[","] == 1)
    local personDrawn = person.host:sections(person.hyperCode)
    check("with the person's apps the sheet splits running then dormant",
      personDrawn[1] ~= nil and personDrawn[1].title == "RUNNING" and personDrawn[2] ~= nil
        and personDrawn[2].title == "DORMANT")
    check("dormant apps are faded with their title kept bright",
      personDrawn[2] ~= nil and personDrawn[2].alpha == 0.55 and personDrawn[2].titleAlpha == 1.0)
  end
end

--------------------------------------------------------------------------------
-- The app toggler switched off. The sheet has no app section and nothing else changes.
--------------------------------------------------------------------------------

local without = {}
for identity, m in pairs(realManifests) do
  if identity ~= "apptoggler" then without[identity] = m end
end
local off = run(without)
check("without the app toggler the sheet has no app section",
  #off.entries == 1 and type(off.entries[1]) == "table")
check("without the app toggler the sheet still lists every other bound key",
  #missing(off.bound.app, off.sheet.app) == 0 and #missing(off.sheet.app, off.bound.app) == 0)
check("without the app toggler Finder's key is neither bound nor shown",
  not off.bound.app["f"] and not off.sheet.app["f"])

--------------------------------------------------------------------------------
-- An action on a leader, the case phase four was asked to check, once as a registry command and
-- since phase 2b as a bindings row naming one of the clipboard's action descriptors.
--------------------------------------------------------------------------------

local probe = {}
for identity, m in pairs(realManifests) do probe[identity] = m end
local clipboard = {}
for k, v in pairs(realManifests.clipboard) do clipboard[k] = v end
local clipDefaults = {}
for k, v in pairs(realManifests.clipboard.defaults) do clipDefaults[k] = v end
local clipBindings = {}
for _, b in ipairs(realManifests.clipboard.defaults.bindings) do clipBindings[#clipBindings + 1] = b end
clipBindings[#clipBindings + 1] = { action = "manageHistory", key = "9" }
clipDefaults.bindings = clipBindings
clipboard.defaults = clipDefaults
probe.clipboard = clipboard

local withAction = run(probe)
check("an action bound on the leader is bound there", withAction.bound.app["9"] == 1)
check("an action bound on the leader is on that leader's sheet", withAction.sheet.app["9"] == 1)
local labelled = false
for _, section in ipairs(withAction.host:sections(withAction.hyperCode)) do
  for _, row in ipairs(section.rows or {}) do
    if row.badge == "9" and row.label == "Manage clipboard history" then labelled = true end
  end
end
check("the action's sheet row wears its descriptor's description", labelled)
check("the action stays off the window sheet", not withAction.sheet.window["9"])

--------------------------------------------------------------------------------
-- A registry tool declaring the window leader with a leader shortcut. It was refused while the
-- registrar bound a tool's key on the app leader alone. The keymap row for its open key names
-- the window leader, and the binder binds it there. No shipped tool does this, so a copy of one
-- leader tool is moved to the window leader.
--------------------------------------------------------------------------------

local moved = {}
for identity, m in pairs(realManifests) do moved[identity] = m end
local caffeinate = {}
for k, v in pairs(realManifests.caffeinate) do caffeinate[k] = v end
local caffeinateDefaults = {}
for k, v in pairs(realManifests.caffeinate.defaults) do caffeinateDefaults[k] = v end
caffeinateDefaults.leader = "window"
caffeinate.defaults = caffeinateDefaults
moved.caffeinate = caffeinate
local movedKey
for _, b in ipairs(caffeinateDefaults.bindings or {}) do
  if b.action == "open" then movedKey = mark(b.key, b.mods) end
end

local onWindow = run(moved)
check("a registry tool on the window leader is bound without a problem", #onWindow.bindProblems == 0,
  onWindow.bindProblems[1] and tostring(onWindow.bindProblems[1].why) or nil)
check("its open key is bound on the window leader", onWindow.bound.window[movedKey] == 1)
check("and not on the app leader", not onWindow.bound.app[movedKey])
check("and not on the Hyper sheet", not onWindow.sheet.app[movedKey])
-- The window sheet reads the keymap's rows on its leader since phase 2b, so the gap this line used
-- to state is closed and a tool's open key moved there is listed.
check("the window sheet lists it, its rows are the keymap's", onWindow.sheet.window[movedKey] == 1)
check("with the tool moved every key still matches its sheet on both leaders",
  #missing(onWindow.bound.app, onWindow.sheet.app) == 0 and #missing(onWindow.sheet.app, onWindow.bound.app) == 0
    and #missing(onWindow.bound.window, onWindow.sheet.window) == 0
    and #missing(onWindow.sheet.window, onWindow.bound.window) == 0)
check("the same tool on the app leader is bound and shown", real.bound.app[movedKey] == 1
  and real.sheet.app[movedKey] == 1)
