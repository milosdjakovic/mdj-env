-- Unit case for the pure canvas geometry arithmetic,
-- Spoons/Olm.spoon/lib/chooser/providers/canvas/geometry.lua, phase three a part one of
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
local modulePath = caseDir .. "/../../Spoons/Olm.spoon/lib/chooser/providers/canvas/geometry.lua"

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
  -- Short enough that the nine requested rows do not survive. avail works out to three
  -- hundred thirteen points, 500 less 120 of padding, 43 of field and 24 of margin, which fits
  -- five rows of fifty seven, 22 body line plus 19 caption line plus 2 times 8 of padding, and
  -- no more, since six would need 342.
  local shortScreen = { x = 0, y = 0, w = 1440, h = 500 }
  local rects = geometry.resolve(shortScreen, geometry.DEFAULT_LAYOUT, nil)
  check("a short screen trims the row count below what the layout asked for",
    rects.rowCount == 5, "got " .. tostring(rects.rowCount))
  check("the row band's own height is exactly the trimmed row count times the row height",
    rects.list.h == rects.rowCount * geometry.DEFAULT_LAYOUT.rowH,
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
-- The field rect and the list rect sit inside the canvas at the edge margin, the field
-- on top, the list directly beneath it, nothing between them.
--------------------------------------------------------------------------------

do
  local rects = geometry.resolve(ROOMY_SCREEN, geometry.DEFAULT_LAYOUT, nil)
  local L = geometry.DEFAULT_LAYOUT
  check("the field sits inset from the canvas by the edge margin on the leading edges",
    rects.field.x == rects.canvas.x + L.edgeMargin and rects.field.y == rects.canvas.y + L.edgeMargin,
    "x " .. tostring(rects.field.x) .. " y " .. tostring(rects.field.y))
  check("the field stands exactly the field height tall",
    rects.field.h == L.baseH, "got " .. tostring(rects.field.h))
  check("the list sits directly beneath the field with nothing between them",
    rects.list.y == rects.field.y + rects.field.h, "got " .. tostring(rects.list.y))
  check("the field and the list share the same width, the canvas less the edge margin twice",
    rects.field.w == rects.list.w and rects.list.w == rects.canvas.w - 2 * L.edgeMargin)
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
-- M.textBudget, computed from the layout rather than measured, replacing native.lua's
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
  -- The concrete number too, five hundred ninety six less sixteen, twenty eight, ten,
  -- sixteen and twenty eight again, so a change to the formula above and a change to
  -- DEFAULT_LAYOUT's own numbers cannot both drift and still pass unnoticed.
  check("the width budget for this layout on a roomy screen comes out to three hundred fifty eight points",
    geometry.textBudget(rects, L) == 358, "got " .. tostring(geometry.textBudget(rects, L)))
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
  -- three and a half is exactly what one hundred point five leaves over a fifty seven
  -- point row, and a point at the very top of the list rect still answers slot one
  -- with that same remainder as its own offset, matching the row still partly visible
  -- above the viewport's own top.
  local rects = geometry.resolve(ROOMY_SCREEN, geometry.DEFAULT_LAYOUT, nil)
  local point = { x = rects.list.x + 10, y = rects.list.y }
  local slot, offset = geometry.rowAtPoint(point, rects, geometry.DEFAULT_LAYOUT, 100.5)
  check("a fractional scrollTop is reduced to its own sub row remainder rather than used whole",
    slot == 1, "got " .. tostring(slot))
  check("the offset within that first visible row is exactly that remainder",
    math.abs(offset - 43.5) < 1e-9, "got " .. tostring(offset))
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
  local text = { title = { lineHeight = 27 }, body = { lineHeight = 22 }, caption = { lineHeight = 19 } }
  local d = geometry.derivedRows(text)
  check("a row is the body line 22 plus the caption line 19 plus twice the padding 8, which is 57",
    d.rowH == 57, "got " .. tostring(d.rowH))
  check("the field is the title line 27 plus twice the padding 8, which is 43",
    d.baseH == 43, "got " .. tostring(d.baseH))
  check("DEFAULT_LAYOUT states the same 57 and 43 for the shipped sizes",
    geometry.DEFAULT_LAYOUT.rowH == 57 and geometry.DEFAULT_LAYOUT.baseH == 43)
  local bigger = geometry.derivedRows({ title = { lineHeight = 34 }, body = { lineHeight = 26 }, caption = { lineHeight = 22 } })
  check("a larger body 26 and caption 22 reflow the row to 26 plus 22 plus 16, which is 64, and a title 34 the field to 50",
    bigger.rowH == 64 and bigger.baseH == 50, "got " .. tostring(bigger.rowH) .. " " .. tostring(bigger.baseH))
  local padded = geometry.derivedRows(text, 10)
  check("a padding of 10 gives 22 plus 19 plus 20, which is 61, and the field 27 plus 20, which is 47",
    padded.rowH == 61 and padded.baseH == 47, "got " .. tostring(padded.rowH) .. " " .. tostring(padded.baseH))
end
