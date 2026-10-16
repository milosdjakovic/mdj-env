--- Processes preview pane.
---
--- The companion pane docked beside the picker, showing what a single row has no room
--- to say. The full working directory, every port, the live trend, and above all the
--- process tree a stop would take, since seeing that one row is five processes and
--- which five is what makes pressing stop safe.
---
--- The canvas, the dock, the empty state, the hide guard and the teardown belong to the
--- shared docked pane, lib/dockedpane.lua, which the root grants because the manifest
--- declares `pane = true`. This file is the painter that pane calls, the live block over the
--- cached static block, and the cache itself.
---
--- Dot called, like util and metrics, and it holds no policy of its own. The docked pane,
--- the UI kit, the sampler's two accessors and the CPU formatter are all injected by the
--- surface that owns the picker, so this file names nothing concrete and cannot drift from
--- the row it is describing.
---
--- Every piece of text is drawn through the kit's five roles and every colour is a role
--- name, so this file names no font, size, line height or colour. What the pane is made of,
--- the live block, the sections and the tree, is built as kit nodes by pane-nodes.lua,
--- which loads in plain Lua and is covered by a unit case. This file owns what has a
--- view to draw in, the cache, the sampler's figures and the painter.
---
--- The redraw is split in two because it has two very different callers. The static
--- half, everything derived from the row itself, is built once per row and cached,
--- since the highlight poll fires often and a row's command line and tree do not
--- change under it. The live half, the two figures and their sparklines, is rebuilt on
--- every paint, which is the only work a sampler tick costs. Its HEIGHT is fixed by
--- whether the row can be sampled at all rather than by whether a reading has landed
--- yet, so the static half below it never shifts when the first sample arrives and the
--- cache stays valid across the whole open.
---
--- Rows differ and the pane must never show a labelled section with nothing under it.
--- A section whose text comes back empty is dropped entirely, label included, so a
--- container row shows no DIRECTORY heading and no TREE heading, a portless watcher
--- shows no PORTS heading, and a container, which is deliberately never sampled,
--- reserves no room for figures it will never have.


local previewPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local util = loadfile(previewPath .. "util.lua")()
local nodes = loadfile(previewPath .. "pane-nodes.lua")()

local M = {}

-- Injected, see M.configure. Empty until then, and with no docked pane or kit injected the
-- pane stays dark, which is the whole degradation path, see M.isEnabled.
local cfg = {}

local pane = nil  -- the shared docked pane, made in configure from the root's grant
local model = nil -- the cached static half of the row on screen, see buildModel

--------------------------------------------------------------------------------
-- The live block's figures
--------------------------------------------------------------------------------

-- One field of the sampler's trail for a row, oldest first. The sampler only remembers
-- a reading once it carries a CPU figure, so the two trails always have the same length
-- and neither can contain a hole.
local function trail(key, field)
  local history = cfg.metrics and cfg.metrics.history(key)
  if not history then return {} end
  local out = {}
  for i, reading in ipairs(history) do out[i] = reading[field] or 0 end
  return out
end

local function extremes(values)
  if #values == 0 then return 0, 0 end
  local lo, hi = values[1], values[1]
  for _, v in ipairs(values) do
    if v < lo then lo = v end
    if v > hi then hi = v end
  end
  return lo, hi
end

