--- === Settings.pane ===
---
--- The companion pane docked beside the Plugins page, where the highlighted plugin's about block,
--- its needs and what else moves with it are drawn. Only that page reserves a pane, the top level
--- and the other two pages declare none, so the stage places and removes it as the page comes and
--- goes.
---
--- A canvas of its own rather than a CanvasPanel instance, for the reason the speedtest and
--- clipboard panes give, it has to land exactly on the companion rect the chooser reserved. The
--- surface is the shared one, injected, and every piece of text and colour comes from the kit.
--- Content is built as a function of the kit, so a redock or a theme change repaints from the
--- same description without anyone being told again. There is no scroll, since a plugin's block
--- is short, and anything taller than the pane is cut at its edge.

local M = {}

local cfg = {}
local canvas = nil
local frame = nil
local build = nil   -- the last description asked for, so a redock repaints without being told
local hidden = false

local function ensureCanvas()
  if canvas then return end
  canvas = hs.canvas.new(frame)
  canvas:level(hs.canvas.windowLevels.floating)
  -- A click on the pane must not pull focus off the search field.
  canvas:clickActivating(false)
end

local function innerRect()
  local pad = cfg.ui.tokens().pad
  return { x = pad, y = pad, w = frame.w - 2 * pad, h = frame.h - 2 * pad }
end

-- The shared empty state draws in its own box at the origin, so it is moved into place here.
local function shifted(el, dx, dy)
  local copy = {}
  for k, v in pairs(el) do copy[k] = v end
  if el.frame then
    copy.frame = { x = (el.frame.x or 0) + dx, y = (el.frame.y or 0) + dy,
                   w = el.frame.w, h = el.frame.h }
  end
  return copy
end

local function paint()
  if hidden or not (build and frame and cfg.surface and cfg.ui) then return end
  ensureCanvas()
  local ui = cfg.ui
  local rect = innerRect()
  local viewport = ui.interior(frame.w, frame.h)
  local content = ui.layout(build(ui), rect, { tokens = ui.tokens(), viewport = viewport })
  local els = {}
  for _, el in ipairs(cfg.surface(frame.w, frame.h)) do els[#els + 1] = el end
  for _, el in ipairs(content) do els[#els + 1] = el end
  canvas:frame(frame)
  canvas:replaceElements(els)
  canvas:show()
end

--- pane.configure(opts) - opts.surface, opts.emptyState and opts.ui, all injected. With no
--- surface or kit the pane stays dark, see isEnabled.
function M.configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  return M
end

--- pane.isEnabled() - whether a pane can be drawn at all.
function M.isEnabled()
  return cfg.surface ~= nil and cfg.ui ~= nil
end

--- pane.dock(companionFrame) - take the rect the stage reported. Fired with a seed rect at show
--- and again once the real window settles, so a redock is expected.
function M.dock(companionFrame)
  if not (M.isEnabled() and companionFrame) then return end
  frame = companionFrame
  hidden = false
  if build then paint() end
end

--- pane.show(describe) - describe is a function of the kit answering the node to draw.
function M.show(describe)
  build = describe
  paint()
end

--- pane.clear() - the shared empty state, for a highlight with nothing to describe. The pane stays
--- up rather than vanishing, since a reserved rectangle with nothing in it reads as a broken
--- layout.
function M.clear()
  build = nil
  if hidden or not (frame and cfg.surface and cfg.ui) then return end
  ensureCanvas()
  local rect = innerRect()
  local els = {}
  for _, el in ipairs(cfg.surface(frame.w, frame.h)) do els[#els + 1] = el end
  -- The manifest declares a pane surface, so the empty state always arrives beside it. Were it
  -- missing, the pane would still stay up with its backdrop and nothing drawn on it, since a
  -- docked pane is never hidden while its presentation shows.
  for _, el in ipairs(cfg.emptyState and cfg.emptyState(rect.w, rect.h) or {}) do
    els[#els + 1] = shifted(el, rect.x, rect.y)
  end
  canvas:frame(frame)
  canvas:replaceElements(els)
  canvas:show()
end

--- pane.hide() - hide without destroying, for the stage's own swap away signal.
function M.hide()
  hidden = true
  if canvas then canvas:hide() end
end

--- pane.destroy() - tear the pane down on the one teardown path.
function M.destroy()
  build = nil
  frame = nil
  hidden = false
  if canvas then
    canvas:delete()
    canvas = nil
  end
end

return M
