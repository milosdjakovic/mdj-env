-- Unit case for Olm.spoon/host/actionpanel/init.lua, the verb classification phase eight's
-- first packet builds. The runner reaches this file with a dofile call carrying an absolute
-- path, so this file in turn locates itself the same way, through debug.getinfo, and derives
-- the module path from there. No absolute path is ever written down here, and the module
-- under test is only loaded, never edited.
--
-- Each check prints one line, PASS or FAIL followed by a plain description, and the runner
-- counts and reports from those lines alone, the same convention every other case file
-- already follows.
--
-- The module is a configured singleton rather than a factory, so every block below still
-- loads its own fresh copy with loadfile, the same isolation cases/registry.lua keeps for its
-- own factory, only here a fresh copy is a fresh singleton rather than a fresh instance of
-- one. A refusal to configure is proven by the raise itself, and a dropped binding is proven
-- two ways, what verbsIn actually kept and the line it would have logged, read directly out of
-- a small stub answering w(message) rather than out of hs.logger's own global, shared,
-- process wide history, which is not this file's to own.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local modulePath = caseDir .. "/../../Spoons/Olm.spoon/host/actionpanel/init.lua"

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
    error("could not load Olm.spoon/host/actionpanel/init.lua, " .. tostring(err))
  end
  local ap = chunk()
  ap:init()
  return ap
end

local function found(warnings, needle)
  for _, message in ipairs(warnings) do
    if message:find(needle, 1, true) then return true end
  end
  return false
end

-- configure requires deps.kindOf, a function, the same readable error registry.lua raises for
-- its own required opts.apiVersion. Both a missing value and one that is not a function reach
-- the same raise, so both are checked against it rather than as two refusals pretending to
-- distinguish something the module itself does not.
do
  local ap = freshModule()
  local calledOk, err = pcall(function() ap:configure({}) end)
  check(
    "configure with no deps.kindOf raises a readable error",
    calledOk == false and type(err) == "string" and #err > 0,
    "pcall returned ok=" .. tostring(calledOk) .. " err=" .. tostring(err)
  )

  local calledOk2, err2 = pcall(function() ap:configure({ kindOf = "not a function" }) end)
  check(
    "configure with a deps.kindOf that is not a function raises the same way",
    calledOk2 == false and type(err2) == "string" and #err2 > 0,
    "pcall returned ok=" .. tostring(calledOk2) .. " err=" .. tostring(err2)
  )
end

-- A binding whose action classifies as a verb is kept, in the shape it was given.
do
  local ap = freshModule()
  ap:configure({ kindOf = function(action)
    if action == "browseInto" then return ap.kinds.verb end
    return nil
  end })
  local bindings = { { key = "l", action = "browseInto", description = "Into folder" } }
  local kept = ap:verbsIn(bindings)
  check(
    "a binding whose action classifies as a verb is kept",
    #kept == 1 and kept[1].action == "browseInto" and kept[1].description == "Into folder"
  )
end

