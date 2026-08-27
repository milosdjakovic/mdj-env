--- === Processes.chooser ===
---
--- The list surface over the engine. Pure policy, it talks to the engine only
--- through the injected api table and knows nothing about how a scan is performed
--- or what a source is.
---
--- Mostly a flat list, which is the point. Unlike the display profiles menu there
--- is nothing to drill into, you find a thing and you stop it, so Return running a
--- terminal action and letting the native chooser close is exactly right and no
--- Return interception is needed. The one exception is a stop the source refuses to
--- take silently, which re-shows as a two row confirmation, so the frame state here
--- is a single nullable pending stop rather than a menu stack.
---
--- The confirmation leads with the harmless row. A stray Return on a confirm screen
--- must never be the destructive answer, the same reason the display profiles delete
--- leads with Keep.
---
--- The live sampler belongs to this file rather than to the engine, because it exists
--- only while a surface is on screen. It is started once the picker is up and stopped
--- the moment it closes, so nothing samples in the background, and the surface is the
--- one piece that knows when that window opens and shuts.
---
--- The detail pane belongs here for the same reason, and this file is the only place
--- that knows all three of the picker, the sampler and the pane, so it is where the
--- three are tied together. It owns the row lookup the pane needs, the highlight the
--- pane follows, and the tick the pane redraws on, and the pane itself knows none of
--- them.
---
--- Migrated onto host/stage, the trickle migration, docs/BRIEF-CONTRACT-V2.md. This file
--- owns no chooser instance and builds no window any more. Its rows, its selection dispatch,
--- and its pane hooks are exactly what they always were, now named on the manifest's own
--- presentation block instead of handed to a Chooser.new call this file no longer makes. Its
--- own documented rule that a scan must land before the picker ever shows is what needed
--- contract v2's own second addition, enter, rather than being quietly dropped to fit a
--- contract that could not otherwise express it.

local M = { name = "Processes.chooser" }

local chooserPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local util = loadfile(chooserPath .. "util.lua")()
local metrics = loadfile(chooserPath .. "metrics.lua")()
local preview = loadfile(chooserPath .. "preview.lua")()
local icons = loadfile(chooserPath .. "icons.lua")()

local cfg = {}         -- injected, api from the spoon root, view deps from the main root
local rows = {}        -- rows from the most recent scan, read by the supplier
local pending = nil    -- a stop awaiting confirmation, { row = ..., message = ... }
local reopen = false   -- ask onClose to re-show rather than end, for the confirmation
local scanning = false -- guards against overlapping scans from a fast refresh
local misses = 0       -- consecutive samples that found no window, see onSample

-- Migrated onto host/stage, the trickle migration. This plugin owns no Chooser instance of
-- its own any more, so isShowing lives here instead as a plain flag, true from the moment
-- chooser.enter's own proceed is about to fire until chooser.onClose says otherwise, the
-- window this plugin used to ask isShowing() directly having become a fact only the stage
-- itself now holds. lastHighlighted is the item the presentation's own onHighlight last
-- named, cached so a re-render asked for outside a fresh highlight event, a rescan or a
-- reorder under a stationary highlight, has something to redraw without a chooser instance
-- of its own left to ask selectedItem() of.
local showing = false
local lastHighlighted = nil

-- The pending re-show, held until it fires. A Hammerspoon timer is userdata whose finalizer
-- stops it, so one nothing refers to can be collected before it runs, and the confirmation
-- would then never appear, leaving a stop the user asked for silently abandoned. Only one
-- re-show is ever pending, since it is armed on the single selection that needs confirming.
local reopenTimer = nil

-- Every proceed still waiting on the scan chooser.enter is already running, contract v2
-- decision two. A second enter while the first is still in flight does not start a second
-- scan, cfg.api.scan's own note on being asked to overlap, it joins this list instead and is
-- called once the one scan already running lands, alongside whichever proceed started it.
-- host/stage's own generation guard is what makes calling a stale one harmless, so this list
-- never has to work out which of its own entries still matter.
local entering = {}

