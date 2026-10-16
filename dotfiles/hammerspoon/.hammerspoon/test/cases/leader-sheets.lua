-- Unit case for the two leader cheat sheets, phase four of the core split. The promise is that
-- every key bound on a leader appears on that leader's sheet and that nothing appears there
-- which is not bound.
--
-- A plan is built over the real manifests, every plugin and every host, the way the composition
-- root builds one, with nothing switched off and no person overrides, so what is checked is
-- what the shipped declarations produce.
--
-- What is bound is found by running the code that binds, with a recorder standing in for each
-- leader engine. The registry's leader keys go through lib/registrar.lua's own bind, over a real
-- lib/registry.lua instance holding one registration per manifest that declares a registry
-- block, and its commands get their keys through the registrar's own command lookup. A plugin
-- that binds its own keys in a wiring step is driven through that step on a fresh copy of its
-- module. Every wiring step whose method starts with bind must be one this case drives, so a
-- plugin that starts binding keys a new way fails here until the case learns it. Two rules live
-- inline in root/compose.lua, which no unit case can load. A host that declares a key and a
-- leader and registers nothing binds that key through lib/hints.lua's own rule, which the case
-- calls rather than restates, and the launcher's lock and sleep rows bind theirs, restated.
--
-- What the sheet shows is read off the real hosts. The Hyper sheet is configured with the list
-- lib/contributions.lua assembles from lib/hints.lua's sections and every supplier answering the
-- cheatSheetSections set, then shown into a recorder. The window sheet is configured with the
-- stamped list the root hands it and shown the same way. A badge is spelled by a glyph function
-- that keeps the key and its modifiers readable, so a bound chord and a sheet row compare as one
-- plain string.
--
-- Then the defect phase four was asked to check. A command declared on a leader, a registry
-- command with a key and shortcut leader, was bound by the registrar and dropped by the sheet,
-- since the sheet looked its key up through the plan and a command belongs to no directory. No
-- shipped command sits on a leader today, the clipboard's two are global, so a probe command is
-- added to a copy of one manifest and must reach both the binding and the sheet.
--
-- Last, a registry tool declaring the window leader with a leader shortcut. The registrar binds
-- a tool's open key only on the app leader's engine, so such a key used to land on Hyper and on
-- neither sheet. It is refused at wiring now, and a copy of one shipped tool moved to the window
-- leader must be refused by name, bound nowhere and shown nowhere.
--
-- Under a plain lua interpreter with no Hammerspoon at all, a small stub stands in. Inside the
-- running Hammerspoon nothing here touches the live config, every module is a fresh copy loaded
-- with loadfile, and the one global binding call a toggle with its own modifiers would make is
-- swapped for a recorder for the length of that one call.

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
local contributions = load("lib/contributions.lua")
local leaders = load("lib/leaders.lua")

local realManifests = plugins.readAll({ spoonDir .. "plugins", spoonDir .. "host" }, nil)
local libNames = {}
for _, name in ipairs({ "windowleader", "hyperkey", "appfocus", "recency", "storage", "paste",
  "cheatsheet", "registry", "glyphicon", "chordkey", "queryassoc", "ui" }) do
  libNames[name] = true
end

