--- === CanvasPanel ===
---
--- The default canvas surface for this config, plus a panel that docks it around an
--- anchor frame (typically a chooser) or centers it on screen. It is two things that
--- fit together.
---
--- First, it OWNS the shared surface look. One style, set once from the composition
--- root via CanvasPanel.configure(style), holds the light and dark background, the
--- border, the border width, and the corner radius. The panel resolves the current
--- appearance on every draw, so a surface tracks the system light and dark switch.
--- Because the style lives in one place, every surface drawn through this atom looks
--- identical, and editing that one style restyles all of them at once.
--- CanvasPanel.surfaceElements(w, h) is the single routine that paints the surface, a
--- filled rounded rectangle plus a rounded border. The panel's own show() uses it, and
--- a consumer that owns its own canvas (the clipboard preview) prepends the same
--- elements, so nothing draws the surface a second way.
---
--- Second, it is the mechanism for a docked panel: placement (below / above / left /
--- right / center), sizing, and reveal timing. WHAT it shows is a pluggable content
--- renderer injected by the caller, so a purpose like a shortcut-hint bar is one
--- content object and the panel stays ignorant of it. The composition root creates an
--- instance per purpose and wires show/hide to a chooser's onPositioned/onClose.
---
--- This is the Strategy pattern: the panel is the context that owns placement and the
--- surface, the content is the strategy that owns what is drawn. Add a new purpose by
--- writing a new content object, never by editing the panel.
---
--- MODULE API (dot-called):
---   CanvasPanel.configure(opts)                the one injection door. opts.surface sets
---                                              the shared surface style (below); opts.screen
---                                              sets the function a centered panel uses to
---                                              pick its screen (opts.screen() -> hs.screen),
---                                              defaulting to hs.screen.mainScreen so the atom
---                                              still places itself if nothing is injected.
---                                              Callable more than once; each call merges.
---   CanvasPanel.surfaceElements(w, h, style?)  the surface elements for a w x h box at
---                                              origin (0, 0); style overrides the default.
---   CanvasPanel.new(config) -> instance        a docked or centered panel.
---
--- style (all optional; omit a field to draw nothing for it):
---   cornerRadius  surface rounding in points (0 = square).
---   borderWidth   border stroke width (default 1).
---   dark, light   each { bg = "#RRGGBB", border = "#RRGGBB" }. The side matching the
---                 live appearance is used; light falls back to dark when absent.
---
--- Reveal timing. By default the panel draws the instant show/arm is called. Give it a
--- delay and it becomes idle-timed instead: arm(anchor) starts a countdown rather than
--- drawing, poke() restarts that countdown (call it on each keypress), and when the
--- countdown expires the panel reveals and latches, staying up until hide() regardless of
--- later pokes. This is the deferred hint bar: hidden while the field is in active use,
--- shown once the user pauses. The panel owns only the timing; it never learns where the
--- pokes come from, so a caller wires its own activity source to poke().
---
--- config (all optional unless noted):
---   placement  "below" (default) | "above" | "left" | "right" | "center". The
---              first four dock the panel relative to the anchor; "center" ignores
---              the anchor and centers the panel on the active screen, so show()
---              and arm() may be called with no anchor. Used by the cheat sheet
---              overlay, which is a standalone centered panel rather than a dock.
---   delay      idle milliseconds before arm() reveals the panel; nil or 0 draws it
---              instantly. Once revealed it stays until hide(), so poke() after that is
---              a no-op.
---   gap        points between the anchor and the panel (default 8).
---   length     the panel's size along its own axis: height for below/above, width
---              for left/right. nil = auto from the content's preferred size.
---   breadth    the panel's size along the shared axis: width for below/above,
---              height for left/right. nil = match the anchor's size on that axis.
---   align      "start" (default) | "center" | "end", along the shared axis when
---              breadth is smaller than the anchor.
---   padX, padY inner padding around the content (default 14, 10).
---   style      per-instance surface override; nil inherits the configured default.
---   level      canvas window level (default hs.canvas.windowLevels.popUpMenu).
---   content    REQUIRED renderer:
---                preferredSize(availW, availH) -> { w = , h = }
---                  availW/availH is the content box the panel offers (either may
---                  be nil when that axis is auto); return the natural content size.
---                draw(w, h) -> { <canvas element>, ... }
---                  draw into a w x h box with its origin at (0, 0); the panel
---                  offsets the elements by its padding and draws the surface behind
---                  them.
---                state() -> string, OPTIONAL. What is being said right now, as one
---                  comparable value. Content that can go stale while the panel sits
---                  there offers it, and the panel then polls while visible and redraws
---                  when the value changes, so what is on screen keeps being true. Omit
---                  it for fixed content and no timer runs at all.
---
--- This is the olm side copy of CanvasPanel, moved into the core as lib/panel.lua in phase
--- five of the build plan. It is a faithful copy, the module api and the instance api are
--- unchanged, so assigning it to the CanvasPanel spoon global is a drop in. The original
--- this was copied from still lives at Spoons/CanvasPanel.spoon.

