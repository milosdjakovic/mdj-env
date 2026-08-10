-- Unit case for Olm.spoon/lib/registry.lua, the tool registry phase seven builds, a
-- factory in the same style as lib/recency.lua. The runner reaches this file with a
-- dofile call carrying an absolute path, so this file in turn locates itself the same
-- way, through debug.getinfo, and derives the module path from there. No absolute path
-- is ever written down here, and the module under test is only loaded, never edited.
--
-- Each check prints one line, PASS or FAIL followed by a plain description, and the
-- runner counts and reports from those lines alone, the same convention every other
-- case file already follows.
--
-- Every block below loads its own fresh copy of the module with loadfile and builds its
-- own instance with M.new, so one block's registrations can never leak into another's
-- expectations, the same isolation cases/recency.lua already keeps. A refusal is proven
-- two ways here, the boolean register answers and the line it would have logged. Rather
-- than reading that line back out of hs.logger's own global, shared, process wide
-- history, which is not this file's to own, opts.log hands the module a small stub
-- answering w(message), collecting straight into a table this file already holds.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local modulePath = caseDir .. "/../../Spoons/Olm.spoon/lib/registry.lua"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    if detail then
      print("FAIL " .. description .. ", " .. detail)
    else
      print("FAIL " .. description)
    end
  end
end

local function freshModule()
  local chunk, err = loadfile(modulePath)
  if not chunk then
    error("could not load Olm.spoon/lib/registry.lua, " .. tostring(err))
  end
  return chunk()
end

-- A stub logger, and a fresh instance built against it, in one call, so every block
-- below reads warnings.log for what it just logged.
local function freshRegistry(apiVersion)
  local warnings = {}
  local log = { w = function(message) warnings[#warnings + 1] = message end }
  local M = freshModule()
  local r = M.new({ apiVersion = apiVersion or 1, log = log })
  return r, warnings
end

local function found(warnings, needle)
  for _, message in ipairs(warnings) do
    if message:find(needle, 1, true) then return true end
  end
  return false
end

-- M.new requires opts.apiVersion, the same readable error recency.lua raises for its
-- own missing opts.settingsKey.
do
  local M = freshModule()
  local calledOk, err = pcall(function() return M.new({}) end)
  check(
    "M.new without opts.apiVersion raises a readable error",
    calledOk == false and type(err) == "string" and #err > 0,
    "pcall returned ok=" .. tostring(calledOk) .. " err=" .. tostring(err)
  )
end

-- A good registration and a successful run.
do
  local r = freshRegistry(1)
  local ran = 0
  local ok = r.register({ name = "clipboard", apiVersion = 1, open = function() ran = ran + 1 end })
  check("a well formed descriptor registers", ok == true)

  r.activate({ "clipboard" })
  local didRun = r.run("clipboard")
  check("run answers true and calls open for an active tool", didRun == true and ran == 1)
end

-- Refusal one, no name, or a name that is not a string.
do
  local r, warnings = freshRegistry(1)

  local ok = r.register({ apiVersion = 1, open = function() end })
  check("a descriptor with no name is refused", ok == false)
  check(
    "the refusal for a missing name is logged",
    found(warnings, "name is missing"),
    table.concat(warnings, " | ")
  )

  local ok2 = r.register({ name = 42, apiVersion = 1, open = function() end })
  check("a descriptor whose name is not a string is refused", ok2 == false)
  check(
    "the refusal for a non string name is logged",
    found(warnings, "not a string"),
    table.concat(warnings, " | ")
  )
end

-- Refusal two, a second registration under a name already taken.
do
  local r, warnings = freshRegistry(1)
  check(
    "the first registration under a name succeeds",
    r.register({ name = "vpn", apiVersion = 1, open = function() end }) == true
  )

  local ok = r.register({ name = "vpn", apiVersion = 1, open = function() end })
  check("a second registration under the same name is refused", ok == false)
  check(
    "the refusal names the tool that already holds the name",
    found(warnings, "vpn"),
    table.concat(warnings, " | ")
  )
end

-- Refusal three, a commands key colliding with any name already indexed, whether a
-- tool name or another tool's command.
do
  local r, warnings = freshRegistry(1)
  check(
    "a tool with a command registers",
    r.register({ name = "clipboard", apiVersion = 1, commands = { appendCopy = function() end } }) == true
  )

  local ok = r.register({ name = "textCase", apiVersion = 1, commands = { appendCopy = function() end } })
  check("a command colliding with another tool's command is refused", ok == false)
  check(
    "the refusal names the new tool and the command that collided",
    found(warnings, "textCase") and found(warnings, "appendCopy"),
    table.concat(warnings, " | ")
  )

  local ok2 = r.register({ name = "appendCopy", apiVersion = 1, open = function() end })
  check("a tool named after another tool's existing command is refused", ok2 == false)
end

-- Refusal four, an apiVersion that is missing, not an integer, or does not match the
-- core's.
do
  local r, warnings = freshRegistry(1)

  check(
    "a missing apiVersion is refused",
    r.register({ name = "a", open = function() end }) == false
  )
  check(
    "the refusal for a missing apiVersion is logged",
    found(warnings, "apiVersion"),
    table.concat(warnings, " | ")
  )

  check(
    "a non integer apiVersion is refused",
    r.register({ name = "b", apiVersion = 1.5, open = function() end }) == false
  )
  check(
    "an apiVersion that does not match the core's is refused",
    r.register({ name = "c", apiVersion = 2, open = function() end }) == false
  )
end

-- Activation, a name nothing registered logs one warning naming it and is otherwise
-- ignored.
do
  local r, warnings = freshRegistry(1)
  r.register({ name = "vpn", apiVersion = 1, open = function() end })

  r.activate({ "vpn", "noSuchTool" })
  check(
    "an unknown name in the activation list is logged",
    found(warnings, "noSuchTool"),
    table.concat(warnings, " | ")
  )

  local active = r.active()
  check(
    "active lists only the tool that was actually registered",
    #active == 1 and active[1] == "vpn"
  )
end

-- Inactive answers, a registered tool left out of the activation list.
do
  local r = freshRegistry(1)
  r.register({ name = "vpn", apiVersion = 1, open = function() end })
  r.register({ name = "emoji", apiVersion = 1, open = function() end })
  r.activate({ "vpn" })

  check("run answers false for a registered but inactive tool", r.run("emoji") == false)
  check("get answers nil for a registered but inactive tool", r.get("emoji") == nil)
  check(
    "get answers the descriptor for an active tool",
    r.get("vpn") ~= nil and r.get("vpn").name == "vpn"
  )

  local all = r.all()
  check("all lists every registered tool regardless of active state", #all == 2)
end

-- A command dispatching through its owning tool, and following its tool's active
-- state.
do
  local r = freshRegistry(1)
  local calls = {}
  r.register({
    name = "clipboard",
    apiVersion = 1,
    open = function() calls[#calls + 1] = "open" end,
    commands = {
      appendCopy = function() calls[#calls + 1] = "appendCopy" end,
    },
  })

  check(
    "a command on an inactive tool does not run",
    r.run("appendCopy") == false and #calls == 0
  )

  r.activate({ "clipboard" })
  check("a command on an active tool runs through its owning tool", r.run("appendCopy") == true)
  check("the command's own function is what ran", calls[#calls] == "appendCopy")
end
