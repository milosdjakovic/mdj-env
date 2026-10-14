-- Unit case for the pure canvas geometry arithmetic,
-- Spoons/Olm.spoon/lib/chooser/providers/default/geometry.lua, phase three a part one of
-- this track's build plan and built from docs/BRIEF-CANVAS-GEOMETRY.md. Every check
-- here drives that one file alone, with no hs.canvas, no hs.screen and no timer behind
-- it, the same reason test/cases/canvaslist.lua drives list model.lua alone rather than
-- through a canvas of its own. geometry.lua touches no hs function at all, so this case
-- would run correctly even outside a live Hammerspoon, though it is run through the
-- real one over hs -c the same way every case here is, since that is what test/units.sh
-- already does for the whole suite.
--
-- Each check prints one line, PASS or FAIL followed by a plain description, and the
-- runner counts from those lines alone, the same convention every other case follows.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local modulePath = caseDir .. "/../../Spoons/Olm.spoon/lib/chooser/providers/default/geometry.lua"

local moduleChunk, loadErr = loadfile(modulePath)
if not moduleChunk then
  print("FAIL load Olm.spoon canvas geometry.lua, " .. tostring(loadErr))
  return
end
local geometry = moduleChunk()

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

-- A plain screen frame, wide and tall enough that the row count the layout asks for
-- always survives the trim, used by every check below that is not itself testing the
-- trim or the vertical clamp.
local ROOMY_SCREEN = { x = 0, y = 0, w = 1440, h = 900 }

--------------------------------------------------------------------------------
-- The row trim, the screen height less twice the minimum vertical padding, less the
-- field height and the edge margin twice, divided by the row height, floored, and
-- never more than the requested count.
--------------------------------------------------------------------------------

do
  local rects = geometry.resolve(ROOMY_SCREEN, geometry.DEFAULT_LAYOUT, nil)
  check("a roomy screen keeps the full requested row count",
    rects.rowCount == geometry.DEFAULT_LAYOUT.rowCount,
    "got " .. tostring(rects.rowCount))
end

do
  -- Short enough that the nine requested rows do not survive. avail is 500 less 120 of
  -- padding, 61 of field, 10 of margin below the list and the peek of a row, which fits five
  -- rows of fifty one and no more.
  local shortScreen = { x = 0, y = 0, w = 1440, h = 500 }
  local rects = geometry.resolve(shortScreen, geometry.DEFAULT_LAYOUT, nil)
  check("a short screen trims the row count below what the layout asked for",
    rects.rowCount == 5, "got " .. tostring(rects.rowCount))
  local peek = geometry.DEFAULT_LAYOUT.peek
  check("the row band's own height is the trimmed row count and the peek times the row height",
    rects.list.h == (rects.rowCount + peek) * geometry.DEFAULT_LAYOUT.rowH
      and rects.viewRows == rects.rowCount + peek,
    "got " .. tostring(rects.list.h))
end

do
  -- A screen too short for even one whole row bottoms the trim out at zero rather than
  -- leaving it negative, the same answer something sane rather than raising posture
  -- every other file in this provider already keeps.
  local tinyScreen = { x = 0, y = 0, w = 1440, h = 120 }
  local rects = geometry.resolve(tinyScreen, geometry.DEFAULT_LAYOUT, nil)
  check("a screen too short for even one row trims the row count to zero rather than negative",
    rects.rowCount == 0, "got " .. tostring(rects.rowCount))
end

--------------------------------------------------------------------------------
-- Centring the pair, with and without a companion, and paneWidth as true, as a number,
-- and as nil, every answer capped by paneMaxW.
--------------------------------------------------------------------------------

do
  local rects = geometry.resolve(ROOMY_SCREEN, geometry.DEFAULT_LAYOUT, nil)
  check("paneWidth nil answers no companion at all", rects.companion == nil)
  local expectedX = ROOMY_SCREEN.x + math.floor((ROOMY_SCREEN.w - geometry.DEFAULT_LAYOUT.width) / 2)
  check("with no companion the canvas alone is centred on the screen",
    rects.canvas.x == expectedX, "got " .. tostring(rects.canvas.x))
end

