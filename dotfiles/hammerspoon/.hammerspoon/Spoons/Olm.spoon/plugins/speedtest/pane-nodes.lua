--- What the speedtest pane looks like, as UI kit nodes and nothing else. It holds no canvas, no
--- scroll and no state, one function for each thing the pane can show, a run being taken right
--- now, a finished run, the trend across a network's history, and a block of explanation, so
--- pane.lua can decide what to show and when to draw it without knowing how any of it is built.
--- The kit arrives as the first argument of every function, since this file never loads it, which
--- also lets the unit case drive it with a bare kit and no canvas. Nothing here names a font, a
--- size, a line height or a colour literal, every piece of text is one of the kit's roles and
--- every colour a role name.
---
--- The roles. A large figure and the words that stand where one would be are title, a heading is
--- the kit's heading, a line a person reads as content is body, and an explanation or a line of
--- metadata is caption, which is drawn in subtext. Nothing is drawn louder than its role, so
--- emphasis comes from the colour a figure is given and never from an extra size.
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
--- The colours of a graph are ranks. The download is the first series and so primary, the upload
--- the second and so secondary, and the strip of latency or responsiveness the third and so
--- tertiary, in every view, so a series is the same colour wherever it is drawn. A baseline is the
--- border colour, the same rule colour a divider is drawn in.

local nodesPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local util = loadfile(nodesPath .. "util.lua")()

local M = {}

-- The gap between one block and the next, and between a heading and what it heads.
M.GAP = "m"
M.HEADING_GAP = "xs"
-- Between two graphs that are stacked directly, so one's baseline does not touch the next one's
-- peak.
M.GRAPH_GAP = "s"

-- The geometry of a graph rather than type, so these stay numbers.
M.GRAPH_H = 30
M.STRIP_H = 22
-- Room under a run of bars for the mark that says which one is the newest, drawn below the
-- baseline, two points down and two high, with a little air left under it.
M.MARK_ROOM = 6
M.MARK_DROP, M.MARK_H = 2, 2
-- A bar is wide enough to read as one and capped so two runs do not draw as two great slabs, with
-- the gap between neighbours taken out of the slot rather than out of the width. A bar is never
-- shorter than MIN_BAR_H, so a reading that rounds to nothing is still a reading.
M.BAR_MIN_W, M.BAR_MAX_W, M.BAR_GAP = 2, 18, 3
M.MIN_BAR_H = 1.5

-- How many digits before the point the slot a figure is drawn in has room for. Three covers every
-- link up to a thousand megabits, which a measurement on this kind of Mac does not reach. A
-- reading above it is drawn whole in a wider slot, so nothing is ever cut, and only that reading
-- moves the unit beside it.
M.FIGURE_DIGITS = 3

--------------------------------------------------------------------------------
-- Figures
--------------------------------------------------------------------------------

-- The width of one string at a role, measured whole the way the layout engine measures a text, so
-- a slot sized from it is exactly as wide as the text it is meant to hold.
local function widthOf(ui, str, role)
  local measure = ui.measure
  if measure.exact then return measure:exact(str, role.font, role.size) end
  return measure:width(str, role.font, role.size)
end

-- The widest value a figure can take, per font and size, measured once. A figure is rebuilt about
-- four times a second while a run is on, and a measurement asks the system.
local widest = {}

--- M.figureSlot(ui, number) -> points, how wide the slot a figure's number is drawn in must be.
---
--- The title role is the proportional system font, whose digits have different widths, so a
--- figure drawn at its own width pushes the unit beside it sideways every time it changes, from
--- 81.1 to 88.8 and back. The font cannot be asked for tabular digits, the canvas takes a font by
--- name and size and nothing else, and naming another font is not allowed here, so the figure sits
--- right aligned in a slot as wide as the widest value the format can produce, and the unit stands
--- after the slot and never moves. The widest value is the widest digit, found by measuring all
--- ten, repeated for the digits before the point and once after it.
function M.figureSlot(ui, number)
  local role = ui.tokens().text.title
  local key = role.font .. "\0" .. tostring(role.size)
  local slot = widest[key]
  if not slot then
    local digit, digitW = "0", 0
    for d = 0, 9 do
      local w = widthOf(ui, tostring(d), role)
      if w > digitW then digit, digitW = tostring(d), w end
    end
    slot = math.ceil(widthOf(ui, digit:rep(M.FIGURE_DIGITS) .. "." .. digit, role))
    widest[key] = slot
  end
  return math.max(slot, math.ceil(widthOf(ui, number, role)))
