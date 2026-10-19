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

-- The sources and their provenance. A toggle is found by its data shape, a plain combo has no
-- leader, a command takes the lookup's origin, a tool is told from a host and a special row
-- is read from the host that declares it.
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
    data = { toggler = { toggles = {
      { app = "Safari", key = "S" },
      { app = "Terminal", key = "S", modifiers = { "alt" } },
    } } },
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
  eq(seen["toggles:Safari"].leader, "hyper", "a toggle with no modifiers sits on the app leader")
  eq(seen["toggles:Terminal"].leader, nil, "a toggle stating modifiers is a plain combo")
  eq(seen["toggles:Terminal"].origin, "user", "a toggle is the person's own")
  eq(seen["command:pasteNext"].leader, nil, "a global command is a plain combo")
  eq(seen["command:pasteNext"].origin, "user", "a command takes the lookup's origin")
end

-- A build given no plan raises, which is the failure the root catches so a defect here cannot
-- stop a load. The root's own pcall needs the whole composition, so this pins the raise.
do
  local ok = pcall(keymap.build, {})
  eq(ok, false, "a build with no plan raises, for the root to catch")
end

print(string.format("keymap, %d check(s), %d failure(s)", checks, failures))
os.exit(failures == 0 and 0 or 1)
