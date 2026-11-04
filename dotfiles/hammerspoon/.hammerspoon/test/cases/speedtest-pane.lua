-- Unit case for the speedtest pane's shape, plugins/speedtest/pane-nodes.lua. The runner reaches
-- this file with a dofile call carrying an absolute path, so it locates itself through
-- debug.getinfo and derives every module path from there.
--
-- The nodes file is pure, it only builds UI kit nodes, so it is driven with the real kit, style
-- and layout loaded as plain Lua and a stub measurer, and no canvas is ever made. The stub gives
-- the digits different widths on purpose, the way the system font does, since the figure slot
-- exists for exactly that. What pane.lua decides is which view is on screen, and the docking, the
-- scroll and the paint are the shared preview pane's, which test/cases/previewpane.lua covers.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local olm = caseDir .. "/../../Spoons/Olm.spoon/"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local function fresh(path)
  local chunk, err = loadfile(olm .. path)
  if not chunk then error("could not load " .. path .. ", " .. tostring(err)) end
  return chunk()
end

-- Proportional digits, a one is narrow and an eight wide, a point is narrower still, and every
-- other character is seven points. Whole strings are the sum, so a slot can be checked by sum.
local function charWidth(ch)
  if ch == "1" then return 5 end
  if ch == "." then return 4 end
  if ch:match("%d") then return 9 end
  return 7
end
local stubMeasure = fresh("lib/ui/measure.lua").new()
function stubMeasure:width(str)
  local total = 0
  for ch in (str or ""):gmatch(".") do total = total + charWidth(ch) end
  return total
end
stubMeasure.exact = stubMeasure.width

local styleLib = fresh("lib/ui/style.lua")
local style = styleLib.new({ appearance = function() return "Dark" end })
-- theme-exempt, fixture colours for a unit case, not a tool's look
style.configure({ colors = { dark = { foreground = { white = 0.92 }, subtext = { white = 0.55 },
  background = "#29292e", border = "#59575C", primary = "#a58be0", secondary = "#6fc7a0",
  tertiary = "#d9a066" } } })
local tokens = style.tokens()
local kit = fresh("lib/ui/kit.lua").new(styleLib.names)
local engine = fresh("lib/ui/layout.lua").new({ measure = stubMeasure })
local ui = setmetatable({
  tokens = function() return tokens end,
  measure = stubMeasure,
  layout = function(node, rect, opts) return engine.layout(node, rect, tokens, opts) end,
}, { __index = kit })

local nodes = fresh("plugins/speedtest/pane-nodes.lua")
local RECT = { x = 0, y = 0, w = 400, h = 2000 }

local function textOf(el) return el.text and el.text.getString and el.text:getString() end

