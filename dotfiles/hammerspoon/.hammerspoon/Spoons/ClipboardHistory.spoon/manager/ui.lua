--- The clipboard consumer of the shared Chooser atom, plus the live preview pane.
---
--- The generic chooser behavior (the window, theming, row styling, navigation,
--- positioning, and click away dismissal) lives in Chooser.spoon, injected here
--- as a factory. This file supplies only clipboard policy. The rows, what a
--- selection pastes, the append batch, right click delete, and the preview that
--- docks in the companion pane the atom reserves beside the chooser.
---
--- The preview is an hs.canvas docked into the companion frame the native atom
--- reserves beside the chooser, drawn to match the panel look. It never takes key
--- focus, so typing always stays in the search field. The atom polls the
--- highlighted row and calls onHighlight, which re-renders the canvas here.
---
--- Preview rendering is per kind, building canvas elements (never a webview). Text
--- and url wrap in a monospace block; image and video show the downscaled preview
--- PNG the store already generated (sips or ffmpeg, off the main thread, in
--- preview.lua), loaded straight as an hs.image, so nothing sizes media here. A
--- single text file is read off the main thread with hs.task so an undownloaded or
--- large file cannot stall the pane, and the result is dropped if the selection has
--- moved on. Content taller than the pane scrolls with the Hyper+Cmd+j/k bindings.

local UI = {}

local store, monitor, util = nil, nil, nil
local cfg = nil -- layout and size config, see configure
local Chooser = nil -- the injected Chooser.spoon factory
local picker = nil -- our Chooser instance, built once in UI.build

-- Display labels and the type-filter query prefixes, both ui policy.
local KIND_LABEL = { text = "Text", url = "URL", file = "File", image = "Image" }
local KIND_PREFIX = {
  img = "image", image = "image",
  url = "url", link = "url",
  file = "file", files = "file",
  txt = "text", text = "text",
}

-- State
local preview = nil -- the hs.canvas companion pane, built lazily in ensurePreview
local previewFrame = nil -- the companion rect the atom reported, where the canvas docks
local renderToken = 0 -- bumped each render; async results check it to avoid stale writes
local scrollOffset = 0 -- how far the current preview is scrolled down, in points
local maxScroll = 0 -- clamp bound for scrollOffset, set by the last render from content height
local thumbCache = {} -- path -> hs.image (or false), for row thumbnails
local imageCache = {} -- preview png path -> hs.image (or false), so a re-highlight re-decodes nothing
local iconCache = {} -- bundle id -> hs.image (or false), for row source-app icons
local existCache = {} -- linked-file path -> bool, so the badge does not restat per keystroke

-- Append batch. The Hyper a binding collects the highlighted entry here, in the
-- order pressed, so several items can be gathered and pasted together on close.
-- Membership is keyed by the live store reference each row carries, so a row's
-- order badge is just its position in this list, and toggling an item off
-- renumbers the rest for free. Collecting never touches the store, so the visible
-- list never shifts while the picker is open; the reorder happens on commit. The
-- batch is cleared on every close, so each open starts empty.
local batch = {}

local function batchPos(e)
  for i = 1, #batch do
    if batch[i] == e then
      return i
    end
  end
  return nil
end

