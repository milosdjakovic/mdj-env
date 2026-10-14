--- What the processes detail pane looks like, as UI kit nodes and nothing else. It holds no
--- canvas, no sampler, no cache and no row source, only the shape of the live block, of the
--- sections a row carries and of the tree, so preview.lua can decide what to show and when to
--- draw it without knowing how any of it is built. The kit arrives as the first argument of
--- every function, since this file never loads it, which also lets the unit case drive it with
--- a bare kit and no canvas. Nothing here names a font, a size, a line height or a colour
--- literal, every piece of text is one of the kit's roles and every colour a role name.
---
--- The roles. Every heading is section, with its facts flush right in subtext. A port list, a
--- command line, an image name and a container id are the code role wrapped, since a person
--- copies them and a long one has to be read whole. The tree is a code block, cut at the width,
--- since a line of it is a line and a wrapped one would break the box drawing it exists to show.

local M = {}

-- The one gap between one block and the next, in the live block and in the static half.
M.GAP = "m"

-- Between a heading and what it heads.
M.HEADING_GAP = "xs"

-- The geometry of a graph rather than type, so these stay numbers. The strip is SPARK_H high,
-- with SPARK_GAP of air between its heading and its top.
M.SPARK_H = 20
M.SPARK_GAP = 3
-- Points per sample, so a short trail draws short rather than being stretched across the
-- full width and reading as far more history than there is. The newest sample sits
-- at the right edge and the trail grows leftward, which also means the pane needs to
-- know nothing about the sampler's history cap.
M.SPARK_STEP = 7
-- The CPU strip is scaled from zero to the window's peak, floored here, so a server
-- idling at a fraction of a percent draws along the bottom instead of having its noise
-- blown up into a mountain range.
M.CPU_FLOOR = 5

--------------------------------------------------------------------------------
-- The live block
--------------------------------------------------------------------------------

--- M.liveSpan(ui, row) -> points, how much room the live block takes at the top of the pane,
--- including the gap that separates it from the static half. Zero for a row that cannot be
--- sampled. It is derived from the role line height and the space steps rather than measured
--- from what was drawn, because it has to be known before the block is built, since it is what
--- the static half below is placed by, and it has to stay the same whether or not a sample has
--- landed yet, or the whole pane would jump the moment one does.
function M.liveSpan(ui, row)
  if not (row and row.pid) then return 0 end
  local T = ui.tokens()
  local block = T.text.section.lineHeight + T.space[M.HEADING_GAP] + M.SPARK_GAP + M.SPARK_H
  return 2 * block + 2 * T.space[M.GAP]
end

