--- The clipboard consumer of the shared Chooser atom, plus the live preview pane.
---
--- The generic chooser behavior (the window, theming, row styling, navigation,
--- positioning, and click away dismissal) lives in Chooser.spoon, injected here
--- as a factory. This file supplies only clipboard policy. The rows, what a
--- selection pastes, the append batch, right click delete, and the preview that
--- docks in the companion pane the atom reserves beside the chooser.
---
--- The preview is a separate non-activating webview. Non-activating matters, the
--- pane must never take key focus or typing would leave the search field. The
--- atom polls the highlighted row and calls onHighlight, which renders here.
---
--- Preview rendering is per kind. Text, url, and image render synchronously and
--- are cached. A single text file is read off the main thread with hs.task so an
--- undownloaded or large file cannot stall the pane, and the result is dropped if
--- the selection has moved on. Images render from a downscaled preview file, so
--- nothing encodes a full-res bitmap on the main thread.

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

-- Build the preview webview stylesheet from a palette's color set. Concatenated
-- rather than formatted so the literal percents in the CSS need no escaping.
local function previewCss(p)
  return "<style>"
    .. "html,body{margin:0;height:100%;background:" .. p.bg .. ";color:" .. p.fg .. ";"
    .. "font:16px/1.5 -apple-system,BlinkMacSystemFont,Menlo,monospace;}"
    .. ".wrap{padding:16px;box-sizing:border-box;height:100%;overflow:auto;}"
    .. ".meta{color:" .. p.meta .. ";font-size:11px;margin-bottom:10px;"
    .. "text-transform:uppercase;letter-spacing:.04em;}"
    .. ".path{color:" .. p.path .. ";font-size:11px;margin-bottom:6px;word-break:break-all;}"
    .. ".note{color:" .. p.note .. ";}"
    .. "pre{white-space:pre-wrap;word-break:break-word;margin:0;}"
    .. "img{max-width:100%;height:auto;border-radius:8px;margin-top:8px;}"
    .. "</style>"
end

-- State
local preview = nil
local renderToken = 0 -- bumped each render; async results check it to avoid stale writes
local previewCache = {} -- entry -> inner html, for the synchronous kinds only
local themeCss = nil -- preview CSS for the current open, built lazily from the atom's active theme
local thumbCache = {} -- path -> hs.image (or false), for row thumbnails
local iconCache = {} -- bundle id -> hs.image (or false), for row source-app icons

-- Which preview sink this backend uses. The web backend embeds a preview pane in
-- the picker window, so the html is pushed straight into it. The native backend
-- docks a separate companion webview beside the chooser. Set once in UI.build by
-- asking the picker whether it reserves an embedded pane. emit is forward declared
-- here so the render functions can close over it before it is defined below, past
-- the companion pane helpers it needs.
local embedded = false
local emit = nil

-- The preview stylesheet for this open. Built from the palette the atom selected
-- for the current appearance, so the preview follows light and dark like the
-- chooser. Reset to nil on close, so the next open rebuilds it against the theme
-- picked then.
local function currentCss()
  if not themeCss then
    themeCss = previewCss(picker:activeTheme().preview)
  end
  return themeCss
end

-- Append batch. The Hyper a binding collects the highlighted entry here, in the
-- order pressed, so several items can be gathered and pasted together on close.
-- Membership is keyed by the live store reference each row carries, so a row's
-- order badge is just its position in this list, and toggling an item off
-- renumbers the rest for free. Collecting never touches the store, so the visible
-- list never shifts while the picker is open; the reorder happens on commit. The
-- batch is cleared on every close, so each open starts empty.
local batch = {}

-- Circled digits for the order badge, one per collected position. Present in the
-- system UI font, so they render in a styled row title. Past twenty, a plain
-- parenthesized number stands in rather than running out of glyphs.
local BATCH_BADGES = {
  "①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩",
  "⑪", "⑫", "⑬", "⑭", "⑮", "⑯", "⑰", "⑱", "⑲", "⑳",
}

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