local obj = {}
obj.__index = obj
obj.name = "CanvasPanel"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

function obj:init()
  return self
end

-- The one shared surface style, injected by the composition root. Nil until then,
-- in which case a panel simply draws no surface behind its content.
local DEFAULT_STYLE = nil

-- The screen a centered panel resolves against, injected by the composition root so
-- the atom does not name the display policy. It is the same seam every overlay reads,
-- so the cheat sheets and choosers agree on which display they use. Defaults to
-- hs.screen.mainScreen (the screen with the focused window), so a centered panel still
-- places itself if the root injects nothing. Resolved on each draw, so it tracks the
-- live state.
local SCREEN_PROVIDER = hs.screen.mainScreen

--- CanvasPanel.configure(opts) - the one injection door.
--- opts.surface sets the shared surface style (dark/light bg and border, border width,
---   corner radius). One source, so every surface this atom draws stays identical and one
---   edit restyles them all.
--- opts.screen sets the function a centered panel uses to pick its screen (opts.screen() ->
---   hs.screen), wiring the shared overlay display policy in.
--- Callable more than once, each call merges, so the root can set the surface early and the
--- screen later once its resolver exists. A field left out is left unchanged.
function obj.configure(opts)
  opts = opts or {}
  if opts.surface ~= nil then DEFAULT_STYLE = opts.surface end
  if opts.screen ~= nil then SCREEN_PROVIDER = opts.screen end
  return obj
end

-- Pick the side of a style matching the live appearance, falling back to dark.
local function styleSide(style)
  local dark = hs.host.interfaceStyle() == "Dark"
  return (dark and style.dark) or style.light or style.dark or {}
end

local function hexColor(hex)
  local r, g, b = hex:match("#?(%x%x)(%x%x)(%x%x)")
  if not r then return nil end
  return { red = tonumber(r, 16) / 255, green = tonumber(g, 16) / 255,
           blue = tonumber(b, 16) / 255, alpha = 1.0 }
end

--- CanvasPanel.surfaceElements(w, h, style) - the surface as canvas elements for a
--- w x h box at origin (0, 0): a filled rounded rectangle plus a rounded border,
--- resolved for the current appearance. This is the single place the surface is
--- painted, reused by show() and by any consumer that manages its own canvas. `style`
--- overrides the configured default for this call.
function obj.surfaceElements(w, h, style)
  style = style or DEFAULT_STYLE or {}
  local side = styleSide(style)
  local radius = style.cornerRadius or 0
  local bw = style.borderWidth or 1
  local radii = { xRadius = radius, yRadius = radius }
  local els = {}
  local bg = side.bg and hexColor(side.bg)
  if bg then
    els[#els + 1] = { type = "rectangle", action = "fill", fillColor = bg,
      roundedRectRadii = radii, frame = { x = 0, y = 0, w = w, h = h } }
  end
  local border = side.border and hexColor(side.border)
  if border then
    -- Inset by half the stroke so the full border stays inside the canvas bounds.
    els[#els + 1] = { type = "rectangle", action = "stroke", strokeColor = border,
      strokeWidth = bw, roundedRectRadii = radii,
      frame = { x = bw / 2, y = bw / 2, w = w - bw, h = h - bw } }
  end
  return els
end

