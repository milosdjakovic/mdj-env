--- The clipboard consumer of the shared Chooser atom, plus the live preview pane.
---
--- The generic chooser behavior (the window, theming, row styling, navigation,
--- positioning, and click away dismissal) lives in Chooser.spoon, injected here
--- as a factory. This file supplies only clipboard policy. The rows, what a
--- selection pastes, the append batch, right click delete, and the preview that
--- docks in the companion pane the atom reserves beside the chooser.
---
--- The preview is the shared docked pane, lib/dockedpane.lua, granted for the manifest's
--- `pane = true`, which owns the canvas in the companion frame the atom reserves, its dock,
--- the empty state, the scroll and the teardown. It never takes key focus, so typing always
--- stays in the search field. The atom polls the highlighted row and calls onHighlight, which
--- hands the pane a new tree here.
---
--- Preview rendering is per kind, a tree of UI kit nodes laid out onto a canvas (never a
--- webview). Text and url wrap in the code role; image and video show the downscaled preview
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
-- Migrated onto host/stage, the trickle migration. This plugin owns no Chooser instance and
-- builds no window any more, so isShowing lives here instead as a plain flag, true from the
-- moment UI.onPresent runs until onClose says otherwise. It is also what
-- providers/hammerspoon.lua's own toggle now reads and drives, through UI.isShowing and
-- UI.hide, in place of the instance it used to ask directly.
--
-- Review finding H6. This file used to also hold lastHighlighted, a module local cache set
-- only by renderPreview, the atom's own onHighlight target, and read back by appendSelected,
-- deleteSelected, and every explicit re-render. It was never seeded any other way and never
-- cleared on close, so a cold open answered whatever the previous session had highlighted for
-- one poll interval, 80 milliseconds, and UI.deleteSelected read it unconditionally, an
-- unrecoverable wrong deletion the one real cost among the three plugins this bug touched.
-- cfg.stageSelectedItem, host/stage's own Stage:selectedItem() published for exactly this,
-- replaces every read the cache used to answer.
local showing = false
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
local companion = nil -- the shared docked pane, made in configure from the root's grant
local renderToken = 0 -- bumped each render; async results check it to avoid stale writes
local thumbCache = {} -- path -> hs.image (or false), for row thumbnails
local imageCache = {} -- preview png path -> hs.image (or false), so a re-highlight re-decodes nothing
local iconCache = {} -- bundle id -> hs.image (or false), for row source-app icons
local existCache = {} -- linked-file path -> bool, so the badge does not restat per keystroke
-- entry -> its history row, so a keystroke over a thousand entries builds no row and no names
-- table it built before, decided 2026-10-17 after a review counted every row rebuilt on every
-- key. Weak keyed, so an entry that leaves the store falls out on its own. A row is rebuilt when
-- its entry's content changes, UI.entryChanged, when rowGen moves, on every open and when media
-- lands, since a thumbnail, an icon or a file badge may then read differently, when its batch
-- position changes, and when its age text would read differently, at the time
-- util.relTimeChanges answers, so the subtitle is always what it would be built fresh. Only the
-- bonus, the entry's place in a store that grows, is written on every keystroke.
local rowCache = setmetatable({}, { __mode = "k" })
local rowGen = 0

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
-- result to the picker. Already a no op before this migration, since the native backend,
-- the only one left since the webview backend was retired, has no setFooter method at all,
-- and host/stage exposes none either, so this stays exactly as inert as it already was
-- rather than gaining a new gap the migration would have to answer for.
--
-- Review finding L2. A genuine no op body rather than a conditional guarding an empty
-- block, legal Lua the first version of this fix left behind for a reader to re derive.
-- Nothing calls into this function differently depending on cfg.footerFor, so there is
-- nothing left to branch on until a future backend, or a future stage capability, answers
-- setFooter, at which point this is the one place that resumes working from rather than
-- being rediscovered from nothing.
local function refreshFooter()
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

-- Split an optional leading type token ("img ...", "file: ...") off the query. The supplier
-- reads the kind to narrow the candidates and UI.searchText answers the rest, so the grammar is
-- parsed here once for both and the shared search never sees the prefix.
local function parseQuery(q)
  q = q or ""
  local word, rest = q:match("^(%a+)[:%s]%s*(.*)$")
  if word and KIND_PREFIX[word:lower()] then
    return KIND_PREFIX[word:lower()], rest
  end
  return nil, q
end

-- An appended row (Hyper+a) is marked by swapping its icon for a big keycap number, since a
-- tiny text prefix was too easy to miss. The icon is a keycap digit 1 to 9, capping at one
-- shared mark past nine, so it says "queued and roughly where", not exact depth. The keys are
-- declared in the manifest and Olm draws them.
local function queuedIcon(pos)
  return pos <= 9 and ("queued" .. pos) or "queuedMore"
end

-- Forward declaration. parseColor is defined below in the colour section, but the row
-- builder needs it to show a colour chip. It is only called at runtime, well after the
-- whole file has loaded, so the later assignment is in place by then.
local parseColor

-- Row icon helpers. The row icon now says what kind an entry is, not which app it came
-- from. Files show the system icon for their type, images their thumbnail, url and text a
-- named icon Olm draws, and a colour literal a small chip of the colour. The pictures and the
-- chip are content and carry a stable iconKey so the atom encodes each once and reuses it.
local ICON = 44 -- scratch canvas edge for the colour chip, the one mark this file still draws

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

