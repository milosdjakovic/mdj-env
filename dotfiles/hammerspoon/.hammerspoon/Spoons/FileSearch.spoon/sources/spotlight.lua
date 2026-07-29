--- Spotlight source, the one that answers an ordinary unscoped search.
---
--- macOS already maintains a live filesystem index, updated by the kernel as files change,
--- so this source builds nothing and costs nothing when idle. It runs through hs.spotlight,
--- which is in process and hands its work to another thread, so there is no shellout and no
--- process to spawn. Measured on one machine, a single name query over the whole home
--- answers in about 105 milliseconds almost regardless of what it asks, because the cost is
--- round trip overhead rather than work.
---
--- WHAT IT CANNOT SEE, and this is the reason two other sources exist. Spotlight indexes no
--- path containing a dot segment. Not the dot entry itself and not anything beneath it, so
--- every file in ~/.config is invisible to it, measured as zero results for all 599 of them.
--- That is not a filter that can be turned off, the data is simply absent, which is why the
--- hidden source walks that blind spot itself rather than asking here with a different flag.
---
--- FIVE FACTS ABOUT THE QUERY, every one of them learned by probing rather than by reading,
--- and all five cost a wrong first attempt.
---
--- The mdfind wildcard form is not accepted. `kMDItemFSName == "*x*"c` works on the command
--- line and hs.spotlight rejects it outright as an unparseable format string. The form that
--- works is the proper NSPredicate one, LIKE with explicit wildcards and the cd modifier for
--- case and diacritic insensitivity.
---
--- $time.now is not accepted either. mdfind takes `$time.now(-259200)` and hs.spotlight
--- fails to parse the selector, so a date bound has to be CAST instead. And an NSDate counts
--- seconds from 2001-01-01 rather than from the unix epoch, so the reference offset has to be
--- subtracted or the bound lands thirty one years in the past and matches everything.
---
--- An attribute is cheap to read only if the query was told about it. Undeclared, each
--- kMDItemContentType read cost 0.284 milliseconds, which is forty times a declared one and
--- turned a two thousand row harvest into more than half a second of blocked main thread. So
--- valueListAttributes is not an optimisation here, it is the difference between a picker that
--- types smoothly and one that stalls on a three letter word. See the note at the call.
---
--- inProgress fires far too rarely to bound a broad gather at its default rate. A probe
--- asking to stop at two hundred results was first notified at three thousand eight hundred,
--- by which point the query had run a full second. updateInterval is what fixes that, so it
--- is set low deliberately and the early stop is what keeps a vague three letter query from
--- gathering tens of thousands of rows nobody will scroll to.
---
--- And the search scope is NOT simply the home directory. Every broad probe came back
--- dominated by ~/Library, thousands of logs and caches, which cost gather time and then get
--- discarded. So the scope is the top level of home minus the pruned names, which is the same
--- pure data the hidden index walks by, and the noise never enters the gather at all.

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local util = loadfile(spoonPath .. "../util.lua")()

local M = {}
M.name = "spotlight"

-- NSDate's epoch, 2001-01-01, against the unix one.
local NSDATE_REFERENCE = 978307200

local cfg = {
  prune = {},
  limits = {},
}

-- The live query, parked in a field. Holding it is not optional. An hs.spotlight object is
-- userdata whose finalizer stops the query, so one nothing refers to can be collected mid
-- flight and the callback then simply never arrives, which is the same hazard this config
-- documents for timers and reads exactly like a search that found nothing.
local active = nil
local activeGen = 0

--- spotlight.configure(opts)
--- opts.prune   directory names never worth searching, used to build the scope list
--- opts.limits  the pure limits table, read for the recent window
function M.configure(opts)
  opts = opts or {}
  cfg.prune = opts.prune or {}
  cfg.limits = opts.limits or {}
  cfg.scopes = nil -- rebuilt lazily, so a configure after a reload picks up new folders
  return M
end

function M.available()
  if not hs.spotlight then return false, "hs.spotlight unavailable" end
  return true
end

--- Answers anything with no scope that is not asking for hidden paths. A scope goes to the
--- walk source, which is both faster on a small tree and able to see dotfiles, and hidden
--- goes to the index that actually holds them.
function M.supports(parsed)
  if parsed.scope then return false end
  if parsed.hidden then return false end
  return true
