--- Processes preview pane.
---
--- The companion pane docked beside the picker, showing what a single row has no room
--- to say. The full working directory, every port, the live trend, and above all the
--- process tree a stop would take, since seeing that one row is five processes and
--- which five is what makes pressing stop safe.
---
--- It is a canvas of its own rather than a CanvasPanel instance, the same choice the
--- clipboard preview makes and for the same reason. A CanvasPanel computes its own
--- placement from an anchor and sizes itself from its content, while this pane must
--- land exactly on the companion rect the Chooser atom already reserved and reported.
--- Drawing it anywhere else would put it outside the rect the atom's click watcher
--- treats as part of the picker, so a click on the pane would dismiss the picker
--- instead of being passed through. What it does share is the surface itself, injected
--- as CanvasPanel.surfaceElements, so the pane, the docked shortcut panel and the cheat
--- sheets are one component drawn in three places rather than three lookalikes.
---
--- Dot called, like util and metrics, and it holds no policy of its own. The surface
--- routine, the palette, the sampler's two accessors and the CPU formatter are all
--- injected by the surface that owns the picker, so this file names nothing concrete
--- and cannot drift from the row it is describing.
---
--- The redraw is split in two because it has two very different callers. The static
--- half, everything derived from the row itself, is built once per row and cached,
--- since the highlight poll fires often and a row's command line and tree do not
--- change under it. The live half, the two figures and their sparklines, is rebuilt on
--- every paint, which is the only work a sampler tick costs. Its HEIGHT is fixed by
--- whether the row can be sampled at all rather than by whether a reading has landed
--- yet, so the static half below it never shifts when the first sample arrives and the
--- cache stays valid across the whole open.
---
--- Rows differ and the pane must never show a labelled section with nothing under it.
--- A section whose text comes back empty is dropped entirely, label included, so a
--- container row shows no DIRECTORY heading and no TREE heading, a portless watcher
--- shows no PORTS heading, and a container, which is deliberately never sampled,
--- reserves no room for figures it will never have.

local previewPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local util = loadfile(previewPath .. "util.lua")()

local M = {}

-- Injected, see M.configure. Empty until then, and with no surface injected the pane
-- stays dark, which is the whole degradation path, see M.isEnabled.
local cfg = {}

local canvas = nil -- the docked canvas, built lazily and deleted on every close
local frame = nil  -- the companion rect the atom reported, where the canvas docks
local colors = nil -- the palette, resolved once per open rather than per highlight
local model = nil  -- the cached static half of the row on screen, see buildModel
local hidden = false -- set by M.hide, cleared by M.dock, the resurrection guard paint reads

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

-- The padding matches the shortcut panel and the clipboard preview, CanvasPanel's
-- 14 and 10, so the panes that share the screen also share their inner margin.
local PAD_X, PAD_Y = 14, 10

-- One monospace font for everything, so a wrap can be measured by column arithmetic
-- and so the tree's box drawing lines up into real columns. A proportional font would
-- need per string measurement for every line and would still bend the tree.
local FONT = "Menlo"
local LABEL_SIZE, BODY_SIZE, TREE_SIZE = 11, 12, 11
local LINE_MULT = 1.35
local BLOCK_GAP = 12   -- between one section and the next
local HEADING_GAP = 2  -- between a heading and what it heads

-- The live block. Two label lines each with a strip under it, and a fixed total, since
-- the static content below is positioned past it and must not move when a sample lands.
local SPARK_H = 20
local SPARK_GAP = 3
-- Points per sample, so a short trail draws short rather than being stretched across
-- the full width and reading as far more history than there is. The newest sample sits
-- at the right edge and the trail grows leftward, which also means the pane needs to
-- know nothing about the sampler's history cap.
local SPARK_STEP = 7
-- The CPU strip is scaled from zero to the window's peak, floored here, so a server
-- idling at a fraction of a percent draws along the bottom instead of having its noise
-- blown up into a mountain range.
local CPU_FLOOR = 5

local function lineHeight(size)
  return math.ceil(size * LINE_MULT)
end

