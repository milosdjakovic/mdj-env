-- Unit case for Olm.spoon/host/queryscope/init.lua, the alias grammar that scopes a query
-- driven list down to one tool. The runner reaches this file with a dofile call carrying
-- an absolute path, so this file in turn locates itself the same way, through
-- debug.getinfo, and derives the module path from there.
--
-- Only verbFor is covered here, phase eight's fourth packet. It is the one piece of this
-- module with no live hs.chooser, no clipboard, and no file system behind it, so it is the
-- one piece a pure Lua case can prove without a live Hammerspoon driving the rest of it.
-- Everything else this module does is already exercised live, through
-- test/inventory.lua's own scopes section and the console notes this module's own
-- CLAUDE.md already records.
--
-- Two patterns the composition root builds on top of verbFor, preferring a declared verb
-- over the ordinary action table and keeping only a hosted row whose action the scope
-- actually declared, are reproduced here too, against this module's own real verbFor
-- rather than a stand in, since init.lua's own closures cannot be dofiled in isolation.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local modulePath = caseDir .. "/../../Spoons/Olm.spoon/host/queryscope/init.lua"

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
    error("could not load Olm.spoon/host/queryscope/init.lua, " .. tostring(err))
  end
  return chunk():init()
end

-- A minimal admissible scope, rows and run present since QueryScope requires both, plus
-- whatever verbs a block below wants to check.
local function fileSearchLikeScope(verbs)
  return {
    name = "fileSearch",
    title = "File search",
    aliases = { "/" },
    rows = function() return {} end,
    run = function() end,
    verbs = verbs,
  }
end

-- verbFor answers a callable for a declared verb, and calling it runs the underlying
-- function against the row's own payload, the same pcall wrapped shape actFor already
-- answers in.
do
  local qs = freshModule()
  local seen
  qs:configure({ scopes = { fileSearchLikeScope({
    revealInFinder = function(payload) seen = payload end,
  }) } })
  local item = { kind = "scope", scope = "fileSearch", payload = { path = "/tmp/x" } }
  local verb = qs:verbFor(item, "revealInFinder")
  check("verbFor answers a callable for a declared verb", type(verb) == "function")
  verb()
  check(
    "calling the answer runs the verb against the row's own payload",
    seen ~= nil and seen.path == "/tmp/x"
  )
end

-- verbFor answers nil for an action the scope never declared a verb for, a legitimate
-- absence rather than a mistake.
do
  local qs = freshModule()
  qs:configure({ scopes = { fileSearchLikeScope({ revealInFinder = function() end }) } })
  local item = { kind = "scope", scope = "fileSearch", payload = { path = "/tmp/x" } }
  check("verbFor answers nil for an undeclared action", qs:verbFor(item, "copyPath") == nil)
end

-- verbFor answers nil for a row that is not a scope row at all. An app row from the
-- launcher's own catalog carries no payload, and a scope row naming an unknown scope
-- answers the same nil _scopeOf already gives run, peek, redirect, and act.
do
  local qs = freshModule()
  qs:configure({ scopes = { fileSearchLikeScope({ revealInFinder = function() end }) } })
  check(
    "verbFor answers nil for a row with no payload",
    qs:verbFor({ kind = "app", bundleID = "com.example.app" }, "revealInFinder") == nil
  )
  check(
    "verbFor answers nil for a scope row naming an unknown scope",
    qs:verbFor({ kind = "scope", scope = "noSuchScope", payload = {} }, "revealInFinder") == nil
  )
end

-- verbFor answers nil when the scope declares no verbs at all, the ordinary case every
-- scope but file search's own is in.
do
  local qs = freshModule()
  qs:configure({ scopes = { fileSearchLikeScope(nil) } })
  local item = { kind = "scope", scope = "fileSearch", payload = {} }
  check("verbFor answers nil for a scope that declares no verbs", qs:verbFor(item, "revealInFinder") == nil)
end

-- A verb that raises costs a console line rather than a broken caller, mirroring actFor.
do
  local qs = freshModule()
  qs:configure({ scopes = { fileSearchLikeScope({
    revealInFinder = function() error("boom") end,
  }) } })
  local item = { kind = "scope", scope = "fileSearch", payload = {} }
  local verb = qs:verbFor(item, "revealInFinder")
  local ok = pcall(verb)
  check("calling the answer never raises even when the verb itself does", ok == true)
end

-- The composition root's own run prefers a scope's declared verb over its ordinary
-- action table, and falls through to that table only when verbFor answers nil. This
-- reproduces that one line exactly, against this module's own real verbFor, since
-- init.lua's own run closure cannot be dofiled on its own.
do
  local qs = freshModule()
  qs:configure({ scopes = { fileSearchLikeScope({ revealInFinder = function() end }) } })
  local ran = {}
  local contextActions = {
    revealInFinder = function() error("the fallback ran, the declared verb should have") end,
    copyPath = function() ran[#ran + 1] = "fallback" end,
  }
  local function run(action, item)
    local verb = item and qs:verbFor(item, action)
    if verb then
      verb()
      ran[#ran + 1] = "verb"
      return
    end
    local fn = contextActions[action]
    if fn then fn() end
  end

  run("revealInFinder", { kind = "scope", scope = "fileSearch", payload = {} })
  check("a declared verb runs instead of the fallback", ran[1] == "verb")

  ran = {}
  run("copyPath", { kind = "scope", scope = "fileSearch", payload = {} })
  check("an undeclared action falls through to the ordinary action table", ran[1] == "fallback")

  ran = {}
  run("copyPath", nil)
  check("a nil item, an ordinary row with no scope at all, falls through the same way", ran[1] == "fallback")
end

-- The composition root's own hosted rowsFor keeps a verb row only when verbFor would
-- answer non nil for it, and qualifies its chord with the tool's own description so the
-- row never claims a chord that only works elsewhere. Reproduced against this module's
-- own real verbFor for the same reason as the block above.
do
  local qs = freshModule()
  qs:configure({ scopes = { fileSearchLikeScope({
    revealInFinder = function() end,
    copyPath = function() end,
  }) } })
  local bindings = {
    { action = "revealInFinder", chord = "Hyper+O" },
    { action = "browseInto", chord = "Hyper+L" },
  }
  local function hostedRows(contextName, description)
    local out = {}
    for _, b in ipairs(bindings) do
      local item = { kind = "scope", scope = contextName, payload = {} }
      if qs:verbFor(item, b.action) then
        out[#out + 1] = { action = b.action, chord = b.chord .. " in " .. description }
      end
    end
    return out
  end
  local rows = hostedRows("fileSearch", "File search")
  check(
    "a hosted row list keeps only the actions the scope declared a verb for",
    #rows == 1 and rows[1].action == "revealInFinder"
  )
  check(
    "a kept row's chord is qualified with the tool's own description",
    rows[1].chord == "Hyper+O in File search"
  )
end
