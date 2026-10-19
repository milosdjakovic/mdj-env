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

-- Refusal one, no name, or a name that is not a string. One line in the module covers
-- both, its name is missing or is not a string, so both cases below are checked against
-- that same one line rather than two checks pretending to distinguish something the log
-- itself does not.
do
  local r, warnings = freshRegistry(1)

  local ok = r.register({ apiVersion = 1, open = function() end })
  check("a descriptor with no name is refused", ok == false)

  local ok2 = r.register({ name = 42, apiVersion = 1, open = function() end })
  check("a descriptor whose name is not a string is refused", ok2 == false)

  check(
    "both refusals above logged the one line covering a missing or non string name",
    found(warnings, "name is missing"),
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

-- Refusal three, a descriptor still carrying commands. Commands retired in phase 2b of the keymap
-- plan, since an action descriptor in a plugin's provides.actions is the one way to declare
-- something runnable, and a tool registered without the rows and keys its commands declared would
-- be the quieter failure, so the whole descriptor is refused, naming the tool and what replaced
-- them, and nothing about it is committed.
do
  local r, warnings = freshRegistry(1)
  local calls = {}
  local ok = r.register({ name = "clipboard", apiVersion = 1,
    open = function() calls[#calls + 1] = "open" end,
    commands = { appendCopy = function() calls[#calls + 1] = "appendCopy" end } })
  check("a descriptor carrying commands is refused", ok == false)
  check(
    "the refusal names the tool and says an action descriptor replaces its commands",
    found(warnings, "clipboard") and found(warnings, "provides.actions"),
    table.concat(warnings, " | ")
  )
  r.activate({ "clipboard" })
  check("nothing about the refused descriptor was committed, run answers false",
    r.run("clipboard") == false and r.run("appendCopy") == false and #calls == 0)
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

-- activate answers to the same refuse rather than raise principle register does. A
-- setting holding the wrong shape, a string rather than a list, must not raise out of
-- config load, which would take down the whole of Hammerspoon rather than only the
-- launcher.
do
  local r, warnings = freshRegistry(1)
  r.register({ name = "vpn", apiVersion = 1, open = function() end })
  r.activate({ "vpn" })
  check("vpn is active before the malformed activate call", r.get("vpn") ~= nil)

  local calledOk = pcall(function() r.activate("not-a-list") end)
  check("activate given a string rather than a table does not raise", calledOk == true)
  check(
    "the refusal for a non table activation list is logged, naming what it got",
    found(warnings, "not-a-list"),
    table.concat(warnings, " | ")
  )
  check("the active set is left empty rather than keeping the previous activation", r.get("vpn") == nil)
end

-- Inactive answers, a registered tool left out of the activation list.
do
  local r = freshRegistry(1)
  r.register({ name = "vpn", apiVersion = 1, hosted = true, open = function() end, surface = function() end })
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

  local byName = {}
  for _, tool in ipairs(all) do byName[tool.name] = tool end
  check(
    "all reports surface presence and the hosted flag for the tool that declared both",
    byName.vpn.active == true and byName.vpn.surface == true and byName.vpn.hosted == true
  )
  check(
    "all reports surface absence and hosted false for the tool that declared neither",
    byName.emoji.active == false and byName.emoji.surface == false and byName.emoji.hosted == false
  )
end

-- Refusal, a surface that is present and is not a function. This is the guard the
-- ordering hazard section of the second packet asks for, since a surface handed in
-- already built rather than as a closure is exactly the mistake that discipline exists
-- to catch.
do
  local r, warnings = freshRegistry(1)
  local ok = r.register({ name = "emoji", apiVersion = 1, surface = { isShowing = function() return false end } })
  check("a descriptor whose surface is present and is not a function is refused", ok == false)
  check(
    "the refusal names the tool and says its surface is not a function",
    found(warnings, "emoji") and found(warnings, "is not a function"),
    table.concat(warnings, " | ")
  )
end

-- Refusal, a row that is present and is not a table, the third packet's guard on the
-- tool's own launcher row.
do
  local r, warnings = freshRegistry(1)
  local ok = r.register({ name = "displayProfiles", apiVersion = 1, row = "Displays" })
  check("a descriptor whose row is present and is not a table is refused", ok == false)
  check(
    "the refusal names the tool and says its row is not a table",
    found(warnings, "displayProfiles") and found(warnings, "is not a table"),
    table.concat(warnings, " | ")
  )
end

-- Refusal, a row that is present and has no category, since a subtitle with no
-- category would render wrong rather than absent.
do
  local r, warnings = freshRegistry(1)
  local ok = r.register({ name = "textCase", apiVersion = 1, row = { detail = "recase the selection in place" } })
  check("a descriptor whose row has no category is refused", ok == false)
  check(
    "the refusal names the tool and says its row has no category",
    found(warnings, "textCase") and found(warnings, "has no category"),
    table.concat(warnings, " | ")
  )
end

-- rowFor, a tool's own row, resolved only while the tool is active.
do
  local r = freshRegistry(1)
  r.register({ name = "vpn", apiVersion = 1, open = function() end, row = { category = "Network" } })
  check("rowFor answers nil for a registered but inactive tool", r.rowFor("vpn") == nil)

  r.activate({ "vpn" })
  local row = r.rowFor("vpn")
  check(
    "rowFor answers the tool's own row once it is active",
    row ~= nil and row.category == "Network"
  )
end

-- rowFor, a name nothing registered.
do
  local r = freshRegistry(1)
  check("rowFor answers nil for a name nothing registered", r.rowFor("noSuchTool") == nil)
end

-- Refusal, a scope that is present and is not a table, phase seven's fourth packet.
do
  local r, warnings = freshRegistry(1)
  local ok = r.register({ name = "caffeinate", apiVersion = 1, scope = "not a table" })
  check("a descriptor whose scope is present and is not a table is refused", ok == false)
  check(
    "the refusal names the tool and says its scope is not a table",
    found(warnings, "caffeinate") and found(warnings, "is not a table"),
    table.concat(warnings, " | ")
  )
end

-- Refusal, a scope present with no rows function, or with a rows that is not a function.
-- One line in the module covers both, so both are checked against it rather than as two
-- refusals pretending to distinguish something the log itself does not.
do
  local r, warnings = freshRegistry(1)
  local ok = r.register({ name = "vpn", apiVersion = 1, scope = { run = function() end } })
  check("a scope with no rows function is refused", ok == false)
  check(
    "the refusal names the tool and says its scope has no rows function",
    found(warnings, "vpn") and found(warnings, "no rows function"),
    table.concat(warnings, " | ")
  )

  local ok2 = r.register({ name = "browserTabs", apiVersion = 1, scope = { rows = "not a function", run = function() end } })
  check("a scope whose rows is present and is not a function is refused the same way", ok2 == false)
end

-- Refusal, a scope present with no run function, or with a run that is not a function.
do
  local r, warnings = freshRegistry(1)
  local ok = r.register({ name = "dockAutoHide", apiVersion = 1, scope = { rows = function() end } })
  check("a scope with no run function is refused", ok == false)
  check(
    "the refusal names the tool and says its scope has no run function",
    found(warnings, "dockAutoHide") and found(warnings, "no run function"),
    table.concat(warnings, " | ")
  )

  local ok2 = r.register({ name = "fileSearch", apiVersion = 1, scope = { rows = function() end, run = "not a function" } })
  check("a scope whose run is present and is not a function is refused the same way", ok2 == false)
end

-- A scope's matcher is the one field that is not a function, false on four scopes today,
-- so false is accepted and anything else that is not a function is refused.
do
  local r = freshRegistry(1)
  local ok = r.register({
    name = "caffeinate", apiVersion = 1,
    scope = { rows = function() end, run = function() end, matcher = false },
  })
  check("a scope whose matcher is false registers", ok == true)
end

do
  local r, warnings = freshRegistry(1)
  local ok = r.register({
    name = "vpn", apiVersion = 1,
    scope = { rows = function() end, run = function() end, matcher = "not false or a function" },
  })
  check("a scope whose matcher is neither false nor a function is refused", ok == false)
  check(
    "the refusal names the tool and says its scope's matcher is neither false nor a function",
    found(warnings, "vpn") and found(warnings, "neither false nor a function"),
    table.concat(warnings, " | ")
  )
end

-- Refusal, a scope's peek, redirect, or act present and not a function, each its own
-- registration so one bad field cannot hide behind another.
do
  local r, warnings = freshRegistry(1)
  local ok = r.register({
    name = "fileSearch", apiVersion = 1,
    scope = { rows = function() end, run = function() end, peek = "not a function" },
  })
  check("a scope whose peek is present and is not a function is refused", ok == false)
  check(
    "the refusal names the tool and says its scope's peek is not a function",
    found(warnings, "fileSearch") and found(warnings, "peek is present and is not a function"),
    table.concat(warnings, " | ")
  )
end

do
  local r, warnings = freshRegistry(1)
  local ok = r.register({
    name = "aliasDirectory", apiVersion = 1,
    scope = { rows = function() end, run = function() end, redirect = "not a function" },
  })
  check("a scope whose redirect is present and is not a function is refused", ok == false)
  check(
    "the refusal names the tool and says its scope's redirect is not a function",
    found(warnings, "aliasDirectory") and found(warnings, "redirect is present and is not a function"),
    table.concat(warnings, " | ")
  )
end

do
  local r, warnings = freshRegistry(1)
  local ok = r.register({
    name = "dockAutoHide", apiVersion = 1,
    scope = { rows = function() end, run = function() end, act = "not a function" },
  })
  check("a scope whose act is present and is not a function is refused", ok == false)
  check(
    "the refusal names the tool and says its scope's act is not a function",
    found(warnings, "dockAutoHide") and found(warnings, "act is present and is not a function"),
    table.concat(warnings, " | ")
  )
end

-- Refusal, a scope's verbs present and not a table, phase eight's fourth packet.
do
  local r, warnings = freshRegistry(1)
  local ok = r.register({
    name = "fileSearch", apiVersion = 1,
    scope = { rows = function() end, run = function() end, verbs = "not a table" },
  })
  check("a scope whose verbs is present and is not a table is refused", ok == false)
  check(
    "the refusal names the tool and says its scope's verbs is not a table",
    found(warnings, "fileSearch") and found(warnings, "verbs is present and is not a table"),
    table.concat(warnings, " | ")
  )
end

-- Refusal, a scope's verbs entry that is neither a bare function nor a table with a callable
-- fn, naming the tool and the action.
do
  local r, warnings = freshRegistry(1)
  local ok = r.register({
    name = "fileSearch", apiVersion = 1,
    scope = { rows = function() end, run = function() end,
      verbs = { revealInFinder = { fn = function() end, closes = true }, copyPath = "not a function or a table" } },
  })
  check("a scope whose verbs entry is neither a function nor a table with a callable fn is refused", ok == false)
  check(
    "the refusal names the tool and the action whose verb is the wrong shape",
    found(warnings, "fileSearch") and found(warnings, "copyPath"),
    table.concat(warnings, " | ")
  )
end

-- Refusal, a verbs entry that declares neither, a bare function carrying no closes at all,
-- since closes has no default and a verb that never says whether it closes is refused rather
-- than guessed at.
do
  local r, warnings = freshRegistry(1)
  local ok = r.register({
    name = "fileSearch", apiVersion = 1,
    scope = { rows = function() end, run = function() end,
      verbs = { revealInFinder = function() end } },
  })
  check("a verbs entry spelled as a bare function, declaring no closes, is refused", ok == false)
  check(
    "the refusal names the tool, the action, and says it does not say whether it closes the list",
    found(warnings, "fileSearch") and found(warnings, "revealInFinder")
      and found(warnings, "does not say whether it closes the list"),
    table.concat(warnings, " | ")
  )
end

-- Refusal, a verbs entry whose table carries a callable fn but a closes that is present and
-- not a boolean, the second way to declare neither.
do
  local r, warnings = freshRegistry(1)
  local ok = r.register({
    name = "fileSearch", apiVersion = 1,
    scope = { rows = function() end, run = function() end,
      verbs = { copyPath = { fn = function() end, closes = "not a boolean" } } },
  })
  check("a verbs entry whose closes is present and is not a boolean is refused", ok == false)
  check(
    "the refusal names the tool, the action, and says it does not say whether it closes the list",
    found(warnings, "fileSearch") and found(warnings, "copyPath")
      and found(warnings, "does not say whether it closes the list"),
    table.concat(warnings, " | ")
  )
end

-- A verb declared as closing, and a verb declared as not closing, both register, side by side
-- so one true and one false are both proven rather than only the one that happens to be
-- truthy.
do
  local r = freshRegistry(1)
  local ok = r.register({
    name = "fileSearch", apiVersion = 1,
    scope = { rows = function() end, run = function() end,
      verbs = {
        revealInFinder = { fn = function() end, closes = true },
        peekPreview = { fn = function() end, closes = false },
      } },
  })
  check("a scope whose verbs each state their own closes, true and false alike, registers", ok == true)
end

-- A well formed scope registers, with matcher, peek, redirect, and act all present.
do
  local r = freshRegistry(1)
  local ok = r.register({
    name = "fileSearch", apiVersion = 1,
    scope = {
      matcher = false,
      rows = function() end,
      run = function() end,
      peek = function() end,
      redirect = function() end,
      act = function() end,
    },
  })
  check("a fully formed scope with every optional field present registers", ok == true)
end

-- scopeFor, a tool's own scope, resolved only while the tool is active, and nil for an
-- unknown name, mirroring rowFor exactly.
do
  local r = freshRegistry(1)
  local rows = function() end
  local run = function() end
  r.register({ name = "vpn", apiVersion = 1, scope = { rows = rows, run = run } })
  check("scopeFor answers nil for a registered but inactive tool", r.scopeFor("vpn") == nil)

  r.activate({ "vpn" })
  local scope = r.scopeFor("vpn")
  check(
    "scopeFor answers the tool's own scope once it is active",
    scope ~= nil and scope.rows == rows and scope.run == run
  )

  check("scopeFor answers nil for a name nothing registered", r.scopeFor("noSuchTool") == nil)
end

-- all() reports scope presence beside surface and hosted, the cross check this packet
-- adds so a tool that is hosted with no scope behind it is visible in a committed file
-- rather than caught only by a warning nobody is watching for.
do
  local r = freshRegistry(1)
  r.register({
    name = "emoji", apiVersion = 1, hosted = true,
    open = function() end,
    scope = { rows = function() end, run = function() end },
  })
  r.register({ name = "colorPicker", apiVersion = 1, open = function() end })
  r.activate({ "emoji", "colorPicker" })

  local all = r.all()
  local byName = {}
  for _, tool in ipairs(all) do byName[tool.name] = tool end
  check(
    "all reports scope presence true for the tool that declared one",
    byName.emoji.scope == true and byName.emoji.hosted == true
  )
  check(
    "all reports scope presence false for the tool that declared none",
    byName.colorPicker.scope == false
  )
end

-- scopes(spec), a name nothing registered is skipped and logs one warning naming it, the
-- same mistake surfaces(spec) warns about for the same reason.
do
  local r, warnings = freshRegistry(1)
  local out = r.scopes({ "noSuchTool" })
  check("an unknown name in a scopes spec contributes nothing", #out == 0)
  check(
    "an unknown name in a scopes spec is warned about by name",
    found(warnings, "noSuchTool"),
    table.concat(warnings, " | ")
  )
end

-- scopes(spec), a registered but inactive tool's scope is skipped with no warning at
-- all, since that is what inactive already means everywhere else in this module.
do
  local r, warnings = freshRegistry(1)
  r.register({ name = "vpn", apiVersion = 1, scope = { rows = function() end, run = function() end } })
  -- vpn is registered but never activated.
  local out = r.scopes({ "vpn" })
  check("an inactive tool's scope contributes nothing to the list", #out == 0)
  check("an inactive tool's scope is skipped without logging anything", #warnings == 0)
end

-- scopes(spec), an active tool that declared no scope is a different silence than an
-- unregistered name, the emoji case this packet protects, a scope registering only
-- under a condition that did not hold this run, so nothing is logged for it either.
do
  local r, warnings = freshRegistry(1)
  r.register({ name = "colorPicker", apiVersion = 1, open = function() end })
  r.activate({ "colorPicker" })
  local out = r.scopes({ "colorPicker" })
  check("an active tool with no scope contributes nothing to the list", #out == 0)
  check("an active tool with no scope is skipped without logging anything", #warnings == 0)
end

-- scopes(spec), a resolved tool answers a table carrying both name and opts, since
-- joining the identity fields from the manifest defaults and config/plugins.lua stays the root's own scope(name,
-- opts) helper's job, and a non string entry passes straight through untouched, in the
-- order the spec gave, mixed with the resolved tool.
do
  local r = freshRegistry(1)
  local rows = function() end
  local run = function() end
  r.register({ name = "vpn", apiVersion = 1, scope = { matcher = false, rows = rows, run = run } })
  r.activate({ "vpn" })

  local passthrough = { name = "apps", title = "Apps", rows = function() end, run = function() end }
  local out = r.scopes({ passthrough, "vpn" })
  check("scopes resolves a mixed spec list preserving its order", #out == 2 and out[1] == passthrough)
  check(
    "a resolved tool answers a table carrying its name and its opts rather than a finished scope",
    out[2].name == "vpn" and out[2].opts.matcher == false and out[2].opts.rows == rows and out[2].opts.run == run
  )
end

-- A well formed shortcut, leader or global, registers, phase seven's fifth and last packet.
do
  local r = freshRegistry(1)
  local ok = r.register({ name = "vpn", apiVersion = 1, shortcut = "leader", open = function() end })
  check("a tool whose shortcut is leader and which has an open registers", ok == true)

  local ok2 = r.register({ name = "clipboard", apiVersion = 1, shortcut = "global", open = function() end })
  check("a tool whose shortcut is global and which has an open registers", ok2 == true)
end

-- Refusal, a shortcut that is present and is neither leader nor global, one of the two
-- shortcut refusals this packet adds.
do
  local r, warnings = freshRegistry(1)
  local ok = r.register({ name = "vpn", apiVersion = 1, shortcut = "modifier", open = function() end })
  check("a descriptor whose shortcut is neither leader nor global is refused", ok == false)
  check(
    "the refusal names the tool and says its shortcut is neither leader nor global",
    found(warnings, "vpn") and found(warnings, "neither 'leader' nor 'global'"),
    table.concat(warnings, " | ")
  )
end

-- Refusal, a shortcut that is present and well formed but has nothing to bind, the second
-- of the two shortcut refusals, since a shortcut bound to nothing is worse than none at all.
do
  local r, warnings = freshRegistry(1)
  local ok = r.register({ name = "colorPicker", apiVersion = 1, shortcut = "leader" })
  check("a descriptor whose shortcut has nothing to bind is refused", ok == false)
  check(
    "the refusal names the tool and says its shortcut has nothing to bind",
    found(warnings, "colorPicker") and found(warnings, "has nothing to bind"),
    table.concat(warnings, " | ")
  )
end

-- shortcuts(), every active tool carrying a shortcut, answered in registration order, an
-- inactive tool contributing nothing.
do
  local r = freshRegistry(1)
  local vpnOpen = function() end
  local clipOpen = function() end
  local emojiOpen = function() end
  r.register({ name = "vpn", apiVersion = 1, shortcut = "leader", open = vpnOpen })
  r.register({ name = "clipboard", apiVersion = 1, shortcut = "global", open = clipOpen })
  -- Registered after clipboard but never activated, so it must contribute nothing below,
  -- the same nil-and-false silence every other read already answers for an inactive tool.
  r.register({ name = "emoji", apiVersion = 1, shortcut = "leader", open = emojiOpen })
  r.activate({ "vpn", "clipboard" })

  local out = r.shortcuts()
  check("shortcuts contributes nothing for a registered but inactive tool", #out == 2)
  check(
    "shortcuts answers in registration order",
    out[1].name == "vpn" and out[1].kind == "leader" and out[1].fn == vpnOpen
      and out[2].name == "clipboard" and out[2].kind == "global" and out[2].fn == clipOpen
  )
end

-- shortcuts(), registration order preserved across three active tools.
do
  local r = freshRegistry(1)
  local openA, openB, openC = function() end, function() end, function() end
  r.register({ name = "browserTabs", apiVersion = 1, shortcut = "leader", open = openA })
  r.register({ name = "fileSearch", apiVersion = 1, shortcut = "leader", open = openB })
  r.register({ name = "colorPicker", apiVersion = 1, shortcut = "leader", open = openC })
  r.activate({ "browserTabs", "fileSearch", "colorPicker" })

  local out = r.shortcuts()
  check(
    "shortcuts preserves registration order across three active tools",
    #out == 3 and out[1].name == "browserTabs" and out[2].name == "fileSearch" and out[3].name == "colorPicker"
  )
end
