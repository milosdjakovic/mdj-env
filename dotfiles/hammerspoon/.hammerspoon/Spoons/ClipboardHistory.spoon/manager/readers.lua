--- Per-type capture readers, a Chain of Responsibility over the pasteboard.
---
--- M.build(util) returns an ordered list of readers. The monitor walks it and
--- uses the first reader whose matches(ctx) is true, so the order is the capture
--- priority: file over image over url over text. That order is deliberate, a
--- Finder copy carries both a file-url and a thumbnail image rep, and we want it
--- recorded as named files, not pasted bytes; a real image copy has no file-url
--- so it still reaches the image reader.
---
--- Each reader is a table:
---   kind                 the entry kind it produces
---   matches(ctx) -> bool  ctx = { set = <contentTypes as a set>, avail = <typesAvailable> }
---   read(ctx) -> entry    a raw entry for store.add, or nil if nothing usable
--- Adding a type is a new reader here plus one line in the composition root.

local M = {}

local floor = math.floor

-- Resolve an opaque Finder file-reference url (file:///.file/id=<inode>) to a
-- real path via NSURL.filePathURL, reached through the ObjC bridge in JXA. This
-- is the only method that works for reference urls; the AppleScript alias
-- manager rejects them. One short subprocess, run only for reference urls.
local function resolveReferenceURL(refURL)
  local js = "ObjC.import('Foundation'); var r = $.NSURL.URLWithString("
    .. string.format("%q", refURL)
    .. "); (r && r.filePathURL) ? r.filePathURL.path.js : '';"
  local ok, resolved = hs.osascript.javascript(js)
  if ok and type(resolved) == "string" and #resolved > 0 then
    return resolved
  end
  return nil
end

-- Turn one copied url item into a real filesystem path, or nil if it is not a
-- resolvable file url. Handles the reference url, the clean filePath a normal
-- file url already carries, and a raw percent-encoded fallback.
local function itemToPath(util, item)
  local urlStr = util.urlString(item)
  local filePath = type(item) == "table" and item.filePath or nil

  if urlStr and urlStr:match("^file:///%.file/") then
    local real = resolveReferenceURL(urlStr)
    if real then
      return (real:gsub("/$", ""))
    end
  end
  if filePath and #filePath > 0 and not filePath:match("^/%.file/") then
    return (filePath:gsub("/$", ""))
  end
  if urlStr and urlStr:match("^file://") then
    local u = urlStr:gsub("^file://[^/]*", ""):gsub("%%(%x%x)", function(h)
      return string.char(tonumber(h, 16))
    end)
    return (u:gsub("/$", ""))
  end
  return nil
end

-- Read every copied file url, not just the first, so a multi-file Finder copy
-- becomes one entry listing all of them.
local function readFilePaths(util)
  local raw = hs.pasteboard.readURL(nil, true) -- all url representations
  local items
  if type(raw) ~= "table" then
    items = {}
  elseif raw.url or raw.filePath or raw.__luaSkinType then
    items = { raw } -- a single NSURL table, not an array
  else
    items = raw
  end
  local paths = {}
  for _, item in ipairs(items) do
    local p = itemToPath(util, item)
    if p then
      paths[#paths + 1] = p
    end
  end
  return paths
end

function M.build(util)
  local fileReader = {
    kind = "file",
    matches = function(ctx)
      return ctx.set["public.file-url"] == true
    end,
    read = function()
      local paths = readFilePaths(util)
      if #paths == 0 then
        return nil
      end
      local title = util.oneLine(util.basename(paths[1]), 80)
      if #paths > 1 then
        title = title .. "  +" .. (#paths - 1)
      end
      local preview = #paths == 1 and util.oneLine(paths[1], 160) or (#paths .. " files")
      return { kind = "file", _paths = paths, ts = os.time(), title = title, preview = preview }
    end,
  }

  local imageReader = {
    kind = "image",
    matches = function(ctx)
      return ctx.avail.image == true
    end,
    read = function()
      local img = hs.pasteboard.readImage()
      if not img then
        return nil
      end
      local sz = img:size() or { w = 0, h = 0 }
      local w, h = floor(sz.w or 0), floor(sz.h or 0)
      return {
        kind = "image", _img = img, w = w, h = h, ts = os.time(),
        title = string.format("Image %dx%d", w, h), preview = "image",
      }
    end,
  }

  local urlReader = {
    kind = "url",
    matches = function(ctx)
      return ctx.avail.URL == true
    end,
    read = function()
      local u = util.urlString(hs.pasteboard.readURL())
      if not u or #u == 0 then
        return nil
      end
      return { kind = "url", text = u, ts = os.time(), title = util.oneLine(u, 100), preview = "URL" }
    end,
  }

  local textReader = {
    kind = "text",
    matches = function(ctx)
      return ctx.avail.string == true
    end,
    read = function()
      local s = hs.pasteboard.readString()
      if not s or #(s:gsub("%s", "")) == 0 then
        return nil
      end
      return {
        kind = "text", text = s, ts = os.time(),
        title = util.oneLine(s, 100), preview = string.format("%d chars", #s),
      }
    end,
  }

  return { fileReader, imageReader, urlReader, textReader }
end

return M
