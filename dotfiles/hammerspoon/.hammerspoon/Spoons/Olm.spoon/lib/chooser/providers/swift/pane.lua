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
--- drawn, its corner radius is read off it and the pane's glass takes that radius. The radius is
--- the surface's own, so a theme that squares the surface squares the glass with it.
---
--- WHERE IT IS DRAWN is decided inside the library and never here, since a pane knows no chooser.
--- native/Pane.swift asks the seam in native/Entry.swift for the visible chooser panel whose
--- reported companion is the rect this pane is placed on, and draws into the pane's region of that
--- panel's own window, on the one shape of glass the list stands on, so the two are one surface
--- and come and go together. With no such panel it stands in a window of its own.
---
--- IT SCROLLS NATIVELY. It answers scrollsNatively, so the pane hands it a scrolling pane's
--- content at its full height with the height, the reset and the thumb, and native/Pane.swift
--- draws it in a scroll view that scrolls with the system's own momentum, Lua repainting only when
--- the content changes. scrollBy moves that view, for a key that pages the pane.
---
--- IT DRAWS A CANVASPANEL TOO. lib/panel.lua keeps the same contract and hands the factory its
--- window as a second argument, { level, onClick, activates }. The library then makes a window
--- that is never drawn into a chooser panel's, stands at that level, is ordered front on every
--- show as hs.canvas is, is click through unless onClick is given, and never activates
--- Hammerspoon whatever activates says. A click on it is hit tested in Swift against the elements
--- built with id and trackMouseUp, the topmost first as hs.canvas does, and onClick is told the
--- id, or _canvas_ when none is under the pointer, through a function the library holds for that
--- window alone and lets go of when it is deleted or its Lua state closes.
---
--- Whatever Swift could not draw comes back named, an element type, an action or a scaling it
--- does not know, or an attribute it does not draw, and is said once per name for the session,
--- since the same pane repaints whenever its content changes.
---
--- M.factory(native, log) -> function(frame, window) -> backend, native the loaded library, log
--- a logger with e, or nil for print. window is absent for a pane, see lib/dockedpane.lua.

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
  -- The frame is not needed here, since a pane and a panel both place their backend before every
  -- render, and nothing is shown until then.
  return function(_, window)
    local id
    if window then
      -- A panel's window. onClick goes over only when it is a function, so the library holds
      -- nothing for a window that takes no click.
      id = native.paneNew({ panel = true, level = window.level,
        onClick = type(window.onClick) == "function" and window.onClick or nil })
    else
      id = native.paneNew()
    end
    local backend = {}

    function backend.place(rect)
      native.panePlace(id, rect)
    end

    function backend.scrollsNatively() return true end

    -- scroll is { height, visible, reset, thumb }, see lib/dockedpane.lua's header.
    function backend.render(surface, content, scroll)
      report(log, native.paneDraw(id, radiusOf(surface), content, scroll))
    end

    function backend.scrollBy(points)
      return native.paneScrollBy(id, points) == true
    end

    function backend.show() native.paneShow(id) end
    function backend.hide() native.paneHide(id) end
    function backend.isShowing() return native.paneIsVisible(id) == true end
    function backend.destroy() native.paneDelete(id) end

    return backend
  end
end

return M
