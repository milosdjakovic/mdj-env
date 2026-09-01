--- === Speedtest.pane ===
---
--- The companion pane docked beside the list, where every figure a run returns actually lands. A
--- row holds three numbers and a run answers twenty, which is the whole argument for the pane
--- existing at all.
---
--- A canvas of its own rather than a CanvasPanel instance, the same choice the clipboard and
--- processes previews both make and for the same reason. A CanvasPanel computes its own placement
--- and sizes itself from its content, while this pane has to land exactly on the companion rect
--- the chooser atom reserved and reported. Drawing anywhere else would put it outside the rect the
--- atom's click watcher treats as part of the picker, so a click on the pane would dismiss the
--- list instead of passing through. What it does share is the surface itself, injected as
--- CanvasPanel.surfaceElements, so this pane, the docked shortcut panel and the cheat sheets are
--- one component drawn in three places rather than three lookalikes.
---
--- It draws four different things and knows which by which function was called, a run being taken
--- right now, a finished run, the trend across a network's history, and a block of explanation.
--- Each builds its own element list and none shares layout with the others.
---
--- EVERY GRAPH HERE IS ONE OF TWO KINDS AND THE DIFFERENCE IS NOT DECORATION. A curve is drawn
--- for a continuous sample, throughput measured four times a second through one run or latency
--- measured through one load, where the space between two points means elapsed time and joining
--- them is telling the truth. Bars are drawn for a series of separate runs, where the space
--- between two of them is however long the person went without measuring, and a line joining them
--- would draw a slope through a gap it knows nothing about. A single run therefore gets one bar
--- rather than a flat line, which is also why a network with one reading is shown that reading's
--- own shape instead of a trend that cannot exist yet.
---
--- Content taller than the pane scrolls, since a finished run says more than a pane holds at the
--- sizes a chooser reserves. The scroll arrives from the atom rather than from a key of this
--- plugin's own, so it costs no binding anywhere.

local panePath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local util = loadfile(panePath .. "util.lua")()

local M = {}

local cfg = {}

local canvas = nil
local frame = nil
local colors = nil
local model = nil     -- the last thing asked for, so a redock repaints without being told again
local hidden = false
local scrollY = 0     -- how far the body is scrolled, always clamped to the real overflow
local maxScroll = 0   -- how far it can go, recomputed on every paint since content changes

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local PAD_X, PAD_Y = 14, 10

local FONT = "Menlo"
local LABEL_SIZE, BODY_SIZE, BIG_SIZE = 11, 12, 20
local LINE_MULT = 1.35
local BLOCK_GAP = 12
local HEADING_GAP = 2
local GRAPH_H = 30
local STRIP_H = 22

local function lineHeight(size)
  return math.ceil(size * LINE_MULT)
end

local LABEL_H = lineHeight(LABEL_SIZE)

local function hexColor(hex)
  local r, g, b = tostring(hex):match("#?(%x%x)(%x%x)(%x%x)")
  if not r then return { white = 0.85, alpha = 1 } end
  return { red = tonumber(r, 16) / 255, green = tonumber(g, 16) / 255,
           blue = tonumber(b, 16) / 255, alpha = 1 }
end

local function faded(color, alpha)
  local copy = {}
  for k, v in pairs(color) do copy[k] = v end
  copy.alpha = alpha
  return copy
end

-- A styled run with a pinned line height, so the drawn height matches the line count exactly and
-- every block below lands where the layout said it would. Truncating rather than wrapping is a
-- safety net, since a line a shade wider than expected would otherwise take a line more than the
-- layout accounted for and push everything below it down.
local function styled(text, color, size, align)
  local pinned = lineHeight(size)
  return hs.styledtext.new(text or "", {
    font = { name = FONT, size = size },
    color = color,
    paragraphStyle = { maximumLineHeight = pinned, minimumLineHeight = pinned,
                       alignment = align, lineBreak = "truncateTail" },
  })
end

