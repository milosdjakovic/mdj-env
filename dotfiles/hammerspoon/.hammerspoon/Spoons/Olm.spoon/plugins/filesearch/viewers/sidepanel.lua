--- The docked side panel, one of the two preview providers.
---
--- The companion pane docked beside the picker, describing the highlighted row. A row is
--- one line and one line cannot answer the two questions asked before pressing Return.
--- Which of the four files called init.lua this one is, and whether it is the thing you
--- had in mind. The subtitle answers the first as far as a line can, and this answers the
--- second by showing what is actually inside.
---
--- It also owns the facts a list cannot afford. Reading a size or a date costs a call per
--- row and a page is two hundred rows, while this describes exactly one, so it stats that
--- one and reports everything the call already returned.
---
--- It is a canvas of its own rather than a CanvasPanel instance, the same choice the
--- clipboard preview and the Processes pane make and for the same reason. A CanvasPanel
--- computes its own placement from an anchor and sizes itself from its content, while this
--- pane must land exactly on the companion rect the Chooser atom already reserved and
--- reported. Drawing it anywhere else would put it outside the rect the atom's click
--- watcher treats as part of the picker, so a click on the pane would dismiss the picker
--- rather than being passed through. What it does share is the surface itself, injected as
--- CanvasPanel.surfaceElements, so the pane, the docked shortcut panel and the cheat
--- sheets are one component drawn in several places rather than lookalikes.
---
--- Dot called, and it holds no policy. The surface routine, the palette, the limits, the
--- last used lookup and the thumbnail chain are all injected by the surface that owns the
--- picker, so this file names nothing concrete.
---
--- WHAT THE BODY SHOWS IS A CHAIN OF RESPONSIBILITY, see BODIES below. Each describer is
--- offered the row and either answers with something to draw or declines, and the first
--- answer wins. Declining is a real part of it rather than an error path, since a text
--- file that cannot be opened and an image type with no generator behind it both have to
--- fall through to the row being described by its facts alone. Adding a kind of file this
--- pane can show is a new describer plus one line in that list.
---
--- The header is not part of the chain. It draws for every row, because a name, a location
--- and a handful of dates are true of everything, and a pane that sometimes had no header
--- would be answering a different question per row.
---
--- IT FOLLOWS THE HIGHLIGHT, which is the property that separates it from the other provider
--- rather than an incidental detail. A canvas already on screen redraws for nothing, so it can
--- track the poll and cost only a timer, and that is what makes a permanent summary in the
--- corner of your eye affordable at all. See viewers/quicklook.lua for the opposite case.

-- A viewer sits one directory below the spoon root, so its siblings are one level up.
local viewerPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local util = loadfile(viewerPath .. "../util.lua")()

local M = {}

--- viewer.name - for the console line when a provider steps aside.
M.name = "sidepanel"

--- viewer.followsHighlight - true, see the header. The surface reads this to decide whether to
--- run a highlight poll and to wire the scroll keys.
M.followsHighlight = true

-- Injected, see M.configure. Empty until then, and with no surface injected the pane
-- stays down entirely, which is the whole degradation path, see M.available.
local cfg = {}

local canvas = nil       -- the docked canvas, built lazily and deleted on every close
local frame = nil        -- the companion rect the atom reported, where the canvas docks
local colors = nil       -- the palette, resolved once per open rather than per highlight
local model = nil        -- the row on screen, laid out, see buildModel
local scrollOffset = 0   -- how far down the body, in points, clamped at paint
local pending = 0        -- the generation of the newest thumbnail request, see requestImage

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

-- The padding matches the shortcut panel, the clipboard preview and the Processes pane,
-- CanvasPanel's 14 and 10, so every surface sharing the screen shares its inner margin.
local PAD_X, PAD_Y = 14, 10

-- One monospace font throughout, so a wrap can be measured by column arithmetic rather
-- than by measuring every string, and so a file's own indentation survives being shown.
-- A proportional font would bend the head of a source file out of shape, which is most of
-- what this pane draws.
local FONT = "Menlo"
local NAME_SIZE, LABEL_SIZE, BODY_SIZE = 13, 11, 11
local LINE_MULT = 1.35
local BLOCK_GAP = 12    -- between one block and the next
local HEADING_GAP = 2   -- between a heading and what it heads

