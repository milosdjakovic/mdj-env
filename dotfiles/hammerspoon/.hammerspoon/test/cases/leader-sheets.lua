-- Unit case for the two leader cheat sheets, phase four of the core split. The promise is that
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
-- validateActions and providedBindings, asked of a fresh copy of each plugin that declares
-- provides.actions or provides.bindings. No wiring step may bind a key any more, so a step whose
-- method starts with bind fails the case. Two inputs the root builds inline, which no unit case
-- can load, are restated small. A host's key calls its show through lib/hints.lua's own rule,
-- which the case calls rather than restates, and the launcher's lock and sleep rows call a
-- system function, here a stand in.
--
-- What the sheet shows is read off the real hosts. The Hyper sheet is configured with the list
-- lib/contributions.lua assembles from lib/hints.lua's sections, read off the keymap since phase
-- 2b of the keymap plan, and every supplier answering the cheatSheetSections set, then shown into
-- a recorder. The window sheet is configured with the keymap's rows on the window leader, stamped
-- the way the root stamps them, and shown the same way. A badge is spelled by a glyph function
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
-- window sheet reads the keymap's rows the open key is on that sheet too.
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
      runningApplications = function() return {} end,
    },
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
local contributions = load("lib/contributions.lua")
local leaders = load("lib/leaders.lua")

