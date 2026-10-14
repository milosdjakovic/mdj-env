--- === Speedtest.pane ===
---
--- The companion pane docked beside the list, where every figure a run returns actually lands. A
--- row holds three numbers and a run answers twenty, which is the whole argument for the pane
--- existing at all.
---
--- A canvas of its own rather than a CanvasPanel instance, the same choice the clipboard and
--- processes previews both make and for the same reason. A CanvasPanel computes its own placement
--- and sizes itself from its content, while this pane has to land exactly on the companion rect
--- the chooser atom reserved and reported. Drawing anywhere else would put it outside the rect the
--- atom's click watcher treats as part of the picker, so a click on the pane would dismiss the
--- list instead of passing through. What it does share is the surface itself, injected as
--- CanvasPanel.surfaceElements, so this pane, the docked shortcut panel and the cheat sheets are
--- one component drawn in three places rather than three lookalikes.
---
--- It draws four different things and knows which by which function was called, a run being taken
--- right now, a finished run, the trend across a network's history, and a block of explanation.
--- What each looks like is built as UI kit nodes by pane-nodes.lua, which is also where the two
--- kinds of graph, a curve and bars, and the reason they differ are written down. This file is the
--- canvas, the scroll and the choice of which view is on screen, and every piece of text and every
--- colour in it comes from the kit, so a font, a size or a colour is never named here.
---
--- Content taller than the pane scrolls, since a finished run says more than a pane holds at the
--- sizes a chooser reserves. The scroll arrives from the atom rather than from a key of this
--- plugin's own, so it costs no binding anywhere. Scroll events add up and one paint is made for
--- the next frame, since a trackpad sends dozens a second and a paint is a layout.

local panePath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local nodes = loadfile(panePath .. "pane-nodes.lua")()

local M = {}

-- Injected, see M.configure. Empty until then, and with no surface or kit injected the pane
-- stays dark, which is the whole degradation path, see M.isEnabled.
local cfg = {}

local canvas = nil
local frame = nil
local model = nil     -- the last thing asked for, so a redock repaints without being told again
local hidden = false
local scrollY = 0     -- how far the body is scrolled, always clamped to the real overflow
local maxScroll = 0   -- how far it can go, recomputed on every paint since content changes
local scrollTimer = nil -- the one pending scroll paint, see M.scrollBy

-- One display frame, the longest a scroll event waits for its paint.
local SCROLL_FRAME = 1 / 60

-- The thumb of the scroll bar, geometry rather than type. It sits SCROLL_EDGE in from the right
-- edge of the pane and is never shorter than SCROLL_MIN.
local SCROLL_EDGE, SCROLL_W, SCROLL_MIN = 7, 3, 18

local function stopScrollTimer()
  if scrollTimer then
    scrollTimer:stop()
    scrollTimer = nil
  end
end

-- The inner box the pane is laid out in, the frame less the kit's one inset, which is the space
-- around content every surface shares. In the canvas's own coordinates.
local function innerRect()
  local inset = cfg.ui.tokens().inset
  return { x = inset.x, y = inset.y, w = frame.w - 2 * inset.x, h = frame.h - 2 * inset.y }
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function ensureCanvas()
  if canvas then return end
  canvas = hs.canvas.new(frame)
  canvas:level(hs.canvas.windowLevels.floating)
  -- A click on the pane must not pull focus off the search field. The atom's click watcher
  -- already treats a point inside the companion rect as part of the picker and passes it
  -- through, so between the two a click here changes nothing.
  canvas:clickActivating(false)
end

-- What the model on screen is made of, as one node. Every view is built by pane-nodes.lua.
local function buildBody()
  local ui = cfg.ui
  if model.what == "running" then
    return nodes.running(ui, model)
  elseif model.what == "result" then
    return nodes.result(ui, model.record, model.label, model.history)
  elseif model.what == "trend" then
    return nodes.trend(ui, model.history, model.label, model.note)
  end
  return nodes.text(ui, model.title, model.lines)
end

-- A shallow copy of an element with its frame offset, for the shared empty state, which draws in
-- its own box at the origin and is placed here.
local function shifted(el, dx, dy)
  local copy = {}
  for k, v in pairs(el) do copy[k] = v end
  if el.frame then
    copy.frame = { x = (el.frame.x or 0) + dx, y = (el.frame.y or 0) + dy,
                   w = el.frame.w, h = el.frame.h }
  end
  return copy
end

-- subtext laid over with the kit's fade alpha, the look of a thumb that is there without
-- competing with the text, an alpha over a role and not a colour of its own.
local function thumbColor(tokens)
  local color = {}
  for k, v in pairs(tokens.colors.subtext) do color[k] = v end
  color.alpha = (color.alpha or 1) * tokens.alpha.fade
  return color
end

