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
--- FOUR PREDICATE FACTS, every one of them learned by probing rather than by reading, and
--- all four cost a wrong first attempt.
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

-- Build the predicate for a parse, or nil when there is nothing to ask.
local function predicateFor(parsed)
  local clauses = {}

  if parsed.kind == "recent" then
    local days = cfg.limits.recentDays or 3
    local since = os.time() - (days * 86400) - NSDATE_REFERENCE
    clauses[#clauses + 1] = string.format('(kMDItemContentModificationDate >= CAST(%d, "NSDate"))', since)
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
  local function harvest()
    local rows = {}
    local n = q:count()
    if n > cap then n = cap end
    for i = 1, n do
      local ok, path = pcall(function() return q[i]:valueForAttribute("kMDItemPath") end)
      if ok and path then
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

  -- A low update interval is what makes the early stop possible at all, see the header.
  pcall(function() q:updateInterval(0.1) end)
  q:callbackMessages("didFinish", "inProgress")
  q:setCallback(function(o, msg)
    if delivered then return end
    if msg == "inProgress" then
      if o:count() >= cap then deliver(nil) end
    elseif msg == "didFinish" then
      deliver(nil)
    end
  end)

  q:searchScopes(searchScopes())

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
