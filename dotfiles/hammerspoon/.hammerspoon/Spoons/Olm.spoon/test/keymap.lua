-- The keymap read model in plain Lua.
--
-- lib/keymap.lua is pure, it takes the plan, the roles and the keycode table as inputs, so it
-- needs no Hammerspoon and no stub. These cases drive it with small hand written plans and pin
-- the collision rule, how a person's row displaces a default, and the spelling it normalises to.
-- The person's own keymap file, config/keymap.lua, has its cases in test/keymap-person.lua. The proof that it
-- holds every live chord is a different check, see keys.sh and its offline mode.
--
-- Run it.
--   lua test/keymap.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local keymap = assert(loadfile(here .. "../lib/keymap.lua"))()

local failures, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %s, wanted %s, got %s", what, tostring(want), tostring(got)))
  end
end

local ROLES = { app = "HYPER", window = "META" }

-- A fake of Hammerspoon's keycode table, name to code and code to name in one table, with the
-- two spellings of the return key sharing a code the way the real table does.
local KEYCODES = { a = 0, s = 1, ["return"] = 36, enter = 36, [0] = "a", [1] = "s", [36] = "return" }

local function build(plan, extra)
  local inputs = { plan = plan, roles = ROLES, keycodes = KEYCODES }
  for k, v in pairs(extra or {}) do inputs[k] = v end
  return keymap.build(inputs)
end

local function defaultPlan(effective, provenance)
  return { effective = effective, provenance = provenance or {}, identity = {}, contexts = {} }
end

