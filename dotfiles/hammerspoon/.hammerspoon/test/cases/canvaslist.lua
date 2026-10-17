-- Unit case for the pure model and the render helper behind the canvas row list,
-- Spoons/Olm.spoon/lib/chooser/providers/default/list/model.lua and render.lua, phase
-- three a of this track's build plan and built from the canvas list brief. Every check
-- here drives those two files alone, with no eventtap, no canvas, and no timer behind
-- them, the same reason test/cases/canvasfield.lua drives field model.lua alone rather
-- than through its own shell.
--
-- model.lua loads lib/chooser/rank.lua itself, and render.lua loads model.lua itself,
-- both by a relative path resolved through debug.getinfo the same way field input.lua
-- resolves its own siblings, so this case loads both with the plain global environment
-- rather than a restricted one, the same choice test/cases/match.lua already makes for a
-- module that reaches another file on disk. render.lua also reaches hs.styledtext for
-- its own font metrics as of round four, and this case is run through the real running
-- Hammerspoon over hs -c the same way every case here is, so that call answers for real
-- rather than needing a stand in.
--
-- Each check prints one line, PASS or FAIL followed by a plain description, and the
-- runner counts from those lines alone, the same convention every other case follows.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local listDir = caseDir .. "/../../Spoons/Olm.spoon/lib/chooser/providers/default/list/"
local modulePath = listDir .. "model.lua"
local renderPath = listDir .. "render.lua"

local moduleChunk, loadErr = loadfile(modulePath)
if not moduleChunk then
  print("FAIL load Olm.spoon canvas list model.lua, " .. tostring(loadErr))
  return
end
local model = moduleChunk()

local renderChunk, renderLoadErr = loadfile(renderPath)
if not renderChunk then
  print("FAIL load Olm.spoon canvas list render.lua, " .. tostring(renderLoadErr))
  return
end
local render = renderChunk()

-- The model ranks only with the matcher it is handed, since phase one of the unified search
-- deleted its own copy hard wired to fuzzy, so the filtering cases below hand it the real one.
local fuzzy = assert(loadfile(caseDir .. "/../../Spoons/Olm.spoon/lib/chooser/match.lua"))().fuzzy

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

-- A supplier row exactly in the shape lib/chooser/providers/legacy.lua documents at its
-- own head, title, subTitle, image, enabled, item and filterText, since decision one of
-- the brief asks for a row this list can rank to be a row the native provider could have
-- drawn.
local function row(title, subTitle, item, opts)
  opts = opts or {}
  return {
    title = title, subTitle = subTitle, item = item,
    enabled = opts.enabled, filterText = opts.filterText, image = opts.image,
  }
end

local function rowSet(n)
  local out = {}
  for i = 1, n do
    out[i] = row("Row " .. i, "sub " .. i, i)
  end
  return out
end

-- The layout every viewport check below states for itself rather than leaning on
-- model.lua's own fallback, ROW_H being the number every points based assertion in this
-- file is written against, so a reader can see where forty two, or any multiple of it,
-- comes from rather than treating it as a number that fell out of the sky.
local ROW_H = 42
local ROWS_10 = { rowCount = 10, rowH = ROW_H }

-- The type the render layouts below carry, the kit's body, caption and section roles at
-- their shipped sizes. A line is the size times 1.35 rounded up, so body 16 gives 22,
-- caption 14 gives 19, and section 12 gives 17. The row height a render layout states is the
-- derived one, 22 body plus 19 caption plus 2 times a padding of 8, which is 57, the number
-- geometry.lua's DEFAULT_LAYOUT answers for these sizes.
local FONT = ".AppleSystemUIFont"
local PAD = 8
local TYPE = {
  font = FONT, textSize = 16, textLine = 22,
  subFont = FONT, subSize = 14, subLine = 19,
  numFont = FONT, numSize = 12,
}
local DERIVED_ROW_H = 22 + 19 + 2 * PAD

--------------------------------------------------------------------------------
-- Seeding a state
--------------------------------------------------------------------------------

