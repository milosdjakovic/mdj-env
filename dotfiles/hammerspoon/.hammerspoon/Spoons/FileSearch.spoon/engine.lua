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
  --
  -- THREE INSTANCES OF THE SAME HAZARD NOW, so it is worth stating as a rule rather than as
  -- three notes. The composition root and this engine are literally the same table, so a public
  -- field here can silently overwrite something the root hung on itself, and the other way
  -- around. The third was a ranker injected as `frecency`, which wiped the root's own frecency
  -- module the moment configure ran and left it looking like the module had no methods. Anything
  -- injected into the engine therefore lands on an underscored field, and anything the root
  -- exposes to the outside keeps the plain name.
  self.matcher = nil
  self.onResults = nil

  self._parsed = nil
  self._retained = {}
  self._truncated = false
  self._display = {}
  self._status = nil
  self._gen = 0
  self._debounce = nil
  -- Two channels, so two handles. A typed search and the background recent files fetch run
  -- concurrently by design, and one shared slot is what made starting either one abandon the
  -- other. Holding each handle is also what keeps its search reachable, see the source contract.
  self._activeHandle = nil
  self._recentsHandle = nil
  self._recents = nil
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
--- opts.ranker     a preference over paths, answering score(path) and top(n). Optional, and
---                 without it every ordering here is exactly what it was before, which is a
---                 file date or a text score. Called a ranker rather than named for what
---                 backs it, because the engine does not care where a preference came from,
---                 and kept on a private field because the composition root that injects it
---                 IS this same table, so a public name here would overwrite the root's own
--- opts.onResults  called with no arguments whenever rows changed underneath the caller,
---                 so the surface can redraw. The engine never touches a chooser itself
function obj:configure(opts)
  opts = opts or {}
  self.types = opts.types or {}
  self.roots = opts.roots or {}
  self.prune = opts.prune or {}
  self.matcher = opts.matcher
  self._ranker = opts.ranker
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
      -- An alias value may be relative to home, absolute, or written with a tilde. Joining
      -- every value under home was a defect rather than a limitation, since the config has
      -- always documented the absolute form. A value of `/Applications` became
      -- `~//Applications`, which fails on most machines and, on one that happens to hold a home
      -- Applications folder, resolves and quietly answers with the wrong directory.
      local base = home
      if mapped ~= "" then
        base = util.expandHome(mapped)
        if base:sub(1, 1) ~= "/" then base = home .. "/" .. base end
      end
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
--
-- The haystack is the row's FOLDED path, never the raw one. The shared words matcher folds
-- only the query and compares the haystack verbatim, by design, since it is built for long
-- clipboard bodies that must not be refolded per keystroke. Handing it a raw path made every
-- uppercase query match nothing, and it looked like a broken search rather than a broken
-- filter, because typing the same text in one go dispatched instead and found the file.
function obj:_filter(rows, parsed)
  if parsed.text == "" then return rows end
  local matcher = self.matcher
  local out = {}
  for i = 1, #rows do
    local r = rows[i]
    local hay = r.lower or (r.path or ""):lower()
    local keep
    if type(matcher) == "function" then
      keep = matcher(parsed.text, hay) ~= nil
    else
      keep = allWordsIn(hay, parsed.words)
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
---
--- What you use adds a fourth question, and it is deliberately the WEAKEST of the four. The
--- bump saturates below the gap between the name match tiers, so a file you open daily is
--- floated above others that matched the query just as well, and never above one that matched
--- it better. That asymmetry is the whole point. Here the query is the strong signal and your
--- habits break the ties, while in the list you see before typing there is no query at all, so
--- there your habits are the only signal and they choose the rows outright.
function obj:_order(rows, parsed)
  if parsed.kind ~= "search" or parsed.text == "" then return rows end
  local text = parsed.text:lower()
  local weight = self._ranker and (self.limits.frecencyWeight or 0) or 0
  local scored = {}
  for i = 1, #rows do
    local r = rows[i]
    local name = (r.name or ""):lower()
    local s = 0
    if name:find(text, 1, true) then s = s + 1000 end
    if allWordsIn(name, parsed.words) then s = s + 500 end
    if r.isDir then s = s + 50 end
    s = s - math.min(#(r.path or ""), 500) / 25
    if weight > 0 then
      -- Saturating rather than linear, so one heavily used file cannot run away with the
      -- ranking however many times it has been opened. Two uses is already most of the bump.
      local used = self._ranker.score(r.path)
      if used > 0 then s = s + weight * (used / (used + 2)) end
    end
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
---
--- The directory ITSELF counts as noise, not only what lives in it. Matching only an inner
--- segment left the folder standing while everything under it went, so a __pycache__ row sat in
--- the recent list with its own contents filtered out from under it, which reads as a filter that
--- half works. A name in that list is a name nobody searches for, in either position.
function obj:_denoise(rows, parsed)
  if parsed.ignored or parsed.scope then return rows end
  if #self.prune == 0 then return rows end
  local out = {}
  for i = 1, #rows do
    local path = rows[i].path or ""
    local noisy = false
    for _, name in ipairs(self.prune) do
      if path:find("/" .. name .. "/", 1, true) or path:sub(-#name - 1) == "/" .. name then
        noisy = true
        break
      end
    end
    if not noisy then out[#out + 1] = rows[i] end
  end
  return out
end

-- Float what you use to the top of the list you land on before typing anything.
--
-- REORDERING WOULD NOT BE ENOUGH HERE, which is the thing worth understanding. That list is a
-- date bound capped at a few dozen rows, so a file you open every day but have not modified in
-- a month is not in the candidate set at all and no amount of sorting will surface it. So this
-- merges rather than sorts, and it is the one place in the spoon where a row appears that no
-- source returned.
--
-- It is BOUNDED on purpose, a few rows and then the dates. Letting it fill the page would turn
-- the default view into the same ten things forever, which is the opposite of what that view is
-- for, since right after a download or a build is exactly when this picker gets opened and a
-- file that did not exist a minute ago has no history to rank. So the two answers share the
-- list, habits first and then what just changed.
--
-- A path that the date list already returned is MOVED rather than rebuilt, so it keeps the size
-- and the modification date Spotlight handed over for free. Only a row that would otherwise be
-- absent is built here, and that one is stat'd so it reads the same as its neighbours rather
-- than being the one row with no age beside it. At a few rows per open that cost is nothing.
function obj:_float(rows)
  local n = self.limits.recentFloat or 0
  if n <= 0 or not self._ranker then return rows end
  local top = self._ranker.top(n)
  if #top == 0 then return rows end

  local byPath = {}
  for _, r in ipairs(rows) do byPath[r.path] = r end

  local out, seen = {}, {}
  for _, path in ipairs(top) do
    if not seen[path] then
      seen[path] = true
      local row = byPath[path]
      if not row then
        local attrs = hs.fs.attributes(path) or {}
        row = util.row(path, {
          isDir = attrs.mode == "directory",
          size = attrs.size,
          modified = attrs.modification,
          source = "frecency",
        })
      end
      out[#out + 1] = row
    end
  end
  for _, r in ipairs(rows) do
    if not seen[r.path] then out[#out + 1] = r end
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

-- Abandons the TYPED search only, and the recent files fetch is deliberately left running.
-- It answers a different question, what you touched lately rather than what you asked for, so
-- nothing a query does can invalidate it, and letting it land means the next open has the list
-- already. It used to be cancelled here, and since a cancelled search never calls back, the
-- pending flag stayed set and no later open ever fetched again, so the picker showed a loading
-- row and nothing else for the rest of the process.
function obj:_cancelInflight()
  if self._activeHandle then
    pcall(function() self._activeHandle.cancel() end)
  end
  self._activeHandle = nil
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

  self:_redraw(parsed, "searching")

  local ctx = {
    scopePath = scopePath,
    cap = self.limits.retainCap,
    timeoutSeconds = self.limits.timeoutSeconds,
    limits = self.limits,
  }

  self._activeHandle = src.search(parsed, ctx, function(rows, reason)
    if gen ~= self._gen then return end
    self._activeHandle = nil
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
-- since what you touched lately does not change while a picker is open. Refetched on each open
-- while the previous list stays on screen, so only the very first open of a session ever shows
-- a loading row.
--
-- The handle IS the in flight flag, one field rather than a separate boolean saying the same
-- thing, and that matters because the boolean it replaced could wedge. It was set before the
-- fetch and cleared only by the callback, so anything that abandoned the fetch left it set
-- forever with no handle behind it, and every later open returned here immediately and fetched
-- nothing. Holding the handle is also what keeps the fetch reachable, so a second open cannot
-- overwrite a live one and let it be collected mid flight.
function obj:_fetchRecents()
  if self._recentsHandle then return end
  local parsed = query.parse("", self.types)
  local src = self:_sourceFor(parsed)
  if not src then return end
  local ctx = {
    scopePath = nil,
    cap = self.limits.recentCount,
    timeoutSeconds = self.limits.timeoutSeconds,
    limits = self.limits,
  }
  self._recentsHandle = src.search(parsed, ctx, function(rows)
    self._recentsHandle = nil
    -- Filtered before it is merged, and in that order for a reason. This list fills itself in
    -- without going through _publish, so it was the one result set the noise filter never saw,
    -- and the view everyone lands on could open on a __pycache__ directory and two .pyc files
    -- inside it, all three named by the prune list. Nothing else in the spoon had that hole,
    -- because everything else publishes.
    --
    -- Filtering first and floating second is what lets your own history override the filter. A
    -- pruned path you deliberately used still comes back, since it is added by name rather than
    -- surviving the filter, and the date half of the list stays clean.
    rows = self:_denoise(rows or {}, parsed)
    -- Merged once here rather than on every redraw, so the list cannot reorder itself under
    -- someone who is reading it, and the stat calls happen once per open.
    self._recents = self:_float(rows)
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

--- engine:upQuery() -> a query browsing the parent of the current scope, or nil
--- The counterpart of browseQueryFor, and the same idea. Going back up is expressed as a
--- scope the user could have typed, so nothing needs a history stack or a notion of where
--- the picker has been. It is nil with no scope, since there is nowhere above a search of
--- everywhere, and nil at the root.
---
--- It resolves the scope on demand rather than reading a field the dispatch filled in, so it
--- is right even when the key is pressed before the listing has come back.
---
--- Home is collapsed back to a tilde because this lands in the query field where it is read,
--- and climbing a few levels otherwise fills the field with the same twenty characters of home
--- prefix on every step. The resolver expands a tilde before anything else, so what goes out is
--- exactly what can come back in, and nothing else has to know.
function obj:upQuery()
  local parsed = self._parsed
  if not parsed or not parsed.scope then return nil end
  local here = self:_resolveScope(parsed.scope)
  if not here or here == "/" then return nil end
  local parent = here:match("^(.*)/[^/]+$")
  if not parent or parent == "" then return "/" end
  local home = os.getenv("HOME") or ""
  if home ~= "" and parent:sub(1, #home) == home then
    parent = "~" .. parent:sub(#home + 1)
  end
  return parent .. "/"
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