local function lineHeight(size)
  return math.ceil(size * LINE_MULT)
end

local LABEL_H = lineHeight(LABEL_SIZE)

--------------------------------------------------------------------------------
-- Text and colour helpers
--------------------------------------------------------------------------------

local function hexColor(hex)
  local r, g, b = tostring(hex):match("#?(%x%x)(%x%x)(%x%x)")
  if not r then return { white = 0.85, alpha = 1 } end
  return { red = tonumber(r, 16) / 255, green = tonumber(g, 16) / 255,
           blue = tonumber(b, 16) / 255, alpha = 1 }
end

-- A styled run with a pinned line height, so the drawn height matches the line count
-- exactly and every block below lands where the layout said it would.
--
-- Every run truncates rather than wraps, which is a safety net rather than a look. The
-- blocks here are wrapped by column arithmetic against an averaged character width, so a
-- line measuring a shade wider than the estimate would otherwise wrap itself, silently
-- taking one more line than the layout accounted for and pushing everything below it down.
local function styled(text, color, size, align)
  local lineH = lineHeight(size)
  return hs.styledtext.new(text or "", {
    font = { name = FONT, size = size },
    color = color,
    paragraphStyle = { maximumLineHeight = lineH, minimumLineHeight = lineH,
                       alignment = align, lineBreak = "truncateTail" },
  })
end

-- Monospace character width per size, measured once from a run so any per glyph padding
-- averages out. This is the unit the column budgets are counted in.
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

-- Wrap one line to a column budget, breaking at the last space that fits and hard
-- breaking a token longer than the whole line, which is what a long path with no spaces
-- in it needs. Tabs are expanded first, since a tab drawn in a monospace run is one cell
-- wide and would collapse the indentation this pane exists to show.
--
local function wrapMono(str, cols)
  str = tostring(str):gsub("\t", "  ")
  local lines, pos, n = {}, 1, #str
  if n == 0 then return { "" } end
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

