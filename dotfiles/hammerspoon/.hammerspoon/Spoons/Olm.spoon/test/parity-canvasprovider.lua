-- Parity probe for the canvas picker provider, stage two of docs/DESIGN-UI-KIT.md. Run
-- through test/parity.sh, which exports the old tree and names it in PARITY_ARGS. Builds a
-- provider from the old tree and one from this checkout, drives each through the steps its
-- own show takes up to the draw, with a stand in surface that keeps what it is handed rather
-- than a window, and compares the field and list elements for an empty field with its
-- placeholder, a field holding a selection, and a list scrolled down to a disabled row. The
-- measured widths a supplier formats against are compared too.

local source = debug.getinfo(1, "S").source
local here = (source:match("^@(.*)$") or source):match("^(.*/)")
local lib = dofile(here .. "parity-lib.lua")

local ok, err = pcall(function()
  local policy = lib.policy()
  local ui = lib.newUI(policy)
  local SCREEN = { x = 0, y = 0, w = 1512, h = 945 }
  local icon = hs.image.imageFromName("NSCaution")

  local rows = {}
  for i = 1, 14 do
    rows[i] = { title = "Row number " .. i .. " with a title",
      subTitle = (i % 3 ~= 0) and ("~/Development/some/path/" .. i) or nil,
      image = (i % 2 == 0) and icon or nil, enabled = i ~= 11, item = i }
  end

  local function tree(dir)
    local panel = dofile(dir .. "lib/panel.lua")
    panel.configure({ surface = policy.surface })
    local canvasDir = dir .. "lib/chooser/providers/canvas/"
    return {
      provider = dofile(canvasDir .. "init.lua"),
      geometry = dofile(canvasDir .. "geometry.lua"),
      listModel = dofile(canvasDir .. "list/model.lua"),
      panel = panel,
    }
  end
  local oldTree, newTree = tree(lib.old), tree(lib.new)
  oldTree.provider.configure({ panel = oldTree.panel })
  newTree.panel.configure({ ui = ui })
  newTree.provider.configure({ panel = newTree.panel, ui = ui })

  local function draw(t, fieldState, steps)
    local p = t.provider.new({ theme = policy.chooserTheme, placeholder = "Search apps",
      rows = function() return rows end })
    p:_selectTheme()
    p:_deriveStyles()
    p._rects = t.geometry.resolve(SCREEN, p.layout, nil)
    p:_updateDrawLayout()
    p:_rebuildList("", true)
    for _ = 1, steps do p.listState = t.listModel.moveDown(p.listState) end
    p.field = { getState = function() return fieldState end }
    p._caretVisible = true
    local captured
    p.surface = { draw = function(_, els) captured = els end }
    p:_redraw()
    local widths = { p:textWidth("Hello Wörld, a title", "title"), p:textWidth("~/a/sub title", "sub") }
    return captured, widths, p._rects.canvas
  end

  local cases = {
    { name = "an empty field and the first row", field = { text = "", caret = 0 }, steps = 0 },
    { name = "a selection in the field", field = { text = "hello world", caret = 9, anchor = 3 }, steps = 2 },
    { name = "scrolled to a disabled row", field = { text = "row", caret = 3 }, steps = 10 },
  }
  for _, half in ipairs(lib.halves) do
    for _, c in ipairs(cases) do
      local old, ow, rect = lib.withHalf(half, function() return draw(oldTree, c.field, c.steps) end)
      local new, nw = lib.withHalf(half, function() return draw(newTree, c.field, c.steps) end)
      local extras = {}
      if ow[1] ~= nw[1] or ow[2] ~= nw[2] then
        extras[1] = "textWidth old " .. ow[1] .. " " .. ow[2] .. " new " .. nw[1] .. " " .. nw[2]
      end
      lib.check("canvas provider, " .. c.name .. ", " .. half, old, new, rect.w, rect.h, extras)
    end
  end
  lib.summary()
end)
if not ok then lib.out("ERROR " .. tostring(err)) end
lib.done()