end

-- The directories worth searching, the top level of home minus the pruned names. Computed
-- once and reused, since a new top level folder is rare and a reload rebuilds it.
local function searchScopes()
  if cfg.scopes then return cfg.scopes end
  local home = os.getenv("HOME") or ""
  local skip = {}
  for _, name in ipairs(cfg.prune or {}) do skip[name] = true end
  local scopes = {}
  local ok = pcall(function()
    for entry in hs.fs.dir(home) do
      if entry ~= "." and entry ~= ".." and not skip[entry] then
        local full = home .. "/" .. entry
        -- Dot entries are pointless here, since nothing under one is indexed anyway.
        if entry:sub(1, 1) ~= "." and hs.fs.attributes(full, "mode") == "directory" then
          scopes[#scopes + 1] = full
        end
      end
    end
  end)
  if not ok or #scopes == 0 then scopes = { home } end
  cfg.scopes = scopes
  return scopes
end

-- The scope roots are invisible to a search of themselves, which is the second blind spot here
-- and it was found by looking for ~/Downloads and getting everything called downloads except
-- that. A query searches INSIDE each top level folder, so those folders are never results, and
-- they are exactly the ones with short obvious names people type first.
--
-- They are a handful of entries, so they are matched here in plain Lua and added to what the
-- index returned. It belongs in this file for the same reason the hidden source exists at all, a
-- blind spot is owned by the source that has it, rather than worked around by the engine, which
-- knows nothing about scopes.
--
-- Skipped when a type filter is on, since a directory has no extension and could not satisfy it.
local function matchingRoots(parsed)
  if parsed.kind ~= "search" then return {} end
  if parsed.exts and #parsed.exts > 0 then return {} end
  local rows = {}
  for _, dir in ipairs(searchScopes()) do
    local name = (dir:match("([^/]+)$") or ""):lower()
    local all = #parsed.words > 0
    for _, w in ipairs(parsed.words) do
      if not name:find(w:lower(), 1, true) then all = false break end
    end
    if all then rows[#rows + 1] = util.row(dir, { isDir = true, source = M.name }) end
  end
  return rows
end

-- Order rows newest first. This is NOT the same job as the sort descriptor and both are needed.
-- The descriptor decides which rows the query holds at the top, and so which ones a capped harvest
-- reads at all, while this decides the order of what came back. They come apart whenever the
-- gather stops early, because a query that has not finished gathering has not sorted anything, so
-- without this a bare type token would show a date sorted heading over an arbitrary sample.
--
-- A missing date, or one in the future, is treated as unknown and sorts last. A single file with
-- corrupt metadata would otherwise squat at the top of the default view permanently, and two of
-- them were doing exactly that.
local function sortByDate(rows)
  local horizon = os.time() + 86400
  local function key(r)
    local d = r.modified or 0
    if d > horizon then return 0 end
    return d
  end
  table.sort(rows, function(a, b)
    local da, db = key(a), key(b)
    if da == db then return (a.path or "") < (b.path or "") end
    return da > db
  end)
  return rows
end

-- Escape a fragment for embedding in a predicate string literal.
local function esc(s)
  return tostring(s or ""):gsub("\\", "\\\\"):gsub('"', '\\"')
end

-- Every word must appear in the name, in any order, which is the same words semantics the
-- rest of this config uses for searching inside long text.
local function nameClauses(words)
  local parts = {}
  for _, w in ipairs(words) do
    parts[#parts + 1] = string.format('(kMDItemFSName LIKE[cd] "*%s*")', esc(w))
  end
  return parts
end

-- One clause matching any of the extensions a type token covers.
local function extClause(exts)
  local parts = {}
  for _, e in ipairs(exts) do
    parts[#parts + 1] = string.format('(kMDItemFSName LIKE[cd] "*.%s")', esc(e))
  end
  return "(" .. table.concat(parts, " || ") .. ")"
end

-- A bare type token is kind recent too, since nothing was typed. It is worth naming, because the
-- two shapes want opposite treatment and conflating them is what made `.py` find nothing.
local function isTypeOnly(parsed)
  return parsed.kind == "recent" and parsed.exts ~= nil and #parsed.exts > 0
end

-- How many rows a bare type token may READ to fill a page, as opposed to how many it keeps.
--
-- It is the one query shape that has to filter while harvesting rather than after it, and that is
-- not a duplicate of the engine's noise filter, it is the only place the work can be done. The
-- engine can only filter what a source handed it, so returning a capped sample first means the
-- filter throws most of the sample away, which is exactly why `.js` came back with eleven rows.
--
-- The reason it cannot simply read deeper until the page is full is density. Only 0.12 percent of
-- the 204,496 js files here sit outside a pruned directory, so filling two hundred rows means
-- reading 161,334 of them and five seconds. The list is date sorted, so a bound spends its budget
-- on the newest candidates and a very common extension returns FEWER rows rather than taking
-- longer, which is the right way round. Measured, py fills a page by row 204 and png by row 799,
-- so neither comes near this.
--
-- Pushing the prune into the predicate was tried first and does nothing at all. Excluding
-- */node_modules/* through kMDItemPath left the count at 204,496 unchanged, so that attribute is
-- not queryable this way whatever the syntax suggests.
local SCAN_BUDGET = 6000

-- Build the predicate for a parse, or nil when there is nothing to ask.
local function predicateFor(parsed)
  local clauses = {}

  if parsed.kind == "recent" then
    -- The date bound ONLY when there is nothing else to narrow by, which is the fix for a bare
    -- type token finding nothing. `.py` parses as recent with an extension filter, and ANDing the
    -- two asked for python files modified in the last few days, which is reliably empty. It is
    -- also far slower rather than cheaper, measured at 4839 milliseconds to return zero against
    -- 475 for the same name pattern with no bound at all, so a date bound sitting next to a name
    -- pattern costs on both counts. The type filter is its own bound, so nothing replaces it.
    if not isTypeOnly(parsed) then
      local days = cfg.limits.recentDays or 7
      local since = os.time() - (days * 86400) - NSDATE_REFERENCE
      clauses[#clauses + 1] = string.format('(kMDItemContentModificationDate >= CAST(%d, "NSDate"))', since)
    end
  else
    for _, c in ipairs(nameClauses(parsed.words)) do
      clauses[#clauses + 1] = c
    end
  end

  if parsed.exts and #parsed.exts > 0 then
    clauses[#clauses + 1] = extClause(parsed.exts)
  end

  if #clauses == 0 then return nil end
  return table.concat(clauses, " && ")
end

--- spotlight.cancel() - abandon the live query.
function M.cancel()
  activeGen = activeGen + 1
  if active then
    pcall(function() active:stop() end)
    active = nil
  end
end

--- spotlight.search(parsed, ctx, cb)
function M.search(parsed, ctx, cb)
  local pred = predicateFor(parsed)
  if not pred then
    cb({}, "nothing to search for")
    return
  end

  M.cancel()
  activeGen = activeGen + 1
  local gen = activeGen
  local cap = ctx.cap or 200
  local delivered = false

  local q = hs.spotlight.new()
  active = q

  -- Read the capped rows out into plain data. Reading an attribute crosses into
  -- Objective C per call, so only what a row actually needs is read, and the modification
  -- date only where it is the ordering.
  local wantDate = (parsed.kind == "recent")
  -- A bare type token filters noise while it reads, and only that shape does. The bang sigil
  -- switches it off here for the same reason it does in the engine, one meaning in one place.
  local dropNoise = isTypeOnly(parsed) and not parsed.ignored and #(cfg.prune or {}) > 0
  local function isNoisy(path)
    for _, name in ipairs(cfg.prune) do
      if path:find("/" .. name .. "/", 1, true) then return true end
    end
    return false
  end

  local function harvest()
    -- The scope roots first, since the index cannot return them. The set is only built when
    -- there is one to skip, so the ordinary case pays no lookup per row at all.
    local rows = matchingRoots(parsed)
    local seen = nil
    if #rows > 0 then
      seen = {}
      for _, r in ipairs(rows) do seen[r.path] = true end
    end
    -- How far to READ, which is not how many to KEEP. They are the same number for every shape but
    -- a bare type token, which reads deeper and keeps fewer because it filters as it goes.
    local n = q:count()
    local scanLimit = dropNoise and SCAN_BUDGET or cap
    if n > scanLimit then n = scanLimit end
    for i = 1, n do
      if #rows >= cap then break end
      local ok, path = pcall(function() return q[i]:valueForAttribute("kMDItemPath") end)
      if ok and path and not (seen and seen[path]) and not (dropNoise and isNoisy(path)) then
        local isDir = false
        local okT, ctype = pcall(function() return q[i]:valueForAttribute("kMDItemContentType") end)
        if okT and ctype == "public.folder" then isDir = true end
        local modified = nil
        if wantDate then
          local okD, d = pcall(function() return q[i]:valueForAttribute("kMDItemContentModificationDate") end)
          if okD and type(d) == "number" then modified = d end
        end
        rows[#rows + 1] = util.row(path, { isDir = isDir, modified = modified, source = M.name })
      end
    end
    if parsed.kind == "recent" then sortByDate(rows) end
    return rows
  end

  local function deliver(reason)
    if delivered or gen ~= activeGen then return end
    delivered = true
    local rows = harvest()
    pcall(function() q:stop() end)
    if active == q then active = nil end
    cb(rows, reason)
  end

  -- The early stop keeps a vague SEARCH from gathering tens of thousands of rows, and it is
  -- deliberately off for anything ordered by date, which is both recent shapes.
  --
  -- The reason is that an early stop and a date order are incompatible. A query that has not
  -- finished gathering has not sorted anything, so stopping early hands back an arbitrary sample
  -- and then calling it newest first is a lie. It also breaks the type token scan, which is only
  -- worth bounding because it spends its budget on the newest candidates first.
  --
  -- Waiting is affordable because the gather is the cheap half. Sixty thousand results gather in
  -- about sixty milliseconds and the whole js extension, 204 thousand files, in 385, while the
  -- expensive half is reading rows out and only a page of those is ever read. A cold index is the
  -- exception, where the same js gather measured 6.3 seconds, and the timeout is the backstop for
  -- that, delivering what was gathered rather than nothing.
  local byDate = parsed.kind == "recent"

  -- A low update interval is what makes the early stop possible at all, see the header.
  pcall(function() q:updateInterval(0.1) end)
  q:callbackMessages("didFinish", "inProgress")
  q:setCallback(function(o, msg)
    if delivered then return end
    if msg == "inProgress" then
      if not byDate and o:count() >= cap then deliver(nil) end
    elseif msg == "didFinish" then
      deliver(nil)
    end
  end)

  q:searchScopes(searchScopes())

  -- DECLARE WHAT WILL BE READ, or reading it costs forty times more. An attribute the query
  -- was never told about is fetched one row at a time on demand, and kMDItemContentType
  -- measured 0.284 milliseconds per row that way, so harvesting two thousand rows blocked the
  -- main thread for 567 milliseconds and was felt as the picker freezing mid word, which is
  -- exactly the lag this was reported as. Named up front the same read costs 0.008. Measured
  -- by alternating the declaration over six fresh terms, mean harvest 300 milliseconds against
  -- 21, with the gather unchanged at 128 against 110, so nothing is traded, the cost is simply
  -- removed. kMDItemPath is already cheap undeclared at 0.011 and is left alone, and the
  -- modification date needs no declaration either because the recent query already names it as
  -- its sort key, which puts it in the query's own attribute set for free.
  pcall(function() q:valueListAttributes({ "kMDItemContentType" }) end)

  -- Recent is the one query with a meaningful order of its own, newest first, and Spotlight
  -- sorts it inside the index so no row has to be stat'd and nothing is sorted in Lua.
  -- The descriptor takes a key and a direction as named fields. Anything else is rejected at
  -- the bridge with "key field missing in NSSortDescriptor table", which is one more form that
  -- had to be found by running it rather than by reading.
  if parsed.kind == "recent" then
    pcall(function()
      q:sortDescriptors({ { key = "kMDItemContentModificationDate", ascending = false } })
    end)
  end

  local ok, err = pcall(function() q:queryString(pred) end)
  if not ok then
    active = nil
    cb({}, "bad predicate, " .. tostring(err))
    return
  end

  -- The timeout is the backstop for a query that never reports finishing. Held in a local
  -- the closure keeps alive, for the same collection reason as the query itself.
  local timeout
  timeout = util.after(ctx.timeoutSeconds or 5, function()
    if not delivered then deliver("timed out") end
  end)
  local _ = timeout

  q:start()
end

return M