local kit = nil -- the UI kit, needs.lib.ui, set by configure, declared here so the row icons see it

-- A small chip of a colour literal, cached by the colour so it is drawn once. A
-- translucent colour sits over a light fill so its alpha is visible.
local chipCache = {}
local function colorChip(col)
  -- The chip's corner is the kit's nested radius, so a square surface draws a square chip.
  local r = kit.tokens().radius.nested
  local key = string.format("chip:%.3f,%.3f,%.3f,%.3f:%g", col.r, col.g, col.b, col.a, r)
  local hit = chipCache[key]
  if hit ~= nil then return hit or nil, key end
  local c = hs.canvas.new({ x = 0, y = 0, w = ICON, h = ICON })
  local box = { x = 7, y = 7, w = ICON - 14, h = ICON - 14 }
  local radii = { xRadius = r, yRadius = r }
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

-- What a history row is searched by, besides its title. A text or url entry names its full body,
-- a further name of the row matched at the title's levels, so a word deep in a long body is
-- found by the shared search's long field rule, a word start or inside a word, with nothing
-- truncated. A copied file answers only to its file name, the last part of each path, Milos's
-- decision of 2026-10-17, since a folder word matched every file under that folder, and support
-- listed eight screenshots saved under Application Support. So a file entry names the basename
-- of every path and nothing else, its body included. The preview is not among them, it reads
-- 1200 chars or URL or image, so searching it once made chars match every text entry.
local function namesOf(e)
  local names = {}
  if e.kind == "file" then
    for _, el in ipairs(e.files or {}) do
      if type(el.path) == "string" then names[#names + 1] = util.basename(el.path) end
    end
    return names
  end
  if type(e.text) == "string" and e.text ~= "" then names[#names + 1] = e.text end
  return names
end

-- The atom's rows supplier. Returns plain items, every history entry of the kind the query
-- names, in the store's order, newest first, and the shared search ranks them. The type prefix,
-- the batch mark and the kind icon are clipboard policy and live here, and so does the
-- narrowing by kind, since it is a filter the grammar states rather than a match. What is left
-- after the prefix reaches the shared search through UI.searchText, the presentation's
-- searchText. A row filters on its title, since its subtitle is a kind, an age and a count,
-- names its body or its file names, and carries its place in the store as a bonus, so among rows
-- the search calls equally good the newer leads, and a newer entry never lifts over a better
-- match.
local function buildChoices(q)
  -- The page is a different list, not a filtered one, so it answers first and the type prefix
  -- never sees its query. That field is a duration being typed rather than a search, which is
  -- why UI.searchText answers nothing on this page and the shared search keeps these rows as
  -- they are.
  if page == "prune" then return prune.rows(q) end

  local kind = parseQuery(q)
  local out = {}
  local all = store.all()
  local count = #all
  local now = os.time()
  for i, e in ipairs(all) do
    local cached = rowCache[e]
    local pos = (not kind or e.kind == kind) and batchPos(e) or nil
    if cached and (not kind or e.kind == kind) and cached.gen == rowGen and cached.pos == pos
      and now < cached.ageUntil then
      local row = cached.row
      row.bonus = (count - i + 1) / count
      out[#out + 1] = row
    elseif not kind or e.kind == kind then
      -- An appended row shows its 1-based batch position as its icon (the keycap
      -- number), the most visible mark on the native chooser, which renders no icon
      -- badge. Otherwise the icon says the kind: an image shows its own thumbnail, a
      -- file the system icon for its type, a colour literal a chip of the colour, and
      -- url and text a named icon. The source app is no longer a row icon, it
      -- moved to the preview header. The stable iconKey lets the atom encode each icon
      -- once and reuse it.
      local img, iconKey, icon
      if pos then
        icon = queuedIcon(pos)
      elseif e.kind == "image" then
        local thumb = thumbImage(e.thumb)
        if thumb then img, iconKey = thumb, "thumb:" .. e.thumb end
      elseif e.kind == "file" then
        img, iconKey = fileRowIcon(e)
      elseif e.kind == "url" then
        icon = "url"
      else
        local col = parseColor(e.text)
        if col then
          img, iconKey = colorChip(col)
        else
          icon = "text"
        end
      end
      local row = {
        title = e.title,
        subTitle = subTextFor(e),
        filterText = e.title,
        names = namesOf(e),
        bonus = (count - i + 1) / count,
        image = img,
        icon = icon,
        iconKey = iconKey,
        badge = pos and tostring(pos) or nil,
        item = e,
      }
      rowCache[e] = { row = row, gen = rowGen, pos = pos, ageUntil = util.relTimeChanges(e.ts) }
      out[#out + 1] = row
    end
  end
  return out
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Preview rendering (the atom's onHighlight target)
--------------------------------------------------------------------------------
--
-- A render picks what kind of entry it has, asks that kind for its facts and its blocks, and
-- composes them with manager/pane.lua into one tree of UI kit nodes. paint() hands the tree to
-- the docked pane, which lays it out clipped to the inner box and scrolled by the live offset.
-- This file chooses and measures nothing about type, every font, size, line height and colour
-- is the kit's, see pane.lua. Media comes straight from the store's
-- downscaled preview PNG (preview.lua sized it with sips or ffmpeg off the main thread),
-- loaded once as an hs.image, so nothing sizes it here.

local TEXT_DISPLAY_CAP = 20000 -- max characters drawn, so the pane stays bounded

local pane = nil -- manager/pane.lua, loaded the way init.lua loads its siblings
do
  local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
  local chunk, err = loadfile(here .. "pane.lua")
  if not chunk then error("clipboard native: failed to load pane.lua: " .. tostring(err)) end
  pane = chunk()
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


-- Hand a tree to the docked pane, which draws the shared surface first, then the tree laid out
-- in the inner box, scrolled by the live offset and clipped at the inside of the border. The
-- padding scrolls with the content, so a line cut at the bottom is cut by the edge of the pane
-- rather than by the padding. A node of nil is the shared empty state. keepScroll is for a
-- later delivery to the entry already on screen, which must not jump back to the top, and the
-- pane's own hide guard keeps a late decode, a store change or an in flight read from bringing
-- the pane back up after a swap away.
local function paint(node, keepScroll)
  if not companion then return end
  if node == nil then
    companion.clear()
    return
  end
  companion.show(function() return node end, { keepScroll = keepScroll })
end

-- A tree with nothing in it, a manage history row with nothing to say.
local function blank()
  return kit.stack({})
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


--------------------------------------------------------------------------------
-- What each kind of entry shows, and how a file is told apart
--------------------------------------------------------------------------------

-- The batch mark, today's "#N Appended", as a mark of the facts rather than glued onto a
-- string, so it is placed and upper cased by the one rule the rest of the facts follow.
local function batchMarks(e)
  local pos = batchPos(e)
  return pos and { "#" .. pos .. " Appended" } or {}
end

-- The facts every entry shares, with its own kind, details and marks. The source is the app
-- the entry was copied from, and an entry that recorded none draws the facts alone.
local function factsFor(e, kind, details, marks)
  local icon = e.sourceApp and appIcon(e.sourceApp) or nil
  local name = e.sourceApp and appName(e.sourceApp) or nil
  return {
    source = (icon or name) and { icon = icon, name = name } or nil,
    kind = kind,
    details = details or {},
    time = util.relTime(e.ts),
    marks = marks or batchMarks(e),
  }
end

-- Text that would overflow the pane is cut here, so the layout never wraps a book.
local function capped(text)
  if #text > TEXT_DISPLAY_CAP then
    return text:sub(1, TEXT_DISPLAY_CAP) .. "\n\n… truncated"
  end
  return text
end

-- The colour preview, its three canonical forms and a swatch. The swatch fills the width and
-- is square, unless the room left in the pane is shorter than the width, in which case it
-- takes that height so it still fits without a scroll. The room is asked of the layout, since
-- the header and the forms are the kit's to measure.
local function colorBlocks(e, c, ctx)
  local facts = factsFor(e, "Color", {})
  local forms = { pane.text(kit, table.concat(colorReps(c), "\n")) }
  local used = ctx.heightOf(facts, forms)
  local avail = math.max(0, ctx.h - used - kit.tokens().space[pane.GAP])
  local side = (avail > 0 and avail < ctx.w) and avail or ctx.w
  local fill = { red = c.r, green = c.g, blue = c.b, alpha = c.a }
  return facts, { forms[1], pane.swatch(kit, fill, ctx.w, side) }
end

-- The path of a file's bytes, our frozen copy first and the original only if it survives,
-- else nil, a dead link.
local function readPathOf(el)
  return (el.stored and hs.fs.attributes(el.stored) and el.stored)
    or (hs.fs.attributes(el.path) and el.path)
    or nil
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

-- An image block for a path, or the note saying why there is none.
local function imageOrNote(noteText, path, ctx)
  local img = previewImage(path)
  if img then return { pane.image(kit, img) } end
  return { pane.note(kit, noteText) }
end

-- FILE_BODIES is a Chain of Responsibility for one file, what shows under its path. Handlers
-- are tried in order and the first whose match answers true is the only one that runs, so the
-- order is the policy. Adding a file type is one handler placed in this list, nothing else
-- changes. A handler's body answers the blocks to draw now and, when it has more to say
-- later, a second value, a function of done which calls done with the blocks to draw once it
-- knows. The caller owns the guard against a selection that moved on, so a handler never
-- looks at the render token. ctx is { w, h }, the inner width and height.
local FILE_BODIES = {
  { name = "folder",
    match = function(el) return el.isDir end,
    body = function(el)
      return { pane.note(kit, pathExists(el.path) and "Folder." or "Folder no longer exists.") }
    end },
  -- A previewable file carries a small PNG, a raster image, a video frame, or a pdf or icns
  -- page, in our cache. It goes before anything else since it is durable and lets a deleted
  -- file still show its thumbnail. While it is being generated the path is set but the file
  -- is absent, so a pending note shows, and mediaReady repaints when it lands.
  { name = "cachedPreview",
    match = function(el) return el.prev end,
    body = function(el, ctx)
      if not hs.fs.attributes(el.prev) then return { pane.note(kit, "Generating preview…") } end
      return imageOrNote("Cannot render preview.", el.prev, ctx)
    end },
  { name = "gone",
    match = function(el) return readPathOf(el) == nil end,
    body = function() return { pane.note(kit, "File no longer exists.") } end },
  -- A raster image can still fall back to the original bytes, a video just says it has no
  -- frame.
  { name = "raster",
    match = function(_, ext) return util.RASTER_EXT[ext] end,
    body = function(el, ctx) return imageOrNote("Cannot render image.", readPathOf(el), ctx) end },
  { name = "video",
    match = function(_, ext) return util.VIDEO_EXT[ext] end,
    body = function() return { pane.note(kit, "No video preview.") } end },
  -- Anything left is read as text. The pane shows a note at once and fills the body when the
  -- read returns, off the main thread so a slow or large file cannot freeze it.
  { name = "text",
    match = function() return true end,
    body = function(el)
      local path = readPathOf(el)
      local function later(done)
        asyncRead(path, cfg.fileReadCap, function(data, failed)
          if failed then
            done({ pane.note(kit, "Cannot read file.") })
          elseif data:find("\0", 1, true) then
            done({ pane.note(kit, "Binary file, no text preview.") })
          else
            local truncated = #data > cfg.fileReadCap
            if truncated then data = data:sub(1, cfg.fileReadCap) end
            if #data > TEXT_DISPLAY_CAP then data = data:sub(1, TEXT_DISPLAY_CAP); truncated = true end
            if truncated then data = data .. "\n\n… truncated" end
            done({ pane.text(kit, data) })
          end
        end)
      end
      return { pane.note(kit, "Loading…") }, later
    end },
}

-- KINDS is the Strategy table for what an entry shows. Each entry answers whether it takes an
-- entry and, if so, build(e, ctx), which answers the facts, the blocks and, for a body that
-- arrives later, the function that delivers it, see FILE_BODIES. The first that matches is
-- used, so the manage history row, which has no kind, comes first and text, which takes
-- anything left, last. ctx is { w, h, heightOf }, the inner size and a way to ask how tall a
-- header and some blocks would be. A new kind is one entry here.
local KINDS = {
  { name = "history",
    match = function(e) return e.side ~= nil end,
    -- The page lists what a row would take rather than the content of one entry, so prune
    -- answers the facts itself, a kind and details, with no source, no time and no marks.
    build = function(e)
      local facts, body = prune.preview(e)
      if not facts then return nil end
      return { kind = facts.kind, details = facts.details, marks = {} }, { pane.text(kit, body) }
    end },
  { name = "file",
    match = function(e) return e.kind == "file" end,
    build = function(e, ctx)
      local files = e.files or {}
      local details = {}
      if #files ~= 1 then details[#details + 1] = #files .. " items" end
      if e.size and e.size > 0 then details[#details + 1] = util.humanSize(e.size) end
      local marks = {}
      local badge = fileBadge(e)
      if badge then marks[#marks + 1] = badge end
      for _, mark in ipairs(batchMarks(e)) do marks[#marks + 1] = mark end
      local facts = factsFor(e, KIND_LABEL.file, details, marks)
      local paths = {}
      for i, el in ipairs(files) do paths[i] = el.path end
      local blocks = { pane.paths(kit, paths) }
      if #files ~= 1 then
        -- Several files show their paths and then every thumbnail that is there.
        for _, el in ipairs(files) do
          if el.prev and hs.fs.attributes(el.prev) then
            local img = previewImage(el.prev)
            if img then blocks[#blocks + 1] = pane.image(kit, img) end
          end
        end
        return facts, blocks
      end
      local el = files[1]
      local ext = util.fileExt(el.path)
      for _, handler in ipairs(FILE_BODIES) do
        if handler.match(el, ext) then
          local more, later = handler.body(el, ctx)
          for _, block in ipairs(more) do blocks[#blocks + 1] = block end
          return facts, blocks, later and function(done)
            later(function(delivered)
              local all = { blocks[1] }
              for _, block in ipairs(delivered) do all[#all + 1] = block end
              done(all)
            end)
          end
        end
      end
    end },
  { name = "image",
    match = function(e) return e.kind == "image" end,
    build = function(e, ctx)
      -- The dimensions are in the title the reader wrote, Image WxH, so they are read back
      -- rather than stored twice.
      local details = {}
      local dims = tostring(e.title or ""):match("(%d+x%d+)")
      if dims then details[#details + 1] = dims end
      if e.size then details[#details + 1] = util.humanSize(e.size) end
      local facts = factsFor(e, KIND_LABEL.image, details)
      return facts, imageOrNote("No preview.", e.prev, ctx)
    end },
  { name = "url",
    match = function(e) return e.kind == "url" end,
    build = function(e)
      return factsFor(e, KIND_LABEL.url), { pane.text(kit, capped(e.text or "")) }
    end },
  -- A text entry that is nothing but a single colour literal renders as a swatch with its
  -- canonical forms, rather than the raw text.
  { name = "text",
    match = function() return true end,
    build = function(e, ctx)
      local c = e.kind == "text" and parseColor(e.text) or nil
      if c then return colorBlocks(e, c, ctx) end
      -- Text shows its character count, computed once at capture, so the pane never
      -- recounts on highlight.
      local details = {}
      if e.kind == "text" and e.chars then details[1] = e.chars .. " chars" end
      return factsFor(e, KIND_LABEL[e.kind] or e.kind, details), { pane.text(kit, capped(e.text or "")) }
    end },
}

-- The atom's onHighlight target. Reset the scroll to the top for the new entry, pick its
-- kind, then paint what it answers. The atom seeds one call before it has positioned
-- anything, so the very first call of a show can land with no companion rect known yet.
-- Nothing here can size or measure without one, so it defers entirely rather than guessing a
-- width, the same way the processes and filesearch panes defer their own first paint.
-- onPositioned calls this again the moment it has a real rect, well before anything is
-- visible. This is the presentation's own onHighlight, named directly on the manifest's own
-- presentation block. Review finding H6, no longer caches e anywhere, every other caller
-- that used to read that cache now asks cfg.stageSelectedItem for the live row instead.
local function renderPreview(e)
  local inner = companion and companion.inner()
  if not inner then return end
  renderToken = renderToken + 1
  if not e then
    paint(nil)
    return
  end
  local ctx = { w = inner.w, h = inner.h }
  ctx.heightOf = function(facts, blocks)
    local _, height = kit.layout(pane.compose(kit, facts, blocks), inner)
    return height
  end
  for _, kind in ipairs(KINDS) do
    if kind.match(e) then
      local facts, blocks, later = kind.build(e, ctx)
      if not facts then
        paint(blank())
        return
      end
      paint(pane.compose(kit, facts, blocks))
      if later then
        -- The selection may move on while a read is out, and an answer for an entry that is
        -- no longer showing is dropped.
        local token = renderToken
        later(function(delivered)
          if token ~= renderToken then return end
          paint(pane.compose(kit, facts, delivered), true)
        end)
      end
      return
    end
  end
end

--------------------------------------------------------------------------------
-- Preview pane lifecycle
--------------------------------------------------------------------------------

-- On close. The pane is destroyed, so nothing outlives a dismissal and the next open starts at
-- the top with no frame until the atom reports one, and the per open caches go with it.
local function hidePreview()
  renderToken = renderToken + 1 -- a read still out must not paint into the destroyed pane
  if companion then companion.destroy() end
  imageCache = {} -- drop decoded preview images between opens
  existCache = {} -- recheck linked-file liveness on the next open
end

-- The swap away signal's own hide, lighter than hidePreview above on purpose. A swap back
-- must repaint at once rather than rebuild from nothing, so this leaves imageCache and
-- existCache alone, the per open caches hidePreview drops between opens, and only takes
-- the canvas down and raises the pane's guard.
local function hidePreviewForSwap()
  if companion then companion.hide() end
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
--
-- Contract v3, docs/BRIEF-CONTRACT-V3.md, was weighed against this and left it as it is,
-- decision three's own reserved case, a row that mutates the list it is standing on rather
-- than moving to a new one. manifest.lua's own presentation comment carries the fuller
-- reasoning, including why the page switch below stays on this same pair for a second, separate
-- reason.
--
-- Answers "stay" now, the mandate for this reserved case, rather than true, since a delete is
-- exactly the mutation in place stay exists for, the row itself gone but the highlight
-- staying at the row number it sat on rather than jumping back to the top of the page. The
-- door into this page, UI.manageHistory, and the door out, UI.leaveManageHistory reached
-- through back() below, both run outside this function entirely, calling
-- cfg.redrawPresented(name, true) directly rather than answering through intercept at all, so
-- neither is a branch here that would need to keep answering true, and neither does.
local function intercept(item)
  if page ~= "prune" or not item or not item.side or item.side == "hint" then return false end
  local removed = prune.apply(item)
  local left = #store.all()
  if cfg.notify then cfg.notify(prune.message(item, removed, left)) end
  return "stay"
end

-- Backspace on an empty field, the way out of the page. It is the same press that steps out of
-- a hosted list in the launcher and out of a typed scope, so one habit covers all three, and
-- answering false with no page on keeps it ordinary editing everywhere else.
--
-- Contract v3 leaves this in place too, since the page it steps out of was never entered
-- through select in the first place, the Hyper m binding and the manage history command both
-- acting on whatever list is already open rather than completing a chosen row, so there is no
-- child here for Stage:pop to have restored. manifest.lua's own presentation comment says why.
local function back()
  if page == nil then return false end
  UI.leaveManageHistory()
  return true
end

-- The chooser closed for any reason. Cancel any uncommitted batch, hide the
-- preview, and drop the page. Named on the manifest's own presentation block as the
-- contract's onClose, told once whenever the stage hides entirely, never on a swap, the
-- identical meaning the atom's own onClose already carried for the standalone picker this
-- used to be attached to directly.
--
-- Migrated onto host/stage. Drops its own picker:setPlaceholder(PLACEHOLDER.history) call,
-- since the next cold show already carries that exact string as this presentation's own
-- static placeholder, resolved once at register, so there is nothing left to reset by hand.
-- Drops its own call to cfg.onClose too, which fed the docked shortcut panel the action bar
-- inside the chooser's own canvas has since replaced.
local function onClose()
  batch = {}
  -- Leave the page behind, so the next open is the history list. The same reason the launcher
  -- drops a hosted list on show, a page is where you were rather than a setting you chose.
  page = nil
  -- Reset the footer to its no-batch labels now the batch is cleared, so the next
  -- open does not come up still reading "Delete marked". The picker is hidden here,
  -- so setFooter only updates the stored hints the next open renders from.
  refreshFooter()
  hidePreview()
  showing = false
end

-- The native atom reserved a companion rect beside the chooser. Record it and
-- render the current selection into the canvas (paint places it there). Fired at
-- show with a seed frame and again once the real chooser window settles, so
-- re-docking is expected and harmless.
--
-- Migrated onto host/stage. Drops its own call to cfg.onPositioned and the anchor
-- arithmetic that built it, which fed the docked shortcut panel the action bar has since
-- replaced. Review
-- finding H6. Reads cfg.stageSelectedItem live, which answers correctly even at this exact
-- moment, before the atom's own isVisible() would say true, host/stage/init.lua's own
-- Stage:selectedItem() guarding on the stack rather than on that for precisely this call.
local function onPositioned(chooserFrame, companionFrame)
  if companionFrame then
    -- A redock is the swap back the pane's hide guards against, so it may paint again.
    if companion then companion.dock(companionFrame) end
    renderPreview(cfg.stageSelectedItem and cfg.stageSelectedItem())
  else
    -- host/stage/init.lua's own review finding H2 comment, near present's own handoff, says
    -- onPositioned is where a pane consumer actually knows to erase its own canvas,
    -- never onClose, since this nil, nil call is the stage telling the outgoing
    -- presentation it lost the pair to whatever just became current, a genuine swap
    -- rather than a close. hidePreviewForSwap, not hidePreview, since a swap back must
    -- repaint at once rather than rebuild from the per open caches hidePreview drops.
    hidePreviewForSwap()
  end
end

-- Migrated onto host/stage. cfg.redrawPresented replaces the direct picker:refresh() this
-- used to call on an instance it held itself.
local function onRightClick(entry)
  if not entry or entry.side then return end
  store.removeEntry(entry)
  if cfg.redrawPresented then cfg.redrawPresented("clipboard") end
end

--------------------------------------------------------------------------------
-- Public API (the manager forwards these; the root's Hyper context binds the
-- navigation methods)
--------------------------------------------------------------------------------

--- UI.show() - present through the shared stage. Called by providers/hammerspoon.lua's own
--- toggle, which reads UI.isShowing() first and calls this only when the native manager is not
--- already up, so this itself does not need to guard against a redundant present.
function UI.show()
  if cfg.stagePresent then cfg.stagePresent("clipboard") end
end

--- UI.isShowing() - migrated onto host/stage. Reads the plain flag this presentation's own
--- onPresent and onClose keep current, rather than an instance this file no longer holds.
--- providers/hammerspoon.lua's own toggle is what this exists for now, isShowing deciding
--- whether a press means UI.show or UI.hide, the identical question the nav system asks
--- host/stage's own surfaceFor instead, both answering from the same underlying fact.
function UI.isShowing()
  return showing
end

--- UI.hide() - migrated onto host/stage. cfg.stageHide replaces the direct picker:hide() this
--- used to call on an instance it held itself, for providers/hammerspoon.lua's own toggle.
function UI.hide()
  if cfg.stageHide then cfg.stageHide() end
end

--- UI.refresh() - rebuild the visible rows, e.g. after a clear. Migrated onto host/stage,
--- cfg.redrawPresented replacing the direct picker:refresh() this used to call.
function UI.refresh()
  if cfg.redrawPresented then cfg.redrawPresented("clipboard") end
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
  rowGen = rowGen + 1
  if showing then
    if cfg.redrawPresented then cfg.redrawPresented("clipboard") end
    renderPreview(cfg.stageSelectedItem and cfg.stageSelectedItem())
  end
end

--- UI.entryChanged(entry) - one entry's content was rewritten in place, which only the append
--- accumulator does. Drop the entry's cached row, so the next keystroke builds it again with the
--- grown title, count and body as its name, and repaint if the chooser happens to be open so the
--- row and the preview show the grown content. The shared search keys its lowered copy of a long
--- body by the string, which the append replaced with a new one, so nothing else is invalidated.
--- Until phase three of the unified search on 2026-10-17 this dropped the entry's cached
--- lowercased haystack instead, which the words matcher searched and nothing reads any more.
function UI.entryChanged(entry)
  rowCache[entry] = nil
  if showing then
    if cfg.redrawPresented then cfg.redrawPresented("clipboard") end
    renderPreview(cfg.stageSelectedItem and cfg.stageSelectedItem())
  end
end

-- selectNext, selectPrev, and insertSelected are gone, the trickle migration, deleted along
-- with the Chooser.new block that gave them something to answer for. The composition root now
-- routes this plugin's own navigation through host/stage's own surfaceFor once
-- wiredRegistry.presentationFor("clipboard") answers a presentation, falling through to this
-- submodule for appendSelected, deleteSelected, manageHistory, leaveManageHistory,
-- scrollPreviewDown, and scrollPreviewUp, the extra verbs neither the stage nor its five
-- function adapter was ever asked to carry.

-- How far one Hyper+Cmd+j/k press scrolls the preview, roughly a mouse-wheel
-- notch, enough to read a long entry in a few presses without overshooting.
local PREVIEW_SCROLL_STEP = 120

--- UI.scrollPreviewBy(points) - move the preview by a distance in points, positive being
--- further down the content. The one place the offset changes, so the keys and the
--- trackpad cannot drift apart. The docked pane clamps it to the content overflow and
--- redraws the last content at the new offset without rebuilding it.
function UI.scrollPreviewBy(points)
  if not (companion and showing) then return end
  -- The docked pane clamps the offset against the content and paints once per frame, however
  -- many events land before it.
  companion.scrollBy(points)
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
---
--- Review finding H6. Reads cfg.stageSelectedItem live rather than the retired
--- lastHighlighted cache, so this can no longer add the previous session's entry to the
--- batch on a cold open plus immediate keypress.
function UI.appendSelected()
  if not showing or page then return end
  local entry = cfg.stageSelectedItem and cfg.stageSelectedItem()
  if not entry then return end
  toggleBatch(entry)
  if cfg.redrawPresented then cfg.redrawPresented("clipboard") end
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
  if not showing or page then return end
  if #batch > 0 then
    for _, e in ipairs(batch) do store.removeEntry(e) end
    batch = {}
  else
    -- Review finding H6, the costly one. This used to read a module local cache seeded only
    -- by the atom's own poll and never cleared on close, so a cold open plus an immediate d
    -- deleted whatever the previous session had highlighted, wherever it now sat in history,
    -- an unrecoverable wrong deletion. cfg.stageSelectedItem reads the widget's own live
    -- selection directly, answering correctly the instant a row is on screen with no poll
    -- interval to race.
    local entry = cfg.stageSelectedItem and cfg.stageSelectedItem()
    if not entry then return end
    store.removeEntry(entry)
  end
  if cfg.redrawPresented then cfg.redrawPresented("clipboard") end
  refreshFooter()
end

--- UI.manageHistory() - show the manage history page, or step back off it when it is already
--- on, for the Hyper m binding and for the launcher row that opens straight onto it. One verb
--- both ways round, because the key is what a person will press again to get out and finding it
--- inert there is worse than a second key nobody would guess.
---
--- Opening from the launcher arrives here with nothing showing, so the picker is shown too, and
--- the page is set BEFORE the show since showing is what builds the first rows.
--- Migrated onto host/stage. A fresh present when nothing was showing carries this
--- presentation's own static placeholder, "Search clipboard", so cfg.stageSetPlaceholder
--- corrects it to the prune wording right after, the identical direct field control
--- cfg.stageSetQuery already exists for. Already showing, the field is cleared and the ladder
--- rebuilt exactly as before, through the published words rather than the retired instance.
---
--- Review finding M4. wasShowing is captured before cfg.stagePresent runs, and it has to be,
--- since Stage:present calls this presentation's own onPresent, which sets showing true,
--- before it ever returns, so testing showing itself after that call answers true on the
--- cold path too and the warm path's own block ran a second time on top of a cold show that
--- had already done the identical work honestly, through its own onPresent and the atom's own
--- native seeding. Harmless in the specific numbers, an empty field cleared again and a
--- redraw asking for what a cold show already painted, but the comment claimed a path the
--- code did not take, and a live selectedItem read landing on top of a fresh show was one
--- fewer thing worth reasoning about correctly than needed to be.
function UI.manageHistory()
  if page == "prune" then
    UI.leaveManageHistory()
    return
  end
  page = "prune"
  local wasShowing = showing
  if not wasShowing then
    if cfg.stagePresent then cfg.stagePresent("clipboard") end
  end
  if cfg.stageSetPlaceholder then cfg.stageSetPlaceholder(PLACEHOLDER.prune) end
  if wasShowing then
    -- Whatever was typed was a search over history, and on this page the same text would
    -- read as a duration, so the field starts empty and the ladder is what a person sees
    -- first.
    if cfg.stageSetQuery then cfg.stageSetQuery("") end
    if cfg.redrawPresented then cfg.redrawPresented("clipboard", true) end
    renderPreview(cfg.stageSelectedItem and cfg.stageSelectedItem())
  end
end

--- UI.leaveManageHistory() - give the history list back, the answer to Backspace on an empty
--- field and to pressing the page's own key again. Rebuilds from the top, since the list now
--- means something else and the highlight has no business staying on the row number the page
--- left it on. Migrated onto host/stage, the identical published words manageHistory above
--- already uses.
function UI.leaveManageHistory()
  if page == nil then return end
  page = nil
  if cfg.stageSetPlaceholder then cfg.stageSetPlaceholder(PLACEHOLDER.history) end
  if cfg.stageSetQuery then cfg.stageSetQuery("") end
  if cfg.redrawPresented then cfg.redrawPresented("clipboard", true) end
  renderPreview(cfg.stageSelectedItem and cfg.stageSelectedItem())
end

--- UI.isManagingHistory() - whether the page is on, read by the plugin's own predicate so the
--- key panel lists the way out exactly while there is one. Migrated onto host/stage, reading
--- the plain showing flag rather than an instance this file no longer holds.
function UI.isManagingHistory()
  return page == "prune" and showing
end

--- UI.placeholder() -> string. The field hint while this plugin's own presentation is
--- current, named on the manifest's own presentation block. Resolved once, at register, since
--- the presentation contract wants a plain string a presentation carries rather than a
--- function to call again later. The prune page's own wording is reached live instead,
--- through cfg.stageSetPlaceholder, manageHistory and leaveManageHistory above, the direct
--- field control a presentation's own static placeholder cannot express.
function UI.placeholder()
  return PLACEHOLDER.history
end

--- UI.onPresent() - the presentation contract's own onPresent, named on the manifest's own
--- presentation block, called whenever this presentation becomes current, through present or
--- push alike. Marks this plugin's own showing flag, which providers/hammerspoon.lua's own
--- toggle, and every guard in this file, now reads in place of an instance's own isShowing().
function UI.onPresent()
  showing = true
  rowGen = rowGen + 1
end

--- UI.build() - no longer creates a Chooser instance, the trickle migration. Whatever this
--- used to hand a Chooser.new call, theme, fieldMode, rows, onSelect, the drill down pair, the
--- panel triple, and layout, is now either read straight off this module by the registrar,
--- rows and select through the manifest's own presentation block, or owned by the stage as
--- fixed, atom level policy. The presentation declares no matcher since phase three of the
--- unified search, so the shared one ranks, and its searchText is UI.searchText below.
--- widthPct, paneMaxW, rowH, baseH, rowCount, gap, topFrac, and minVPad were eight restated
--- atom defaults even before this migration, surprise 9.4 of the consumer map, and pollInterval
--- turns out to equal the atom's own hardcoded fallback of 0.08 exactly, so nothing here was
--- ever a real override beyond companionWidth, which paneWidth = true in the manifest now
--- carries. The injected Chooser factory and the ten now unread layout keys it used to build a
--- window from were deleted from manager/init.lua's own defaults in the close out sweep,
--- REVIEW-TRICKLE.md's own L3, rather than left as inert injection nothing reads. Kept as a
--- callable no op rather than deleted itself, since manager/init.lua's own start still calls it
--- and a wiring step this file no longer needs is cheaper to leave inert than to go edit a
--- second file over.
function UI.build()
  return UI
end

--- UI.configure(opts) - inject store, the insertion engine, util, media (for the shared file
--- state rule fileBadge draws on), prune (the manage history page, whose rows and wording this
--- file only draws), the UI kit (opts.ui, needs.lib.ui, which every piece of text in the preview
--- is drawn through), the shared docked pane (opts.dockedPane, the root's grant for the
--- manifest's `pane = true`, which draws the preview's background, border, empty state and
--- scroll), and the layout config. stagePresent,
--- redrawPresented, stageHide, stageSetQuery, and stageSetPlaceholder, the trickle migration's
--- own root published words, arrive here too, under needs.data in the manifest.
function UI.configure(opts)
  store = opts.store
  paste = opts.paste
  util = opts.util
  media = opts.media
  prune = opts.prune
  kit = opts.ui
  if not companion and opts.dockedPane then
    companion = opts.dockedPane({ scroll = true })
  end
  isAccumulator = opts.isAccumulator or isAccumulator
  cfg = opts
  return UI
end

--- UI.rows(query) -> list. The row supplier, named on the manifest's own presentation block
--- as the contract's rows, exposing buildChoices, the atom's own rows supplier from before
--- the migration, without a second copy to disagree with.
UI.rows = buildChoices

--- UI.searchText(raw) -> string. The presentation's searchText, the text the shared search
--- ranks the history by, which is what follows a type prefix, so img cat ranks the images by
--- cat while buildChoices keeps only the images. On the manage history page the field is a
--- duration or a count rather than a search, so it answers nothing, which keeps that page's rows
--- in the order prune.lua gave them whatever is typed, as matcher false did for the whole
--- presentation before. The page swaps inside one presentation, so the matcher the stage writes
--- before a show cannot follow it, and this is read on every keystroke, so it can.
function UI.searchText(raw)
  if page == "prune" then return "" end
  local _, rest = parseQuery(raw)
  return rest or ""
end

--- UI.select(item) - apply a row, named on the manifest's own presentation block as the
--- contract's onSelect, exposing the file local onSelect already defined above.
UI.select = onSelect

--- UI.intercept, UI.back - the presentation contract's own drill down pair, named on the
--- manifest's own presentation block, exposing the file local functions already defined above
--- without a second copy to disagree with.
UI.intercept = intercept
UI.back = back

--- UI.onHighlight - the presentation contract's own onHighlight, named on the manifest's own
--- presentation block. renderPreview already is the atom's onHighlight target, unchanged.
UI.onHighlight = renderPreview

--- UI.onScroll, UI.onPositioned, UI.onRightClick, UI.onClose - the remaining presentation
--- contract hooks, named on the manifest's own presentation block, exposing the file local
--- functions already defined above without a second copy to disagree with. onScroll wraps
--- UI.scrollPreviewBy directly, the identical function the two scroll keys already go through,
--- so a pane is scrolled the same amount whichever one asked.
UI.onScroll = UI.scrollPreviewBy
UI.onPositioned = onPositioned
UI.onRightClick = onRightClick
UI.onClose = onClose

return UI