--- M.spark(ui, values, lo, hi, color) -> node, one strip. values is the trail, oldest first, lo and
--- hi the range the strip's height stands for, color a colour name for the line.
---
--- The baseline is always drawn, so a row with no history yet reads as waiting rather than as
--- a gap in the pane. A range that has collapsed to nothing draws down the middle, which reads
--- as steady rather than as pinned at either edge. The baseline is the border colour, the same
--- rule colour a divider is drawn in.
function M.spark(ui, values, lo, hi, color)
  return ui.raw(M.SPARK_GAP + M.SPARK_H, function(rect, tokens)
    local top = rect.y + M.SPARK_GAP
    local base = top + M.SPARK_H
    local els = { { type = "segments", action = "stroke", strokeWidth = 1,
      strokeColor = tokens.colors.border,
      coordinates = { { x = rect.x, y = base }, { x = rect.x + rect.w, y = base } } } }
    if #values < 2 then return els end

    local step = math.min(M.SPARK_STEP, rect.w / (#values - 1))
    local span = hi - lo
    local coordinates = {}
    for i, v in ipairs(values) do
      -- Anchored at the right edge, so the newest sample is always in the same place and
      -- the trail extends back into the pane as far as there is history for it.
      local x = rect.x + rect.w - (#values - i) * step
      local frac = (span > 0) and ((v - lo) / span) or 0.5
      coordinates[i] = { x = x, y = base - frac * (M.SPARK_H - 1) }
    end
    els[#els + 1] = { type = "segments", action = "stroke", strokeWidth = 1.5,
      strokeColor = tokens.colors[color], strokeCapStyle = "round", coordinates = coordinates }
    return els
  end)
end

--- M.live(ui, row, spec) -> node or nil, the live half. Nil for a row with no pid, which is
--- not sampled and reserves nothing. spec is { cpu = strip, mem = strip }, each strip being
--- { facts, values, lo, hi }, the text flush right of its heading, the trail and its range.
--- The CPU line is the primary accent and the memory line the secondary, the first and second
--- series in the order the accents are taken.
---
--- Its height is M.liveSpan less the closing gap, and it is the same whatever the spec holds.
function M.live(ui, row, spec)
  if not (row and row.pid) then return nil end
  local function block(label, strip, color)
    return ui.stack({
      ui.heading(label, strip.facts),
      M.spark(ui, strip.values, strip.lo, strip.hi, color),
    }, { gap = M.HEADING_GAP })
  end
  return ui.stack({
    block("CPU", spec.cpu, "primary"),
    block("MEMORY", spec.mem, "secondary"),
  }, { gap = M.GAP })
end

--------------------------------------------------------------------------------
-- The sections, one per thing the row carries
--------------------------------------------------------------------------------

local HOME = os.getenv("HOME") or ""

-- Home shortened to a tilde. The pane is read, not copied from, and the first thirty
-- characters of every path being identical costs width the project part needs.
local function tildePath(path)
  if HOME ~= "" and path:sub(1, #HOME) == HOME then return "~" .. path:sub(#HOME + 1) end
  return path
end

-- What a section's tone is drawn in, a colour name of the kit. The tones are this file's own
-- words for three emphases, so a section says how loud it is and not which colour.
local TONES = { fg = "foreground", path = "subtext", meta = "subtext" }

-- The sections, in reading order. Each one names its heading, the tone its value is drawn
-- in, and a builder that returns the text or nothing at all. Returning nothing drops the
-- whole section including its heading, which is the single rule that keeps every shape of row
-- free of empty labelled space, rather than a branch per source that this file would have to
-- grow.
--
-- A heading is a function where the row decides the wording. A row carrying a container id is
-- a container, so its command field holds an image name rather than a command line, and it is
-- labelled for what it is. That tests a field the row carries rather than the name of the
-- source that produced it, which is the same way the rest of the pane decides what to draw.
M.SECTIONS = {
  {
    label = "PORTS",
    tone = "fg",
    -- Joined with the dot the row subtitle already separates facts by, so the two read alike.
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

--- M.sections(ui, row) -> a list of nodes, one per section the row has text for, in reading
--- order, empty when it has none. Each is a heading over its text in the code role, wrapped.
function M.sections(ui, row)
  local out = {}
  for _, section in ipairs(M.SECTIONS) do
    local text = section.text(row)
    if text and text ~= "" then
      out[#out + 1] = ui.stack({
        ui.heading(headingOf(section, row)),
        ui.text(text, "code", { wrap = true, color = TONES[section.tone] }),
      }, { gap = M.HEADING_GAP })
    end
  end
  return out
end

--------------------------------------------------------------------------------
-- The tree
--------------------------------------------------------------------------------

--- M.treeLines(tree, pidWidth) -> the drawn lines. Turns the flat member list into tree
--- lines. The source hands over a pre order walk carrying a depth per member, which is enough
--- to reconstruct the shape, and every prefix unit is exactly three columns wide.
---
--- Whether a member is the last of its siblings is not on the member, so it is read from the
--- walk. The next member at the same depth before any shallower one means more siblings
--- follow, and that single lookahead decides both the corner it draws and whether its own
--- children carry a continuation bar past it.
---
--- A label is never cut here. The code block cuts each line at the pane width, the pid sits
--- before the label, so a cut only ever takes the end of a label and the column stays lined up.
function M.treeLines(tree, pidWidth)
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
    lines[#lines + 1] = drawn .. pid .. (member.label or "")
  end
  return lines
end

--- M.tree(ui, row, w, availH) -> node or nil, the tree section given whatever vertical room
--- the sections above it left, availH, at the width w.
---
--- It is last in the pane because it is the one section that can be any length, so it is also
--- the one that can absorb the leftover space instead of forcing a scroll into a pane that has
--- no scroll bindings. Past the room available it is cut with a count of what was cut, and when
--- there is no room for even one member the section is dropped whole rather than printing a
--- heading over nothing. The heading's own height is measured through the layout rather than
--- assumed, so the room the members get is what is really left.
---
--- The count is the scan's view of the group. A stop re reads the group live before
--- signalling it, so a tree that grew since the scan is still taken whole, and this
--- number is what the picker knew rather than a promise.
function M.tree(ui, row, w, availH)
  local tree = row.tree or {}
  if #tree == 0 then return nil end

  local facts = string.format("stops %d process%s", #tree, #tree == 1 and "" or "es")
  local heading = ui.heading("TREE", facts)
  local _, headH = ui.layout(heading, { x = 0, y = 0, w = w, h = availH })
  local T = ui.tokens()
  local room = availH - headH - T.space[M.HEADING_GAP]
  if room < T.text.code.lineHeight then return nil end

  local widest = 0
  for _, member in ipairs(tree) do
    widest = math.max(widest, #tostring(member.pid or "?"))
  end
  return ui.stack({
    heading,
    ui.code(M.treeLines(tree, widest), {
      maxHeight = room,
      more = function(count) return string.format("… %d more", count) end,
    }),
  }, { gap = M.HEADING_GAP })
end

--- M.static(ui, row, w, h) -> node or nil, everything the row itself says, the sections and
--- then the tree, in a box w wide and h high. Nil when the row has nothing to say.
---
--- The tree's room is what the sections leave, and the sections' height is measured through the
--- layout rather than summed, since a wrapped command is as tall as the pane is wide.
function M.static(ui, row, w, h)
  local parts = M.sections(ui, row)
  local used = 0
  if #parts > 0 then
    local _, sectionsH = ui.layout(ui.stack(parts, { gap = M.GAP }), { x = 0, y = 0, w = w, h = h })
    used = sectionsH + ui.tokens().space[M.GAP]
  end
  local tree = M.tree(ui, row, w, h - used)
  if tree then parts[#parts + 1] = tree end
  if #parts == 0 then return nil end
  return ui.stack(parts, { gap = M.GAP })
end

return M
