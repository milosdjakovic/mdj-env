-- The keymap read model in plain Lua.
--
-- lib/keymap.lua is pure, it takes the plan, the roles and the keycode table as inputs, so it
-- needs no Hammerspoon and no stub. These cases drive it with small hand written plans and pin
-- the collision rule, the one exemption, and the spelling it normalises to. The proof that it
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

-- A default meeting the person's own override is not reported, two of the person's own are, and
-- two defaults beside an override are still reported once.
do
  local effective = {
    shipped = { leader = "app", bindings = { { action = "a", key = "a" } } },
    mine = { leader = "app", key = "a" },
  }
  local result = build(defaultPlan(effective, { mine = { key = "user" } }))
  eq(#result.problems, 0, "a default meeting a user override is not reported")

  effective.mine2 = { leader = "app", key = "a" }
  result = build(defaultPlan(effective, { mine = { key = "user" }, mine2 = { key = "user" } }))
  eq(#result.problems, 1, "two user overrides on one chord are reported")

  effective.shipped2 = { leader = "app", bindings = { { action = "b", key = "a" } } }
  result = build(defaultPlan(effective, { mine = { key = "user" }, mine2 = { key = "user" } }))
  eq(#result.problems, 2, "two defaults beside user overrides are still reported once each class")
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
-- plain combo has no leader, a command takes the lookup's origin, a tool is told from a host and
-- a special row is read from the host that declares it.
do
  local plan = defaultPlan({
    tool = { leader = "app", key = "t" },
    host = { leader = "app", key = "h", specialRows = { { name = "lock", key = "l" }, { name = "nokey" } } },
    mover = { leader = "window", bindings = { { action = "left", key = "left", when = "gate" } } },
  }, { tool = { key = "user" } })
  local result = build(plan, {
    shortcuts = { { name = "tool", kind = "leader" }, { name = "pasteNext", kind = "global" } },
    manifests = { source = { registry = { commands = { pasteNext = { key = "v", mods = { "ctrl", "alt" } } } } } },
    commandKey = function(name) return { key = "v", mods = { "ctrl", "alt" }, origin = "user" } end,
    provided = { toggler = {
      { action = "Safari", key = "S", leader = "app", fn = function() end },
      { action = "Terminal", key = "S", mods = { "alt" }, fn = function() end },
    } },
  })
  eq(#result.problems, 0, "the sources raise no collision between themselves")
  local seen = {}
  for _, row in ipairs(result.rows) do seen[row.source .. ":" .. row.action] = row end
  eq(seen["tool:open"] ~= nil, true, "a registered tool is a tool row")
  eq(seen["tool:open"].origin, "user", "a user set key marks the row as the person's")
  eq(seen["host:open"] ~= nil, true, "an unregistered owner with a key is a host row")
  eq(seen["special:lock"] ~= nil, true, "a special row with a key is read")
  eq(seen["special:nokey"], nil, "a special row with no key is not")
  eq(seen["bindings:left"].leader, "meta", "a window role resolves through the roles table")
  eq(seen["bindings:left"].when, "gate", "a binding's gate is kept")
  eq(seen["provided:Safari"].leader, "hyper", "a provided row naming the app role sits on the app leader")
  eq(seen["provided:Safari"].anyMods, true, "a provided row on a leader stating no modifiers is a catch all")
  eq(seen["provided:Terminal"].leader, nil, "a provided row stating modifiers is a plain combo")
  eq(seen["provided:Terminal"].origin, "user", "a provided row is the person's own")
  eq(seen["command:pasteNext"].leader, nil, "a global command is a plain combo")
  eq(seen["command:pasteNext"].origin, "user", "a command takes the lookup's origin")
end

-- Every global row carries the function it calls, and the bound list holds the global rows in
-- the binding order, the order the paths before the binder bound in, plugin bindings in plan
-- order, then shortcuts in registration order, then hosts, then special rows. A binding whose action was refused is
-- marked so the binder stays quiet about it, and a binding's own repeat wins over the
-- descriptor's.
do
  local openA, cmd, show, lock = function() end, function() end, function() end, function() end
  local leftRun, rightRun = function() end, function() end
  local plan = {
    effective = {
      zeta = { leader = "app", bindings = { { action = "go", key = "g" }, { action = "bad", key = "b" } } },
      alpha = { leader = "window", bindings = { { action = "left", key = "left", repeats = false },
        { action = "right", key = "right" } } },
      tool = { leader = "app", key = "t" },
      host = { leader = "app", key = "h", specialRows = { { name = "lock", key = "l" } } },
    },
    identity = {}, contexts = { list = { bindings = { { action = "close", key = "x" } } } },
    order = { "zeta", "alpha", "tool", "host" },
  }
  local result = keymap.build({
    plan = plan, roles = ROLES, keycodes = KEYCODES,
    shortcuts = { { name = "tool", kind = "leader", fn = openA }, { name = "go", kind = "global", fn = cmd } },
    actions = {
      zeta = { go = { run = function() end } },
      alpha = { left = { run = leftRun, repeats = true }, right = { run = rightRun, repeats = true } },
    },
    refusedActions = { zeta = { bad = true } },
    hostRun = function(directory) return directory == "host" and show or nil end,
    specialRun = function(owner, name) return name == "lock" and lock or nil end,
  })
  local by = {}
  for _, row in ipairs(result.rows) do by[row.source .. ":" .. tostring(row.action)] = row end
  eq(by["tool:open"].run, openA, "a tool row runs its shortcut's function")
  eq(by["host:open"].run, show, "a host row runs what the root answers for it")
  eq(by["special:lock"].run, lock, "a special row runs what the root answers for it")
  eq(by["bindings:left"].run, leftRun, "a binding runs the descriptor its action names")
  eq(by["bindings:left"].repeats, false, "a binding's own repeat wins over the descriptor's")
  eq(by["bindings:right"].repeats, true, "the descriptor's repeat answers where the binding is silent")
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
  eq(place["host:open"] < place["special:lock"], true, "and hosts before special rows")
end

-- One source that raises drops its own rows with one problem naming it, and every other source
-- still builds. A plugin whose whole actions member failed marks every binding refused, so the
-- binder stays quiet about them, and a host with nothing to show is a quiet row.
do
  local plan = {
    effective = {
      host = { leader = "app", key = "h" },
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
    good = { run = function() end },
    broken = { run = "notAFunction" },
  }
  local actions, refused, problems = registrar.validateActions("demo", { provides = { actions = "actions" } }, module)
  eq(actions.good ~= nil, true, "the function form is called on its module and a good action kept")
  eq(actions.broken, nil, "a broken action is not kept")
  eq(refused.broken, true, "and is named as refused")
  eq(#problems, 1, "one problem for the one broken action")
  local why = problems[1] and (problems[1].where .. " " .. problems[1].why) or ""
  eq(why:find("demo action broken", 1, true) ~= nil, true, "the problem names the plugin and the action")
  eq(why:find("field run", 1, true) ~= nil, true, "the problem names the field")

  actions = registrar.validateActions("demo", { provides = { actions = "table" } }, { table = { x = { run = function() end } } })
  eq(actions.x ~= nil, true, "the table form is read as it sits")
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

-- A build given no plan raises, which is the failure the root catches so a defect here cannot
-- stop a load. The root's own pcall needs the whole composition, so this pins the raise.
do
  local ok = pcall(keymap.build, {})
  eq(ok, false, "a build with no plan raises, for the root to catch")
end

print(string.format("keymap, %d check(s), %d failure(s)", checks, failures))
os.exit(failures == 0 and 0 or 1)