local Panel = {}
Panel.__index = Panel

-- Offset a content element's frame by the panel padding, returning a shifted copy so
-- the content can draw in its own (0,0) box while the panel owns absolute placement.
local function shifted(el, dx, dy)
  local copy = {}
  for k, v in pairs(el) do copy[k] = v end
  if el.frame then
    copy.frame = { x = (el.frame.x or 0) + dx, y = (el.frame.y or 0) + dy,
                   w = el.frame.w, h = el.frame.h }
  end
  return copy
end

-- Compute the panel frame and the content box from the anchor, placement, and sizes.
function Panel:_layout(anchor)
  local c = self.config
  local padX, padY = c.padX or 14, c.padY or 10
  local gap = c.gap or 8
  local centered = (c.placement == "center")
  local horizontal = (c.placement == "left" or c.placement == "right")

  -- The shared axis matches the anchor unless breadth overrides it; the free axis
  -- comes from config.length, else the content's preferred size on that axis. A
  -- centered panel has no anchor to match, so both axes come from the content.
  local availW, availH
  if centered then
    availW, availH = nil, nil
  elseif horizontal then
    local breadth = c.breadth or anchor.h
    availH = breadth - 2 * padY
    availW = c.length and (c.length - 2 * padX) or nil
  else
    local breadth = c.breadth or anchor.w
    availW = breadth - 2 * padX
    availH = c.length and (c.length - 2 * padY) or nil
  end

  local ps = self.config.content.preferredSize(availW, availH) or { w = 0, h = 0 }
  local contentW = availW or ps.w
  local contentH = availH or ps.h
  local panelW = contentW + 2 * padX
  local panelH = contentH + 2 * padY

  -- Align along the shared axis when the panel is smaller than the anchor there.
  local function alignOn(start, anchorLen, panelLen)
    if c.align == "center" then return start + (anchorLen - panelLen) / 2 end
    if c.align == "end" then return start + anchorLen - panelLen end
    return start
  end

  local x, y
  if centered then
    local screen = SCREEN_PROVIDER() or hs.screen.mainScreen() or hs.screen.primaryScreen()
    local sf = screen:frame()
    x = sf.x + (sf.w - panelW) / 2
    y = sf.y + (sf.h - panelH) / 2
  elseif c.placement == "above" then
    x = alignOn(anchor.x, anchor.w, panelW)
    y = anchor.y - gap - panelH
  elseif c.placement == "left" then
    x = anchor.x - gap - panelW
    y = alignOn(anchor.y, anchor.h, panelH)
  elseif c.placement == "right" then
    x = anchor.x + anchor.w + gap
    y = alignOn(anchor.y, anchor.h, panelH)
  else -- below
    x = alignOn(anchor.x, anchor.w, panelW)
    y = anchor.y + anchor.h + gap
  end

  return { x = x, y = y, w = panelW, h = panelH }, contentW, contentH, padX, padY
end

