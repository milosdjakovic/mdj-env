--- === DockedPane ===
---
--- The docked companion pane, the surface beside a list that describes the highlighted row. Every
--- plugin with a pane used to carry its own copy of this lifecycle, the lazy window, the inner
--- rect, the dock, show, hide and destroy, the shared surface underneath and the shared empty
--- state, five copies of the same sixty lines that differed only in what they drew. This file
--- owns all of it once, and a plugin keeps only what it draws.
---
--- WHY A WINDOW OF ITS OWN AND NOT A CANVASPANEL INSTANCE. A CanvasPanel computes its own
--- placement from an anchor and sizes itself from its content, while a docked pane has to land
--- exactly on the companion rect the chooser reserved and reported. Drawing anywhere else would
--- put it outside the rect the chooser's click watcher treats as part of the picker, so a click
--- on the pane would dismiss the list instead of passing through. What it does share with
--- CanvasPanel is the surface and the empty state, both injected, so a pane, the toasts and the
--- cheat sheets are one component drawn in several places.
---
--- THE PATTERN IS TEMPLATE METHOD, adapted to closures. This file is the fixed skeleton of a
--- paint, the guards, the backend, the surface first, the scroll clamp, the optional thumb, the
--- frame and the show. The one step that varies, what is drawn, is a function the plugin hands
--- in. A plain pane hands a describer, a function of the kit answering one node, and the pane
--- lays it out in the inner rect. A pane made of several regions, a fixed header over a
--- scrolled body, or a cached block under a live one, hands a painter instead, a function of the
--- view answering canvas elements and how far the content overflows, and the pane still does
--- everything around it. Both are called again on every paint, so a redock or a change of
--- appearance repaints from the same description without anyone being told again.
---
--- THE DRAWING BACKEND IS A STRATEGY. Whatever a pane describes or paints is reduced here to two
--- lists of hs.canvas element tables, the surface and the content, in the pane's own coordinates
--- with the origin at its top left, and those two lists are the whole contract with whatever
--- puts them on screen. deps.backend is a factory, called once at the first paint with the
--- companion rect, answering a backend that keeps four promises and holds no rule.
---   backend.place(frame)             move to the companion rect, in screen coordinates.
---   backend.render(surface, content) draw both lists, replacing whatever was drawn before, with
---                                 a third argument for a backend that scrolls natively, below.
---   backend.show(), backend.hide()   bring it up and take it down without forgetting it.
---   backend.destroy()                tear it down for good, on close.
---   backend.isShowing()           whether it is on screen, which this file never asks and
---                                 lib/panel.lua does.
---   backend.scrollsNatively()     optional, true for a backend that scrolls its own view.
---   backend.scrollBy(points)      only on such a backend, scroll its view, answering whether it
---                                 moved.
--- The contract has a second consumer, lib/panel.lua, whose overlays, the leader sheets and the
--- toasts, are reduced to the same two lists and drawn by the same backends. A panel calls the
--- factory with a second argument, its window, which a pane never passes.
---   window.level      an hs.canvas.windowLevels value, the pane's being floating.
---   window.onClick    function(id), told the id of an element built with id and trackMouseUp when
---                     it is clicked, the id _canvas_ when no such element is under the click.
---                     Absent means the window is click through, as a pane's canvas has always been
---                     for a canvas with no mouse callback.
---   window.activates  true where a click may activate Hammerspoon, hs.canvas's own default,
---                     which a panel kept and a pane turns off. The native backend never
---                     activates.
--- A window also tells the native backend this is no pane, so it is never drawn into a chooser
--- panel's window and is ordered front on every show, as hs.canvas does, where a pane is ordered
--- front only when it comes up. That is the whole extension, one optional argument.
--- lib/dockedpane/canvas.lua is one, an hs.canvas that paints the surface and the content in
--- order, which is how every pane drew before the backend existed. The swift chooser's
--- lib/chooser/providers/swift/pane.lua is the other, drawn on the swift chooser panel's own
--- glass by the same Swift library, which puts glass where the surface elements would be and
--- draws the content over it. The composition root chooses, the native one only while the swift
--- provider serves, and no code in this file or in a plugin ever picks one.
---
--- A BACKEND THAT SCROLLS NATIVELY. A canvas scrolls by being painted again at a new offset, so
--- this file holds the offset, clamps it, draws the thumb and coalesces scroll events into one
--- paint a frame. A backend whose view scrolls on its own, with momentum and at display rate,
--- answers scrollsNatively, and for it a scrolling pane's content is laid out once at its full
--- height, unshifted by any offset and cut only at the bottom of all of it, and handed over as
--- render(surface, content, scroll) with scroll = { height, visible, reset, thumb }. height is the
--- whole content's height in the pane's coordinates, the pane's own height plus the overflow,
--- visible the pane's height, reset whether the content changed since the last render so the view
--- goes back to the top, and thumb whether the pane asked for a thumb, which the backend shows as
--- its own overlay scroller. Here scrollY stays zero, nothing is clamped, no thumb is drawn and no
--- scroll timer runs, and pane.scrollBy becomes backend.scrollBy, so a key that pages the pane
--- still pages it. A painter is called once as usual to learn its overflow, and again with the
--- view's viewport grown by that overflow, which is how a painter that cuts at the viewport and
--- lays out only what is inside it hands over everything. A painter's fixed header therefore
--- scrolls with the rest under such a backend. The canvas backend answers nothing and keeps the
--- path above exactly as it was.
---
--- Granted rather than loaded. A plugin whose surface declares `pane = true` receives
--- `opts.dockedPane`, a function answering a new pane, built by the composition root with the
--- kit, the surface, the empty state and the backend already in it. The declaration stays the
--- one gate, so a plugin that never asked for a pane cannot make one, and nothing here names a
--- plugin.
---
--- Plain Lua. The timer comes from deps when given, and from hs otherwise, read at the moment it
--- is needed, so a unit case drives this file over a stub with no Hammerspoon running. That
--- fallback is the one place this file reaches for hs, kept here as the seam rather than behind
--- another layer.
---
--- PANE API, dot called, every member a closure, so pane.show(x) needs no self.
---   pane.isEnabled()            whether anything can be drawn, a surface, a kit and a backend
---                               all present.
---   pane.dock(companionFrame)   take the rect the chooser reported and repaint what is current.
---                               Fired with a seed rect at show and again once the window
---                               settles, so a redock is expected.
---   pane.inner()                the padded box content is laid out in, in the pane's own
---                               coordinates, nil before the first dock.
---   pane.show(describe, opts)   describe(ui, view) answers one kit node.
---   pane.draw(painter, opts)    painter(view) answers elements and the overflow in points.
---                               Both reset the scroll unless opts.keepScroll is true.
---   pane.repaint()              paint what is current again at the current scroll.
---   pane.clear()                the shared empty state, for a highlight with nothing to say.
---   pane.scrollBy(points)       move further down by points, answering whether anything moved,
---                               the backend's own view when it scrolls natively.
---   pane.hide()                 hide without destroying, for the stage's swap away signal.
---   pane.destroy()              destroy the backend and forget everything, on close.
---
--- view, what a describer and a painter are handed.
---   frame     the companion rect, in screen coordinates.
---   inner     the frame less the kit's pad on all four sides, in the pane's own coordinates.
---   viewport  the box inside the surface's border, which scrolled content is cut at.
---   scrollY   how far the content is scrolled, in points, always zero under a backend that
---             scrolls natively.

