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
-- whatever verbs a block below wants to check. Verbs are written in the real shape
-- lib/registry.lua now requires, a table carrying fn plus a required closes, since that is
-- what a live scope actually holds, closes already validated to a real boolean by the time
-- it ever reaches this module.
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

-- verbFor answers a callable for a declared verb, plus its own declared closes, and calling
-- the callable runs the underlying function against the row's own payload, the same pcall
-- wrapped shape actFor already answers in.
do
  local qs = freshModule()
  local seen
  qs:configure({ scopes = { fileSearchLikeScope({
    revealInFinder = { fn = function(payload) seen = payload end, closes = true },
  }) } })
  local item = { kind = "scope", scope = "fileSearch", payload = { path = "/tmp/x" } }
  local verb, closes = qs:verbFor(item, "revealInFinder")
  check("verbFor answers a callable for a declared verb", type(verb) == "function")
  check("verbFor answers the verb's own declared closes", closes == true)
  verb()
  check(
    "calling the answer runs the verb against the row's own payload",
    seen ~= nil and seen.path == "/tmp/x"
  )
end

-- verbFor answers a verb's own closes exactly as declared, true and false alike, so a caller
-- reading it never has to guess or assume a default.
do
  local qs = freshModule()
  qs:configure({ scopes = { fileSearchLikeScope({
    revealInFinder = { fn = function() end, closes = true },
    peekPreview = { fn = function() end, closes = false },
  }) } })
  local item = { kind = "scope", scope = "fileSearch", payload = {} }
  local _, closesReveal = qs:verbFor(item, "revealInFinder")
  local _, closesPeek = qs:verbFor(item, "peekPreview")
  check("a verb declared closing answers closes true", closesReveal == true)
  check("a verb declared not closing answers closes false", closesPeek == false)
end

-- verbFor answers nil for an action the scope never declared a verb for, a legitimate
-- absence rather than a mistake.
do
  local qs = freshModule()
  qs:configure({ scopes = { fileSearchLikeScope({
    revealInFinder = { fn = function() end, closes = true },
  }) } })
  local item = { kind = "scope", scope = "fileSearch", payload = { path = "/tmp/x" } }
  check("verbFor answers nil for an undeclared action", qs:verbFor(item, "copyPath") == nil)
end

-- verbFor answers nil for a row that is not a scope row at all. An app row from the
-- launcher's own catalog carries no payload, and a scope row naming an unknown scope
-- answers the same nil _scopeOf already gives run, peek, redirect, and act.
do
  local qs = freshModule()
  qs:configure({ scopes = { fileSearchLikeScope({
    revealInFinder = { fn = function() end, closes = true },
  }) } })
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

-- A scope built by hand outside the registry, the one place this module cannot lean on
-- lib/registry.lua's own refusal, may still spell a verb as a bare function carrying no
-- closes at all. verbFor still runs it, since a callable is a callable, but never answers
-- closes true for it, coercing the missing declaration to false rather than to nil, since a
-- caller asking this needs one answer or the other and nil reads as neither.
do
  local qs = freshModule()
  qs:configure({ scopes = { fileSearchLikeScope({
    revealInFinder = function() end,
  }) } })
  local item = { kind = "scope", scope = "fileSearch", payload = {} }
  local verb, closes = qs:verbFor(item, "revealInFinder")
  check("a bare function verb still answers a callable", type(verb) == "function")
  check("a bare function verb, declaring no closes, coerces to closes false rather than nil", closes == false)
end

-- A verb that raises costs a console line rather than a broken caller, mirroring actFor.
do
  local qs = freshModule()
  qs:configure({ scopes = { fileSearchLikeScope({
    revealInFinder = { fn = function() error("boom") end, closes = true },
  }) } })
  local item = { kind = "scope", scope = "fileSearch", payload = {} }
  local verb = qs:verbFor(item, "revealInFinder")
  local ok = pcall(verb)
  check("calling the answer never raises even when the verb itself does", ok == true)
end

