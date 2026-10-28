--- === DockedPane canvas backend ===
---
--- The drawing backend a docked pane uses whenever the native one is not handed in, which is
--- every chooser but the swift one. It is the canvas half lib/dockedpane.lua used to hold itself,
--- moved here unchanged, so a pane under the default chooser draws exactly what it drew before.
--- lib/dockedpane.lua's header states the contract every backend keeps, and this file is one
--- concrete strategy behind it. The composition root picks it and hands it in, and neither the
--- pane nor a plugin names it.
---
--- One hs.canvas per pane, made by the factory at the first paint, at the companion rect. It
--- floats, and a click on it activates nothing, so a click on the pane never pulls focus off the
--- search field. The chooser's click watcher already treats a point inside the companion rect as
--- part of the picker and passes it through, so between the two a click here changes nothing.
---
--- Plain Lua. The canvas library comes from deps when given and from hs otherwise, read when a
--- backend is made, so a unit case drives this file over a stub with no Hammerspoon running.
---
--- M.new(deps) -> factory, deps.canvas optional, hs.canvas or a stub with new and windowLevels.
--- factory(frame) -> a backend for one pane, its canvas made at frame.

local M = {}

function M.new(deps)
  deps = deps or {}
  return function(frame)
    local lib = deps.canvas or hs.canvas
    local canvas = lib.new(frame)
    canvas:level(lib.windowLevels.floating)
    canvas:clickActivating(false)

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
    function backend.destroy() canvas:delete() end

    return backend
  end
end

return M