-- Wrap a block of source lines to a column budget.
--
-- Everything read is wrapped, deliberately, and the trim happens after. The input is already
-- bounded by the read cap, so this is a few thousand iterations at worst, and wrapping all of
-- it is what makes the count of what is being left out an exact number rather than an estimate.
-- What is NOT affordable is drawing all of it, which is a different layer and is handled in
-- paint.
local function wrapBlock(lines, cols)
  local out = {}
  for _, line in ipairs(lines) do
    for _, part in ipairs(wrapMono(line, cols)) do out[#out + 1] = part end
  end
  return out
end

-- What is being left out, said in the units that are actually known.
--
-- A COUNT OF LINES IS ONLY HONEST WHEN THE FILE HAS LINES. A minified bundle is one line of a
-- hundred thousand characters, so telling you seven hundred more lines would be describing the
-- wrapping rather than the file. Characters is true whatever the shape, and it comes from the
-- stat, so it counts the whole file rather than only the part that was read.
--
-- The character figure is measured against the bytes drawn, so it is off by a line ending here
-- and an expanded tab there, well under a percent on any real file. It says roughly how much
-- more there is, which is the question, and pretending to an exact figure would cost a second
-- pass for nothing.
local function remainderNote(lines, overLines, shownBytes, total, hasLines)
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

-- A block of text as one canvas element rather than one per line. The pinned line height
-- makes the joined run's drawn height exactly the line count, and one element keeps a
-- repaint cheap where a long file head would otherwise cost dozens.
local function appendLines(els, lines, y, w, color, size)
  if #lines == 0 then return y end
  local lineH = lineHeight(size)
  local h = #lines * lineH
  els[#els + 1] = { type = "text", text = styled(table.concat(lines, "\n"), color, size),
    frame = { x = 0, y = y, w = w, h = h + lineH } }
  return y + h
end

-- A label at the left with a value flush against the right edge. Two anchors rather than
-- one padded run, because a value read down a column has to start in the same place on
-- every line and a padded run in a wrapped block cannot promise that.
local function appendPair(els, label, value, y, w, valueColor)
  els[#els + 1] = { type = "text", text = styled(label, colors.meta, LABEL_SIZE),
    frame = { x = 0, y = y, w = w, h = LABEL_H * 2 } }
  els[#els + 1] = { type = "text", text = styled(value, valueColor or colors.fg, LABEL_SIZE, "right"),
    frame = { x = 0, y = y, w = w, h = LABEL_H * 2 } }
  return y + LABEL_H
end

-- A section heading, with an optional right hand fact. Same two anchors as a pair, in the
-- meta tone on both sides, so a heading reads as a heading rather than as another field.
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
-- What the row is
--------------------------------------------------------------------------------

-- One stat per row, held for as long as the pane is describing it. The highlight fires
-- from a poll, so this must not be asked again on every fire, and the answer cannot go
-- stale under a pane that is only up for a few seconds.
local function statOf(row)
  if not (row and row.path) then return nil end
  return hs.fs.attributes(row.path)
end

-- What kind of thing this is, in one word.
--
-- Taken from the extension rather than from the system's own type description, which
-- Hammerspoon does not expose, and left as the extension itself when it names no family.
-- Naming families here would mean a second copy of the type table in config, which the
-- reader of this line gains nothing from.
local function kindOf(row, attrs)
  if attrs and attrs.mode == "link" then return "Alias" end
  if row.isDir then
    if (row.ext or "") == "app" or (row.name or ""):match("%.app$") then return "Application" end
    return "Folder"
  end
  local ext = row.ext or ""
  if ext == "" then return "File" end
  return ext:upper()
end

--------------------------------------------------------------------------------
-- The body, a Chain of Responsibility over the kinds of file this pane can show
--------------------------------------------------------------------------------

-- How far into a directory the listing looks. The count over the heading is what it found
-- within this many entries, reported as an "or more" past it, because a directory holding
-- a hundred thousand entries would otherwise cost a full walk to put one number on screen.
local DIR_SCAN_CAP = 2000

-- A directory, listed newest first, the same order the picker's own browse uses so the
-- pane and the list never disagree about what the top of a folder is.
--
-- Newest first needs a date per entry, so this stats what it lists. That is a real cost
-- and it is affordable only because it is bounded twice, by the scan cap above and by the
-- entry count from config, and because it happens for one row rather than for a page.
local function folderBody(row, attrs, ctx)
  if not row.isDir then return nil end
  -- The whole read is guarded, because hs.fs.dir RAISES on a directory it cannot open rather
  -- than returning nil, and the iterator can raise part way through as well. A row naming a
  -- folder that no longer exists is ordinary here, since the index can be stale and the recent
  -- list outlives what it lists, and this runs inside the highlight poll where an error would
  -- be an unhandled one. Failing means declining, so such a row is described by its header.
  local entries, scanned, truncated = {}, 0, false
  local ok = pcall(function()
    local iter, dirObj = hs.fs.dir(row.path)
    for name in iter, dirObj do
      if name ~= "." and name ~= ".." then
        scanned = scanned + 1
        if scanned > DIR_SCAN_CAP then
          truncated = true
          break
        end
        local full = row.path:gsub("/+$", "") .. "/" .. name
        local a = hs.fs.attributes(full)
        entries[#entries + 1] = {
          name = (a and a.mode == "directory") and (name .. "/") or name,
          at = (a and a.modification) or 0,
        }
      end
    end
  end)
  if not ok then return nil end
  if #entries == 0 then
    return { label = "FOLDER", facts = "empty", lines = {} }
  end
  table.sort(entries, function(a, b) return a.at > b.at end)

  local cap = ctx.folderEntries
  local lines = {}
  for i = 1, math.min(cap, #entries) do
    lines[#lines + 1] = entries[i].name
  end
  local facts = string.format("%d%s item%s", scanned, truncated and "+" or "",
    (scanned == 1 and not truncated) and "" or "s")
  return { label = "FOLDER", facts = facts, lines = lines, wrap = false }
end

-- Anything with a picture behind it, which is decided by the injected thumbnail chain
-- rather than here, so this file learns nothing about image formats or about Quick Look.
-- Gated on the extension rather than on sniffed content on purpose, and ahead of the text
-- describer, so an svg is drawn rather than having its markup printed.
--
-- The image is asked for asynchronously and may not be ready, in which case the section
-- says so and the pane repaints itself when it lands. See requestImage.
local function imageBody(row, attrs, ctx)
  if row.isDir or not cfg.thumbs then return nil end
  if not cfg.thumbs.handles(row.ext or "") then return nil end
  local img, note = ctx.image(row, attrs)
  if img then return { label = "PREVIEW", image = img } end
  return { label = "PREVIEW", facts = note }
end

-- A text file, which is decided by looking rather than by an extension table, so a source
-- file, a json, a markdown and a config with no extension at all are all covered without
-- any of them being listed anywhere. A NUL byte in the first block is what says otherwise,
-- since text does not contain one and nearly every binary format does.
--
-- Read synchronously and bounded to the configured cap. That is a deliberate exception to
-- this spoon's rule that nothing blocks, because the read is a few tens of kilobytes off a
-- local disk and going asynchronous would mean a task per highlight fire. The case it
-- would cost is a file on a slow network mount, where the pane would stall for as long as
-- the read takes.
local function textBody(row, attrs, ctx)
  if row.isDir then return nil end
  if attrs and attrs.size == 0 then return { label = "HEAD", facts = "empty file", lines = {} } end
  local f = io.open(row.path, "rb")
  if not f then return nil end
  local blob = f:read(ctx.readCap)
  f:close()
  if not blob or blob == "" then return nil end
  if blob:find("\0", 1, true) then return nil end

  -- Every line the read got, with no cap of its own. The read cap is the bound, and it is the
  -- only one that can be, because a cap counted in source lines would stop a hundred thousand
  -- character single line file after one line and stop a normal file before the end of what was
  -- already paid for. Bounding here also used to make the count of what is left out a guess,
  -- since nothing downstream could know how much was never looked at.
  --
  -- The terminator is added only when it is missing, which matters more than it looks. Adding
  -- one unconditionally gives a file that already ends in a newline a phantom empty last line,
  -- an invisible blank while nothing counted the lines and an off by one the moment something
  -- did, reporting five hundred and one lines left where five hundred were. A file genuinely
  -- ending in a blank line still keeps it, since only the terminator is supplied.
  local text = blob
  if text:sub(-1) ~= "\n" then text = text .. "\n" end
  local lines = {}
  for line in text:gmatch("([^\n]*)\n") do
    lines[#lines + 1] = (line:gsub("\r$", ""))
  end
  -- A last line cut mid way through by the read cap is dropped rather than shown, since half a
  -- line of source reads as a file that ends strangely. Only when there is a whole line to fall
  -- back on, and a minified file is exactly the case where there is not, since the read cap
  -- lands in the middle of its only line.
  local capped = #blob >= ctx.readCap
  if capped and #lines > 1 then table.remove(lines) end
  -- The budget is handed over rather than applied here, because it has to be counted in DRAWN
  -- lines and only the layout knows how a source line wraps.
  return {
    label = "HEAD", lines = lines, wrap = true,
    budget = ctx.headLines, slack = ctx.headSlack,
    total = attrs and attrs.size,
    -- Whether a count of lines would mean anything. It takes both, a file that really has
    -- lines, and a read that reached the end so the count is of the file rather than of the
    -- window we happened to read.
    hasLines = (#lines > 1) and not capped,
  }
end

-- In order. The first one to answer owns the body, and one that declines passes the row
-- along, which is what leaves a binary with no generator behind it described by its facts
-- alone rather than by an empty labelled box.
local BODIES = { folderBody, imageBody, textBody }

--------------------------------------------------------------------------------
-- Laying a row out
--------------------------------------------------------------------------------

-- The header, everything true of every row. The name, where it lives, then the facts.
--
-- Both ages are LABELLED, the same fix the row subtitle carries, because a bare age reads
-- as something you did and a file a build wrote four days ago is not a file you touched
-- four days ago. When you last reached for it comes first, since it is the field that
-- explains why the row is where it is.
local function headerElements(row, attrs, w)
  local els, y = {}, 0
  els[#els + 1] = { type = "text", text = styled(row.name or row.path, colors.fg, NAME_SIZE),
    frame = { x = 0, y = y, w = w, h = lineHeight(NAME_SIZE) * 2 } }
  y = y + lineHeight(NAME_SIZE)

  local dir = util.shortDir(row.dir)
  if dir ~= "" then
    y = appendLines(els, wrapMono(dir, columns(w, LABEL_SIZE)), y, w, colors.path, LABEL_SIZE)
  end
  y = y + BLOCK_GAP

  y = appendPair(els, "KIND", kindOf(row, attrs), y, w)
  -- No size for a directory. A directory's own byte count is the size of the entry that
  -- holds its names, which is not the question anyone is asking, and the folder section
  -- below carries the count that is.
  if attrs and attrs.size and not row.isDir then
    y = appendPair(els, "SIZE", util.humanBytes(attrs.size), y, w)
  end
  if attrs and attrs.modification then
    y = appendPair(els, "CHANGED", util.humanAge(attrs.modification), y, w)
  end
  if attrs and attrs.creation then
    y = appendPair(els, "ADDED", util.humanAge(attrs.creation), y, w)
  end
  local usedAt = cfg.usedAt and row.path and cfg.usedAt(row.path)
  if usedAt then
    -- In the accent tone, because it is the one fact on the pane that is about you rather
    -- than about the file.
    y = appendPair(els, "USED", util.humanAge(usedAt), y, w, colors.note)
  end
  return els, y + BLOCK_GAP
end

-- The body's own elements, laid out in a box of their own starting at zero, so the paint
-- can offset them by the scroll without the builder knowing anything about it.
local function bodyElements(body, w)
  local els, y = {}, 0
  if body.image then
    y = appendHeading(els, body.label, body.facts, y, w)
    local size = body.image:size()
    -- Scaled to the width and never past its own size, so a small icon is drawn at the
    -- size it really is rather than blown up into a blur.
    local drawW = math.min(w, size.w)
    local drawH = size.h * (drawW / size.w)
    els[#els + 1] = { type = "image", image = body.image, imageScaling = "scaleProportionally",
      imageAlignment = "topLeft", frame = { x = 0, y = y, w = drawW, h = drawH } }
    return els, y + drawH
  end
  -- Wrapped before the heading is written, so the heading can say what was left out. The
  -- describer cannot say it, because whether a budget counted in drawn lines is reached
  -- depends on how wide the pane turned out.
  local lines = body.lines or {}
  if body.wrap then lines = wrapBlock(lines, columns(w, BODY_SIZE)) end

  -- THE SLACK IS THE POINT OF THIS BLOCK. A budget with a hard edge means a file four lines
  -- over it loses those four lines and gains a notice about them, which is a worse thing to
  -- read than the four lines were. So the budget is where the trim lands and the slack is how
  -- far past it a file is simply shown whole. Anything up to budget plus slack is complete and
  -- says nothing, and only past that is it worth trimming and worth mentioning.
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
    note = remainderNote(lines, over, bytes, body.total, body.hasLines)
  end

  local facts = body.facts
  if note and not facts then facts = string.format("first %d lines", shown) end
  y = appendHeading(els, body.label, facts, y, w)

  -- The text block is DESCRIBED rather than built, so the paint can draw only the lines
  -- that are actually on screen. Everything above is a fixed handful of elements and is
  -- built here as before. See the note on paint for why the difference matters.
  local run = nil
  if #lines > 0 then
    run = { lines = lines, y = y, size = BODY_SIZE, color = colors.fg,
            lineH = lineHeight(BODY_SIZE), note = note }
    y = y + #lines * run.lineH
    -- Room for the note under the last line, so scrolling to the bottom reaches it.
    if note then y = y + run.lineH end
  end
  return els, y, run
end

-- Everything for one row, built once and cached, since the highlight poll fires often and
-- nothing here changes under it. Keyed on the path and the box, so a re dock at the
-- corrected frame rebuilds and a poll that has not moved pays nothing.
local function buildModel(row, w, h)
  local attrs = statOf(row)
  local headEls, bodyY = headerElements(row, attrs, w)
  local body, bodyEls, bodyH, bodyRun = nil, {}, 0, nil
  local limits = cfg.limits or {}
  local ctx = {
    readCap = limits.readCap or 64 * 1024,
    headLines = limits.headLines or 400,
    headSlack = limits.headSlack or 20,
    folderEntries = limits.folderEntries or 100,
    image = function(r, a) return M._image(r, a) end,
  }
  for _, describe in ipairs(BODIES) do
    body = describe(row, attrs, ctx)
    if body then break end
  end
  if body then bodyEls, bodyH, bodyRun = bodyElements(body, w) end
  return {
    row = row, path = row.path, w = w, h = h, attrs = attrs,
    headEls = headEls, bodyY = bodyY, bodyEls = bodyEls, bodyH = bodyH, bodyRun = bodyRun,
  }
end

--------------------------------------------------------------------------------
-- Painting
--------------------------------------------------------------------------------

-- A shallow copy of an element with its frame offset, so a block built in its own (0, 0)
-- box can be placed absolutely without the builder knowing where it landed.
local function shifted(el, dx, dy)
  local copy = {}
  for k, v in pairs(el) do copy[k] = v end
  if el.frame then
    copy.frame = { x = (el.frame.x or 0) + dx, y = (el.frame.y or 0) + dy,
                   w = el.frame.w, h = el.frame.h }
  end
  return copy
end

local function ensureCanvas()
  if canvas then return end
  canvas = hs.canvas.new(frame)
  canvas:level(hs.canvas.windowLevels.floating)
  -- A click on the pane must not pull focus off the search field. The atom's click watcher
  -- already treats a point inside the companion rect as part of the picker and passes it
  -- through, so between the two a click here changes nothing.
  canvas:clickActivating(false)
end

-- Compose the surface, the header and the body, and show.
--
-- The body is clipped to what is left below the header and drawn at the scroll offset,
-- which is clamped HERE rather than where it is changed. That is what lets a key press, a
-- trackpad gesture and a rebuild at a new height all be written without any of them
-- knowing how tall the content turned out.
--
-- ONLY THE LINES ON SCREEN ARE DRAWN, and that is not an optimisation to be simplified
-- away. A clip bounds what is VISIBLE and not what is laid out, so handing the canvas the
-- whole block made every paint cost the whole file, and a paint happens on every scroll
-- event. Measured with a heartbeat timer, a four hundred line body stalled the main thread
-- for fifty to a hundred milliseconds per paint and dropped half the frames of a scroll,
-- while the same body windowed to the thirty visible lines costs nothing above the idle
-- floor whatever the file is. The run is rebuilt per paint rather than cached, which is
-- affordable exactly because it is only ever the visible slice.
local function paint()
  if not (model and frame and cfg.surface) then return end
  ensureCanvas()
  local innerW = frame.w - 2 * PAD_X
  local innerH = frame.h - 2 * PAD_Y
  local bodyRoom = innerH - model.bodyY

  local overflow = math.max(0, model.bodyH - bodyRoom)
  if scrollOffset > overflow then scrollOffset = overflow end
  if scrollOffset < 0 then scrollOffset = 0 end

  local els = {}
  for _, el in ipairs(cfg.surface(frame.w, frame.h)) do els[#els + 1] = el end
  els[#els + 1] = { type = "rectangle", action = "clip",
    frame = { x = PAD_X, y = PAD_Y, w = innerW, h = innerH } }
  for _, el in ipairs(model.headEls) do els[#els + 1] = shifted(el, PAD_X, PAD_Y) end

  if bodyRoom > 0 and (#model.bodyEls > 0 or model.bodyRun) then
    -- A second clip, so a body scrolled up stops at the header rather than being drawn
    -- over it, and one scrolled down stops at the padding rather than at the border.
    els[#els + 1] = { type = "rectangle", action = "clip",
      frame = { x = PAD_X, y = PAD_Y + model.bodyY, w = innerW, h = bodyRoom } }
    local dy = PAD_Y + model.bodyY - scrollOffset
    for _, el in ipairs(model.bodyEls) do els[#els + 1] = shifted(el, PAD_X, dy) end

    local run = model.bodyRun
    if run then
      -- One line of margin at each end, so a partly scrolled line is still drawn rather
      -- than appearing only once its top edge crosses into the box.
      local first = math.max(1, math.floor((scrollOffset - run.y) / run.lineH))
      local last = math.min(#run.lines, first + math.ceil(bodyRoom / run.lineH) + 1)
      if last >= first then
        local slice = {}
        for i = first, last do slice[#slice + 1] = run.lines[i] end
        els[#els + 1] = { type = "text",
          text = styled(table.concat(slice, "\n"), run.color, run.size),
          -- The slice is placed where its FIRST line belongs rather than at the top of the
          -- block, which is what keeps the text still while the window moves over it.
          frame = { x = PAD_X, y = dy + run.y + (first - 1) * run.lineH,
                    w = innerW, h = (#slice + 1) * run.lineH } }
      end
      -- What was left out, under the ellipsis at the very end. In the meta tone, because it is
      -- the pane talking about the file rather than more of the file. Always emitted, since it
      -- is one line and the clip drops it while you are anywhere above the bottom.
      if run.note then
        els[#els + 1] = { type = "text",
          text = styled(run.note, colors.meta, LABEL_SIZE),
          frame = { x = PAD_X, y = dy + run.y + #run.lines * run.lineH,
                    w = innerW, h = 2 * run.lineH } }
      end
    end
    els[#els + 1] = { type = "resetClip" }
  end

  canvas:frame(frame)
  canvas:replaceElements(els)
  canvas:show()
end

--------------------------------------------------------------------------------
-- Thumbnails, asked for once per row and answered late
--------------------------------------------------------------------------------

-- The images already in hand, keyed by the path plus what the file was when it was
-- rendered, so an edited file is drawn again rather than shown as it used to be. Held for
-- the open and dropped on close, the same lifetime as the row icon memo the root clears,
-- because an image is real memory and a reopen re renders from the generator's own cache
-- in a few milliseconds.
local images = {}

local function imageKey(row, attrs)
  return string.format("%s|%s|%s", row.path, tostring(attrs and attrs.size),
    tostring(attrs and attrs.modification))
end

--- The image for a row, or nil plus a word for what is happening.
---
--- Called from a describer while the model is being built, so it must answer at once. A
--- miss asks for one and answers nil, and the pane repaints itself when that lands.
---
--- ONE GENERATOR ANSWERS IMMEDIATELY and that is not a special case to tolerate, it is the
--- common one, since every ordinary image goes through the in process decode. So an answer
--- arriving before the ask has even returned is taken straight back to the describer, which
--- is what `settled` distinguishes. Without it a raster showed the word rendering on its
--- first build and its picture only on some later one, because the repaint path below
--- correctly refuses to fire while the model it would rebuild is still being built.
---
--- The generation counter keeps a genuinely late answer honest. Moving the highlight bumps
--- it, so a render finishing after you have left the row is kept for next time and paints
--- nothing, which is the whole reason it cannot simply repaint on arrival.
function M._image(row, attrs)
  local key = imageKey(row, attrs)
  local hit = images[key]
  if hit ~= nil then
    if hit == false then return nil, "no preview" end
    return hit
  end
  local generation = pending
  local edge = (cfg.limits and cfg.limits.imageEdge) or 600
  local settled, landed = false, nil
  -- The size travels with the ask, because a backend deciding whether it will take this file
  -- would otherwise stat a file the header already stat'd.
  cfg.thumbs.image({ path = row.path, ext = row.ext or "", edge = edge,
                     size = attrs and attrs.size }, function(img)
    images[key] = img or false
    if not settled then
      landed = img
      return
    end
    if generation ~= pending then return end
    if not (model and model.path == row.path) then return end
    -- Rebuilt rather than patched, because the image decides the body's height and the
    -- overflow the scroll is clamped against is measured from it.
    model = buildModel(model.row, model.w, model.h)
    paint()
  end)
  settled = true
  if landed then return landed end
  if images[key] == false then return nil, "no preview" end
  return nil, "rendering"
end

--------------------------------------------------------------------------------
-- Public surface (dot-called)
--------------------------------------------------------------------------------

--- preview.configure(opts) - injected by the surface that owns the picker.
--- opts.surface   function(w, h) -> canvas elements, the shared CanvasPanel surface.
---                Absent means no pane at all, see available.
--- opts.palette   function() -> the theme's preview colour set, resolved per open so the
---                pane follows the live light and dark appearance.
--- opts.limits    the preview block from config, the read cap, the head line count, the
---                folder entry count and the image edge, so no number here is a policy
---                this file invented.
--- opts.usedAt    function(path) -> when that path was last acted on, the same seam the
---                row subtitle reads, so the pane and the row cannot disagree about it.
--- opts.thumbs    the thumbnail chain. Absent means the image describer declines every
---                row and a picture simply never appears, which is a working pane.
function M.configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  return M
end

--- viewer.available() -> bool, reason
--- Whether a pane can be drawn at all, which is to say whether the composition root injected
--- the shared surface. The picker asks before reserving a companion rect, so a root that wires
--- nothing gets the picker exactly as it was rather than a pane of unreadable text floating
--- over the desktop with no background behind it.
function M.available()
  if cfg.surface == nil then return false, "no canvas surface was injected" end
  return true
end

--- viewer.companionWidth(policy) -> the room this provider needs beside the list.
--- Answered by the provider rather than read from config by the surface, because how much room
--- a preview needs is the provider's own business and the other one needs none. Absent an
--- explicit policy width, the pane inherits the chooser's own width, the atom's default for
--- every companion.
function M.companionWidth(policy)
  if not M.available() then return 0 end
  return (policy and policy.width) or true
end

--- viewer.close() - the contract's teardown name, over this provider's own.
function M.close()
  return M.destroy()
end

--- preview.dock(companionFrame) - take the rect the Chooser atom reported.
--- Fired with a seed rect at show and again once the real window settles, so a re dock is
--- expected. The palette is resolved here rather than per highlight, since it can only
--- change between opens.
function M.dock(companionFrame)
  if not (M.available() and companionFrame) then return end
  frame = companionFrame
  local p = (cfg.palette and cfg.palette()) or {}
  colors = {
    fg = hexColor(p.fg or "#dcdcdc"),
    meta = hexColor(p.meta or "#8a8a8a"),
    path = hexColor(p.path or "#7a7a7a"),
    note = hexColor(p.note or "#c8a86a"),
  }
  if model then
    model = buildModel(model.row, frame.w - 2 * PAD_X, frame.h - 2 * PAD_Y)
    paint()
  end
end

--- preview.show(row) - describe a row, or clear the pane when handed nothing.
--- Called straight from the atom's highlight poll, so it is cheap when nothing moved. The
--- layout is rebuilt only when the row or its box changed.
---
--- The scroll goes back to the top whenever the row changes, because an offset carried
--- over would open the next file part way down for no reason the reader can see.
function M.show(row)
  if not (M.available() and frame and colors) then return end
  if not (row and row.path) then
    M.clear()
    return
  end
  local w, h = frame.w - 2 * PAD_X, frame.h - 2 * PAD_Y
  if not (model and model.path == row.path and model.w == w and model.h == h) then
    pending = pending + 1
    scrollOffset = 0
    model = buildModel(row, w, h)
  end
  paint()
end

--- preview.scrollBy(points) - move the body by a distance in points, positive being
--- further down it. The one place the offset changes, so the keys and the trackpad cannot
--- drift apart, and the clamp lives in paint where the content height is known.
function M.scrollBy(points)
  if not model then return end
  scrollOffset = scrollOffset + (tonumber(points) or 0)
  paint()
end

--- preview.clear() - drop the pane's content and hide it, keeping the canvas.
--- For a highlight with nothing to describe, a status row or a help row, so the picker is
--- not left beside an empty bordered box.
function M.clear()
  model = nil
  scrollOffset = 0
  if canvas then canvas:hide() end
end

--- preview.destroy() - tear the pane down completely.
--- Hooked to the picker's one teardown path, so no dismissal leaves a canvas behind.
--- Deleted rather than hidden because nothing may survive a close, and rebuilding one
--- canvas on the next open costs nothing.
function M.destroy()
  model = nil
  frame = nil
  colors = nil
  scrollOffset = 0
  pending = pending + 1
  images = {}
  if canvas then
    canvas:delete()
    canvas = nil
  end
end

return M
