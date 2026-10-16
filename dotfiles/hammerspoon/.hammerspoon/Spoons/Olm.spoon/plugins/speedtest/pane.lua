--- === Speedtest.pane ===
---
--- The companion pane docked beside the list, where every figure a run returns actually lands. A
--- row holds three numbers and a run answers twenty, which is the whole argument for the pane
--- existing at all.
---
--- The canvas, the dock, the empty state, the scroll and its thumb, and the teardown all belong to
--- the shared docked pane, lib/dockedpane.lua, which the root grants because the manifest declares
--- `pane = true`. This file keeps only which view is on screen. It draws four different things and
--- knows which by which function was called, a run being taken right now, a finished run, the
--- trend across a network's history, and a block of explanation. What each looks like is built as
--- UI kit nodes by pane-nodes.lua, which is also where the two kinds of graph, a curve and bars,
--- and the reason they differ are written down.
---
--- Content taller than the pane scrolls, since a finished run says more than a pane holds at the
--- sizes a chooser reserves, and a thumb at the right edge says so while there is more than fits.

local panePath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local nodes = loadfile(panePath .. "pane-nodes.lua")()

local M = {}

local pane = nil  -- the shared docked pane, made in configure from the root's grant
local model = nil -- the view on screen, read by describe on every paint

-- What the model on screen is made of, as one node. Every view is built by pane-nodes.lua. A
-- function of the kit the pane hands over, so a redock or a refresh lays out the current model.
local function describe(ui)
  if model.what == "running" then
    return nodes.running(ui, model)
  elseif model.what == "result" then
    return nodes.result(ui, model.record, model.label, model.history)
  elseif model.what == "trend" then
    return nodes.trend(ui, model.history, model.label, model.note)
  end
  return nodes.text(ui, model.title, model.lines)
end

--- pane.configure(opts) - injected by the file that owns the picker.
--- opts.dockedPane  the root's docked pane grant, a function answering a pane. Absent means no
---                  pane at all, see isEnabled.
function M.configure(opts)
  opts = opts or {}
  if not pane and opts.dockedPane then
    pane = opts.dockedPane({ scroll = true, thumb = true })
  end
  return M
end

--- pane.isEnabled() - whether a pane can be drawn at all.
function M.isEnabled()
  return pane ~= nil and pane.isEnabled() and true or false
end

--- pane.dock(companionFrame) - take the rect the chooser reported.
function M.dock(companionFrame)
  if pane then pane.dock(companionFrame) end
end

-- Every show starts at the top, since the content underneath it changed.
local function show(next)
  model = next
  if pane then pane.show(describe) end
end

--- pane.showRunning(state) - the run being taken right now.
--- state.samples the live trail, state.elapsed and state.limit the seconds, state.live whether
--- figures can arrive at all.
function M.showRunning(state)
  show({
    what = "running",
    samples = state.samples or {},
    elapsed = state.elapsed or 0,
    limit = state.limit or 10,
    live = state.live and true or false,
  })
end

--- pane.refreshRunning(state) - the same view with fresh figures, keeping the scroll where the
--- person put it, since this is called several times a second and resetting it would make the
--- pane impossible to read while a run is on.
function M.refreshRunning(state)
  if not (model and model.what == "running") then
    M.showRunning(state)
    return
  end
  model.samples = state.samples or {}
  model.elapsed = state.elapsed or 0
  if pane then pane.repaint() end
end

--- pane.showResult(record, label, history) - one finished run in full.
function M.showResult(record, label, history)
  if not record then
    M.clear()
    return
  end
  show({ what = "result", record = record, label = label, history = history or {} })
end

--- pane.showTrend(history, label, note) - a network's own past.
function M.showTrend(history, label, note)
  show({ what = "trend", history = history or {}, label = label, note = note })
end

--- pane.showText(title, lines) - a block of explanation, for a page whose highlight has something
--- to say and no measurement behind it.
function M.showText(title, lines)
  show({ what = "text", title = title, lines = lines or {} })
end

--- pane.scrollBy(points) -> whether anything moved.
--- Negated on the way through. This pane has always moved against the sign the chooser hands
--- every pane, and the shared piece takes positive as further down, so the negation keeps the
--- direction a person already knows here exactly as it was.
function M.scrollBy(points)
  if not pane then return false end
  return pane.scrollBy(-(points or 0))
end

--- pane.clear() - the shared empty state, for a highlight with nothing to describe.
function M.clear()
  model = nil
  if pane then pane.clear() end
end

--- pane.hide() - hide without destroying, for the stage's own swap away signal.
function M.hide()
  if pane then pane.hide() end
end

--- pane.destroy() - tear the pane down completely, on the one teardown path.
function M.destroy()
  model = nil
  if pane then pane.destroy() end
end

return M
