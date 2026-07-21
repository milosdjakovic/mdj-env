--- === HelperPanel ===
---
--- A generic canvas panel that docks around an anchor frame, typically a chooser.
--- It is the mechanism only: placement (below / above / left / right), sizing, and
--- drawing its own matched fill and border. WHAT it shows is a pluggable content
--- renderer injected by the caller, so a purpose like a shortcut-hint bar is one
--- content object and the panel stays ignorant of it. The composition root creates
--- an instance per purpose and wires show/hide to a chooser's onPositioned/onClose.
---
--- This is the Strategy pattern: the panel is the context that owns placement and
--- styling, the content is the strategy that owns what is drawn. Add a new purpose
--- by writing a new content object, never by editing the panel.
---
--- FACTORY: spoon.HelperPanel.new(config) -> instance (dot-called).
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
---   fill       panel fill: a canvas color table, or a function returning one
---              (evaluated per show, so a caller can track light/dark).
---   border     { color = <color|fn>, width = <n, default 1> }, or nil for none.
---   level      canvas window level (default hs.canvas.windowLevels.popUpMenu).
---   content    REQUIRED renderer:
---                preferredSize(availW, availH) -> { w = , h = }
---                  availW/availH is the content box the panel offers (either may
---                  be nil when that axis is auto); return the natural content size.
---                draw(w, h) -> { <canvas element>, ... }
---                  draw into a w x h box with its origin at (0, 0); the panel
---                  offsets the elements by its padding and draws the fill/border
---                  behind them.

local obj = {}
obj.__index = obj
obj.name = "HelperPanel"
obj.version = "1.0"
obj.author = "mdj-env"

function obj:init()
  return self
end

local Panel = {}
Panel.__index = Panel

local function resolve(v)
  if type(v) == "function" then return v() end
  return v
end

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
    local sf = (hs.screen.mainScreen() or hs.screen.primaryScreen()):frame()
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

--- HelperPanel:show(anchorFrame) - place and draw the panel relative to anchorFrame
--- ({ x, y, w, h }). Safe to call repeatedly; the canvas is built once and reused.
function Panel:show(anchor)
  if not anchor and self.config.placement ~= "center" then return end
  local frame, contentW, contentH, padX, padY = self:_layout(anchor)

  local els = {}
  local fill = resolve(self.config.fill)
  if fill then
    els[#els + 1] = { type = "rectangle", action = "fill", fillColor = fill,
      frame = { x = 0, y = 0, w = frame.w, h = frame.h } }
  end
  local border = self.config.border
  if border then
    local bw = border.width or 1
    -- Inset by half the stroke so the full border stays inside the canvas bounds.
    els[#els + 1] = { type = "rectangle", action = "stroke",
      strokeColor = resolve(border.color), strokeWidth = bw,
      frame = { x = bw / 2, y = bw / 2, w = frame.w - bw, h = frame.h - bw } }
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
  end)
end

--- HelperPanel:arm(anchorFrame) - the reveal-timing entry point. With no delay it draws
--- at once, the same as show. With a delay it stores the anchor and starts the idle
--- countdown instead of drawing, unless the panel has already revealed, in which case it
--- redraws at the corrected anchor (a chooser reports its frame twice as it settles).
function Panel:arm(anchor)
  if not anchor and self.config.placement ~= "center" then return end
  self.anchor = anchor
  local delay = self.config.delay
  if not delay or delay <= 0 then
    self:show(anchor)
    return
  end
  if self.shown then
    self:show(anchor)
    return
  end
  if not self.timer then self:_startTimer() end
end

--- HelperPanel:poke() - signal activity, restarting the idle countdown so the reveal is
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

--- HelperPanel:hide() - hide the panel and clear the reveal state, so the next arm starts
--- a fresh countdown (the canvas is kept alive for the next show).
function Panel:hide()
  if self.timer then
    self.timer:stop()
    self.timer = nil
  end
  self.shown = false
  self.anchor = nil
  if self.canvas then self.canvas:hide() end
end

--- HelperPanel:isShowing() - whether the panel is currently visible.
function Panel:isShowing()
  return self.canvas ~= nil and self.canvas:isShowing()
end

--- HelperPanel.new(config) -> instance.
function obj.new(config)
  assert(config and config.content, "HelperPanel.new: config.content is required")
  return setmetatable({ config = config, canvas = nil, timer = nil, shown = false, anchor = nil }, Panel)
end

return obj
