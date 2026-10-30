--- Index source, the one that answers every unscoped search and the recent list.
---
--- The whole of home, plus the declared starting points, is listed into one file by a small
--- Swift helper, fileindex.swift beside this file, and every search and the recent list is
--- answered by the same helper reading that file. Each run of the helper does one thing, prints
--- at most a page of lines, and exits, so the memory a crawl or a scan needs is never
--- Hammerspoon's. That is the reason this exists. Spotlight answered inside the process, and a
--- recent list gathered tens of thousands of result objects there, which a collect freed but
--- malloc kept, so the footprint settled near two hundred megabytes after a few searches.
---
--- It also has no blind spot. Spotlight holds no path with a dot segment, which needed a second
--- index of its own, and it could not return the top level folders it was told to search inside.
--- The crawl lists both, so one source replaced two. What was given up is that Spotlight always
--- knew about a file saved a second ago, and this index is as old as its last rebuild, see warm.
---
--- The helper ranks only roughly, enough to hand back the right few thousand candidates, and the
--- shared search in Olm ranks those again, so the list orders rows the way every other list does.

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local util = loadfile(spoonPath .. "../util.lua")()

local M = {}
M.name = "index"

--- The Swift compiler, at the fixed absolute path a system binary lives at, declared in the
--- manifest as the system kind with unit naming index, the same as the Quick Look viewer.
local SWIFTC = "/usr/bin/swiftc"
local SOURCE = spoonPath .. "fileindex.swift"

local cfg = {
  storage = nil,
  prune = {},
  searchAlso = {},
  limits = {},
  maxAgeSeconds = 300,
  -- Called after a rebuild lands, so the root can ask the engine to answer again from it.
  onRebuilt = nil,
}

local compiling = false
local building = false
-- Callbacks waiting on the binary or the index, run once whichever they wait for is ready.
local waiting = {}
-- The rebuild in flight, held so it is not collected before its callback arrives.
local buildHandle = nil

local function cacheDir()
  return cfg.storage and cfg.storage.cacheDir("filesearch") or nil
end

local function binaryPath()
  local dir = cacheDir()
  return dir and (dir .. "/fileindex") or nil
end

local function indexPath()
  local dir = cacheDir()
  return dir and (dir .. "/file-index.txt") or nil
end

local function binaryFresh()
  local bin = binaryPath() and hs.fs.attributes(binaryPath(), "modification")
  if not bin then return false end
  local src = hs.fs.attributes(SOURCE, "modification")
  return src == nil or bin >= src
end

local function indexAgeSeconds()
  local t = indexPath() and hs.fs.attributes(indexPath(), "modification")
  if type(t) ~= "number" then return nil end
  return os.time() - t
end

local function flush(ok)
  local list = waiting
  waiting = {}
  for _, fn in ipairs(list) do fn(ok) end
end

--- index.configure(opts)
--- opts.storage        the storage lib, which names the cache directory
--- opts.prune          folder names never descended into
--- opts.searchAlso     starting points outside home, added to home itself
--- opts.limits         the pure limits table, read for the recent window
--- opts.maxAgeSeconds  how stale the index may be before an open rebuilds it
--- opts.onRebuilt      called after a rebuild replaced the index
function M.configure(opts)
  opts = opts or {}
  cfg.storage = opts.storage
  cfg.prune = opts.prune or {}
  cfg.searchAlso = opts.searchAlso or {}
  cfg.limits = opts.limits or {}
  cfg.maxAgeSeconds = opts.maxAgeSeconds or 300
  cfg.onRebuilt = opts.onRebuilt
  return M
end

function M.available()
  if not cacheDir() then return false, "no storage" end
  if binaryFresh() then return true end
  if hs.fs.attributes(SWIFTC, "mode") == "file" then return true end
  return false, "no helper binary and no Swift compiler at " .. SWIFTC
end

--- Claims every query without a scope. A scope goes to the walk source, which reads that folder
--- live and is faster on it than any index.
function M.supports(parsed)
  return parsed.scope == nil
end

--- index.status() -> "building index" when there is no index yet and one is being made,
--- "updating index" when a stale one is being replaced, or nil.
function M.status()
  if not (building or compiling) then return nil end
  return indexAgeSeconds() and "updating index" or "building index"
end