local LABEL_H = lineHeight(LABEL_SIZE)

-- The live block's total, spelled out from the pieces liveBlock lays rather than
-- measured from what it drew. It has to be known before the block is built, because it
-- is what the static half below is offset by, and it has to stay the same whether or
-- not a sample has landed yet, or the whole pane would jump the moment one does.
local LIVE_H = 2 * (LABEL_H + HEADING_GAP + SPARK_GAP + SPARK_H) + 2 * BLOCK_GAP

--------------------------------------------------------------------------------
-- Text and colour helpers
--------------------------------------------------------------------------------

local function hexColor(hex)
  local r, g, b = tostring(hex):match("#?(%x%x)(%x%x)(%x%x)")
  if not r then return { white = 0.85, alpha = 1 } end
  return { red = tonumber(r, 16) / 255, green = tonumber(g, 16) / 255,
           blue = tonumber(b, 16) / 255, alpha = 1 }
end

-- A fainter copy of a palette colour, for the strip baselines. Derived rather than
-- named in the palette, since a baseline is a shade of a colour the theme already
-- carries and adding a key for it would be a second thing to keep in step.
local function faded(color, alpha)
  local c = {}
  for k, v in pairs(color) do c[k] = v end
  c.alpha = alpha
  return c
end

-- A styled run with a pinned line height, so the drawn height matches the line count
-- exactly and every block below it lands where the layout said it would.
--
-- Every run truncates rather than wraps, and that is a safety net rather than a look.
-- The blocks here are wrapped by column arithmetic against an averaged character
-- width, so a line that measures a shade wider than the estimate would otherwise wrap
-- itself, silently taking a line more than the layout accounted for and pushing
-- everything below it down. Losing a character at the edge is the far cheaper failure,
-- and in the tree a wrap would break the box drawing outright.
local function styled(text, color, size, align)
  local lineH = lineHeight(size)
  return hs.styledtext.new(text or "", {
    font = { name = FONT, size = size },
    color = color,
    paragraphStyle = { maximumLineHeight = lineH, minimumLineHeight = lineH,
                       alignment = align, lineBreak = "truncateTail" },
  })
end

