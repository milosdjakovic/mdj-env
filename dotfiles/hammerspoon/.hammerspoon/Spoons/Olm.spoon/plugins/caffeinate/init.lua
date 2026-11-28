--- === Caffeinate ===
---
--- A keep awake tool. Hyper+K opens one native chooser whose search field doubles as the
--- value entry, showing a single row that morphs with what you type. An empty field is the
--- state toggle, Keep Awake Indefinitely while keep awake is off and Stop Keeping Awake while it is on, its
--- subtitle carrying the live status. A clock like 15:30 morphs the row into a hold until
--- that time, and a duration morphs it into a hold for that span, the subtitle naming the
--- concrete end and its day once the end is not today. A duration is an h or m span like
--- 1h30m or 90m, or a bare number of hours once it is too large to be a clock hour, so 25
--- means 25h. A value still forming, a bare hour under 24 or a half typed clock, leaves the
--- row a disabled keep typing hint, and anything malformed a disabled error row, so Return
--- can never apply an empty or invalid value.
---
--- One row, not a list, so the chooser stays a single compact line and there is never a
--- second row to submit by mistake. The clock and the duration never overlap, since a clock
--- always carries the colon and a value without one is read as a duration, so the query
--- resolves to at most one. The format examples live in the subtitle rather than the
--- placeholder, which kept the placeholder short enough not to clip. Typing a value while a
--- session is already running sets a new bound rather than turning off first, which the
--- engine already supports by replacing the running session.
---
--- This file is the composition root and the command policy. It loads the engine, the keep
--- awake mechanism, and parses the query into rows, turning a chosen row into an engine
--- call. It is module style with plain functions.
---
--- The value entry folds into the search field, one morphing row, so keep awake needs no
--- inline form fields and rides the same shared window every presenting tool now shows
--- into.
---
--- Migrated onto host/stage, the trickle migration. This file owns no Chooser instance and
--- builds no window any more. Its rows and its selection dispatch are exactly what they
--- always were, now named on the manifest's own presentation block instead of handed to a
--- Chooser.new call this file no longer makes, and fit there is what asks for a window as tall
--- as its one morphing row. The plugin root's
--- own three function surface, isShowing, hide, and insertSelected, is gone too, deleted along with the Chooser.new block that gave it
--- something to answer for, host/stage's own surfaceFor answering all five generic nav
--- verbs now that a presentation exists to find. surface.nav stays false in the manifest,
--- unrelated to any of this since lib/surface.lua reads it at the binding layer to decide
--- whether j and k are ever added to this context's own bindings at all, independent of
--- what any surface answers, so the single morphing row still has nothing to move between.
---
--- This is the olm side copy of Caffeinate, phase six of the olm build plan, and the
--- original this was copied from lived at Spoons/Caffeinate.spoon.

local M = { name = "Caffeinate", version = "3.0", author = "Milos Djakovic", license = "MIT" }