-- Compile the helper when it is missing or older than its source, then call done(ok). The
-- compile runs off the main thread and takes several seconds, which only the first open after
-- an edit to the helper ever pays.
local function ensureBinary(done)
  if binaryFresh() then done(true) return end
  waiting[#waiting + 1] = done
  if compiling then return end
  compiling = true
  hs.fs.mkdir(cacheDir())
  util.run(SWIFTC, { "-O", SOURCE, "-o", binaryPath() }, 120, function(out, err)
    compiling = false
    local ok = binaryFresh()
    if not ok then util.log.i("index helper compile failed, " .. tostring(err)) end
    flush(ok)
  end)
end

-- The roots the crawl starts from, home and every declared starting point that exists here.
local function roots()
  local home = os.getenv("HOME") or ""
  local list, seen = { home }, { [home] = true }
  for _, entry in ipairs(cfg.searchAlso) do
    local path = util.expandHome(tostring(entry)):gsub("/+$", "")
    if path ~= "" and path:sub(1, 1) ~= "/" then path = home .. "/" .. path end
    if path ~= "" and not seen[path] and hs.fs.attributes(path, "mode") == "directory" then
      seen[path] = true
      list[#list + 1] = path
    end
  end
  return list
end

-- Rebuild the index, then call done(ok). The helper writes a temporary file and moves it into
-- place, so a search running meanwhile reads the old index whole and never a half written one.
local function rebuild(done)
  ensureBinary(function(ok)
    if not ok then done(false) return end
    waiting[#waiting + 1] = done
    if building then return end
    building = true
    local args = { "build", indexPath(), table.concat(cfg.prune, "\n") }
    for _, r in ipairs(roots()) do args[#args + 1] = r end
    buildHandle = util.run(binaryPath(), args, 60, function(out, err)
      buildHandle = nil
      building = false
      local built = out ~= nil and indexAgeSeconds() ~= nil
      if not built then util.log.i("index build failed, " .. tostring(err)) end
      flush(built)
      if built and cfg.onRebuilt then cfg.onRebuilt() end
    end)
  end)
end

--- index.warm() - called when the picker opens. Builds the index when it is missing and
--- rebuilds it in the background when it is older than maxAgeSeconds, so a rebuild happens only
--- on an open, at most once per that many seconds, and never while nobody is searching.
function M.warm()
  if not cacheDir() then return end
  local age = indexAgeSeconds()
  if age and age <= cfg.maxAgeSeconds then return end
  rebuild(function() end)
end

-- Turn the helper's lines into rows.
local function rowsOf(out)
  local rows = {}
  for line in util.lines(out or "") do
    local mtime, flags, path = line:match("^(%d+)\t(%a*)\t(.+)$")
    if path then
      rows[#rows + 1] = util.row(path, {
        isDir = flags:find("d", 1, true) ~= nil,
        modified = tonumber(mtime),
        source = M.name,
      })
    end
  end
  return rows
end

-- The helper's arguments for a parse, or nil and a status when there is nothing to ask.
local function argsFor(parsed, cap)
  local exts = {}
  for _, e in ipairs(parsed.exts or {}) do
    exts[#exts + 1] = "-e"
    exts[#exts + 1] = e
  end
  if parsed.kind == "recent" then
    if parsed.hidden then return nil, "type something to search hidden files" end
    -- A bare type token is its own bound, so it reaches back as far as the index does rather
    -- than asking for files of that type changed in the last few days, which is reliably empty.
    local since = 0
    if #exts == 0 then since = os.time() - (cfg.limits.recentDays or 7) * 86400 end
    local args = { "recent", indexPath(), tostring(cap), tostring(since) }
    for _, a in ipairs(exts) do args[#args + 1] = a end
    return args
  end
  if #parsed.words == 0 then return nil, "nothing to search for" end
  local args = { "search", indexPath(), tostring(cap) }
  if parsed.hidden then args[#args + 1] = "-h" end
  for _, a in ipairs(exts) do args[#args + 1] = a end
  for _, w in ipairs(parsed.words) do args[#args + 1] = w end
  return args
end

--- index.search(parsed, ctx, cb) -> handle or nil
--- Nil only while the helper or the first index is being made, since that search has nothing to
--- cancel yet, and the engine's generation guard drops its answer if the person has moved on.
function M.search(parsed, ctx, cb)
  local cap = ctx.cap or 200
  local function run()
    local args, status = argsFor(parsed, cap)
    if not args then cb({}, status) return nil end
    return util.run(binaryPath(), args, ctx.timeoutSeconds, function(out, err)
      if not out then cb({}, err and "index search failed" or nil) return end
      cb(rowsOf(out), nil)
    end)
  end
  if binaryFresh() and indexAgeSeconds() then return run() end
  rebuild(function(ok)
    if ok then run() else cb({}, "no source available") end
  end)
  return nil
end

return M