local function shifted(element, dx, dy)
  local copy = {}
  for k, v in pairs(element) do copy[k] = v end
  if copy.frame then
    copy.frame = { x = copy.frame.x + dx, y = copy.frame.y + dy,
                   w = copy.frame.w, h = copy.frame.h }
  end
  if copy.coordinates then
    local moved = {}
    for i, point in ipairs(copy.coordinates) do
      moved[i] = { x = point.x + dx, y = point.y + dy }
    end
    copy.coordinates = moved
  end
  return copy
end

--------------------------------------------------------------------------------
-- Blocks
--------------------------------------------------------------------------------

-- A heading read as two anchors, the name at the left and the facts flush right, so a figure that
-- changes under the eye stays in one fixed place instead of sliding as its text grows.
local function heading(els, label, facts, y, w)
  els[#els + 1] = { type = "text", text = styled(label, colors.meta, LABEL_SIZE),
    frame = { x = 0, y = y, w = w, h = LABEL_H * 2 } }
  if facts and facts ~= "" then
    els[#els + 1] = { type = "text", text = styled(facts, colors.meta, LABEL_SIZE, "right"),
      frame = { x = 0, y = y, w = w, h = LABEL_H * 2 } }
  end
  return y + LABEL_H + HEADING_GAP
end

local function line(els, text, y, w, color, size)
  size = size or BODY_SIZE
  local h = lineHeight(size)
  els[#els + 1] = { type = "text", text = styled(text, color or colors.fg, size),
    frame = { x = 0, y = y, w = w, h = h * 2 } }
  return y + h
end