-- The composition root's own run prefers a scope's declared verb over its ordinary action
-- table, closes the chooser only when the verb's own closes says so, and falls through to
-- the action table only when verbFor answers nil. This reproduces that exactly, against this
-- module's own real verbFor, since init.lua's own run closure cannot be dofiled on its own.
--
-- verb and closes are read from an if rather than from `item and qs:verbFor(item, action)` on
-- one line, because and truncates a multiple return down to one value the moment it sits
-- inside a larger expression, which would make closes answer nil forever, silently, the exact
-- shape of mistake this phase's own hazards warn about.
do
  local qs = freshModule()
  qs:configure({ scopes = { fileSearchLikeScope({
    revealInFinder = { fn = function() end, closes = true },
    peekPreview = { fn = function() end, closes = false },
  }) } })
  local ran = {}
  local contextActions = {
    revealInFinder = function() error("the fallback ran, the declared verb should have") end,
    peekPreview = function() error("the fallback ran, the declared verb should have") end,
    copyPath = function() ran[#ran + 1] = "fallback" end,
    closeChooser = function() ran[#ran + 1] = "closed" end,
  }
  local function run(action, item)
    local verb, closes
    if item then
      verb, closes = qs:verbFor(item, action)
    end
    if verb then
      verb()
      ran[#ran + 1] = "verb"
      if closes then contextActions.closeChooser() end
      return
    end
    local fn = contextActions[action]
    if fn then fn() end
  end

  run("revealInFinder", { kind = "scope", scope = "fileSearch", payload = {} })
  check(
    "a declared verb that closes runs and closes the chooser afterward",
    ran[1] == "verb" and ran[2] == "closed"
  )

  ran = {}
  run("peekPreview", { kind = "scope", scope = "fileSearch", payload = {} })
  check(
    "a declared verb that does not close runs without closing anything",
    ran[1] == "verb" and ran[2] == nil
  )

  ran = {}
  run("copyPath", { kind = "scope", scope = "fileSearch", payload = {} })
  check("an undeclared action falls through to the ordinary action table", ran[1] == "fallback")

  ran = {}
  run("copyPath", nil)
  check("a nil item, an ordinary row with no scope at all, falls through the same way", ran[1] == "fallback")
end

-- The composition root's own hosted rowsFor keeps a verb row only when the tool's own verbs
-- table declares that action at all, a presence check rather than a shape check, since
-- lib/registry.lua already refuses every shape but a table carrying fn plus a required closes
-- by the time anything registers, so checking the shape a second time here would be a third
-- place in the tree that knows what a verb entry looks like. It qualifies the kept row's chord
-- with the tool's own description so it never claims a chord that only works elsewhere, and
-- carries the verb's own closes straight off the same table the presence check just found,
-- guaranteed by the registry to be a real boolean by now. This asks the verbs table directly
-- rather than through verbFor, since rowsFor would otherwise have to build a scope row for
-- every context to ask, and eleven of the twelve name no scope at all, which would log
-- verbFor's own unknown scope warning on every one of them for a question that is presentation
-- only and never touches a real row.
do
  local qs = freshModule()
  local verbs = {
    revealInFinder = { fn = function() end, closes = true },
    copyPath = { fn = function() end, closes = true },
  }
  qs:configure({ scopes = { fileSearchLikeScope(verbs) } })
  local bindings = {
    { action = "revealInFinder", chord = "Hyper+O" },
    { action = "browseInto", chord = "Hyper+L" },
  }
  local function hostedVerbDeclared(action)
    return verbs ~= nil and verbs[action] ~= nil
  end
  local function hostedRows(description)
    local out = {}
    for _, b in ipairs(bindings) do
      if hostedVerbDeclared(b.action) then
        out[#out + 1] = { action = b.action, chord = b.chord .. " in " .. description, closes = verbs[b.action].closes }
      end
    end
    return out
  end
  local rows = hostedRows("File search")
  check(
    "a hosted row list keeps only the actions the scope declared a verb for",
    #rows == 1 and rows[1].action == "revealInFinder"
  )
  check(
    "a kept row's chord is qualified with the tool's own description",
    rows[1].chord == "Hyper+O in File search"
  )
  check("a kept row carries the verb's own closes", rows[1].closes == true)

  local item = { kind = "scope", scope = "fileSearch", payload = {} }
  check(
    "the presence check agrees with this module's own verbFor for a declared action",
    (qs:verbFor(item, "revealInFinder") ~= nil) == hostedVerbDeclared("revealInFinder")
  )
  check(
    "the presence check agrees with this module's own verbFor for an undeclared action",
    (qs:verbFor(item, "browseInto") ~= nil) == hostedVerbDeclared("browseInto")
  )
end