local function paint()
  if hidden then return end
  if not (model and frame and cfg.surface and cfg.ui) then return end
  ensureCanvas()
  local ui = cfg.ui
  local tokens = ui.tokens()
  local rect = innerRect()

  local body = buildBody()
  -- Laid out in the padded box and cut at the inside of the border, so a line scrolled past
  -- the padding is cut by the edge of the pane rather than by the padding.
  local viewport = ui.interior(frame.w, frame.h)
  local content, bodyH = ui.layout(body, rect, { scrollY = scrollY, tokens = tokens, viewport = viewport })
  maxScroll = math.max(0, (bodyH or 0) - rect.h)
  -- The offset is clamped here, against the height the layout answers, so a scroll, a rebuild at
  -- a new height and a run that grows underneath it all land somewhere real.
  if scrollY > maxScroll or scrollY < 0 then
    scrollY = math.max(0, math.min(scrollY, maxScroll))
    content = ui.layout(body, rect, { scrollY = scrollY, tokens = tokens, viewport = viewport })
  end

  local els = {}
  for _, el in ipairs(cfg.surface(frame.w, frame.h)) do els[#els + 1] = el end
  for _, el in ipairs(content) do els[#els + 1] = el end

  -- A thumb rather than a hint in words, drawn only while there is genuinely more than fits, so a
  -- pane that holds all of its content carries no chrome at all.
  if maxScroll > 0 then
    local thumbH = math.max(SCROLL_MIN, rect.h * (rect.h / bodyH))
    local travel = rect.h - thumbH
    local radius = SCROLL_W / 2
    els[#els + 1] = { type = "rectangle", action = "fill",
      roundedRectRadii = { xRadius = radius, yRadius = radius }, fillColor = thumbColor(tokens),
      frame = { x = frame.w - SCROLL_EDGE, y = rect.y + (scrollY / maxScroll) * travel,
                w = SCROLL_W, h = thumbH } }
  end

  canvas:frame(frame)
  canvas:replaceElements(els)
  canvas:show()
end

--------------------------------------------------------------------------------
-- Public surface, dot called
--------------------------------------------------------------------------------

--- pane.configure(opts) - injected by the file that owns the picker.
--- opts.surface     function(w, h) -> canvas elements, the shared CanvasPanel surface. Absent
---                  means no pane at all, see isEnabled.
--- opts.emptyState  function(w, h, opts) -> the shared quiet state a docked pane paints when its
---                  highlight has nothing to describe.
--- opts.ui          the UI kit, needs.lib.ui, which every piece of text and every colour in the
---                  pane comes through and which follows the system appearance itself. Absent
---                  means no pane at all, the same as no surface.
function M.configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  return M
end

--- pane.isEnabled() - whether a pane can be drawn at all, which is to say whether the root
--- injected the shared surface and the kit.
function M.isEnabled()
  return cfg.surface ~= nil and cfg.ui ~= nil
end

--- pane.dock(companionFrame) - take the rect the chooser atom reported. Fired with a seed rect at
--- show and again once the real window settles, so a redock is expected.
function M.dock(companionFrame)
  if not (M.isEnabled() and companionFrame) then return end
  frame = companionFrame
  hidden = false
  if model then paint() end
end

-- Every show resets the scroll, since the content underneath it changed and holding a position
-- measured against something else would land somewhere arbitrary.
local function show(next)
  model = next
  scrollY = 0
  stopScrollTimer()
  paint()
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
  paint()
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
--- The atom hands over a distance already normalised for a wheel against a trackpad and already
--- corrected for direction, so this only has to clamp and repaint. The offset moves at once and
--- the paint waits for the next frame, so however many events land before it they cost one layout.
function M.scrollBy(points)
  if not (model and frame and maxScroll > 0) then return false end
  local next = math.max(0, math.min(maxScroll, scrollY - (points or 0)))
  if next == scrollY then return false end
  scrollY = next
  if not scrollTimer then
    scrollTimer = hs.timer.doAfter(SCROLL_FRAME, function()
      scrollTimer = nil
      paint()
    end)
  end
  return true
end

--- pane.clear() - the shared empty state, for a highlight with nothing to describe. The pane stays
--- up rather than vanishing, since a reserved rectangle with nothing in it reads as a broken
--- layout. It genuinely disappears only on the stage's own swap signal and on destroy.
function M.clear()
  model = nil
  scrollY = 0
  maxScroll = 0
  stopScrollTimer()
  if hidden then return end
  if not (frame and cfg.surface and cfg.ui) then return end
  if not cfg.emptyState then
    if canvas then canvas:hide() end
    return
  end
  ensureCanvas()
  local rect = innerRect()
  local els = {}
  for _, el in ipairs(cfg.surface(frame.w, frame.h)) do els[#els + 1] = el end
  for _, el in ipairs(cfg.emptyState(rect.w, rect.h)) do
    els[#els + 1] = shifted(el, rect.x, rect.y)
  end
  canvas:frame(frame)
  canvas:replaceElements(els)
  canvas:show()
end

--- pane.hide() - hide without destroying, for the stage's own swap away signal.
function M.hide()
  hidden = true
  stopScrollTimer()
  if canvas then canvas:hide() end
end

--- pane.destroy() - tear the pane down completely, on the one teardown path.
function M.destroy()
  stopScrollTimer()
  model = nil
  frame = nil
  hidden = false
  scrollY = 0
  maxScroll = 0
  if canvas then
    canvas:delete()
    canvas = nil
  end
end

return M
