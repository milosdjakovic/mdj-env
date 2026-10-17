-- Unit case for the empty state of the default chooser's row list, drawn by
-- Spoons/Olm.spoon/lib/chooser/providers/default/list/render.lua when a typed query leaves no
-- rows. The provider hands render the shared CanvasPanel.emptyStateElements as style.emptyState
-- and the query it ranked with, and render alone decides whether the band shows it, so this case
-- drives render with a stand in for that routine and reads what comes back. Loaded the way
-- cases/canvaslist.lua loads it, through debug.getinfo, with no absolute path written down.
--
-- render.lua asks hs.styledtext for font metrics. Run through the units runner that is the real
-- one, and run under plain lua a stand in answers it, so the case reads the same either way.
--
-- Each check prints one line, PASS or FAIL followed by a plain description, and the runner
-- counts from those lines alone.

if not hs then
  hs = { styledtext = { fontInfo = function(f) return { ascender = f.size, descender = 0, capHeight = f.size * 0.7 } end } }
end

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local listDir = caseDir .. "/../../Spoons/Olm.spoon/lib/chooser/providers/default/list/"

local modelChunk, modelErr = loadfile(listDir .. "model.lua")
if not modelChunk then
  print("FAIL load Olm.spoon canvas list model.lua, " .. tostring(modelErr))
  return
end
local model = modelChunk()

local renderChunk, renderErr = loadfile(listDir .. "render.lua")
if not renderChunk then
  print("FAIL load Olm.spoon canvas list render.lua, " .. tostring(renderErr))
  return
end
local render = renderChunk()

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local FONT = ".AppleSystemUIFont"
local ROW_H = 47
local LAYOUT = {
  font = FONT, textSize = 16, textLine = 22,
  subFont = FONT, subSize = 14, subLine = 19,
  numFont = FONT, numSize = 16,
  rowH = ROW_H, rowCount = 9, padBottom = 14,
}
local RECT = { x = 14, y = 57, w = 452, h = 9 * ROW_H + 14 }

-- The stand in for CanvasPanel.emptyStateElements, one text at the origin like the real one,
-- remembering the box it was asked to fill.
local asked
local style = {
  emptyState = function(w, h)
    asked = { w = w, h = h }
    return { { type = "text", text = "No results", frame = { x = 0, y = h / 2 - 19, w = w, h = 19 } } }
  end,
}

local function emptyText(els)
  for _, el in ipairs(els) do
    if el.type == "text" and el.text == "No results" then return el end
  end
end

local none = model.newState({}, LAYOUT, "")
local some = model.newState({ { title = "Safari" }, { title = "Mail" } }, LAYOUT, "")

-- The predicate, on its own.
check("a typed query with no rows shows the empty state", render.showsEmptyState(none, "zzz"))
check("an empty query with no rows does not", not render.showsEmptyState(none, ""))
check("no query at all does not", not render.showsEmptyState(none, nil))
check("a typed query with rows does not", not render.showsEmptyState(some, "sa"))

-- What is drawn.
do
  asked = nil
  local els = render.elements(none, RECT, LAYOUT, style, nil, "zzz")
  local el = emptyText(els)
  check("the empty state is drawn for a typed query with no rows", el ~= nil)
  check("it fills the band the rows would have filled", asked and asked.w == RECT.w
    and asked.h == render.bandHeight(LAYOUT),
    asked and (asked.w .. " x " .. asked.h) or "never asked")
  check("it is placed inside the band", el and el.frame.x == RECT.x
    and el.frame.y > RECT.y and el.frame.y < RECT.y + RECT.h)
  check("the band keeps room for at least one row", render.bandHeight(LAYOUT) >= ROW_H)
  check("no highlight is drawn under it", (function()
    for _, e in ipairs(els) do
      if e.type == "rectangle" and e.action == "fill" then return false end
    end
    return true
  end)())
  check("the clip is still closed after it", els[#els].type == "resetClip")
end

do
  asked = nil
  local els = render.elements(none, RECT, LAYOUT, style, nil, "")
  check("nothing is drawn for an empty query with no rows", emptyText(els) == nil and asked == nil)
end

do
  asked = nil
  local els = render.elements(some, RECT, LAYOUT, style, nil, "sa")
  check("nothing is drawn while rows are showing", emptyText(els) == nil and asked == nil)
end

do
  local els = render.elements(none, RECT, LAYOUT, {}, nil, "zzz")
  check("a caller with no empty state routine draws nothing there", emptyText(els) == nil)
end

-- A one row list, the smallest a presentation may declare, still has room for the message.
do
  local one = { font = FONT, textSize = 16, textLine = 22, subFont = FONT, subSize = 14,
    subLine = 19, numFont = FONT, numSize = 16, rowH = ROW_H, rowCount = 1, padBottom = 14 }
  asked = nil
  render.elements(model.newState({}, one, ""), RECT, one, style, nil, "zzz")
  check("a one row list hands the empty state a whole row of room",
    asked and asked.h >= ROW_H, asked and tostring(asked.h) or "never asked")
end

-- Zero rows still answer no highlighted row and no visible slot, so Return, a digit and a click
-- reach nothing, exactly as before the empty state.
check("no row is highlighted under the empty state", model.highlightedRow(none) == nil)
check("no visible slot answers under the empty state", model.rowAtVisibleSlot(none, 1) == nil)
check("no point in the band answers a row", model.rowAtPoint(none, ROW_H / 2) == nil)