-- Monospace character width per size, measured once from a run so any per glyph
-- padding averages out. This is what the column budgets are counted in.
local charWidth = {}
local function monoCharWidth(size)
  local hit = charWidth[size]
  if hit then return hit end
  local run = "MMMMMMMMMMMMMMMMMMMM"
  local sz = hs.drawing.getTextDrawingSize(hs.styledtext.new(run, { font = { name = FONT, size = size } }))
  hit = (((sz and sz.w) or (size * 12 * 0.6)) / #run)
  charWidth[size] = hit
  return hit
end

local function columns(w, size)
  return math.max(1, math.floor(w / monoCharWidth(size)))
end

-- Wrap one long line to a column budget. Simpler than a general purpose wrapper
-- because everything here starts as a single line, a command line or a path, so there
-- are no paragraphs to preserve. It breaks at the last space that fits and hard breaks
-- a token longer than the whole line, which is exactly what a long path with no spaces
-- in it needs.
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
    for s in slice:gmatch("() ") do lastSpace = s end
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

-- A block of text as one canvas element rather than one per line. The pinned line
-- height makes the joined run's drawn height exactly the line count, and one element
-- keeps a repaint cheap where a long tree would otherwise cost dozens.
local function appendLines(els, lines, y, w, color, size)
  if #lines == 0 then return y end
  local lineH = lineHeight(size)
  local h = #lines * lineH
  els[#els + 1] = { type = "text", text = styled(table.concat(lines, "\n"), color, size),
    frame = { x = 0, y = y, w = w, h = h + lineH } }
  return y + h
end

-- A heading line, read as two anchors like the clipboard preview's header. The name
-- sits at the left and the facts sit flush against the right edge, so a figure that
-- changes under the eye stays in one fixed place instead of sliding as its own text
-- grows. The right anchor is optional and a heading with nothing to report simply
-- carries no facts.
local function appendHeading(els, label, facts, y, w)
  els[#els + 1] = { type = "text", text = styled(label, colors.meta, LABEL_SIZE),
    frame = { x = 0, y = y, w = w, h = LABEL_H * 2 } }
  if facts and facts ~= "" then
    els[#els + 1] = { type = "text", text = styled(facts, colors.meta, LABEL_SIZE, "right"),
      frame = { x = 0, y = y, w = w, h = LABEL_H * 2 } }
  end
  return y + LABEL_H + HEADING_GAP
end

--------------------------------------------------------------------------------
-- Sparklines
--------------------------------------------------------------------------------

-- One field of the sampler's trail for a row, oldest first. The sampler only remembers
-- a reading once it carries a CPU figure, so the two trails always have the same length
-- and neither can contain a hole.
local function trail(key, field)
  local history = cfg.metrics and cfg.metrics.history(key)
  if not history then return {} end
  local out = {}
  for i, reading in ipairs(history) do out[i] = reading[field] or 0 end
  return out
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

-- Draw a trail into a strip, with the baseline always present so a row with no history
-- yet reads as waiting rather than as a gap in the pane. lo and hi are the value range
-- the strip's height stands for, and a range that has collapsed to nothing draws down
-- the middle, which reads as steady rather than as pinned at either edge.
local function appendSpark(els, values, y, w, color, lo, hi)
  els[#els + 1] = { type = "segments", action = "stroke", strokeWidth = 1,
    strokeColor = faded(colors.meta, 0.35),
    coordinates = { { x = 0, y = y + SPARK_H }, { x = w, y = y + SPARK_H } } }
  if #values < 2 then return y + SPARK_H end

  local step = math.min(SPARK_STEP, w / (#values - 1))
  local span = hi - lo
  local coordinates = {}
  for i, v in ipairs(values) do
    -- Anchored at the right edge, so the newest sample is always in the same place and
    -- the trail extends back into the pane as far as there is history for it.
    local x = w - (#values - i) * step
    local frac = (span > 0) and ((v - lo) / span) or 0.5
    coordinates[i] = { x = x, y = y + SPARK_H - frac * (SPARK_H - 1) }
  end
  els[#els + 1] = { type = "segments", action = "stroke", strokeWidth = 1.5,
    strokeColor = color, strokeCapStyle = "round", coordinates = coordinates }
  return y + SPARK_H
end

-- The live half of the pane, rebuilt on every paint. Height is decided by whether the
-- row can be sampled at all rather than by whether a sample has landed, so the block
-- appears the moment the pane does and the static content below never shifts under it.
--
-- A container reserves nothing here. Asking the docker daemon for stats costs more than
-- the whole scan, so those rows carry no live figures by design, and a strip drawn for
-- them would be a permanently empty one.
--
-- The two strips are scaled differently on purpose. CPU is an absolute question, is
-- this thing busy, so it runs from zero to the window's peak with a floor under it.
-- Memory is a relative one, is this thing growing, so it runs across the window's own
-- range, where a leak climbs and a steady server sits flat down the middle. The figures
-- beside each heading carry the absolute anchor either way.
local function liveBlock(row, w)
  local els = {}
  if not (row and row.pid) then return els end

  local reading = cfg.metrics and cfg.metrics.reading(row.key)
  local cpuTrail = trail(row.key, "cpu")
  local memTrail = trail(row.key, "rss")
  -- A plain percentage if nothing was injected, so a missed wiring costs the rounding
  -- rather than throwing inside the highlight poll on every fire.
  local formatCpu = cfg.formatCpu or function(pct) return string.format("%.1f%%", pct) end
  local y = 0

  -- The peak is printed only when it is above the figure beside it. A peak that IS the
  -- current reading is the same number written twice, which costs the line's width and
  -- tells you nothing, and it is exactly the case a quiet steady process is always in.
  local facts = {}
  local cpu = reading and reading.cpu
  if cpu then facts[#facts + 1] = formatCpu(cpu) end
  local _, cpuPeak = extremes(cpuTrail)
  if cpuPeak > (cpu or 0) then facts[#facts + 1] = "peak " .. formatCpu(cpuPeak) end
  y = appendHeading(els, "CPU", table.concat(facts, "   "), y, w)
  y = appendSpark(els, cpuTrail, y + SPARK_GAP, w, colors.note, 0, math.max(cpuPeak, CPU_FLOOR))
  y = y + BLOCK_GAP

  facts = {}
  -- The scan's own reading stands in until the first sample lands, the same fallback
  -- the row subtitle takes, so the pane is never briefly missing a figure it is about
  -- to have.
  local rss = (reading and reading.rss) or row.rss
  if rss then facts[#facts + 1] = util.humanBytes(rss) end
  local memLo, memHi = extremes(memTrail)
  if memHi > (rss or 0) then facts[#facts + 1] = "peak " .. util.humanBytes(memHi) end
  y = appendHeading(els, "MEMORY", table.concat(facts, "   "), y, w)
  appendSpark(els, memTrail, y + SPARK_GAP, w, colors.meta, memLo, memHi)

  return els
end

--------------------------------------------------------------------------------
-- The static half, one section per thing the row carries
--------------------------------------------------------------------------------

local HOME = os.getenv("HOME") or ""

-- Home shortened to a tilde. The pane is read, not copied from, and the first thirty
-- characters of every path being identical costs width the project part needs.
local function tildePath(path)
  if HOME ~= "" and path:sub(1, #HOME) == HOME then return "~" .. path:sub(#HOME + 1) end
  return path
end

-- The sections, in reading order. Each one names its heading, the palette tone its
-- value is drawn in, and a builder that returns the text or nothing at all. Returning
-- nothing drops the whole section including its heading, which is the single rule that
-- keeps every shape of row free of empty labelled space, rather than a branch per
-- source that this file would have to grow.
--
-- A heading is a function where the row decides the wording. A row carrying a
-- container id is a container, so its command field holds an image name rather than a
-- command line, and it is labelled for what it is. That tests a field the row carries
-- rather than the name of the source that produced it, which is the same way the rest
-- of the pane decides what to draw.
local SECTIONS = {
  {
    label = "PORTS",
    tone = "fg",
    -- Joined with the dot the row subtitle already separates facts by, rather than
    -- with a run of spaces, because everything drawn here is wrapped by a routine that
    -- collapses whitespace and a wider gap would quietly come out as a single space.
    text = function(row)
      local parts = {}
      for _, port in ipairs(row.ports or {}) do parts[#parts + 1] = ":" .. port end
      return table.concat(parts, " · ")
    end,
  },
  {
    label = "DIRECTORY",
    tone = "path",
    text = function(row) return row.cwd and tildePath(row.cwd) end,
  },
  {
    label = function(row) return row.containerId and "IMAGE" or "COMMAND" end,
    tone = "fg",
    -- The untruncated form when the source carries one, since reading the whole
    -- invocation is most of the reason this section exists and the elided copy on
    -- the row was cut to fit a single subtitle line. Falling back rather than
    -- requiring it, so a source that carries only the one form still renders.
    text = function(row) return row.commandFull or row.command end,
  },
  {
    label = "CONTAINER",
    tone = "meta",
    -- The short id docker itself prints, which is what any follow up command takes.
    -- The container's NAME is already the row's title, so repeating it here would
    -- spend a section on something the eye is resting on anyway.
    text = function(row) return row.containerId and row.containerId:sub(1, 12) end,
  },
}

local function headingOf(section, row)
  if type(section.label) == "function" then return section.label(row) end
  return section.label
end

--------------------------------------------------------------------------------
-- The tree
--------------------------------------------------------------------------------

-- Turn the flat member list into drawn tree lines. The source hands over a pre order
-- walk carrying a depth per member, which is enough to reconstruct the shape, and every
-- prefix unit is exactly three columns wide, so the indentation can be measured by
-- arithmetic rather than by counting bytes in a string of box characters.
--
-- Whether a member is the last of its siblings is not on the member, so it is read from
-- the walk. The next member at the same depth before any shallower one means more
-- siblings follow, and that single lookahead decides both the corner it draws and
-- whether its own children carry a continuation bar past it.
local function treeLines(tree, cols, pidWidth)
  local lines, prefix = {}, {}
  for i, member in ipairs(tree) do
    local depth = member.depth or 0
    local last = true
    for j = i + 1, #tree do
      local other = tree[j].depth or 0
      if other < depth then break end
      if other == depth then
        last = false
        break
      end
    end
    local drawn = table.concat(prefix, "", 1, depth)
    if depth > 0 then drawn = drawn .. (last and "└─ " or "├─ ") end
    -- A root carries no bar past it even when another root follows, because a root
    -- draws no connector of its own for a bar to descend from, so one there would hang
    -- in the air beside a line that starts at the margin.
    prefix[depth + 1] = (depth > 0 and not last) and "│  " or "   "

    -- Padded on the right rather than the left, so the number sits against the corner
    -- that points at it instead of being pushed away from it by its own padding, while
    -- the fixed width still lines the labels up down the block.
    local pid = string.format("%-" .. pidWidth .. "s ", tostring(member.pid or "?"))
    -- The label is cut rather than wrapped, because a wrapped second line would sit
    -- under the box characters and break the only thing this block exists to show.
    local budget = cols - 3 * depth - pidWidth - 1
    local label = util.elide(member.label or "", math.max(4, budget)) or ""
    lines[#lines + 1] = drawn .. pid .. label
  end
  return lines
end

-- The tree, given whatever vertical room the sections above it left. It is last in the
-- pane because it is the one section that can be any length, so it is also the one that
-- can absorb the leftover space instead of forcing a scroll into a pane that has no
-- scroll bindings. Past the room available it is cut with a count of what was cut, and
-- when there is no room for even one member the section is dropped whole rather than
-- printing a heading over nothing.
--
-- The count is the scan's view of the group. A stop re reads the group live before
-- signalling it, so a tree that grew since the scan is still taken whole, and this
-- number is what the picker knew rather than a promise.
local function appendTree(els, row, y, w, availH)
  local tree = row.tree or {}
  if #tree == 0 then return y end

  local lineH = lineHeight(TREE_SIZE)
  local room = availH - y - LABEL_H - HEADING_GAP
  local maxLines = math.floor(room / lineH)
  if maxLines < 1 then return y end

  local widest = 0
  for _, member in ipairs(tree) do
    widest = math.max(widest, #tostring(member.pid or "?"))
  end
  local lines = treeLines(tree, columns(w, TREE_SIZE), widest)

  if #lines > maxLines then
    local kept = math.max(1, maxLines - 1)
    local dropped = #lines - kept
    while #lines > kept do table.remove(lines) end
    lines[#lines + 1] = string.format("… %d more", dropped)
  end

  local facts = string.format("stops %d process%s", #tree, #tree == 1 and "" or "es")
  y = appendHeading(els, "TREE", facts, y, w)
  return appendLines(els, lines, y, w, colors.fg, TREE_SIZE)
end

--------------------------------------------------------------------------------
-- The static model, built once per row
--------------------------------------------------------------------------------

-- Everything the row itself says, laid out from the top of the space the live block
-- leaves. Cached by the row key and the box it was laid out in, so the highlight poll
-- pays for this once per row rather than once per fire, and a re dock at a corrected
-- frame rebuilds it because the tree's cut depends on the height.
local function buildModel(row, w, h)
  local liveH = (row.pid and LIVE_H) or 0
  local els, y = {}, 0
  for _, section in ipairs(SECTIONS) do
    local text = section.text(row)
    if text and text ~= "" then
      y = appendHeading(els, headingOf(section, row), nil, y, w)
      y = appendLines(els, wrapMono(text, columns(w, BODY_SIZE)), y, w, colors[section.tone], BODY_SIZE)
      y = y + BLOCK_GAP
    end
  end
  y = appendTree(els, row, y, w, h - liveH)
  return { row = row, w = w, h = h, liveH = liveH, els = els }
end

--------------------------------------------------------------------------------
-- Painting
--------------------------------------------------------------------------------

-- A shallow copy of an element with its frame offset, so a block built in its own
-- (0, 0) box can be placed absolutely without the builder knowing where it landed.
local function shifted(el, dx, dy)
  local copy = {}
  for k, v in pairs(el) do copy[k] = v end
  if el.frame then
    copy.frame = { x = (el.frame.x or 0) + dx, y = (el.frame.y or 0) + dy,
                   w = el.frame.w, h = el.frame.h }
  end
  -- A segments element carries coordinates rather than a frame, so it is offset the
  -- same way. Copied into a new list, since the source list is the cached model and
  -- mutating it would move the block a little further on every repaint.
  if el.coordinates then
    local moved = {}
    for i, p in ipairs(el.coordinates) do
      moved[i] = { x = p.x + dx, y = p.y + dy }
    end
    copy.coordinates = moved
  end
  return copy
end

local function ensureCanvas()
  if canvas then return end
  canvas = hs.canvas.new(frame)
  canvas:level(hs.canvas.windowLevels.floating)
  -- A click on the pane must not pull focus off the search field. The atom's click
  -- watcher already treats a point inside the companion rect as part of the picker
  -- and passes it through, so between the two a click here changes nothing.
  canvas:clickActivating(false)
end

-- Compose the surface, the live block, and the cached static block, and show. Called by
-- a new highlight and by every sampler tick alike, and the only work it repeats is the
-- live block, which is two headings and two short polylines.
local function paint()
  -- The sampler ticks every 1.5 seconds while the list is showing, live or not. hidden is
  -- what stops that tick, or any other late redraw, from bringing the canvas back up
  -- beside a tool that is no longer current once M.hide has taken it down for a swap away.
  if hidden then return end
  if not (model and frame and cfg.surface) then return end
  ensureCanvas()
  local innerW = frame.w - 2 * PAD_X
  local innerH = frame.h - 2 * PAD_Y

  local els = {}
  for _, el in ipairs(cfg.surface(frame.w, frame.h)) do els[#els + 1] = el end
  -- Clip to the inner box, so a tree cut a line short of fitting still stops at the
  -- padding rather than crossing the border.
  els[#els + 1] = { type = "rectangle", action = "clip",
    frame = { x = PAD_X, y = PAD_Y, w = innerW, h = innerH } }

  for _, el in ipairs(liveBlock(model.row, innerW)) do
    els[#els + 1] = shifted(el, PAD_X, PAD_Y)
  end
  for _, el in ipairs(model.els) do
    els[#els + 1] = shifted(el, PAD_X, PAD_Y + model.liveH)
  end

  canvas:frame(frame)
  canvas:replaceElements(els)
  canvas:show()
end

--------------------------------------------------------------------------------
-- Public surface (dot-called)
--------------------------------------------------------------------------------

--- preview.configure(opts) - injected by the surface that owns the picker.
--- opts.surface    function(w, h) -> canvas elements, the shared CanvasPanel surface.
---                 Absent means no pane at all, see isEnabled.
--- opts.palette    function() -> the theme's preview colour set, resolved per open so
---                 the pane follows the live light and dark appearance.
--- opts.metrics    the live sampler, of which only reading(key) and history(key) are
---                 called. Injected rather than loaded here, because loadfile returns a
---                 fresh module each time and a second copy of the sampler would hold
---                 its own empty history and every sparkline would stay flat.
--- opts.formatCpu  the row's own percentage formatter, injected so the figure in the
---                 pane and the figure on the row can never round differently.
--- opts.emptyState function(w, h, opts) -> canvas elements, the shared CanvasPanel empty
---                 state, painted by clear below for a frame with nothing to preview.
---                 Absent falls back to hiding the canvas, the old behaviour, so a root
---                 that has not been updated to inject it degrades rather than breaking.
function M.configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  return M
end

--- preview.isEnabled() -> boolean
--- Whether a pane can be drawn at all, which is to say whether the composition root
--- injected the shared surface. The picker asks before reserving a companion rect, so a
--- root that wires nothing gets the picker exactly as it was rather than a pane of
--- unreadable text floating over the desktop with no background behind it.
function M.isEnabled()
  return cfg.surface ~= nil
end

--- preview.dock(companionFrame) - take the rect the Chooser atom reported.
--- Fired with a seed rect at show and again once the real window settles, so a re dock
--- is expected. The palette is resolved here rather than per highlight, since it can
--- only change between opens.
function M.dock(companionFrame)
  if not (M.isEnabled() and companionFrame) then return end
  frame = companionFrame
  -- A redock is the swap back M.hide guards against, so the pane may paint again from
  -- here on. The highlight seed the caller runs right after this call is what actually
  -- fills the pane, cold or not, a nil highlight landing in M.clear same as any other.
  hidden = false
  local p = (cfg.palette and cfg.palette()) or {}
  colors = {
    fg = hexColor(p.fg or "#dcdcdc"),
    meta = hexColor(p.meta or "#8a8a8a"),
    path = hexColor(p.path or "#7a7a7a"),
    note = hexColor(p.note or "#c8a86a"),
  }
  if model then
    -- The settle can correct the height, which changes where the tree has to stop.
    model = buildModel(model.row, frame.w - 2 * PAD_X, frame.h - 2 * PAD_Y)
    paint()
  end
end

--- preview.show(row) - render a row, or clear the pane when handed nothing.
--- The static half is rebuilt only when the row or its box changed, so this is cheap
--- enough to be called straight from the atom's highlight poll.
---
--- The cache is keyed on the row TABLE rather than on its key, which is what makes both
--- cases right at once. A poll that has not moved hands back the very same table and
--- pays nothing, while a rescan hands back a fresh one under the same key and rebuilds,
--- which it must, since a tree grows and shrinks between scans and the count under it
--- is the whole reason the pane is there.
function M.show(row)
  if not (M.isEnabled() and frame and colors) then return end
  if not row then
    M.clear()
    return
  end
  local w, h = frame.w - 2 * PAD_X, frame.h - 2 * PAD_Y
  if not (model and model.row == row and model.w == w and model.h == h) then
    model = buildModel(row, w, h)
  end
  paint()
end

--- preview.refresh() - redraw the row already on screen.
--- The seam the sampler tick uses. There is no timer here and none is wanted, the
--- surface already ticks once per sample and calls this, so the sparklines advance in
--- step with the figures on the rows and nothing polls twice.
function M.refresh()
  if model then paint() end
end

--- preview.clear() - the empty state, for a frame with nothing to preview, the empty
--- list row or a confirmation screen with no target.
---
--- This used to hide the canvas outright, on the reasoning that nothing to preview means
--- nothing to draw. That reads as a broken layout instead, a bordered rectangle reserved
--- beside the list with nothing in it, so the pane now stays up and paints the shared
--- empty state, the same quiet message every other docked pane shows in this moment,
--- rather than vanishing. The pane genuinely disappears only on the stage's own swap
--- signal, M.hide below, and on M.destroy.
function M.clear()
  model = nil
  if not (frame and colors and cfg.surface) then return end
  -- See paint's own note. A swap away must stay down through whatever clear the sampler
  -- or a rescan fires while nobody can see it.
  if hidden then return end
  if not cfg.emptyState then
    -- Absent means a misconfigured or partially configured module, so degrade by
    -- hiding rather than erroring.
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

--- preview.hide() - hide the canvas without destroying it, for the stage's own swap away
--- signal, onPositioned told nil twice when a different presentation becomes current. The
--- canvas, the frame, the colors and the model all survive, so a swap back to this
--- presentation docks again and repaints at once rather than rebuilding from nothing.
function M.hide()
  hidden = true
  if canvas then canvas:hide() end
end

--- preview.destroy() - tear the pane down completely.
--- Hooked to the picker's one teardown path, the same place the sampler stops, so no
--- dismissal leaves a canvas behind. Deleted rather than hidden because nothing may
--- survive a close, and rebuilding one canvas on the next open costs nothing.
function M.destroy()
  model = nil
  frame = nil
  colors = nil
  hidden = false
  if canvas then
    canvas:delete()
    canvas = nil
  end
end

return M
