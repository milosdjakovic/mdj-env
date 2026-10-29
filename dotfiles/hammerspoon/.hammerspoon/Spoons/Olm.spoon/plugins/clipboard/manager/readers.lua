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
---
--- M.textEntry is exported beside the chain, because how a text entry is labelled must
--- have one owner. The append accumulator grows an entry's text after capture and has to
--- relabel it exactly the way a fresh copy would be labelled, so it calls this rather
--- than recomputing the title and the character count on its own and drifting.

local M = {}

local floor = math.floor

-- A Finder copy puts an opaque reference url on the pasteboard, file:///.file/id=<n>, and
-- the real path arrives beside it without any resolving. LuaSkin hands it over as the url's
-- filePath, and Finder also writes every path into NSFilenamesPboardType. This used to
-- resolve the reference through hs.osascript.javascript, and every such call left a
-- JavaScriptCore context in Hammerspoon's process for good, about seven megabytes a copied
-- file, which grew the process past a gigabyte. decisions/olm-icons.md has the measurement.
local function filenamesOnPasteboard()
  local ok, list = pcall(hs.pasteboard.readPListForUTI, nil, "NSFilenamesPboardType")
  if ok and type(list) == "table" then return list end
  return {}
end

-- Turn one copied url item into a real filesystem path, or nil if it is not a
-- resolvable file url. Handles the clean filePath a file url carries, a reference
-- url through the filename at the same position, and a raw percent-encoded fallback.
local function itemToPath(util, item, filename)
  local urlStr = util.urlString(item)
  local filePath = type(item) == "table" and item.filePath or nil

  if filePath and #filePath > 0 and not filePath:match("^/%.file/") then
    return (filePath:gsub("/$", ""))
  end
  if urlStr and urlStr:match("^file:///%.file/") then
    if type(filename) == "string" and #filename > 0 then
      return (filename:gsub("/$", ""))
    end
    return nil
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
  local filenames
  for i, item in ipairs(items) do
    local urlStr = util.urlString(item)
    if not filenames and urlStr and urlStr:match("^file:///%.file/") then
      filenames = filenamesOnPasteboard()
    end
    local p = itemToPath(util, item, filenames and filenames[i])
    if p then
      paths[#paths + 1] = p
    end
  end
  return paths
end

-- A plain-text string that is itself a single http or https url, trimmed. Browsers copy
-- the address bar as plain text with no url type, so the url reader never sees it and a
-- copied url would read as text. This lets the text reader promote such a string to a url.
-- Strict on purpose, the whole string must be one address with no whitespace, so a link
-- sitting inside a sentence stays text. No dot is required after the scheme, so a
-- localhost address is recognised too.
local function urlLike(s)
  local t = s:match("^%s*(%S+)%s*$")
  if t and t:match("^https?://.+") then
    return t
  end
  return nil
end

--- M.textEntry(util, s) -> entry
--- Build a raw text entry from a string, the one place a text entry's label, character
--- count, and size are decided. It does no url promotion, that stays in the text reader
--- above the call, so anything routed through here is text and stays text.
function M.textEntry(util, s)
  -- Character count, not byte count, so a multibyte string reads honestly.
  -- utf8.len returns nil on invalid data, so fall back to the byte length.
  local chars = #s
  if utf8 and utf8.len then
    local n = utf8.len(s)
    if n then chars = n end
  end
  return {
    kind = "text", text = s, ts = os.time(),
    title = util.oneLine(s, 100), preview = string.format("%d chars", chars),
    size = #s, chars = chars,
  }
end

-- Whether this process can open the file for reading. A stat is not enough, since a file
-- in another app's container answers attributes and then refuses to be opened.
local function readable(path)
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end

function M.build(util)
  local fileReader = {
    kind = "file",
    -- A copy from another device over Universal Clipboard arrives as a file url into the
    -- system's own spool, which this process may stat but never open, beside the image's real
    -- bytes. Recorded as a file it could never be frozen or previewed, and the spool is
    -- cleared soon after, so when no linked file can be opened and the pasteboard carries an
    -- image this reader steps aside for the image one. A real Finder copy is always readable,
    -- so its thumbnail rep never wins. The paths are read once and left on ctx for read, and
    -- the first name goes on ctx too so the image keeps what it was called.
    matches = function(ctx)
      if ctx.set["public.file-url"] ~= true then return false end
      ctx.paths = readFilePaths(util)
      if ctx.avail.image == true and #ctx.paths > 0 then
        for _, p in ipairs(ctx.paths) do
          if readable(p) then return true end
        end
        ctx.imageName = util.basename(ctx.paths[1])
        return false
      end
      return true
    end,
    read = function(ctx)
      local paths = ctx.paths or readFilePaths(util)
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
    read = function(ctx)
      local img = hs.pasteboard.readImage()
      if not img then
        return nil
      end
      local sz = img:size() or { w = 0, h = 0 }
      local w, h = floor(sz.w or 0), floor(sz.h or 0)
      local title = string.format("Image %dx%d", w, h)
      if ctx.imageName then
        title = util.oneLine(ctx.imageName, 80)
      end
      return {
        kind = "image", _img = img, w = w, h = h, ts = os.time(),
        title = title, preview = "image",
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
      return { kind = "url", text = u, ts = os.time(), title = util.oneLine(u, 100), preview = "URL", size = #u }
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
      -- A bare pasted url arrives as plain text with no url type, so promote it to a url
      -- here, so the kind, the label, the preview, the url filter, and the icon all agree.
      local u = urlLike(s)
      if u then
        return { kind = "url", text = u, ts = os.time(), title = util.oneLine(u, 100), preview = "URL", size = #u }
      end
      return M.textEntry(util, s)
    end,
  }

  return { fileReader, imageReader, urlReader, textReader }
end

return M
