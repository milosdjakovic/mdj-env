--- File search engine, the Context.
---
--- It owns the behaviour and talks only through the source contract, naming no backend.
--- Give it a raw query string and it answers with rows to draw right now, arranging for
--- whatever it does not yet know to arrive later. Everything about WHERE files come from
--- lives in the sources, and everything about WHICH source answers a given query shape
--- lives in the order the composition root registered them.
---
--- THE ONE IDEA WORTH KNOWING is that a search costs one round trip per search rather
--- than one per keystroke. Typing eleven characters fires one query, not eleven, because
--- once results are held a longer text over the same population can only ever match a
--- subset of them, so it is filtered locally with no dispatch at all. That single
--- property is what makes this feel instant, and it is worth more than any cache, which
--- is why there is no result cache here. A cache would be wrong at the exact moment the
--- tool is used, right after something was downloaded or built, while narrowing is always
--- exactly as live as the results it narrows.
---
--- The guard on narrowing has three parts and all three matter. The population must be
--- identical, which query.narrows decides. The text must have grown rather than changed,
--- which it also decides. And the held set must not have been truncated by its cap, which
--- only this file knows, because a subset of a truncated set is not a subset of the truth.
--- Retaining well above what is displayed is what keeps that third condition true in
--- practice.
---
--- Everything expensive happens elsewhere. Spotlight queries run off the main thread and
--- call back, and the walk and the hidden index run as separate processes. What is left
--- here is parsing, a local filter, and an ordering, all of which are microseconds. That
--- is not an optimisation, it is a requirement, because Hammerspoon owns the event taps
--- for every leader key in this config and a block would freeze the whole keyboard.

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(spoonPath .. name)
  if not chunk then
    error("FileSearch: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end

local query = load("query.lua")
local util = load("util.lua")

local obj = {}
obj.__index = obj
obj.name = "FileSearch"
obj.version = "1.0"
obj.author = "mdj-env"
obj.license = "MIT"

local log = util.log

-- Defaults, overridden wholesale by the limits table the root injects from config. They
-- exist so the engine still runs unconfigured rather than erroring on a nil.
local DEFAULTS = {
  debounceMs = 70,
  displayCap = 200,
  retainCap = 2000,
  minChars = 3,
  timeoutSeconds = 5,
  recentCount = 40,
  recentDays = 14,
  hiddenMaxAgeSeconds = 300,
}

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function obj:init()
  self.types = {}
  self.roots = {}
  self.prune = {}
  self.limits = DEFAULTS
  -- Underscored deliberately. The spoon root hangs a table of sources BY NAME on this same
  -- object as `sources`, for readability at the call site, so the engine's own ordered list
  -- must not use that name or init would wipe the registry the root just built. That is not a
  -- hypothetical, it was the first thing the integration run caught.
  self._sources = {}
  -- _contract is deliberately NOT cleared here. The spoon root assigns it at load time and
  -- reads it back when building the engine's options, so clearing it in init left the
  -- validation silently switched off, with three sources registered and none of them checked.
  -- Same family of bug as the sources collision above, and just as quiet.
  self.matcher = nil
  self.onResults = nil

  self._parsed = nil
  self._retained = {}
  self._truncated = false
  self._display = {}
  self._status = nil
  self._gen = 0
  self._debounce = nil
  self._activeSource = nil
  self._recents = nil
  self._recentsPending = false
  return self
end

--- engine:configure(opts)
--- opts.types      token to extension map, pure data from config
--- opts.roots      directory alias map, pure data from config
--- opts.prune      directory names whose contents are noise in an unscoped result, which is
---                 what the bang sigil switches off
--- opts.limits     caps and timings, pure data from config
--- opts.sources    ordered source list. Order IS the conflict resolution, the first
---                 source claiming a query shape owns it, so this is the one decision
---                 that cannot be made anywhere but the composition root
--- opts.contract   the contract module, injected so the engine validates against the
---                 same declaration a source author reads
--- opts.matcher    match(query, hay) -> score or nil, used for the local narrow so the
---                 filter that runs between round trips agrees with the one the chooser
---                 applies to what it draws. Omit it and a plain all words test is used
--- opts.onResults  called with no arguments whenever rows changed underneath the caller,
---                 so the surface can redraw. The engine never touches a chooser itself
function obj:configure(opts)
  opts = opts or {}
  self.types = opts.types or {}
  self.roots = opts.roots or {}
  self.prune = opts.prune or {}
  self.matcher = opts.matcher
  self.onResults = opts.onResults
  self._contract = opts.contract

  local limits = {}
  for k, v in pairs(DEFAULTS) do limits[k] = v end
  for k, v in pairs(opts.limits or {}) do limits[k] = v end
  self.limits = limits

  -- Validate once at load and drop whatever does not conform, so a half written source
  -- fails visibly here rather than mid query.
  self._sources = {}
  for _, src in ipairs(opts.sources or {}) do
    if self._contract then
      local ok, missing = self._contract.validate(src)
      if ok then
        self._sources[#self._sources + 1] = src
      else
        log.e("dropping source " .. tostring(src and src.name or "?") .. ", missing " .. tostring(missing))
      end
    else
      self._sources[#self._sources + 1] = src
    end
  end

  return self
end

--------------------------------------------------------------------------------
-- Scope resolution
--------------------------------------------------------------------------------

local function isDir(path)
  if not path or path == "" then return false end
  local attrs = hs.fs.attributes(path, "mode")
  return attrs == "directory"
end

--- Resolve a raw scope token to a real directory, or nil when it names nothing.
---
--- Three tries in order. An absolute or tilde path is taken literally, which is what
--- makes browsing into a result work, since that path is absolute. Then the first segment
--- is looked up in the alias table, so `dl/` and `downloads/` both land in Downloads and
--- further segments are appended beneath it. Then the whole token is tried literally
--- under the home directory.
---
--- This is deliberately synchronous and shells out to nothing. A frecency tool would be
--- the obvious fourth try and would make `someproject/` resolve without an alias, but it
--- is a shellout, and an asynchronous scope resolution would mean two hops before any row
--- appears. That trade is not worth it for the first version, and adding it later is a
--- fourth branch here plus a dependency declaration.
function obj:_resolveScope(token)
  if not token then return nil end
  local t = token:gsub("/+$", "")
  if t == "" then return "/" end

  t = util.expandHome(t)
  if t:sub(1, 1) == "/" then
    return isDir(t) and t or nil
  end

  local home = os.getenv("HOME") or ""
  local first, rest = t:match("^([^/]+)/?(.*)$")
  if first then
    local mapped = self.roots[first:lower()]
    if mapped ~= nil then
      local base = (mapped == "") and home or (home .. "/" .. mapped)
      local full = (rest ~= "") and (base .. "/" .. rest) or base
      if isDir(full) then return full end
    end
  end

  local literal = home .. "/" .. t
  if isDir(literal) then return literal end
  return nil
end

--------------------------------------------------------------------------------
-- Local filtering and ordering
--------------------------------------------------------------------------------

local function allWordsIn(hay, words)
  for i = 1, #words do
    if not hay:find(words[i]:lower(), 1, true) then return false end
  end
  return true
end

-- Filter held rows down to a longer text. Uses the injected matcher so the narrow agrees
-- with the policy every chooser applies, falling back to an all words test.
function obj:_filter(rows, parsed)
  if parsed.text == "" then return rows end
  local matcher = self.matcher
  local out = {}
  for i = 1, #rows do
    local r = rows[i]
    local hay = r.path or ""
    local keep
    if type(matcher) == "function" then
      keep = matcher(parsed.text, hay) ~= nil
    else
      keep = allWordsIn(hay:lower(), parsed.words)
    end
    if keep then out[#out + 1] = r end
  end
  return out
end

--- Order rows for display.
---
--- A browse and a recent list arrive already ordered by the thing that makes them useful,
--- modification time, so their order is kept. A search is ordered here, and deliberately
--- without a fuzzy scorer. A path is long text searched from the inside where you type a
--- real fragment, which is the same reasoning that put the clipboard on the words strategy
--- rather than fuzzy, so the ordering answers three plain questions. Does the basename
--- hold the whole text, does it hold every word, and failing both, is the path shorter.
--- Shorter wins because a match near the top of a tree is nearly always the one meant, and
--- it is what keeps a vendored copy buried twelve levels down from outranking the real file.
function obj:_order(rows, parsed)
  if parsed.kind ~= "search" or parsed.text == "" then return rows end
  local text = parsed.text:lower()
  local scored = {}
  for i = 1, #rows do
    local r = rows[i]
    local name = (r.name or ""):lower()
    local s = 0
    if name:find(text, 1, true) then s = s + 1000 end
    if allWordsIn(name, parsed.words) then s = s + 500 end
    if r.isDir then s = s + 50 end
    s = s - math.min(#(r.path or ""), 500) / 25
    scored[#scored + 1] = { row = r, score = s, idx = i }
  end
  table.sort(scored, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.idx < b.idx
  end)
  local out = {}
  for i = 1, #scored do out[i] = scored[i].row end
  return out
end

--- Drop rows living inside a directory nobody searches for, the vendored copies and the
--- caches. This is what the bang sigil switches off, and it is the ONE meaning that sigil
--- carries so it reads the same whichever source answered.
---
--- It applies to unscoped results only, and that exception matters. Naming a directory is an
--- explicit statement about where to look, so scoping into `node_modules/` must not then have
--- every row filtered out for being inside node_modules. The walk source already applies the
--- same list as walk excludes, so a scoped search is filtered at the tree rather than here.
function obj:_denoise(rows, parsed)
  if parsed.ignored or parsed.scope then return rows end
  if #self.prune == 0 then return rows end
  local out = {}
  for i = 1, #rows do
    local path = rows[i].path or ""
    local noisy = false
    for _, name in ipairs(self.prune) do
      if path:find("/" .. name .. "/", 1, true) then noisy = true break end
    end
    if not noisy then out[#out + 1] = rows[i] end
  end
  return out
end

-- Publish a result set. Keeps the retained copy for narrowing, notes whether it was
-- truncated, and cuts the display list to its own smaller cap.
--
-- Truncation is noted against what the source returned rather than what survived the noise
-- filter, because it is the source's cap that decides whether the held set is the whole truth,
-- which is the condition narrowing depends on.
function obj:_publish(rows, parsed, status)
  local retainCap = self.limits.retainCap
  self._truncated = #rows >= retainCap
  -- Only a real search result may be narrowed against. See the flag's note in rowsFor.
  self._narrowable = true
  rows = self:_denoise(rows, parsed)
  local retained = rows
  if #retained > retainCap then
    local cut = {}
    for i = 1, retainCap do cut[i] = retained[i] end
    retained = cut
  end
  self._retained = retained
  self._parsedShape = parsed
  self:_redraw(parsed, status)
end

-- Recompute what is displayed from what is retained, without any dispatch.
function obj:_redraw(parsed, status)
  local rows = self._retained
  if self._parsedShape and query.narrows(self._parsedShape, parsed) then
    rows = self:_filter(rows, parsed)
  end
  rows = self:_order(rows, parsed)
  local cap = self.limits.displayCap
  if #rows > cap then
    local cut = {}
    for i = 1, cap do cut[i] = rows[i] end
    rows = cut
  end
  self._display = rows
  self._status = status
  if self.onResults then self.onResults() end
end

--------------------------------------------------------------------------------
-- Dispatch
--------------------------------------------------------------------------------

-- The first registered source that is available and supports this query shape. Order is
-- the whole conflict resolution, so this never inspects what a source is.
function obj:_sourceFor(parsed)
  for _, src in ipairs(self._sources) do
    if src.supports(parsed) then
      local ok, reason = src.available()
      if ok then return src end
      log.i("source " .. tostring(src.name or "?") .. " stepped aside, " .. tostring(reason))
    end
  end
  return nil
end

function obj:_cancelInflight()
  if self._activeSource and self._activeSource.cancel then
    pcall(function() self._activeSource.cancel() end)
  end
  self._activeSource = nil
end

-- Fire the search. Every callback carries the generation it was issued under, so an
-- answer to a query the user has already moved past is dropped rather than painted. This
-- is separate from cancelling, because a task terminated a microsecond too late still has
-- its callback queued.
function obj:_dispatch(parsed)
  self._gen = self._gen + 1
  local gen = self._gen
  self:_cancelInflight()

  local scopePath = parsed.scope and self:_resolveScope(parsed.scope) or nil
  if parsed.scope and not scopePath then
    self._retained, self._parsedShape, self._truncated = {}, parsed, false
    self:_redraw(parsed, "no such directory")
    return
  end

  local src = self:_sourceFor(parsed)
  if not src then
    self._retained, self._parsedShape, self._truncated = {}, parsed, false
    self:_redraw(parsed, "no source available")
    return
  end

  self._activeSource = src
  self:_redraw(parsed, "searching")

  local ctx = {
    scopePath = scopePath,
    cap = self.limits.retainCap,
    timeoutSeconds = self.limits.timeoutSeconds,
    limits = self.limits,
  }

  src.search(parsed, ctx, function(rows, reason)
    if gen ~= self._gen then return end
    self._activeSource = nil
    if reason then log.i("search via " .. tostring(src.name or "?") .. ", " .. tostring(reason)) end
    -- Spelled out rather than folded into an and/or expression. `cond and nil or fallback`
    -- always yields the fallback in Lua, since `and nil` is falsy, which is exactly how every
    -- successful search came back labelled as having found nothing.
    rows = rows or {}
    local status = nil
    if #rows == 0 then status = reason or "nothing found" end
    self:_publish(rows, parsed, status)
  end)
end

--------------------------------------------------------------------------------
-- Public api, what the surface talks to
--------------------------------------------------------------------------------

--- engine:reset()
--- Start a fresh session. Clears held state and begins the recent files fetch so the list
--- has something in it before anything is typed, which is why this runs on show rather
--- than on the first keystroke. The round trip then overlaps with the user reading.
function obj:reset()
  self:_cancelInflight()
  if self._debounce then self._debounce.cancel() end
  self._debounce = nil
  self._gen = self._gen + 1
  self._parsed = nil
  self._parsedShape = nil
  self._retained = {}
  self._display = {}
  self._truncated = false
  self._narrowable = false
  self._status = nil
  self:_fetchRecents()
  return self
end

-- Recent files, the state the picker opens in. Held for the session rather than per query,
-- since what you touched lately does not change while a picker is open.
function obj:_fetchRecents()
  if self._recentsPending then return end
  local parsed = query.parse("", self.types)
  local src = self:_sourceFor(parsed)
  if not src then return end
  self._recentsPending = true
  local ctx = {
    scopePath = nil,
    cap = self.limits.recentCount,
    timeoutSeconds = self.limits.timeoutSeconds,
    limits = self.limits,
  }
  src.search(parsed, ctx, function(rows)
    self._recentsPending = false
    self._recents = rows or {}
    -- Only paint them if nothing has been typed since, otherwise a slow recents fetch
    -- would overwrite a real search the user already started.
    if not self._parsed or self._parsed.kind == "recent" then
      self._retained = self._recents
      self._parsedShape = parsed
      self._truncated = false
      -- The recent list is the other place the retained set is filled without going through
      -- _publish, so it has to clear this too or a search that published earlier would leave
      -- the flag on and the next typed query would narrow against recents.
      self._narrowable = false
      self:_redraw(self._parsed or parsed, nil)
    end
  end)
end

--- engine:rowsFor(raw) -> rows, status
--- The surface calls this on every query change and gets what to draw right now. It may
--- schedule work as a side effect, which is unavoidable because the row supplier is the
--- only hook a query change reaches, and is the reason this is named for what it returns
--- rather than for what it does.
---
--- Three outcomes. A query that narrows the held one is filtered locally and drawn with no
--- dispatch, which is the common case mid typing. A query too short or too broad to be
--- worth a round trip shows the recent list. Anything else arms the debounce, and the rows
--- already on screen stay until the answer lands, because clearing them first makes a
--- picker flicker for no gain.
function obj:rowsFor(raw)
  local parsed = query.parse(raw or "", self.types)
  local prev = self._parsed
  self._parsed = parsed

  if prev and prev.raw == parsed.raw then
    return self._display, self._status
  end

  -- Nothing typed, and no type filter to make it a real query. Show the session's
  -- recent list rather than dispatching.
  if parsed.kind == "recent" and not parsed.exts and not parsed.hidden then
    if self._debounce then self._debounce.cancel() end
    self._debounce = nil
    self:_cancelInflight()
    self._gen = self._gen + 1
    self._retained = self._recents or {}
    self._parsedShape = query.parse("", self.types)
    self._truncated = false
    self._narrowable = false
    -- Spelled out, for the same reason as the one in _dispatch. This one read as loading
    -- forever, even with the recent list drawn on screen.
    local recentStatus = nil
    if not self._recents then recentStatus = "loading" end
    self:_redraw(parsed, recentStatus)
    return self._display, self._status
  end

  -- Too short to be useful unscoped. A scope lifts the floor, since the candidate set is
  -- already small enough that one character is a fair question.
  if parsed.kind == "search" and not parsed.scope and #parsed.text < self.limits.minChars then
    if self._debounce then self._debounce.cancel() end
    self._debounce = nil
    self._retained = self._recents or {}
    self._parsedShape = query.parse("", self.types)
    self._truncated = false
    self._narrowable = false
    self:_redraw(parsed, "keep typing")
    return self._display, self._status
  end

  -- The narrowing path. No process, no query, no debounce.
  --
  -- _narrowable is the condition that is easy to miss and was missed. The other three ask
  -- whether the text merely grew over an identical population, and they are all satisfied by
  -- the RECENT list too, since its shape is the empty query and any typed text grows from
  -- that. But a recent list is files touched in the last few days, not a superset of anything,
  -- so narrowing against it silently answers every search from that small set and a real
  -- search never runs. That is exactly how a live run came back with zero rows for a file the
  -- headless run had found. So only a published search result is ever narrowed against.
  if prev and self._narrowable and self._parsedShape
    and query.narrows(self._parsedShape, parsed) and not self._truncated then
    if self._debounce then self._debounce.cancel() end
    self._debounce = nil
    self:_redraw(parsed, nil)
    return self._display, self._status
  end

  -- Otherwise dispatch, after the debounce. The handle is held and the previous one
  -- cancelled, because an unreferenced timer can be collected before it fires and the
  -- search would then simply never happen, with nothing logged and nothing to find.
  if self._debounce then self._debounce.cancel() end
  self._debounce = util.after(self.limits.debounceMs / 1000, function()
    self._debounce = nil
    self:_dispatch(parsed)
  end)

  return self._display, self._status
end

--- engine:rows() -> the current display rows, for a caller redrawing after onResults.
function obj:rows()
  return self._display
end

--- engine:status() -> short text describing why the list looks the way it does, or nil.
function obj:status()
  return self._status
end

--- engine:parsed() -> the current parse, so a surface can describe the active filters
--- without parsing the query a second time.
function obj:parsed()
  return self._parsed
end

--- engine:browseQueryFor(row) -> a query string that browses into this row
--- An absolute path with a trailing slash, which the scope resolver takes literally. So
--- walking into a directory found by a search needs no new concept, it is the same scope
--- grammar the user could have typed.
function obj:browseQueryFor(row)
  if not row or not row.path then return nil end
  if not row.isDir then return nil end
  return row.path:gsub("/+$", "") .. "/"
end

--- engine:cancel() - abandon everything in flight, called when the surface closes.
function obj:cancel()
  if self._debounce then self._debounce.cancel() end
  self._debounce = nil
  self:_cancelInflight()
  self._gen = self._gen + 1
  return self
end

return obj
