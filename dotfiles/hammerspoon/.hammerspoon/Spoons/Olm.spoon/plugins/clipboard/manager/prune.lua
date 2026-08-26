--- Manage history, the age based bulk delete.
---
--- The picker's second page. Normally the clipboard chooser lists history, and while this page
--- is on it lists a small set of rows that each delete a slice of that history by age instead.
--- It is a page rather than a second chooser because the atom already carries the pair a drill
--- down needs, intercept to act on a row without closing the list and back to step out again
--- on Backspace, which is how the launcher hosts somebody else's list. Reusing it means every
--- key the clipboard context binds stays live while the page is open, and the preview pane is
--- still there to show what a row would actually take.
---
--- This file is pure Lua over the store. It reads history, counts what a slice would take, and
--- hands rows back as plain data carrying a glyph STRING rather than an image, so every canvas
--- call stays in the ui and this stays loadable, and testable, with no Hammerspoon at all.
---
--- What a field holds is either a duration or a count, and the count came second because a plain
--- number was the one thing a person typed here that meant nothing. A bare 100 now reads as a
--- hundred entries, offering the same two directions a span does, so trimming history to the
--- newest hundred is the count shaped twin of deleting everything older than a week. A trailing
--- run of digits AFTER a unit is still a value being typed rather than a count, so 4d1 keeps
--- reading as a half typed span on its way to 4d12h.
---
--- The one thing it decides on its own is what a duration means. The units are w, d, h and m,
--- m being minutes exactly as the keep awake field reads it, written in any order and summed,
--- so 4d12h and 12h4d are the same span and 4d4d is eight days rather than an error. There is
--- no year and no month unit. A clipboard history reaches a month or two at the very most and
--- 4w already says that, so y and mo are refused rather than guessed at, since a guess between
--- minutes and months is the one mistake here that cannot be taken back.

local P = {}

local store = nil -- injected, the history this page reads and deletes from

local UNIT_SECS = { m = 60, h = 3600, d = 86400, w = 604800 }

-- Descending, since a span is read back in this order however it was typed.
local UNIT_ORDER = { { "w", 604800 }, { "d", 86400 }, { "h", 3600 }, { "m", 60 } }

-- The ladder an empty field offers, the recent window the browsers all use, where clearing the
-- last hour means what was copied in the last hour goes and everything older stays. It is data
-- rather than code so changing the rungs is one edit and nothing else has to agree.
local PRESETS = {
  { secs = 3600, title = "Last hour" },
  { secs = 12 * 3600, title = "Last 12 hours" },
  { secs = 24 * 3600, title = "Last 24 hours" },
  { secs = 2 * 86400, title = "Last 2 days" },
  { secs = 7 * 86400, title = "Last 7 days" },
}

-- Both shapes, since the field takes either and a person who typed one may not know the other is
-- there. Units first because they are the less guessable half.
local EXAMPLES = "90m, 4d12h, 3w2d in any order, or a plain 100 for a count"

-- What the pane lists at most, so a slice holding hundreds of entries still builds one bounded
-- block of text rather than a wall the pane has to measure and clip.
local PREVIEW_ROWS = 30

--------------------------------------------------------------------------------
-- The duration grammar
--------------------------------------------------------------------------------

--- P.parse(q) -> value, or nil and a status.
--- A value is one of two shapes, { secs = n } for a duration and { count = n } for a number of
--- entries, so a caller reads which it got by asking which field is there rather than by being
--- told a kind twice. The status says what a field holding no value is doing, "empty" for nothing
--- typed, "incomplete" for a span still forming, meaning a trailing number whose unit has not
--- been typed yet, and "bad" for anything else. The rows turn the middle one into a keep typing
--- hint and the last into an error row, both disabled, which is what keeps Return from ever
--- applying a half typed value.
---
--- The whole field being digits is a count. A run of digits at the END of something that already
--- carries a unit is not, it is a span mid keystroke, which is the one place these two readings
--- could have collided and the reason the count is only ever read from the whole field.
function P.parse(q)
  q = tostring(q or ""):gsub("%s+", ""):lower()
  if q == "" then return nil, "empty" end

  local bare = q:match("^%d+$")
  if bare then
    local n = tonumber(bare)
    if n < 1 then return nil, "bad" end
    return { count = n }
  end

  local total, pos = 0, 1
  while pos <= #q do
    local num, unit, nextPos = q:match("^(%d+)(%a)()", pos)
    if not num then
      -- Digits with no unit yet, so the span is still being typed rather than wrong.
      if q:sub(pos):match("^%d+$") then return nil, "incomplete" end
      return nil, "bad"
    end
    local secs = UNIT_SECS[unit]
    if not secs then return nil, "bad" end
    total = total + tonumber(num) * secs
    pos = nextPos
  end
  if total <= 0 then return nil, "bad" end
  return { secs = total }
end