-- What the live block shows for a row right now, the two headings' facts and the two trails
-- with the range each strip stands for, rebuilt on every paint. The block is built from this
-- by pane-nodes.lua, and a row that cannot be sampled never reaches here.
--
-- A container is never sampled. Asking the docker daemon for stats costs more than the whole
-- scan, so those rows carry no live figures by design, and a strip drawn for them would be a
-- permanently empty one.
--
-- The two strips are scaled differently on purpose. CPU is an absolute question, is
-- this thing busy, so it runs from zero to the window's peak with a floor under it.
-- Memory is a relative one, is this thing growing, so it runs across the window's own
-- range, where a leak climbs and a steady server sits flat down the middle. The figures
-- beside each heading carry the absolute anchor either way.
local function liveSpec(row)
  local reading = cfg.metrics and cfg.metrics.reading(row.key)
  local cpuTrail = trail(row.key, "cpu")
  local memTrail = trail(row.key, "rss")
  -- A plain percentage if nothing was injected, so a missed wiring costs the rounding
  -- rather than throwing inside the highlight poll on every fire.
  local formatCpu = cfg.formatCpu or function(pct) return string.format("%.1f%%", pct) end

  -- The peak is printed only when it is above the figure beside it. A peak that IS the
  -- current reading is the same number written twice, which costs the line's width and
  -- tells you nothing, and it is exactly the case a quiet steady process is always in.
  local facts = {}
  local cpu = reading and reading.cpu
  if cpu then facts[#facts + 1] = formatCpu(cpu) end
  local _, cpuPeak = extremes(cpuTrail)
  if cpuPeak > (cpu or 0) then facts[#facts + 1] = "peak " .. formatCpu(cpuPeak) end
  local cpuStrip = { facts = table.concat(facts, "   "), values = cpuTrail,
                     lo = 0, hi = math.max(cpuPeak, nodes.CPU_FLOOR) }

  facts = {}
  -- The scan's own reading stands in until the first sample lands, the same fallback
  -- the row subtitle takes, so the pane is never briefly missing a figure it is about
  -- to have.
  local rss = (reading and reading.rss) or row.rss
  if rss then facts[#facts + 1] = util.humanBytes(rss) end
  local memLo, memHi = extremes(memTrail)
  if memHi > (rss or 0) then facts[#facts + 1] = "peak " .. util.humanBytes(memHi) end
  local memStrip = { facts = table.concat(facts, "   "), values = memTrail, lo = memLo, hi = memHi }

  return { cpu = cpuStrip, mem = memStrip }
end

--------------------------------------------------------------------------------
-- The static model, built once per row
--------------------------------------------------------------------------------

-- Everything the row itself says, laid out below the space the live block takes. Cached by the
-- row and the box it was laid out in, so the highlight poll pays for this once per row rather
-- than once per fire, and a re dock at a corrected frame rebuilds it because the tree's cut
-- depends on the height.
--
-- The elements are kept, as file search keeps its header's, so the sampler's tick lays out the
-- live block and nothing else. They are laid out in their own rect, which starts at the live
-- block's height, so painting them needs no shifting.
local function buildModel(row, rect)
  local liveH = nodes.liveSpan(cfg.ui, row)
  local below = { x = rect.x, y = rect.y + liveH, w = rect.w, h = rect.h - liveH }
  local node = nodes.static(cfg.ui, row, below.w, below.h)
  local els = node and cfg.ui.layout(node, below) or {}
  return { row = row, w = rect.w, h = rect.h, els = els }
end

--------------------------------------------------------------------------------
-- Painting
--------------------------------------------------------------------------------

-- The painter the docked pane calls, the live block and the cached static block, drawn over the
-- surface the pane paints first. Called by a new highlight and by every sampler tick alike, and
-- the only work it repeats is the live block, which is two headings and two short polylines. The
-- sampler ticks every 1.5 seconds while the list is showing, and the pane's own hide guard is
-- what keeps a tick from bringing the canvas back beside a tool that is no longer current.
--
-- A redock at a corrected frame changes the box, which changes where the tree has to stop, so
-- the static half is rebuilt here when the box moved rather than when the dock fired.
local function paintRow(view)
  local rect = view.inner
  if not (model.w == rect.w and model.h == rect.h) then
    model = buildModel(model.row, rect)
  end
  -- Clip to the inner box, so a tree cut a line short of fitting still stops at the
  -- padding rather than crossing the border.
  local els = { { type = "rectangle", action = "clip", frame = rect } }
  local live = nodes.live(cfg.ui, model.row, model.row.pid and liveSpec(model.row))
  if live then
    for _, el in ipairs(cfg.ui.layout(live, rect)) do els[#els + 1] = el end
  end
  for _, el in ipairs(model.els) do els[#els + 1] = el end
  return els, 0
end

--------------------------------------------------------------------------------
-- Public surface (dot-called)
--------------------------------------------------------------------------------

--- preview.configure(opts) - injected by the surface that owns the picker.
--- opts.dockedPane the root's docked pane grant, a function answering a pane. Absent means
---                 no pane at all, see isEnabled.
--- opts.ui         the UI kit, needs.lib.ui, which every piece of text in the pane is drawn
---                 through and which follows the system appearance itself. Absent means no
---                 pane at all, the same as no surface.
--- opts.metrics    the live sampler, of which only reading(key) and history(key) are
---                 called. Injected rather than loaded here, because loadfile returns a
---                 fresh module each time and a second copy of the sampler would hold
---                 its own empty history and every sparkline would stay flat.
--- opts.formatCpu  the row's own percentage formatter, injected so the figure in the
---                 pane and the figure on the row can never round differently.
function M.configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  if not pane and cfg.dockedPane then pane = cfg.dockedPane() end
  return M
end

--- preview.isEnabled() -> boolean
--- Whether a pane can be drawn at all, which is to say whether the composition root
--- granted the docked pane and the kit. The picker asks before reserving a companion
--- rect, so a root that wires nothing gets the picker exactly as it was rather than a pane
--- of unreadable text floating over the desktop with no background behind it.
function M.isEnabled()
  return pane ~= nil and pane.isEnabled() and cfg.ui ~= nil
end

--- preview.dock(companionFrame) - take the rect the Chooser atom reported.
--- Fired with a seed rect at show and again once the real window settles, so a re dock
--- is expected.
function M.dock(companionFrame)
  if not M.isEnabled() then return end
  -- The highlight seed the caller runs right after this call is what actually fills the
  -- pane, cold or not, a nil highlight landing in M.clear same as any other.
  pane.dock(companionFrame)
end

--- preview.show(row) - render a row, or clear the pane when handed nothing.
--- The static half is rebuilt only when the row or its box changed, so this is cheap
--- enough to be called straight from the atom's highlight poll.
---
--- The cache is keyed on the row TABLE rather than on its key, which is what makes both
--- cases right at once. A poll that has not moved hands back the very same table and
--- pays nothing, while a rescan hands back a fresh one under the same key and rebuilds,
--- which it must, since a tree grows and shrinks between scans and the count under it
--- is the whole reason the pane is there.
function M.show(row)
  local rect = M.isEnabled() and pane.inner()
  if not rect then return end
  if not row then
    M.clear()
    return
  end
  if not (model and model.row == row and model.w == rect.w and model.h == rect.h) then
    model = buildModel(row, rect)
  end
  pane.draw(paintRow)
end

--- preview.refresh() - redraw the row already on screen.
--- The seam the sampler tick uses. There is no timer here and none is wanted, the
--- surface already ticks once per sample and calls this, so the sparklines advance in
--- step with the figures on the rows and nothing polls twice.
function M.refresh()
  if model and pane then pane.repaint() end
end

--- preview.clear() - the shared empty state, for a frame with nothing to preview, the
--- empty list row or a confirmation screen with no target. The pane stays up rather than
--- vanishing, and genuinely disappears only on the stage's own swap signal, M.hide below,
--- and on M.destroy.
function M.clear()
  model = nil
  if pane then pane.clear() end
end

--- preview.hide() - hide the canvas without destroying it, for the stage's own swap away
--- signal, onPositioned told nil twice when a different presentation becomes current. The
--- canvas, the frame and the model all survive, so a swap back to this
--- presentation docks again and repaints at once rather than rebuilding from nothing.
function M.hide()
  if pane then pane.hide() end
end

--- preview.destroy() - tear the pane down completely.
--- Hooked to the picker's one teardown path, the same place the sampler stops, so no
--- dismissal leaves a canvas behind. Deleted rather than hidden because nothing may
--- survive a close, and rebuilding one canvas on the next open costs nothing.
function M.destroy()
  model = nil
  if pane then pane.destroy() end
end

return M
