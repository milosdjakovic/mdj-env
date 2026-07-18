--- Pure string and pasteboard helpers shared by the readers and the ui.
--- No state, no other module dependencies, so it is safe to load first and
--- inject everywhere.

local U = {}

local floor = math.floor

-- File-extension sets, pure data shared by the preview generators (which pick a
-- backend by type), the store (which asks the preview module whether a file is
-- previewable), and the ui (which picks the image render path). One list, so the
-- three never disagree. Raster images go to sips, videos to ffmpeg, and the docs
-- macOS can draw (pdf first page, icns) to hs.image.
U.RASTER_EXT = {
  png = true, jpg = true, jpeg = true, gif = true, bmp = true,
  tiff = true, tif = true, heic = true, webp = true,
}
U.VIDEO_EXT = {
  mp4 = true, mov = true, m4v = true, avi = true, mkv = true, webm = true,
  flv = true, wmv = true, mpg = true, mpeg = true, ["3gp"] = true, ["3g2"] = true,
  ogv = true,
}
U.DOC_EXT = { pdf = true, icns = true }

-- Collapse whitespace to a single line and cap the length for display.
function U.oneLine(s, n)
  s = s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if #s > n then
    s = s:sub(1, n - 1) .. "…"
  end
  return s
end

function U.basename(path)
  return path:match("([^/]+)/?$") or path
end

function U.fileExt(path)
  return (path:match("%.([%w]+)$") or ""):lower()
end

function U.relTime(ts)
  local d = os.time() - (ts or 0)
  if d < 60 then
    return d .. "s ago"
  elseif d < 3600 then
    return floor(d / 60) .. "m ago"
  elseif d < 86400 then
    return floor(d / 3600) .. "h ago"
  end
  return floor(d / 86400) .. "d ago"
end

function U.humanSize(n)
  if not n then return "?" end
  if n < 1024 then return n .. " B" end
  if n < 1024 * 1024 then return string.format("%.1f KB", n / 1024) end
  return string.format("%.1f MB", n / (1024 * 1024))
end

-- Escape the three characters that would break the preview html.
function U.esc(s)
  return (s:gsub("[&<>]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" }))
end

-- Turn the array from hs.pasteboard.contentTypes into a set for quick lookup.
function U.typeSet(list)
  local s = {}
  for _, v in ipairs(list or {}) do
    s[v] = true
  end
  return s
end

-- readURL hands back an NSURL table (or a bare string); pull the url string out.
function U.urlString(u)
  if type(u) == "string" then return u end
  if type(u) == "table" then return u.url or u[1] end
  return nil
end

return U
