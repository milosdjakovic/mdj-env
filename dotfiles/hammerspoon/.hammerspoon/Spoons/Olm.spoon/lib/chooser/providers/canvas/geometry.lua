--- === Canvas geometry ===
---
--- The arithmetic the canvas picker stands on, phase three a part one of this track's
--- build plan and built from docs/BRIEF-CANVAS-GEOMETRY.md. Pure Lua. No hs.canvas, no
--- timer, no drawing, and no hs.screen either, a caller resolves the screen and hands in
--- a frame, which is what keeps every rule here provable offline with nothing but plain
--- tables behind it, the same reasoning list model.lua and field model.lua both already
--- rest on.
---
--- M.DEFAULT_LAYOUT carries the canvas layout the orchestrator settled by hand across
--- five rounds of the canvas list brief, read from Spoons/Olm.spoon/test/probe-canvasfield.lua's
--- own GEOMETRY table rather than chosen fresh here. Those values are the design and this
--- file only carries them, it does not relitigate them. Four more names on this table,
--- gap, paneMaxW, topFrac and minVPad, answer a different question, how the surface sits
--- on the screen rather than how tall a row stands, and neither the geometry brief nor
--- the five rounds of hand judgement behind BRIEF-CANVAS-LIST.md ever redesigned that
--- question for a canvas surface. So this file borrows those four values outright from
--- the native provider's own DEFAULT_LAYOUT rather than inventing a fresh answer nobody
--- asked for, the same vocabulary the geometry brief already asks every field here to
--- share with that module. titleLineBreak travels the same way, native's own default of
--- truncateTail, a question this file never adjudicates.
---
--- M.resolve(screenFrame, layout, paneWidth) answers one table of rectangles, canvas,
--- field, list, chooser, companion and rowCount, every rectangle in absolute screen
--- points, the same space hs.window frames and hs.eventtap event locations already use.
--- The arithmetic mirrors native.lua's own placement functions in shape, a row count
--- trimmed to the screen, a pair centred as one unit, a top biased vertical position
--- clamped between two pads with the top pad winning when the surface cannot keep both,
--- and a companion width resolved from true, a number, or nil, every answer capped at
--- paneMaxW. Nothing here is copied from native.lua's own numbers, only the shape of the
--- reasoning, since the canvas surface's own proportions are its own design.
---
--- M.textBudget(rects, layout) answers the pixel room a row's title has, computed from
--- the layout rather than measured off anything, which is what lets it replace the
--- native provider's own ROW_TEXT_INSET, a constant read off the accessibility tree of a
--- widget this backend does not draw. The trailing allowance this file subtracts is the
--- horizontal pad plus a numeral column exactly layout.iconSize wide, matching the
--- numeral column list render.lua already draws at that same width in its own M.elements,
--- so a title's budget and the space the row number actually occupies never quietly
--- disagree, this file's own header names that agreement so a later change to one is a
--- prompt to check the other.
---
--- M.rowAtPoint(point, rects, layout, scrollTop) answers a slot in the VISIBLE band, one
--- based, counting from whatever row currently sits topmost in the viewport, and the
--- point's own offset within that row in points, or nil when the point falls outside the
--- list rect. This is not an index into a filtered set, since this file is never told how
--- many rows a filtered set actually holds, it only knows the geometry of a viewport that
--- could in principle hold rows forever. The arithmetic takes the point's own offset from
--- the list rect's own top, adds only the SUB ROW remainder of scrollTop, scrollTop
--- modulo the row height, divides by the row height and floors, then adds one. Using the
--- remainder rather than the whole of scrollTop is the one detail worth naming plainly,
--- since the whole of scrollTop would answer an absolute row number that has already
--- travelled past however many rows are scrolled out of view above the top of the
--- viewport, which reads as correct at the top of a freshly opened list and silently
--- wrong the moment anything has scrolled, exactly the kind of number that looks right in
--- the one case a person tries by hand and wrong in every other. The remainder alone
--- answers where a point sits relative to whichever row is currently first on screen,
--- which is the only question this file can answer without knowing the filtered set's own
--- size, and the caller turns this visible slot into a real filtered index through
--- list/model.lua's own M.rowAtPoint, which composes this arithmetic with the existing
--- M.rowAtVisibleSlot, the one place that does know how many rows the filtered set holds.
--- Confusing the two, treating this file's own slot as if it already were the filtered
--- index, is the exact off by one that separation exists to prevent.
---
--- Truncation, section two of the brief, measured before anything here was written
--- rather than assumed. An hs.canvas text element was rendered offscreen twice, once
--- handed a plain Lua string and once handed an hs.styledtext value built the same way
--- native.lua's own styledText function at its line one hundred fifty five builds one,
--- carrying a paragraphStyle of lineBreak truncateTail, both into the same narrow frame
--- holding a string far too long to fit. The canvas was never shown, hs.canvas.new plus
--- imageFromCanvas rasterizes without a window ever appearing, and the two images were
--- saved to a scratch PNG and looked at directly. The plain string was cut off hard with
--- no ellipsis at all, the last visible word sheared in the middle of a letter. The
--- styled text carrying truncateTail read out in full up to a single trailing ellipsis
--- exactly where the frame ran out of room, indistinguishable from what any ordinary
--- macOS text field does. truncateMiddle was measured the same way straight after and
--- read correctly too, an ellipsis in the middle of the string with both ends intact. So
--- the paragraph style IS honoured by an hs.canvas text element, truncation is free, this
--- configuration already carries the code for it in native.lua's own styledText, and this
--- file delivers no truncate.lua, exactly the outcome the brief asked to be verified
--- before anything was built rather than assumed. The element key carrying the styled
--- value is the ordinary text key every element in list/render.lua already uses, an
--- hs.styledtext value is simply accepted wherever a plain string would be.

