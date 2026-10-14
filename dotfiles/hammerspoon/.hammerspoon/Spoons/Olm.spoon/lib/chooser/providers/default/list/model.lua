--- === Canvas list model ===
---
--- The pure core of the canvas row list, phase three a of this track's build plan and
--- built from the canvas list brief. Rows go in, a query goes in, and out comes the
--- filtered and ranked set, the highlighted index, and the scroll offset. Nothing here
--- touches hs, a timer, or a canvas, so this file is provable offline with nothing but
--- plain Lua tables behind it, the same reasoning that split field model.lua away from
--- the event tap around it.
---
--- A row is the shape lib/chooser/providers/legacy.lua already documents at its own
--- head, title, subTitle, image, enabled, item and filterText. A row this file can rank
--- must be a row the native provider could have drawn, so a future picker built on this
--- list needs no translation between the two and no consumer ever learns which backend
--- answered a given row.
---
--- Filtering reuses lib/chooser/match.lua rather than reimplementing any matching rule
--- of its own, loaded by path exactly the way field input.lua loads its own siblings.
--- The fuzzy strategy in that file is the one every list in this configuration ranks
--- with today, and this file asks for nothing else, since a difference in what ranks
--- first would read as this backend being worse when it would only be different. The
--- haystack a row is searched on is its own filterText when it carries one, otherwise
--- its title and subTitle joined with a space, matching haystackOf in the native
--- provider, restated here rather than imported since it is one line of string
--- concatenation and not a matching rule the brief asks this file to reuse.
---
--- State is a plain table, rows, query, filtered, highlight, scrollTop, rowH,
--- visibleCount. rows is exactly what the caller supplied, kept so a later setQuery can
--- rerank the same set without the caller handing rows over again. filtered is the
--- ranked survivors of the current query, in the order they are drawn. highlight is a
--- one based index into filtered, or nil when filtered is empty, an empty set having no
--- highlight at all rather than a highlight pointing at nothing. rowH is the height of
--- one row in points, read once from a layout table's own rowH field on construction, the
--- same field name lib/chooser/providers/legacy.lua's DEFAULT_LAYOUT already carries.
--- visibleCount is how many whole rows the viewport nominally holds at once, read once
--- from that same layout table's rowCount field, so the viewport's own height in points is
--- always rowH times visibleCount and never a number carried separately that could drift
--- from those two.
---
--- scrollTop is a point offset from the top of the filtered set to the top of the
--- viewport, not a row index. This is round five's own replacement for what scrollTop
--- used to be, a whole row the viewport started drawing from, and the change is what
--- lets the viewport sit between two rows rather than only ever on a row's own boundary,
--- which is the whole of what makes a trackpad's continuous scroll read as smooth
--- instead of as a series of jumps. A scrollTop that is not a multiple of rowH means the
--- row at the top of the viewport, and the row at its bottom, are only partly shown, and
--- drawing that partial row correctly is render.lua's own job through hs.canvas's clip
--- action, this file only ever answers where every row sits relative to the viewport,
--- never how much of it should be visible.
---
--- Keeping the highlight visible and following the wheel are two different questions
--- with two different answers, and keeping them apart is the one design decision this
--- round actually rests on. moveDown, moveUp, newState and setQuery all move or seed the
--- highlight, and every one of them recomputes scrollTop afterward so the highlighted
--- row is never left outside the viewport, moving it only when the highlight is not
--- fully inside and then only far enough to show it, which keeps the keyboard's own
--- movement instant and free of any animation, and leaves a partly cut row where it was. scrollTo and scrollBy do the opposite, they move scrollTop on their own
--- and never touch highlight at all, which is what a wheel or a trackpad drives, and
--- normalizeState, the function every one of these opens by calling, only ever bounds
--- whatever scrollTop it was handed into the range the filtered set can support, it does
--- not pull scrollTop back toward the highlight. A version of this file that let
--- normalizeState anchor scrollTop to the highlight again on every call, the way the row
--- index era of this file used to, would undo a wheel scroll the very next time anything
--- read the state at all, since nearly every function here opens by normalizing, and
--- that is precisely the bug this design avoids rather than one it happens not to have
--- hit yet.
---
--- Every operation below takes a state and answers a new one rather than mutating the
--- one it was given, and every operation clamps whatever it is handed rather than
--- refusing it, the same discipline field model.lua's own header states and for the same
--- reason, a caller may hand this file a state that drifted since the last call and this
--- file would rather answer something sane than stop the list working.