local realManifests = plugins.readAll({ spoonDir .. "plugins", spoonDir .. "host" }, nil)
local libNames = {}
for _, name in ipairs({ "windowleader", "hyperkey", "appfocus", "recency", "storage", "paste",
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
    libNames = libNames })
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

  -- What each plugin can run and the rows it provides, asked of a fresh copy of its module the
  -- way the root asks after wiring. The toggler is configured first, since its rows are built
  -- from its toggles in configure. The window manager and capture answer their actions with
  -- nothing configured.
  local modules, actions, refused, provided = {}, {}, {}, {}
  for _, directory in ipairs(plan.order) do
    local identity = plan.identity[directory] or directory
    local manifest = manifests[identity] or {}
    local provides = manifest.provides or {}
    if provides.actions ~= nil or provides.bindings ~= nil then
      local eff = plan.effective[directory] or {}
      local module
      if identity == "apptoggler" then
        module = load("plugins/apptoggler/init.lua")
        module:init()
        -- The person's roster and toggles, handed over by field name, win over the shipped
        -- defaults the way init.lua's shared table does for the running config.
        local given = (person.data or {}).apptoggler or {}
        local apps, shipped = given.apps or eff.apps, given.toggles or eff.toggles
        -- A toggle stating its own modifiers is a global combo, so one is added to prove it
        -- stays off every sheet.
        local toggles = {}
        for _, t in ipairs(shipped or {}) do toggles[#toggles + 1] = t end
        toggles[#toggles + 1] = { app = "Finder", key = "8", modifiers = { "ctrl", "alt" } }
        module:configure({ apps = apps, toggles = toggles, appFocus = {} })
      elseif identity == "capture" then
        module = load("plugins/capture/engine.lua")
      else
        module = load("plugins/" .. directory .. "/init.lua")
      end
      modules[identity] = module
      local answered, refusedNames, problems = registrar.validateActions(identity, manifest, module)
      actions[directory], refused[directory] = answered, refusedNames
      for _, pr in ipairs(problems) do result.bindProblems[#result.bindProblems + 1] = pr end
      local rows, rowProblems = registrar.providedBindings(identity, manifest, module)
      if provides.bindings ~= nil then provided[directory] = rows end
      for _, pr in ipairs(rowProblems) do result.bindProblems[#result.bindProblems + 1] = pr end
    end
  end

  local claimed = {}
  for _, entry in ipairs(registry.shortcuts()) do claimed[entry.name] = true end
  local keymap = keymapLib.build({
    plan = plan, roles = { app = "HYPER", window = "META" },
    shortcuts = registry.shortcuts(),
    actions = actions, refusedActions = refused, provided = provided,
    hostRun = function(directory)
      local identity = plan.identity[directory] or directory
      return hints.hostKeyBinding(plan.effective[directory], hostModule(directory), claimed[identity])
        and noop or nil
    end,
    specialRun = function(owner, name)
      if owner == (plan.identity.launcher or "launcher") and (name == "lock" or name == "sleep") then return noop end
      return nil
    end,
  })
  for _, pr in ipairs(keymap.problems) do result.bindProblems[#result.bindProblems + 1] = pr end
  for _, pr in ipairs(binderLib.bind(keymap.bound, {
    engines = { hyper = appLeader, meta = windowLeader },
    hotkey = function(mods, key) bindOn("global")(key, mods) end,
  })) do
    result.bindProblems[#result.bindProblems + 1] = pr
  end

  -- The Hyper sheet, configured the way step K configures it and shown into a recorder.
  local function recorder(into)
    return {
      glyphFor = mark,
      show = function(_, model)
        for _, section in ipairs(model.sections or {}) do
          for _, row in ipairs(section.rows or {}) do tally(into, tostring(row.badge):lower()) end
        end
      end,
      hide = noop,
    }
  end
  local hyperIdentity = plan.identity.hypercheatsheet or "hypercheatsheet"
  local own = hints.sections(keymap, plan, { leader = "hyper", registry = registry })
  local entries = contributions.sheetSections({
    host = hyperIdentity, role = "app", plan = plan, manifests = manifests, modules = modules,
    registrar = registrar, own = own,
    ownOrder = (plan.effective[hyperIdentity] or {}).cheatSheetOrder,
  })
  result.entries = entries
  local hyper = load("host/hypercheatsheet/init.lua")
  hyper:init()
  hyper:configure({ cheatSheet = recorder(result.sheet.app), sections = entries })
  hyper:show()
  result.hyper = hyper

  -- The window sheet, handed the keymap's rows on the window leader stamped the way the root
  -- stamps them, every predicate open.
  local code = 106
  local predicates = setmetatable({}, { __index = function() return function() return true end end })
  local windowSheet = load("host/windowcheatsheet/init.lua")
  windowSheet:init()
  windowSheet:configure({
    windowBindings = leaders.stampBindings(hints.leaderRows(keymap, "meta"), code),
    leaders = { [code] = "WINDOW" },
    cheatSheet = recorder(result.sheet.window),
    predicates = predicates,
  })
  windowSheet:show(code)
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
check("the toggle with its own modifiers was bound as a global combo", real.bound.global["8+alt+ctrl"])

-- The app toggles come first, as they always have, through the supplier the plugin declared.
check("the Hyper sheet's first entry is a supplier", type(real.entries[1]) == "function")
local drawn = real.hyper:_sections()
check("the app sections lead the sheet, running then dormant",
  drawn[1] ~= nil and drawn[1].title == "RUNNING" and drawn[2] ~= nil and drawn[2].title == "DORMANT")
check("the app sections keep the icon grid and the bound chords drop it",
  drawn[1].iconSize == nil and drawn[#drawn].iconSize == 0)
check("dormant apps are faded with their title kept bright",
  drawn[2].alpha == 0.55 and drawn[2].titleAlpha == 1.0)
check("the shipped Finder toggle is on the sheet", real.sheet.app["f"] == 1)

--------------------------------------------------------------------------------
-- The person's own configuration. Every run above has an empty user, which is a machine that
-- configured nothing, so one run is made with the real config/plugins.lua as the user, and the
-- app roster and toggles from config/apps.lua and config/keys.lua handed over the way init.lua
-- hands them, in its own entry in config/plugins.lua. Loaded by path from this checkout, since a
-- require inside the live Hammerspoon would return the running config's cached modules.
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
  -- config/plugins.lua pulls in config/keys.lua and config/apps.lua itself, since its apptoggler
  -- entry carries both lists as that plugin's data.
  local loaded, personPlugins = pcall(function()
    return dofile(configRoot .. "config/plugins.lua")
  end)
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
    local person = run(realManifests, { user = personPlugins, data = data })
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
for _, section in ipairs(withAction.hyper:_sections()) do
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
