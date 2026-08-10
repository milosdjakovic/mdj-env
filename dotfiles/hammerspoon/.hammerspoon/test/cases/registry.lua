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

-- Refusal three, a commands key colliding with any name already indexed, whether a
-- tool name or another tool's command, or with its own tool's name, which is not yet in
-- that index at the point a command is checked.
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

  -- The tool's own name is not yet in the flat index at the point a command is checked,
  -- only a prior tool's is, so a command keyed the same as its own tool's name needs its
  -- own check rather than falling out of the one against the flat index.
  local calls = {}
  local ok3 = r.register({
    name = "vpn",
    apiVersion = 1,
    open = function() calls[#calls + 1] = "open" end,
    commands = { vpn = function() calls[#calls + 1] = "vpn" end },
  })
  check("a command keyed the same as its own tool's name is refused", ok3 == false)
  check(
    "the self collision refusal names the tool and says it collided with its own tool name",
    found(warnings, "own tool name"),
    table.concat(warnings, " | ")
  )
  check("nothing about the refused descriptor was committed, run answers false", r.run("vpn") == false and #calls == 0)
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

-- rowFor, a command's row resolved through its owning tool, and nil for every command
-- an inactive tool owns, the same silence rowFor already answers for the tool itself.
do
  local r = freshRegistry(1)
  r.register({
    name = "clipboard",
    apiVersion = 1,
    open = function() end,
    row = { category = "Clipboard" },
    commands = {
      appendCopy = { fn = function() end, row = { category = "Clipboard", chord = "modifier" } },
      pasteNext = { fn = function() end, row = { category = "Clipboard", chord = "modifier" } },
    },
  })
  check("rowFor answers nil for a command of an inactive tool", r.rowFor("appendCopy") == nil)
  check(
    "rowFor answers nil for every other command the same inactive tool owns",
    r.rowFor("pasteNext") == nil
  )

  r.activate({ "clipboard" })
  local commandRow = r.rowFor("appendCopy")
  check(
    "rowFor answers a command's own row through its owning tool once that tool is active",
    commandRow ~= nil and commandRow.category == "Clipboard" and commandRow.chord == "modifier"
  )
end

-- rowFor, a name nothing registered.
do
  local r = freshRegistry(1)
  check("rowFor answers nil for a name nothing registered", r.rowFor("noSuchTool") == nil)
end

-- surfaces(spec), a string entry resolving to an active tool's surface, in the order
-- the spec gave, mixed with a plain object the registry was never told about.
do
  local r = freshRegistry(1)
  local vpnSurface = { isShowing = function() return false end }
  local emojiSurface = { isShowing = function() return false end }
  r.register({ name = "vpn", apiVersion = 1, surface = function() return vpnSurface end })
  r.register({ name = "emoji", apiVersion = 1, surface = function() return emojiSurface end })
  r.activate({ "vpn", "emoji" })

  local passthrough = { isShowing = function() return true end }
  local out = r.surfaces({ "emoji", passthrough, "vpn" })
  check(
    "surfaces resolves a mixed spec list preserving its order",
    #out == 3 and out[1] == emojiSurface and out[2] == passthrough and out[3] == vpnSurface
  )
end

-- surfaces(spec), a registered but inactive tool's surface is skipped with no warning
-- at all, since that is what inactive already means everywhere else in this module.
do
  local r, warnings = freshRegistry(1)
  r.register({ name = "vpn", apiVersion = 1, surface = function() return { isShowing = function() end } end })
  -- vpn is registered but never activated.
  local out = r.surfaces({ "vpn" })
  check("an inactive tool's surface contributes nothing to the list", #out == 0)
  check("an inactive tool's surface is skipped without logging anything", #warnings == 0)
end

-- surfaces(spec), an active tool with no surface at all is not the same as an inactive
-- one and must not share its silence. Naming a tool with nothing to navigate in a
-- navigation list is a mistake, so this logs one warning naming the tool, set directly
-- against the inactive case above to make the contrast provable in one file.
do
  local r, warnings = freshRegistry(1)
  r.register({ name = "colorPicker", apiVersion = 1, open = function() end })
  r.activate({ "colorPicker" })
  local out = r.surfaces({ "colorPicker" })
  check("an active tool with no surface contributes nothing to the list", #out == 0)
  check(
    "an active tool with no surface is warned about by name",
    found(warnings, "colorPicker"),
    table.concat(warnings, " | ")
  )
end

-- surfaces(spec), a name nothing registered is skipped and logs one warning naming it.
do
  local r, warnings = freshRegistry(1)
  local out = r.surfaces({ "noSuchTool" })
  check("an unknown name in a surfaces spec contributes nothing", #out == 0)
  check(
    "an unknown name in a surfaces spec is warned about by name",
    found(warnings, "noSuchTool"),
    table.concat(warnings, " | ")
  )
end

-- surfaces(spec), a surface closure that resolves to nothing is skipped with a warning
-- naming the tool, the same silent-hazard guard the missing isShowing case below shares.
do
  local r, warnings = freshRegistry(1)
  r.register({ name = "textCase", apiVersion = 1, surface = function() return nil end })
  r.activate({ "textCase" })
  local out = r.surfaces({ "textCase" })
  check("a surface resolving to nothing contributes nothing to the list", #out == 0)
  check(
    "a surface resolving to nothing is warned about by name",
    found(warnings, "textCase"),
    table.concat(warnings, " | ")
  )
end

-- surfaces(spec), a surface resolving to an object with no isShowing is treated the
-- same as a surface resolving to nothing, warned about by name and left out.
do
  local r, warnings = freshRegistry(1)
  r.register({ name = "textCase", apiVersion = 1, surface = function() return { selectNext = function() end } end })
  r.activate({ "textCase" })
  local out = r.surfaces({ "textCase" })
  check("a surface with no isShowing contributes nothing to the list", #out == 0)
  check(
    "a surface with no isShowing is warned about by name",
    found(warnings, "textCase"),
    table.concat(warnings, " | ")
  )
end