local M = {}

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")

-- lib/chooser/match.lua sits three directories above this file, list up to canvas up to
-- providers up to chooser, where the real matcher lives beside the atom every other
-- chooser in this configuration already ranks through.
local MATCH_PATH = spoonPath .. "../../../match.lua"

local function loadMatch()
  local chunk, err = loadfile(MATCH_PATH)
  if not chunk then
    error("Canvas list model, failed to load match.lua, " .. tostring(err))
  end
  return chunk()
end

local match = loadMatch()

-- The visible row count a state falls back to when a caller passes no layout at all, or
-- a layout naming no rowCount of its own, ten, matching DEFAULT_LAYOUT.rowCount in the
-- native provider, so a state built with no layout still moves and scrolls the way the
-- real chooser does. DEFAULT_ROW_H is the matching fallback for rowH, agreeing with
-- render.lua's own DEFAULT_LAYOUT.rowH so a state and the elements drawn for it never
-- quietly disagree about how tall a row stands when a caller leans on both files'
-- defaults at once.
local DEFAULT_VISIBLE_COUNT = 10
local DEFAULT_ROW_H = 42

--------------------------------------------------------------------------------
-- The haystack a row is searched on, decision two of the brief
--------------------------------------------------------------------------------

local function haystackOf(row)
  return row.filterText or ((row.title or "") .. " " .. (row.subTitle or ""))
end