-- Monospace character width per size, measured once from a run so any per glyph padding averages
-- out. This is what the column budgets below are counted in.
local charWidth = {}
local function monoCharWidth(size)
  local hit = charWidth[size]
  if hit then return hit end
  local run = "MMMMMMMMMMMMMMMMMMMM"
  local measured = hs.drawing.getTextDrawingSize(
    hs.styledtext.new(run, { font = { name = FONT, size = size } }))
  hit = (((measured and measured.w) or (size * 12 * 0.6)) / #run)
  charWidth[size] = hit
  return hit
end

-- Break one sentence to a column budget, at the last space that fits, hard breaking a token longer
-- than a whole line. Simpler than a general purpose wrapper because everything here starts as a
-- single sentence with no paragraphs to preserve.
local function wrapMono(str, cols)
  str = tostring(str):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  local lines, pos, n = {}, 1, #str
  while pos <= n do
    if n - pos + 1 <= cols then
      lines[#lines + 1] = str:sub(pos)
      break
    end
    local slice = str:sub(pos, pos + cols - 1)
    local lastSpace = nil
    for at in slice:gmatch("() ") do lastSpace = at end
    if lastSpace and lastSpace > 1 then
      lines[#lines + 1] = str:sub(pos, pos + lastSpace - 2)
      pos = pos + lastSpace
    else
      lines[#lines + 1] = slice
      pos = pos + cols
    end
  end
  return lines
end

-- A whole sentence, wrapped to the pane and drawn as ONE element rather than one per line, since
-- a pinned line height makes the joined run's drawn height exactly the line count. Every piece of
-- prose in this file goes through here, so nothing is written pre broken to a width it might not
-- have and nothing is silently cut at the edge.
local function paragraph(els, text, y, w, color, size)
  size = size or BODY_SIZE
  local cols = math.max(8, math.floor(w / monoCharWidth(size)))
  local lines = wrapMono(text, cols)
  if #lines == 0 then return y end
  local h = lineHeight(size)
  els[#els + 1] = { type = "text",
    text = styled(table.concat(lines, "\n"), color or colors.fg, size),
    frame = { x = 0, y = y, w = w, h = #lines * h + h } }
  return y + #lines * h
end

local function extremes(values)
  if #values == 0 then return 0, 0 end
  local lo, hi = values[1], values[1]
  for _, v in ipairs(values) do
    if v < lo then lo = v end
    if v > hi then hi = v end
  end
  return lo, hi
end

-- A continuous sample drawn as a line across the full width, oldest at the left. The baseline is
-- always drawn, so a series too short to plot reads as waiting rather than as a gap. Scaled from
-- zero rather than from its own floor, since throughput and latency are both absolute questions
-- and a curve floating on its own minimum makes a steady link look like a mountain range.
local function curve(els, values, y, w, color, height)
  height = height or GRAPH_H
  els[#els + 1] = { type = "segments", action = "stroke", strokeWidth = 1,
    strokeColor = faded(colors.meta, 0.35),
    coordinates = { { x = 0, y = y + height }, { x = w, y = y + height } } }
  if type(values) ~= "table" or #values < 2 then return y + height end

  local _, hi = extremes(values)
  if hi <= 0 then return y + height end
  local step = w / (#values - 1)
  local coordinates = {}
  for i, v in ipairs(values) do
    coordinates[i] = { x = (i - 1) * step, y = y + height - (v / hi) * (height - 1) }
  end
  els[#els + 1] = { type = "segments", action = "stroke", strokeWidth = 1.5,
    strokeColor = color, strokeCapStyle = "round", coordinates = coordinates }
  return y + height
end

-- A series of separate runs, one bar each, oldest at the left. See this file's own header for why
-- these are never joined into a line.
local function bars(els, values, y, w, color, height)
  height = height or GRAPH_H
  els[#els + 1] = { type = "segments", action = "stroke", strokeWidth = 1,
    strokeColor = faded(colors.meta, 0.35),
    coordinates = { { x = 0, y = y + height }, { x = w, y = y + height } } }
  if type(values) ~= "table" or #values == 0 then return y + height end

  local _, hi = extremes(values)
  if hi <= 0 then return y + height end
  local slot = w / #values
  -- Wide enough to read as a bar and capped so two runs do not draw as two great slabs, with the
  -- gap between them coming out of the slot rather than out of the width.
  local barW = math.max(2, math.min(18, slot - 3))
  for i, v in ipairs(values) do
    local h = (v / hi) * (height - 1)
    if h < 1.5 then h = 1.5 end
    els[#els + 1] = { type = "rectangle", action = "fill", fillColor = color,
      frame = { x = (i - 1) * slot + (slot - barW) / 2, y = y + height - h, w = barW, h = h } }
  end
  return y + height
end

-- The newest bar in a series, marked so the reading being looked at is findable among its own
-- history rather than being one column of many that all look alike.
local function markLast(els, count, y, w, color, height)
  if count < 2 then return end
  local slot = w / count
  local barW = math.max(2, math.min(18, slot - 3))
  local x = (count - 1) * slot + (slot - barW) / 2
  els[#els + 1] = { type = "rectangle", action = "fill", fillColor = faded(color, 0.9),
    frame = { x = x, y = y + (height or GRAPH_H) + 2, w = barW, h = 2 } }
end

--------------------------------------------------------------------------------
-- A run being taken right now
--------------------------------------------------------------------------------

local function seriesOf(samples, field)
  local out = {}
  for i, s in ipairs(samples or {}) do out[i] = s[field] or 0 end
  return out
end

local function runningElements(state, w)
  local els, y = {}, 0
  local samples = state.samples or {}
  local latest = samples[#samples]

  y = heading(els, "MEASURING", state.elapsed .. "s of " .. state.limit .. "s", y, w)
  y = y + HEADING_GAP

  if not state.live then
    y = line(els, "Running.", y, w, colors.fg, BIG_SIZE)
    y = y + BLOCK_GAP
    y = paragraph(els, "No figures while this runs. The tool only reports progress to a terminal, "
      .. "and script, which is what gives it one, is missing from this Mac.", y, w, colors.meta)
    return els, y
  end

  if not latest then
    y = line(els, "Warming up", y, w, colors.fg, BIG_SIZE)
    y = y + BLOCK_GAP
    y = paragraph(els, "The first figures land a second or two in, once the flows are open.",
      y, w, colors.meta)
    return els, y
  end

  y = line(els, string.format("%.1f Mbps down", latest.down), y, w, colors.fg, BIG_SIZE)
  y = curve(els, seriesOf(samples, "down"), y, w, colors.fg)
  y = y + BLOCK_GAP

  y = line(els, string.format("%.1f Mbps up", latest.up), y, w, colors.note, BIG_SIZE)
  y = curve(els, seriesOf(samples, "up"), y, w, colors.note)
  y = y + BLOCK_GAP

  local rating = util.rating(latest.rpm)
  y = heading(els, "RESPONSIVENESS", rating, y, w)
  if latest.rpm and latest.rpm > 0 then
    local loaded = util.loadedMs(latest.rpm)
    y = line(els, string.format("%.0f RPM, %.0f ms under load", latest.rpm, loaded or 0), y, w)
    y = curve(els, seriesOf(samples, "rpm"), y, w, colors.meta, STRIP_H)
  else
    y = line(els, "not measured yet", y, w, colors.meta)
  end
  y = y + BLOCK_GAP

  y = paragraph(els, "These are live and still settling. The reading that gets kept is the "
    .. "tool's own final answer rather than the last of these.", y, w, colors.meta)
  return els, y
end

--------------------------------------------------------------------------------
-- A finished run
--------------------------------------------------------------------------------

-- Where this run sits among the ones before it on the same network, the one thing a single
-- reading cannot say about itself and the whole reason the history exists.
local function standing(record, history)
  if not (record and record.down and history) then return nil end
  local better, total = 0, 0
  for _, other in ipairs(history) do
    if other.at ~= record.at and other.down then
      total = total + 1
      if record.down > other.down then better = better + 1 end
    end
  end
  if total == 0 then return nil end
  return "faster than " .. better .. " of the last " .. total .. " runs here"
end

local function linkLine(record)
  local parts = {}
  parts[#parts + 1] = record.kind == "wifi" and "Wi Fi" or (record.kind or "link")
  if record.iface then parts[#parts + 1] = record.iface end
  if record.proto then parts[#parts + 1] = record.proto:upper() end
  return table.concat(parts, ", ")
end

local function stateLine(record)
  local parts = {}
  if record.l4s then
    parts[#parts + 1] = "L4S " .. (record.l4s == "enabled" and "on" or "off")
  end
  if record.proxied then
    parts[#parts + 1] = record.proxied == "not_proxied" and "not proxied" or "proxied"
  end
  if #parts == 0 then return nil end
  return table.concat(parts, ", ")
end

local function resultElements(record, label, history, w)
  local els, y = {}, 0

  local down = util.rate(record.down)
  local up = util.rate(record.up)
  if down then y = line(els, down .. " Mbps down", y, w, colors.fg, BIG_SIZE) end
  if up then y = line(els, up .. " Mbps up", y, w, colors.note, BIG_SIZE) end
  if not (down or up) then y = line(els, "Nothing measured", y, w, colors.meta, BIG_SIZE) end
  y = y + BLOCK_GAP

  -- The run's own shape while it was being taken, which exists for every run on its own and so
  -- is never flat for want of history. A run recorded before this was kept simply has none.
  local shape = record.curve
  if shape and (shape.down or shape.up) then
    y = heading(els, "THROUGH THIS RUN",
      record.secs and string.format("%.0f seconds", record.secs) or nil, y, w)
    if shape.down then y = curve(els, shape.down, y, w, colors.fg) end
    if shape.up then y = curve(els, shape.up, y, w, colors.note) end
    y = y + BLOCK_GAP
  end

  if record.rpm then
    local rating = util.rating(record.rpm)
    y = heading(els, "RESPONSIVENESS", rating, y, w)
    y = line(els, string.format("%.0f RPM", record.rpm), y, w)
    local loaded = util.loadedMs(record.rpm)
    local detail = {}
    if loaded then detail[#detail + 1] = string.format("%.0f ms under load", loaded) end
    if record.idleMs then detail[#detail + 1] = string.format("%.0f ms idle", record.idleMs) end
    if #detail > 0 then y = line(els, table.concat(detail, ", "), y, w, colors.meta) end
    y = y + BLOCK_GAP
  end

  if record.strip and record.lat then
    local range = string.format("%.0f to %.0f ms", record.lat.min or 0, record.lat.max or 0)
    y = heading(els, "LATENCY UNDER LOAD", range, y, w)
    y = curve(els, record.strip, y, w, colors.note, STRIP_H)
    if record.lat.med then
      y = line(els, string.format("median %.0f ms, 95th %.0f ms",
        record.lat.med, record.lat.p95 or record.lat.med), y, w, colors.meta)
    end
    y = y + BLOCK_GAP
  end

  y = heading(els, "LINK", nil, y, w)
  y = line(els, linkLine(record), y, w, colors.meta)
  local state = stateLine(record)
  if state then y = line(els, state, y, w, colors.meta) end
  local where = {}
  if record.endpoint then where[#where + 1] = record.endpoint end
  if record.secs then where[#where + 1] = string.format("%.0f s", record.secs) end
  if #where > 0 then y = line(els, table.concat(where, ", "), y, w, colors.meta) end
  y = y + BLOCK_GAP

  local place = standing(record, history)
  if place then
    y = heading(els, string.upper(label or "THIS NETWORK"), nil, y, w)
    y = line(els, place, y, w, colors.note)
  end

  return els, y
end

--------------------------------------------------------------------------------
-- A network's history
--------------------------------------------------------------------------------

-- Oldest first, which is the direction a trend is read in, while every list on screen is newest
-- first, which is the order a person looks things up in. The two orders are opposite on purpose
-- and this is the one place that flips.
local function series(history, field)
  local values = {}
  for i = #history, 1, -1 do
    local v = history[i][field]
    if v then values[#values + 1] = v end
  end
  return values
end

local function bestOf(values)
  if #values == 0 then return nil end
  local _, hi = extremes(values)
  return hi
end

local function trendElements(history, label, note, w)
  local els, y = {}, 0

  y = heading(els, "TREND", (#history > 0) and (#history .. " runs") or nil, y, w)
  y = line(els, label or "This network", y, w, colors.fg, BODY_SIZE)
  y = y + BLOCK_GAP

  if #history == 0 then
    y = paragraph(els, "No runs on this network yet. One takes about ten seconds and draws its "
      .. "own graph while it goes.", y, w, colors.meta)
    if note then
      y = y + BLOCK_GAP
      y = paragraph(els, note, y, w, colors.note)
    end
    return els, y
  end

  -- One reading is not a trend and drawing it as one is what makes a graph look flat and mean
  -- nothing. What that reading does have is its own shape, so that is what is shown instead,
  -- with the wording saying plainly which of the two this is.
  if #history == 1 then
    local only = history[1]
    y = paragraph(els, "One reading so far, so this is its own shape rather than a trend.",
      y, w, colors.meta)
    y = y + BLOCK_GAP
    local shape = only.curve
    if shape and shape.down then
      y = heading(els, "DOWNLOAD", (util.rate(only.down) or "") .. " Mbps", y, w)
      y = curve(els, shape.down, y, w, colors.fg)
      y = y + BLOCK_GAP
      y = heading(els, "UPLOAD", (util.rate(only.up) or "") .. " Mbps", y, w)
      y = curve(els, shape.up, y, w, colors.note)
    else
      y = heading(els, "THIS READING",
        (util.rate(only.down) or "?") .. " down, " .. (util.rate(only.up) or "?") .. " up", y, w)
      y = paragraph(els, "It was taken before the live figures were kept, so it has no shape of "
        .. "its own. The next one will.", y, w, colors.meta)
    end
    if note then
      y = y + BLOCK_GAP
      y = paragraph(els, note, y, w, colors.note)
    end
    return els, y
  end

  local downs = series(history, "down")
  local ups = series(history, "up")
  local rpms = series(history, "rpm")

  if #downs > 0 then
    y = heading(els, "DOWNLOAD",
      "now " .. util.rate(downs[#downs]) .. ", best " .. util.rate(bestOf(downs)), y, w)
    y = bars(els, downs, y, w, colors.fg)
    markLast(els, #downs, y - GRAPH_H, w, colors.fg)
    y = y + 6
    local median = util.median(downs)
    if median then y = line(els, "median " .. util.rate(median) .. " Mbps", y, w, colors.meta) end
    y = y + BLOCK_GAP
  end

  if #ups > 0 then
    y = heading(els, "UPLOAD",
      "now " .. util.rate(ups[#ups]) .. ", best " .. util.rate(bestOf(ups)), y, w)
    y = bars(els, ups, y, w, colors.note)
    markLast(els, #ups, y - GRAPH_H, w, colors.note)
    y = y + 6
    local median = util.median(ups)
    if median then y = line(els, "median " .. util.rate(median) .. " Mbps", y, w, colors.meta) end
    y = y + BLOCK_GAP
  end

  if #rpms > 0 then
    local median = util.median(rpms)
    y = heading(els, "RESPONSIVENESS",
      median and (string.format("median %.0f RPM", median)) or nil, y, w)
    y = bars(els, rpms, y, w, colors.meta, STRIP_H)
    y = y + BLOCK_GAP
  end

  if note then y = paragraph(els, note, y, w, colors.note) end
  return els, y
end

--------------------------------------------------------------------------------
-- A block of explanation
--------------------------------------------------------------------------------

local function textElements(title, lines, w)
  local els, y = {}, 0
  y = heading(els, string.upper(title or ""), nil, y, w)
  for _, text in ipairs(lines or {}) do
    if text == "" then
      y = y + BLOCK_GAP
    else
      y = paragraph(els, text, y, w, colors.meta)
    end
  end
  return els, y
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function ensureCanvas()
  if canvas then return end
  canvas = hs.canvas.new(frame)
  canvas:level(hs.canvas.windowLevels.floating)
  -- A click on the pane must not pull focus off the search field. The atom's click watcher
  -- already treats a point inside the companion rect as part of the picker and passes it
  -- through, so between the two a click here changes nothing.
  canvas:clickActivating(false)
end

local function buildBody(innerW)
  if model.what == "running" then
    return runningElements(model, innerW)
  elseif model.what == "result" then
    return resultElements(model.record, model.label, model.history, innerW)
  elseif model.what == "trend" then
    return trendElements(model.history, model.label, model.note, innerW)
  end
  return textElements(model.title, model.lines, innerW)
end

local function paint()
  if hidden then return end
  if not (model and frame and colors and cfg.surface) then return end
  ensureCanvas()

  local innerW = frame.w - 2 * PAD_X
  local innerH = frame.h - 2 * PAD_Y

  local body, bodyH = buildBody(innerW)
  maxScroll = math.max(0, (bodyH or 0) - innerH)
  if scrollY > maxScroll then scrollY = maxScroll end
  if scrollY < 0 then scrollY = 0 end

  local els = {}
  for _, el in ipairs(cfg.surface(frame.w, frame.h)) do els[#els + 1] = el end
  els[#els + 1] = { type = "rectangle", action = "clip",
    frame = { x = PAD_X, y = PAD_Y, w = innerW, h = innerH } }
  for _, el in ipairs(body) do els[#els + 1] = shifted(el, PAD_X, PAD_Y - scrollY) end
  els[#els + 1] = { type = "resetClip" }

  -- A thumb rather than a hint in words, drawn only while there is genuinely more than fits, so a
  -- pane that holds all of its content carries no chrome at all.
  if maxScroll > 0 then
    local trackH = innerH
    local thumbH = math.max(18, trackH * (innerH / (bodyH or innerH)))
    local travel = trackH - thumbH
    local thumbY = PAD_Y + (maxScroll > 0 and (scrollY / maxScroll) * travel or 0)
    els[#els + 1] = { type = "rectangle", action = "fill", roundedRectRadii = { xRadius = 2, yRadius = 2 },
      fillColor = faded(colors.meta, 0.45),
      frame = { x = frame.w - 7, y = thumbY, w = 3, h = thumbH } }
  end

  canvas:frame(frame)
  canvas:replaceElements(els)
  canvas:show()
end

--------------------------------------------------------------------------------
-- Public surface, dot called
--------------------------------------------------------------------------------

--- pane.configure(opts) - injected by the file that owns the picker.
--- opts.surface     function(w, h) -> canvas elements, the shared CanvasPanel surface. Absent
---                  means no pane at all, see isEnabled.
--- opts.emptyState  function(w, h, opts) -> the shared quiet state a docked pane paints when its
---                  highlight has nothing to describe.
--- opts.palette     function() -> the theme's preview colours, resolved per open so the pane
---                  follows the live light and dark appearance.
function M.configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  return M
end

--- pane.isEnabled() - whether a pane can be drawn at all, which is to say whether the root
--- injected the shared surface.
function M.isEnabled()
  return cfg.surface ~= nil
end

--- pane.dock(companionFrame) - take the rect the chooser atom reported. Fired with a seed rect at
--- show and again once the real window settles, so a redock is expected.
function M.dock(companionFrame)
  if not (M.isEnabled() and companionFrame) then return end
  frame = companionFrame
  hidden = false
  local p = (cfg.palette and cfg.palette()) or {}
  colors = {
    fg = hexColor(p.fg or "#dcdcdc"),
    meta = hexColor(p.meta or "#8a8a8a"),
    path = hexColor(p.path or "#7a7a7a"),
    note = hexColor(p.note or "#c8a86a"),
  }
  if model then paint() end
end

-- Every show resets the scroll, since the content underneath it changed and holding a position
-- measured against something else would land somewhere arbitrary.
local function show(next)
  model = next
  scrollY = 0
  paint()
end

--- pane.showRunning(state) - the run being taken right now.
--- state.samples the live trail, state.elapsed and state.limit the seconds, state.live whether
--- figures can arrive at all.
function M.showRunning(state)
  show({
    what = "running",
    samples = state.samples or {},
    elapsed = state.elapsed or 0,
    limit = state.limit or 10,
    live = state.live and true or false,
  })
end

--- pane.refreshRunning(state) - the same view with fresh figures, keeping the scroll where the
--- person put it, since this is called several times a second and resetting it would make the
--- pane impossible to read while a run is on.
function M.refreshRunning(state)
  if not (model and model.what == "running") then
    M.showRunning(state)
    return
  end
  model.samples = state.samples or {}
  model.elapsed = state.elapsed or 0
  paint()
end

--- pane.showResult(record, label, history) - one finished run in full.
function M.showResult(record, label, history)
  if not record then
    M.clear()
    return
  end
  show({ what = "result", record = record, label = label, history = history or {} })
end

--- pane.showTrend(history, label, note) - a network's own past.
function M.showTrend(history, label, note)
  show({ what = "trend", history = history or {}, label = label, note = note })
end

--- pane.showText(title, lines) - a block of explanation, for a page whose highlight has something
--- to say and no measurement behind it.
function M.showText(title, lines)
  show({ what = "text", title = title, lines = lines or {} })
end

--- pane.scrollBy(points) -> whether anything moved.
--- The atom hands over a distance already normalised for a wheel against a trackpad and already
--- corrected for direction, so this only has to clamp and repaint.
function M.scrollBy(points)
  if not (model and frame and maxScroll > 0) then return false end
  local next = scrollY - (points or 0)
  if next < 0 then next = 0 end
  if next > maxScroll then next = maxScroll end
  if next == scrollY then return false end
  scrollY = next
  paint()
  return true
end

--- pane.clear() - the shared empty state, for a highlight with nothing to describe. The pane stays
--- up rather than vanishing, since a reserved rectangle with nothing in it reads as a broken
--- layout. It genuinely disappears only on the stage's own swap signal and on destroy.
function M.clear()
  model = nil
  scrollY = 0
  maxScroll = 0
  if hidden then return end
  if not (frame and colors and cfg.surface) then return end
  if not cfg.emptyState then
    if canvas then canvas:hide() end
    return
  end
  ensureCanvas()
  local innerW, innerH = frame.w - 2 * PAD_X, frame.h - 2 * PAD_Y
  local els = {}
  for _, el in ipairs(cfg.surface(frame.w, frame.h)) do els[#els + 1] = el end
  for _, el in ipairs(cfg.emptyState(innerW, innerH, { color = colors.meta })) do
    els[#els + 1] = shifted(el, PAD_X, PAD_Y)
  end
  canvas:frame(frame)
  canvas:replaceElements(els)
  canvas:show()
end

--- pane.hide() - hide without destroying, for the stage's own swap away signal.
function M.hide()
  hidden = true
  if canvas then canvas:hide() end
end

--- pane.destroy() - tear the pane down completely, on the one teardown path.
function M.destroy()
  model = nil
  frame = nil
  colors = nil
  hidden = false
  scrollY = 0
  maxScroll = 0
  if canvas then
    canvas:delete()
    canvas = nil
  end
end

return M
