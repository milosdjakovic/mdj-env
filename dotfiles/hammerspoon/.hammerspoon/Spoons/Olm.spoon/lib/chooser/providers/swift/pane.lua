--- === Swift pane backend ===
---
--- The docked pane's native drawing backend, the Lua half of native/Pane.swift. It keeps the
--- backend contract lib/dockedpane.lua's header states, place, render, show, hide and destroy,
--- and it is a Humble Object over the same Swift library the chooser panel lives in, so the pane
--- and the panel are torn down together by that library's reload sentinel. It keeps no pane rule.
--- The pane hands it the surface and the content as hs.canvas element lists, exactly what the
--- canvas backend is handed, and it passes the content to Swift unchanged.
---
--- THE SURFACE BECOMES GLASS. The surface elements are a filled rounded rectangle and its
--- stroked border, and the fill drawn over glass would cover the glass, so the pane would read as
--- a painted card beside a glass panel rather than as one surface with it. So the surface is not
--- drawn, its corner radius is read off it and the Swift window stands on the chooser panel's
--- own glass at that radius. The radius is the surface's own, so a theme that squares the
--- surface squares the glass with it.
---
--- Whatever Swift could not draw comes back named, an element type, an action or a scaling it
--- does not know, or an attribute it does not draw, and is said once per name for the session,
--- since the same pane repaints on every scroll.
---
--- M.factory(native, log) -> function(frame) -> backend, native the loaded library, log a
--- logger with e, or nil for print.

local M = {}

-- Every name already reported, so a repaint never says one twice.
local reported = {}

-- The corner of the surface's fill, or of its stroke widened by half the stroke, which is how
-- lib/panel.lua nests the one inside the other. Zero for a surface with neither.
local function radiusOf(surface)
  for _, el in ipairs(surface or {}) do
    local radii = el.type == "rectangle" and el.roundedRectRadii
    if radii and el.action == "fill" then return radii.xRadius or 0 end
  end
  for _, el in ipairs(surface or {}) do
    local radii = el.type == "rectangle" and el.roundedRectRadii
    if radii and el.action == "stroke" then return (radii.xRadius or 0) + (el.strokeWidth or 1) / 2 end
  end
  return 0
end
M.radiusOf = radiusOf

local function report(log, names)
  for _, name in ipairs(names or {}) do
    if not reported[name] then
      reported[name] = true
      local line = "Olm swift pane, an element it cannot draw was left out, " .. tostring(name)
      if log then log.e(line) else print(line) end
    end
  end
end

function M.factory(native, log)
  -- The frame is not needed here, since the pane places its backend before every render, and
  -- the window stays hidden until then.
  return function()
    local id = native.paneNew()
    local backend = {}

    function backend.place(rect)
      native.panePlace(id, rect)
    end

    function backend.render(surface, content)
      report(log, native.paneDraw(id, radiusOf(surface), content))
    end

    function backend.show() native.paneShow(id) end
    function backend.hide() native.paneHide(id) end
    function backend.destroy() native.paneDelete(id) end

    return backend
  end
end

return M