-- The binding steps this case knows how to drive, by identity and method. Anything else whose
-- method starts with bind fails the case, since its keys would go unchecked.
local DRIVEN = {
  ["apptoggler.bindHotkeys"] = true,
  ["capture.bindHotkeys"] = true,
  ["windowmanager.bindToLeader"] = true,
}

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
    sheet = { app = {}, window = {} }, undriven = {}, problems = plan.problems, refused = {} }

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
      local commands = nil
      if block.commands then
        commands = {}
        for name, spec in pairs(block.commands) do
          commands[name] = { fn = noop, shortcut = spec.shortcut }
        end
      end
      registry.register({ name = identity, apiVersion = 1, open = noop, shortcut = block.shortcut,
        commands = commands })
    end
  end
  local names = {}
  for _, entry in ipairs(registry.all()) do names[#names + 1] = entry.name end
  registry.activate(names)

  local function commandKey(name) return registrar.commandKey(manifests, {}, name) end
  local claimed = {}
  for _, entry in ipairs(registry.shortcuts()) do
    claimed[entry.name] = true
    -- A refusal raises, which the wiring stage turns into a problem line, so it is caught and
    -- kept here the way that stage keeps it.
    local ok, err = pcall(registrar.bind, entry, plan, {
      log = noop,
      bindLeader = bindOn("app"),
      leaderRole = "app",
      bindGlobal = function(mods, key) bindOn("global")(key, mods) end,
      rootKey = commandKey,
    })
    if not ok then result.refused[entry.name] = tostring(err) end
  end

  -- The two rules root/compose.lua binds by itself. A host's own key goes through the same
  -- lib/hints.lua rule the root calls, so nothing is restated, and the launcher's lock and sleep
  -- rows bind theirs, the only special rows the root has a system call for.
  for _, directory in ipairs(plan.order) do
    local identity = plan.identity[directory] or directory
    local eff = plan.effective[directory] or {}
    local role, key, mods = hints.hostKeyBinding(eff, hostModule(directory), claimed[identity])
    if role == "app" then bindOn("app")(key, mods) end
  end
  local systemCalls = { lock = true, sleep = true }
  for _, row in ipairs((plan.effective[plan.identity.launcher or "launcher"] or {}).specialRows or {}) do
    if systemCalls[row.name] and row.key then bindOn("app")(row.key) end
  end

  -- Every wiring step that binds keys, driven on a fresh copy of its plugin.
  local modules = {}
  for _, directory in ipairs(plan.order) do
    local identity = plan.identity[directory] or directory
    for _, step in ipairs((manifests[identity] or {}).wiring or {}) do
      if type(step.method) == "string" and step.method:match("^bind") then
        local tag = identity .. "." .. step.method
        local eff = plan.effective[directory] or {}
        if not DRIVEN[tag] then
          result.undriven[#result.undriven + 1] = tag
        elseif identity == "apptoggler" then
          local toggler = load("plugins/apptoggler/init.lua")
          toggler:init()
          -- The person's roster and toggles, handed over by field name, win over the shipped
          -- defaults the way init.lua's shared table does for the running config.
          local given = (person.data or {}).apptoggler or {}
          local apps, shipped = given.apps or eff.apps, given.toggles or eff.toggles
          toggler:configure({ apps = apps, hyperKey = appLeader, appFocus = {} })
          -- A toggle stating its own modifiers is a global combo, so one is added to prove it
          -- stays off every sheet. The global binding call is swapped for a recorder for this
          -- one call only, so the live config is never handed a hotkey.
          local toggles = {}
          for _, t in ipairs(shipped or {}) do toggles[#toggles + 1] = t end
          toggles[#toggles + 1] = { app = "Finder", key = "8", modifiers = { "ctrl", "alt" } }
          local realHotkey = hs.hotkey
          hs.hotkey = { bind = function(mods, key) bindOn("global")(key, mods) end }
          local ok, err = pcall(toggler.bindHotkeys, toggler, toggles)
          hs.hotkey = realHotkey
          if not ok then error(err) end
          modules[identity] = toggler
        elseif identity == "capture" then
          local capture = load("plugins/capture/engine.lua")
          capture._hyperKey = appLeader
          capture:bindHotkeys(eff.bindings)
        elseif identity == "windowmanager" then
          local windows = load("plugins/windowmanager/init.lua")
          windows:bindToLeader(windowLeader, eff.bindings)
        end
      end
    end
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
  local own = hints.sections(registry, plan, { leader = "app", commandKey = commandKey })
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
  result.ownWithout = hints.sections(registry, plan, { leader = "app" })

  -- The window sheet, handed the stamped list the root builds, every predicate open.
  local code = 106
  local predicates = setmetatable({}, { __index = function() return function() return true end end })
  local windowSheet = load("host/windowcheatsheet/init.lua")
  windowSheet:init()
  windowSheet:configure({
    windowBindings = leaders.stampBindings(hints.leaderBindings(plan, "window"), code),
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
check("every wiring step that binds keys is one this case drives", #real.undriven == 0,
  "not driven, " .. table.concat(real.undriven, ", "))

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
-- A command on a leader, the case phase four was asked to check.
--------------------------------------------------------------------------------

local probe = {}
for identity, m in pairs(realManifests) do probe[identity] = m end
local clipboard = {}
for k, v in pairs(realManifests.clipboard) do clipboard[k] = v end
local reg = {}
for k, v in pairs(realManifests.clipboard.registry) do reg[k] = v end
local commands = {}
for k, v in pairs(realManifests.clipboard.registry.commands) do commands[k] = v end
commands.probeLeaderCommand = { fn = "open", key = "9", shortcut = "leader",
  row = { description = "Probe command" } }
reg.commands = commands
clipboard.registry = reg
probe.clipboard = clipboard

local withCommand = run(probe)
check("a command declared on the leader is bound there", withCommand.bound.app["9"] == 1)
check("a command declared on the leader is on that leader's sheet", withCommand.sheet.app["9"] == 1)
local labelled = false
for _, section in ipairs(withCommand.hyper:_sections()) do
  for _, row in ipairs(section.rows or {}) do
    if row.badge == "9" and row.label == "Probe command" then labelled = true end
  end
end
check("the command's row wears the description its launcher row declares", labelled)
local before = false
for _, section in ipairs(withCommand.ownWithout) do
  for _, b in ipairs(section.bindings or {}) do
    if tostring(b.key) == "9" then before = true end
  end
end
check("without the command lookup the sheet drops it, the defect this case guards", not before)
check("the command stays off the window sheet", not withCommand.sheet.window["9"])

--------------------------------------------------------------------------------
-- A registry tool declaring the window leader with a leader shortcut. The registrar binds a
-- tool's open key on the app leader's engine alone, and each sheet lists only its own leader's
-- tools, so such a key was bound on Hyper and listed nowhere. It is refused at wiring now with a
-- problem line naming the tool. No shipped tool does this, so a copy of one leader tool is moved
-- to the window leader.
--------------------------------------------------------------------------------

check("no shipped registry tool is refused", next(real.refused) == nil,
  next(real.refused) and (next(real.refused) .. ", " .. real.refused[next(real.refused)]) or nil)

local moved = {}
for identity, m in pairs(realManifests) do moved[identity] = m end
local caffeinate = {}
for k, v in pairs(realManifests.caffeinate) do caffeinate[k] = v end
local caffeinateDefaults = {}
for k, v in pairs(realManifests.caffeinate.defaults) do caffeinateDefaults[k] = v end
caffeinateDefaults.leader = "window"
caffeinate.defaults = caffeinateDefaults
moved.caffeinate = caffeinate
local movedKey = mark(caffeinateDefaults.key)

local onWindow = run(moved)
local refusal = onWindow.refused.caffeinate
check("a registry tool on the window leader is refused at wiring", refusal ~= nil)
check("the refusal names the tool and the leader it asked for",
  refusal ~= nil and refusal:find("'caffeinate'", 1, true) ~= nil and refusal:find("leader = 'window'", 1, true) ~= nil,
  refusal)
check("the refused key is bound on neither leader",
  not onWindow.bound.app[movedKey] and not onWindow.bound.window[movedKey])
check("the refused key is on neither sheet",
  not onWindow.sheet.app[movedKey] and not onWindow.sheet.window[movedKey])
check("with the tool refused every other key still matches its sheet on both leaders",
  #missing(onWindow.bound.app, onWindow.sheet.app) == 0 and #missing(onWindow.sheet.app, onWindow.bound.app) == 0
    and #missing(onWindow.bound.window, onWindow.sheet.window) == 0
    and #missing(onWindow.sheet.window, onWindow.bound.window) == 0)
check("the same tool on the app leader is bound and shown", real.bound.app[movedKey] == 1
  and real.sheet.app[movedKey] == 1)