-- The longest a scan is ever given before enter proceeds regardless, contract v2 decision
-- two's own requirement that a deferring presentation arranges its own timeout, the identical
-- discipline VPN's FETCH_TIMEOUT already keeps, so a task that never calls back cannot strand
-- a person on a launcher row that silently does nothing. Chosen well past what an ordinary
-- local scan ever takes, M.show's own retired design note put that under a tenth of a second.
local ENTER_TIMEOUT = 5

--------------------------------------------------------------------------------
-- Row icons
--------------------------------------------------------------------------------

-- The technology glyphs and the framework naming both live in icons.lua, which is the
-- one place that decides what a row is called and what is drawn for it. Only the three
-- fixed affordances stay here, because the empty state and the two confirmation answers
-- are not technologies and never want a brand mark.
local ICON_EMPTY = "🚫"
local ICON_KEEP = "↩️"
local ICON_STOP = "🛑"

-- The detail pane beside the list inherits the chooser's own width, the manifest's own
-- presentation.paneWidth = true, the atom's own paneMaxW still capping whichever width wins.
-- Migrated onto host/stage, this is now a plain declared value rather than something read
-- off cfg.previewWidth at start, cfg.previewWidth having never been set by anything on the
-- retired standalone path either, so nothing here loses a capability that was ever exercised.

--------------------------------------------------------------------------------
-- Row text
--------------------------------------------------------------------------------