-- Load the engine sibling by absolute path off this file's own location, the loadfile
-- pattern the spoons use (not require, since a spoon dir is not on package.path). The load
-- helper wraps loadfile so a broken sibling fails with a Caffeinate-prefixed message
-- rather than a bare Lua error. The view is the shared Chooser atom, injected by the root
-- rather than loaded here, since it lives in its own spoon and is shared across the list
-- tools.
local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(spoonPath .. name)
  if not chunk then
    error("Caffeinate: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end
local engine = load("engine.lua")

local cfg = nil       -- injected: stagePresent and redrawPresented, the root published words

--------------------------------------------------------------------------------
-- Row supplier (one morphing row, state and query driven)
--------------------------------------------------------------------------------

-- The grammar and the words live in rows.lua, pure, so the fixture Olm.app's port is checked
-- against is recorded from the very code this list runs. The status is read live on each call, so
-- the toggle subtitle tracks a session winding down.
local Rows = load("rows.lua")

local function rows(query)
  return { Rows.line(query, engine.status()) }
end

--------------------------------------------------------------------------------
-- Selection dispatch (command policy)
--------------------------------------------------------------------------------

-- A row was chosen. Each id maps to one engine call. Applying a timed or indefinite hold
-- replaces any running session, so an override never needs an off first. The hint rows are
-- disabled, so onSelect never fires for them.
local function onSelect(sel)
  if not sel then return end
  if sel.id == "indefinite" then
    engine.keepIndefinitely()
  elseif sel.id == "off" then
    engine.disable()
  elseif sel.id == "until" then
    engine.keepUntil(sel.ts)
  elseif sel.id == "for" then
    engine.keepFor(sel.secs)
  end
end

-- The engine changed while this presentation may be current, a timed session expired.
-- Redraw so the primary row's title and status follow the live state. Migrated onto
-- host/stage, cfg.redrawPresented replacing the direct chooser:refresh() this used to call
-- on an instance it held itself, already a no op unless this presentation, and no other,
-- is what the stage is actually showing.
local function onChange()
  if cfg.redrawPresented then cfg.redrawPresented("caffeinate") end
end

--------------------------------------------------------------------------------
-- Public control surface (dot-called, matching the clipboard and the VPN list)
--------------------------------------------------------------------------------

--- M.show() - present through the shared stage. cfg.stagePresent asks the registry for
--- this plugin's own presentation and hands it to Stage:present, exactly what opening keep
--- awake from cold has always meant. The list reads the live state itself, so there is
--- nothing to fetch first, and this plugin declares no onPresent for that reason.
function M.show()
  if cfg.stagePresent then cfg.stagePresent("caffeinate") end
end

--- M.rows(query) -> list. The morphing row for a query, named on the manifest's own
--- presentation block as the contract's rows, and exposed here under this plain name so a
--- scope can ask for the identical data through provides.rows without a second copy to
--- disagree with. Says nothing about where it is shown.
M.rows = rows

--- M.select(item) - apply one of those rows, taking the descriptor its own rows produced.
--- Named on the manifest's own presentation block as the contract's onSelect.
M.select = onSelect

--- M.placeholder() -> string. The field hint while this plugin's own presentation is
--- current, named on the manifest's own presentation block. Resolved once, at register,
--- since the presentation contract wants a plain string a presentation carries rather than
--- a function to call again later.
function M.placeholder()
  return "Time or duration"
end

-- isShowing, hide, and insertSelected are gone, the trickle migration, deleted along with
-- the Chooser.new block that gave them something to answer for. The composition root now
-- routes this plugin's own navigation through host/stage's own surfaceFor once
-- wiredRegistry.presentationFor("caffeinate") answers a presentation, which answers all
-- five generic verbs regardless of surface.nav, that field only ever deciding at the
-- binding layer whether j and k exist as bindings in this context at all.

--- M:configure(opts) - inject stagePresent and redrawPresented, the two root published
--- words phase three's own trickle migration adds. Both optional, both no ops when absent,
--- M.show and onChange above say what each one degrades to without the other.
--
-- Colon here, not dot, because spoon.Caffeinate:configure(opts) is how both the live top
-- level init.lua and the shared wiring pipeline in lib/wire.lua reach it. self arrives as M
-- and the body below never names it.
function M:configure(opts)
  cfg = opts or {}
  return M
end

--- M:start() - wire the engine. Called once by the root. Builds no chooser any more, the
--- trickle migration. Whatever this plugin used to hand a Chooser.new call, theme, a field
--- mode, the matcher, rows, onSelect, the row count, and the panel triple, is now either
--- read straight off this module by the registrar, rows and select through the manifest's
--- own presentation block, or owned by the stage as fixed, atom level policy, fit and
--- matcher being contract fields the manifest carries as plain values rather than this file
--- computing anything.
function M:start()
  engine.configure({ onChange = onChange })
  engine.start()
  return M
end

return M
