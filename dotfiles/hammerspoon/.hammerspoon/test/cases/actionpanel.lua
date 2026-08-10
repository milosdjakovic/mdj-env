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

-- configure now also requires deps.rowsFor and deps.run, phase eight's second packet, and
-- every block below that only exercises kindOf or verbsIn hands these two in as plain no ops,
-- since neither is that block's own business, the same way it hands in a kindOf that answers
-- only what that block cares about.
local NOOP_ROWS_FOR = function() return {} end
local NOOP_RUN = function() end

-- A fake picker instance answering isShowing, selectedItem, selectedRow, selectRow, query,
-- setQuery, and refresh, the seven methods decorate and toggle ever call on one, standing in
-- for the atom the same way the gate asks for. showing, row, item, and q are mutable through
-- the returned table itself, so a case can change what the instance answers between calls, and
-- refreshCalls records every resetRow argument refresh was called with, in order, so a case
-- can read back whether and how it was asked to rebuild. query and setQuery are the field the
-- coordinator's review found missing entirely, so this stands in for it too, a plain string
-- the fake stores rather than anything the real atom's query changed callback would fire on,
-- since nothing here needs that callback to prove the panel restores what it captured.
local function fakeInstance(opts)
  opts = opts or {}
  local instance = {
    showing = opts.showing ~= false,
    row = opts.row or 1,
    item = opts.item,
    q = opts.query or "",
    refreshCalls = {},
  }
  instance.isShowing = function() return instance.showing end
  instance.selectedItem = function() return instance.item end
  instance.selectedRow = function() return instance.row end
  instance.selectRow = function(_, n) instance.row = n end
  instance.query = function() return instance.q end
  instance.setQuery = function(_, text) instance.q = text or "" end
  instance.refresh = function(_, resetRow) instance.refreshCalls[#instance.refreshCalls + 1] = resetRow end
  return instance
end

-- The marker fakeConfig below reads as "omit this field entirely", distinct from a real
-- override, which is always a function, so a case asking for a config with no intercept and
-- no back of its own passes OMIT rather than a plain nil, which pairs() would never see in a
-- literal table anyway.
local OMIT = {}

-- A fake config carrying all six functions decorate wraps, rows, intercept, back, onSelect,
-- onHighlight, and onClose, each recording every call it receives in the returned calls table
-- so a case can read back whether and how its own original was reached. rows answers one
-- plain row of its own, distinct from anything a panel would ever build, so a case can tell
-- the tool's own rows apart from the panel's at a glance. overrides replaces a field before
-- decorate ever sees it, or removes it outright when the value is OMIT above, which is how a
-- case builds the config with no intercept and no back of its own.
local function fakeConfig(overrides)
  local calls = {
    rows = {}, intercept = {}, back = {}, onSelect = {}, onHighlight = {}, onClose = {},
  }
  local config = {
    matcher = false,
    rows = function(query)
      calls.rows[#calls.rows + 1] = query
      return { { title = "tool row", filterText = "tool row" } }
    end,
    intercept = function(item)
      calls.intercept[#calls.intercept + 1] = item
      return false
    end,
    back = function()
      calls.back[#calls.back + 1] = true
      return false
    end,
    onSelect = function(item) calls.onSelect[#calls.onSelect + 1] = item end,
    onHighlight = function(item) calls.onHighlight[#calls.onHighlight + 1] = item end,
    onClose = function() calls.onClose[#calls.onClose + 1] = true end,
  }
  for k, v in pairs(overrides or {}) do
    if v == OMIT then
      config[k] = nil
    else
      config[k] = v
    end
  end
  return config, calls
end

-- A configured module ready for the panel's own cases below. rowsByContext maps a context
-- name to the plain rows deps.rowsFor should answer for it, the shape the root's own rowsFor
-- would build, action, title, chord, defaulting to an empty list for any name not present.
-- run records every action it was asked to run, in order, in the returned runCalls, and every
-- warning logged is read back through the returned warnings, the same log stub every block
-- above already uses. kindOf answers nothing for everything, since nothing below this point
-- exercises classification, only presentation and the swap.
local function configuredPanel(rowsByContext)
  local ap = freshModule()
  local runCalls = {}
  local warnings = {}
  ap:configure({
    kindOf = function() return nil end,
    rowsFor = function(name) return (rowsByContext or {})[name] or {} end,
    run = function(action) runCalls[#runCalls + 1] = action end,
    log = { w = function(message) warnings[#warnings + 1] = message end },
  })
  return ap, runCalls, warnings
end

-- configure requires deps.kindOf, deps.rowsFor, and deps.run, each a function, the same
-- readable error registry.lua raises for its own required opts.apiVersion. Both a missing
-- value and one that is not a function reach the same raise, so both are checked against it
-- rather than as two refusals pretending to distinguish something the module itself does not.
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

  local calledOk3, err3 = pcall(function() ap:configure({ kindOf = NOOP_RUN, run = NOOP_RUN }) end)
  check(
    "configure with no deps.rowsFor raises a readable error",
    calledOk3 == false and type(err3) == "string" and #err3 > 0,
    "pcall returned ok=" .. tostring(calledOk3) .. " err=" .. tostring(err3)
  )

  local calledOk4, err4 = pcall(function() ap:configure({ kindOf = NOOP_RUN, rowsFor = NOOP_ROWS_FOR }) end)
  check(
    "configure with no deps.run raises a readable error",
    calledOk4 == false and type(err4) == "string" and #err4 > 0,
    "pcall returned ok=" .. tostring(calledOk4) .. " err=" .. tostring(err4)
  )
end

-- A binding whose action classifies as a verb is kept, in the shape it was given.
do
  local ap = freshModule()
  ap:configure({ rowsFor = NOOP_ROWS_FOR, run = NOOP_RUN, kindOf = function(action)
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
  ap:configure({ log = log, rowsFor = NOOP_ROWS_FOR, run = NOOP_RUN, kindOf = function(action)
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
  ap:configure({ rowsFor = NOOP_ROWS_FOR, run = NOOP_RUN, kindOf = function(action) return kinds[action] end })
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
  ap:configure({ log = log, rowsFor = NOOP_ROWS_FOR, run = NOOP_RUN, kindOf = function() return nil end })
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
  ap:configure({ log = log, rowsFor = NOOP_ROWS_FOR, run = NOOP_RUN, kindOf = function() return "neitherKind" end })
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
  ap:configure({ rowsFor = NOOP_ROWS_FOR, run = NOOP_RUN, kindOf = function(action)
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
  ap:configure({ rowsFor = NOOP_ROWS_FOR, run = NOOP_RUN, kindOf = function(action)
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

--------------------------------------------------------------------------------
-- The panel proper, decorate, toggle, and isOpen, phase eight's second packet. Every block
-- below drives the whole cycle through a fake config and a fake instance rather than a live
-- chooser, since decorate only wraps functions and toggle only calls the five methods
-- fakeInstance answers.
--------------------------------------------------------------------------------

-- decorate's wrapped rows function answers the tool's own supplier while the panel is closed,
-- and the panel's own rows, built from deps.rowsFor, the moment it is open on this instance.
do
  local ap, runCalls = configuredPanel({
    demo = { { action = "doThing", title = "Do Thing", chord = "Hyper+D" }, { title = "Back" } },
  })
  local config = fakeConfig()
  local instance = fakeInstance({ showing = true })
  ap:decorate(instance, config)

  local closedRows = config.rows("")
  check(
    "the supplier answers the original's rows while the panel is closed",
    #closedRows == 1 and closedRows[1].title == "tool row"
  )

  ap:toggle("demo")
  local openRows = config.rows("")
  check(
    "the supplier answers the panel's own rows while the panel is open on this instance",
    #openRows == 2 and openRows[1].title == "Do Thing" and openRows[2].title == "Back"
  )
  check("opening the panel alone runs no action", #runCalls == 0)
end

-- An original intercept and an original back are both still reached exactly as before while
-- the panel stays closed on this instance.
do
  local ap = configuredPanel({})
  local config, calls = fakeConfig()
  local instance = fakeInstance({ showing = false })
  ap:decorate(instance, config)

  local interceptResult = config.intercept({ some = "item" })
  local backResult = config.back()
  check("the original intercept is still reached while the panel is closed", #calls.intercept == 1)
  check("the wrapped intercept answers whatever the original did while closed", interceptResult == false)
  check("the original back is still reached while the panel is closed", #calls.back == 1)
  check("the wrapped back answers whatever the original did while closed", backResult == false)
end

-- A chooser with no intercept and no back of its own gains both, once the panel opens on it,
-- and answers nothing (false) for either beforehand, since there is no original to fall
-- through to and the panel is not yet open.
do
  local ap = configuredPanel({ demo = {} })
  local config = fakeConfig({ intercept = OMIT, back = OMIT })
  local instance = fakeInstance({ showing = true })
  ap:decorate(instance, config)

  check(
    "a chooser with no intercept of its own answers false while the panel is closed",
    config.intercept({ title = "Back" }) == false
  )
  check(
    "a chooser with no back of its own answers false while the panel is closed",
    config.back() == false
  )

  ap:toggle("demo")
  check(
    "the same chooser now answers true to intercept, gained once the panel opened",
    config.intercept({ title = "Back" }) == true
  )
  check(
    "choosing Back through the gained intercept closed the panel again",
    not ap:isOpen()
  )

  ap:toggle("demo")
  check(
    "the same chooser now answers true to back too, gained once the panel opened",
    config.back() == true
  )
end

-- Opening the panel clears the field rather than rebuilding with whatever the tool's own query
-- happened to be, since the query is as much a part of what the panel swaps as the rows are.
-- Without this the panel comes up filtered by text nobody typed for a panel title and shows
-- nothing, the one thing the design says it must never do, on the single most common path
-- there is, a person who had already typed something.
do
  local ap = configuredPanel({
    demo = { { action = "doThing", title = "Do Thing" }, { title = "Back" } },
  })
  local config = fakeConfig()
  local instance = fakeInstance({ showing = true, query = "whatever the tool's own list had" })
  ap:decorate(instance, config)

  ap:toggle("demo")
  check("opening the panel clears the field", instance:query() == "")
  local rows = config.rows("")
  check(
    "the panel's own rows are not filtered out by the query the tool's own list had",
    #rows == 2 and rows[1].title == "Do Thing" and rows[2].title == "Back"
  )
end

-- The row captured when the panel opened is what selectRow is later asked for, and the field
-- is restored to what the tool's own list held, not to whatever was typed inside the panel to
-- find the verb, both restored by the deferred continuation after a verb is chosen. The query
-- is restored SYNCHRONOUSLY though, ahead of the row, since the field has to be right before
-- either refresh that follows, the atom's own or the continuation's, rebuilds against it.
-- ap._defer stands in for hs.timer.doAfter, running the continuation at once rather than on a
-- later runloop tick, so this reads its effect back without a real wait, exactly what
-- obj._defer exists for.
do
  local ap, runCalls = configuredPanel({
    demo = { { action = "doThing", title = "Do Thing" } },
  })
  ap._defer = function(_, fn) fn() end
  local config = fakeConfig()
  local instance = fakeInstance({ showing = true, row = 4, query = "rev" })
  ap:decorate(instance, config)

  ap:toggle("demo")
  check("opening the panel clears the field here too", instance:query() == "")
  -- Typing inside the panel to find the verb, and the atom's own refresh(true), called for
  -- real by _intercept the moment a handler answers true, resetting the highlight to the
  -- first row before the continuation ever runs. Simulated here since fakeInstance's own
  -- refresh only records the call rather than moving anything or reacting to typing.
  instance:setQuery("do")
  instance.row = 1

  local handled = config.intercept({ action = "doThing", title = "Do Thing" })
  check("choosing a verb answers true, keeping the chooser open", handled == true)
  check(
    "the field is restored to what the tool's own list held, not to what found the verb",
    instance:query() == "rev"
  )
  check(
    "the deferred continuation puts the highlight back on the row the panel was opened over",
    instance.row == 4
  )
  check(
    "the deferred continuation runs the action through deps.run",
    #runCalls == 1 and runCalls[1] == "doThing"
  )
end

-- Choosing the Back row restores the field and the highlight the exact same way a chosen verb
-- does, not only closing the panel, since all four ways out owe the chooser the same thing back.
do
  local ap = configuredPanel({ demo = { { action = "doThing", title = "Do Thing" } } })
  ap._defer = function(_, fn) fn() end
  local config = fakeConfig()
  local instance = fakeInstance({ showing = true, row = 5, query = "abc" })
  ap:decorate(instance, config)

  ap:toggle("demo")
  instance.row = 1
  local handled = config.intercept({ title = "Back" })
  check("choosing Back answers true", handled == true)
  check("choosing Back restores the field the tool's own list held", instance:query() == "abc")
  check(
    "choosing Back puts the highlight back on the row the panel was opened over",
    instance.row == 5
  )
end

-- Backspace on an empty field restores the field and the highlight the same way, rather than
-- leaving the highlight wherever the atom's own refresh(true) dropped it, the first row.
do
  local ap = configuredPanel({ demo = { { action = "doThing", title = "Do Thing" } } })
  ap._defer = function(_, fn) fn() end
  local config = fakeConfig()
  local instance = fakeInstance({ showing = true, row = 6, query = "xyz" })
  ap:decorate(instance, config)

  ap:toggle("demo")
  instance.row = 1
  local handled = config.back()
  check("back answers true while the panel is open", handled == true)
  check("back restores the field the tool's own list held", instance:query() == "xyz")
  check(
    "back puts the highlight back on the row the panel was opened over",
    instance.row == 6
  )
end

-- Toggling the panel closed with the chord puts the chooser's own list back exactly as the
-- other three ways out do, the field restored and the highlight back on the row the panel was
-- opened over, through its own explicit refresh since this is the one way out that answers no
-- to intercept and to back and so earns none of their automatic rebuild. Without this the
-- chooser keeps showing panel rows while every wrapper already believes the panel is closed.
do
  local ap = configuredPanel({ demo = { { action = "doThing", title = "Do Thing" } } })
  ap._defer = function(_, fn) fn() end
  local config = fakeConfig()
  local instance = fakeInstance({ showing = true, row = 3, query = "rev" })
  ap:decorate(instance, config)

  ap:toggle("demo")
  instance.row = 1 -- the atom's own refresh(true) at open would have reset it
  ap:toggle("demo") -- the chord pressed again while the panel is open
  check("the panel is closed after toggling it a second time", not ap:isOpen())
  check("the chord close restores the field the tool's own list held", instance:query() == "rev")
  check(
    "the chord close puts the highlight back on the row the panel was opened over",
    instance.row == 3
  )
  check(
    "the chord close rebuilds through its own refresh, once to open and once to close",
    #instance.refreshCalls == 2
  )
  local rows = config.rows("")
  check(
    "the supplier answers the tool's own row again once the chord closed the panel",
    #rows == 1 and rows[1].title == "tool row"
  )
end

-- A continuation that finds its chooser gone warns naming the action and runs nothing, rather
-- than acting on a selection nobody can see.
do
  local ap, runCalls, warnings = configuredPanel({
    demo = { { action = "doThing", title = "Do Thing" } },
  })
  ap._defer = function(_, fn) fn() end
  local config = fakeConfig()
  local instance = fakeInstance({ showing = true })
  ap:decorate(instance, config)

  ap:toggle("demo")
  instance.showing = false -- the chooser tore down before the deferred continuation ran
  config.intercept({ action = "doThing", title = "Do Thing" })
  check("a continuation finding its chooser gone runs no action", #runCalls == 0)
  check(
    "a continuation finding its chooser gone warns naming the action",
    found(warnings, "doThing"),
    table.concat(warnings, " | ")
  )
end

-- onHighlight is not called at all while the panel is open on this instance, so a companion
-- pane keeps showing the item the panel was opened over, and reaches the original as always
-- while the panel is closed.
do
  local ap = configuredPanel({ demo = {} })
  local config, calls = fakeConfig()
  local instance = fakeInstance({ showing = true })
  ap:decorate(instance, config)

  config.onHighlight({ some = "item" })
  check("onHighlight reaches the original while the panel is closed", #calls.onHighlight == 1)

  ap:toggle("demo")
  config.onHighlight({ some = "item" })
  check("onHighlight does not reach the original while the panel is open", #calls.onHighlight == 1)
end

-- onClose clears the panel's open state, whatever tore the chooser down, and still reaches the
-- original, so the tool's own teardown behaviour is unchanged.
do
  local ap = configuredPanel({ demo = { { action = "doThing", title = "Do Thing" } } })
  local config, calls = fakeConfig()
  local instance = fakeInstance({ showing = true })
  ap:decorate(instance, config)

  ap:toggle("demo")
  check("the panel is open after toggle", ap:isOpen())
  config.onClose()
  check("onClose clears the panel's open state", not ap:isOpen())
  check("onClose still reaches the original", #calls.onClose == 1)
end

-- A panel row reaching onSelect is a defect, since intercept should have answered first and
-- kept it from ever completing, so this warns naming it rather than reaching the original.
do
  local ap, _, warnings = configuredPanel({ demo = {} })
  local config, calls = fakeConfig()
  local instance = fakeInstance({ showing = true })
  ap:decorate(instance, config)

  ap:toggle("demo")
  config.onSelect({ action = "doThing", title = "Do Thing" })
  check("a panel row reaching onSelect does not reach the original", #calls.onSelect == 0)
  check(
    "a panel row reaching onSelect warns naming it instead",
    found(warnings, "doThing"),
    table.concat(warnings, " | ")
  )
end

-- A context with no verbs, deps.rowsFor answering only its Back row, shows exactly one row,
-- the shape nine of the twelve real contexts take.
do
  local ap = configuredPanel({ empty = { { title = "Back", chord = "⌫" } } })
  local config = fakeConfig()
  local instance = fakeInstance({ showing = true })
  ap:decorate(instance, config)

  ap:toggle("empty")
  local rows = config.rows("")
  check(
    "a context with no verbs answers exactly one row, Back alone",
    #rows == 1 and rows[1].title == "Back"
  )
end

-- The panel filters its own rows by a plain case insensitive substring against the title when
-- config.matcher was false at decoration time, the supplier owning filtering, and answers
-- every row unfiltered otherwise, letting the instance's own matcher rank the full list, the
-- same choice the atom already gives every consumer over its ordinary rows.
do
  local ap = configuredPanel({
    demo = {
      { action = "doThing", title = "Do The Thing" },
      { action = "other", title = "Second Verb" },
      { title = "Back" },
    },
  })
  local config = fakeConfig({ matcher = false })
  local instance = fakeInstance({ showing = true })
  ap:decorate(instance, config)
  ap:toggle("demo")
  local filtered = config.rows("the")
  check(
    "the panel filters its own rows by a case insensitive substring when the supplier owns filtering",
    #filtered == 1 and filtered[1].title == "Do The Thing"
  )
end

do
  local ap = configuredPanel({
    demo = { { action = "doThing", title = "Do The Thing" }, { title = "Back" } },
  })
  local config = fakeConfig({ matcher = function() return 1 end })
  local instance = fakeInstance({ showing = true })
  ap:decorate(instance, config)
  ap:toggle("demo")
  local unfiltered = config.rows("the")
  check(
    "the panel answers every row unfiltered when the instance's own matcher owns ranking",
    #unfiltered == 2
  )
end

-- decoratedCount answers how many instances decorate has wrapped, so a live measurement can
-- prove the panel is actually installed on a chooser rather than assuming Chooser.configure's
-- seam ran before it was built. Needs no configure, the same reason decorate itself does not.
do
  local ap = freshModule()
  check("decoratedCount answers zero before decorate is ever called", ap:decoratedCount() == 0)
  local config1 = fakeConfig()
  local instance1 = fakeInstance({ showing = false })
  ap:decorate(instance1, config1)
  check("decoratedCount answers one after decorating a single instance", ap:decoratedCount() == 1)
  local config2 = fakeConfig()
  local instance2 = fakeInstance({ showing = false })
  ap:decorate(instance2, config2)
  check(
    "decoratedCount answers two after a second instance, needing no configure at all",
    ap:decoratedCount() == 2
  )
end
