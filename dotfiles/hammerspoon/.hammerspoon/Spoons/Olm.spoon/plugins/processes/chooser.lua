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

local M = { name = "Processes.chooser" }

local chooserPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local util = loadfile(chooserPath .. "util.lua")()
local metrics = loadfile(chooserPath .. "metrics.lua")()
local preview = loadfile(chooserPath .. "preview.lua")()
local icons = loadfile(chooserPath .. "icons.lua")()

local cfg = {}         -- injected, api from the spoon root, view deps from the main root
local chooser = nil    -- the one native Chooser instance
local rows = {}        -- rows from the most recent scan, read by the supplier
local pending = nil    -- a stop awaiting confirmation, { row = ..., message = ... }
local reopen = false   -- ask onClose to re-show rather than end, for the confirmation
local scanning = false -- guards against overlapping scans from a fast refresh
local misses = 0       -- consecutive samples that found no window, see onSample

-- The pending re-show, held until it fires. A Hammerspoon timer is userdata whose finalizer
-- stops it, so one nothing refers to can be collected before it runs, and the confirmation
-- would then never appear, leaving a stop the user asked for silently abandoned. Only one
-- re-show is ever pending, since it is armed on the single selection that needs confirming.
local reopenTimer = nil

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

-- The detail pane beside the list inherits the chooser's own width by default, the
-- same place the clipboard's preview does, so this surface has no width of its own to
-- keep. A root that wants a different one still passes previewWidth, and the atom's
-- paneMaxW still caps whichever one wins.

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
  if chooser and chooser:isShowing() then
    misses = 0
    if not pending then chooser:refresh() end
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

local function startSampling()
  if not chooser or pending then return end
  misses = 0
  metrics.start(metricTargets, onSample)
end

-- Show the LIST and put the sampler behind it, so there is one place where the two are
-- tied together and no way to open the list without its numbers. The confirmation
-- frame shows the chooser directly instead, since it carries no rows to sample for.
local function showChooser()
  if not chooser then return end
  chooser:show()
  startSampling()
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

-- The atom's onHighlight target. Fired from a poll, so everything expensive behind it
-- is cached on the row, and a row with nothing behind it, the empty state or a
-- confirmation answer, clears the pane rather than leaving a stale one beside the list.
local function onHighlight(item)
  preview.show(previewRow(item))
end

-- Re-render for the row under the highlight right now.
--
-- Needed because the atom's poll compares the highlighted ROW NUMBER, so when the list
-- itself changes under a stationary highlight, a rescan or a heat sort, it sees the
-- same number and never fires. Without this the pane would keep describing whatever
-- used to be in that position.
local function renderHighlighted()
  if chooser then onHighlight(chooser:selectedItem()) end
end