--- CanvasPanel:show(anchorFrame) - place and draw the panel relative to anchorFrame
--- ({ x, y, w, h }). Safe to call repeatedly; the canvas is built once and reused.
function Panel:show(anchor)
  if not anchor and self.config.placement ~= "center" then return end
  local frame, contentW, contentH, padX, padY = self:_layout(anchor)

  local els = {}
  for _, el in ipairs(obj.surfaceElements(frame.w, frame.h, self.config.style)) do
    els[#els + 1] = el
  end
  for _, el in ipairs(self.config.content.draw(contentW, contentH) or {}) do
    els[#els + 1] = shifted(el, padX, padY)
  end

  if not self.canvas then
    self.canvas = hs.canvas.new(frame)
    self.canvas:level(self.config.level or hs.canvas.windowLevels.popUpMenu)
  else
    self.canvas:frame(frame)
  end
  self.canvas:replaceElements(els)
  self.canvas:show()
end

-- Start (or restart) the idle countdown. On expiry the panel reveals at the last armed
-- anchor and latches, so it stays up until hide clears the state.
function Panel:_startTimer()
  self.timer = hs.timer.doAfter((self.config.delay or 0) / 1000, function()
    self.timer = nil
    self.shown = true
    if self.anchor then self:show(self.anchor) end
    self:_startWatch()
  end)
end

-- How often a visible panel checks whether what it is showing is still true.
local WATCH_INTERVAL = 0.25

-- Keep a revealed panel honest, for content that can go stale while nobody touches it.
--
-- THE PANEL LATCHES VISIBLE, which is what made this necessary. Content is asked for on every
-- draw, so the reveal shows the truth, but after that nothing redraws and the answer drifts. For
-- shortcut hints that means a key gated on live state stays printed after it stops working and
-- stays missing after it starts, which is exactly the disagreement the reveal-time question was
-- introduced to prevent. It was reported for the way out of a hosted list, listed only if the list
-- was entered BEFORE the panel appeared and still listed after stepping back out of it, and the
-- same staleness was already true of every other gated key including the preview one.
--
-- A poll rather than a set of notifications, deliberately. The alternative is every consumer
-- telling the panel after every event that might matter, which is a list nobody can keep complete,
-- and the one already missing from it is the reason this exists. Polling covers every gate there is
-- and every gate added later, with no consumer knowing a panel is watching.
--
-- Only for content that offers `state`, so a panel showing something fixed runs no timer at all,
-- and only while visible, which is while the user has paused. A redraw happens only when the
-- reported state changes, so a steady panel is a string comparison four times a second and nothing
-- else, never a flicker.
function Panel:_startWatch()
  local state = self.config.content.state
  if type(state) ~= "function" then return end
  if self.watchTimer then self.watchTimer:stop() end
  self.lastState = state()
  -- Guarded on the canvas rather than on `shown`, which only tracks the DELAYED reveal and stays
  -- false for a panel configured with no delay, where the canvas is up all the same. Reading the
  -- canvas is true on both paths, and it leaves a centered panel's nil anchor alone, since show
  -- already accepts that.
  self.watchTimer = hs.timer.doEvery(WATCH_INTERVAL, function()
    if not self:isShowing() then return end
    local now = state()
    if now ~= self.lastState then
      self.lastState = now
      self:show(self.anchor)
    end
  end)
end

function Panel:_stopWatch()
  if self.watchTimer then
    self.watchTimer:stop()
    self.watchTimer = nil
  end
  self.lastState = nil
end

--- CanvasPanel:arm(anchorFrame) - the reveal-timing entry point. With no delay it draws
--- at once, the same as show. With a delay it stores the anchor and starts the idle
--- countdown instead of drawing, unless the panel has already revealed, in which case it
--- redraws at the corrected anchor (a chooser reports its frame twice as it settles).
function Panel:arm(anchor)
  if not anchor and self.config.placement ~= "center" then return end
  self.anchor = anchor
  local delay = self.config.delay
  if not delay or delay <= 0 then
    self:show(anchor)
    self:_startWatch()
    return
  end
  if self.shown then
    self:show(anchor)
    return
  end
  if not self.timer then self:_startTimer() end
end

--- CanvasPanel:poke() - signal activity, restarting the idle countdown so the reveal is
--- pushed back. A no-op with no delay, and a no-op once the panel has revealed, since it
--- latches visible from then on.
function Panel:poke()
  local delay = self.config.delay
  if not delay or delay <= 0 or self.shown then return end
  if self.timer then
    self.timer:stop()
    self:_startTimer()
  end
end

--- CanvasPanel:hide() - hide the panel and clear the reveal state, so the next arm starts
--- a fresh countdown (the canvas is kept alive for the next show).
function Panel:hide()
  if self.timer then
    self.timer:stop()
    self.timer = nil
  end
  self:_stopWatch()
  self.shown = false
  self.anchor = nil
  if self.canvas then self.canvas:hide() end
end

--- CanvasPanel:isShowing() - whether the panel is currently visible.
function Panel:isShowing()
  return self.canvas ~= nil and self.canvas:isShowing()
end

--- CanvasPanel.new(config) -> instance.
function obj.new(config)
  assert(config and config.content, "CanvasPanel.new: config.content is required")
  return setmetatable({ config = config, canvas = nil, timer = nil, shown = false, anchor = nil,
                        watchTimer = nil, lastState = nil }, Panel)
end

return obj