local function toggleBatch(e)
  local pos = batchPos(e)
  if pos then
    table.remove(batch, pos)
  else
    batch[#batch + 1] = e
  end
end

-- Push a fresh footer whenever the batch count changes, so the injected footer
-- supplier can relabel the delete hint ("Delete" vs "Delete marked (N)") to match.
-- The supplier owns the wording; this only hands it the live count and forwards the
-- result to the picker. A no op on a backend whose picker has no setFooter (native).
local function refreshFooter()
  if picker and picker.setFooter and cfg and cfg.footerFor then
    picker:setFooter(cfg.footerFor(#batch))
  end
end

--------------------------------------------------------------------------------
-- Rows and filtering (the atom's rows supplier)
--------------------------------------------------------------------------------

local function thumbImage(path)
  if not path then return nil end
  local c = thumbCache[path]
  if c ~= nil then return c or nil end
  local img = hs.image.imageFromPath(path) or false
  thumbCache[path] = img
  return img or nil
end

-- The icon of the app an entry was copied from, resolved from its bundle id and
-- cached. A false marks a bundle id that has no resolvable icon (uninstalled or
-- iconless), so it is looked up only once. nil when the entry recorded no source.
local function appIcon(bundleID)
  if not bundleID then return nil end
  local c = iconCache[bundleID]
  if c ~= nil then return c or nil end
  local img = hs.image.imageFromAppBundle(bundleID) or false
  iconCache[bundleID] = img
  return img or nil
end

-- Whether a linked original still exists, memoized per open so filtering, which
-- rebuilds the rows on every keystroke, does not restat the same paths. Frozen
-- files never reach here, only links, so the number of stats is small. Cleared on
-- close and when new media lands, alongside the other caches.
local function pathExists(p)
  local c = existCache[p]
  if c ~= nil then return c end
  local ok = hs.fs.attributes(p) ~= nil
  existCache[p] = ok
  return ok
end

-- The file state badge, from the three-state model. A frozen element carries a
-- stored copy and needs no check; only links (a file with no stored copy, and
-- folders, which are never frozen) are stat'd. Returns "Deleted" if any linked
-- original is gone, "Linked" if any element is a link but all still exist, or nil
-- when every element is a frozen copy and nothing needs saying.
local function fileBadge(e)
  local anyLink, anyMissing = false, false
  for _, el in ipairs(e.files or {}) do
    if not el.stored then
      anyLink = true
      if not pathExists(el.path) then
        anyMissing = true
      end
    end
  end
  if anyMissing then return "Deleted" end
  if anyLink then return "Linked" end
  return nil
end

local function subTextFor(e)
  local parts = { KIND_LABEL[e.kind] or e.kind, util.relTime(e.ts) }
  -- The file location belongs only in the preview, so the picker shows just the
  -- count when several files were copied and nothing extra for a single one. The
  -- Linked/Deleted badge rides along so dead copies are visible without opening
  -- the preview.
  if e.kind == "file" then
    local files = e.files or {}
    if #files > 1 then
      parts[#parts + 1] = #files .. " files"
    end
    local badge = fileBadge(e)
    if badge then
      parts[#parts + 1] = badge
    end
  end
  return table.concat(parts, "  ·  ")
end

local function haystack(e)
  local parts = { e.title, e.preview or "" }
  if e.text then parts[#parts + 1] = e.text end
  for _, el in ipairs(e.files or {}) do
    parts[#parts + 1] = el.path
  end
  return table.concat(parts, " "):lower()
end

-- Split an optional leading type token ("img ...", "file: ...") off the query.
local function parseQuery(q)
  q = q or ""
  local word, rest = q:match("^(%a+)[:%s]%s*(.*)$")
  if word and KIND_PREFIX[word:lower()] then
    return KIND_PREFIX[word:lower()], rest
  end
  return nil, q
end

-- An appended row (Hyper+a) is marked by swapping its icon for a big keycap-emoji
-- number, since a tiny text prefix was too easy to miss. The glyph is a keycap
-- digit 1..9, capping at the ten-keycap past nine, so the mark says "queued and
-- roughly where", not exact depth.
local KEYCAP = { "1️⃣", "2️⃣", "3️⃣", "4️⃣", "5️⃣", "6️⃣", "7️⃣", "8️⃣", "9️⃣" }
local function keycapGlyph(pos)
  return KEYCAP[pos] or "🔟"
end

-- Render a keycap emoji to a square hs.image once per position, cached. hs.canvas
-- draws the glyph and imageFromCanvas snapshots it; the image is independent of the
-- canvas, so the scratch canvas is deleted right after. An hs.image serialises fine
-- as a chooser row image (only functions are dropped), so it stands in as the icon.
local keycapCache = {}
local function keycapImage(pos)
  local hit = keycapCache[pos]
  if hit ~= nil then return hit or nil end
  local S = 48
  local c = hs.canvas.new({ x = 0, y = 0, w = S, h = S })
  c[1] = { type = "text", text = keycapGlyph(pos), textSize = 34,
           textAlignment = "center", frame = { x = 0, y = (S - 40) / 2, w = S, h = 42 } }
  local img = c:imageFromCanvas() or false
  c:delete()
  keycapCache[pos] = img
  return img or nil
end

-- The preview meta note for an appended entry, kept as readable text (the pane's
-- monospace block, unlike the row icon, is no place for the emoji).
local function withBatchMark(meta, e)
  local pos = batchPos(e)
  return pos and (meta .. "  ·  #" .. pos .. " Appended") or meta
end

-- The atom's rows supplier. Returns plain items; the atom styles them with the
-- active palette. Filtering, the type prefix, the batch mark, and the thumbnail or
-- source-app icon are all clipboard policy and live here.
local function buildChoices(q)
  local kind, rest = parseQuery(q)
  rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
  local out = {}
  for _, e in ipairs(store.all()) do
    if (not kind or e.kind == kind) and (rest == "" or haystack(e):find(rest, 1, true)) then
      -- An appended row shows its 1-based batch position as its icon (the keycap
      -- number), the most visible mark on the native chooser, which renders no icon
      -- badge. Otherwise a true image copy shows its own thumbnail and every other
      -- row shows the icon of the app it came from, falling back to nothing when
      -- unknown. The stable iconKey lets the atom encode each icon once and reuse it.
      local pos = batchPos(e)
      local img, iconKey
      if pos then
        img, iconKey = keycapImage(pos), "batch:" .. pos
      else
        local thumb = e.kind == "image" and thumbImage(e.thumb) or nil
        if thumb then
          img, iconKey = thumb, "thumb:" .. e.thumb
        else
          local ic = appIcon(e.sourceApp)
          if ic then img, iconKey = ic, "app:" .. e.sourceApp end
        end
      end
      out[#out + 1] = {
        title = e.title,
        subTitle = subTextFor(e),
        image = img,
        iconKey = iconKey,
        badge = pos and tostring(pos) or nil,
        item = e,
      }
    end
  end
  return out
end

--------------------------------------------------------------------------------
-- Preview rendering (the atom's onHighlight target)
--------------------------------------------------------------------------------
--
-- Everything is drawn as hs.canvas elements. A render builds a content model of
-- blocks (meta lines, wrapped text, images) stacked top down from y = 0, measuring
-- each block so the total height is known, then paint() lays them into the canvas
-- offset by the padding and the live scroll, clipped to the inner box. Media comes
-- straight from the store's downscaled preview PNG (preview.lua sized it with sips
-- or ffmpeg off the main thread), loaded once as an hs.image; nothing sizes it here.

-- Layout and type sizes for the canvas content. The padding matches the shortcut
-- panel (HelperPanel's 14/10) so the two canvas panels read as one component.
local PAD_X, PAD_Y = 14, 10
local META_SIZE, PATH_SIZE, BODY_SIZE = 11, 11, 13
local BODY_FONT = "Menlo" -- monospace, so text wraps by column math with exact heights
local LINE_MULT = 1.35 -- body line height as a multiple of the font size
local BLOCK_GAP = 10 -- vertical gap between content blocks
local TEXT_DISPLAY_CAP = 20000 -- max characters drawn, so the canvas stays bounded

-- Colors resolved per render from the atom's active (light/dark) preview palette.
local colors = nil

-- The content of the last paint, kept so a scroll can redraw at the new offset
-- without rebuilding the model.
local lastEls, lastH = {}, 0

-- Convert a CSS hex string (the palette's format) to a canvas color table.
local function hexColor(hex)
  local r, g, b = tostring(hex):match("#?(%x%x)(%x%x)(%x%x)")
  if not r then return { white = 0.85, alpha = 1 } end
  return { red = tonumber(r, 16) / 255, green = tonumber(g, 16) / 255,
           blue = tonumber(b, 16) / 255, alpha = 1 }
end

-- A shallow copy of a canvas element with its frame offset by (dx, dy), so content
-- built in its own (0,0) box can be placed absolutely without mutating the source.
local function shiftEl(el, dx, dy)
  local copy = {}
  for k, v in pairs(el) do copy[k] = v end
  if el.frame then
    copy.frame = { x = (el.frame.x or 0) + dx, y = (el.frame.y or 0) + dy,
                   w = el.frame.w, h = el.frame.h }
  end
  return copy
end

local function ensurePreview()
  if preview then return end
  preview = hs.canvas.new({ x = 0, y = 0, w = cfg.previewW, h = cfg.previewH })
  preview:level(hs.canvas.windowLevels.floating)
  preview:clickActivating(false) -- a click on the pane must not pull focus off the field
end

-- Monospace character width per size, measured once from a run so any per-glyph
-- padding averages out. Drives the column count text wraps to.
local charWidthCache = {}
local function monoCharWidth(size)
  local c = charWidthCache[size]
  if c then return c end
  local run = "MMMMMMMMMMMMMMMMMMMM" -- 20 chars
  local sz = hs.drawing.getTextDrawingSize(hs.styledtext.new(run, { font = { name = BODY_FONT, size = size } }))
  c = (((sz and sz.w) or (size * 12 * 0.6)) / #run)
  charWidthCache[size] = c
  return c
end

-- Wrap text to a column budget for the monospace body font. Honors existing
-- newlines, breaks at the last space in an over-long line, and hard-breaks a word
-- longer than the whole line, so leading indentation survives. Tabs become spaces
-- first so the column math holds.
local function wrapMono(str, cols)
  local lines = {}
  str = tostring(str):gsub("\t", "    ")
  for para in (str .. "\n"):gmatch("(.-)\n") do
    if #para == 0 then
      lines[#lines + 1] = ""
    else
      local pos, n = 1, #para
      while pos <= n do
        if n - pos + 1 <= cols then
          lines[#lines + 1] = para:sub(pos)
          break
        end
        local slice = para:sub(pos, pos + cols - 1)
        local lastSpace = nil
        for s in slice:gmatch("() ") do lastSpace = s end
        if lastSpace and lastSpace > 1 then
          lines[#lines + 1] = para:sub(pos, pos + lastSpace - 2)
          pos = pos + lastSpace
        else
          lines[#lines + 1] = slice
          pos = pos + cols
        end
      end
    end
  end
  return lines
end

-- A styled text run with a fixed line height, so the drawn height matches the line
-- count exactly and the scroll clamp stays honest.
local function styled(text, color, size, lineH)
  return hs.styledtext.new(text, {
    font = { name = BODY_FONT, size = size },
    color = color,
    paragraphStyle = { maximumLineHeight = lineH, minimumLineHeight = lineH },
  })
end

-- The decoded preview image for a path, cached (false marks a decode failure so it
-- is tried once). The store's PNG is content-unique, so a hit is always valid.
local function previewImage(path)
  if not path then return nil end
  local hit = imageCache[path]
  if hit ~= nil then return hit or nil end
  local img = hs.image.imageFromPath(path) or false
  imageCache[path] = img
  return img or nil
end

-- Append a wrapped text block at content-local (x0, y0), returning the y below it.
local function appendText(els, str, x0, y0, w, color, size)
  local cols = math.max(1, math.floor(w / monoCharWidth(size)))
  local lineH = math.ceil(size * LINE_MULT)
  local lines = wrapMono(str, cols)
  if #lines == 0 then return y0 end
  local h = #lines * lineH
  els[#els + 1] = { type = "text", text = styled(table.concat(lines, "\n"), color, size, lineH),
    frame = { x = x0, y = y0, w = w, h = h + lineH } }
  return y0 + h
end

-- Append an image scaled to fit the content width (the preview PNG is already
-- small), returning the y below it.
local function appendImage(els, img, x0, y0, w)
  local sz = img:size()
  local h = (sz and sz.w and sz.w > 0) and (w * sz.h / sz.w) or w
  els[#els + 1] = { type = "image", image = img, imageScaling = "scaleProportionally",
    imageAlignment = "topLeft", frame = { x = x0, y = y0, w = w, h = h } }
  return y0 + h
end

-- Lay the content blocks into the canvas: solid fill and border first (unclipped),
-- then a clip to the inner box, then the content shifted by the padding and the
-- live scroll. maxScroll comes from the overflow, so a tall entry scrolls under the
-- padding instead of spilling over the border. Records the model for repaint().
local function paint(contentEls, contentH)
  ensurePreview()
  lastEls, lastH = contentEls, contentH
  local frame = previewFrame or { x = 0, y = 0, w = cfg.previewW, h = cfg.previewH }
  local innerW = frame.w - 2 * PAD_X
  local innerH = frame.h - 2 * PAD_Y
  maxScroll = math.max(0, contentH - innerH)
  if scrollOffset > maxScroll then scrollOffset = maxScroll end
  if scrollOffset < 0 then scrollOffset = 0 end

  -- Square fill and 1px border, drawn exactly like HelperPanel (the shortcut panel),
  -- so the preview and the panel are the same component, just placed differently.
  local els = {
    { type = "rectangle", action = "fill", fillColor = colors.bg,
      frame = { x = 0, y = 0, w = frame.w, h = frame.h } },
    { type = "rectangle", action = "stroke", strokeColor = colors.border, strokeWidth = 1,
      frame = { x = 0.5, y = 0.5, w = frame.w - 1, h = frame.h - 1 } },
    -- Clip to the inner box; every element after this is restricted to it.
    { type = "rectangle", action = "clip",
      frame = { x = PAD_X, y = PAD_Y, w = innerW, h = innerH } },
  }
  for _, el in ipairs(contentEls) do
    els[#els + 1] = shiftEl(el, PAD_X, PAD_Y - scrollOffset)
  end
  preview:frame(frame)
  preview:replaceElements(els)
  preview:show()
end

-- Redraw the last content at the current scroll, for the scroll bindings.
local function repaint()
  paint(lastEls, lastH)
end

-- The inner content width, the companion frame minus horizontal padding.
local function innerWidth()
  return (previewFrame and previewFrame.w or cfg.previewW) - 2 * PAD_X
end

-- Header blocks for a file entry: an uppercase meta line (count, size, badge) and
-- one path line per original. Returns the element list and the y below it.
local function buildFileHeader(e, w)
  local els = {}
  local files = e.files or {}
  local meta = "File  ·  " .. #files .. " item" .. (#files == 1 and "" or "s")
  if e.size and e.size > 0 then meta = meta .. "  ·  " .. util.humanSize(e.size) end
  local badge = fileBadge(e)
  if badge then meta = meta .. "  ·  " .. badge end
  meta = withBatchMark(meta, e)
  local y = appendText(els, meta:upper(), 0, 0, w, colors.meta, META_SIZE)
  y = y + 4
  for _, el in ipairs(files) do
    y = appendText(els, el.path, 0, y, w, colors.path, PATH_SIZE) + 2
  end
  return els, y + BLOCK_GAP
end

-- The synchronous kinds, text, url, and image, as canvas blocks. Returns the
-- element list and total content height.
local function buildNonFile(e)
  local els = {}
  local w = innerWidth()
  if e.kind == "image" then
    local meta = e.title
    if e.size then meta = meta .. "  ·  " .. util.humanSize(e.size) end
    meta = withBatchMark(meta, e)
    local y = appendText(els, meta:upper(), 0, 0, w, colors.meta, META_SIZE) + BLOCK_GAP
    local img = previewImage(e.prev)
    if img then
      y = appendImage(els, img, 0, y, w)
    else
      y = appendText(els, "No preview.", 0, y, w, colors.note, BODY_SIZE)
    end
    return els, y
  end
  local meta = (KIND_LABEL[e.kind] or e.kind) .. "  ·  " .. util.relTime(e.ts)
  -- Text shows its character count, computed once at capture, so the pane never
  -- recounts on highlight.
  if e.kind == "text" and e.chars then meta = meta .. "  ·  " .. e.chars .. " chars" end
  meta = withBatchMark(meta, e)
  local y = appendText(els, meta:upper(), 0, 0, w, colors.meta, META_SIZE) + BLOCK_GAP
  local text = e.text or ""
  local capped = #text > TEXT_DISPLAY_CAP
  if capped then text = text:sub(1, TEXT_DISPLAY_CAP) .. "\n\n… truncated" end
  y = appendText(els, text, 0, y, w, colors.fg, BODY_SIZE)
  return els, y
end

-- Read the head of a file off the main thread, so a slow or large file cannot
-- freeze the pane. head -c cap+1 lets us detect truncation.
local function asyncRead(path, cap, cb)
  local t = hs.task.new("/usr/bin/head", function(code, out)
    cb(out or "", code ~= 0)
  end, { "-c", tostring(cap + 1), path })
  if t then
    t:start()
  else
    cb("", true)
  end
end

-- Draw the file header plus an optional trailing note in one paint, the common
-- shape for the file cases that resolve synchronously.
local function paintFile(e, noteText, noteColor)
  local els, y = buildFileHeader(e, innerWidth())
  if noteText then y = appendText(els, noteText, 0, y, innerWidth(), noteColor or colors.note, BODY_SIZE) end
  paint(els, y)
end

local function renderFile(e, token)
  local w = innerWidth()
  local files = e.files or {}
  if #files ~= 1 then
    local els, y = buildFileHeader(e, w)
    for _, el in ipairs(files) do
      if el.prev and hs.fs.attributes(el.prev) then
        local img = previewImage(el.prev)
        if img then y = appendImage(els, img, 0, y, w) + BLOCK_GAP end
      end
    end
    paint(els, y)
    return
  end

  local el = files[1]
  if el.isDir then
    paintFile(e, pathExists(el.path) and "Folder." or "Folder no longer exists.")
    return
  end

  -- A previewable file carries a small PNG (a raster image, a video frame, or a
  -- pdf/icns page) in our cache. Prefer it before anything else, since it is
  -- durable and lets a Deleted file still show its thumbnail. While it is still
  -- being generated the path is set but the file is absent, so show a pending note;
  -- mediaReady repaints when it lands.
  local ext = util.fileExt(el.path)
  if el.prev then
    if hs.fs.attributes(el.prev) then
      local img = previewImage(el.prev)
      if img then
        local els, y = buildFileHeader(e, w)
        paint(els, appendImage(els, img, 0, y, w))
      else
        paintFile(e, "Cannot render preview.")
      end
    else
      paintFile(e, "Generating preview…")
    end
    return
  end

  -- No cached preview. Prefer our frozen copy, fall back to the original only if it
  -- survives, else the entry is a dead link.
  local readPath = (el.stored and hs.fs.attributes(el.stored) and el.stored)
    or (hs.fs.attributes(el.path) and el.path)
    or nil
  if not readPath then
    paintFile(e, "File no longer exists.")
    return
  end

  -- A raster image can still fall back to the original bytes; a video just says it
  -- has no frame.
  if util.RASTER_EXT[ext] then
    local img = previewImage(readPath)
    if img then
      local els, y = buildFileHeader(e, w)
      paint(els, appendImage(els, img, 0, y, w))
    else
      paintFile(e, "Cannot render image.")
    end
    return
  end
  if util.VIDEO_EXT[ext] then
    paintFile(e, "No video preview.")
    return
  end

  -- Text: show the header at once, fill the body when the async read returns.
  paintFile(e, "Loading…")
  asyncRead(readPath, cfg.fileReadCap, function(data, failed)
    if token ~= renderToken then
      return -- selection moved on
    end
    if failed then
      paintFile(e, "Cannot read file.")
    elseif data:find("\0", 1, true) then
      paintFile(e, "Binary file, no text preview.")
    else
      local truncated = #data > cfg.fileReadCap
      if truncated then data = data:sub(1, cfg.fileReadCap) end
      if #data > TEXT_DISPLAY_CAP then data = data:sub(1, TEXT_DISPLAY_CAP); truncated = true end
      if truncated then data = data .. "\n\n… truncated" end
      local els, y = buildFileHeader(e, w)
      paint(els, appendText(els, data, 0, y, w, colors.fg, BODY_SIZE))
    end
  end)
end

-- The atom's onHighlight target. Resolve the palette for the current appearance,
-- reset the scroll to the top for the new entry, then paint the model.
local function renderPreview(e)
  renderToken = renderToken + 1
  scrollOffset = 0
  local p = picker:activeTheme().preview
  colors = {
    bg = hexColor(p.bg), fg = hexColor(p.fg), meta = hexColor(p.meta),
    path = hexColor(p.path), note = hexColor(p.note), border = hexColor(p.border or p.meta),
  }
  if not e then
    paint({}, 0)
    return
  end
  if e.kind == "file" then
    renderFile(e, renderToken)
    return
  end
  local els, h = buildNonFile(e)
  paint(els, h)
end

--------------------------------------------------------------------------------
-- Preview pane lifecycle
--------------------------------------------------------------------------------

local function hidePreview()
  if preview then
    preview:hide()
  end
  imageCache = {} -- drop decoded preview images between opens
  existCache = {} -- recheck linked-file liveness on the next open
  scrollOffset = 0 -- next open starts at the top
end

--------------------------------------------------------------------------------
-- Atom callbacks
--------------------------------------------------------------------------------

-- A row was chosen. A non-empty batch commits as a group and the highlighted row
-- is ignored, otherwise the single highlighted item pastes. The atom fires this
-- before onClose, so the batch is still intact here; onClose clears it after.
local function onSelect(entry)
  if #batch > 0 then
    monitor.pasteBatch(batch)
  else
    monitor.paste(entry)
  end
end

-- The chooser closed for any reason. Cancel any uncommitted batch, hide the
-- preview, and tell the root (which drops the shortcut overlay). Injected as the
-- atom's onClose, so this file never learns about the overlay or the click watcher.
local function onClose()
  batch = {}
  -- Reset the footer to its no-batch labels now the batch is cleared, so the next
  -- open does not come up still reading "Delete marked". The picker is hidden here,
  -- so setFooter only updates the stored hints the next open renders from.
  refreshFooter()
  hidePreview()
  if cfg and cfg.onClose then
    cfg.onClose()
  end
end

-- The native atom reserved a companion rect beside the chooser. Record it and
-- render the current selection into the canvas (paint places it there). Fired at
-- show with a seed frame and again once the real chooser window settles, so
-- re-docking is expected and harmless. The chooserFrame is forwarded to the
-- injected onPositioned, which the composition root uses to dock the shortcut
-- panel below, so this file never learns about that panel.
local function onPositioned(chooserFrame, companionFrame)
  if companionFrame then
    previewFrame = companionFrame
    renderPreview(picker:selectedItem())
  end
  if cfg and cfg.onPositioned then
    -- The shortcut panel docks below this anchor. Span it across the chooser and the
    -- companion preview so it sits full width beneath the pair, not just the list.
    local anchor = chooserFrame
    if companionFrame then
      anchor = {
        x = chooserFrame.x, y = chooserFrame.y, h = chooserFrame.h,
        w = (companionFrame.x + companionFrame.w) - chooserFrame.x,
      }
    end
    cfg.onPositioned(anchor)
  end
end

local function onRightClick(entry)
  if not entry then return end
  store.removeEntry(entry)
  picker:refresh()
end

--------------------------------------------------------------------------------
-- Public API (the manager forwards these; the root's Hyper context binds the
-- navigation methods)
--------------------------------------------------------------------------------

function UI.show()
  if picker then picker:show() end
end

function UI.isShowing()
  return picker ~= nil and picker:isShowing()
end

function UI.hide()
  if picker then picker:hide() end
end

--- UI.refresh() - rebuild the visible rows, e.g. after a clear.
function UI.refresh()
  if picker then picker:refresh() end
end

--- UI.mediaReady() - a just-copied item's preview or thumbnail finished generating
--- off the main thread. Drop the caches that may hold its not-yet-ready state (the
--- thumb cache remembers a missing file as false, the preview cache an empty image)
--- and, if the chooser is open, repaint the rows and the current preview so the
--- fresh image or video frame appears without the user moving the selection.
function UI.mediaReady()
  thumbCache = {}
  imageCache = {}
  existCache = {}
  if picker and picker:isShowing() then
    picker:refresh()
    renderPreview(picker:selectedItem())
  end
end

function UI.selectNext()
  if picker then picker:selectNext() end
end

function UI.selectPrev()
  if picker then picker:selectPrev() end
end

function UI.insertSelected()
  if picker then picker:insertSelected() end
end

-- How far one Hyper+Cmd+j/k press scrolls the preview, roughly a mouse-wheel
-- notch, enough to read a long entry in a few presses without overshooting.
local PREVIEW_SCROLL_STEP = 120

--- UI.scrollPreviewDown() / UI.scrollPreviewUp() - scroll the canvas preview pane,
--- for the Hyper+Cmd+j / Hyper+Cmd+k bindings, so a clipboard entry taller than the
--- pane can be read. The offset is clamped to the content overflow by paint, and
--- repaint redraws the last content at the new offset without rebuilding it.
function UI.scrollPreviewDown()
  if not (preview and picker and picker:isShowing()) then return end
  scrollOffset = scrollOffset + PREVIEW_SCROLL_STEP
  repaint()
end

function UI.scrollPreviewUp()
  if not (preview and picker and picker:isShowing()) then return end
  scrollOffset = scrollOffset - PREVIEW_SCROLL_STEP
  repaint()
end

--- UI.appendSelected() - toggle the highlighted row in the append batch, for the
--- Hyper a binding. The chooser stays open. Refreshing redraws the rows with the
--- new order badges, and the atom's refresh preserves the highlight.
function UI.appendSelected()
  if not picker or not picker:isShowing() then return end
  local entry = picker:selectedItem()
  if not entry then return end
  toggleBatch(entry)
  picker:refresh()
  renderPreview(entry) -- update the preview's mark to match the row, without moving
  refreshFooter()
end

--- UI.deleteSelected() - delete from history, for the Hyper d binding. With a batch
--- marked (Hyper a), delete the whole marked set and clear it, matching the "Delete
--- marked" label; otherwise delete just the highlighted entry. Refreshing redraws the
--- remaining rows, and refreshFooter restores the label once the batch is empty.
function UI.deleteSelected()
  if not picker or not picker:isShowing() then return end
  if #batch > 0 then
    for _, e in ipairs(batch) do store.removeEntry(e) end
    batch = {}
  else
    local entry = picker:selectedItem()
    if not entry then return end
    store.removeEntry(entry)
  end
  picker:refresh()
  refreshFooter()
end

--- UI.build() - create the Chooser instance. Called once at start and reused
--- across shows. Maps the clipboard layout config onto the atom's layout, wires
--- the clipboard policy through the atom's callbacks, and reserves a companion
--- pane the width of the preview. The provider and the onActivity/onPositioned
--- hooks are injected from the composition root (native, with a docked shortcut
--- panel); onActivity is forwarded straight to the atom so the panel's idle timer
--- resets on each keypress, and onPositioned is composed inside our own so both
--- the preview and the panel get placed.
function UI.build()
  picker = Chooser.new({
    theme = cfg.theme,
    fieldMode = "filter",
    placeholder = "Search clipboard",
    pollInterval = cfg.previewPoll,
    rows = buildChoices,
    onSelect = onSelect,
    onHighlight = renderPreview,
    onClose = onClose,
    onPositioned = onPositioned,
    onActivity = cfg.onActivity,
    onRightClick = onRightClick,
    layout = {
      widthPct = cfg.chooserWidthPct,
      paneMaxW = cfg.paneMaxW,
      rowH = cfg.chooserRowH,
      baseH = cfg.chooserBaseH,
      rowCount = cfg.chooserRows,
      gap = cfg.uiGap,
      topFrac = cfg.uiTopFrac,
      minVPad = cfg.minVPad,
      -- The width the atom reserves for the docked companion preview beside the list.
      companionWidth = cfg.previewW,
    },
  })
  return UI
end

--- UI.configure(opts) - inject store, monitor, util, the Chooser factory, the
--- theme, and the layout config.
function UI.configure(opts)
  store = opts.store
  monitor = opts.monitor
  util = opts.util
  Chooser = opts.chooser
  cfg = opts
  return UI
end

return UI
