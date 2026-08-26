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

-- paste is the injected insertion engine, Olm.spoon/lib/paste.lua
local store, paste, util, media = nil, nil, nil, nil
-- Asked per row while building the list, so a growing entry can be marked. Defaults to
-- answering no, so the rows render the same when no accumulator is wired in at all.
local isAccumulator = function() return false end
local cfg = nil -- layout and size config, see configure
local Chooser = nil -- the injected Chooser.spoon factory
local picker = nil -- our Chooser instance, built once in UI.build
-- The manage history page, injected. It owns the duration grammar, the slices and their
-- wording, and this file only draws whatever it hands back, see prune.lua.
local prune = nil
-- Which page the one chooser is showing, nil for the history list and "prune" for manage
-- history. The atom's own drill down pair drives it, intercept acting on a page row without
-- closing the list and back stepping out of the page on Backspace from an empty field, so
-- there is one chooser, one context, and one set of keys either way.
local page = nil

-- What the field says it wants, one label per page. Named here rather than written at each of
-- the three places that set it, since the field is the only thing telling a person that the
-- same box now takes a duration instead of a search.
local PLACEHOLDER = {
  history = "Search clipboard",
  prune = "Duration or count, 4d12h or 100",
}

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
-- entry -> its lowercased searchable text, built once. Weak keyed, so an entry that leaves
-- the store falls out on its own. One thing does change an entry's content after capture,
-- the append accumulator growing it, and that is the single case this has to be told about,
-- through UI.entryChanged.
local hayCache = setmetatable({}, { __mode = "k" })

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

-- The friendly name of the app an entry was copied from, resolved from its bundle id and
-- cached. A false marks a bundle id with no resolvable name, looked up only once, nil when
-- the entry recorded no source. Shown in the preview header beside the app icon.
local nameCache = {}
local function appName(bundleID)
  if not bundleID then return nil end
  local c = nameCache[bundleID]
  if c ~= nil then return c or nil end
  local name = hs.application.nameForBundleID(bundleID) or false
  nameCache[bundleID] = name
  return name or nil
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

-- The file state badge, the shared rule in media.lua, fed this pane's memoized
-- existence check rather than a fresh stat, since filtering rebuilds every row on
-- every keystroke and a fresh stat per row per keystroke is the cost that memo
-- exists to avoid. See media.fileBadge for what the three answers mean.
local function fileBadge(e)
  return media.fileBadge(e, pathExists)
end