do
  -- paneWidth true inherits the canvas's own width, six hundred twenty, which exceeds
  -- paneMaxW of four hundred eighty, so the cap is what actually lands.
  local rects = geometry.resolve(ROOMY_SCREEN, geometry.DEFAULT_LAYOUT, true)
  check("paneWidth true is capped by paneMaxW rather than truly inheriting the canvas width",
    rects.companion.w == geometry.DEFAULT_LAYOUT.paneMaxW,
    "got " .. tostring(rects.companion.w))
  local total = rects.canvas.w + geometry.DEFAULT_LAYOUT.gap + rects.companion.w
  local expectedX = ROOMY_SCREEN.x + math.floor((ROOMY_SCREEN.w - total) / 2)
  check("the pair centres as one unit, the canvas plus the gap plus the companion",
    rects.canvas.x == expectedX, "got " .. tostring(rects.canvas.x))
  check("the companion sits directly beside the canvas across the gap",
    rects.companion.x == rects.canvas.x + rects.canvas.w + geometry.DEFAULT_LAYOUT.gap,
    "got " .. tostring(rects.companion.x))
end

do
  -- A number under the cap overrides the width independently rather than inheriting
  -- the canvas's own.
  local rects = geometry.resolve(ROOMY_SCREEN, geometry.DEFAULT_LAYOUT, 300)
  check("a paneWidth number under the cap is taken as is",
    rects.companion.w == 300, "got " .. tostring(rects.companion.w))
end

do
  -- A number over the cap is still capped, exactly as true is.
  local rects = geometry.resolve(ROOMY_SCREEN, geometry.DEFAULT_LAYOUT, 900)
  check("a paneWidth number over the cap is capped by paneMaxW",
    rects.companion.w == geometry.DEFAULT_LAYOUT.paneMaxW,
    "got " .. tostring(rects.companion.w))
end

do
  local rects = geometry.resolve(ROOMY_SCREEN, geometry.DEFAULT_LAYOUT, 0)
  check("paneWidth zero answers no companion, matching nil",
    rects.companion == nil)
end

--------------------------------------------------------------------------------
-- The chooser frame is the canvas frame, answered under both names.
--------------------------------------------------------------------------------

do
  local rects = geometry.resolve(ROOMY_SCREEN, geometry.DEFAULT_LAYOUT, nil)
  check("chooser and canvas answer the very same rectangle",
    rects.chooser.x == rects.canvas.x and rects.chooser.y == rects.canvas.y
      and rects.chooser.w == rects.canvas.w and rects.chooser.h == rects.canvas.h)
end

--------------------------------------------------------------------------------
-- The canvas has no padding of its own. The field spans the top, its text inset by the margin
-- so it starts on the highlighted row's left edge, and the list starts right under it with no
-- gap, padded by the margin on its sides and below.
--------------------------------------------------------------------------------

do
  local rects = geometry.resolve(ROOMY_SCREEN, geometry.DEFAULT_LAYOUT, nil)
  local L = geometry.DEFAULT_LAYOUT
  check("the field sits at the canvas top, its text inset by the margin so it lines up with the highlighted row's edge",
    rects.field.x == rects.list.x and rects.field.x == rects.canvas.x + L.marginX and rects.field.y == rects.canvas.y,
    "x " .. tostring(rects.field.x) .. " y " .. tostring(rects.field.y))
  check("the field stands exactly the field height tall",
    rects.field.h == L.baseH, "got " .. tostring(rects.field.h))
  check("the list starts right under the field with no gap",
    rects.list.y == rects.field.y + rects.field.h, "got " .. tostring(rects.list.y))
  check("the list and the field are both the canvas less the margin twice",
    rects.list.w == rects.canvas.w - 2 * L.marginX and rects.field.w == rects.list.w)
  check("the canvas is the field, the rows with the half row peek and one margin below them",
    rects.canvas.h == L.baseH + (rects.rowCount + L.peek) * L.rowH + L.marginY)
  check("every x inset is the one inset x, the kit's 14, and the margin below is its y, 10",
    L.padX == 14 and L.iconGap == 14 and L.marginX == 14 and L.marginY == 10)
end

--------------------------------------------------------------------------------
-- The vertical clamp. The top fraction down from the top of the screen, clamped never
-- closer than the minimum padding to either edge, and the top pad winning when the
-- surface is too tall to keep both.
--------------------------------------------------------------------------------