-- Two shipped defaults on one chord are reported, naming both owners and both actions.
do
  local result = build(defaultPlan({
    one = { leader = "app", bindings = { { action = "first", key = "a" } } },
    two = { leader = "app", bindings = { { action = "second", key = "A" } } },
  }))
  eq(#result.problems, 1, "two defaults on one chord collide once")
  local why = result.problems[1] and result.problems[1].why or ""
  eq(why:find("'one' action 'first'", 1, true) ~= nil, true, "the problem names the first owner and action")
  eq(why:find("'two' action 'second'", 1, true) ~= nil, true, "the problem names the second owner and action")
  eq(why:find("hyper+a", 1, true) ~= nil, true, "the problem names the chord")
  eq(why:find("global", 1, true) ~= nil, true, "the problem names the layer")
end

-- A list's key and a global key on one chord share it on purpose, since the layers never meet.
do
  local plan = defaultPlan({ one = { leader = "app", bindings = { { action = "open", key = "s" } } } })
  plan.contexts = { list = { when = "listOpen", priority = 100, bindings = { { action = "close", key = "s" } } } }
  local result = build(plan)
  eq(#result.problems, 0, "a list key and a global key on one chord do not collide")
  eq(#result.rows, 2, "both rows are kept")
end

-- A catch all and an exact modifier row on one key are different slots, and so is a catch all
-- against a row that states an empty list.
do
  local result = build(defaultPlan({
    one = { leader = "app", bindings = {
      { action = "any", key = "s" },
      { action = "exact", key = "s", mods = { "shift" } },
      { action = "none", key = "s", mods = {} },
    } },
  }))
  eq(#result.problems, 0, "a catch all, an exact row and an empty list row do not collide")
  local flags = {}
  for _, row in ipairs(result.rows) do flags[row.action] = row.anyMods end
  eq(flags.any, true, "a row with no mods field is a catch all")
  eq(flags.none, false, "a row with an empty mods list is not")
end

-- A person's own row on a slot a default holds wins it, and the default is dropped with one
-- routine note rather than reported or bound beside it. Two of the person's own are reported,
-- and every default on a slot the person took is dropped, so none of them is reported either.
-- This replaced the one exemption the collision check kept until phase 5 of the keymap plan.
do
  local effective = {
    shipped = { leader = "app", bindings = { { action = "a", key = "a" } } },
    mine = { leader = "app", bindings = { { action = "open", key = "a" } } },
  }
  local result = build(defaultPlan(effective, { mine = { key = "user" } }))
  eq(#result.problems, 0, "a default meeting a user override is not reported")
  local owners = {}
  for _, row in ipairs(result.rows) do owners[#owners + 1] = row.owner end
  eq(table.concat(owners, ","), "mine", "and the default is dropped rather than bound beside it")
  eq(#result.notes, 1, "said in one routine note")
  eq((result.notes[1] or ""):find("shipped.a", 1, true) ~= nil, true, "which names the displaced action")

  effective.mine2 = { leader = "app", bindings = { { action = "open", key = "a" } } }
  result = build(defaultPlan(effective, { mine = { key = "user" }, mine2 = { key = "user" } }))
  eq(#result.problems, 1, "two user overrides on one chord are reported")

  effective.shipped2 = { leader = "app", bindings = { { action = "b", key = "a" } } }
  result = build(defaultPlan(effective, { mine = { key = "user" }, mine2 = { key = "user" } }))
  eq(#result.problems, 1, "two defaults on a slot the person took are both dropped, so only the person's pair is reported")
end

-- Spelling. Case, modifier order, modifier aliases and keycode aliases all agree.
do
  local result = build(defaultPlan({
    one = { leader = "app", bindings = {
      { action = "x", key = "S", mods = { "Shift", "Command" } },
      { action = "y", key = "ENTER", mods = { "cmd", "shift" } },
    } },
  }))
  local byAction = {}
  for _, row in ipairs(result.rows) do byAction[row.action] = row end
  eq(byAction.x.key, "s", "an upper case key is lowercased")
  eq(table.concat(byAction.x.mods, "+"), "cmd+shift", "modifiers are sorted and aliases canonical")
  eq(byAction.y.key, "return", "a keycode alias takes the table's own name")
  eq(table.concat(byAction.y.mods, "+"), "cmd+shift", "the same modifiers in another order agree")
  eq(keymap.modsText({ "shift", "cmd" }), keymap.modsText({ "command", "Shift" }), "modsText agrees across order and alias")
  eq(keymap.modsText(nil), "any", "modsText names a catch all")
  eq(keymap.modsText({}), "none", "modsText names an empty list")
end

-- The same chord in different case or modifier order is one collision, not two chords.
do
  local result = build(defaultPlan({
    one = { leader = "app", bindings = { { action = "p", key = "S", mods = { "shift", "cmd" } } } },
    two = { leader = "app", bindings = { { action = "q", key = "s", mods = { "Command", "Shift" } } } },
  }))
  eq(#result.problems, 1, "case and modifier order do not hide a collision")
end

-- The sources and their provenance. A provided row comes from the rows a plugin answered, a
-- plain combo has no leader, and a tool's open row is told from a host's. A special row is not a
-- source since phase 5 of the keymap plan, a host's runnable rows being its descriptors. A bindings row stating leader false is a plain combo, and one
-- naming its own role sits on that role whatever the plugin's default says.
do
  local plan = defaultPlan({
    tool = { leader = "app", bindings = { { action = "open", key = "t" } } },
    host = { leader = "app", bindings = { { action = "open", key = "h" } },
      specialRows = { { name = "lock", key = "l" }, { name = "nokey" } } },
    mover = { leader = "window", bindings = {
      { action = "left", key = "left", when = "gate" },
      { action = "paste", key = "v", mods = { "ctrl", "alt" }, leader = false },
      { action = "raise", key = "r", leader = "app" },
    } },
  }, { tool = { key = "user" } })
  local result = build(plan, {
    shortcuts = { { name = "tool", kind = "leader" } },
    provided = { toggler = {
      { action = "Safari", key = "S", leader = "app", fn = function() end },
      { action = "Terminal", key = "S", mods = { "alt" }, fn = function() end },
    } },
  })
  eq(#result.problems, 0, "the sources raise no collision between themselves")
  local seen = {}
  for _, row in ipairs(result.rows) do seen[row.source .. ":" .. row.action] = row end
  eq(seen["tool:open"] ~= nil, true, "a registered tool's open row is a tool row")
  eq(seen["tool:open"].origin, "user", "a key the person set marks the open row as theirs")
  eq(seen["tool:open"].role, "app", "an open row stating no leader inherits the plugin's role")
  eq(seen["host:open"] ~= nil, true, "an unregistered owner's open row is a host row")
  eq(seen["bindings:open"], nil, "an open row is never read a second time as a plain binding")
  eq(seen["special:lock"], nil, "a special row is no source, even with a key")
  eq(seen["special:nokey"], nil, "nor without one")
  eq(seen["bindings:left"].leader, "meta", "a window role resolves through the roles table")
  eq(seen["bindings:left"].role, "window", "and the row keeps the role it answers")
  eq(seen["bindings:left"].when, "gate", "a binding's gate is kept")
  eq(seen["bindings:paste"].leader, nil, "a bindings row with leader false is a plain combo")
  eq(seen["bindings:paste"].role, nil, "and answers no role")
  eq(table.concat(seen["bindings:paste"].mods, "+"), "alt+ctrl", "its modifiers are sorted to compare")
  eq(table.concat(seen["bindings:paste"].shownMods, "+"), "ctrl+alt", "and kept in the order a Mac spells them to show")
  eq(seen["bindings:raise"].leader, "hyper", "a row naming its own role leaves the plugin's default")
  eq(seen["provided:Safari"].leader, "hyper", "a provided row naming the app role sits on the app leader")
  eq(seen["provided:Safari"].anyMods, true, "a provided row on a leader stating no modifiers is a catch all")
  eq(seen["provided:Terminal"].leader, nil, "a provided row stating modifiers is a plain combo")
  eq(seen["provided:Terminal"].origin, "user", "a provided row is the person's own")
end

-- A bindings row with leader false and no modifiers would take a bare key from every app, and a
-- leader that is neither a role word nor false is a typo, so each is one problem and unbound.
do
  local result = build(defaultPlan({
    bad = { leader = "app", bindings = {
      { action = "bare", key = "b", leader = false },
      { action = "typo", key = "t", leader = true },
      { action = "fine", key = "f" },
    } },
  }))
  local seen, lines = {}, 0
  for _, row in ipairs(result.rows) do seen[row.action] = true end
  for _, pr in ipairs(result.problems) do
    if pr.why:find("bindings row", 1, true) then lines = lines + 1 end
  end
  eq(seen.bare, nil, "a plain row with no modifiers is not read")
  eq(seen.typo, nil, "a row with a leader of the wrong shape is not read")
  eq(seen.fine, true, "the plugin's other rows still are")
  eq(lines, 2, "and each refused row is one problem")
end

-- Every global row carries the function it calls, and the bound list holds the global rows in
-- the binding order, the order the paths before the binder bound in, plugin bindings in plan
-- order, then shortcuts in registration order, then hosts. A binding whose action was refused is
-- marked so the binder stays quiet about it, and a binding's own repeat wins over the
-- descriptor's.
do
  local openA, cmd, show = function() end, function() end, function() end
  local leftRun, rightRun = function() end, function() end
  local plan = {
    effective = {
      zeta = { leader = "app", bindings = { { action = "go", key = "g" }, { action = "bad", key = "b" } } },
      alpha = { leader = "window", bindings = { { action = "left", key = "left", repeats = false },
        { action = "right", key = "right" } } },
      tool = { leader = "app", bindings = { { action = "open", key = "t" } } },
      host = { leader = "app", bindings = { { action = "open", key = "h" } } },
    },
    identity = {}, contexts = { list = { bindings = { { action = "close", key = "x" } } } },
    order = { "zeta", "alpha", "tool", "host" },
  }
  local result = keymap.build({
    plan = plan, roles = ROLES, keycodes = KEYCODES,
    shortcuts = { { name = "tool", kind = "leader", fn = openA } },
    actions = {
      zeta = { go = { run = function() end } },
      alpha = { left = { run = leftRun, repeats = true, description = "Left" },
        right = { run = rightRun, repeats = true } },
    },
    refusedActions = { zeta = { bad = true } },
    hostRun = function(directory) return directory == "host" and show or nil end,
  })
  local by = {}
  for _, row in ipairs(result.rows) do by[row.source .. ":" .. tostring(row.action)] = row end
  eq(by["tool:open"].run, openA, "a tool row runs its shortcut's function")
  eq(by["host:open"].run, show, "a host row runs what the root answers for it")
  eq(by["bindings:left"].run, leftRun, "a binding runs the descriptor its action names")
  eq(by["bindings:left"].repeats, false, "a binding's own repeat wins over the descriptor's")
  eq(by["bindings:right"].repeats, true, "the descriptor's repeat answers where the binding is silent")
  eq(by["bindings:left"].description, "Left", "the descriptor's description labels a binding that states none")
  eq(by["bindings:bad"].run, nil, "a refused action leaves its binding with no function")
  eq(by["bindings:bad"].refused, true, "and marks the row refused")
  eq(by["context:close"].run, nil, "a list's own key carries no function, the contexts bind it")
  local place = {}
  for i, row in ipairs(result.bound) do place[row.source .. ":" .. tostring(row.action)] = i end
  eq(place["context:close"], nil, "a list's own key is not in the bound list")
  eq(#result.bound, #result.rows - 1, "every global row is in the bound list")
  eq(place["bindings:go"] < place["bindings:bad"], true, "each plugin's bindings keep their own order")
  eq(place["bindings:bad"] < place["bindings:left"], true, "bindings follow plan order")
  eq(place["bindings:left"] < place["bindings:right"], true, "and the next plugin's own order")
  eq(place["bindings:right"] < place["tool:open"], true, "every binding comes before every shortcut")
  eq(place["tool:open"] < place["host:open"], true, "shortcuts come before hosts")
end

-- One source that raises drops its own rows with one problem naming it, and every other source
-- still builds. A plugin whose whole actions member failed marks every binding refused, so the
-- binder stays quiet about them, and a host with nothing to show is a quiet row.
do
  local plan = {
    effective = {
      host = { leader = "app", bindings = { { action = "open", key = "h" } } },
      mover = { leader = "app", bindings = { { action = "go", key = "g" } } },
    },
    identity = {}, contexts = {}, order = { "host", "mover" },
  }
  local result = keymap.build({ plan = plan, roles = ROLES, keycodes = KEYCODES,
    hostRun = function() error("boom") end, refusedActions = { mover = true } })
  local by, raised = {}, nil
  for _, row in ipairs(result.rows) do by[row.source .. ":" .. tostring(row.action)] = row end
  for _, pr in ipairs(result.problems) do if pr.where == "the open keys source" then raised = pr end end
  eq(by["host:open"], nil, "a raising source leaves its rows out")
  eq(raised ~= nil, true, "and is one problem naming the source")
  eq(by["bindings:go"] ~= nil, true, "every other source still builds")
  eq(by["bindings:go"].refused, true, "a failed actions member marks every binding of the plugin refused")

  local quiet = keymap.build({ plan = plan, roles = ROLES, keycodes = KEYCODES,
    hostRun = function() return nil end })
  local host
  for _, row in ipairs(quiet.rows) do if row.source == "host" then host = row end end
  eq(host and host.quiet, true, "a host with nothing to show is a quiet row")
  local binder = assert(loadfile(here .. "../lib/binder.lua"))()
  local problems = binder.bind({ host }, { engines = { hyper = { bind = function() end } } })
  eq(#problems, 0, "and the binder leaves it unbound without a line")

  local registrar = assert(loadfile(here .. "../lib/registrar.lua"))()
  local _, refused = registrar.validateActions("demo", { provides = { actions = "actions" } },
    { actions = function() error("raised") end })
  eq(refused, true, "an actions member that raises answers refused as true")
end

-- Descriptor validation, the registrar's half. A table or a function answering one, a bad field
-- refused with one problem naming the plugin, the action and the field, and the rest kept.
do
  local registrar = assert(loadfile(here .. "../lib/registrar.lua"))()
  local ok, field = registrar.validateDescriptor({ run = function() end, description = "x", repeats = true,
    keywords = { "a", "b" }, icon = { emoji = "x" }, group = function() end, listed = false })
  eq(ok, true, "a descriptor with every optional field in its type passes")
  ok, field = registrar.validateDescriptor({ description = "no run" })
  eq(ok, false, "a descriptor with no run is refused")
  eq(field, "run", "and run is named")
  ok, field = registrar.validateDescriptor({ run = function() end, repeat_ = true })
  eq(field, "repeat_", "an unknown field is refused by name")
  ok, field = registrar.validateDescriptor({ run = function() end, repeats = "yes" })
  eq(field, "repeats", "a field of the wrong type is refused by name")
  ok, field = registrar.validateDescriptor({ run = function() end, keywords = { "a", 3 } })
  eq(field, "keywords", "a keyword list holding a number is refused")
  eq((registrar.validateDescriptor("run")), false, "a descriptor that is not a table is refused")

  local module = { built = nil }
  function module:actions() return self.built end
  module.built = {
    { name = "good", run = function() end },
    { name = "broken", run = "notAFunction" },
    { name = "later", run = function() end },
  }
  local actions, refused, problems, order = registrar.validateActions("demo", { provides = { actions = "actions" } }, module)
  eq(actions.good ~= nil, true, "the function form is called on its module and a good action kept")
  eq(actions.broken, nil, "a broken action is not kept")
  eq(refused.broken, true, "and is named as refused")
  eq(#problems, 1, "one problem for the one broken action")
  eq(table.concat(order, ","), "good,later", "the order is the list's own, refused actions left out")
  local why = problems[1] and (problems[1].where .. " " .. problems[1].why) or ""
  eq(why:find("demo action broken", 1, true) ~= nil, true, "the problem names the plugin and the action")
  eq(why:find("field run", 1, true) ~= nil, true, "the problem names the field")

  actions = registrar.validateActions("demo", { provides = { actions = "table" } },
    { table = { { name = "x", run = function() end } } })
  eq(actions.x ~= nil, true, "the table form is read as it sits")

  -- A table keyed by name was the shape before phase 2b and cannot say an order, so it is refused
  -- whole. A descriptor with no name is named by its place, and a second one taking a name
  -- already taken is refused while the first keeps it.
  local _, keyed, keyedProblems = registrar.validateActions("demo", { provides = { actions = "table" } },
    { table = { x = { run = function() end } } })
  eq(keyed, true, "a table keyed by name is refused whole")
  eq((keyedProblems[1] and keyedProblems[1].why or ""):find("rather than a list", 1, true) ~= nil, true,
    "and the problem says a list is the shape")
  local first = function() end
  local named, _, namedProblems = registrar.validateActions("demo", { provides = { actions = "table" } },
    { table = { { run = function() end }, { name = "x", run = first }, { name = "x", run = function() end } } })
  eq(named.x and named.x.run, first, "the first descriptor taking a name keeps it")
  eq(#namedProblems, 2, "a nameless descriptor and a second taker of a name are one problem each")
  local _, _, missing = registrar.validateActions("demo", { provides = { actions = "nothing" } }, {})
  eq(#missing, 1, "a member that names nothing is one problem")
  local none = registrar.validateActions("demo", {}, {})
  eq(next(none), nil, "a plugin declaring no actions answers an empty table")

  local rows, rowProblems = registrar.providedBindings("demo", { provides = { bindings = "rows" } }, {
    rows = function() return {
      { action = "a", key = "a", leader = "app", fn = function() end },
      { action = "b", key = "b", mods = { "alt" }, fn = function() end },
      { action = "c", key = "c", leader = "app" },
      { action = "d", key = "d", fn = function() end },
    } end,
  })
  eq(#rows, 2, "provided rows with a key, a function and a leader or modifiers are kept")
  eq(#rowProblems, 2, "a row with no function and a row with neither leader nor modifiers are refused")
end

-- The retired fields. registry.commands, defaults.key and defaults.mods are each refused with one
-- problem naming what replaced it, and defaults.leader is not, since it stays as the role every
-- bindings row of a plugin inherits.
do
  local registrar = assert(loadfile(here .. "../lib/registrar.lua"))()
  local problems = registrar.retiredFields("old", {
    registry = { commands = { x = {} } },
    defaults = { leader = "app", key = "K", mods = { "cmd" } },
  })
  eq(#problems, 3, "each retired field is one problem")
  local text = ""
  for _, pr in ipairs(problems) do text = text .. pr.where .. " " .. pr.why .. "\n" end
  eq(text:find("registry.commands is retired, replaced by an action descriptor", 1, true) ~= nil, true,
    "a command names the descriptor that replaced it")
  eq(text:find("defaults.key is retired, replaced by a defaults.bindings row whose action is open", 1, true) ~= nil,
    true, "a key names the open row that replaced it")
  eq(text:find("defaults.mods is retired", 1, true) ~= nil, true, "and so does a modifier list")
  eq(#registrar.retiredFields("new", { defaults = { leader = "window", bindings = {} } }), 0,
    "defaults.leader and bindings are not retired")

  -- The registry refuses a descriptor still carrying commands rather than registering it short.
  local registryLib = assert(loadfile(here .. "../lib/registry.lua"))()
  local said = {}
  local registry = registryLib.new({ apiVersion = 1, log = { w = function(m) said[#said + 1] = m end } })
  eq(registry.register({ name = "old", apiVersion = 1, open = function() end, commands = { x = function() end } }),
    false, "the registry refuses a descriptor carrying commands")
  eq((said[1] or ""):find("carries commands, which retired", 1, true) ~= nil, true, "and says what replaced them")
end

-- A person's key override in config/plugins.lua, vpn = { key = "Q" }, still moves the open key until
-- phase 5. It is split off the override, the rest merges as ever, and it lands on the open row of
-- the effective table the merge copied, so no manifest table is touched, and the provenance taken
-- from the override as written marks that row the person's.
do
  local defaults = assert(loadfile(here .. "../lib/defaults.lua"))()
  local shipped = { leader = "app", description = "VPN", bindings = { { action = "open", key = "P" } } }
  local mine = { key = "Q", mods = { "shift" }, description = "Tunnel" }
  local rest, openKey = defaults.splitOpenKey(mine)
  eq(rest.key, nil, "the key is taken out of the override")
  eq(rest.description, "Tunnel", "and every other field stays in it")
  local eff = defaults.merge(shipped, rest)
  eq(defaults.applyOpenKey(eff, openKey), true, "the key lands on a plugin with an open row")
  eq(eff.bindings[1].key, "Q", "the open row takes the person's key")
  eq(table.concat(eff.bindings[1].mods, "+"), "shift", "and their modifiers")
  eq(eff.key, nil, "and no key field reaches the effective table")
  eq(shipped.bindings[1].key, "P", "the manifest's own row is untouched")
  eq(defaults.applyOpenKey({ bindings = { { action = "go", key = "g" } } }, openKey), false,
    "a plugin with no open row answers false for the caller to report")
  local same, none = defaults.splitOpenKey({ leader = "window" })
  eq(none, nil, "an override with no key or mods is left as it is")
  eq(same.leader, "window", "a leader override merges as an ordinary default")

  local prov = defaults.provenance(shipped, mine)
  local result = build(defaultPlan({ vpn = eff }, { vpn = prov }), { shortcuts = { { name = "vpn", kind = "leader" } } })
  local open = result.rows[1]
  eq(open and open.key, "q", "the keymap binds the translated key")
  eq(open and open.origin, "user", "and marks it the person's")
end

-- Launcher rows from descriptors. Olm builds one row per listed action in the plugin's own order,
-- the title its description, the subtitle its subtitle followed by the keymap's chord, the item its
-- kind or the owner's identity joined to its name, and a runner that runs the chosen descriptor and
-- hands any other row to the plugin's own launcherRun.
do
  local contributions = assert(loadfile(here .. "../lib/contributions.lua"))()
  local result = build(defaultPlan({
    clip = { leader = "app", bindings = {
      { action = "open", key = "x" },
      { action = "append", key = "c", mods = { "ctrl", "alt" }, leader = false },
    } },
  }), { shortcuts = { { name = "clip", kind = "leader" } } })
  local ran = {}
  local actions = { clip = {
    append = { name = "append", run = function() ran[#ran + 1] = "append" end, description = "Append copy",
      subtitle = "Clipboard", icon = "append", keywords = "collect", kind = "special" },
    manage = { name = "manage", run = function() ran[#ran + 1] = "manage" end, subtitle = "Clipboard" },
    hidden = { name = "hidden", run = function() end, listed = false },
  } }
  local own = {}
  local suppliers, runners = contributions.assemble({
    host = "launcher",
    plan = { order = { "clip" }, identity = {}, sets = { launcher = { launcherRun = { "clip" } } },
      effective = { clip = { launcherOrder = 25 } } },
    manifests = { clip = { provides = { launcherRun = "launcherRun" } } },
    modules = { clip = { launcherRun = function(_, item) own[#own + 1] = item.name end } },
    registrar = assert(loadfile(here .. "../lib/registrar.lua"))(),
    actions = actions, actionOrder = { clip = { "append", "manage", "hidden" } },
    keymap = result,
  })
  eq(#suppliers, 1, "a plugin with listed actions is one supplier")
  local rows = suppliers[1]()
  eq(#rows, 2, "an unlisted action gets no row")
  eq(rows[1].title, "Append copy", "the title is the descriptor's description")
  eq(rows[2].title, "manage", "and the action's name where it states none")
  eq(rows[1].group, "Clipboard", "the subtitle is the descriptor's subtitle")
  eq(rows[1].chord and rows[1].chord.leader, false, "a plain combo's chord names no leader")
  eq(rows[1].chord and table.concat(rows[1].chord.mods, "+"), "ctrl+alt", "and its modifiers as a Mac spells them")
  eq(rows[2].chord, nil, "an action with no key has no chord")
  eq(rows[1].item.kind .. ":" .. rows[1].item.name, "special:append", "the item is the descriptor's kind and its name")
  eq(rows[2].item.kind, "clip", "and the owner's identity where it states no kind")
  eq(rows[1].item.owner, "clip", "every row is owned by its plugin")
  eq(rows[1].order, 25, "and placed by the plugin's launcherOrder")
  eq(rows[1].keywords, "collect", "keywords travel to the row")
  runners.clip(rows[1].item)
  runners.clip({ kind = "clip", name = "computed" })
  eq(ran[1], "append", "a chosen action row runs its descriptor")
  eq(own[1], "computed", "any other row of the plugin reaches its own launcherRun")
end

-- A leader sheet's rows read the keymap, registered tools first in registration order, then each
-- plugin in plan order with its host key and then its bindings, a host's own actions among them, one row per chord,
-- and nothing on another leader or with no leader at all.
do
  local hints = assert(loadfile(here .. "../lib/hints.lua"))()
  local plan = {
    effective = {
      zed = { leader = "app", description = "Zed tool", bindings = { { action = "open", key = "z" } } },
      cap = { leader = "app", bindings = { { action = "shot", key = "4" },
        { action = "shot2", key = "4", mods = { "shift" } }, { action = "far", key = "f", leader = "window" } } },
      host = { leader = "app", description = "Host", bindings = { { action = "open", key = "space" },
        { action = "lock", key = "l", description = "Lock" } } },
      clip = { leader = "app", bindings = { { action = "paste", key = "v", mods = { "ctrl" }, leader = false } } },
    },
    identity = {}, contexts = {}, order = { "cap", "host", "zed", "clip" },
  }
  local result = keymap.build({ plan = plan, roles = ROLES, keycodes = KEYCODES,
    shortcuts = { { name = "zed", kind = "leader", fn = function() end } },
    actions = { cap = { shot = { description = "Shot", group = "Capture" } } },
    hostRun = function() return function() end end,
  })
  local rows = hints.sheetRows(result, plan, "hyper")
  local labels = {}
  for _, b in ipairs(rows) do labels[#labels + 1] = b.description end
  eq(table.concat(labels, ","), "Zed tool,Shot,Shot2,Host,Lock",
    "tools lead, then each plugin's host key and bindings, in plan order, a row with no label wearing its action in words")
  eq(rows[3].mods and rows[3].mods[1], "shift", "a row keeps its modifiers")
  eq(rows[2].group, "Capture", "a row carries the group its descriptor names")

  local windowRows = hints.sheetRows(result, plan, "meta")
  eq(#windowRows, 1, "a leader's sheet reads the keymap's rows on its own leader")
  eq(windowRows[1].action, "far", "including a row a plugin on another leader moved there")
end

-- Review fixes of phase 2b. key NONE or false unbinds the open row, a person's bindings that state
-- no open row keep the default one unless the key was declined, and a registered leader tool left
-- with no open row is named, quietly where the person unbound it.
do
  local defaults = assert(loadfile(here .. "../lib/defaults.lua"))()
  local shipped = { leader = "app", bindings = { { action = "open", key = "P" }, { action = "go", key = "g" } } }
  for _, declined in ipairs({ defaults.NONE, false }) do
    local mine = { key = declined }
    local rest, openKey = defaults.splitOpenKey(mine)
    local eff = defaults.merge(shipped, rest)
    defaults.keepOpenRow(shipped, mine, eff)
    eq(defaults.applyOpenKey(eff, openKey), true, "a declined key lands on the open row")
    local open = false
    for _, b in ipairs(eff.bindings) do if b.action == "open" then open = true end end
    eq(open, false, "key " .. tostring(declined == false and "false" or "NONE") .. " removes the open row")
    eq(#eff.bindings, 1, "and keeps every other row")
  end

  local mine = { bindings = { { action = "go", key = "h" } } }
  local eff = defaults.merge(shipped, mine)
  defaults.keepOpenRow(shipped, mine, eff)
  eq(eff.bindings[1].action .. eff.bindings[1].key, "openP", "a bindings override with no open row keeps the default one")
  eq(#eff.bindings, 2, "and replaces the other rows wholesale")
  local alone = defaults.merge(shipped, (defaults.splitOpenKey({ key = "Q" })))
  eq(alone.leader, "app", "an override holding only a key keeps every other default")
  local declined = { key = defaults.NONE, bindings = { { action = "go", key = "h" } } }
  local eff2 = defaults.merge(shipped, defaults.splitOpenKey(declined))
  defaults.keepOpenRow(shipped, declined, eff2)
  eq(#eff2.bindings, 1, "unless the person declined the open key")
  local own = { bindings = { { action = "open", key = "Q" } } }
  local eff3 = defaults.merge(shipped, own)
  defaults.keepOpenRow(shipped, own, eff3)
  eq(#eff3.bindings == 1 and eff3.bindings[1].key, "Q", "a person's own open row is kept as written")

  local function openProblems(effective, provenance)
    local result = build(defaultPlan(effective, provenance), { shortcuts = { { name = "tool", kind = "leader" } } })
    local n = 0
    for _, pr in ipairs(result.problems) do
      if pr.why:find("no bindings row whose action is open", 1, true) then n = n + 1 end
    end
    return n
  end
  eq(openProblems({ tool = { leader = "app", bindings = {} } }), 1,
    "a registered leader tool with no open row is one problem")
  eq(openProblems({ tool = { leader = "app", bindings = {} } }, { tool = { key = "user" } }), 0,
    "and none where the person unbound it")
  eq(openProblems({ tool = { leader = "app", bindings = { { action = "open", key = "t" } } } }), 0,
    "a tool with its open row is not named")
end

-- A role word no leader answers is a problem naming the plugin, the action and the word, and the
-- row is left unbound rather than moved to the app leader.
do
  local result = build(defaultPlan({
    typo = { leader = "app", bindings = { { action = "go", key = "g", leader = "widnow" } } },
    inherit = { leader = "apps", bindings = { { action = "run", key = "r" } } },
  }))
  local text, rows = "", 0
  for _, pr in ipairs(result.problems) do text = text .. pr.where .. " " .. pr.why .. "\n" end
  for _ in ipairs(result.rows) do rows = rows + 1 end
  eq(rows, 0, "neither misspelled row is bound")
  eq(text:find("typo go", 1, true) ~= nil and text:find("'widnow'", 1, true) ~= nil, true,
    "the problem names the plugin, the action and the word")
  eq(text:find("'apps'", 1, true) ~= nil, true, "a misspelled default leader is named too")
end

-- A descriptor kind the launcher keys specially is refused, and special is refused only on a
-- registered tool's name. The reserved set is read off the launcher host itself.
do
  local registrar = assert(loadfile(here .. "../lib/registrar.lua"))()
  local launcherSource = assert(io.open(here .. "../host/launcher/init.lua")):read("a")
  local reservedLine = launcherSource:match("obj%.reservedKinds = (%b{})")
  local reserved = assert(load("return " .. reservedLine))()
  eq(reserved.app and reserved.calc and reserved.scope and not reserved.special, true,
    "the launcher reserves app, calc and scope and leaves special open")
  local list = {
    { name = "a", run = function() end, kind = "app" },
    { name = "c", run = function() end, kind = "calc" },
    { name = "s", run = function() end, kind = "scope" },
    { name = "vpn", run = function() end, kind = "special" },
    { name = "appendCopy", run = function() end, kind = "special" },
  }
  local actions, refused = registrar.validateActions("demo", { provides = { actions = "t" } }, { t = list },
    { reservedKinds = reserved, toolNames = { vpn = true } })
  eq(refused.a and refused.c and refused.s and true, true, "every reserved kind is refused")
  eq(refused.vpn, true, "special on a registered tool's name is refused")
  eq(actions.appendCopy ~= nil, true, "special on any other name stays legal")
end

-- A launcher row built from a descriptor takes its key's gate, the binding's own when before the
-- descriptor's, the rule the keymap and every leader's sheet follow.
do
  local contributions = assert(loadfile(here .. "../lib/contributions.lua"))()
  local result = build(defaultPlan({
    wm = { leader = "window", bindings = { { action = "next", key = "n", when = "bindingGate" } } },
  }), { actions = { wm = { next = { run = function() end, when = "descriptorGate" } } } })
  local row = contributions.actionRow("wm", "next", { name = "next", run = function() end, when = "descriptorGate" }, result)
  eq(row.when, "bindingGate", "the binding's gate wins on the row as on the key")
  local plain = contributions.actionRow("wm", "other", { name = "other", run = function() end, when = "descriptorGate" }, result)
  eq(plain.when, "descriptorGate", "and the descriptor's answers where no binding states one")
end

-- A build given no plan raises, which is the failure the root catches so a defect here cannot
-- stop a load. The root's own pcall needs the whole composition, so this pins the raise.
do
  local ok = pcall(keymap.build, {})
  eq(ok, false, "a build with no plan raises, for the root to catch")
end

print(string.format("keymap, %d check(s), %d failure(s)", checks, failures))
os.exit(failures == 0 and 0 or 1)