local M = {}

-- One display frame, the longest a scroll event waits for its paint.
local SCROLL_FRAME = 1 / 60

-- The scroll thumb, geometry rather than type. It sits THUMB_EDGE in from the right edge of the
-- pane, THUMB_W wide, and is never shorter than THUMB_MIN.
local THUMB_EDGE, THUMB_W, THUMB_MIN = 7, 3, 18

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

--- DockedPane.new(deps, spec) -> pane
--- deps, from the composition root.
---   ui          the UI kit, every piece of text and colour comes through it. Absent means a
---               pane that never draws, see isEnabled.
---   surface     function(w, h) -> elements, CanvasPanel.surfaceElements.
---   emptyState  function(w, h, opts) -> elements, CanvasPanel.emptyStateElements. Absent leaves
---               the bare surface up, since a docked pane is never hidden while it is current.
---   backend     function(frame) -> backend, the drawing strategy, see above. Absent means a
---               pane that never draws, see isEnabled.
---   timer       optional, hs.timer or a stub with doAfter.
--- spec, from the plugin, all optional.
---   scroll      true when content taller than the pane scrolls. Without it content is laid
---               out unscrolled and cut at the border.
---   thumb       true to draw a scroll thumb while there is more than fits, a describer only.
---   emptyText   this pane's own line for the empty state, in place of the shared default.
function M.new(deps, spec)
  deps = deps or {}
  spec = spec or {}
  local pane = {}

  local backend = nil  -- built lazily on the first paint and destroyed on destroy
  local frame = nil    -- the companion rect, nil until the first dock and after destroy
  local current = nil  -- what is on screen, { describe = fn }, { painter = fn } or { empty = true }
  local hidden = false -- set by hide, cleared by dock, the guard every late paint reads
  local scrollY = 0    -- how far the content is scrolled, clamped on every paint
  local overflow = 0   -- how far it can go, measured by the last paint
  local timer = nil    -- the one pending scroll paint
  local native = false -- whether the backend scrolls its own view, read once when it is built
  local reset = true   -- whether the next native render goes back to the top

  local function timerLib() return deps.timer or hs.timer end

  local function stopTimer()
    if timer then
      timer:stop()
      timer = nil
    end
  end

  local function ensureBackend()
    if backend then return end
    backend = deps.backend(frame)
    native = type(backend.scrollsNatively) == "function" and backend.scrollsNatively() == true
  end

  -- The viewport grown downward by the overflow, the box full height content is cut at.
  local function grown(viewport, by)
    local out = {}
    for k, v in pairs(viewport) do out[k] = v end
    out.h = viewport.h + by
    return out
  end

  function pane.isEnabled()
    return deps.surface ~= nil and deps.ui ~= nil and deps.backend ~= nil
  end

  function pane.inner()
    if not (frame and deps.ui) then return nil end
    -- under is how much of the companion's bottom the chooser's bar floats over, so content is
    -- laid out above the bar while the pane's clip still reaches the bottom edge behind it.
    local pad = deps.ui.tokens().pad
    return { x = pad, y = pad, w = frame.w - 2 * pad, h = frame.h - 2 * pad - (frame.under or 0) }
  end

  local function viewOf(inner)
    return { frame = frame, inner = inner, viewport = deps.ui.interior(frame.w, frame.h),
             scrollY = scrollY }
  end

  -- The empty state laid into the inner box. The emptyText goes over only when this pane set
  -- one, so a pane without it calls the shared routine exactly as it always did.
  local function emptyElements(inner)
    if not deps.emptyState then return {} end
    local els = spec.emptyText and deps.emptyState(inner.w, inner.h, { text = spec.emptyText })
      or deps.emptyState(inner.w, inner.h)
    local out = {}
    for _, el in ipairs(els or {}) do out[#out + 1] = shifted(el, inner.x, inner.y) end
    return out
  end

  -- A describer's node, laid out in the inner box and cut at the inside of the border, so a line
  -- scrolled past the padding is cut by the edge of the pane rather than by the padding. The
  -- offset is clamped against the height the layout answers, so a scroll, a rebuild at a new
  -- height and content that grows underneath it all land somewhere real.
  local function describedElements(inner)
    local ui = deps.ui
    local tokens = ui.tokens()
    local view = viewOf(inner)
    local node = current.describe(ui, view)
    if not node then return {} end
    if not spec.scroll then
      return ui.layout(node, inner, { tokens = tokens, viewport = view.viewport })
    end
    local content, contentH = ui.layout(node, inner,
      { scrollY = scrollY, tokens = tokens, viewport = view.viewport })
    overflow = math.max(0, (contentH or 0) - inner.h)
    -- A native backend scrolls the whole of it, so it is laid out again down to its end, with
    -- no clamp and no thumb, both being the backend's.
    if native then
      if overflow > 0 then
        content = ui.layout(node, inner,
          { scrollY = 0, tokens = tokens, viewport = grown(view.viewport, overflow) })
      end
      return content
    end
    if scrollY > overflow or scrollY < 0 then
      scrollY = math.max(0, math.min(scrollY, overflow))
      content = ui.layout(node, inner, { scrollY = scrollY, tokens = tokens, viewport = view.viewport })
    end
    -- A thumb rather than a hint in words, drawn only while there is genuinely more than fits,
    -- so a pane that holds all of its content carries no chrome at all.
    if spec.thumb and overflow > 0 then
      local thumbH = math.max(THUMB_MIN, inner.h * (inner.h / contentH))
      local travel = inner.h - thumbH
      -- A pill while the surface is rounded, never rounder than the kit's nested corner, so a
      -- square surface draws a square thumb.
      local radius = math.min(THUMB_W / 2, tokens.radius.nested)
      content[#content + 1] = { type = "rectangle", action = "fill",
        roundedRectRadii = { xRadius = radius, yRadius = radius }, fillColor = thumbColor(tokens),
        frame = { x = frame.w - THUMB_EDGE, y = inner.y + (scrollY / overflow) * travel,
                  w = THUMB_W, h = thumbH } }
    end
    return content
  end

  -- A painter's elements, clamped the same way against the overflow it reports.
  local function paintedElements(inner)
    local els, over = current.painter(viewOf(inner))
    if not spec.scroll then return els or {} end
    overflow = math.max(0, over or 0)
    if native then
      if overflow > 0 then
        local tall = viewOf(inner)
        tall.viewport = grown(tall.viewport, overflow)
        els = current.painter(tall)
      end
      return els or {}
    end
    if scrollY > overflow or scrollY < 0 then
      scrollY = math.max(0, math.min(scrollY, overflow))
      els = current.painter(viewOf(inner))
    end
    return els or {}
  end

  local function paint()
    -- A late tick, a settled read or a thumbnail can all reach here after hide took the pane
    -- down for a swap away. hidden is what stops any of them bringing it back up beside a tool
    -- that is no longer current.
    if hidden then return end
    if not (current and frame and pane.isEnabled()) then return end
    ensureBackend()
    local inner = pane.inner()
    local surface = deps.surface(frame.w, frame.h) or {}
    local content
    if current.empty then
      overflow = 0
      content = emptyElements(inner)
    elseif current.describe then
      content = describedElements(inner)
    else
      content = paintedElements(inner)
    end
    backend.place(frame)
    if native then
      local extra = spec.scroll and overflow or 0
      backend.render(surface, content, { height = frame.h + extra, visible = frame.h,
        reset = reset, thumb = spec.thumb == true })
      reset = false
    else
      backend.render(surface, content)
    end
    backend.show()
  end

  -- Every show resets the scroll unless asked not to, since the content underneath changed and a
  -- position measured against something else would land somewhere arbitrary. A native backend is
  -- told so with its next render, and a repaint or a redock keeps where its view is.
  local function present(next, opts)
    current = next
    if not (opts and opts.keepScroll) then
      scrollY = 0
      reset = true
      stopTimer()
    end
    paint()
  end

  function pane.dock(companionFrame)
    if not (pane.isEnabled() and companionFrame) then return end
    frame = companionFrame
    -- A redock is the swap back hide guards against, so the pane may paint again from here on.
    hidden = false
    paint()
  end

  function pane.show(describe, opts)
    present({ describe = describe }, opts)
  end

  function pane.draw(painter, opts)
    present({ painter = painter }, opts)
  end

  function pane.repaint()
    paint()
  end

  -- The pane stays up rather than vanishing, since a reserved rectangle with nothing in it reads
  -- as a broken layout. It genuinely disappears only on hide and on destroy.
  function pane.clear()
    present({ empty = true })
    overflow = 0
  end

  -- The chooser hands over a distance already normalised for a wheel against a trackpad. The
  -- offset moves at once, clamped against the overflow the last paint measured, and the paint
  -- waits for the next frame, so however many events land before it they cost one layout. A
  -- backend that scrolls natively is asked to move its own view instead, and nothing repaints.
  function pane.scrollBy(points)
    if not (spec.scroll and current and not current.empty and frame and overflow > 0) then
      return false
    end
    if native then return backend.scrollBy(tonumber(points) or 0) == true end
    local next = math.max(0, math.min(overflow, scrollY + (tonumber(points) or 0)))
    if next == scrollY then return false end
    scrollY = next
    if not timer then
      timer = timerLib().doAfter(SCROLL_FRAME, function()
        timer = nil
        paint()
      end)
    end
    return true
  end

  function pane.hide()
    hidden = true
    stopTimer()
    if backend then backend.hide() end
  end

  -- Destroyed rather than hidden, because nothing may survive a close and rebuilding one backend
  -- on the next open costs nothing.
  function pane.destroy()
    stopTimer()
    current = nil
    frame = nil
    hidden = false
    scrollY = 0
    overflow = 0
    native = false
    reset = true
    if backend then
      backend.destroy()
      backend = nil
    end
  end

  return pane
end

return M