-- Ports sit in the TITLE rather than the subtitle, next to the name, because the
-- port is half the identity of a development server and the thing you scan the list
-- for. The native chooser has no second column to right align them into, so they
-- trail the name instead of sitting at the edge.
local function titleFor(row)
  local ports = row.ports or {}
  if #ports == 0 then return row.title end
  local parts = {}
  for _, p in ipairs(ports) do parts[#parts + 1] = ":" .. p end
  return row.title .. "   " .. table.concat(parts, " ")
end

-- The half of the subtitle that does not move, and the only half a query searches.
--
-- The resident memory the scan reported used to sit here and no longer does. The live
-- figure below supersedes it and says more, since it covers the whole process group
-- rather than the one listener, so keeping both would have been the same fact twice
-- and a longer line. Everything else stays as it was, because the line already earns
-- its width, and the room for the live figures came out of that removal rather than
-- out of the end of the line.
--
-- The leading word is the framework when one was recognised and the runtime otherwise,
-- and it replaces rather than joins. Three rows reading node tell you nothing, and next
-- next node would be the same fact twice on a line that is already full. The runtime it
-- displaced is not lost, it stays in the search haystack below, so a query of node still
-- finds every one of them.
local function staticSubtitle(row, label)
  local bits = {}
  bits[#bits + 1] = label or row.runtime
  if row.pid then bits[#bits + 1] = "pid " .. row.pid end
  if row.status and row.status ~= "" then bits[#bits + 1] = row.status:lower() end
  if row.command and row.command ~= "" and row.command ~= row.title then
    bits[#bits + 1] = row.command
  end
  return table.concat(bits, " · ")
end

-- One decimal below ten and none above it. A busy tree swings between 40 and 90 and
-- the tenth is noise there, while the difference between an idle server at 0.2 and one
-- quietly polling at 4 is the whole question at the bottom of the range. Anything under
-- a twentieth of a percent reads as a flat zero rather than a distracting 0.0.
local function formatCpu(pct)
  if pct < 0.05 then return "0%" end
  if pct < 10 then return string.format("%.1f%%", pct) end
  return string.format("%.0f%%", pct)
end

-- The half that moves, and it leads the line on purpose. These are the two numbers you
-- came to compare across rows, and a figure that changes under the eye has to sit in
-- one fixed place or reading down the column becomes a hunt. Memory falls back to the
-- listener's own reading from the scan until the first sample lands, so the line is
-- never briefly missing a number it is about to have.
local function liveSubtitle(row)
  local reading = metrics.reading(row.key)
  local bits = {}
  if reading and reading.cpu then bits[#bits + 1] = formatCpu(reading.cpu) end
  local kb = (reading and reading.rss) or row.rss
  if kb then bits[#bits + 1] = util.humanBytes(kb) end
  return table.concat(bits, " · ")
end

local function subtitleFor(row, static)
  local live = liveSubtitle(row)
  if live == "" then return util.elide(static, 150) end
  if static == "" then return util.elide(live, 150) end
  return util.elide(live .. " · " .. static, 150)
end

-- Everything a query may match, beyond what is visible. The port matters most, so a
-- half remembered ":3000" or a bare "3000" finds its listener, and the working
-- directory is folded in so a project name that never reaches the label still hits.
--
-- It is handed the STATIC subtitle rather than the rendered one, so the live figures
-- are searchable by nothing. A query of "3" is asking about port 3000, never about a
-- row that happens to be at three percent this second, and folding a moving number
-- into the haystack would also mean the set of matching rows changed on its own every
-- tick, with nobody having typed anything.
--
-- Lowercased here because the words matcher folds case on the query only and
-- compares the haystack verbatim, by contract, so the caller owns that fold. Without
-- it a runtime lsof reports as "Python" would not answer to "python", and no
-- container or project name with a capital in it would match a lowercase query.
-- Folding per keystroke is what the clipboard avoids, but these are a couple of
-- dozen short strings rather than long bodies, so the cost is nothing here.
--
-- Appended one at a time rather than built as a table literal. A local row has no
-- container name and a container row has no working directory, so exactly one field
-- is always nil and a literal would leave a hole that makes table.concat throw.
local function filterTextFor(row, title, subtitle)
  local bits = {}
  local function add(v) if v and v ~= "" then bits[#bits + 1] = v end end
  add(title)
  add(subtitle)
  add(row.cwd)
  add(row.containerName)
  add(row.runtime)
  for _, p in ipairs(row.ports or {}) do bits[#bits + 1] = tostring(p) end
  return table.concat(bits, " "):lower()
end

--------------------------------------------------------------------------------
-- Row suppliers
--------------------------------------------------------------------------------

local function listRows()
  if #rows == 0 then
    return { { title = "Nothing running", enabled = false,
               subTitle = "No development servers or containers found",
               image = icons.emoji(ICON_EMPTY) } }
  end
  local out = {}
  for _, row in ipairs(rows) do
    local title = titleFor(row)
    -- Classified once and read twice. The picture and the word come from the same
    -- decision, so asking for them separately would run the rules over every row on
    -- every keystroke a second time for no new answer.
    local image, label = icons.badge(row)
    local static = staticSubtitle(row, label)
    out[#out + 1] = {
      title = title,
      subTitle = subtitleFor(row, static),
      image = image,
      filterText = filterTextFor(row, title, static),
      -- Serializable only. hs.chooser drops a function off a row, which is why
      -- every list tool here carries a descriptor and looks the real thing up on
      -- select rather than closing over it.
      item = { key = row.key },
    }
  end
  return out
end

-- The confirmation. Harmless answer first, so the fresh highlight and a stray Return
-- both leave the thing running.
local function confirmRows()
  return {
    { title = "Keep it running", subTitle = "", image = icons.emoji(ICON_KEEP),
      item = { confirm = false } },
    { title = "Stop anyway", subTitle = pending.message or "",
      image = icons.emoji(ICON_STOP), item = { confirm = true } },
  }
end

local function supplier()
  if pending then return confirmRows() end
  return listRows()
end

--------------------------------------------------------------------------------
-- Live sampling, tied to the window being open
--------------------------------------------------------------------------------

-- What the sampler should follow, rebuilt from the rows in hand on every tick, so a
-- rescan that replaces them needs no restart. A container has no pid, so it produces
-- no target and simply carries no live figures. Asking the docker daemon for container
-- stats is a second shellout costing more than the whole scan, for rows that are
-- already named and already the thing you would stop, so it is deliberately not done.
local function metricTargets()
  local targets = {}
  for _, row in ipairs(rows) do
    if row.key and row.pid then
      targets[#targets + 1] = { key = row.key, pid = row.pid, pgid = row.pgid }
    end
  end
  return targets
end

-- Redraw in place. The visible ORDER is untouched, only the text of each row changes,
-- because a list that reshuffles under the cursor while you are reaching for Return is
-- a way to stop the wrong process. The refresh keeps the highlight where it was, which
-- is only safe precisely because nothing moved.
--
-- The window going away also stops the sampler here. onClose is the real teardown and
-- fires on every dismissal, so this is a backstop for a window that vanished without
-- one, and it forgives a couple of ticks because the first sample can land before the
-- panel has finished appearing and a stop there would leave the picker with no figures
-- at all.
local MISSES_BEFORE_STOP = 3

local function onSample()
  if showing then
    misses = 0
    if not pending and cfg.redrawPresented then cfg.redrawPresented("processes") end
    -- The pane advances on the same tick as the rows, which is the whole reason it
    -- takes its trail from the sampler rather than keeping one. There is no second
    -- timer anywhere and there must not be, since two of them would drift apart and a
    -- sparkline would disagree with the figure printed above it.
    preview.refresh()
    return
  end
  misses = misses + 1
  if misses >= MISSES_BEFORE_STOP then metrics.stop() end
end

-- Migrated onto host/stage. The chooser instance guard is gone along with the instance
-- itself, showing above being the one fact left to ask, since sampling still means nothing
-- for the confirmation's own two rows.
local function startSampling()
  if pending then return end
  misses = 0
  metrics.start(metricTargets, onSample)
end

--------------------------------------------------------------------------------
-- Acting on a row
--------------------------------------------------------------------------------

local function rowByKey(key)
  for _, row in ipairs(rows) do
    if row.key == key then return row end
  end
  return nil
end

local function report(ok, message)
  if message and message ~= "" then hs.alert.show(message) end
end

--------------------------------------------------------------------------------
-- The detail pane, following the highlight
--------------------------------------------------------------------------------

-- The row the pane should be describing. Normally the highlighted one, resolved from
-- the descriptor the row carries, since a row cannot carry the real thing.
--
-- During a confirmation it is the PENDING row instead, which is the one moment the
-- pane matters most. The question on screen is whether to take down more processes
-- than you expected, and the tree beside it is the answer, so the pane keeps showing
-- the target rather than following a highlight that is now sitting on Keep or Stop.
local function previewRow(item)
  if pending then return rowByKey(pending.key) end
  return item and item.key and rowByKey(item.key) or nil
end

-- The presentation's own onHighlight, host/stage's own poll still fired for the identical
-- reason the atom's own poll used to feed the chooser this file no longer owns. Everything
-- expensive behind it is cached on the row, and a row with nothing behind it, the empty
-- state or a confirmation answer, clears the pane rather than leaving a stale one beside the
-- list. Cached into lastHighlighted too, since renderHighlighted below has no chooser
-- instance left to ask selectedItem() of and this is the only place that fact is heard fresh.
local function onHighlight(item)
  lastHighlighted = item
  preview.show(previewRow(item))
end

-- Re-render for the row under the highlight right now.
--
-- Needed because the atom's poll compares the highlighted ROW NUMBER, so when the list
-- itself changes under a stationary highlight, a rescan or a heat sort, it sees the
-- same number and never fires. Without this the pane would keep describing whatever
-- used to be in that position. Reads lastHighlighted rather than asking an instance this
-- file no longer holds, safe because onHighlight above always runs at least once before
-- this could ever be called, the atom seeding the highlight before it positions anything
-- on every fresh show and this presentation's own onPositioned below never running first.
local function renderHighlighted()
  onHighlight(lastHighlighted)
end

-- Migrated onto host/stage. Docks the pane into the companion rect the stage reserved and
-- seeds its first paint, exactly as before, and drops its own call to cfg.onPositioned and
-- the anchor arithmetic that built it, since host/stage's own paneAnchor now re anchors the
-- docked shortcut panel itself, on every path that has real frames to report, and a plugin
-- still making that call would be a second, competing writer of the identical panel.
local function onPositioned(chooserFrame, companionFrame)
  if companionFrame then
    preview.dock(companionFrame)
    -- The atom seeds the highlight before it positions anything, so the first
    -- onHighlight lands with nowhere to draw. This is what fills the pane on open.
    renderHighlighted()
  end
end

-- Run a stop and deal with the three outcomes. Done, refused for a reason the user
-- should see, or refused only because the target is large, which becomes the
-- confirmation rather than an error.
local function runStop(row, opts)
  cfg.api.stop(row, opts, function(ok, message)
    if ok then
      report(true, message)
      return
    end
    if not opts.confirmed and message and message:find("confirm") then
      pending = { key = row.key, message = message }
      reopen = true
      -- The shared instance has already closed on the selection, host/stage's own onClose
      -- clearing the whole stack the identical way a genuine dismissal does, so the confirm
      -- frame is shown on the next tick as a fresh present rather than a reshow of anything
      -- still standing. cfg.stagePresent rather than the retired chooser:show(), migrated
      -- onto the shared stage. chooser.enter sees pending already set and proceeds at once,
      -- without paying for a scan the confirmation's own two rows never asked for.
      reopenTimer = hs.timer.doAfter(0, function()
        if cfg.stagePresent then cfg.stagePresent("processes") end
      end)
      return
    end
    report(false, message or "could not stop")
  end)
end

local function onSelect(item)
  if not item then pending = nil return end

  if pending then
    local row = rowByKey(pending.key)
    local confirmed = item.confirm
    pending = nil
    if confirmed and row then runStop(row, { confirmed = true }) end
    return
  end

  local row = item.key and rowByKey(item.key)
  if row then runStop(row, {}) end
end

--------------------------------------------------------------------------------
-- Public control surface (dot-called)
--------------------------------------------------------------------------------

--- M.show() - present through the shared stage. registry.open's own kept fallback, VPN's
--- identical precedent, reached only if presentationFor ever answered nil for a name it used
--- to answer for, since this tool proposes no key of its own and a launcher row choosing it
--- pushes the registry's own presentation straight from root/compose.lua's rowIntercept
--- without ever calling this. cfg.stagePresent asks the registry for this plugin's own
--- presentation and hands it to Stage:present, which is what runs chooser.enter's own scan
--- before showing anything, exactly what M.show used to do inline before this plugin had a
--- presentation to defer through instead.
function M.show()
  if cfg.stagePresent then cfg.stagePresent("processes") end
end

--- M.rows(query) -> list. The row supplier, named on the manifest's own presentation block
--- as the contract's rows. Ignores query, the same as it always has, since this list has
--- never been a text filter over its own rows, the shared stage's own matcher, "words" per
--- this plugin's own presentation.matcher, doing the only filtering this list ever answers to.
M.rows = supplier

--- M.select(item) - apply one of those rows, named on the manifest's own presentation block
--- as the contract's onSelect.
M.select = onSelect

--- M.placeholder() -> string. The field hint while this plugin's own presentation is current,
--- named on the manifest's own presentation block. Resolved once, at register, since the
--- presentation contract wants a plain string a presentation carries rather than a function
--- to call again later.
function M.placeholder()
  return cfg.placeholder or "Search project, port, runtime"
end

--- M.enter(proceed) - contract v2's own deferred entry, named on the manifest's own
--- presentation block. Scans first and proceeds after, so the picker never appears before its
--- rows mean something, the identical rule M.show's own retired design note stated, "Showing
--- first and filling in later would flash an empty list on every open for no gain." A
--- confirmation already has its own two rows built from whatever runStop's own callback
--- populated in pending, nothing left to gather, so that branch proceeds at once rather than
--- paying for a scan the confirmation never asked for.
---
--- A scan already in flight is joined rather than restarted, cfg.api.scan's own reason for a
--- scanning guard existing at all, proceed queued in entering and called once that one scan
--- lands alongside whichever proceed started it, host/stage's own generation guard being what
--- makes calling a stale one harmless. A scan that never calls back, an hs.task that fails to
--- launch among the failures VPN's own review already named for its identical async doors,
--- proceeds anyway once ENTER_TIMEOUT elapses, on whatever rows this list already held, rather
--- than stranding a person on a launcher row that silently does nothing, contract v2's own
--- requirement that a deferring presentation arranges its own timeout. A real answer landing
--- after that timeout already fired still updates rows and asks to be redrawn, through the
--- published word every other async source here already uses, rather than being dropped.
function M.enter(proceed)
  if pending then
    showing = true
    proceed()
    return
  end
  if scanning then
    entering[#entering + 1] = proceed
    return
  end
  -- The glyph tints depend on whether the chooser will draw light or dark, and an open
  -- is the only moment that can have changed since anyone last asked.
  icons.refresh()
  scanning = true
  local proceeded = false
  local function proceedOnce()
    if proceeded then return end
    proceeded = true
    showing = true
    startSampling()
    local waiting = entering
    entering = {}
    proceed()
    for _, cb in ipairs(waiting) do cb() end
  end
  local timeoutTimer = hs.timer.doAfter(ENTER_TIMEOUT, function()
    scanning = false
    proceedOnce()
  end)
  cfg.api.scan(function(result)
    timeoutTimer:stop()
    scanning = false
    rows = result or {}
    if proceeded then
      if cfg.redrawPresented then cfg.redrawPresented("processes") end
    else
      proceedOnce()
    end
  end)
end

--- M.refresh() - rescan and redraw in place, without closing.
--- Also the way back to the engine's own order after a heat sort, since a rescan
--- rebuilds the list rather than reordering the one in hand.
function M.refresh()
  if not showing or scanning then return end
  scanning = true
  cfg.api.scan(function(result)
    scanning = false
    rows = result or {}
    if showing then
      if cfg.redrawPresented then cfg.redrawPresented("processes") end
      -- The highlight has not moved, so the poll will not fire, but every row behind
      -- it is a fresh table from this scan and the one under the highlight may be a
      -- different server entirely.
      renderHighlighted()
    end
  end)
end

--- M.sortByLoad() - reorder the list by the blended live load, hottest first.
---
--- A one shot reorder rather than a mode, which is the whole reason live figures can
--- be shown at all. The rows never move on their own, so the list you are reading is
--- the list you act on, and asking for heat order is an explicit act with a visible
--- result. Asking again re-sorts against whatever the numbers say by then, and a
--- rescan puts the engine's own order back, so there is no sticky state anywhere and
--- nothing to remember you are in.
---
--- The highlight resets to the top, unlike the in place tick. Every row has moved, so
--- there is no row to stay on, and the point of asking was to see what is at the top.
function M.sortByLoad()
  if not showing or pending or #rows == 0 then return end
  local score, order = {}, {}
  for i, row in ipairs(rows) do
    local reading = metrics.reading(row.key)
    -- Keyed by the row itself rather than by its key, so a row that somehow carries
    -- none still sorts rather than throwing. Below zero for a row with no reading at
    -- all, so containers and anything sampled too recently sink beneath a genuine
    -- idle zero instead of mixing into the quiet end of the list.
    score[row] = reading and reading.score or -1
    order[row] = i
  end
  -- table.sort is not stable, so the incoming position breaks every tie and the rows
  -- that share a score keep the order they already had rather than being shuffled.
  table.sort(rows, function(a, b)
    if score[a] ~= score[b] then return score[a] > score[b] end
    return order[a] < order[b]
  end)
  -- resetRow true, the trickle migration's own addition to the published redraw word,
  -- since every row has moved and the point of asking was to see what is at the top.
  if cfg.redrawPresented then cfg.redrawPresented("processes", true) end
  -- The highlight returns to the top, which is where it usually already was, so the
  -- poll sees no move even though every row has changed place underneath it.
  renderHighlighted()
end

--- M.stopForced() - stop the highlighted row with no grace period and no size
--- confirmation. The deliberate escape hatch for something already wedged, which is
--- why it skips the guard that a plain stop respects.
function M.stopForced()
  if not showing or pending then return end
  local row = lastHighlighted and lastHighlighted.key and rowByKey(lastHighlighted.key)
  if not row then return end
  -- The trickle migration's own published word, the same instant feedback
  -- chooser:hide() gave the retired standalone picker, so a forced stop does not leave
  -- a stale row on screen until the next sample or rescan corrects it.
  if cfg.stageHide then cfg.stageHide() end
  runStop(row, { force = true, confirmed = true })
end

-- isShowing, hide, selectNext, selectPrev, and insertSelected are gone, the trickle
-- migration, deleted along with the Chooser.new block that gave them something to answer
-- for. The composition root now routes this plugin's own navigation through host/stage's own
-- surfaceFor once wiredRegistry.presentationFor("processes") answers a presentation, falling
-- through to this submodule for refresh, sortByLoad, and stopForced, the three extra verbs
-- neither the stage nor its five function adapter was ever asked to carry.

--- M.onHighlight, M.onPositioned - the presentation contract's own pane hooks, named on the
--- manifest's own presentation block, exposing the file local functions already defined above
--- under "The detail pane, following the highlight" without a second copy to disagree with.
M.onHighlight = onHighlight
M.onPositioned = onPositioned

--- M.onClose() - the presentation contract's own onClose, named on the manifest's own
--- presentation block, told once whenever the stage hides entirely, never on a swap, which is
--- what the atom's own teardown already meant for the standalone picker this used to be
--- attached to directly. Composes the confirmation behaviour with the pane and sampler
--- teardown exactly as before. A pending confirm asked to re-show is left alone rather than
--- cleared, so an escape out of the confirmation leaves the process alone, and showing is
--- dropped here too, so onSample's own backstop and stopForced's own guard both read a closed
--- presentation the instant a real dismissal tears it down.
function M.onClose()
  metrics.stop()
  preview.destroy()
  showing = false
  if reopen then
    reopen = false
  else
    pending = nil
  end
end

--- M:configure(opts) - merge injected deps across the two callers. The spoon root injects
--- `api`, the view over the engine, and `metrics`, the sampler's slice of the policy. The main
--- root injects `theme`, `chooser`, `matcher`, and the panel triple too, the ambient grant a
--- surfaced plugin still earns even though this file no longer reads any of them, having no
--- Chooser.new call left to hand them to, kept as the single wiring seam so the main root
--- stays the one place the atoms are handed in, VPN's own manifest carrying the identical note.
--- stagePresent, redrawPresented, and stageHide, the trickle migration's own three root
--- published words, arrive here too, under needs.data above.
---
--- The sampler's policy arrives here rather than at the spoon root because the sampler
--- is part of this surface and is loaded by this file. Forwarding the block keeps the
--- root the only place that reads the config, and keeps the weights out of the
--- mechanism, which is the same split each source gets.
--
-- Colon here, not dot, because every caller, the plugin root's own configure, the live top
-- level init.lua, and the shared wiring pipeline in lib/wire.lua, reaches this submodule as
-- chooser:configure(opts). self arrives as M and the body below never names it. metrics stays
-- a plain dot call, it is this file's own internal collaborator and unrelated to the wiring
-- contract.
function M:configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  if opts and opts.metrics then metrics.configure(opts.metrics) end
  return M
end

--- M:start() - configure the detail pane. Builds no chooser any more, the trickle migration.
--- Whatever this plugin used to hand a Chooser.new call, theme, a field mode, the matcher,
--- rows, onSelect, and the panel triple, is now either read straight off this module by the
--- registrar, rows and select through the manifest's own presentation block, or owned by the
--- stage as fixed, atom level policy that never varied per presentation in the first place,
--- matcher being contract v2's own exception, still read straight off presentation.matcher
--- rather than computed here, since this plugin never varies it either.
---
--- The pane is configured first, because whether there is one at all used to decide whether
--- the atom reserved room beside the list. It still decides paneWidth's own honesty, true
--- meaning a pane genuinely exists, but the reservation itself is host/stage's concern now.
--- With no surface injected the pane stands down and this presentation opens exactly as it
--- did before one existed, rather than half wired.
function M:start()
  preview.configure({
    surface = cfg.surface,
    -- The atom's own light and dark resolution, hs.host.interfaceStyle() picking cfg.theme's
    -- dark or light half, lib/chooser/providers/native.lua:178's own arithmetic, reproduced
    -- here rather than reached through an instance this file no longer holds, so the pane
    -- still follows the system appearance switch exactly as it did before the migration.
    palette = function()
      local p = cfg.theme or {}
      local dark = hs.host.interfaceStyle() == "Dark"
      local resolved = (dark and p.dark) or p.light or p.dark
      return resolved and resolved.preview
    end,
    -- The one sampler this file already holds. Handing it over rather than letting the
    -- pane load its own matters, since loadfile returns a fresh module every call and a
    -- second sampler would keep its own empty history behind every sparkline.
    metrics = metrics,
    formatCpu = formatCpu,
  })
  return M
end

return M