-- A binding whose action classifies as navigation is dropped in silence, the entire point of
-- this function.
do
  local ap = freshModule()
  local warnings = {}
  local log = { w = function(message) warnings[#warnings + 1] = message end }
  ap:configure({ log = log, kindOf = function(action)
    if action == "selectNext" then return ap.kinds.navigation end
    return nil
  end })
  local bindings = { { key = "j", action = "selectNext", description = "Move down" } }
  local kept = ap:verbsIn(bindings)
  check("a binding whose action classifies as navigation is dropped", #kept == 0)
  check("navigation is dropped without a warning, unlike an unclassified action", #warnings == 0)
end

-- Declaration order survives the filter, a mix of kept and dropped bindings answering in the
-- order they were given rather than in the order the policy table happens to hold them.
do
  local ap = freshModule()
  local kinds = {
    appendSelected = ap.kinds.verb,
    selectNext = ap.kinds.navigation,
    deleteSelected = ap.kinds.verb,
    sortByLoad = ap.kinds.verb,
  }
  ap:configure({ kindOf = function(action) return kinds[action] end })
  local bindings = {
    { key = "a", action = "appendSelected" },
    { key = "j", action = "selectNext" },
    { key = "d", action = "deleteSelected" },
    { key = "s", action = "sortByLoad" },
  }
  local kept = ap:verbsIn(bindings)
  check(
    "declaration order survives the filter across the kept bindings",
    #kept == 3 and kept[1].action == "appendSelected" and kept[2].action == "deleteSelected"
      and kept[3].action == "sortByLoad"
  )
end

-- An unclassified action, deps.kindOf answering nil, is dropped and costs one warning naming
-- the action, read back through the injected log rather than through hs.logger's own history.
do
  local ap = freshModule()
  local warnings = {}
  local log = { w = function(message) warnings[#warnings + 1] = message end }
  ap:configure({ log = log, kindOf = function() return nil end })
  local bindings = { { key = "q", action = "mysteryAction" } }
  local kept = ap:verbsIn(bindings)
  check("an action deps.kindOf answers nil for is dropped", #kept == 0)
  check(
    "the drop costs one warning naming the action, read back through the injected log",
    found(warnings, "mysteryAction"),
    table.concat(warnings, " | ")
  )
end

-- An action classified as something outside obj.kinds, neither verb nor navigation, is treated
-- the same as an unclassified one, dropped and named in a warning.
do
  local ap = freshModule()
  local warnings = {}
  local log = { w = function(message) warnings[#warnings + 1] = message end }
  ap:configure({ log = log, kindOf = function() return "neitherKind" end })
  local bindings = { { key = "q", action = "mysteryAction" } }
  local kept = ap:verbsIn(bindings)
  check("an action classified as something outside obj.kinds is dropped the same way as nil", #kept == 0)
  check(
    "the drop names the action even though deps.kindOf answered something rather than nil",
    found(warnings, "mysteryAction"),
    table.concat(warnings, " | ")
  )
end

-- The list handed to verbsIn is never mutated, whatever the filter decides, since the caller
-- may be holding the very table config/keys.lua built.
do
  local ap = freshModule()
  ap:configure({ kindOf = function(action)
    if action == "browseUp" then return ap.kinds.verb end
    return ap.kinds.navigation
  end })
  local original = {
    { key = "h", action = "browseUp" },
    { key = "j", action = "selectNext" },
  }
  local originalLength = #original
  ap:verbsIn(original)
  check("the list handed to verbsIn keeps its own length afterward", #original == originalLength)
  check(
    "the list handed to verbsIn keeps its own entries and their own order afterward",
    original[1].action == "browseUp" and original[2].action == "selectNext"
  )
end

-- kindOf on a configured module answers the injected classifier's own answer for one action
-- name, the public door test/inventory.lua reads the live wiring through.
do
  local ap = freshModule()
  ap:configure({ kindOf = function(action)
    if action == "browseInto" then return ap.kinds.verb end
    return ap.kinds.navigation
  end })
  check("kindOf on a configured module answers the injected classifier's own answer", ap:kindOf("browseInto") == ap.kinds.verb)
  check("kindOf on a configured module answers it for every action, not only a verb", ap:kindOf("selectNext") == ap.kinds.navigation)
end

-- verbsIn asked before configure has ever run answers an empty list rather than raising the
-- nil call error self._kindOf() would otherwise produce, and it warns naming itself and the
-- caller rather than failing in silence. The log is set directly on the fresh module here,
-- never through configure, since configure is exactly the call this case must not make, and
-- ap.kinds.verb still resolves fine since obj.kinds is set at module load rather than by it.
do
  local ap = freshModule()
  local warnings = {}
  ap._log = { w = function(message) warnings[#warnings + 1] = message end }
  local kept = ap:verbsIn({ { key = "j", action = "selectNext" } })
  check("verbsIn asked before configure ran answers an empty list rather than raising", #kept == 0)
  check(
    "verbsIn asked before configure ran warns naming itself and the module as unconfigured",
    found(warnings, "verbsIn") and found(warnings, "ActionPanel"),
    table.concat(warnings, " | ")
  )
end

-- kindOf asked before configure has ever run answers nil the same way, sharing the exact same
-- guard verbsIn above just exercised rather than carrying a second copy of it.
do
  local ap = freshModule()
  local warnings = {}
  ap._log = { w = function(message) warnings[#warnings + 1] = message end }
  local kind = ap:kindOf("selectNext")
  check("kindOf asked before configure ran answers nil rather than raising", kind == nil)
  check(
    "kindOf asked before configure ran warns naming itself and the module as unconfigured",
    found(warnings, "kindOf") and found(warnings, "ActionPanel"),
    table.concat(warnings, " | ")
  )
end