local function subTextFor(e)
  local parts = { KIND_LABEL[e.kind] or e.kind, util.relTime(e.ts) }
  -- The live accumulator says how many pieces it holds, since an entry that grew offscreen
  -- otherwise looks like any other row and its title only shows the first hundred characters
  -- collapsed onto one line. The count goes here rather than in the icon slot, which the kind
  -- glyph and the batch position keycap already contend for.
  local accumulating, pieces = isAccumulator(e)
  if accumulating then
    parts[#parts + 1] = pieces .. " pieces"
  end
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

-- The lowercased text the word matcher searches for an entry, its title, preview,
-- body, and any file paths folded together. Built once per entry and cached against
-- the live store reference, so a keystroke no longer rebuilds and lowercases the full
-- body of the whole history, which was the bulk of the old per-keystroke cost.
local function haystack(e)
  local hit = hayCache[e]
  if hit then return hit end
  local parts = { e.title, e.preview or "" }
  if e.text then parts[#parts + 1] = e.text end
  for _, el in ipairs(e.files or {}) do
    parts[#parts + 1] = el.path
  end
  local hay = table.concat(parts, " "):lower()
  hayCache[e] = hay
  return hay
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

-- Forward declaration. parseColor is defined below in the colour section, but the row
-- builder needs it to show a colour chip. It is only called at runtime, well after the
-- whole file has loaded, so the later assignment is in place by then.
local parseColor

-- Row icon helpers. The row icon now says what kind an entry is, not which app it came
-- from. Files show the system icon for their type, images their thumbnail, url and text a
-- flat monochrome mark drawn on a scratch canvas the way the keycap badges are, and a
-- colour literal a small chip of the colour. Each carries a stable iconKey so the atom
-- encodes it once and reuses it.
local ICON = 44 -- scratch canvas edge for the drawn marks, matching the keycap size

-- File type icons, keyed so the same type is fetched once. An extension drives the icon
-- with no need for the file to still exist, a folder and a generic file have their own
-- keys.
local fileIconCache = {}
local function cachedIcon(key, producer)
  local hit = fileIconCache[key]
  if hit ~= nil then return hit or nil, key end
  local img = producer() or false
  fileIconCache[key] = img
  return img or nil, key
end

local function fileRowIcon(e)
  local el = (e.files or {})[1]
  if not el then return nil, nil end
  if el.isDir then
    return cachedIcon("dir", function() return hs.image.iconForFileType("public.folder") end)
  end
  local ext = util.fileExt(el.path)
  if ext ~= "" then
    return cachedIcon("ext:" .. ext, function() return hs.image.iconForFileType(ext) end)
  end
  if hs.fs.attributes(el.path) then
    return cachedIcon("path:" .. el.path, function() return hs.image.iconForFile(el.path) end)
  end
  return cachedIcon("data", function() return hs.image.iconForFileType("public.data") end)
end

-- Kind marks, drawn once and cached. Both are emoji rendered to an image the same way the
-- keycap badges are, so the row icon family stays consistent. Text is the memo emoji, url is
-- the link emoji.
local glyphCache = {}

local function drawEmojiGlyph(glyph)
  local c = hs.canvas.new({ x = 0, y = 0, w = ICON, h = ICON })
  c[1] = { type = "text", text = glyph, textSize = 30,
    textAlignment = "center", frame = { x = 0, y = (ICON - 36) / 2, w = ICON, h = 38 } }
  local img = c:imageFromCanvas() or false
  c:delete()
  return img
end

-- Any emoji as a row icon, drawn once and cached by the string itself. Keyed by the glyph
-- rather than by what it stands for, so the kind marks and the manage history page's own
-- glyphs, which arrive as plain strings from a file that may not call into hs at all, share one
-- cache and one renderer.
local function emojiImage(glyph)
  local hit = glyphCache[glyph]
  if hit ~= nil then return hit or nil end
  local img = drawEmojiGlyph(glyph)
  glyphCache[glyph] = img
  return img or nil
end

local function kindGlyph(kind)
  return emojiImage(kind == "url" and "🔗" or "📝")
end

-- A small chip of a colour literal, cached by the colour so it is drawn once. A
-- translucent colour sits over a light fill so its alpha is visible.
local chipCache = {}
local function colorChip(col)
  local key = string.format("chip:%.3f,%.3f,%.3f,%.3f", col.r, col.g, col.b, col.a)
  local hit = chipCache[key]
  if hit ~= nil then return hit or nil, key end
  local c = hs.canvas.new({ x = 0, y = 0, w = ICON, h = ICON })
  local box = { x = 7, y = 7, w = ICON - 14, h = ICON - 14 }
  local radii = { xRadius = 6, yRadius = 6 }
  if col.a < 1 then
    c[#c + 1] = { type = "rectangle", action = "fill", fillColor = { white = 0.9, alpha = 1 },
      roundedRectRadii = radii, frame = box }
  end
  c[#c + 1] = { type = "rectangle", action = "fill",
    fillColor = { red = col.r, green = col.g, blue = col.b, alpha = col.a },
    roundedRectRadii = radii, frame = box }
  local img = c:imageFromCanvas() or false
  c:delete()
  chipCache[key] = img
  return img or nil, key
end

-- The manage history page's rows, its own plain data with each glyph string turned into the
-- icon image here. The page never touches a canvas and this never decides what a row means,
-- which is the whole split, and it is why that file loads and can be tested without hs.
local function pruneChoices(q)
  local out = prune.rows(q)
  for _, r in ipairs(out) do
    if r.glyph then
      r.image, r.iconKey = emojiImage(r.glyph), "glyph:" .. r.glyph
      r.glyph = nil
    end
  end
  return out
end

-- The atom's rows supplier. Returns plain items; the atom styles them with the
-- active palette. Filtering, the type prefix, the batch mark, and the kind icon
-- are all clipboard policy and live here. The free-text part runs through
-- the injected word matcher (Chooser.matchers.words), not the fuzzy one the label choosers
-- use, so the full body of every entry stays searchable with a cheap byte scan and nothing
-- is truncated. Its result is used only as a yes or no, so a match keeps the row and the
-- store's recency order is preserved.
local function buildChoices(q)
  -- The page is a different list, not a filtered one, so it answers first and the type prefix
  -- and the word matcher below never see its query. That field is a duration being typed rather
  -- than a search, which is also why the chooser opts out of the shared matcher entirely.
  if page == "prune" then return pruneChoices(q) end

  local kind, rest = parseQuery(q)
  rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
  local out = {}
  for _, e in ipairs(store.all()) do
    if (not kind or e.kind == kind) and (rest == "" or cfg.matcher(rest, haystack(e)) ~= nil) then
      -- An appended row shows its 1-based batch position as its icon (the keycap
      -- number), the most visible mark on the native chooser, which renders no icon
      -- badge. Otherwise the icon says the kind: an image shows its own thumbnail, a
      -- file the system icon for its type, a colour literal a chip of the colour, and
      -- url and text a flat monochrome mark. The source app is no longer a row icon, it
      -- moved to the preview header. The stable iconKey lets the atom encode each icon
      -- once and reuse it.
      local pos = batchPos(e)
      local img, iconKey
      if pos then
        img, iconKey = keycapImage(pos), "batch:" .. pos
      elseif e.kind == "image" then
        local thumb = thumbImage(e.thumb)
        if thumb then img, iconKey = thumb, "thumb:" .. e.thumb end
      elseif e.kind == "file" then
        img, iconKey = fileRowIcon(e)
      elseif e.kind == "url" then
        img, iconKey = kindGlyph("url"), "glyph:url"
      else
        local col = parseColor(e.text)
        if col then
          img, iconKey = colorChip(col)
        else
          img, iconKey = kindGlyph("text"), "glyph:text"
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
-- panel (CanvasPanel's 14/10) so the two canvas panels read as one component.
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

-- Built only from paint(), which never runs before previewFrame holds the atom's
-- real rect, so the canvas is sized right from its first frame and never sized off
-- a config number.
local function ensurePreview()
  if preview then return end
  preview = hs.canvas.new({ x = 0, y = 0, w = previewFrame.w, h = previewFrame.h })
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
local function styled(text, color, size, lineH, align)
  return hs.styledtext.new(text, {
    font = { name = BODY_FONT, size = size },
    color = color,
    paragraphStyle = { maximumLineHeight = lineH, minimumLineHeight = lineH, alignment = align },
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

-- The preview header line, read as two anchored groups. The source, the app icon and its
-- name, sits at the left. The facts the builder joined, the type and size and time, sit
-- flush against the right edge in a quiet uppercase strip, joined by a plain gap where the
-- builder used a dot, so the line reads as two calm anchors rather than one centred run. The
-- name keeps its natural case so the source reads as a proper noun against the facts, and it
-- is capped to the space before the facts so the two never touch. Returns the y below the
-- single header line. Every kind's builder routes its meta through here, so the header is one
-- place, and each still joins its parts with the canonical dot, which this presenter reforms.
local HDR_ICON = 15
local META_GAP = "   " -- the facts separator, a plain gap in place of the builder dot
local function metaHeader(els, e, w, meta)
  local ic = e and appIcon(e.sourceApp) or nil
  local name = e and appName(e.sourceApp) or nil
  local lineH = math.ceil(META_SIZE * LINE_MULT)
  local x = 0
  if ic then
    els[#els + 1] = { type = "image", image = ic, imageScaling = "scaleProportionally",
      imageAlignment = "center", frame = { x = 0, y = 0, w = HDR_ICON, h = HDR_ICON } }
    x = HDR_ICON + 6
  end
  -- Facts flush right. The strip is pure ascii once the dot is gone, so the character count
  -- times the mono glyph width estimates its pixel width, enough to reserve the name's room,
  -- while the right alignment itself hugs the edge exactly with no reliance on that estimate.
  local factsW = 0
  if meta and #meta > 0 then
    local facts = (meta:gsub("  ·  ", META_GAP)):upper()
    factsW = math.ceil(#facts * monoCharWidth(META_SIZE))
    els[#els + 1] = { type = "text", text = styled(facts, colors.meta, META_SIZE, lineH, "right"),
      frame = { x = x, y = 0, w = w - x, h = lineH * 2 } }
  end
  if name then
    local avail = math.max(0, w - x - factsW - 12)
    if avail > 0 then
      els[#els + 1] = { type = "text", text = styled(name, colors.meta, META_SIZE, lineH),
        frame = { x = x, y = 0, w = avail, h = lineH * 2 } }
    end
  end
  return lineH
end

-- Lay the content blocks into the canvas: the shared surface first (unclipped),
-- then a clip to the inner box, then the content shifted by the padding and the
-- live scroll. maxScroll comes from the overflow, so a tall entry scrolls under the
-- padding instead of spilling over the border. Records the model for repaint().
local function paint(contentEls, contentH)
  if not previewFrame then return end
  ensurePreview()
  lastEls, lastH = contentEls, contentH
  local frame = previewFrame
  local innerW = frame.w - 2 * PAD_X
  local innerH = frame.h - 2 * PAD_Y
  maxScroll = math.max(0, contentH - innerH)
  if scrollOffset > maxScroll then scrollOffset = maxScroll end
  if scrollOffset < 0 then scrollOffset = 0 end

  -- Background and rounded border come from the shared surface, the same routine the
  -- CanvasPanel hint bar draws, so the preview and the panel are one component just
  -- placed differently. Then a clip to the inner box confines the content.
  local els = {}
  for _, el in ipairs(cfg.surface and cfg.surface(frame.w, frame.h) or {}) do
    els[#els + 1] = el
  end
  els[#els + 1] = { type = "rectangle", action = "clip",
    frame = { x = PAD_X, y = PAD_Y, w = innerW, h = innerH } }
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

-- The inner content width, the companion frame minus horizontal padding. Only ever
-- called while building content for renderPreview, which has already deferred when
-- there is no frame yet, so previewFrame is always real here.
local function innerWidth()
  return previewFrame.w - 2 * PAD_X
end

-- The inner content height, the companion frame minus vertical padding. Used to
-- size the colour swatch so it fills the pane without forcing a scroll. Same
-- guarantee as innerWidth, previewFrame is always real by the time this runs.
local function innerHeight()
  return previewFrame.h - 2 * PAD_Y
end

--------------------------------------------------------------------------------
-- Colour swatch (a text entry that is a single colour literal)
--------------------------------------------------------------------------------
--
-- When the copied text is nothing but one colour value (hex, rgb/rgba, or
-- hsl/hsla), the preview shows that colour's three canonical forms and a large
-- swatch filling the pane, instead of the raw monospace text. Parsing is strict,
-- the whole trimmed string must be the colour, so prose that merely mentions #fff
-- is left as ordinary text. All values are normalised to red/green/blue/alpha in
-- 0..1, the canvas colour space.

local function clamp01(x)
  return x < 0 and 0 or (x > 1 and 1 or x)
end

-- Format an alpha as the shortest decimal (0.5, not 0.50; 1, not 1.00).
local function trimNum(x)
  local s = string.format("%.2f", x)
  return (s:gsub("(%..-)0+$", "%1"):gsub("%.$", ""))
end

-- HSL (h in degrees, s and l in 0..1) to RGB in 0..1.
local function hslToRgb(h, s, l)
  h = (h % 360) / 360
  if s == 0 then return l, l, l end
  local function hue(p, q, t)
    if t < 0 then t = t + 1 end
    if t > 1 then t = t - 1 end
    if t < 1 / 6 then return p + (q - p) * 6 * t end
    if t < 1 / 2 then return q end
    if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
    return p
  end
  local q = l < 0.5 and l * (1 + s) or l + s - l * s
  local p = 2 * l - q
  return hue(p, q, h + 1 / 3), hue(p, q, h), hue(p, q, h - 1 / 3)
end

-- RGB in 0..1 to HSL (h in degrees, s and l in 0..1), so any colour can be shown
-- in every form regardless of how it was copied.
local function rgbToHsl(r, g, b)
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local l = (mx + mn) / 2
  if mx == mn then return 0, 0, l end
  local d = mx - mn
  local s = l > 0.5 and d / (2 - mx - mn) or d / (mx + mn)
  local h
  if mx == r then
    h = (g - b) / d + (g < b and 6 or 0)
  elseif mx == g then
    h = (b - r) / d + 2
  else
    h = (r - g) / d + 4
  end
  return h * 60, s, l
end

-- #rgb, #rgba, #rrggbb, or #rrggbbaa. Shorthand is expanded before slicing.
local function parseHexColor(s)
  local hex = s:match("^#(%x+)$")
  if not hex then return nil end
  local n = #hex
  if n == 3 or n == 4 then
    hex = hex:gsub("(%x)", "%1%1")
    n = #hex
  end
  if n ~= 6 and n ~= 8 then return nil end
  local function comp(i)
    return tonumber(hex:sub(i, i + 1), 16) / 255
  end
  return { r = comp(1), g = comp(3), b = comp(5), a = n == 8 and comp(7) or 1 }
end

-- Split the args of a functional colour on commas, whitespace, or the slash CSS
-- uses before alpha, so rgb(1 2 3 / 50%) and rgba(1, 2, 3, 0.5) both parse.
local function colorArgs(inner)
  local out = {}
  for tok in inner:gmatch("[^,%s/]+") do
    out[#out + 1] = tok
  end
  return out
end

-- Read a trailing alpha token, either 0..1 or a percentage. Defaults to 1.
local function parseAlpha(tok)
  if not tok then return 1 end
  local pct = tok:match("^([%d%.]+)%%$")
  if pct then return clamp01(tonumber(pct) / 100) end
  return clamp01(tonumber(tok) or 1)
end

-- rgb(r, g, b) / rgba(r, g, b, a). Channels are 0..255 or percentages.
local function parseRgbColor(s)
  local inner = s:match("^rgba?%((.+)%)$")
  if not inner then return nil end
  local a = colorArgs(inner)
  if #a < 3 or #a > 4 then return nil end
  local function chan(tok)
    local pct = tok:match("^([%d%.]+)%%$")
    if pct then return clamp01(tonumber(pct) / 100) end
    local v = tonumber(tok)
    return v and clamp01(v / 255) or nil
  end
  local r, g, b = chan(a[1]), chan(a[2]), chan(a[3])
  if not (r and g and b) then return nil end
  return { r = r, g = g, b = b, a = parseAlpha(a[4]) }
end

-- hsl(h, s%, l%) / hsla(h, s%, l%, a). Hue in degrees, saturation and lightness
-- as percentages.
local function parseHslColor(s)
  local inner = s:match("^hsla?%((.+)%)$")
  if not inner then return nil end
  local a = colorArgs(inner)
  if #a < 3 or #a > 4 then return nil end
  local h = tonumber((a[1]:gsub("deg$", "")))
  local sat = tonumber((a[2]:gsub("%%$", "")))
  local lit = tonumber((a[3]:gsub("%%$", "")))
  if not (h and sat and lit) then return nil end
  local r, g, b = hslToRgb(h, clamp01(sat / 100), clamp01(lit / 100))
  return { r = r, g = g, b = b, a = parseAlpha(a[4]) }
end

-- The strict gate: a trimmed string that is exactly one colour literal, else nil.
-- The length cap keeps the match cheap and rejects a stray paragraph outright.
parseColor = function(text)
  local s = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if #s == 0 or #s > 64 then return nil end
  s = s:lower()
  return parseHexColor(s) or parseRgbColor(s) or parseHslColor(s)
end

-- The three canonical forms of a colour, aligned label + value in the monospace
-- body, with alpha carried only when it is not fully opaque.
local function colorReps(c)
  local R = math.floor(c.r * 255 + 0.5)
  local G = math.floor(c.g * 255 + 0.5)
  local B = math.floor(c.b * 255 + 0.5)
  local h, s, l = rgbToHsl(c.r, c.g, c.b)
  h, s, l = math.floor(h + 0.5), math.floor(s * 100 + 0.5), math.floor(l * 100 + 0.5)
  if c.a < 1 then
    local A = math.floor(c.a * 255 + 0.5)
    return {
      string.format("HEX   #%02X%02X%02X%02X", R, G, B, A),
      string.format("RGB   rgba(%d, %d, %d, %s)", R, G, B, trimNum(c.a)),
      string.format("HSL   hsla(%d, %d%%, %d%%, %s)", h, s, l, trimNum(c.a)),
    }
  end
  return {
    string.format("HEX   #%02X%02X%02X", R, G, B),
    string.format("RGB   rgb(%d, %d, %d)", R, G, B),
    string.format("HSL   hsl(%d, %d%%, %d%%)", h, s, l),
  }
end

-- A checkerboard behind a translucent swatch, so alpha reads against it instead of
-- blending invisibly into the panel. Drawn only when the colour is not opaque, and
-- clipped by the caller to the rounded swatch box. The cell scales with the swatch
-- so the grid stays ~8 cells wide at any size, a fixed handful of rectangles.
local function appendChecker(els, x0, y0, w, h)
  local cell = math.max(8, math.floor(math.min(w, h) / 8))
  els[#els + 1] = { type = "rectangle", action = "fill", fillColor = { white = 0.92, alpha = 1 },
    frame = { x = x0, y = y0, w = w, h = h } }
  local dark = { white = 0.72, alpha = 1 }
  local rowIdx, yy = 0, y0
  while yy < y0 + h do
    local ch = math.min(cell, y0 + h - yy)
    local colIdx, xx = 0, x0
    while xx < x0 + w do
      local cw = math.min(cell, x0 + w - xx)
      if (rowIdx + colIdx) % 2 == 1 then
        els[#els + 1] = { type = "rectangle", action = "fill", fillColor = dark,
          frame = { x = xx, y = yy, w = cw, h = ch } }
      end
      xx, colIdx = xx + cell, colIdx + 1
    end
    yy, rowIdx = yy + cell, rowIdx + 1
  end
end

-- The swatch block: a plain rectangle filled with the colour, over a checker for
-- transparency so a translucent colour reads against it instead of blending into
-- the panel. No border and no rounded corners, it is a flat block of the colour.
local function appendSwatch(els, color, x0, y0, w, h)
  if color.alpha < 1 then appendChecker(els, x0, y0, w, h) end
  els[#els + 1] = { type = "rectangle", action = "fill", fillColor = color,
    frame = { x = x0, y = y0, w = w, h = h } }
  return y0 + h
end

-- Build the colour preview: an uppercase meta line, the three canonical forms, and
-- the swatch. The swatch fills the width and is square, unless the space left in the
-- pane is shorter than the width, in which case it takes that height so it still
-- fits without a scroll (the pane is taller than wide, so a square usually fits).
local function buildColor(e, c)
  local els = {}
  local w = innerWidth()
  local meta = withBatchMark("Color  ·  " .. util.relTime(e.ts), e)
  local y = metaHeader(els, e, w, meta) + BLOCK_GAP
  y = appendText(els, table.concat(colorReps(c), "\n"), 0, y, w, colors.fg, BODY_SIZE) + BLOCK_GAP
  local avail = math.max(0, innerHeight() - y)
  local side = (avail > 0 and avail < w) and avail or w
  local fill = { red = c.r, green = c.g, blue = c.b, alpha = c.a }
  return els, appendSwatch(els, fill, 0, y, w, side)
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
  local y = metaHeader(els, e, w, meta) + 4
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
    local y = metaHeader(els, e, w, meta) + BLOCK_GAP
    local img = previewImage(e.prev)
    if img then
      y = appendImage(els, img, 0, y, w)
    else
      y = appendText(els, "No preview.", 0, y, w, colors.note, BODY_SIZE)
    end
    return els, y
  end
  -- A text entry that is nothing but a single colour literal renders as a swatch
  -- with its canonical forms, rather than the raw monospace text.
  if e.kind == "text" then
    local c = parseColor(e.text)
    if c then return buildColor(e, c) end
  end
  local meta = (KIND_LABEL[e.kind] or e.kind) .. "  ·  " .. util.relTime(e.ts)
  -- Text shows its character count, computed once at capture, so the pane never
  -- recounts on highlight.
  if e.kind == "text" and e.chars then meta = meta .. "  ·  " .. e.chars .. " chars" end
  meta = withBatchMark(meta, e)
  local y = metaHeader(els, e, w, meta) + BLOCK_GAP
  local text = e.text or ""
  local capped = #text > TEXT_DISPLAY_CAP
  if capped then text = text:sub(1, TEXT_DISPLAY_CAP) .. "\n\n… truncated" end
  y = appendText(els, text, 0, y, w, colors.fg, BODY_SIZE)
  return els, y
end

-- Read the head of a file off the main thread, so a slow or large file cannot
-- freeze the pane. head -c cap+1 lets us detect truncation. head is optional, and a
-- machine without it should read exactly like a task that failed to start, which is
-- already the shape the caller understands.
local function asyncRead(path, cap, cb)
  local headPath = cfg.deps and cfg.deps.path("head")
  if not headPath then
    cb("", true)
    return
  end
  local t = hs.task.new(headPath, function(code, out)
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
-- reset the scroll to the top for the new entry, then paint the model. The atom
-- seeds one call before it has positioned anything, so the very first call of a
-- show can land with no companion rect known yet. Nothing here can size or measure
-- without one, so it defers entirely rather than guessing a width, the same way the
-- processes and filesearch panes defer their own first paint. onPositioned calls
-- this again the moment it has a real rect, well before anything is visible.
local function renderPreview(e)
  if not previewFrame then return end
  renderToken = renderToken + 1
  scrollOffset = 0
  -- Only the text colours come from the palette; the pane's background and border are
  -- the shared surface, drawn in paint() through the injected cfg.surface.
  local p = picker:activeTheme().preview
  colors = {
    fg = hexColor(p.fg), meta = hexColor(p.meta),
    path = hexColor(p.path), note = hexColor(p.note),
  }
  if not e then
    paint({}, 0)
    return
  end
  -- A manage history row, whose pane lists what the row would take rather than the content of
  -- one entry. Drawn with the same meta line and monospace body every other kind uses, since
  -- what differs is the text and nothing about the shape.
  if e.side then
    local meta, body = prune.preview(e)
    if not meta then
      paint({}, 0)
      return
    end
    local els, w = {}, innerWidth()
    local y = metaHeader(els, nil, w, meta) + BLOCK_GAP
    paint(els, appendText(els, body, 0, y, w, colors.fg, BODY_SIZE))
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
  -- A manage history row is answered in intercept, which acts and keeps the list open, so
  -- nothing that pastes should ever see one. This is the guard for the paths intercept does not
  -- cover rather than a second dispatch, since pasting a slice descriptor is meaningless.
  if entry and entry.side then return end
  if #batch > 0 then
    -- The deferred reorder. Collecting never touches the store, so the list stays put while
    -- the picker is open, and only here, on commit and close, does each collected entry float
    -- to the top in collected order, saved once, so the next open reflects it. It happens on
    -- this side of the call because what a paste means for the list is this spoon's policy and
    -- never the engine's, and the whole batch is reordered before any of it pastes, exactly as
    -- it was when the engine's own pasteBatch did it.
    for _, e in ipairs(batch) do
      store.moveToFront(e)
    end
    paste.pasteBatch(batch)
  else
    -- Same policy for a single row, and gated on the paste having started, since an entry whose
    -- media has gone pastes nothing and has no business floating to the top for it.
    if paste.paste(entry) then
      store.moveToFront(entry)
    end
  end
end

-- A row was chosen while the manage history page is on. Acting here rather than in onSelect is
-- what the atom's intercept is for, since a delete leaves a list that should now read
-- differently rather than one that should be gone, so the slice goes, the counts redraw
-- themselves from the store, and the page stays open for a second pass. Answering false for
-- every other row is what leaves Return meaning paste on the history list.
local function intercept(item)
  if page ~= "prune" or not item or not item.side or item.side == "hint" then return false end
  local removed = prune.apply(item)
  local left = #store.all()
  if cfg.notify then cfg.notify(prune.message(item, removed, left)) end
  return true
end

-- Backspace on an empty field, the way out of the page. It is the same press that steps out of
-- a hosted list in the launcher and out of a typed scope, so one habit covers all three, and
-- answering false with no page on keeps it ordinary editing everywhere else.
local function back()
  if page == nil then return false end
  UI.leaveManageHistory()
  return true
end

-- The chooser closed for any reason. Cancel any uncommitted batch, hide the
-- preview, and tell the root (which drops the shortcut overlay). Injected as the
-- atom's onClose, so this file never learns about the overlay or the click watcher.
local function onClose()
  batch = {}
  -- Leave the page behind, so the next open is the history list. The same reason the launcher
  -- drops a hosted list on show, a page is where you were rather than a setting you chose.
  page = nil
  if picker then picker:setPlaceholder(PLACEHOLDER.history) end
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
  if not entry or entry.side then return end
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

--- UI.entryChanged(entry) - one entry's content was rewritten in place, which only the append
--- accumulator does. Drop its cached searchable text, or a search would keep missing the words
--- just appended, and repaint if the chooser happens to be open so the row and the preview show
--- the grown content. Nothing else has to be invalidated, since the row is built from the entry
--- itself and the media caches are keyed by path.
function UI.entryChanged(entry)
  hayCache[entry] = nil
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

--- UI.scrollPreviewBy(points) - move the preview by a distance in points, positive being
--- further down the content. The one place the offset changes, so the keys and the
--- trackpad cannot drift apart, and the clamp to the content overflow stays where it
--- already was, in paint. Repaint redraws the last content at the new offset without
--- rebuilding it.
function UI.scrollPreviewBy(points)
  if not (preview and picker and picker:isShowing()) then return end
  scrollOffset = scrollOffset + (tonumber(points) or 0)
  repaint()
end

--- UI.scrollPreviewDown() / UI.scrollPreviewUp() - one step of the above, for the
--- Hyper+Cmd+j / Hyper+Cmd+k bindings, so a clipboard entry taller than the pane can be
--- read without reaching for the trackpad.
function UI.scrollPreviewDown()
  UI.scrollPreviewBy(PREVIEW_SCROLL_STEP)
end

function UI.scrollPreviewUp()
  UI.scrollPreviewBy(-PREVIEW_SCROLL_STEP)
end

--- UI.appendSelected() - toggle the highlighted row in the append batch, for the
--- Hyper a binding. The chooser stays open. Refreshing redraws the rows with the
--- new order badges, and the atom's refresh preserves the highlight.
function UI.appendSelected()
  if not picker or not picker:isShowing() or page then return end
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
  -- Inert on the manage history page. Every row there already deletes, on Return, in a slice
  -- whose size the row states, and a d that took the highlighted slice instead would be the one
  -- key in this picker whose meaning silently changed with the page.
  if not picker or not picker:isShowing() or page then return end
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

--- UI.manageHistory() - show the manage history page, or step back off it when it is already
--- on, for the Hyper m binding and for the launcher row that opens straight onto it. One verb
--- both ways round, because the key is what a person will press again to get out and finding it
--- inert there is worse than a second key nobody would guess.
---
--- Opening from the launcher arrives here with nothing showing, so the picker is shown too, and
--- the page is set BEFORE the show since showing is what builds the first rows.
function UI.manageHistory()
  if not picker then return end
  if page == "prune" then
    UI.leaveManageHistory()
    return
  end
  page = "prune"
  picker:setPlaceholder(PLACEHOLDER.prune)
  if not picker:isShowing() then
    picker:show()
    return
  end
  -- Whatever was typed was a search over history, and on this page the same text would read as
  -- a duration, so the field starts empty and the ladder is what a person sees first.
  picker:setQuery("")
  picker:refresh(true)
  renderPreview(picker:selectedItem())
end

--- UI.leaveManageHistory() - give the history list back, the answer to Backspace on an empty
--- field and to pressing the page's own key again. Rebuilds from the top, since the list now
--- means something else and the highlight has no business staying on the row number the page
--- left it on.
function UI.leaveManageHistory()
  if page == nil then return end
  page = nil
  if not picker then return end
  picker:setPlaceholder(PLACEHOLDER.history)
  picker:setQuery("")
  picker:refresh(true)
  renderPreview(picker:selectedItem())
end

--- UI.isManagingHistory() - whether the page is on, read by the plugin's own predicate so the
--- hint panel lists the way out exactly while there is one.
function UI.isManagingHistory()
  return page == "prune" and picker ~= nil and picker:isShowing()
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
    fieldMode = Chooser.fieldModes.filter,
    -- Opt out of the atom's filtering and ranking. The clipboard owns its query (it parses
    -- a type prefix) and keeps recency order, so buildChoices filters with the shared
    -- matcher itself rather than handing the atom the full list to rank.
    matcher = false,
    placeholder = PLACEHOLDER.history,
    pollInterval = cfg.previewPoll,
    rows = buildChoices,
    onSelect = onSelect,
    -- The drill down pair. intercept is what lets a manage history row act and leave the list
    -- standing, since hs.chooser hardwires Return to complete and a row whose result is a
    -- differently counted list has nothing left to change once the window is gone, and back is
    -- the way out of it again.
    intercept = intercept,
    back = back,
    onHighlight = renderPreview,
    onClose = onClose,
    onPositioned = onPositioned,
    onActivity = cfg.onActivity,
    -- A trackpad or a wheel over the preview pane, which a canvas cannot report for
    -- itself, so the atom watches for it and hands over a distance in points. The same
    -- verb the two keys go through, so there is one notion of where the pane is scrolled
    -- to and no second one to keep in step.
    onScroll = UI.scrollPreviewBy,
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

--- UI.configure(opts) - inject store, the insertion engine, util, media (for the shared file
--- state rule fileBadge draws on), prune (the manage history page, whose rows and wording this
--- file only draws), the Chooser factory, the theme, the shared
--- surface routine (opts.surface, drawing the preview pane's background and
--- border), and the layout config.
function UI.configure(opts)
  store = opts.store
  paste = opts.paste
  util = opts.util
  media = opts.media
  prune = opts.prune
  Chooser = opts.chooser
  isAccumulator = opts.isAccumulator or isAccumulator
  cfg = opts
  return UI
end

return UI