do
  -- A screen tall enough that topFrac's own six percent lands well inside both pads,
  -- so this checks the plain unclamped arithmetic, the top fraction down from the top
  -- of the screen and nothing more.
  local tallScreen = { x = 0, y = 0, w = 1440, h = 3000 }
  local rects = geometry.resolve(tallScreen, geometry.DEFAULT_LAYOUT, nil)
  local L = geometry.DEFAULT_LAYOUT
  local wanted = tallScreen.y + math.floor(tallScreen.h * L.topFrac)
  check("with room to spare the vertical position is exactly the top fraction down from the screen's own top",
    rects.canvas.y == wanted, "got " .. tostring(rects.canvas.y) .. " wanted " .. tostring(wanted))
end

do
  -- topFrac's own six percent of a nine hundred point screen wants fifty four points
  -- down, less than minVPad's own sixty, so this checks the ordinary clamp up to the
  -- top pad, not the degenerate case where the two pads cannot both be kept at all.
  local rects = geometry.resolve(ROOMY_SCREEN, geometry.DEFAULT_LAYOUT, nil)
  local L = geometry.DEFAULT_LAYOUT
  local lo = ROOMY_SCREEN.y + L.minVPad
  check("a wanted position closer to the top than the minimum padding clamps down to that padding",
    rects.canvas.y == lo, "got " .. tostring(rects.canvas.y) .. " expected " .. tostring(lo))
end

do
  -- A layout whose own minimum padding leaves no room for both pads at once against
  -- this screen height, engineered directly through a custom layout rather than
  -- through the row trim, so this checks the clamp itself and nothing the trim also
  -- happens to affect. avail comes out negative, so the row count trims to zero and
  -- the canvas is only the field plus the edge margin twice, sixty two points tall,
  -- and even that will not fit both a sixty point top pad and a sixty point bottom pad
  -- against a two hundred point screen.
  local L = {}
  for k, v in pairs(geometry.DEFAULT_LAYOUT) do L[k] = v end
  L.minVPad = 90
  local shortScreen = { x = 0, y = 0, w = 1440, h = 200 }
  local rects = geometry.resolve(shortScreen, L, nil)
  local lo = shortScreen.y + L.minVPad
  local hi = shortScreen.y + shortScreen.h - L.minVPad - rects.canvas.h
  check("this layout and screen are too tall to keep both pads, the setup this checks",
    hi < lo, "hi " .. tostring(hi) .. " lo " .. tostring(lo))
  check("the top pad wins, the canvas sits exactly the minimum padding down rather than higher or lower",
    rects.canvas.y == lo, "got " .. tostring(rects.canvas.y))
end

--------------------------------------------------------------------------------
-- M.textBudget, computed from the layout rather than measured, replacing legacy.lua's
-- own ROW_TEXT_INSET constant.
--------------------------------------------------------------------------------

do
  local rects = geometry.resolve(ROOMY_SCREEN, geometry.DEFAULT_LAYOUT, nil)
  local L = geometry.DEFAULT_LAYOUT
  local expected = rects.list.w - L.padX - L.iconSize - L.iconGap - L.padX - L.iconSize
  check("textBudget is the list rect's own width less the leading pad, the icon and its "
    .. "gap, the trailing pad, and the numeral column",
    geometry.textBudget(rects, L) == expected,
    "got " .. tostring(geometry.textBudget(rects, L)) .. " expected " .. tostring(expected))
  -- The concrete number too, four hundred fifty two less fourteen, twenty eight, fourteen,
  -- fourteen and twenty eight again, so a change to the formula above and a change to
  -- DEFAULT_LAYOUT's own numbers cannot both drift and still pass unnoticed.
  check("the width budget for this layout on a roomy screen comes out to three hundred fifty four points",
    geometry.textBudget(rects, L) == 354, "got " .. tostring(geometry.textBudget(rects, L)))
end

do
  check("textBudget answers zero rather than raising when handed no rects at all",
    geometry.textBudget({}, geometry.DEFAULT_LAYOUT) == 0)
end

--------------------------------------------------------------------------------
-- M.rowAtPoint, a slot in the visible band and the point's own offset within that
-- row, or nil outside the list rect entirely, including a point sitting in the field.
--------------------------------------------------------------------------------

do
  local rects = geometry.resolve(ROOMY_SCREEN, geometry.DEFAULT_LAYOUT, nil)
  local L = geometry.DEFAULT_LAYOUT

  local firstRowPoint = { x = rects.list.x + 10, y = rects.list.y + 5 }
  local slot1, offset1 = geometry.rowAtPoint(firstRowPoint, rects, L, 0)
  check("a point five points into the first visible row answers slot one",
    slot1 == 1, "got " .. tostring(slot1))
  check("and the offset within that row is the same five points",
    offset1 == 5, "got " .. tostring(offset1))

  local lastRowY = rects.list.y + (rects.rowCount - 1) * L.rowH + 16
  local lastRowPoint = { x = rects.list.x + 10, y = lastRowY }
  local slotLast = geometry.rowAtPoint(lastRowPoint, rects, L, 0)
  check("a point in the last visible row answers that row's own slot",
    slotLast == rects.rowCount, "got " .. tostring(slotLast))