-- Every node of one kind under a node, depth first.
local function find(node, kind, out)
  out = out or {}
  if node.kind == kind then out[#out + 1] = node end
  for _, child in ipairs(node.children or {}) do find(child, kind, out) end
  return out
end

-- Every string a tree says, in reading order.
local function said(node, out)
  out = out or {}
  if node.kind == "text" then out[#out + 1] = node.str end
  for _, child in ipairs(node.children or {}) do said(child, out) end
  return out
end

local function sentence(node) return table.concat(said(node), "|") end

-- The headings of a tree, which are the section texts a row or a lone text leads with.
local function headings(node)
  local out = {}
  for _, text in ipairs(find(node, "text")) do
    if text.variant == "section" and text.color == nil then out[#out + 1] = text.str end
  end
  return table.concat(out, ",")
end

-- What each graph in a tree draws, in order, as the colour of its line or its first bar.
local function graphs(node)
  local out = {}
  for _, raw in ipairs(find(node, "raw")) do
    local els = raw.draw({ x = 0, y = 0, w = 200, h = raw.height }, tokens)
    local series = els[2]
    out[#out + 1] = { height = raw.height, els = els,
      color = series and (series.strokeColor or series.fillColor) }
  end
  return out
end

local function sameColor(a, b) return a ~= nil and rawequal(a, b) end

--------------------------------------------------------------------------------
-- a run being taken
--------------------------------------------------------------------------------

local dead = nodes.running(ui, { samples = {}, elapsed = 3, limit = 10, live = false })
check("a run with no terminal says Running and why there are no figures",
  sentence(dead):find("MEASURING|3s of 10s|Running.|No figures while this runs", 1, true) ~= nil, sentence(dead))
check("Running is the title role in the foreground",
  find(dead, "text")[3].variant == "title" and find(dead, "text")[3].color == nil)

local warming = nodes.running(ui, { samples = {}, elapsed = 1, limit = 10, live = true })
check("a live run with no sample yet says Warming up and when the figures come",
  sentence(warming):find("Warming up|The first figures land a second or two in", 1, true) ~= nil, sentence(warming))

local trail = {
  { down = 40, up = 10, rpm = 0 },
  { down = 81.14, up = 12.5, rpm = 300 },
}
local live = nodes.running(ui, { samples = trail, elapsed = 4, limit = 10, live = true })
check("a live run has a heading with the seconds, two figures, a responsiveness block and a note",
  headings(live) == "MEASURING,RESPONSIVENESS", headings(live))
check("the figures read number then unit, one decimal",
  sentence(live):find("81.1|Mbps|12.5|Mbps", 1, true) ~= nil, sentence(live))
check("the responsiveness line gives the rating, the RPM and the milliseconds under load",
  sentence(live):find("Medium", 1, true) ~= nil and sentence(live):find("300 RPM, 200 ms under load", 1, true) ~= nil,
  sentence(live))
check("the closing sentence says the figures are still settling",
  sentence(live):find("These are live and still settling.", 1, true) ~= nil)

local liveGraphs = graphs(live)
check("a live run draws download primary, upload secondary and responsiveness tertiary",
  #liveGraphs == 3 and sameColor(liveGraphs[1].color, tokens.colors.primary)
    and sameColor(liveGraphs[2].color, tokens.colors.secondary)
    and sameColor(liveGraphs[3].color, tokens.colors.tertiary))
check("every baseline is the border colour",
  sameColor(liveGraphs[1].els[1].strokeColor, tokens.colors.border)
    and sameColor(liveGraphs[3].els[1].strokeColor, tokens.colors.border))
check("the responsiveness strip is the short one, the throughput curves the tall",
  liveGraphs[1].height == nodes.GRAPH_H and liveGraphs[3].height == nodes.STRIP_H)

local noRpm = nodes.running(ui, { samples = { { down = 1, up = 1 } }, elapsed = 1, limit = 10, live = true })
check("a sample with no responsiveness yet says so in caption and subtext",
  sentence(noRpm):find("Not measured yet", 1, true) ~= nil and #graphs(noRpm) == 2)

--------------------------------------------------------------------------------
-- the figures
--------------------------------------------------------------------------------

-- The widest digit is a nine wide one, so the slot is that digit for every digit the number has,
-- with the point between, and never the fixed three before the point it once was.
check("the slot is as wide as the widest value with the same digits",
  nodes.figureSlot(ui, "5.0") == 9 + 4 + 9 and nodes.figureSlot(ui, "88.8") == 9 + 9 + 4 + 9,
  tostring(nodes.figureSlot(ui, "5.0")) .. " " .. tostring(nodes.figureSlot(ui, "88.8")))
check("a value with more digits gets a slot as wide as its own digits",
  nodes.figureSlot(ui, "1234.5") == 4 * 9 + 4 + 9, tostring(nodes.figureSlot(ui, "1234.5")))

-- Where the number's slot and the unit land, for one figure laid out alone.
local function laid(number)
  local numberEl, unitEl
  for _, el in ipairs(ui.layout(nodes.figure(ui, "down", number), RECT)) do
    local str = textOf(el)
    if str == number then numberEl = el elseif str == "Mbps" then unitEl = el end
  end
  return numberEl and numberEl.frame, unitEl and unitEl.frame
end
local n1, u1 = laid("11.1")
local n2, u2 = laid("88.8")
local n3, u3 = laid("100.5")
check("the unit does not move while the count of digits stays the same",
  u1 and u2 and u1.x == u2.x, u1 and u2 and (u1.x .. " " .. u2.x))
check("the number's slot starts in the same place whatever the number is",
  n1 and n2 and n3 and n1.x == n2.x and n2.x == n3.x)
check("the number is right aligned in a slot of its own digits",
  n2 and n2.w == nodes.figureSlot(ui, "88.8"))
check("one more digit moves the unit by about one digit, never by a blank one in front",
  u3 and u2 and u3.x > u2.x and u3.x - u2.x <= 9, u3 and u2 and (u3.x - u2.x))
check("the unit is drawn in subtext",
  (function()
    for _, text in ipairs(find(nodes.figure(ui, "down", "1.0"), "text")) do
      if text.str == "Mbps" then return text.color == "subtext" and text.variant == "title" end
    end
  end)())

local both = nodes.figures(ui, "81.1", "12.5")
local arrows = find(both, "icon")
check("the two figures stand in one row, download first, each led by its arrow",
  both.kind == "row" and #both.children == 2 and #arrows == 2
    and arrows[1].source.sf == "arrow.down" and arrows[2].source.sf == "arrow.up",
  tostring(both.kind) .. " " .. #arrows)
check("a figure missing on one side leaves the other alone in the row",
  #find(nodes.figures(ui, "81.1", nil), "icon") == 1 and nodes.figures(ui, nil, nil) == nil)
check("a live run shows its figures in that same row",
  #find(live, "icon") == 2)

--------------------------------------------------------------------------------
-- a finished run
--------------------------------------------------------------------------------

local record = {
  at = 100, down = 81140000, up = 12500000, rpm = 300, idleMs = 12.4, secs = 10.2,
  kind = "wifi", iface = "en0", proto = "h3", l4s = "enabled", proxied = "not_proxied",
  endpoint = "edge.example", curve = { down = { 1, 2, 3 }, up = { 3, 2, 1 } },
  strip = { 10, 20, 30 }, lat = { min = 10, med = 20, p95 = 28, max = 30 },
}
local history = { record, { at = 90, down = 50000000 }, { at = 80, down = 90000000 } }
local result = nodes.result(ui, record, "Home", history)
check("a finished run has every section, in reading order",
  headings(result) == "THROUGH THIS RUN,RESPONSIVENESS,LATENCY UNDER LOAD,LINK,HOME", headings(result))
check("the figures use the rate formatter, a decimal under a hundred",
  sentence(result):find("81.1|Mbps|12.5|Mbps", 1, true) ~= nil, sentence(result))
check("a fast link drops the decimal",
  sentence(nodes.result(ui, { down = 250400000 }, nil, {})):find("250|Mbps", 1, true) ~= nil)
check("the facts say seconds, RPM, load and idle latency, and the latency range",
  sentence(result):find("10 seconds", 1, true) ~= nil and sentence(result):find("300 RPM|200 ms under load, 12 ms idle", 1, true) ~= nil
    and sentence(result):find("10 to 30 ms|Median 20 ms, 95th 28 ms", 1, true) ~= nil, sentence(result))
check("the link, state and place lines keep their wording",
  sentence(result):find("Wi-Fi, en0, H3|L4S on, not proxied|edge.example, 10 s", 1, true) ~= nil, sentence(result))
check("a link kind other than Wi-Fi leads its line with a capital",
  nodes.linkLine({ kind = "other", iface = "utun8", proto = "h2" }) == "Other, utun8, H2",
  nodes.linkLine({ kind = "other", iface = "utun8", proto = "h2" }))
check("the standing sentence counts the runs it beat",
  sentence(result):find("Faster than 1 of the last 2 runs here", 1, true) ~= nil, sentence(result))
local resultGraphs = graphs(result)
check("the run's curves are primary then secondary and its latency strip is tertiary",
  #resultGraphs == 3 and sameColor(resultGraphs[1].color, tokens.colors.primary)
    and sameColor(resultGraphs[2].color, tokens.colors.secondary)
    and sameColor(resultGraphs[3].color, tokens.colors.tertiary))
check("the metadata lines are caption, which is drawn in subtext",
  (function()
    for _, text in ipairs(find(result, "text")) do
      if text.str == "Wi-Fi, en0, H3" then return text.variant == "caption" and text.color == nil end
    end
  end)())

local nothing = nodes.result(ui, {}, nil, {})
check("a run with no figures says Nothing measured in the title role and subtext",
  find(nothing, "text")[1].str == "Nothing measured" and find(nothing, "text")[1].variant == "title"
    and find(nothing, "text")[1].color == "subtext")
check("a run with no shape, rpm or strip has only the link block",
  headings(nothing) == "LINK", headings(nothing))
check("with no history there is no standing and no network heading",
  headings(nodes.result(ui, { down = 1e6 }, "Home", {})) == "LINK")
check("a network heading with no label is THIS NETWORK",
  headings(nodes.result(ui, record, nil, history)):find("THIS NETWORK", 1, true) ~= nil)

--------------------------------------------------------------------------------
-- the trend
--------------------------------------------------------------------------------

local empty = nodes.trend(ui, {}, "Home", "A note.")
check("a network with no runs says so, then the note",
  sentence(empty):find("TREND|Home|No runs on this network yet.", 1, true) ~= nil
    and sentence(empty):find("A note.", 1, true) ~= nil and #graphs(empty) == 0, sentence(empty))
check("the network label is the body role in the foreground",
  find(empty, "text")[2].variant == "body" and find(empty, "text")[2].color == nil)
check("with no label the trend says This network",
  sentence(nodes.trend(ui, {}, nil, nil)):find("This network", 1, true) ~= nil)

local one = nodes.trend(ui, { { at = 1, down = 5e6, up = 2e6, curve = { down = { 1, 2 }, up = { 2, 1 } } } },
  "Home", nil)
check("one reading is shown as its own shape, with the wording that says so",
  sentence(one):find("1 runs", 1, true) ~= nil
    and sentence(one):find("One reading so far, so this is its own shape rather than a trend.", 1, true) ~= nil
    and headings(one) == "TREND,DOWNLOAD,UPLOAD", sentence(one))
local oneGraphs = graphs(one)
check("its two curves are primary and secondary and are curves, not bars",
  #oneGraphs == 2 and sameColor(oneGraphs[1].color, tokens.colors.primary)
    and sameColor(oneGraphs[2].color, tokens.colors.secondary) and oneGraphs[1].els[2].type == "segments")

local oldOne = nodes.trend(ui, { { at = 1, down = 5e6 } }, "Home", nil)
check("one reading from before shapes were kept says it has none",
  sentence(oldOne):find("THIS READING|5.0 down, ? up", 1, true) ~= nil
    and sentence(oldOne):find("It was taken before the live figures were kept", 1, true) ~= nil, sentence(oldOne))

local many = {
  { at = 3, down = 90e6, up = 9e6, rpm = 400 },
  { at = 2, down = 60e6, up = 6e6, rpm = 200 },
  { at = 1, down = 30e6, up = 3e6, rpm = 100 },
}
local trend = nodes.trend(ui, many, "Home", "Name it.")
check("a trend heads its runs and lists download, upload and responsiveness",
  headings(trend) == "TREND,DOWNLOAD,UPLOAD,RESPONSIVENESS", headings(trend))
check("the facts read now, best and median",
  sentence(trend):find("Now 90.0, best 90.0", 1, true) ~= nil and sentence(trend):find("Median 60.0 Mbps", 1, true) ~= nil
    and sentence(trend):find("Median 200 RPM", 1, true) ~= nil, sentence(trend))
check("the note closes the trend", sentence(trend):sub(-8) == "Name it.")
local barGraphs = graphs(trend)
check("separate runs are bars, never a joined line, in primary, secondary and tertiary",
  #barGraphs == 3 and barGraphs[1].els[2].type == "rectangle"
    and sameColor(barGraphs[1].color, tokens.colors.primary)
    and sameColor(barGraphs[2].color, tokens.colors.secondary)
    and sameColor(barGraphs[3].color, tokens.colors.tertiary))
check("the newest bar of each direction is marked in its own series colour, below the baseline",
  #barGraphs[1].els == 1 + 3 + 1 and sameColor(barGraphs[1].els[5].fillColor, tokens.colors.primary)
    and barGraphs[1].els[5].frame.y > barGraphs[1].els[1].coordinates[1].y)
check("the responsiveness bars carry no mark and are the short strip",
  #barGraphs[3].els == 1 + 3 and barGraphs[3].height == nodes.STRIP_H)
check("the marked bars reserve room for the mark",
  barGraphs[1].height == nodes.GRAPH_H + nodes.MARK_ROOM)
check("the bars are oldest at the left",
  barGraphs[1].els[2].frame.h < barGraphs[1].els[4].frame.h)
check("series run oldest first although history is newest first",
  (function()
    local values = nodes.series(many, "down")
    return #values == 3 and values[1] == 30e6 and values[2] == 60e6 and values[3] == 90e6
  end)())

local flatGraphs = graphs(nodes.trend(ui, { { at = 2, down = 1e6, up = 1e6 }, { at = 1, down = 1e6, up = 1e6 } }, "x"))
check("a series that never changes still draws its bars",
  #flatGraphs[1].els >= 3)

--------------------------------------------------------------------------------
-- a block of explanation
--------------------------------------------------------------------------------

local help = nodes.text(ui, "Direction", { "First.", "", "Second." })
check("an explanation is an upper cased heading over its paragraphs, with a gap for an empty line",
  headings(help) == "DIRECTION" and #find(help, "spacer") == 1
    and sentence(help) == "DIRECTION|First.|Second.", sentence(help))
check("paragraphs are caption text that wraps",
  (function()
    for _, text in ipairs(find(help, "text")) do
      if text.str == "First." then return text.variant == "caption" and text.wrap == true end
    end
  end)())

--------------------------------------------------------------------------------
-- the pane draws only through the kit
--------------------------------------------------------------------------------

local function slurp(path)
  local handle = io.open(path, "r")
  if not handle then return "" end
  local text = handle:read("*a")
  handle:close()
  return text
end
for _, name in ipairs({ "pane.lua", "pane-nodes.lua" }) do
  local code = slurp(olm .. "plugins/speedtest/" .. name):gsub("%-%-[^\n]*", "")
  check(name .. " names no font, size, line height or colour literal",
    not code:find("Menlo") and not code:find("textSize") and not code:find("textFont")
      and not code:find("hs.styledtext") and not code:find('"#%x%x%x') and not code:find("hs.drawing.color"))
end

-- A layout of every view runs without an error and answers a height.
for label, node in pairs({ running = live, result = result, trend = trend, empty = empty, help = help }) do
  local els, height = ui.layout(node, RECT)
  check("the " .. label .. " view lays out to elements and a height", #els > 0 and height > 0)
end
local first = textOf(ui.layout(nodes.figure(ui, "down", "81.1"), RECT)[1])
check("a laid out figure is drawn as styled text of its number", first == "81.1", tostring(first))
