--- === DockedPane canvas backend ===
---
--- The drawing backend a docked pane and a CanvasPanel use whenever the native one is not handed
--- in, which is under every chooser but the swift one. It is the canvas half lib/dockedpane.lua
--- used to hold itself, moved here unchanged, and since 2026-10-28 also the canvas half
--- lib/panel.lua used to hold, moved the same way, so a pane or a panel under the default chooser
--- draws exactly what it drew before. lib/dockedpane.lua's header states the contract every
--- backend keeps, and this file is one concrete strategy behind it. The composition root picks it
--- and hands it in, and neither the pane, the panel nor a plugin names it.
---
--- One hs.canvas per pane or panel, made by the factory at the first paint. A pane's floats, and
--- a click on it activates nothing, so a click on the pane never pulls focus off the search field.
--- The chooser's click watcher already treats a point inside the companion rect as part of the
--- picker and passes it through, so between the two a click here changes nothing.
---
--- A panel hands the factory its window as a second argument, its level, its click handler and
--- whether a click may activate Hammerspoon, and the canvas is made the way lib/panel.lua made
--- its own. Only content that answers a click turns the canvas's mouse events on, so a panel with
--- plain content stays click through to whatever is under it. A click activates Hammerspoon
--- there, hs.canvas's own default, which the panel kept by never changing it, and it asks for it
--- through activates so that stays exactly as it was.
---
--- Plain Lua. The canvas library comes from deps when given and from hs otherwise, read when a
--- backend is made, so a unit case drives this file over a stub with no Hammerspoon running.
---
--- M.new(deps) -> factory, deps.canvas optional, hs.canvas or a stub with new and windowLevels.
--- factory(frame, window) -> a backend for one pane or panel, its canvas made at frame. window is
--- absent for a pane and { level, onClick, activates } for a panel, see lib/dockedpane.lua.

local M = {}

function M.new(deps)
  deps = deps or {}
  return function(frame, window)
    local lib = deps.canvas or hs.canvas
    local canvas = lib.new(frame)
    canvas:level((window and window.level) or lib.windowLevels.floating)
    if not (window and window.activates) then canvas:clickActivating(false) end
    -- A click is reported as the id of an element the content built with id and trackMouseUp.
    local onClick = window and window.onClick
    if type(onClick) == "function" then
      canvas:canvasMouseEvents(false, true)
      canvas:mouseCallback(function(_, event, id)
        if event == "mouseUp" and id then onClick(id) end
      end)
    end

    local backend = {}

    function backend.place(rect)
      canvas:frame(rect)
    end

    -- The surface first and the content over it, in one list, the order a canvas paints in.
    function backend.render(surface, content)
      local els = {}
      for _, el in ipairs(surface) do els[#els + 1] = el end
      for _, el in ipairs(content) do els[#els + 1] = el end
      canvas:replaceElements(els)
    end

    function backend.show() canvas:show() end
    function backend.hide() canvas:hide() end
    function backend.isShowing() return canvas:isShowing() end
    function backend.destroy() canvas:delete() end

    return backend
  end
end

return M
