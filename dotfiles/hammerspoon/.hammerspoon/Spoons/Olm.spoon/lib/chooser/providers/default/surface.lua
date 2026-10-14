--- === Canvas surface ===
---
--- A window this configuration owns, drawn with hs.canvas, which never takes focus. This
--- is a shell around a resource, not a Strategy. It draws whatever it is handed and holds
--- no policy of its own, it does not know what a row is, what a query is, or that a
--- picker exists at all. That is the same division lib/chooser/providers/default/field
--- already takes, input.lua is the only file touching hs.eventtap and render.lua answers
--- elements without owning a surface, and it is what keeps this placeable inside the
--- three pane window later.
---
--- The focus guarantee, stated as a guarantee rather than a hope. A canvas surface never
--- becomes the key window, so the frontmost application keeps its focus and keeps
--- receiving keys, which is the whole reason this backend exists and is also the reason
--- the mouse and keyboard shells around it have to claim events explicitly rather than
--- relying on focus to route them. hs.canvas answers true to clickActivating by default,
--- which would let a click on this surface bring the owning application forward and pull
--- focus off whatever the picker is meant to sit over, so this file turns that off itself
--- rather than leaving it as a default nobody chose. Every other consumer in this tree
--- that owns a clickable canvas of its own already does the same thing and says the same
--- reason in its own comment, plugins/clipboard/manager/ui.lua among them, so this is the
--- established way rather than a new one.
---
--- The canvas setup mirrors lib/panel.lua, the shared surface atom, rather than inventing
--- a second way to make a canvas in this configuration. CanvasPanel.surfaceElements is
--- the one routine that paints the chrome, a filled rounded rectangle plus a rounded
--- border resolved for the live light or dark appearance, and this file prepends it on
--- every draw exactly the way lib/panel.lua's own show and the clipboard preview both
--- already do, so a surface drawn through this file looks identical to every other
--- surface in this configuration. The window level matches lib/panel.lua's own default,
--- popUpMenu, since this is the same atom's own chrome sitting under a picker rather than
--- under a docked hint panel.
---
--- Surface.new(opts) takes opts.panel, the CanvasPanel module, injected here rather than
--- required by path so this file names no concrete module of its own, and opts.style, the
--- surface style table or nil to take the panel's own configured default. It creates
--- nothing yet, the canvas itself comes into being on the first setFrame call, since there
--- is nothing to draw a window at before a caller has a rect to hand it.
---
--- setFrame(rect) places and sizes the window in absolute screen points, the same space
--- hs.window frames and hs.eventtap event locations already use. It is legal while the
--- surface is visible, hs.canvas itself allows a live frame change, and that is the whole
--- point of this backend, width, height and position become live and free here where they
--- cost a hide and a show on the native one.
---
--- draw(elements) replaces the canvas contents with the chrome for the current frame
--- followed by the elements it was handed, in that order, and appends nothing of its own
--- after them. The chrome is resolved fresh on every call rather than cached, so a light
--- and dark switch is picked up the moment the next draw happens, which is what
--- lib/panel.lua already does and for the same reason. Calling draw before any frame has
--- been set does nothing, since there is no window yet for elements to land on.

local Surface = {}
Surface.__index = Surface

--- Surface.new(opts) answers a new instance holding the injected panel module and the
--- optional style override, with no canvas built yet.
function Surface.new(opts)
  opts = opts or {}
  assert(opts.panel, "Surface.new needs opts.panel, the CanvasPanel module, injected rather than named by path here")
  return setmetatable({
    panel = opts.panel,
    style = opts.style,
    canvas = nil,
    frame = nil,
  }, Surface)
end

--- setFrame(rect) places and sizes the window at rect, x, y, w and h in absolute screen
--- points. The canvas is created on the first call, at the level lib/panel.lua itself
--- defaults to, and clickActivating is turned off the moment the canvas exists, so the
--- focus guarantee in the header above holds from the very first frame onward. A later
--- call simply moves and resizes the same window, which is legal whether the surface is
--- currently shown or hidden.
function Surface:setFrame(rect)
  self.frame = rect
  if self.canvas then
    self.canvas:frame(rect)
    return
  end
  self.canvas = hs.canvas.new(rect)
  self.canvas:level(hs.canvas.windowLevels.popUpMenu)
  self.canvas:clickActivating(false)
end

--- draw(elements) replaces the whole canvas content with the shared chrome for the
--- current frame size followed by elements, in that order, nothing appended after them.
--- A caller with nothing to add yet may pass nil or an empty table and still see the bare
--- chrome. Does nothing when no frame has been set, since there is no canvas to draw on.
function Surface:draw(elements)
  if not self.canvas then return end
  local w, h = self.frame.w, self.frame.h
  local els = {}
  for _, el in ipairs(self.panel.surfaceElements(w, h, self.style)) do
    els[#els + 1] = el
  end
  for _, el in ipairs(elements or {}) do
    els[#els + 1] = el
  end
  self.canvas:replaceElements(els)
end

--- show() reveals the window. Does nothing when no frame has been set.
function Surface:show()
  if self.canvas then self.canvas:show() end
end

--- hide() conceals the window without deleting it, so a later show reveals the same
--- content again with no redraw required.
function Surface:hide()
  if self.canvas then self.canvas:hide() end
end

--- isVisible() answers whether the window is genuinely on screen right now.
function Surface:isVisible()
  return self.canvas ~= nil and self.canvas:isShowing()
end

--- delete() tears the window down completely, the canvas object itself dropped rather
--- than merely hidden, so nothing is left behind for a later setFrame to find and reuse
--- by mistake. A fresh setFrame after this builds an entirely new window.
function Surface:delete()
  if self.canvas then
    self.canvas:delete()
    self.canvas = nil
  end
  self.frame = nil
end

return Surface
