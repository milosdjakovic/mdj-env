-- The preview pane of a list Olm.app hosts, step 3.3d of docs/PLAN-STANDALONE.md,
-- docs/DESIGN-APP-HOSTED.md and docs/PROTOCOL-BRIDGE.md The preview pane.
--
-- A plugin draws its pane through lib/previewpane.lua as it always has, and that file hands what
-- it drew to a drawing backend, a strategy. This file is two more of them. The bridge backend sends
-- the content elements to the app as paneDrawn, and the router picks, per plugin, between it and
-- the backend the root chose before, the bridge while the app shows that plugin's list and the
-- old one otherwise, so the plugin never learns which draws.
--
-- Pure. What only Hammerspoon can do, a picture written to a file, a styled text read and a colour
-- converted, is handed in, so test/bridgeserve.lua drives every part of it over fakes.

local M = {}

-- The element attributes that cross, PaneReader's in lib/chooser/providers/swift/native/Lua.swift,
-- each of which the app's reader reads. Anything else is left out, the mouse tracking ones among
-- them, since a press on the pane is not served yet.
local KEEP = {
  type = true, action = true, frame = true, strokeWidth = true, strokeCapStyle = true,
  strokeJoinStyle = true, roundedRectRadii = true, coordinates = true, closed = true,
  imageAlpha = true, imageAlignment = true, imageScaling = true, textFont = true, textSize = true,
  textAlignment = true, textLineBreak = true,
}
local COLORS = { fillColor = true, strokeColor = true, textColor = true }

-- A plain copy of a frame, a point list or a radii table, numbers and percent strings alike.
local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

--- M.encode(elements, deps) -> the elements as the protocol carries them, a list of plain tables.
--- deps.color(c) -> { red, green, blue, alpha } or nil, a colour of hs.canvas's.
--- deps.text(styled) -> a Text, { string, font, size, color, alignment, lineBreak, lineHeight,
---                      tight }, or nil, for an hs.styledtext.
--- deps.picture(image) -> a Picture, { path }, or nil, for an hs.image.
--- An element whose text or picture cannot cross is left out, and named in the second answer.
function M.encode(elements, deps)
  local out, dropped = {}, {}
  for _, el in ipairs(elements or {}) do
    if type(el) == "table" then
      local e, ok = {}, true
      for k, v in pairs(el) do
        if KEEP[k] then
          e[k] = copy(v)
        elseif COLORS[k] then
          e[k] = deps.color(v)
        elseif k == "text" then
          if type(v) == "string" then e.text = v else e.text = deps.text(v); ok = e.text ~= nil end
        elseif k == "image" then
          e.image = deps.picture(v)
          ok = e.image ~= nil
        end
      end
      if ok then out[#out + 1] = e else dropped[#dropped + 1] = tostring(el.type) end
    end
  end
  return out, dropped
end

--- M.radiusOf(surface) -> the corner of a panel's surface, its fill's or its stroke's widened by
--- half the stroke, lib/chooser/providers/swift/pane.lua's rule, since the app draws its own glass.
function M.radiusOf(surface)
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

--- M.sheetBackend(show, hide) -> a panel backend factory, step 5.2, whose show hands show(frame,
--- surface, content) what the panel last placed and rendered, answering whether the app took it,
--- and whose hide calls hide() when a show was taken. isShowing is whether the app holds one.
function M.sheetBackend(show, hide)
  return function(frame)
    local b, placed, drawn, up = {}, frame, nil, false
    function b.place(f) placed = f end
    function b.render(surface, content) drawn = { surface = surface, content = content } end
    function b.show() up = drawn ~= nil and show(placed, drawn.surface, drawn.content) == true end
    function b.hide()
      if up then hide() end
      up = false
    end
    function b.isShowing() return up end
    function b.destroy() b.hide() end
    return b
  end
end

--- M.backend(send) -> a backend factory whose render hands send(content, scroll) the content of a
--- paint, scroll being lib/previewpane.lua's { height, visible, reset } for a native scroll. The
--- surface is left out, since the app draws its own glass, as the swift chooser's backend does.
--- It scrolls natively, the app's own view, so a scroll key never reaches it.
function M.backend(send)
  return function()
    local b = {}
    function b.place() end
    function b.scrollsNatively() return true end
    function b.render(_, content, scroll) send(content, scroll) end
    function b.scrollBy() return false end
    function b.show() end
    function b.hide() end
    function b.isShowing() return true end
    function b.destroy() end
    return b
  end
end

--- M.router(localFactory, remoteFactory, hosted) -> a backend factory over two, the remote while
--- hosted() answers true and the local otherwise, each built the first time it draws. The one it
--- leaves is hidden. Whether it scrolls natively is the local's answer, read once as
--- lib/previewpane.lua reads it, so a canvas chooser keeps its own scroll. The remote is then
--- handed an unscrolled paint with no scroll table, which the bridge sends at the pane's height.
function M.router(localFactory, remoteFactory, hosted)
  return function(frame, window)
    local made, current = {}, nil
    local placed = frame
    local function get(which)
      if not made[which] then
        made[which] = which == "remote" and remoteFactory(placed) or localFactory(placed, window)
      end
      return made[which]
    end
    local function active()
      local which = hosted() and "remote" or "local"
      if current and current ~= which and made[current] then made[current].hide() end
      current = which
      return get(which)
    end
    local r = {}
    function r.place(f) placed = f; active().place(f) end
    function r.scrollsNatively()
      local l = get("local")
      return type(l.scrollsNatively) == "function" and l.scrollsNatively() == true
    end
    function r.render(surface, content, scroll) active().render(surface, content, scroll) end
    function r.scrollBy(points)
      local b = active()
      return type(b.scrollBy) == "function" and b.scrollBy(points) or false
    end
    function r.show() active().show() end
    function r.hide() if current and made[current] then made[current].hide() end end
    function r.isShowing()
      local b = current and made[current]
      return b ~= nil and type(b.isShowing) == "function" and b.isShowing() == true
    end
    function r.destroy()
      for _, b in pairs(made) do b.destroy() end
      made, current = {}, nil
    end
    return r
  end
end

return M
