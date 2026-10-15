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
--- Dot called, and it holds no policy. The surface routine, the kit, the limits, the
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
local nodes = loadfile(viewerPath .. "sidepanel-nodes.lua")()

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
local model = nil        -- the row on screen, the header's laid out elements and a body node, see buildModel
local scrollOffset = 0   -- how far down the body, in points, clamped at paint
local pending = 0        -- the generation of the newest thumbnail request, see requestImage
local hidden = false     -- set by M.hide, cleared by M.dock, the resurrection guard paint reads
local scrollTimer = nil  -- the one pending scroll paint, see M.scrollBy

-- One display frame, the longest a scroll event waits for its paint.
local SCROLL_FRAME = 1 / 60

local function stopScrollTimer()
  if scrollTimer then
    scrollTimer:stop()
    scrollTimer = nil
  end
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

-- The header, everything true of every row. The name, where it lives, then the facts. What
-- each fact looks like is sidepanel-nodes.lua's business, this only decides which there are.
--
-- Both ages are LABELLED, the same fix the row subtitle carries, because a bare age reads
-- as something you did and a file a build wrote four days ago is not a file you touched
-- four days ago. When you last reached for it comes first, since it is the field that
-- explains why the row is where it is.
local function headerNode(row, attrs)
  local ui = cfg.ui
  local facts = { { label = "KIND", value = kindOf(row, attrs) } }
  -- No size for a directory. A directory's own byte count is the size of the entry that
  -- holds its names, which is not the question anyone is asking, and the folder section
  -- below carries the count that is.
  if attrs and attrs.size and not row.isDir then
    facts[#facts + 1] = { label = "SIZE", value = util.humanBytes(attrs.size) }
  end
  if attrs and attrs.modification then
    facts[#facts + 1] = { label = "CHANGED", value = util.humanAge(attrs.modification) }
  end
  if attrs and attrs.creation then
    facts[#facts + 1] = { label = "ADDED", value = util.humanAge(attrs.creation) }
  end
  local usedAt = cfg.usedAt and row.path and cfg.usedAt(row.path)
  if usedAt then
    -- In the accent tone, because it is the one fact on the pane that is about you rather
    -- than about the file.
    facts[#facts + 1] = { label = "USED", value = util.humanAge(usedAt), color = "subtext" }
  end
  return nodes.header(ui, row.name or row.path, util.shortDir(row.dir), facts)
end

-- The inner box the tree is laid out in, the pane's frame less the kit's pad on all four sides,
-- the space around content every surface shares. In the canvas's own coordinates.
local function innerRect()
  local pad = cfg.ui.tokens().pad
  return { x = pad, y = pad, w = frame.w - 2 * pad, h = frame.h - 2 * pad }
end

-- Everything for one row, built once and cached, since the highlight poll fires often and
-- nothing here changes under it. Keyed on the path and the box, so a re dock at the
-- corrected frame rebuilds and a poll that has not moved pays nothing. w is the width the
-- text is laid out and wrapped at, and h is kept only to key the cache.
local function buildModel(row, w, h)
  local attrs = statOf(row)
  local body = nil
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
  -- The header is laid out here, once, since it never scrolls and a paint happens on every
  -- scroll event. Its elements and height are kept, and a paint only adds them to the list, never
  -- changing them.
  local headEls, headH = cfg.ui.layout(headerNode(row, attrs), innerRect(), { clip = true })
  return {
    row = row, path = row.path, w = w, h = h,
    headEls = headEls, headH = headH,
    body = body and nodes.body(cfg.ui, body, w) or nil,
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
-- The header was laid out when the model was built and never moves. The body is laid out in
-- the rect below it and scrolled by the scroll offset. It is clipped from the header down to
-- the inside of the pane's border, so a body scrolled up stops at the header and a line cut at
-- the bottom is cut by the edge of the pane rather than by the padding, the padding being part
-- of what scrolls.
-- The offset is clamped HERE rather than where it is changed, against the body height the
-- layout answers. That is what lets a key press, a trackpad gesture and a rebuild at a new
-- height all be written without any of them knowing how tall the content turned out.
--
-- ONLY THE LINES ON SCREEN ARE DRAWN, and that is not an optimisation to be simplified
-- away. A clip bounds what is VISIBLE and not what is laid out, so handing the canvas the
-- whole block made every paint cost the whole file, and a paint happens on every scroll
-- event. Measured with a heartbeat timer, a four hundred line body stalled the main thread
-- for fifty to a hundred milliseconds per paint and dropped half the frames of a scroll.
-- The kit's code block lays out only the lines inside the scrolled window, and the body is
-- laid out again on every paint, which is affordable exactly because of that.
local function paint()
  -- A background tick, a late search result, or a settled thumbnail can all reach this
  -- point after M.hide has already taken the canvas down for a swap away. hidden is what
  -- stops any of them from bringing it back up beside a tool that is no longer current.
  if hidden then return end
  if not (model and frame and cfg.surface and cfg.ui) then return end
  ensureCanvas()
  local ui = cfg.ui
  local inner = innerRect()

  local els = {}
  for _, el in ipairs(cfg.surface(frame.w, frame.h)) do els[#els + 1] = el end
  for _, el in ipairs(model.headEls) do els[#els + 1] = el end

  local bodyTop = inner.y + model.headH + ui.tokens().space[nodes.GAP]
  local room = inner.y + inner.h - bodyTop
  if model.body and room > 0 then
    local rect = { x = inner.x, y = bodyTop, w = inner.w, h = room }
    local box = ui.interior(frame.w, frame.h)
    local viewport = { x = box.x, y = bodyTop, w = box.w, h = box.y + box.h - bodyTop }
    local content, bodyH = ui.layout(model.body, rect, { scrollY = scrollOffset, viewport = viewport })
    local overflow = math.max(0, bodyH - room)
    if scrollOffset > overflow or scrollOffset < 0 then
      scrollOffset = math.max(0, math.min(scrollOffset, overflow))
      content = ui.layout(model.body, rect, { scrollY = scrollOffset, viewport = viewport })
    end
    for _, el in ipairs(content) do els[#els + 1] = el end
  else
    scrollOffset = 0
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
--- opts.ui        the UI kit, needs.lib.ui, which every piece of text in the pane is drawn
---                through. Absent means no pane at all, see available.
--- opts.limits    the preview block from config, the read cap, the head line count, the
---                folder entry count and the image edge, so no number here is a policy
---                this file invented.
--- opts.usedAt    function(path) -> when that path was last acted on, the same seam the
---                row subtitle reads, so the pane and the row cannot disagree about it.
--- opts.thumbs    the thumbnail chain. Absent means the image describer declines every
---                row and a picture simply never appears, which is a working pane.
--- opts.emptyState function(w, h, opts) -> canvas elements, the shared CanvasPanel empty
---                state, painted by clear below for a highlight with nothing to describe.
---                Absent falls back to hiding the canvas, the old behaviour, so a root that
---                has not been updated to inject it degrades rather than breaking.
--- opts.emptyText  the line clear below paints into the shared empty state, this pane's
---                own guidance rather than a content label, so a person reads what to do
---                next instead of the wording off whatever row happened to be highlighted.
---                Absent falls back to the shared routine's own generic default.
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
  if cfg.ui == nil then return false, "no UI kit was injected" end
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
--- expected.
function M.dock(companionFrame)
  if not (M.available() and companionFrame) then return end
  frame = companionFrame
  -- A redock is the swap back M.hide guards against, so the pane may paint again from
  -- here on. The highlight seed the caller runs right after this call is what actually
  -- fills the pane, cold or not, a nil highlight landing in M.clear same as any other.
  hidden = false
  if model then
    local inner = innerRect()
    model = buildModel(model.row, inner.w, inner.h)
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
  if not (M.available() and frame) then return end
  if not (row and row.path) then
    M.clear()
    return
  end
  local inner = innerRect()
  local w, h = inner.w, inner.h
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
  -- A trackpad sends dozens of events a second and a paint costs a layout, so the offset adds up
  -- and one paint is scheduled for the next frame, however many events land before it. The
  -- paint clamps the sum, and its own hidden guard keeps a late timer from drawing.
  if scrollTimer then return end
  scrollTimer = hs.timer.doAfter(SCROLL_FRAME, function()
    scrollTimer = nil
    paint()
  end)
end

--- preview.clear() - the empty state, for a highlight with nothing to describe, a
--- status row or a help row, or a cold dock before anything has been highlighted yet.
---
--- This used to hide the canvas outright, on the reasoning that nothing to describe
--- means nothing to draw. That reads as a broken layout instead, a bordered rectangle
--- reserved beside the list with nothing in it, so the pane now stays up and paints the
--- shared empty state, the same quiet message every other docked pane shows in this
--- moment, rather than vanishing. The pane genuinely disappears only on the stage's own
--- swap signal, M.hide below, and on M.destroy.
---
--- The line is cfg.emptyText, this pane's own guidance, falling back to the shared
--- routine's own default when configure never set one. It used to echo the highlighted
--- row's own wording instead, a status row's title standing in for the empty state, and
--- that read as a content label rather than as guidance, Recent files painted where a
--- person expects to be told what to do next.
---
--- Does nothing when called before the first dock, so frame is still nil,
--- since the dock that follows paints this same empty state on its own.
function M.clear()
  stopScrollTimer()
  model = nil
  scrollOffset = 0
  if not (frame and cfg.surface and cfg.ui) then return end
  -- See paint's own note. A swap away must stay down through whatever clear a stray
  -- highlight event fires while nobody can see it.
  if hidden then return end
  if not cfg.emptyState then
    -- Absent means a misconfigured or partially configured module, so degrade by
    -- hiding rather than erroring.
    if canvas then canvas:hide() end
    return
  end
  ensureCanvas()
  local inner = innerRect()
  local els = {}
  for _, el in ipairs(cfg.surface(frame.w, frame.h)) do els[#els + 1] = el end
  for _, el in ipairs(cfg.emptyState(inner.w, inner.h, { text = cfg.emptyText })) do
    els[#els + 1] = shifted(el, inner.x, inner.y)
  end
  canvas:frame(frame)
  canvas:replaceElements(els)
  canvas:show()
end

--- preview.hide() - hide the canvas without destroying it, for the stage's own swap away
--- signal, onPositioned told nil twice when a different presentation becomes current. The
--- canvas, the frame and the model all survive, so a swap back to this
--- presentation docks again and repaints at once rather than rebuilding from nothing.
function M.hide()
  hidden = true
  stopScrollTimer()
  -- Bumps the image generation the same way M.destroy does, so a thumbnail already in
  -- flight for the row this pane was last showing cannot land after the hide and pull
  -- the canvas back up on its own. The swap back through M.dock repaints properly.
  pending = pending + 1
  if canvas then canvas:hide() end
end

--- preview.destroy() - tear the pane down completely.
--- Hooked to the picker's one teardown path, so no dismissal leaves a canvas behind.
--- Deleted rather than hidden because nothing may survive a close, and rebuilding one
--- canvas on the next open costs nothing.
function M.destroy()
  stopScrollTimer()
  model = nil
  frame = nil
  scrollOffset = 0
  pending = pending + 1
  hidden = false
  images = {}
  if canvas then
    canvas:delete()
    canvas = nil
  end
end

return M