-- Ranks rows against a query through match.fuzzy, the one matcher this file asks for,
-- and answers a fresh array of the surviving rows in the order they should draw. An
-- empty query answers every row in its original order, matching what the native
-- provider's own _build does when a matcher is set but the query is empty, no filtering
-- and no reordering, so a list opened with nothing typed yet shows exactly what it was
-- handed. A non empty query scores every row, drops the ones match.fuzzy answers nil
-- for, and sorts survivors by score, the original position breaking a tie, so a stable
-- order upstream of this file, a supplier's own recency for one example, still shows
-- through the ranking exactly the way the native provider preserves it today.
local function rankRows(rows, query)
  if query == "" then
    local out = {}
    for i = 1, #rows do out[i] = rows[i] end
    return out
  end
  local ranked = {}
  for i = 1, #rows do
    local score = match.fuzzy(query, haystackOf(rows[i]))
    if score ~= nil then
      ranked[#ranked + 1] = { row = rows[i], score = score, idx = i }
    end
  end
  table.sort(ranked, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.idx < b.idx
  end)
  local out = {}
  for i = 1, #ranked do out[i] = ranked[i].row end
  return out
end

--------------------------------------------------------------------------------
-- State construction and the total, never raising normalize every operation opens with
--------------------------------------------------------------------------------

local function newRawState(rows, query, filtered, highlight, scrollTop, rowH, visibleCount)
  return {
    rows = rows, query = query, filtered = filtered, highlight = highlight,
    scrollTop = scrollTop, rowH = rowH, visibleCount = visibleCount,
  }
end

-- The one place total content height and viewport height are turned into a bound for
-- scrollTop, so every function below that needs that bound asks this rather than
-- restating the same multiplication and subtraction, which is exactly the drift round
-- two of this track's build plan already found once when a caller and render.lua each
-- multiplied rowCount by rowH on their own.
local function maxScrollFor(total, rowH, visibleCount)
  return math.max(0, total * rowH - rowH * visibleCount)
end

-- Bounds a scrollTop into the range the filtered set can support, no more and no less.
-- This is the general purpose clamp, used by normalizeState for whatever a caller handed
-- in and by scrollTo for wherever a wheel or a trackpad asked the viewport to sit, and it
-- answers zero at both ends rather than letting the viewport travel past either edge of
-- the list, which is the bounded and never rubber banding behaviour round five asks for.
local function boundScroll(scrollTop, total, rowH, visibleCount)
  local maxScroll = maxScrollFor(total, rowH, visibleCount)
  if scrollTop < 0 then scrollTop = 0 end
  if scrollTop > maxScroll then scrollTop = maxScroll end
  return scrollTop
end

-- Moves scrollTop only when the highlighted row is not fully inside the viewport, and
-- then only far enough to show that row fully at the edge it crossed, never past either
-- end of the list. A highlight already fully visible leaves scrollTop exactly as it was,
-- fractional or not, so a partly cut row at the top stays cut while the keyboard moves
-- among the rows below it, and a wheel that stopped between two rows is not snapped by
-- the next key. A wrap moves the highlight far outside the viewport and falls out of the
-- same rule, the viewport lands on that row.
local function scrollToShowHighlight(highlight, scrollTop, total, rowH, visibleCount)
  if total == 0 then return 0 end
  if highlight then
    local viewportH = rowH * visibleCount
    local topOf = (highlight - 1) * rowH
    local bottomOf = topOf + rowH
    if topOf < scrollTop then scrollTop = topOf end
    if bottomOf > scrollTop + viewportH then scrollTop = bottomOf - viewportH end
  end
  return boundScroll(scrollTop, total, rowH, visibleCount)
end

-- Every operation below opens by asking for this, so a state built by hand, seeded from
-- outside, or drifted by a caller between calls always arrives with a highlight that
-- agrees with the filtered set actually sitting in the state, and a scrollTop that at
-- least sits inside the range that set can support. It does not pull scrollTop toward
-- the highlight the way the row index era of this file once did, and the header above
-- explains why, that would undo a wheel or a trackpad's own scroll the next time
-- anything merely read the state rather than moved it. rows and filtered default to an
-- empty list rather than nil, and query to the empty string, so a table missing a field
-- entirely still normalizes to something this file can read safely.
local function normalizeState(rawState)
  local rows = (rawState and rawState.rows) or {}
  local query = (rawState and rawState.query) or ""
  local filtered = (rawState and rawState.filtered) or {}
  local visibleCount = (rawState and rawState.visibleCount) or DEFAULT_VISIBLE_COUNT
  local rowH = (rawState and rawState.rowH) or DEFAULT_ROW_H
  local total = #filtered
  local highlight = rawState and rawState.highlight
  if total == 0 then
    highlight = nil
  elseif highlight == nil then
    highlight = 1
  else
    if highlight < 1 then highlight = 1 end
    if highlight > total then highlight = total end
  end
  local scrollTop = (rawState and rawState.scrollTop) or 0
  scrollTop = boundScroll(scrollTop, total, rowH, visibleCount)
  return newRawState(rows, query, filtered, highlight, scrollTop, rowH, visibleCount)
end

--------------------------------------------------------------------------------
-- Public surface
--------------------------------------------------------------------------------

M.normalized = normalizeState
M.DEFAULT_VISIBLE_COUNT = DEFAULT_VISIBLE_COUNT
M.DEFAULT_ROW_H = DEFAULT_ROW_H

--- M.newState(rows, layout, query) answers a fresh state for a whole supplied row set.
--- layout is read once for its rowCount and rowH fields, the same field names the canvas
--- list brief and render.lua both use, and falls back to DEFAULT_VISIBLE_COUNT and
--- DEFAULT_ROW_H when layout is nil or names neither field of its own. query seeds the
--- initial filter, defaulting to the empty string, an untyped list showing every row it
--- was handed in the order it arrived, scrolled to its own top.
function M.newState(rows, layout, query)
  rows = rows or {}
  query = query or ""
  local visibleCount = (layout and layout.rowCount) or DEFAULT_VISIBLE_COUNT
  local rowH = (layout and layout.rowH) or DEFAULT_ROW_H
  local filtered = rankRows(rows, query)
  local highlight = (#filtered > 0) and 1 or nil
  local scrollTop = scrollToShowHighlight(highlight, 0, #filtered, rowH, visibleCount)
  return newRawState(rows, query, filtered, highlight, scrollTop, rowH, visibleCount)
end

--- M.setQuery(state, query) reranks the same rows the state already holds against a new
--- query, matching how a real chooser resets to the top of a freshly built list rather
--- than trying to hold a highlight over a row that may not even survive the new filter.
--- The state's own rows, rowH and visibleCount travel through unchanged, only what the
--- query touches is answered fresh.
function M.setQuery(rawState, query)
  local ns = normalizeState(rawState)
  query = query or ""
  local filtered = rankRows(ns.rows, query)
  local highlight = (#filtered > 0) and 1 or nil
  local scrollTop = scrollToShowHighlight(highlight, 0, #filtered, ns.rowH, ns.visibleCount)
  return newRawState(ns.rows, query, filtered, highlight, scrollTop, ns.rowH, ns.visibleCount)
end

--- M.moveDown(state) and M.moveUp(state), one function per movement as the brief asks,
--- step the highlight by exactly one row and answer the state unchanged when filtered is
--- empty, which is the total never raising the brief's acceptance section asks for. The
--- highlight wraps at either end, decision five of the original brief, so a movement key
--- held down never dead ends against the top or the bottom of the list, moving down from
--- the last row lands on the first and moving up from the first lands on the last.
--- scrollTop is recomputed afterward through scrollToShowHighlight, so the keyboard's own
--- movement always leaves the highlight fully visible and always lands on a row
--- boundary, with no animation, which is round five's own answer for why the keyboard
--- and the wheel are allowed to feel different. A disabled row is still a row the
--- highlight may sit on, only choosing one is refused, and choosing is a question this
--- file leaves to whatever reads M.highlightedRow, since this file only ever moves a
--- position and never decides what a row means.
function M.moveDown(rawState)
  local ns = normalizeState(rawState)
  local total = #ns.filtered
  if total == 0 then
    return newRawState(ns.rows, ns.query, ns.filtered, nil, ns.scrollTop, ns.rowH, ns.visibleCount)
  end
  local highlight = ns.highlight + 1
  if highlight > total then highlight = 1 end
  local scrollTop = scrollToShowHighlight(highlight, ns.scrollTop, total, ns.rowH, ns.visibleCount)
  return newRawState(ns.rows, ns.query, ns.filtered, highlight, scrollTop, ns.rowH, ns.visibleCount)
end

function M.moveUp(rawState)
  local ns = normalizeState(rawState)
  local total = #ns.filtered
  if total == 0 then
    return newRawState(ns.rows, ns.query, ns.filtered, nil, ns.scrollTop, ns.rowH, ns.visibleCount)
  end
  local highlight = ns.highlight - 1
  if highlight < 1 then highlight = total end
  local scrollTop = scrollToShowHighlight(highlight, ns.scrollTop, total, ns.rowH, ns.visibleCount)
  return newRawState(ns.rows, ns.query, ns.filtered, highlight, scrollTop, ns.rowH, ns.visibleCount)
end

--- M.scrollTo(state, points) sets scrollTop to an absolute point offset, bounded to the
--- range the filtered set can support and never touching highlight at all. This is what
--- a wheel or a trackpad drives, decision four of the original brief being replaced by
--- round five, the viewport moves and the highlight stays exactly where it was, since
--- scrolling is looking while the highlight is choosing, and the header above names why
--- normalizeState is never allowed to undo what this function did. points need not be a
--- multiple of rowH, a viewport sitting between two rows on purpose is what round five
--- asks for, and render.lua's own clip action is what draws that correctly.
function M.scrollTo(rawState, points)
  local ns = normalizeState(rawState)
  local total = #ns.filtered
  local scrollTop = boundScroll(points or 0, total, ns.rowH, ns.visibleCount)
  return newRawState(ns.rows, ns.query, ns.filtered, ns.highlight, scrollTop, ns.rowH, ns.visibleCount)
end

--- M.scrollBy(state, delta) moves scrollTop by a relative number of points, bounded the
--- same way M.scrollTo bounds an absolute one. A trackpad's own continuous point deltas
--- are handed straight to this function, which is what gives macOS's own momentum tail
--- its effect for free, nothing here has to simulate it.
function M.scrollBy(rawState, delta)
  local ns = normalizeState(rawState)
  return M.scrollTo(ns, ns.scrollTop + (delta or 0))
end

--- M.maxScrollTop(state) answers the largest point offset scrollTop can ever sit at for
--- the state's own filtered set, rowH and visibleCount. A caller easing a coarse wheel
--- step toward a target asks this so the target it is easing toward never sits further
--- than the list can actually scroll, which is what keeps that easing from taking a
--- visible moment to unwind an overshoot it was never going to be allowed to show.
function M.maxScrollTop(rawState)
  local ns = normalizeState(rawState)
  return maxScrollFor(#ns.filtered, ns.rowH, ns.visibleCount)
end

--- M.highlightedRow(state) answers the row currently highlighted, or nil when filtered
--- is empty, the one place a caller should ask what is under the highlight rather than
--- reading state.filtered[state.highlight] by hand, so the empty case is answered
--- correctly wherever this file's own answer to it ever changes.
function M.highlightedRow(rawState)
  local ns = normalizeState(rawState)
  if not ns.highlight then return nil end
  return ns.filtered[ns.highlight]
end

--- M.visibleRows(state) answers every row whose own band overlaps the viewport at all,
--- in draw order, each entry carrying the filtered index it sits at and top, the row's
--- own offset in points from the top of the viewport. top is negative for a row that
--- started scrolling off above the viewport, and a row's own top plus rowH can run past
--- the viewport's own height for a row still scrolling in at the bottom, both of which
--- are exactly the partial rows round five's own clipping exists to cut, this file only
--- ever answers where a row sits, never how much of it a renderer is allowed to show.
--- Answers fewer entries than the viewport could hold once the filtered set itself runs
--- out before the viewport does, rather than padding the list with rows that do not
--- exist.
function M.visibleRows(rawState)
  local ns = normalizeState(rawState)
  local total = #ns.filtered
  if total == 0 or ns.rowH <= 0 then return {} end
  local viewportH = ns.rowH * ns.visibleCount
  local firstIndex = math.floor(ns.scrollTop / ns.rowH) + 1
  if firstIndex < 1 then firstIndex = 1 end
  local out = {}
  local index = firstIndex
  while index <= total do
    local rowTop = (index - 1) * ns.rowH
    local top = rowTop - ns.scrollTop
    if top >= viewportH then break end
    out[#out + 1] = { row = ns.filtered[index], index = index, top = top }
    index = index + 1
  end
  return out
end

--- M.rowAtVisibleSlot(state, slot) answers the row and its filtered index sitting at the
--- given position in M.visibleRows, counted from whatever the viewport currently shows,
--- slot 1 being the topmost row on screen whether it is drawn whole or only partly, and
--- answers nil when the viewport does not currently hold that many rows. This is decision
--- four of round four of the brief answered as one function rather than as two places
--- that could drift, cmd plus a digit resolving to a row and this same list numbering its
--- own first nine visible rows both read this same ordering, so there is one answer to
--- which row a given digit means rather than a renderer's own count and a caller's own
--- count that might quietly stop agreeing.
function M.rowAtVisibleSlot(rawState, slot)
  local visible = M.visibleRows(rawState)
  local entry = visible[slot]
  if not entry then return nil, nil end
  return entry.row, entry.index
end

--- M.rowAtPoint(state, yOffsetIntoBand) answers the index into the filtered set for a
--- point that many points below the top of the row band, or nil when it falls past the
--- last row, phase three a part one of this track's build plan, built from
--- docs/BRIEF-CANVAS-GEOMETRY.md. yOffsetIntoBand is already local to the row band's own
--- top, a caller with a raw screen point subtracts the list rect's own top first, the
--- same subtraction geometry.lua's own M.rowAtPoint takes.
---
--- This is the composition the brief asks for, the same arithmetic geometry.lua answers
--- a visible slot with, scrollTop's own SUB ROW remainder added to the offset and
--- divided by the row height, floored and one added, fed straight into this file's own
--- M.rowAtVisibleSlot rather than turned into a filtered index by hand. That second step
--- is why this function lives here and not in geometry.lua, only this file knows how
--- many rows the filtered set actually has, and rowAtVisibleSlot already answers nil
--- past the end of it rather than a wrong row, the exact answer a point below the last
--- row needs.
function M.rowAtPoint(rawState, yOffsetIntoBand)
  local ns = normalizeState(rawState)
  if ns.rowH <= 0 then return nil end
  local remainder = ns.scrollTop % ns.rowH
  local raw = (yOffsetIntoBand + remainder) / ns.rowH
  local slot = math.floor(raw) + 1
  if slot < 1 then return nil end
  local _, index = M.rowAtVisibleSlot(ns, slot)
  return index
end

return M
