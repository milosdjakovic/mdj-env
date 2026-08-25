-- Unit case for Olm.spoon/lib/hints.lua's rowsFor, pinning the hosted argument's contract.
-- The runner reaches this file with a dofile call carrying an absolute path, so this file in
-- turn locates itself the same way, through debug.getinfo, and derives the module path from
-- there, the same convention every other case file in this directory already follows.
--
-- rowsFor used to take a bare true or false flag for a hosted list. It now takes the scope's
-- own verbs table, already resolved by whoever called it, since hints.lua never reads
-- spoon.Olm.registry or any other global. Nothing here drives a live config, every plan,
-- deps table, and verbs table below is plain data built by hand, which is what a pure Lua
-- case can prove without a live Hammerspoon behind it. The point of pinning this with checks
-- is so the next time the argument's meaning moves again, this file fails loudly instead of
-- being left behind the way the composition root's own seam was.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local modulePath = caseDir .. "/../../Spoons/Olm.spoon/lib/hints.lua"

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
    error("could not load Olm.spoon/lib/hints.lua, " .. tostring(err))
  end
  return chunk()
end

-- One context, four bindings. insertSelected sits first, so actionKinds classifies it as
-- navigation by position alone, the same rule a real context's primary action earns.
-- closeChooser carries a fixed name GENERIC_NAV always calls navigation regardless of
-- position, so the context ends on a second navigation binding rather than only its first.
-- revealInFinder and copyPath sit between them and classify as verbs, the shape file search's
-- own real context takes, two verbs a hosted list may or may not declare anything about.
local function demoPlan()
  return {
    order = { "fileSearch" },
    identity = {},
    contexts = {
      fileSearch = {
        bindings = {
          { key = "return", action = "insertSelected", description = "Open" },
          { key = "r", action = "revealInFinder", description = "Reveal in Finder", glyph = "👀" },
          { key = "c", action = "copyPath", description = "Copy Path" },
          { key = "x", action = "closeChooser", description = "Close" },
        },
      },
    },
    -- The owning tool's own description, read through deps.owners below, which is what lets
    -- a kept hosted row qualify its chord with the name of the list it belongs to rather than
    -- the bare context name.
    effective = {
      fileSearch = { description = "File Search" },
    },
  }
end

-- deps carries owners, mapping the context to the tool that owns it, plus chordLabel and
-- leaderName so chordFor renders a real chord rather than falling back to a bare glyph and
-- warning about a missing collaborator on every call.
local function demoDeps()
  return {
    owners = { fileSearch = "fileSearch" },
    chordLabel = function(_, key, _) return "Hyper+" .. tostring(key):upper() end,
    leaderName = "Hyper",
    glyphFor = function(key, _) return tostring(key) end,
  }
end

-- A hosted verbs table keeps only the bindings it declares and drops the rest. Only
-- revealInFinder is declared here, so copyPath, a verb with nothing said about it, is
-- dropped, and Back still leads.
do
  local hints = freshModule()
  local plan = demoPlan()
  local deps = demoDeps()
  local hosted = { revealInFinder = { fn = function() end, closes = true } }
  local rows = hints.rowsFor("fileSearch", plan, deps, hosted)
  check(
    "a hosted verbs table keeps only the bindings it declares and drops the rest",
    #rows == 2 and rows[1].title == "Back" and rows[2].action == "revealInFinder"
  )
end

-- A kept hosted row's chord ends with the word in followed by the owner's description, read
-- through deps.owners and plan.effective, honest about a chord that will not fire until the
-- tool it names is reached directly.
do
  local hints = freshModule()
  local plan = demoPlan()
  local deps = demoDeps()
  local hosted = { revealInFinder = { fn = function() end, closes = true } }
  local rows = hints.rowsFor("fileSearch", plan, deps, hosted)
  local kept = rows[2]
  check(
    "a kept hosted row's chord ends with in followed by the owner's description",
    kept.chord:sub(-#(" in File Search")) == " in File Search",
    "chord was " .. tostring(kept.chord)
  )
end

-- A kept hosted row carries the closes the verbs table declares, read straight off the same
-- entry that proved the action was declared at all, true and false alike so a caller never
-- has to guess or assume a default.
do
  local hints = freshModule()
  local plan = demoPlan()
  local deps = demoDeps()
  local hosted = { revealInFinder = { fn = function() end, closes = false } }
  local rows = hints.rowsFor("fileSearch", plan, deps, hosted)
  check(
    "a kept hosted row carries the closes the verbs table declares",
    rows[2].closes == false
  )
end

-- An empty hosted table answers the Back row alone, reproducing the retired root's own
-- behaviour for a hosted list whose scope declares no verbs at all, rather than leaking the
-- tool's own full set of context verbs the way passing nothing at all used to.
do
  local hints = freshModule()
  local plan = demoPlan()
  local deps = demoDeps()
  local rows = hints.rowsFor("fileSearch", plan, deps, {})
  check(
    "an empty hosted table answers the Back row alone",
    #rows == 1 and rows[1].title == "Back"
  )
end

-- A nil hosted answers every verb row unfiltered with no closes on any, the ordinary
-- non hosted path every real picker's own action panel still takes.
do
  local hints = freshModule()
  local plan = demoPlan()
  local deps = demoDeps()
  local rows = hints.rowsFor("fileSearch", plan, deps, nil)
  check(
    "a nil hosted answers every verb row unfiltered",
    #rows == 3 and rows[1].title == "Back" and rows[2].action == "revealInFinder"
      and rows[3].action == "copyPath"
  )
  check(
    "a nil hosted leaves no closes on any row",
    rows[1].closes == nil and rows[2].closes == nil and rows[3].closes == nil
  )
end