--- P.label(secs) -> a compact descending label, 1w 4d 12h 30m, dropping the zero parts, so a
--- span typed in any order reads back in one canonical shape.
function P.label(secs)
  local parts, left = {}, secs
  for _, u in ipairs(UNIT_ORDER) do
    local n = math.floor(left / u[2])
    if n > 0 then
      parts[#parts + 1] = n .. u[1]
      left = left - n * u[2]
    end
  end
  if #parts == 0 then return "0m" end
  return table.concat(parts, " ")
end

--------------------------------------------------------------------------------
-- What a row would take
--------------------------------------------------------------------------------

-- One rule per row, as a predicate over an entry and its position in history, newest first.
-- Built in a single place and used both to count for the row and to delete when the row is
-- chosen, so the number a person read and the number that actually goes can never come from two
-- different readings of the same value.
--
-- The position is what a count row needs and a span row ignores. A count is about where the line
-- falls in the list and a span about where it falls in time, and both are the same question
-- asked of a different axis, which is why one predicate shape answers for both rather than the
-- count growing a deletion path of its own.
--
-- A span's cutoff is resolved when this is called rather than carried on the row, so both the
-- count and the delete measure from the moment they run. A pause between reading a row and
-- pressing Return therefore moves the boundary a little, which is inherent to a window named
-- relative to now, and is why the message afterwards reports the store's own count rather than
-- the row's. A count has no such drift, since nothing about a position moves while you look at
-- it, though a copy landing in the meantime shifts every position by one.
--
-- An entry with no timestamp counts as ancient, so it falls inside older than and outside the
-- last, the safe way round for a row whose whole promise is that it keeps what is fresh.
local function predicateFor(item)
  if item.side == "all" then
    return function() return true end
  end
  if item.side == "newest" then
    return function(_, i) return i <= item.count end
  end
  if item.side == "trim" then
    return function(_, i) return i > item.count end
  end
  local cutoff = os.time() - item.secs
  if item.side == "older" then
    return function(e) return (e.ts or 0) < cutoff end
  end
  return function(e) return (e.ts or 0) >= cutoff end
end

-- How many entries a row would take. Counting only, with no table built, since the empty page
-- draws six of these and the field re-runs the whole supplier on every keystroke.
local function countFor(item)
  local pred, n = predicateFor(item), 0
  for i, e in ipairs(store.all()) do
    if pred(e, i) then n = n + 1 end
  end
  return n
end

-- Every entry a row would take, newest first since history already is. Only the pane asks for
-- this, one row at a time.
local function matchesFor(item)
  local pred, out = predicateFor(item), {}
  for i, e in ipairs(store.all()) do
    if pred(e, i) then out[#out + 1] = e end
  end
  return out
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

-- One slice row. The subtitle is the whole confirmation this action gets, so it always names
-- both numbers, what goes and what is left, and a row that would take nothing is disabled
-- rather than hidden, which keeps the ladder's rungs in the same place at every history size.
local function sliceRow(item, title, glyph, total)
  local n = countFor(item)
  local sub
  if total == 0 then
    sub = "history is empty"
  elseif n == 0 then
    sub = "nothing to delete"
  else
    sub = string.format("%d of %d items  ·  keeps %d", n, total, total - n)
  end
  return { title = title, subTitle = sub, glyph = glyph, enabled = n > 0, item = item }
end

local function hintRow(title, glyph)
  return { title = title, subTitle = EXAMPLES, glyph = glyph, enabled = false,
    item = { side = "hint" } }
end

--- P.rows(q) -> the page's rows for what is typed.
--- An empty field offers the ladder plus the whole of it. A parsed span offers both directions
--- off the one parse, the recent window first since that is the one a person types a span for,
--- and older than beneath it for the housekeeping case, each with its own count. Anything else
--- is a disabled hint. The field is a value rather than a filter, so nothing here is matched
--- against the query and the ui hands these rows to the chooser exactly as they are.
function P.rows(q)
  local total = #store.all()
  local value, status = P.parse(q)

  if value and value.secs then
    local span = P.label(value.secs)
    return {
      sliceRow({ side = "recent", secs = value.secs, span = span },
        "Delete the last " .. span, "🧹", total),
      sliceRow({ side = "older", secs = value.secs, span = span },
        "Delete older than " .. span, "🕰️", total),
    }
  end

  -- The same two directions on the other axis. The second row is titled Delete rather than Keep
  -- although keeping the newest hundred is what it is for, because every row on this page
  -- deletes, and one whose title said keep while it removed nine hundred entries would be the
  -- single place here where reading the title was not enough. What survives is in the subtitle.
  if value and value.count then
    local n = value.count
    local many = n .. (n == 1 and " item" or " items")
    return {
      -- Newest rather than last, although a span row says last, because a list has a bottom and
      -- the last hundred of one could honestly be read as the hundred at the end of it. Time has
      -- no such second reading. It also makes all four places that name this slice agree, the
      -- row, its twin below, the pane and the message afterwards.
      sliceRow({ side = "newest", count = n, span = "the newest " .. many },
        "Delete the newest " .. many, "🧹", total),
      sliceRow({ side = "trim", count = n, span = "all but the newest " .. many },
        "Delete all but the newest " .. many, "✂️", total),
    }
  end

  if status == "empty" then
    local out = {}
    for _, p in ipairs(PRESETS) do
      out[#out + 1] = sliceRow({ side = "recent", secs = p.secs, span = P.label(p.secs) },
        p.title, "🧹", total)
    end
    out[#out + 1] = sliceRow({ side = "all", span = "all of it" }, "Everything", "🗑️", total)
    return out
  end

  if status == "incomplete" then
    return { hintRow("Keep typing", "⌨️") }
  end
  return { hintRow("Not a duration or a count", "⚠️") }
end

--------------------------------------------------------------------------------
-- The pane
--------------------------------------------------------------------------------

-- One entry's copy time as a short readable stamp, or a plain word when it carries none, since
-- an entry from before timestamps were recorded still has to print something.
local function stamp(e)
  local ts = e and e.ts
  if not ts then return "at an unknown time" end
  return os.date("%a %d %b, %H:%M", ts)
end

--- P.preview(item) -> a meta line and a body block for the highlighted row, or nil for a row
--- with nothing to say, a hint. Two plain strings, because the pane already knows how to draw
--- a meta line above a monospace body and this page has no reason to teach it a second shape.
---
--- What it lists is what would go, newest first, which is the only real check available before
--- a delete that cannot be undone. A count is a promise, and this is the evidence for it.
function P.preview(item)
  if not item or item.side == "hint" then return nil end
  local hits = matchesFor(item)
  local total = #store.all()

  local meta
  if item.side == "all" then
    meta = "Everything  ·  " .. total .. " items"
  elseif item.side == "older" then
    meta = "Older than " .. item.span .. "  ·  " .. #hits .. " of " .. total
  elseif item.side == "trim" then
    meta = "All but the newest " .. item.count .. "  ·  " .. #hits .. " of " .. total
  elseif item.side == "newest" then
    meta = "The newest " .. item.count .. "  ·  " .. #hits .. " of " .. total
  else
    meta = "Last " .. item.span .. "  ·  " .. #hits .. " of " .. total
  end

  local lines = {}
  if #hits == 0 then
    lines[1] = "Nothing falls in this slice, so this row does nothing."
  else
    -- Where the line falls, named on the going side either way. A span knows its own boundary as
    -- a clock reading, while a count only learns one by looking at the entry the line lands
    -- against, so each says which end it is describing rather than both printing one word that
    -- would be true for only one of them.
    if item.secs then
      local cutoff = os.time() - item.secs
      lines[#lines + 1] = "Cutting at " .. os.date("%a %d %b, %H:%M", cutoff)
    elseif item.side == "newest" then
      lines[#lines + 1] = "Oldest one going, copied " .. stamp(hits[#hits])
    elseif item.side == "trim" then
      lines[#lines + 1] = "Newest one going, copied " .. stamp(hits[1])
    end
    lines[#lines + 1] = (total - #hits) .. " of " .. total .. " items stay"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "What goes, newest first"
    for i = 1, math.min(#hits, PREVIEW_ROWS) do
      local e = hits[i]
      lines[#lines + 1] = string.format("%3d  %s", i, e.title or "")
    end
    if #hits > PREVIEW_ROWS then
      lines[#lines + 1] = string.format("     … and %d more", #hits - PREVIEW_ROWS)
    end
  end

  return meta, table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- Applying one
--------------------------------------------------------------------------------

--- P.apply(item) -> how many entries went.
--- The store answers the count rather than the row, since the row's number was measured a
--- moment earlier against a boundary that has moved since, and only one of the two is what
--- actually happened.
function P.apply(item)
  if item.side == "all" then
    local n = #store.all()
    store.clear()
    return n
  end
  return store.removeWhere(predicateFor(item))
end

--- P.message(item, removed, left) -> the one line of feedback after a delete.
--- Here rather than in the ui because it is wording, and all of this page's wording lives
--- together or it drifts apart. Each side writes its own sentence rather than filling in a shared
--- one, since a phrase loose enough to fit a span and a position both reads as neither.
---
--- Every number in it is a measured one, what actually left and what is actually still there, so
--- a row asking for the newest hundred out of a history holding forty says forty and not a
--- hundred.
function P.message(item, removed, left)
  if removed == 0 then return "Nothing to delete" end
  local what = removed .. (removed == 1 and " item" or " items")
  if item.side == "all" then
    return "Cleared clipboard history, " .. what .. " gone"
  end
  if item.side == "newest" then
    return "Deleted the " .. removed .. (removed == 1 and " newest item, " or " newest items, ")
      .. left .. " left"
  end
  if item.side == "trim" then
    return "Deleted " .. what .. ", kept the newest " .. left
  end
  if item.side == "older" then
    return "Deleted " .. what .. " older than " .. item.span .. ", " .. left .. " left"
  end
  return "Deleted " .. what .. " from the last " .. item.span .. ", " .. left .. " left"
end

--- P.configure(opts) - inject the store this page reads and deletes from. Nothing else, since
--- everything else it does is its own policy.
function P.configure(opts)
  store = opts.store
  return P
end

return P
