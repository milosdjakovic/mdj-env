--- What the file search side pane looks like, as UI kit nodes and nothing else. It holds no
--- canvas, no stat, no thumbnail and no row, only the shape of the header and of each kind of
--- body, so sidepanel.lua can decide what a row has and compose it without knowing how any of
--- it is drawn. The kit arrives as the first argument of every function, since this file never
--- loads it, which also lets the unit case drive it with a bare kit and no hs. Nothing here
--- names a font, a size, a line height or a colour literal, every piece of text is one of the
--- kit's roles and every colour a role name.
---
--- The roles. The file name is title, the folder it lives in is code in the path colour, each
--- fact is a caption pair, a heading is section, and a file head or a folder listing is the
--- code role, the same choice the clipboard pane makes for its own text, so a file looks the
--- same in both panes.

local M = {}

-- The one gap between the identity, the facts and the body.
M.GAP = "m"

-- Between a heading and what it heads.
M.HEADING_GAP = "xs"

--- M.wrapBlock(ui, lines, w) -> the drawn lines, every source line wrapped at w by the kit's
--- measurer in the code role's own font and size. The measurer keeps indentation and expands
--- tabs the way the code block draws them, so the drawn lines are what a code block draws one for
--- one, which is what makes a budget counted in them exact without any arithmetic on columns.
function M.wrapBlock(ui, lines, w)
  local code = ui.tokens().text.code
  local out = {}
  for _, line in ipairs(lines) do
    for _, part in ipairs(ui.measure:wrap(line, code.font, code.size, w)) do
      out[#out + 1] = part
    end
  end
  return out
end

--- M.remainderNote(overLines, shownBytes, total, hasLines) -> string or nil, what is being
--- left out, said in the units that are actually known.
---
--- A count of lines is only honest when the file has lines. A minified bundle is one line of a
--- hundred thousand characters, so telling you seven hundred more lines would be describing the
--- wrapping rather than the file. Characters is true whatever the shape, and it comes from the
--- stat, so it counts the whole file rather than only the part that was read.
---
--- The character figure is measured against the bytes drawn, so it is off by a line ending here
--- and an expanded tab there, well under a percent on any real file. It says roughly how much
--- more there is, which is the question, and pretending to an exact figure would cost a second
--- pass for nothing.
function M.remainderNote(overLines, shownBytes, total, hasLines)
  local parts = {}
  if hasLines and overLines > 0 then
    parts[#parts + 1] = string.format("%d lines", overLines)
  end
  if total and total > shownBytes then
    parts[#parts + 1] = string.format("%d characters", total - shownBytes)
  end
  if #parts == 0 then return nil end
  return table.concat(parts, ", ") .. " more"
end

-- A label at the left and a value flush against the right edge, as one row. The label keeps
-- its natural width and the value takes the rest, so the value is never the one cut and one
-- read down a column starts in the same place on every line.
local function labelled(ui, label, labelColor, value, valueColor, role)
  return ui.row({
    ui.text(label, role, { color = labelColor }),
    ui.text(value, role, { color = valueColor, align = "right" }),
  }, { fillIndex = 2 })
end

--- M.pair(ui, label, value, valueColor) -> node, one fact. The label in subtext, the value in
--- the foreground unless valueColor names another.
function M.pair(ui, label, value, valueColor)
  return labelled(ui, label, "subtext", value, valueColor or "foreground", "caption")
end

--- M.header(ui, name, dir, pairs) -> node, everything true of every row. The name, where it
--- lives when it lives anywhere worth saying, then the facts. pairs is an array of
--- { label, value, color }, in the order they are drawn.
function M.header(ui, name, dir, pairs)
  local identity = { ui.text(name, "title", { color = "foreground" }) }
  if dir and dir ~= "" then
    identity[#identity + 1] = ui.text(dir, "code", { wrap = true, color = "path" })
  end
  local facts = {}
  for i, pair in ipairs(pairs) do facts[i] = M.pair(ui, pair.label, pair.value, pair.color) end
  return ui.stack({ ui.stack(identity, { gap = M.HEADING_GAP }), ui.stack(facts) },
    { gap = M.GAP })
end

--- M.body(ui, body, w) -> node, one body as the describers answer it, wrapped at w.
---
--- Wrapped before the heading is written, so the heading can say what was left out. The
--- describer cannot say it, because whether a budget counted in drawn lines is reached depends
--- on how wide the pane turned out.
---
--- The slack is the point of the budget. A budget with a hard edge means a file four lines over
--- it loses those four lines and gains a notice about them, which is a worse thing to read than
--- the four lines were. So the budget is where the trim lands and the slack is how far past it a
--- file is simply shown whole. Anything up to budget plus slack is complete and says nothing,
--- and only past that is it worth trimming and worth mentioning.
function M.body(ui, body, w)
  if body.image then
    return ui.stack({ ui.heading(body.label, body.facts), ui.image(body.image, { upscale = false }) },
      { gap = M.HEADING_GAP })
  end

  local lines = body.lines or {}
  if body.wrap then lines = M.wrapBlock(ui, lines, w) end

  local budget, slack = body.budget, body.slack or 0
  local note, shown = nil, #lines
  if budget and #lines > budget + slack then
    local kept, bytes = {}, 0
    for i = 1, budget do
      kept[i] = lines[i]
      bytes = bytes + #lines[i] + 1
    end
    local over = #lines - budget
    shown = budget
    -- The ellipsis is a line of the body rather than part of the note, so it sits in the body
    -- tone at the end of the text and reads as the text stopping, which is what it means.
    kept[#kept + 1] = "..."
    lines = kept
    note = M.remainderNote(over, bytes, body.total, body.hasLines)
  end

  local facts = body.facts
  if note and not facts then facts = string.format("first %d lines", shown) end
  local heading = ui.heading(body.label, facts)
  if #lines == 0 then return heading end

  -- The code block draws only the lines inside the scrolled window, which is what keeps a long
  -- head cheap, since a clip bounds what is visible and not what is laid out. The note sits
  -- directly under the last line, in its own stack with no gap, so scrolling to the bottom
  -- reaches it.
  local block = { ui.code(lines) }
  if note then block[#block + 1] = ui.text(note, "caption", { color = "subtext" }) end
  return ui.stack({ heading, ui.stack(block) }, { gap = M.HEADING_GAP })
end

return M