-- Compose with the root's own onPositioned rather than replacing it. The atom reports
-- both frames, the pane docks into the companion rect it reserved, and the root's
-- shortcut panel still gets its anchor, so neither knows about the other.
--
-- The anchor handed on spans the pair rather than the list alone, the same as the
-- clipboard, so the hints sit full width beneath both panes instead of stopping short
-- under the list. With no pane there is no companion rect and the anchor is the plain
-- chooser frame, exactly as it was before the pane existed.
local function onPositioned(chooserFrame, companionFrame)
  if companionFrame then
    preview.dock(companionFrame)
    -- The atom seeds the highlight before it positions anything, so the first
    -- onHighlight lands with nowhere to draw. This is what fills the pane on open.
    renderHighlighted()
  end
  if not cfg.onPositioned then return end
  local anchor = chooserFrame
  if companionFrame then
    anchor = {
      x = chooserFrame.x, y = chooserFrame.y, h = chooserFrame.h,
      w = (companionFrame.x + companionFrame.w) - chooserFrame.x,
    }
  end
  cfg.onPositioned(anchor)
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
      -- The native chooser has already closed on the selection, so the confirm
      -- frame is shown on the next tick once it has finished hiding. Shown raw
      -- rather than through showChooser, since the confirmation carries no rows
      -- and there is nothing for a sampler to feed while it is up.
      reopenTimer = hs.timer.doAfter(0, function()
        if chooser then chooser:show() end
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

--- M.show() - scan, then open on the result.
--- The scan is asynchronous, so the picker is shown only once the rows are in hand,
--- the same order TextCase reads a selection before opening. Showing first and
--- filling in later would flash an empty list on every open for no gain, a scan
--- costs well under a tenth of a second.
function M.show()
  if scanning then return end
  pending = nil
  -- The glyph tints depend on whether the chooser will draw light or dark, and an open
  -- is the only moment that can have changed since anyone last asked.
  icons.refresh()
  scanning = true
  cfg.api.scan(function(result)
    scanning = false
    rows = result or {}
    showChooser()
  end)
end

--- M.refresh() - rescan and redraw in place, without closing.
--- Also the way back to the engine's own order after a heat sort, since a rescan
--- rebuilds the list rather than reordering the one in hand.
function M.refresh()
  if not (chooser and chooser:isShowing()) or scanning then return end
  scanning = true
  cfg.api.scan(function(result)
    scanning = false
    rows = result or {}
    if chooser and chooser:isShowing() then
      chooser:refresh()
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
  if not (chooser and chooser:isShowing()) or pending or #rows == 0 then return end
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
  chooser:refresh(true)
  -- The highlight returns to the top, which is where it usually already was, so the
  -- poll sees no move even though every row has changed place underneath it.
  renderHighlighted()
end

--- M.stopForced() - stop the highlighted row with no grace period and no size
--- confirmation. The deliberate escape hatch for something already wedged, which is
--- why it skips the guard that a plain stop respects.
function M.stopForced()
  if not (chooser and chooser:isShowing()) or pending then return end
  local item = chooser:selectedItem()
  local row = item and item.key and rowByKey(item.key)
  if not row then return end
  chooser:hide()
  runStop(row, { force = true, confirmed = true })
end

function M.isShowing()
  return chooser ~= nil and chooser:isShowing()
end

function M.hide()
  if chooser then chooser:hide() end
end

function M.selectNext()
  if chooser then chooser:selectNext() end
end

function M.selectPrev()
  if chooser then chooser:selectPrev() end
end

function M.insertSelected()
  if chooser then chooser:insertSelected() end
end

--- M:configure(opts) - merge injected deps across the two callers. The spoon root
--- injects `api`, the view over the engine, and `metrics`, the sampler's slice of the
--- policy. The main root injects `theme`, the Chooser factory as `chooser`, the
--- matcher, the shared canvas surface as `surface`, and the docked shortcut panel
--- callbacks, the same seams every other chooser receives.
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

--- M:start() - build the one native chooser, once both configures have run.
---
--- The pane is configured first, because whether there is one at all decides whether
--- the atom reserves room beside the list, and that is fixed when the instance is
--- built. With no surface injected the pane stands down and the picker comes up exactly
--- as it did before it existed, rather than half wired.
function M:start()
  preview.configure({
    surface = cfg.surface,
    -- Read through the instance rather than captured, so the pane picks up the palette
    -- the atom selected for THIS open and follows the light and dark switch with it.
    palette = function() return chooser and chooser:activeTheme().preview end,
    -- The one sampler this file already holds. Handing it over rather than letting the
    -- pane load its own matters, since loadfile returns a fresh module every call and a
    -- second sampler would keep its own empty history behind every sparkline.
    metrics = metrics,
    formatCpu = formatCpu,
  })

  chooser = cfg.chooser.new({
    theme = cfg.theme,
    placeholder = cfg.placeholder or "Search project, port, runtime",
    fieldMode = cfg.chooser.fieldModes.filter,
    -- The word matcher rather than the shared fuzzy default, the same choice the
    -- clipboard makes and for the same reason. A query here is a real fragment you
    -- remember, a port number or a project name, not an abbreviation of a short
    -- known label, and subsequence matching over a haystack containing digits and
    -- paths ranks badly on exactly those. Words also keeps the engine's recency
    -- order instead of reranking it.
    matcher = cfg.matcher,
    rows = supplier,
    onSelect = onSelect,
    -- Setting this is what starts the atom's highlight poll, so the pane costs a timer
    -- only when there is a pane to feed.
    onHighlight = preview.isEnabled() and onHighlight or nil,
    onPositioned = onPositioned,
    onActivity = cfg.onActivity,
    -- Compose the root's panel teardown with the confirmation behavior. A pending
    -- confirm asked to re-show, anything else is a real dismissal and clears it, so
    -- an escape out of the confirmation leaves the process alone.
    --
    -- The sampler stops here, on the atom's one idempotent teardown path, which fires
    -- once for a selection, an escape, a click away, or a programmatic close alike. So
    -- there is no dismissal that leaves a timer behind, and the re-show for a
    -- confirmation starts a fresh one rather than keeping the old one alive across a
    -- screen with no rows on it.
    --
    -- The pane goes with it, on the same path and for the same rule. It is destroyed
    -- rather than hidden, so a dismissal leaves nothing behind at all, and the re-show
    -- for a confirmation builds a fresh one the way any other open does.
    onClose = function()
      metrics.stop()
      preview.destroy()
      if cfg.onClose then cfg.onClose() end
      if reopen then
        reopen = false
      else
        pending = nil
      end
    end,
    layout = {
      -- Room beside the list for the detail pane, and zero when there is no pane to
      -- put there, which is what makes the whole feature degrade to the picker as it
      -- was rather than to a gap where something should be.
      companionWidth = preview.isEnabled() and (cfg.previewWidth or true) or 0,
    },
  })
  return M
end

return M