local M = {}

-- The shared row height rule, lib/chooser/rowheight.lua, which the native provider reads too.
local rowHeight = (function()
  local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or ""
  local chunk, err = loadfile(here .. "../../rowheight.lua")
  if not chunk then error("Canvas geometry failed to load rowheight.lua, " .. tostring(err)) end
  return chunk()
end)()

-- Stage two of docs/DESIGN-UI-KIT.md made this table the one canvas layout source. The list
-- renderer used to carry a disagreeing copy of its own and now reads this one, and the
-- native provider keeps its own because the system draws its rows. The type, the font and
-- the two text sizes this table used to carry left it then for the UI kit's tokens, the
-- title and sub variants, which hold the same values, so the provider hands the renderers
-- one font and one pair of sizes rather than two copies that could drift. caretWidth joined
-- it from field render's own literal, the one piece of field geometry that had no home.
M.DEFAULT_LAYOUT = {
  -- Settled by hand across five rounds, read from Spoons/Olm.spoon/test/probe-canvasfield.lua's
  -- own GEOMETRY table. Not this file's own design, this file only carries it.
  -- The list is as wide as the side pane beside it, asked for on 2026 10 14, so the two read
  -- as one surface. paneMaxW below follows this one value rather than repeating it.
  width = 480,
  -- rowH and baseH come from the one row height rule over the body and caption line heights,
  -- and the provider recomputes them from the kit's tokens so a size set in
  -- config/typography.toml reflows them. The two numbers here are that same rule applied to
  -- the shipped sizes, a body line of 22 and a caption line of 19, for a caller that has no
  -- kit, a unit case among them. rowPad is the one vertical padding value.
  rowPad = rowHeight.PAD,
  baseH = 22 + 2 * rowHeight.PAD,
  rowH = 22 + 19 + 2 * rowHeight.PAD,
  rowCount = 9,
  padX = 16,
  iconSize = 28,
  iconGap = 10,
  edgeMargin = 12,
  showRowNumbers = true,
  caretWidth = 2,
  -- Borrowed outright from native.lua's own DEFAULT_LAYOUT, a placement question the
  -- five rounds behind BRIEF-CANVAS-LIST.md never redesigned. Named here so this file's
  -- own header can say plainly that this is a borrow rather than a fresh design.
  gap = 12,
  topFrac = 0.06,
  minVPad = 60,
  titleLineBreak = "truncateTail",
}
M.DEFAULT_LAYOUT.paneMaxW = M.DEFAULT_LAYOUT.width

--- M.derivedRows(text, pad) -> { rowH, baseH, pad }, the row height rule over the kit's
--- tokens.text, see lib/chooser/rowheight.lua.
function M.derivedRows(text, pad)
  return rowHeight.heights(text, pad)
end

--------------------------------------------------------------------------------
-- M.resolve, the whole surface's own placement
--------------------------------------------------------------------------------

-- Trims the requested row count to what the screen can actually hold, the screen
-- height less twice the minimum vertical padding, less the field height and the edge
-- margin twice, divided by the row height, floored, and never more than what layout
-- itself asked for. Bounded at zero rather than left negative on a screen too short to
-- hold even the field, the same answer something sane rather than raising posture every
-- other file in this provider already keeps.
local function trimmedRowCount(screenFrame, layout)
  local avail = screenFrame.h - 2 * layout.minVPad - layout.baseH - 2 * layout.edgeMargin
  local fit = math.floor(avail / layout.rowH)
  return math.max(0, math.min(layout.rowCount, fit))
end

-- Resolves paneWidth into a companion width in points for this call, or zero for no
-- companion. true inherits canvasWidth, a number overrides it independently, nil or
-- zero or a negative number all mean no companion, and every answer is capped at
-- layout.paneMaxW, mirroring native.lua's own _resolveCompanionWidth in shape though not
-- in the numbers it resolves against.
local function resolveCompanionWidth(paneWidth, canvasWidth, layout)
  local w = paneWidth
  if w == true then w = canvasWidth end
  if type(w) ~= "number" or w <= 0 then return 0 end
  return math.min(w, layout.paneMaxW)