do
  local s = model.newState(rowSet(3), ROWS_10)
  check("a freshly seeded state highlights the first row", s.highlight == 1)
  check("a freshly seeded state starts the viewport at the very top, scrollTop zero",
    s.scrollTop == 0, "got " .. tostring(s.scrollTop))
  check("a freshly seeded state keeps every row when the query is empty",
    #s.filtered == 3, "got " .. tostring(#s.filtered))
end

do
  local s = model.newState({}, ROWS_10)
  check("seeding with no rows at all answers no highlight rather than one on nothing",
    s.highlight == nil)
end

--------------------------------------------------------------------------------
-- Filtering through the real matcher, decision two, rather than a rule of this file's own
--------------------------------------------------------------------------------

do
  local rows = rowSet(5)
  rows[3].filterText = "special keyword"
  local s = model.newState(rows, ROWS_10)
  local filtered = model.setQuery(s, "special", fuzzy)
  check("a query narrows the filtered set to the rows the real matcher keeps",
    #filtered.filtered == 1, "got " .. tostring(#filtered.filtered))
  check("the surviving row is the one whose filterText the matcher was asked to search",
    filtered.filtered[1].item == 3)
end

do
  local rows = {
    row("Displays", "System Preferences pane", 1),
    -- Was Downloads System Preferences Look until 2026-10-17, whose words spell dspl by their
    -- initials and so now lead Displays by design. This bag keeps the case's point.
    row("Device Management sync profile lock", "an unrelated bag of words", 2),
  }
  local s = model.newState(rows, ROWS_10)
  local filtered = model.setQuery(s, "dspl", fuzzy)
  check("ranking through the real fuzzy strategy puts a near contiguous match first",
    #filtered.filtered >= 1 and filtered.filtered[1].item == 1,
    "got " .. tostring(filtered.filtered[1] and filtered.filtered[1].item))
end

do
  local rows = rowSet(4)
  local s = model.newState(rows, ROWS_10)
  local filtered = model.setQuery(s, "nothing matches this at all", fuzzy)
  check("a query the matcher rejects for every row answers an empty filtered set",
    #filtered.filtered == 0)
  check("an empty filtered set carries no highlight rather than one on nothing",
    filtered.highlight == nil)
end

do
  local rows = rowSet(4)
  rows[2].filterText = nil
  rows[2].title, rows[2].subTitle = "Alpha", "Beta"
  local s = model.newState(rows, ROWS_10)
  local filtered = model.setQuery(s, "Alpha Beta", fuzzy)
  check("a row with no filterText is searched on its title and subTitle joined, matching haystackOf",
    #filtered.filtered == 1 and filtered.filtered[1].item == 2)
end

--------------------------------------------------------------------------------
-- Movement, one function per direction, decision five's wrap at both ends
--------------------------------------------------------------------------------

do
  local s = model.newState(rowSet(3), ROWS_10)
  s = model.moveDown(s)
  check("moveDown steps the highlight forward by one row", s.highlight == 2)
  s = model.moveDown(s)
  check("a second moveDown reaches the last row", s.highlight == 3)
  s = model.moveDown(s)
  check("moveDown past the last row wraps the highlight back to the first",
    s.highlight == 1, "got " .. tostring(s.highlight))
end

do
  local s = model.newState(rowSet(3), ROWS_10)
  s = model.moveUp(s)
  check("moveUp past the first row wraps the highlight to the last",
    s.highlight == 3, "got " .. tostring(s.highlight))
  s = model.moveUp(s)
  check("a second moveUp steps back one row from the wrapped position", s.highlight == 2)
end

do
  local s = model.newState({}, ROWS_10)
  local afterDown = model.moveDown(s)
  local afterUp = model.moveUp(s)
  check("moveDown on an empty filtered set answers the state unchanged rather than raising",
    afterDown.highlight == nil)
  check("moveUp on an empty filtered set answers the state unchanged rather than raising",
    afterUp.highlight == nil)
end

--------------------------------------------------------------------------------
-- The viewport following the highlight, points rather than a row index as of round five.
-- The keyboard moves the viewport only when the highlight is not fully inside it, and
-- then only far enough to show that row, so a partly cut row stays cut and a fractional
-- scrollTop is left alone. Keeping the highlight visible and following the wheel are two
-- separate questions this file answers with two separate functions.
--------------------------------------------------------------------------------

do
  local s = model.newState(rowSet(25), ROWS_10)
  for _ = 1, 9 do s = model.moveDown(s) end
  check("the viewport has not scrolled while the highlight is still inside the first band",
    s.highlight == 10 and s.scrollTop == 0,
    "highlight " .. tostring(s.highlight) .. " scrollTop " .. tostring(s.scrollTop))
  s = model.moveDown(s)
  check("moving one row past the visible band scrolls the viewport down by exactly one row's height",
    s.highlight == 11 and s.scrollTop == ROW_H,
    "highlight " .. tostring(s.highlight) .. " scrollTop " .. tostring(s.scrollTop))
end

do
  local s = model.newState(rowSet(25), ROWS_10)
  for _ = 1, 10 do s = model.moveDown(s) end
  check("the viewport has scrolled down by one row's height to keep the eleventh row visible",
    s.scrollTop == ROW_H, "got " .. tostring(s.scrollTop))
  for _ = 1, 9 do s = model.moveUp(s) end
  check("moving back up within the same band leaves the viewport exactly where it sat",
    s.highlight == 2 and s.scrollTop == ROW_H,
    "highlight " .. tostring(s.highlight) .. " scrollTop " .. tostring(s.scrollTop))
  s = model.moveUp(s)
  check("moving one row above the band scrolls the viewport back up by one row's height",
    s.highlight == 1 and s.scrollTop == 0,
    "highlight " .. tostring(s.highlight) .. " scrollTop " .. tostring(s.scrollTop))
end

do
  local s = model.newState(rowSet(25), ROWS_10)
  for _ = 1, 24 do s = model.moveDown(s) end
  check("the highlight reaches the very last row after stepping through every other one",
    s.highlight == 25, "got " .. tostring(s.highlight))
  s = model.moveDown(s)
  check("wrapping from the last row to the first snaps the viewport back to the top",
    s.highlight == 1 and s.scrollTop == 0,
    "highlight " .. tostring(s.highlight) .. " scrollTop " .. tostring(s.scrollTop))
  s = model.moveUp(s)
  check("wrapping from the first row to the last snaps the viewport to the tail band",
    s.highlight == 25 and s.scrollTop == 15 * ROW_H,
    "highlight " .. tostring(s.highlight) .. " scrollTop " .. tostring(s.scrollTop))
end

do
  -- A keyboard press arriving while the highlight already sits fully inside whatever
  -- fractional viewport a wheel left behind. Row five is fully visible at scrollTop one
  -- hundred fifty, so the keyboard has no reason to move scrollTop at all.
  local s = model.newState(rowSet(25), ROWS_10)
  for _ = 1, 4 do s = model.moveDown(s) end
  local scrolled = model.scrollTo(s, 150)
  check("a fractional wheel offset can still fully show the current highlight",
    scrolled.scrollTop == 150 and scrolled.highlight == 5,
    "scrollTop " .. tostring(scrolled.scrollTop) .. " highlight " .. tostring(scrolled.highlight))
  local movedDown = model.moveDown(scrolled)
  check("the keyboard still steps the highlight forward normally from a fractional viewport",
    movedDown.highlight == 6, "got " .. tostring(movedDown.highlight))
  check("the keyboard leaves a fractional scrollTop unchanged while the highlight stays fully visible",
    movedDown.scrollTop == 150, "got " .. tostring(movedDown.scrollTop))
end

do
  -- A viewport that is not a whole number of rows, nine and a half, so scrolling down
  -- leaves the top row cut. One move up must not realign the viewport, and the viewport
  -- moves again only once the highlight reaches the cut row.
  local s = model.newState(rowSet(25), { rowCount = 9.5, rowH = ROW_H })
  for _ = 1, 10 do s = model.moveDown(s) end
  local cut = s.scrollTop
  check("scrolling down past the end of view leaves the top row partly cut",
    s.highlight == 11 and cut % ROW_H ~= 0, "highlight " .. tostring(s.highlight) .. " scrollTop " .. tostring(cut))
  s = model.moveUp(s)
  check("one move up leaves the cut top row where it was",
    s.highlight == 10 and s.scrollTop == cut, "scrollTop " .. tostring(s.scrollTop) .. " expected " .. tostring(cut))
  local firstShown = math.floor(cut / ROW_H) + 1
  while s.highlight > firstShown + 1 do s = model.moveUp(s) end
  check("moving up through the fully visible rows never moves the viewport",
    s.scrollTop == cut, "scrollTop " .. tostring(s.scrollTop) .. " expected " .. tostring(cut))
  s = model.moveUp(s)
  check("reaching the cut top row sets scrollTop to that row's own top",
    s.highlight == firstShown and s.scrollTop == (firstShown - 1) * ROW_H,
    "highlight " .. tostring(s.highlight) .. " scrollTop " .. tostring(s.scrollTop))
end

do
  local s = model.newState(rowSet(3), ROWS_10)
  check("a filtered set smaller than the viewport never scrolls at all", s.scrollTop == 0)
  s = model.moveDown(s)
  s = model.moveDown(s)
  check("moving within a short list still never scrolls, the whole list already fits",
    s.scrollTop == 0)
end

--------------------------------------------------------------------------------
-- Scrolling on its own, round five, the wheel and the trackpad's own move rather than
-- the keyboard's. scrollTo and scrollBy never touch highlight, and both are bounded at
-- either end with no rubber banding, decision four of the original brief being replaced.
--------------------------------------------------------------------------------

do
  local s = model.newState(rowSet(25), ROWS_10)
  local scrolled = model.scrollTo(s, 17)
  check("scrollTo answers a point offset with no obligation to land on a row boundary",
    scrolled.scrollTop == 17, "got " .. tostring(scrolled.scrollTop))
  check("scrolling on its own never moves the highlight",
    scrolled.highlight == s.highlight, "got " .. tostring(scrolled.highlight))
end

do
  local s = model.newState(rowSet(25), ROWS_10)
  local scrolledPastTop = model.scrollTo(s, -500)
  check("scrollTo is bounded at the top of the list rather than rubber banding past it",
    scrolledPastTop.scrollTop == 0, "got " .. tostring(scrolledPastTop.scrollTop))

  local atBottom = model.scrollTo(s, model.maxScrollTop(s))
  local scrolledPastBottom = model.scrollTo(atBottom, model.maxScrollTop(atBottom) + 500)
  check("scrollTo is bounded at the bottom of the list rather than rubber banding past it",
    scrolledPastBottom.scrollTop == model.maxScrollTop(s),
    "got " .. tostring(scrolledPastBottom.scrollTop) .. " max " .. tostring(model.maxScrollTop(s)))
end

do
  local s = model.newState(rowSet(25), ROWS_10)
  local once = model.scrollBy(s, 10)
  local twice = model.scrollBy(once, 5)
  check("scrollBy moves scrollTop by a relative amount of points rather than an absolute one",
    twice.scrollTop == 15, "got " .. tostring(twice.scrollTop))
  check("scrollBy never moves the highlight either", twice.highlight == s.highlight)
end

do
  -- The bug this whole split guards against, made concrete. A wheel scrolls the
  -- viewport away from the highlight, and merely reading the state back afterward, the
  -- way highlightedRow and visibleRows both do by normalizing first, must not undo that
  -- scroll, only an actual keyboard movement is allowed to pull the viewport back.
  local s = model.newState(rowSet(25), ROWS_10)
  local scrolled = model.scrollTo(s, model.maxScrollTop(s))
  local stillScrolled = model.normalized(scrolled)
  check("normalizing a wheel scrolled state leaves scrollTop exactly where the wheel put it",
    stillScrolled.scrollTop == scrolled.scrollTop,
    "got " .. tostring(stillScrolled.scrollTop) .. " expected " .. tostring(scrolled.scrollTop))
  local afterRead = model.highlightedRow(scrolled)
  check("reading the highlighted row after a wheel scroll answers the row untouched",
    afterRead.item == 1)
  local movedBack = model.moveDown(scrolled)
  check("the highlight still steps forward by one row exactly as a plain moveDown always would",
    movedBack.highlight == 2, "got " .. tostring(movedBack.highlight))
  check("the next keyboard movement is what pulls the viewport back up to show the highlight",
    movedBack.scrollTop == ROW_H, "got " .. tostring(movedBack.scrollTop))
end

--------------------------------------------------------------------------------
-- Reading the highlighted row and the visible slice back out
--------------------------------------------------------------------------------

do
  local rows = rowSet(3)
  rows[2].enabled = false
  local s = model.newState(rows, ROWS_10)
  s = model.moveDown(s)
  local hr = model.highlightedRow(s)
  check("highlightedRow answers the row currently under the highlight",
    hr.item == 2)
  check("the highlight can sit on a disabled row, choosing it is a question for the consumer",
    hr.enabled == false)
end

do
  local s = model.setQuery(model.newState(rowSet(3), ROWS_10), "nothing at all matches", fuzzy)
  check("highlightedRow answers nil rather than raising when nothing is highlighted",
    model.highlightedRow(s) == nil)
end

do
  local s = model.newState(rowSet(25), ROWS_10)
  local visible = model.visibleRows(s)
  check("visibleRows answers exactly one slot per row the viewport can hold",
    #visible == 10, "got " .. tostring(#visible))
  check("the visible slice starts at the first filtered row", visible[1].row.item == 1)
  check("the visible slice ends at the row the viewport height allows", visible[10].row.item == 10)
  check("a row fully inside the viewport sits at a top offset that is a whole multiple of rowH",
    visible[3].top == 2 * ROW_H, "got " .. tostring(visible[3].top))
end

do
  local s = model.newState(rowSet(4), ROWS_10)
  local visible = model.visibleRows(s)
  check("visibleRows answers fewer entries than the viewport once the filtered set runs out",
    #visible == 4, "got " .. tostring(#visible))
end

do
  -- The partial row this whole round exists for, a viewport sitting between two rows on
  -- purpose. Scrolled seventeen points into a twenty five row list, row one is only
  -- partly shown, its own top sitting above the viewport by that same seventeen points,
  -- and row one still counts as the first visible row, cmd plus one would choose it.
  local s = model.newState(rowSet(25), ROWS_10)
  s = model.scrollTo(s, 17)
  local visible = model.visibleRows(s)
  check("a viewport sitting between two rows still answers the row scrolling off the top",
    visible[1].row.item == 1 and visible[1].top == -17,
    "item " .. tostring(visible[1].row.item) .. " top " .. tostring(visible[1].top))
  check("the row below it sits at a top offset short of a whole rowH by the same seventeen points",
    visible[2].row.item == 2 and visible[2].top == ROW_H - 17,
    "item " .. tostring(visible[2].row.item) .. " top " .. tostring(visible[2].top))
end

--------------------------------------------------------------------------------
-- Cmd plus a digit resolving to a visible row, round four's decision four, including
-- while the viewport sits between two rows, the case most likely to be off by one.
--------------------------------------------------------------------------------

do
  local s = model.newState(rowSet(30), ROWS_10)
  local row1, idx1 = model.rowAtVisibleSlot(s, 1)
  check("slot one resolves to the topmost row when the viewport sits exactly on a boundary",
    row1.item == 1 and idx1 == 1)
  local row9, idx9 = model.rowAtVisibleSlot(s, 9)
  check("slot nine resolves to the ninth row down from the top of the viewport",
    row9.item == 9 and idx9 == 9)
  local row11 = model.rowAtVisibleSlot(s, 11)
  check("a slot past what the viewport currently holds answers nil rather than a wrong row",
    row11 == nil)
end

do
  local s = model.newState(rowSet(30), ROWS_10)
  s = model.scrollTo(s, 17)
  local row1, idx1 = model.rowAtVisibleSlot(s, 1)
  check("cmd one resolves to the row currently topmost even when the viewport shows only part of it",
    idx1 == 1, "got " .. tostring(idx1))
  local row2, idx2 = model.rowAtVisibleSlot(s, 2)
  check("cmd two resolves to the second visible row counted from that same partly shown top row",
    idx2 == 2, "got " .. tostring(idx2))
  local row10, idx10 = model.rowAtVisibleSlot(s, 10)
  check("cmd carries no further than a ninth row by name, but the tenth still resolves for a caller that asks",
    idx10 == 10, "got " .. tostring(idx10))
end

--------------------------------------------------------------------------------
-- Normalizing a state handed in from outside with a highlight or a scrollTop drifted out
-- of range, the same defensive posture field model.lua's own normalizeState takes
--------------------------------------------------------------------------------

do
  local rows = rowSet(5)
  local drifted = {
    rows = rows, query = "", filtered = rows, highlight = 99, scrollTop = 4000,
    rowH = ROW_H, visibleCount = 10,
  }
  local ns = model.normalized(drifted)
  check("a highlight past the end of the filtered set is clamped rather than left invalid",
    ns.highlight == 5, "got " .. tostring(ns.highlight))
  check("a scrollTop past what the filtered set can fill is bounded to the largest legal offset",
    ns.scrollTop == 0, "got " .. tostring(ns.scrollTop))
end

do
  local ns = model.normalized({})
  check("normalizing a completely empty table answers no rows and no highlight rather than raising",
    ns.highlight == nil and #ns.filtered == 0)
end

--------------------------------------------------------------------------------
-- The row band's own height, round two of the canvas list brief. Scrolled to the
-- bottom, the last visible row used to draw a few points short of every row above it,
-- traced to a caller sizing its own canvas a little shorter than the whole number of
-- rows it asked this list to hold, the shortfall landing on the last one since every
-- row above it still had room. render.bandHeight is the fix, the one place that
-- multiplication happens, so a caller never repeats it and cannot quietly drift away
-- from what this file actually draws, and as of round five it is also the exact rect
-- this list's own row band is clipped to.
--------------------------------------------------------------------------------

do
  local layout = {
    width = 480, rowH = DERIVED_ROW_H, rowCount = 10, baseH = 94,
    font = TYPE.font, textSize = TYPE.textSize, textLine = TYPE.textLine, subFont = TYPE.subFont, subSize = TYPE.subSize, subLine = TYPE.subLine, numFont = TYPE.numFont, numSize = TYPE.numSize,
  }
  check("bandHeight answers exactly the row count times the row height, no remainder left over",
    render.bandHeight(layout) == layout.rowCount * layout.rowH,
    "got " .. tostring(render.bandHeight(layout)))
end

do
  check("bandHeight falls back to render.lua's own defaults the same way elements does",
    render.bandHeight(nil) == render.DEFAULT_LAYOUT.rowCount * render.DEFAULT_LAYOUT.rowH,
    "got " .. tostring(render.bandHeight(nil)))
end

do
  -- A state scrolled all the way to the bottom of a set taller than the viewport, the
  -- exact circumstance round two's hand test found broken, driven through the real
  -- elements() this time rather than through model.lua alone, so this proves what a
  -- caller actually gets back rather than only what the two numbers multiply to. The
  -- highlight rectangle is told apart from the clip rectangle round five now also draws
  -- by its own fillColor, the clip rectangle carries none, so this stays correct however
  -- many rectangle typed elements this file answers around it.
  local layout = {
    width = 480, rowH = DERIVED_ROW_H, rowCount = 10, baseH = 94,
    font = TYPE.font, textSize = TYPE.textSize, textLine = TYPE.textLine, subFont = TYPE.subFont, subSize = TYPE.subSize, subLine = TYPE.subLine, numFont = TYPE.numFont, numSize = TYPE.numSize,
  }
  local rows = rowSet(25)
  local s = model.newState(rows, layout)
  for _ = 1, #rows - 1 do s = model.moveDown(s) end
  check("scrolling to the very last row lands the highlight there with the viewport full",
    s.highlight == 25 and #model.visibleRows(s) == layout.rowCount,
    "highlight " .. tostring(s.highlight) .. " visible " .. tostring(#model.visibleRows(s)))

  local rect = { x = 0, y = 0, w = layout.width, h = render.bandHeight(layout) }
  local els = render.elements(s, rect, layout, {})

  local highlightBottom = nil
  for _, el in ipairs(els) do
    if el.type == "rectangle" and el.fillColor then
      highlightBottom = el.frame.y + el.frame.h
    end
  end
  check("the last row's own highlight rectangle reaches its bottom", highlightBottom ~= nil)
  check("the last row's bottom sits exactly at the row band's own bottom, rect.y plus bandHeight",
    highlightBottom == rect.y + render.bandHeight(layout),
    "got " .. tostring(highlightBottom) .. " expected " .. tostring(rect.y + render.bandHeight(layout)))
end

--------------------------------------------------------------------------------
-- Round four, the vertical centring rule. A row with a subtitle stacks title over
-- subtitle as before, a row without one centres the title using real font metrics
-- instead of sitting high with an empty gap beneath it.
--------------------------------------------------------------------------------

do
  local layout = {
    width = 480, rowH = DERIVED_ROW_H, rowCount = 10, baseH = 94,
    font = TYPE.font, textSize = TYPE.textSize, textLine = TYPE.textLine, subFont = TYPE.subFont, subSize = TYPE.subSize, subLine = TYPE.subLine, numFont = TYPE.numFont, numSize = TYPE.numSize,
  }
  local rows = {
    row("Has a subtitle", "the second line", 1),
    row("No subtitle at all", nil, 2),
  }
  local s = model.newState(rows, layout)
  local rect = { x = 0, y = 0, w = layout.width, h = render.bandHeight(layout) }
  local els = render.elements(s, rect, layout, {})

  local titleY = {}
  local subY = nil
  for _, el in ipairs(els) do
    if el.type == "text" and el.text == "Has a subtitle" then titleY[1] = el.frame.y end
    if el.type == "text" and el.text == "No subtitle at all" then titleY[2] = el.frame.y end
    if el.type == "text" and el.text == "the second line" then subY = el.frame.y end
  end
  check("both titles were found among the drawn elements",
    titleY[1] ~= nil and titleY[2] ~= nil)
  -- The space above the title's capitals and the space below the subtitle's baseline are the
  -- same, read from the real metrics the renderer places the frames from, within the one
  -- point two frames may differ by when each is rounded to a whole point.
  local tm = hs.styledtext.fontInfo({ name = TYPE.font, size = TYPE.textSize })
  local sm = hs.styledtext.fontInfo({ name = TYPE.subFont, size = TYPE.subSize })
  local above = titleY[1] + tm.ascender - tm.capHeight
  local below = layout.rowH - (subY + sm.ascender)
  check("a row with a subtitle has the same space above the title's capitals as below the subtitle's baseline",
    math.abs(above - below) <= 1, "above " .. tostring(above) .. " below " .. tostring(below))
  check("the subtitle's baseline sits one caption line below the title's",
    math.abs((subY + sm.ascender) - (titleY[1] + tm.ascender) - layout.subLine) <= 1)
  check("a row with no subtitle centres its title lower than the stacked row's own title sits",
    titleY[2] ~= nil and titleY[2] > titleY[1],
    "centred " .. tostring(titleY[2]) .. " stacked " .. tostring(titleY[1]))
end

do
  -- An empty string subtitle is treated the same as no subtitle at all, matching how
  -- every other read of subTitle in this file already answers "".
  local layout = {
    width = 480, rowH = DERIVED_ROW_H, rowCount = 10, baseH = 94,
    font = TYPE.font, textSize = TYPE.textSize, textLine = TYPE.textLine, subFont = TYPE.subFont, subSize = TYPE.subSize, subLine = TYPE.subLine, numFont = TYPE.numFont, numSize = TYPE.numSize,
  }
  local rows = { row("Empty subtitle", "", 1) }
  local s = model.newState(rows, layout)
  local rect = { x = 0, y = 0, w = layout.width, h = render.bandHeight(layout) }
  local els = render.elements(s, rect, layout, {})
  local sawSubtitleText = false
  for _, el in ipairs(els) do
    if el.type == "text" and el.textSize == layout.subSize and el.text == "" then
      sawSubtitleText = true
    end
  end
  check("an empty subtitle draws no stacked subtitle line at all",
    not sawSubtitleText)
end

--------------------------------------------------------------------------------
-- Round four, the quiet row number behind its own flag
--------------------------------------------------------------------------------

do
  local layout = {
    width = 480, rowH = DERIVED_ROW_H, rowCount = 10, baseH = 94,
    font = TYPE.font, textSize = TYPE.textSize, textLine = TYPE.textLine, subFont = TYPE.subFont, subSize = TYPE.subSize, subLine = TYPE.subLine, numFont = TYPE.numFont, numSize = TYPE.numSize, showRowNumbers = true,
  }
  local s = model.newState(rowSet(12), layout)
  local rect = { x = 0, y = 0, w = layout.width, h = render.bandHeight(layout) }
  local els = render.elements(s, rect, layout, {})

  local numbersSeen = {}
  for _, el in ipairs(els) do
    if el.type == "text" and el.textAlignment == "right" then
      numbersSeen[el.text] = true
    end
  end
  check("the first nine visible rows each draw their own shortcut, the command sign and the digit",
    numbersSeen["\u{2318}1"] and numbersSeen["\u{2318}5"] and numbersSeen["\u{2318}9"])
  check("no shortcut is drawn past the ninth visible row",
    numbersSeen["\u{2318}10"] == nil)
end

do
  local layout = {
    width = 480, rowH = DERIVED_ROW_H, rowCount = 10, baseH = 94,
    font = TYPE.font, textSize = TYPE.textSize, textLine = TYPE.textLine, subFont = TYPE.subFont, subSize = TYPE.subSize, subLine = TYPE.subLine, numFont = TYPE.numFont, numSize = TYPE.numSize, showRowNumbers = false,
  }
  local s = model.newState(rowSet(12), layout)
  local rect = { x = 0, y = 0, w = layout.width, h = render.bandHeight(layout) }
  local els = render.elements(s, rect, layout, {})

  local sawAnyRightAligned = false
  for _, el in ipairs(els) do
    if el.type == "text" and el.textAlignment == "right" then sawAnyRightAligned = true end
  end
  check("showRowNumbers set to false removes the row numbers without touching anything else",
    not sawAnyRightAligned)
end

--------------------------------------------------------------------------------
-- Round five, the clip pair every call to elements now opens and closes with
--------------------------------------------------------------------------------

do
  local layout = {
    width = 480, rowH = DERIVED_ROW_H, rowCount = 10, baseH = 94,
    font = TYPE.font, textSize = TYPE.textSize, textLine = TYPE.textLine, subFont = TYPE.subFont, subSize = TYPE.subSize, subLine = TYPE.subLine, numFont = TYPE.numFont, numSize = TYPE.numSize,
  }
  local s = model.newState(rowSet(3), layout)
  local rect = { x = 5, y = 7, w = layout.width, h = render.bandHeight(layout) }
  local els = render.elements(s, rect, layout, {})

  check("the first element clips the row band to exactly the rect a caller handed in",
    els[1].type == "rectangle" and els[1].action == "clip"
      and els[1].frame.x == rect.x and els[1].frame.y == rect.y
      and els[1].frame.w == rect.w and els[1].frame.h == render.bandHeight(layout),
    "got " .. tostring(els[1].type) .. " " .. tostring(els[1].action))
  check("the last element resets the clip so nothing after this file's own elements is affected",
    els[#els].type == "resetClip", "got " .. tostring(els[#els].type))
end

--------------------------------------------------------------------------------
-- M.rowAtPoint, phase three a part one of this track's build plan, built from
-- docs/BRIEF-CANVAS-GEOMETRY.md. Composes the same visible slot arithmetic
-- geometry.lua answers with the existing M.rowAtVisibleSlot, so a point measured from
-- the top of the row band answers a real filtered index and never a slot the filtered
-- set does not actually hold.
--------------------------------------------------------------------------------

do
  local s = model.newState(rowSet(25), ROWS_10)
  check("a point at the very top of a fresh unscrolled list resolves to the first row",
    model.rowAtPoint(s, 0) == 1, "got " .. tostring(model.rowAtPoint(s, 0)))
  check("a point inside the fifth row resolves to the fifth row",
    model.rowAtPoint(s, 4 * ROW_H + 10) == 5,
    "got " .. tostring(model.rowAtPoint(s, 4 * ROW_H + 10)))
end

do
  -- The partially visible top row round five's own header names, scrolled seventeen
  -- points into a list taller than the viewport. Row one sits seventeen points above
  -- the viewport's own top and still counts as the row a point at the very top of the
  -- band belongs to, and only a point past where its remaining sliver ends resolves to
  -- the row beneath it.
  local s = model.newState(rowSet(25), ROWS_10)
  local scrolled = model.scrollTo(s, 17)
  check("a point at the top of the band lands on the row still partly visible above it",
    model.rowAtPoint(scrolled, 0) == 1, "got " .. tostring(model.rowAtPoint(scrolled, 0)))
  check("a point further into that same partial row still resolves to it",
    model.rowAtPoint(scrolled, 20) == 1, "got " .. tostring(model.rowAtPoint(scrolled, 20)))
  check("a point past where the partial row ends resolves to the row beneath it",
    model.rowAtPoint(scrolled, 25) == 2, "got " .. tostring(model.rowAtPoint(scrolled, 25)))
end

do
  -- A short filtered set, three rows against a ten row viewport, so a point well down
  -- the band falls past the last row the filtered set actually has.
  local s = model.newState(rowSet(3), ROWS_10)
  check("a point below the last row of a short filtered set answers nil rather than a wrong row",
    model.rowAtPoint(s, 5 * ROW_H) == nil, "got " .. tostring(model.rowAtPoint(s, 5 * ROW_H)))
end

--------------------------------------------------------------------------------
-- An icon is drawn at paint, through the injected style.icon
--------------------------------------------------------------------------------

do
  local layout = {
    width = 480, rowH = DERIVED_ROW_H, rowCount = 10, baseH = 94,
    font = TYPE.font, textSize = TYPE.textSize, textLine = TYPE.textLine, subFont = TYPE.subFont, subSize = TYPE.subSize, subLine = TYPE.subLine, numFont = TYPE.numFont, numSize = TYPE.numSize,
  }
  local rows = {
    { title = "named", item = 1, icon = "go", iconOwner = "demo" },
    { title = "pictured", item = 2, image = "real", icon = "go", iconOwner = "demo" },
    { title = "bare", item = 3 },
  }
  local s = model.newState(rows, layout)
  local rect = { x = 0, y = 0, w = layout.width, h = render.bandHeight(layout) }
  local asked = {}
  local colour = "light"
  local style = { icon = function(icon, owner)
    asked[#asked + 1] = icon .. "/" .. tostring(owner)
    return "drawn-" .. colour
  end }
  local function images(els)
    local out = {}
    for _, el in ipairs(els) do
      if el.type == "image" then out[#out + 1] = el.image end
    end
    return out
  end
  local first = images(render.elements(s, rect, layout, style))
  check("a row that names an icon is drawn through style.icon with its owner", first[1] == "drawn-light" and asked[1] == "go/demo")
  check("a row that carries an image keeps it and never asks", first[2] == "real" and #asked == 1)
  check("a row with no icon draws no image", #first == 2)
  colour = "dark"
  local again = images(render.elements(s, rect, layout, style))
  check("the next paint asks again, so a switch of halves redraws the icon", again[1] == "drawn-dark")
  check("without style.icon a row that names an icon draws none",
    #images(render.elements(s, rect, layout, {})) == 1)
end