end

do
  -- A fractional scrollTop, the sub row remainder rather than the whole of it. Forty
  -- nine and a half is exactly what one hundred point five leaves over a fifty one
  -- point row, and a point at the very top of the list rect still answers slot one
  -- with that same remainder as its own offset, matching the row still partly visible
  -- above the viewport's own top.
  local rects = geometry.resolve(ROOMY_SCREEN, geometry.DEFAULT_LAYOUT, nil)
  local point = { x = rects.list.x + 10, y = rects.list.y }
  local slot, offset = geometry.rowAtPoint(point, rects, geometry.DEFAULT_LAYOUT, 100.5)
  check("a fractional scrollTop is reduced to its own sub row remainder rather than used whole",
    slot == 1, "got " .. tostring(slot))
  check("the offset within that first visible row is exactly that remainder",
    math.abs(offset - 49.5) < 1e-9, "got " .. tostring(offset))
end

do
  local rects = geometry.resolve(ROOMY_SCREEN, geometry.DEFAULT_LAYOUT, nil)
  local L = geometry.DEFAULT_LAYOUT

  local inField = { x = rects.field.x + 10, y = rects.field.y + 5 }
  check("a point sitting in the field rather than the list answers nil rather than row zero",
    geometry.rowAtPoint(inField, rects, L, 0) == nil)

  local outside = { x = rects.canvas.x - 500, y = rects.canvas.y - 500 }
  check("a point outside the canvas entirely answers nil",
    geometry.rowAtPoint(outside, rects, L, 0) == nil)

  local belowCanvas = { x = rects.list.x + 10, y = rects.canvas.y + rects.canvas.h + 5 }
  check("a point below the canvas but on the same horizontal band still answers nil",
    geometry.rowAtPoint(belowCanvas, rects, L, 0) == nil)
end

--------------------------------------------------------------------------------
-- The derived row and field heights, lib/chooser/rowheight.lua through M.derivedRows.
--------------------------------------------------------------------------------

do
  -- The inset's y is measured to the letters, so the field is the title's capital plus the
  -- inset twice and a row is the inset, the body's capital, one caption line and the inset.
  local text = { title = { lineHeight = 27 }, body = { lineHeight = 22 }, caption = { lineHeight = 19 } }
  local cap = { title = 14.1, body = 11.3 }
  local inset = { x = 14, y = 10 }
  local d = geometry.derivedRows(text, cap, inset)
  check("a row is 10 plus the body capital 11.3 plus the caption line 19 plus 10, rounded up to 51",
    d.rowH == 51, "got " .. tostring(d.rowH))
  check("the field is a row's 51 plus half again its padding, 10 more, 61",
    d.baseH == 61, "got " .. tostring(d.baseH))
  check("DEFAULT_LAYOUT states the same 51 and 61 at the shipped sizes",
    geometry.DEFAULT_LAYOUT.rowH == 51 and geometry.DEFAULT_LAYOUT.baseH == 61)
  local huge = geometry.derivedRows(text, { title = 40, body = 11.3 }, inset)
  check("a title capital of 40 no longer fits a row, so the field grows to 15 plus 40 plus 15",
    huge.baseH == 70 and huge.rowH == 51, "got " .. tostring(huge.baseH))
  local bigger = geometry.derivedRows({ title = { lineHeight = 34 }, body = { lineHeight = 26 }, caption = { lineHeight = 22 } },
    { title = 18, body = 14 }, inset)
  check("a larger body capital 14 and caption line 22 reflow the row to 56, and the field to 66",
    bigger.rowH == 56 and bigger.baseH == 66, "got " .. tostring(bigger.rowH) .. " " .. tostring(bigger.baseH))
  local roomier = geometry.derivedRows(text, cap, { x = 14, y = 12 })
  check("an inset y of 12 grows the row to 55 and the field to 67",
    roomier.rowH == 55 and roomier.baseH == 67, "got " .. tostring(roomier.rowH) .. " " .. tostring(roomier.baseH))
end
