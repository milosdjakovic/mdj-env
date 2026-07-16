--- The chooser and the live preview pane.
---
--- hs.chooser has no detail view and fires no event when the highlighted row
--- moves, so we own filtering (setting queryChangedCallback disables its built-in
--- match) and the preview is a separate non-activating webview docked beside the
--- chooser, refreshed by polling selectedRow() on a short timer. Non-activating
--- matters, the pane must never take key focus or typing would leave the search
--- field.
---
--- Preview rendering is per kind. Text, url, and image render synchronously and
--- are cached. A single text file is read off the main thread with hs.task so an
--- undownloaded or large file cannot stall the pane, and the result is dropped if
--- the selection has moved on. Images render from a downscaled preview file, so
--- nothing encodes a full-res bitmap on the main thread.

local UI = {}

local store, monitor, util = nil, nil, nil
local cfg = nil -- layout and size config, see configure

-- Display labels and the type-filter query prefixes, both ui policy.
local KIND_LABEL = { text = "Text", url = "URL", file = "File", image = "Image" }
local KIND_PREFIX = {
  img = "image", image = "image",
  url = "url", link = "url",
  file = "file", files = "file",
  txt = "text", text = "text",
}

local PREVIEW_CSS = [[<style>
  html,body{margin:0;height:100%;background:#1e1e22;color:#dcdcdc;
    font:16px/1.5 -apple-system,BlinkMacSystemFont,Menlo,monospace;}
  .wrap{padding:16px;box-sizing:border-box;height:100%;overflow:auto;}
  .meta{color:#8a8a8a;font-size:11px;margin-bottom:10px;
    text-transform:uppercase;letter-spacing:.04em;}
  .path{color:#7a7a7a;font-size:11px;margin-bottom:6px;word-break:break-all;}
  .note{color:#c8a86a;}
  pre{white-space:pre-wrap;word-break:break-word;margin:0;}
  img{max-width:100%;height:auto;border-radius:8px;margin-top:8px;}
</style>]]
local EMPTY_HTML = PREVIEW_CSS .. "<body></body>"

-- State
local chooser = nil
local preview = nil
local uiTimer = nil
local lastPreviewRow = nil
local renderToken = 0 -- bumped each render; async results check it to avoid stale writes
local previewCache = {} -- entry -> html, for the synchronous kinds only
local currentChoices = {} -- rows currently shown, for right-click delete
local thumbCache = {} -- path -> hs.image (or false), for row thumbnails

--------------------------------------------------------------------------------
-- Rows and filtering
--------------------------------------------------------------------------------

-- hs.chooser has no font-size setting, but a row's text and subText accept an
-- hs.styledtext, so the font is set per row here. Styling replaces the bgDark
-- default text color, so a light main color and a dimmer sub color are supplied
-- to keep the dark look. The title matches the preview at 16pt for one readable
-- size across both panes.
--
-- One trade-off comes with 16pt. hs.chooser budgets about 42pt per row and a
-- 16pt row renders a touch taller, so the drift clips the last visible row's
-- dimmed subtext at the bottom edge. That was chosen knowingly for the larger
-- font. Dropping the title to 14pt removes the clip if a clean last row ever
-- matters more than size.
local ROW_FONT = ".AppleSystemUIFont"
local ROW_TITLE_SIZE = 16
local ROW_SUB_SIZE = 12
local ROW_TITLE_COLOR = { white = 0.92 }
local ROW_SUB_COLOR = { white = 0.55 }

local function styled(str, size, color)
  return hs.styledtext.new(str or "", {
    font = { name = ROW_FONT, size = size },
    color = color,
    -- Keep each row to one line, cut with an ellipsis rather than wrapping.
    paragraphStyle = { lineBreak = "truncateTail" },
  })
end

local function thumbImage(path)
  if not path then return nil end
  local c = thumbCache[path]
  if c ~= nil then return c or nil end
  local img = hs.image.imageFromPath(path) or false
  thumbCache[path] = img
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

local function buildChoices(q)
  local kind, rest = parseQuery(q)
  rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
  local out = {}
  for _, e in ipairs(store.all()) do
    if (not kind or e.kind == kind) and (rest == "" or haystack(e):find(rest, 1, true)) then
      out[#out + 1] = {
        text = styled(e.title, ROW_TITLE_SIZE, ROW_TITLE_COLOR),
        subText = styled(subTextFor(e), ROW_SUB_SIZE, ROW_SUB_COLOR),
        image = e.kind == "image" and thumbImage(e.thumb) or nil,
        _entry = e,
      }
    end
  end
  currentChoices = out
  return out
end

--------------------------------------------------------------------------------
-- Preview rendering
--------------------------------------------------------------------------------

local function imageDataURI(path)
  local img = hs.image.imageFromPath(path)
  if not img then return nil end
  return img:encodeAsURLString() -- path is already downscaled on disk, so this is small
end

local function wrap(inner)
  return PREVIEW_CSS .. "<div class=wrap>" .. inner .. "</div>"
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

-- Synchronous kinds: text, url, image.
local function renderNonFile(e)
  if e.kind == "image" then
    local uri = e.prev and imageDataURI(e.prev) or ""
    return wrap("<div class=meta>" .. util.esc(e.title) .. "</div><img src='" .. uri .. "'>")
  end
  local meta = util.esc((KIND_LABEL[e.kind] or e.kind) .. "  ·  " .. util.relTime(e.ts))
  return wrap("<div class=meta>" .. meta .. "</div><pre>" .. util.esc(e.text or "") .. "</pre>")
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
  return wrap(body)
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
    preview:html(multiFileHtml(e))
    return
  end

  local el = files[1]
  if el.isDir then
    preview:html(wrap(fileHeader(e) .. note("Folder.")))
    return
  end

  -- Always prefer our snapshot; fall back to the original only if it survives.
  local readPath = (el.stored and hs.fs.attributes(el.stored) and el.stored)
    or (hs.fs.attributes(el.path) and el.path)
    or nil
  if not readPath then
    preview:html(wrap(fileHeader(e) .. note("File no longer exists.")))
    return
  end

  if util.RENDER_AS_IMAGE[util.fileExt(el.path)] then
    local src = (el.prev and hs.fs.attributes(el.prev) and el.prev) or readPath
    local uri = imageDataURI(src)
    preview:html(wrap(fileHeader(e) .. (uri and ("<img src='" .. uri .. "'>") or note("Cannot render image."))))
    return
  end

  -- Text: show the header at once, fill the body when the async read returns.
  preview:html(wrap(fileHeader(e) .. note("Loading…")))
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
    preview:html(wrap(fileHeader(e) .. body))
  end)
end

local function renderPreview(e)
  if not preview then
    return
  end
  renderToken = renderToken + 1
  if not e then
    preview:html(EMPTY_HTML)
    return
  end
  if e.kind == "file" then
    renderFile(e, renderToken)
    return
  end
  local html = previewCache[e]
  if not html then
    html = renderNonFile(e)
    previewCache[e] = html
  end
  preview:html(html)
end

--------------------------------------------------------------------------------
-- Pane lifecycle and positioning
--------------------------------------------------------------------------------

local function ensurePreview()
  if preview then return end
  preview = hs.webview.new({ x = 0, y = 0, w = cfg.previewW, h = cfg.previewH })
  preview:windowStyle(hs.webview.windowMasks.nonactivating) -- borderless, no focus steal
  preview:level(hs.canvas.windowLevels.floating)
  preview:allowTextEntry(false)
  preview:allowNewWindows(false)
end

local function stopPreviewLoop()
  if uiTimer then
    uiTimer:stop()
    uiTimer = nil
  end
end

local function hidePreview()
  stopPreviewLoop()
  if preview then
    preview:hide()
  end
  previewCache = {} -- drop encoded images between opens
end

local function startPreviewLoop()
  stopPreviewLoop()
  uiTimer = hs.timer.doEvery(cfg.previewPoll, function()
    if not chooser or not chooser:isVisible() then
      hidePreview()
      return
    end
    local row = chooser:selectedRow()
    if row ~= lastPreviewRow then
      lastPreviewRow = row
      local choice = currentChoices[row]
      renderPreview(choice and choice._entry or nil)
    end
  end)
end

-- Vertical top-left of the pair on screen `sf`: biased toward the top by
-- uiTopFrac, but never closer than minVPad to either edge. When the pair is too
-- tall to keep both pads (a short screen with a clamped chooser), the top pad
-- wins so it never rides off the top.
local function topBiasedY(sf, paneH)
  local floor, max, min = math.floor, math.max, math.min
  local lo = sf.y + cfg.minVPad
  local hi = sf.y + sf.h - cfg.minVPad - paneH
  if hi < lo then
    hi = lo
  end
  return max(lo, min(sf.y + floor(sf.h * cfg.uiTopFrac), hi))
end

-- The chooser clamps its own height to fit the screen, so its rendered height is
-- not reliably rows*rowHeight and is only known once it shows. Read the real
-- chooser window just after it appears, place it top-biased with padding on its
-- actual screen, and dock the preview flush beside it at the same top and
-- height. This keeps both panes the same size and the pair well placed even when
-- the chooser came up shorter than requested or landed on another display.
local function matchPreviewToChooser(previewW)
  hs.timer.doAfter(0.03, function()
    if not preview then return end
    local app = hs.application.get("Hammerspoon")
    if not app then return end
    for _, w in ipairs(app:allWindows()) do
      if (w:title() or "") == "Chooser" and w:isVisible() then
        local cf = w:frame()
        local sf = (w:screen() or hs.screen.mainScreen()):frame()
        local y = topBiasedY(sf, cf.h)
        w:setTopLeft({ x = cf.x, y = y })
        preview:frame({ x = cf.x + cf.w + cfg.uiGap, y = y, w = previewW, h = cf.h })
        return
      end
    end
  end)
end

local function positionAndShow()
  local f = hs.screen.mainScreen():frame()
  local floor, min, max = math.floor, math.min, math.max

  -- Trim the row count so the pair fits between the mandatory pads on a short
  -- screen. On a tall screen the full request survives.
  local avail = f.h - 2 * cfg.minVPad
  local maxRows = max(1, floor((avail - cfg.chooserBaseH) / cfg.chooserRowH))
  local rows = min(cfg.chooserRows, maxRows)
  chooser:rows(rows)
  local paneH = cfg.chooserBaseH + rows * cfg.chooserRowH

  local chooserW = min(floor(f.w * cfg.chooserWidthPct / 100), cfg.paneMaxW)
  local previewW = min(cfg.previewW, cfg.paneMaxW)
  local total = chooserW + cfg.uiGap + previewW
  local x = f.x + floor((f.w - total) / 2)
  local y = topBiasedY(f, paneH)

  -- hs.chooser width is a percent of the screen, so translate the capped pixel
  -- width back to a percent right before showing.
  chooser:width(chooserW / f.w * 100)

  ensurePreview()
  -- Seed the preview here; matchPreviewToChooser corrects height and position to
  -- the chooser's real rendered frame a moment later.
  preview:frame({ x = x + chooserW + cfg.uiGap, y = y, w = previewW, h = paneH })
  renderPreview(currentChoices[1] and currentChoices[1]._entry or nil)
  preview:show()

  lastPreviewRow = 1
  chooser:show({ x = x, y = y })
  matchPreviewToChooser(previewW)
  startPreviewLoop()
end

--------------------------------------------------------------------------------
-- Callbacks
--------------------------------------------------------------------------------

local function onChoice(choice)
  hidePreview()
  if choice then
    monitor.paste(choice._entry)
  end
end

local function onRightClick(row)
  local choice = currentChoices[row]
  if not choice then return end
  store.removeEntry(choice._entry)
  chooser:choices(buildChoices(chooser:query() or ""))
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

--- UI.show() - place the chooser and dock the live preview beside it.
function UI.show()
  if not chooser then return end
  chooser:query("")
  chooser:choices(buildChoices(""))
  positionAndShow()
end

function UI.isShowing()
  return chooser ~= nil and chooser:isVisible()
end

--- UI.hide() - dismiss the chooser and its preview pane.
function UI.hide()
  if chooser then
    chooser:hide()
  end
  hidePreview()
end

--- UI.refresh() - rebuild the visible rows, e.g. after a clear.
function UI.refresh()
  if chooser then
    chooser:choices(buildChoices(chooser:query() or ""))
  end
end

--- UI.build() - create the chooser. Called once at start and reused across
--- shows. hs.chooser settles to a compact height on the second and later shows,
--- which is the steady state the row font is tuned against.
function UI.build()
  chooser = hs.chooser.new(onChoice)
  chooser:bgDark(true)
  chooser:width(cfg.chooserWidthPct)
  chooser:rows(cfg.chooserRows)
  chooser:queryChangedCallback(function(q)
    chooser:choices(buildChoices(q))
    lastPreviewRow = nil -- filtering changed the top row, force a preview refresh
  end)
  chooser:rightClickCallback(onRightClick)
  return UI
end

--- UI.configure(opts) - inject store, monitor, util, and the layout config.
function UI.configure(opts)
  store = opts.store
  monitor = opts.monitor
  util = opts.util
  cfg = opts
  return UI
end

return UI