end

--- M.figure(ui, number, unit) -> node, a large figure with its unit, "81.1" and "Mbps down". The
--- number is right aligned in its slot, see figureSlot, and the unit takes the rest of the row.
function M.figure(ui, number, unit)
  return ui.row({
    ui.text(number, "title", { align = ui.aligns.right, width = M.figureSlot(ui, number) }),
    ui.text(unit, "title"),
  }, { gap = "s" })
end

--------------------------------------------------------------------------------
-- Graphs
--------------------------------------------------------------------------------

--- M.peak(values) -> the largest value, 0 for a list with none.
function M.peak(values)
  local hi = 0
  for i, v in ipairs(values or {}) do
    if i == 1 or v > hi then hi = v end
  end
  return hi
end

-- The colour a graph series is drawn in, a role name checked when the node is built so a
-- misspelling is a line number rather than an invisible line.
local function seriesColor(ui, color)
  local roles = ui.tokens().colors
  if not roles[color] then
    error("speedtest graph, unknown colour '" .. tostring(color) .. "'", 3)
  end
  return color
end

local function baseline(rect, base, tokens)
  return { type = "segments", action = "stroke", strokeWidth = 1, strokeColor = tokens.colors.border,
    coordinates = { { x = rect.x, y = base }, { x = rect.x + rect.w, y = base } } }
end