local function subTextFor(e)
  local parts = { KIND_LABEL[e.kind] or e.kind, util.relTime(e.ts) }
  -- The file location belongs only in the preview, so the picker shows just the
  -- count when several files were copied and nothing extra for a single one.
  if e.kind == "file" then
    local files = e.files or {}
    if #files > 1 then
      parts[#parts + 1] = #files .. " files"
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

-- The atom's rows supplier. Returns plain items; the atom styles them with the
-- active palette. Filtering, the type prefix, the batch order badge, and the
-- thumbnail or source-app icon are all clipboard policy and live here.
local function buildChoices(q)
  local kind, rest = parseQuery(q)
  rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
  local out = {}
  for _, e in ipairs(store.all()) do
    if (not kind or e.kind == kind) and (rest == "" or haystack(e):find(rest, 1, true)) then
      -- A collected row wears its order badge on the title, so its place in the
      -- batch shows without moving the row. The badge feeds display only; search
      -- still runs over the raw title in haystack, so it never affects matching.
      local pos = batchPos(e)
      local title = pos and ((BATCH_BADGES[pos] or ("(" .. pos .. ")")) .. "  " .. (e.title or "")) or e.title
      out[#out + 1] = {
        title = title,
        subTitle = subTextFor(e),
        -- A true image copy shows its own thumbnail, every other row shows the
        -- icon of the app it came from, falling back to nothing when unknown.
        image = (e.kind == "image" and thumbImage(e.thumb)) or appIcon(e.sourceApp) or nil,
        item = e,
      }
    end
  end
  return out
end

--------------------------------------------------------------------------------
-- Preview rendering (the atom's onHighlight target)
--------------------------------------------------------------------------------

local function imageDataURI(path)
  local img = hs.image.imageFromPath(path)
  if not img then return nil end
  return img:encodeAsURLString() -- path is already downscaled on disk, so this is small
end

local function wrap(inner)
  return currentCss() .. "<div class=wrap>" .. inner .. "</div>"
end

local function note(inner)
  return "<div class=note>" .. inner .. "</div>"
end

-- Header for a file entry: the item count and each original path.
local function fileHeader(e)
  local files = e.files or {}
  local h = "<div class=meta>File  ·  " .. #files .. " item" .. (#files == 1 and "" or "s") .. "</div>"
  for _, el in ipairs(files) do
    h = h .. "<div class=path>" .. util.esc(el.path) .. "</div>"
  end
  return h
end

-- Synchronous kinds: text, url, image. Each returns the inner html that goes
-- inside the preview wrap; emit decides where it lands, so the same content feeds
-- the embedded pane and the companion window.
local function renderNonFile(e)
  if e.kind == "image" then
    local uri = e.prev and imageDataURI(e.prev) or ""
    return "<div class=meta>" .. util.esc(e.title) .. "</div><img src='" .. uri .. "'>"
  end
  local meta = util.esc((KIND_LABEL[e.kind] or e.kind) .. "  ·  " .. util.relTime(e.ts))
  return "<div class=meta>" .. meta .. "</div><pre>" .. util.esc(e.text or "") .. "</pre>"
end

local function multiFileHtml(e)
  local body = fileHeader(e)
  for _, el in ipairs(e.files or {}) do
    if el.prev and hs.fs.attributes(el.prev) then
      local uri = imageDataURI(el.prev)
      if uri then
        body = body .. "<img src='" .. uri .. "'>"
      end
    end
  end
  return body
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

local function renderFile(e, token)
  local files = e.files or {}
  if #files ~= 1 then
    emit(multiFileHtml(e))
    return
  end

  local el = files[1]
  if el.isDir then
    emit(fileHeader(e) .. note("Folder."))
    return
  end

  -- Always prefer our snapshot; fall back to the original only if it survives.
  local readPath = (el.stored and hs.fs.attributes(el.stored) and el.stored)
    or (hs.fs.attributes(el.path) and el.path)
    or nil
  if not readPath then
    emit(fileHeader(e) .. note("File no longer exists."))
    return
  end

  if util.RENDER_AS_IMAGE[util.fileExt(el.path)] then
    local src = (el.prev and hs.fs.attributes(el.prev) and el.prev) or readPath
    local uri = imageDataURI(src)
    emit(fileHeader(e) .. (uri and ("<img src='" .. uri .. "'>") or note("Cannot render image.")))
    return
  end

  -- Text: show the header at once, fill the body when the async read returns.
  emit(fileHeader(e) .. note("Loading…"))
  asyncRead(readPath, cfg.fileReadCap, function(data, failed)
    if token ~= renderToken then
      return -- selection moved on
    end
    local body
    if failed then
      body = note("Cannot read file.")
    elseif data:find("\0", 1, true) then
      body = note("Binary file, no text preview.")
    else
      local truncated = #data > cfg.fileReadCap
      if truncated then
        data = data:sub(1, cfg.fileReadCap)
      end
      body = "<pre>" .. util.esc(data)
        .. (truncated and ("\n\n… truncated at " .. util.humanSize(cfg.fileReadCap)) or "")
        .. "</pre>"
    end
    emit(fileHeader(e) .. body)
  end)
end

local function renderPreview(e)
  renderToken = renderToken + 1
  if not e then
    emit("")
    return
  end
  if e.kind == "file" then
    renderFile(e, renderToken)
    return
  end
  local inner = previewCache[e]
  if not inner then
    inner = renderNonFile(e)
    previewCache[e] = inner
  end
  emit(inner)
end

--------------------------------------------------------------------------------
-- Preview pane lifecycle
--------------------------------------------------------------------------------

local function ensurePreview()
  if preview then return end
  preview = hs.webview.new({ x = 0, y = 0, w = cfg.previewW, h = cfg.previewH })
  preview:windowStyle(hs.webview.windowMasks.nonactivating) -- borderless, no focus steal
  preview:level(hs.canvas.windowLevels.floating)
  preview:allowTextEntry(false)
  preview:allowNewWindows(false)
end

local function hidePreview()
  if preview then
    preview:hide()
  end
  previewCache = {} -- drop encoded images between opens
  themeCss = nil -- rebuild against the theme picked on the next open
end

-- Route a preview fragment to the active sink. On the web backend the picker
-- embeds the pane, so the inner html is pushed straight in and the page supplies
-- the chrome and theme. On the native backend a companion webview is docked
-- beside the chooser, so the fragment is wrapped with the theme css and written
-- there. Assigned to the forward declared local so the render functions above,
-- which close over it, reach this one definition.
emit = function(inner)
  if embedded then
    picker:setPreview(inner or "")
  else
    ensurePreview()
    preview:html(wrap(inner or ""))
  end
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
  hidePreview()
  if cfg and cfg.onClose then
    cfg.onClose()
  end
end

-- The native atom reserved a companion rect beside the chooser. Dock the preview
-- there and render the current selection. Fired at show with a seed frame and
-- again once the real chooser window settles, so re-docking is expected and
-- harmless. The web backend embeds the preview instead and never calls this, so
-- it is inert there, driven only by onHighlight.
local function onPositioned(_chooserFrame, companionFrame)
  if embedded or not companionFrame then return end
  ensurePreview()
  preview:frame(companionFrame)
  preview:show()
  renderPreview(picker:selectedItem())
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

function UI.selectNext()
  if picker then picker:selectNext() end
end

function UI.selectPrev()
  if picker then picker:selectPrev() end
end

function UI.insertSelected()
  if picker then picker:insertSelected() end
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
end

--- UI.build() - create the Chooser instance. Called once at start and reused
--- across shows. Maps the clipboard layout config onto the atom's layout, wires
--- the clipboard policy through the atom's callbacks, and reserves a companion
--- pane the width of the preview.
function UI.build()
  picker = Chooser.new({
    theme = cfg.theme,
    fieldMode = "filter",
    placeholder = "Hold Hyper for shortcuts",
    pollInterval = cfg.previewPoll,
    rows = buildChoices,
    onSelect = onSelect,
    onHighlight = renderPreview,
    onClose = onClose,
    onPositioned = onPositioned,
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
      -- companionWidth drives the native atom's docked window; previewWidth and
      -- visibleRows drive the web list's embedded split. Each backend reads only
      -- the keys it knows, so passing both keeps this file backend agnostic.
      companionWidth = cfg.previewW,
      previewWidth = cfg.previewW,
      visibleRows = cfg.chooserRows,
    },
  })
  -- Ask the picker whether it embeds a preview pane. The web list answers yes and
  -- the fragments go into it; the native atom lacks the method and the companion
  -- window path runs instead. This is the one place the two backends diverge.
  embedded = (picker.hasPreview ~= nil and picker:hasPreview()) or false
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