end

-- The vertical position, the top fraction down from the top of the screen, clamped
-- never closer than the minimum padding to either edge, with the top pad winning when
-- the surface is too tall to keep both, mirroring native.lua's own _topBiasedY.
local function topBiasedY(screenFrame, layout, canvasHeight)
  local lo = screenFrame.y + layout.minVPad
  local hi = screenFrame.y + screenFrame.h - layout.minVPad - canvasHeight
  if hi < lo then return lo end
  local wanted = screenFrame.y + math.floor(screenFrame.h * layout.topFrac)
  if wanted < lo then return lo end
  if wanted > hi then return hi end
  return wanted
end

--- M.resolve(screenFrame, layout, paneWidth) answers one table of rectangles, all in
--- absolute screen points. layout falls back to M.DEFAULT_LAYOUT when nil.
function M.resolve(screenFrame, layout, paneWidth)
  layout = layout or M.DEFAULT_LAYOUT

  local rowCount = trimmedRowCount(screenFrame, layout)
  local canvasW = layout.width
  local canvasH = 2 * layout.edgeMargin + layout.baseH + rowCount * layout.rowH

  local companionW = resolveCompanionWidth(paneWidth, canvasW, layout)
  local total = canvasW + (companionW > 0 and (layout.gap + companionW) or 0)
  local x = screenFrame.x + math.floor((screenFrame.w - total) / 2)
  local y = topBiasedY(screenFrame, layout, canvasH)

  local canvasRect = { x = x, y = y, w = canvasW, h = canvasH }

  local fieldRect = {
    x = x + layout.edgeMargin, y = y + layout.edgeMargin,
    w = canvasW - 2 * layout.edgeMargin, h = layout.baseH,
  }
  local listRect = {
    x = x + layout.edgeMargin, y = y + layout.edgeMargin + layout.baseH,
    w = canvasW - 2 * layout.edgeMargin, h = rowCount * layout.rowH,
  }

  local companionRect = nil
  if companionW > 0 then
    companionRect = { x = x + canvasW + layout.gap, y = y, w = companionW, h = canvasH }
  end

  return {
    canvas = canvasRect,
    field = fieldRect,
    list = listRect,
    chooser = canvasRect,
    companion = companionRect,
    rowCount = rowCount,
  }
end

--------------------------------------------------------------------------------
-- M.textBudget, replacing native.lua's own measured ROW_TEXT_INSET
--------------------------------------------------------------------------------

--- M.textBudget(rects, layout) answers the pixel room a row's title has, the list
--- rect's own width less the leading pad, the icon and its gap, less the trailing pad
--- and a numeral column exactly layout.iconSize wide, matching list/render.lua's own
--- numeral column width. Computed from the layout, never from a measurement.
function M.textBudget(rects, layout)
  layout = layout or M.DEFAULT_LAYOUT
  local listRect = rects and rects.list
  if not listRect then return 0 end
  local numeralColumnWidth = layout.iconSize
  local budget = listRect.w - layout.padX - layout.iconSize - layout.iconGap
    - layout.padX - numeralColumnWidth
  return math.max(0, budget)
end

--------------------------------------------------------------------------------
-- M.rowAtPoint, a slot in the visible band, not a filtered index
--------------------------------------------------------------------------------

--- M.rowAtPoint(point, rects, layout, scrollTop) answers a visible slot number, one
--- based from whatever row currently sits topmost on screen, and the point's own offset
--- within that row in points, or nil when the point falls outside the list rect,
--- including a point sitting in the field rect instead. This is a slot in the VISIBLE
--- band, not an index into a filtered set, this file has no idea how many rows a
--- filtered set holds. The caller turns one into the other through list/model.lua's own
--- M.rowAtPoint, which composes this same arithmetic with the existing
--- M.rowAtVisibleSlot.
function M.rowAtPoint(point, rects, layout, scrollTop)
  layout = layout or M.DEFAULT_LAYOUT
  local listRect = rects and rects.list
  if not listRect or not layout.rowH or layout.rowH <= 0 then return nil end
  if point.x < listRect.x or point.x >= listRect.x + listRect.w then return nil end
  if point.y < listRect.y or point.y >= listRect.y + listRect.h then return nil end

  local rowH = layout.rowH
  local localY = point.y - listRect.y
  local remainder = (scrollTop or 0) % rowH
  local raw = (localY + remainder) / rowH
  local slot = math.floor(raw) + 1
  local offsetInRow = (raw - math.floor(raw)) * rowH
  return slot, offsetInRow
end

return M