--- M.curve(ui, values, color, height) -> node. A continuous sample drawn as a line across the
--- full width, oldest at the left. The baseline is always drawn, so a series too short to plot
--- reads as waiting rather than as a gap. Scaled from zero rather than from its own floor, since
--- throughput and latency are both absolute questions and a curve floating on its own minimum
--- makes a steady link look like a mountain range.
function M.curve(ui, values, color, height)
  height = height or M.GRAPH_H
  color = seriesColor(ui, color)
  return ui.raw(height, function(rect, tokens)
    local base = rect.y + height
    local els = { baseline(rect, base, tokens) }
    if type(values) ~= "table" or #values < 2 then return els end
    local hi = M.peak(values)
    if hi <= 0 then return els end
    local step = rect.w / (#values - 1)
    local coordinates = {}
    for i, v in ipairs(values) do
      coordinates[i] = { x = rect.x + (i - 1) * step, y = base - (v / hi) * (height - 1) }
    end
    els[#els + 1] = { type = "segments", action = "stroke", strokeWidth = 1.5,
      strokeColor = tokens.colors[color], strokeCapStyle = "round", coordinates = coordinates }
    return els
  end)
end

--- M.bars(ui, values, color, height, mark) -> node. A series of separate runs, one bar each,
--- oldest at the left, see this file's own header for why these are never joined into a line.
--- With mark true the newest bar carries a small mark under the baseline, in the series colour, so
--- the reading being looked at is findable among its own history, and the node is MARK_ROOM
--- taller to hold it. A single bar is not marked, there is nothing to find it among.
function M.bars(ui, values, color, height, mark)
  height = height or M.GRAPH_H
  color = seriesColor(ui, color)
  return ui.raw(height + (mark and M.MARK_ROOM or 0), function(rect, tokens)
    local base = rect.y + height
    local els = { baseline(rect, base, tokens) }
    if type(values) ~= "table" or #values == 0 then return els end
    local hi = M.peak(values)
    if hi <= 0 then return els end
    local slot = rect.w / #values
    local barW = math.max(M.BAR_MIN_W, math.min(M.BAR_MAX_W, slot - M.BAR_GAP))
    for i, v in ipairs(values) do
      local h = math.max(M.MIN_BAR_H, (v / hi) * (height - 1))
      els[#els + 1] = { type = "rectangle", action = "fill", fillColor = tokens.colors[color],
        frame = { x = rect.x + (i - 1) * slot + (slot - barW) / 2, y = base - h, w = barW, h = h } }
    end
    if mark and #values >= 2 then
      els[#els + 1] = { type = "rectangle", action = "fill", fillColor = tokens.colors[color],
        frame = { x = rect.x + (#values - 1) * slot + (slot - barW) / 2, y = base + M.MARK_DROP,
                  w = barW, h = M.MARK_H } }
    end
    return els
  end)
end

--------------------------------------------------------------------------------
-- Pieces every view shares
--------------------------------------------------------------------------------

-- A column of blocks, one gap between each.
local function page(ui, blocks)
  return ui.stack(blocks, { gap = M.GAP })
end

-- A heading over what it heads, with the small gap a heading keeps.
local function under(ui, children)
  return ui.stack(children, { gap = M.HEADING_GAP })
end

-- A sentence or two of explanation, wrapped at the pane width.
local function paragraph(ui, str)
  return ui.text(str, "caption", { wrap = true })
end

-- A line of metadata, cut at the pane width rather than wrapped.
local function meta(ui, str)
  return ui.text(str, "caption")
end

local function seriesOf(samples, field)
  local out = {}
  for i, s in ipairs(samples or {}) do out[i] = s[field] or 0 end
  return out
end

--------------------------------------------------------------------------------
-- A run being taken right now
--------------------------------------------------------------------------------

--- M.running(ui, state) -> node. state.samples is the live trail, state.elapsed and state.limit
--- the seconds, and state.live whether figures can arrive at all.
function M.running(ui, state)
  local samples = state.samples or {}
  local latest = samples[#samples]
  local head = ui.heading("MEASURING", state.elapsed .. "s of " .. state.limit .. "s")

  if not state.live then
    return page(ui, {
      under(ui, { head, ui.text("Running.", "title") }),
      paragraph(ui, "No figures while this runs. The tool only reports progress to a terminal, "
        .. "and script, which is what gives it one, is missing from this Mac."),
    })
  end

  if not latest then
    return page(ui, {
      under(ui, { head, ui.text("Warming up", "title") }),
      paragraph(ui, "The first figures land a second or two in, once the flows are open."),
    })
  end

  local rating = util.rating(latest.rpm)
  local responsive
  if latest.rpm and latest.rpm > 0 then
    responsive = under(ui, {
      ui.heading("RESPONSIVENESS", rating),
      ui.text(string.format("%.0f RPM, %.0f ms under load", latest.rpm,
        util.loadedMs(latest.rpm) or 0), "body"),
      M.curve(ui, seriesOf(samples, "rpm"), "tertiary", M.STRIP_H),
    })
  else
    responsive = under(ui, { ui.heading("RESPONSIVENESS", rating), meta(ui, "not measured yet") })
  end

  return page(ui, {
    under(ui, {
      head,
      under(ui, { M.figure(ui, string.format("%.1f", latest.down), "Mbps down"),
                  M.curve(ui, seriesOf(samples, "down"), "primary") }),
    }),
    under(ui, { M.figure(ui, string.format("%.1f", latest.up), "Mbps up"),
                M.curve(ui, seriesOf(samples, "up"), "secondary") }),
    responsive,
    paragraph(ui, "These are live and still settling. The reading that gets kept is the "
      .. "tool's own final answer rather than the last of these."),
  })
end

--------------------------------------------------------------------------------
-- A finished run
--------------------------------------------------------------------------------

--- M.standing(record, history) -> the sentence saying where this run sits among the ones before
--- it on the same network, or nil. The one thing a single reading cannot say about itself and
--- the whole reason the history exists.
function M.standing(record, history)
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

--- M.linkLine(record) -> the kind of link, its interface and its protocol, "Wi Fi, en0, H3".
function M.linkLine(record)
  local parts = {}
  parts[#parts + 1] = record.kind == "wifi" and "Wi Fi" or (record.kind or "link")
  if record.iface then parts[#parts + 1] = record.iface end
  if record.proto then parts[#parts + 1] = record.proto:upper() end
  return table.concat(parts, ", ")
end

--- M.stateLine(record) -> the L4S and proxy state in one line, or nil when neither is known.
function M.stateLine(record)
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

--- M.result(ui, record, label, history) -> node, one finished run in full. label names the
--- network, history is every run kept for it.
function M.result(ui, record, label, history)
  local blocks = {}

  -- The two large figures, or the words that say there are none. The download is the first series
  -- and the upload the second, the same order the graphs below take their colours in.
  local figures = {}
  local down, up = util.rate(record.down), util.rate(record.up)
  if down then figures[#figures + 1] = M.figure(ui, down, "Mbps down") end
  if up then figures[#figures + 1] = M.figure(ui, up, "Mbps up") end
  if #figures == 0 then
    figures[1] = ui.text("Nothing measured", "title", { color = "subtext" })
  end
  blocks[#blocks + 1] = ui.stack(figures)

  -- The run's own shape while it was being taken, which exists for every run on its own and so
  -- is never flat for want of history. A run recorded before this was kept simply has none.
  local shape = record.curve
  if shape and (shape.down or shape.up) then
    local curves = {}
    if shape.down then curves[#curves + 1] = M.curve(ui, shape.down, "primary") end
    if shape.up then curves[#curves + 1] = M.curve(ui, shape.up, "secondary") end
    blocks[#blocks + 1] = under(ui, {
      ui.heading("THROUGH THIS RUN",
        record.secs and string.format("%.0f seconds", record.secs) or nil),
      ui.stack(curves, { gap = M.GRAPH_GAP }),
    })
  end

  if record.rpm then
    local rows = { ui.heading("RESPONSIVENESS", util.rating(record.rpm)),
                   ui.text(string.format("%.0f RPM", record.rpm), "body") }
    local loaded = util.loadedMs(record.rpm)
    local detail = {}
    if loaded then detail[#detail + 1] = string.format("%.0f ms under load", loaded) end
    if record.idleMs then detail[#detail + 1] = string.format("%.0f ms idle", record.idleMs) end
    if #detail > 0 then rows[#rows + 1] = meta(ui, table.concat(detail, ", ")) end
    blocks[#blocks + 1] = under(ui, rows)
  end

  if record.strip and record.lat then
    local range = string.format("%.0f to %.0f ms", record.lat.min or 0, record.lat.max or 0)
    local rows = { ui.heading("LATENCY UNDER LOAD", range),
                   M.curve(ui, record.strip, "tertiary", M.STRIP_H) }
    if record.lat.med then
      rows[#rows + 1] = meta(ui, string.format("median %.0f ms, 95th %.0f ms",
        record.lat.med, record.lat.p95 or record.lat.med))
    end
    blocks[#blocks + 1] = under(ui, rows)
  end

  local link = { meta(ui, M.linkLine(record)) }
  local state = M.stateLine(record)
  if state then link[#link + 1] = meta(ui, state) end
  local where = {}
  if record.endpoint then where[#where + 1] = record.endpoint end
  if record.secs then where[#where + 1] = string.format("%.0f s", record.secs) end
  if #where > 0 then link[#link + 1] = meta(ui, table.concat(where, ", ")) end
  blocks[#blocks + 1] = under(ui, { ui.heading("LINK"), ui.stack(link) })

  -- Where this run sits among the ones before it, the one thing a single reading cannot say.
  local place = M.standing(record, history)
  if place then
    blocks[#blocks + 1] = under(ui, { ui.heading(string.upper(label or "THIS NETWORK")),
                                      meta(ui, place) })
  end

  return page(ui, blocks)
end

--------------------------------------------------------------------------------
-- A network's history
--------------------------------------------------------------------------------

--- M.series(history, field) -> the values of one field, oldest first, which is the direction a
--- trend is read in, while every list on screen is newest first, which is the order a person
--- looks things up in. The two orders are opposite on purpose and this is the one place that
--- flips.
function M.series(history, field)
  local values = {}
  for i = #history, 1, -1 do
    local v = history[i][field]
    if v then values[#values + 1] = v end
  end
  return values
end

-- One direction's block, its heading with now and best flush right, the bars with the newest
-- marked, and the median under them.
local function direction(ui, label, values, color)
  local rows = {
    ui.heading(label, "now " .. util.rate(values[#values]) .. ", best " .. util.rate(M.peak(values))),
    M.bars(ui, values, color, nil, true),
  }
  local median = util.median(values)
  if median then rows[#rows + 1] = meta(ui, "median " .. util.rate(median) .. " Mbps") end
  return under(ui, rows)
end

--- M.trend(ui, history, label, note) -> node, a network's own past. history is newest first,
--- label names the network and note, when there is one, is a paragraph said under everything.
function M.trend(ui, history, label, note)
  local blocks = {
    under(ui, { ui.heading("TREND", (#history > 0) and (#history .. " runs") or nil),
                ui.text(label or "This network", "body") }),
  }
  local function addNote()
    if note then blocks[#blocks + 1] = paragraph(ui, note) end
  end

  if #history == 0 then
    blocks[#blocks + 1] = paragraph(ui, "No runs on this network yet. One takes about ten "
      .. "seconds and draws its own graph while it goes.")
    addNote()
    return page(ui, blocks)
  end

  -- One reading is not a trend and drawing it as one is what makes a graph look flat and mean
  -- nothing. What that reading does have is its own shape, so that is what is shown instead,
  -- with the wording saying plainly which of the two this is.
  if #history == 1 then
    local only = history[1]
    blocks[#blocks + 1] = paragraph(ui,
      "One reading so far, so this is its own shape rather than a trend.")
    local shape = only.curve
    if shape and shape.down then
      blocks[#blocks + 1] = under(ui, { ui.heading("DOWNLOAD", (util.rate(only.down) or "") .. " Mbps"),
                                        M.curve(ui, shape.down, "primary") })
      blocks[#blocks + 1] = under(ui, { ui.heading("UPLOAD", (util.rate(only.up) or "") .. " Mbps"),
                                        M.curve(ui, shape.up, "secondary") })
    else
      blocks[#blocks + 1] = under(ui, {
        ui.heading("THIS READING",
          (util.rate(only.down) or "?") .. " down, " .. (util.rate(only.up) or "?") .. " up"),
        paragraph(ui, "It was taken before the live figures were kept, so it has no shape of "
          .. "its own. The next one will."),
      })
    end
    addNote()
    return page(ui, blocks)
  end

  local downs = M.series(history, "down")
  local ups = M.series(history, "up")
  local rpms = M.series(history, "rpm")

  if #downs > 0 then blocks[#blocks + 1] = direction(ui, "DOWNLOAD", downs, "primary") end
  if #ups > 0 then blocks[#blocks + 1] = direction(ui, "UPLOAD", ups, "secondary") end
  if #rpms > 0 then
    local median = util.median(rpms)
    blocks[#blocks + 1] = under(ui, {
      ui.heading("RESPONSIVENESS", median and string.format("median %.0f RPM", median) or nil),
      M.bars(ui, rpms, "tertiary", M.STRIP_H),
    })
  end
  addNote()
  return page(ui, blocks)
end

--------------------------------------------------------------------------------
-- A block of explanation
--------------------------------------------------------------------------------

--- M.text(ui, title, lines) -> node. lines is a list of paragraphs and an empty string stands for
--- a gap, so a block of explanation can say more than one thing without running them together.
function M.text(ui, title, lines)
  local rows = {}
  for _, str in ipairs(lines or {}) do
    rows[#rows + 1] = (str == "") and ui.spacer(M.GAP) or paragraph(ui, str)
  end
  return under(ui, { ui.heading(string.upper(title or "")), ui.stack(rows) })
end

return M
