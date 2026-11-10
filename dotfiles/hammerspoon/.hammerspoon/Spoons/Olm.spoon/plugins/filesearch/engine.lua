--- File search engine, the Context.
---
--- It owns the behaviour and talks only through the source contract, naming no backend.
--- Give it a raw query string and it answers with rows to draw right now, arranging for
--- whatever it does not yet know to arrive later. Everything about WHERE files come from
--- lives in the sources, and everything about WHICH source answers a given query shape
--- lives in the order the composition root registered them.
---
--- THE ONE IDEA WORTH KNOWING is that a search costs one round trip per pause in typing rather
--- than one per keystroke. Typing eleven characters quickly fires one query, because the
--- debounce waits for the typing to stop. Meanwhile a longer text over the same population shows
--- the rows already held, ranked again by the shared search, and the round trip after the pause
--- replaces them. There is no result cache, since a cache would be wrong at the exact moment the
--- tool is used, right after something was downloaded or built.
---
--- Until 2026-11-09 a longer text over the held rows asked nothing at all, on the belief that it
--- could only match a subset of them. That holds for a substring and not for the shared search,
--- where a word of four letters gains one typo and a word of three matches inside a word, so a
--- longer word can match a name a shorter one did not. heelo typed slowly held only what hee had
--- found and never showed HelloWorld.jsp, while heelo typed quickly did. So the held rows are only
--- what shows while the answer is on its way, and the answer always comes.
---
--- Everything expensive happens elsewhere. The walk and the index helper run as separate
--- processes and call back. What is left
--- here is parsing and deciding which rows to hand over, all of which are microseconds. That
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
  retainCap = 2000,
  minChars = 1,
  timeoutSeconds = 5,
  recentCount = 40,
  recentDays = 14,
  indexMaxAgeSeconds = 300,
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
  self.onResults = nil

  self._parsed = nil
  self._retained = {}
  self._truncated = false
  self._holding = false
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
  self._recentDates = nil
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
--- opts.ranker     a preference over paths, answering score(path) and top(n). Optional, and
---                 without it no path is preferred, the list you land on is ordered by date
---                 and a typed query by the shared search alone. Called a ranker rather than
---                 named for what
---                 backs it, because the engine does not care where a preference came from,
---                 and kept on a private field because the composition root that injects it
---                 IS this same table, so a public name here would overwrite the root's own
--- opts.onResults  called with no arguments whenever rows changed underneath the caller,
---                 so the surface can redraw. The engine never touches a chooser itself
--- opts.keeps      keeps(row, text) -> whether the shared search keeps this row for this free
---                 text. Optional, and without it the held rows go in the order the source gave
---                 and an answer is never called empty. The engine decides nothing by matching
---                 with it, it only prefers what the search will keep when the retain cap cuts,
---                 and says no matches when a round trip brought back none of those
function obj:configure(opts)
  opts = opts or {}
  self.types = opts.types or {}
  self.roots = opts.roots or {}
  self.prune = opts.prune or {}
  self._ranker = opts.ranker
  self._keeps = opts.keeps
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
-- What the shared search is told
--------------------------------------------------------------------------------

-- The engine filters and orders nothing by match since phase three of the unified search on
-- 2026-10-17. It hands every held row to the chooser, the shared search ranks them by the text
-- searchTextFor answers, and what shows between round trips is that same ranking over the held
-- rows, so what a query keeps is decided in one place, and every query is answered by a round
-- trip whether it was typed quickly or slowly. Until then _filter dropped held rows by the injected words matcher over the
-- folded full path, and _order scored a search by the name holding the text whole, then every
-- word, then a shorter path, with frecency added under the gaps between those tiers.

--- engine:searchTextFor(raw) -> the free text of a query, what the shared search ranks by.
--- The grammar stays here, so `.js ~/dev/ foo` ranks by foo, and a query with no free text, a
--- browse, a bare type or the recent list, answers empty, which keeps the order rows arrive in.
function obj:searchTextFor(raw)
  return query.parse(raw or "", self.types).text
end

--- engine:preference(path) -> how much you use a path, from zero to one, the row's bonus.
--- It orders only rows the shared search calls equally good, so a file you open daily leads
--- others that matched as well and never one that matched better, which is the same asymmetry
--- the old ordering kept by holding its weight under the gaps between its tiers. Saturating
--- rather than linear, so one heavily used file cannot run away with it, and two uses is already
--- half of it.
function obj:preference(path)
  if not self._ranker or not path then return 0 end
  local used = self._ranker.score(path) or 0
  if used <= 0 then return 0 end
  return used / (used + 2)
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
-- list, the files you have used first, in whatever order the ranker's top answers, and then what
-- just changed.
--
-- A path that the date list already returned is MOVED rather than rebuilt, so it keeps the size
-- and the modification date the index handed over for free. Only a row that would otherwise be
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

-- The rows the shared search will keep for this free text first, then the rest, each part in
-- the order the source gave, and how many it keeps. A source asks more loosely than the search
-- keeps, the index helper a word inside a word that the search wants at a word start, so a
-- source's own order can put rows the search drops ahead of rows it keeps, and the retain cap
-- below would then hold the first and lose the second. The kept count
-- is what tells a round trip that brought back only dropped rows from one that found nothing.
-- With no keeps, or no free text, nothing is preferred and every row counts as kept.
function obj:_keptFirst(rows, parsed)
  local keeps = self._keeps
  local text = parsed and parsed.text or ""
  if type(keeps) ~= "function" or text == "" then return rows, #rows end
  local kept, rest = {}, {}
  for i = 1, #rows do
    local ok, yes = pcall(keeps, rows[i], text)
    if ok and yes then kept[#kept + 1] = rows[i] else rest[#rest + 1] = rows[i] end
  end
  local n = #kept
  for i = 1, #rest do kept[#kept + 1] = rest[i] end
  return kept, n
end

-- Publish a result set. Keeps the retained copy, shown while the next round trip is on its way,
-- and notes whether it was truncated, against what the source returned rather than what
-- survived the noise filter.
--
-- A round trip that brought back rows the shared search keeps none of says nothing found, the
-- same status an empty answer gets, since the list would otherwise show a bare empty field
-- after a real answer.
function obj:_publish(rows, parsed, status)
  local retainCap = self.limits.retainCap
  self._truncated = #rows >= retainCap
  -- A real search result, which refresh asks again when the index under it changes.
  self._narrowable = true
  rows = self:_denoise(rows, parsed)
  local keptCount
  rows, keptCount = self:_keptFirst(rows, parsed)
  if status == nil and #rows > 0 and keptCount == 0 then status = "nothing found" end
  local retained = rows
  if #retained > retainCap then
    local cut = {}
    for i = 1, retainCap do cut[i] = retained[i] end
    retained = cut
  end
  self._retained = retained
  self._parsedShape = parsed
  self._holding = false
  self:_redraw(parsed, status)
end

-- Hand over what is retained, without any dispatch. Every held row goes, unfiltered and in the
-- order its source gave, and the shared search ranks them by the query and keeps the
-- presentation's rowLimit after ranking. The display cap that once cut this list to two hundred
-- here cut before any ranking, so the rows it kept were the source's first rather than the best.
-- While a round trip for a query of another shape is pending, the held rows answer a different
-- question and are not handed over at all, see rowsFor.
function obj:_redraw(_, status)
  self._display = self._holding and {} or self._retained
  self._status = status
  if self.onResults then self.onResults() end
  for _, fn in ipairs(self._watchers or {}) do pcall(fn) end
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
    self._retained, self._parsedShape, self._truncated, self._holding = {}, parsed, false, false
    self:_redraw(parsed, "no such directory")
    return
  end

  local src = self:_sourceFor(parsed)
  if not src then
    self._retained, self._parsedShape, self._truncated, self._holding = {}, parsed, false, false
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
  self._holding = false
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
    -- The date half alone, before the float, which is what the shadow compares, since each side
    -- floats from a history of its own, docs/DESIGN-APP-FRECENCY.md.
    self._recentDates = rows
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
      -- _publish, so it clears this too, or refresh would ask again for a search no longer shown.
      self._narrowable = false
      self._holding = false
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
--- Two outcomes. A query too short or too broad to be worth a round trip shows the recent list.
--- Anything else arms the debounce and says searching at once. When the new query asks about the
--- held population, query.sameShape, the held rows stay until the answer lands, because clearing
--- them first makes a picker flicker for no gain, and the shared search ranks them by the new
--- text meanwhile. They are files of that population matching what is typed, a truthful partial
--- answer, which is also why a backspace or an edit keeps them. When it asks about another
--- population, a scope, a type or a sigil changed, the held rows answer a different question,
--- and ranked by the new text they looked like answers, foo.js from ~/dev on top while
--- ~/Downloads .pdf foo was being searched. So then only the pinned searching status shows until
--- the answer lands.
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
    self._holding = false
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
    self._holding = false
    self:_redraw(parsed, "keep typing")
    return self._display, self._status
  end

  -- Every other query is asked, after the debounce. Over the population already held, a longer
  -- text, a backspace or an edit, the held rows stay on screen and the shared search ranks them by
  -- the new text until the answer lands, see the header for why they are never the answer.
  --
  -- Otherwise dispatch, after the debounce. The handle is held and the previous one
  -- cancelled, because an unreferenced timer can be collected before it fires and the
  -- search would then simply never happen, with nothing logged and nothing to find.
  if self._debounce then self._debounce.cancel() end
  self._debounce = util.after(self.limits.debounceMs / 1000, function()
    self._debounce = nil
    self:_dispatch(parsed)
  end)
  self._holding = not (self._parsedShape and query.sameShape(self._parsedShape, parsed))
  self._display = self._holding and {} or self._retained
  self._status = "searching"

  return self._display, self._status
end

--- engine:refresh()
--- Answer the open session again, after the data under it changed. The recent list is fetched
--- afresh and stays on screen until the new one lands, and a published search is dispatched again.
--- Nothing happens without a session, and a list showing recents or asking for more typing has
--- nothing to dispatch, so only those two are refreshed.
function obj:refresh()
  if not (self._recents or self._recentsHandle) then return end
  if self._recentsHandle then
    pcall(function() self._recentsHandle.cancel() end)
    self._recentsHandle = nil
  end
  self:_fetchRecents()
  if self._parsed and self._narrowable then self:_dispatch(self._parsed) end
end

--- engine:watch(fn) - fn is called with nothing after every change of the rows or the status,
--- for a reader beside the picker, the root's comparison with Olm.app among them. Each one is
--- kept for the life of the engine, and one that raises does not stop the others.
function obj:watch(fn)
  if type(fn) ~= "function" then return self end
  self._watchers = self._watchers or {}
  self._watchers[#self._watchers + 1] = fn
  return self
end

--- engine:held() -> { query, status, items }, what the list holds now as the shared search reads
--- it. items are the rows in their source's order, each searched by its file name as the list's
--- own rows are, chooser.searchName, and keyed by its path, without the bonus a person's use adds,
--- since that is the one part of the order the history decides rather than the query. The recent
--- list is handed as the dates gave it, before the float, for the same reason, step 1.4d.
function obj:held()
  local name = obj.chooser and obj.chooser.searchName or function(r) return r.name or r.path end
  local items = {}
  local display = self._display or {}
  if self._recentDates and display == self._recents then display = self._recentDates end
  for _, r in ipairs(display) do
    local title = name(r)
    items[#items + 1] = { title = title, filterText = title, key = r.path, item = r }
  end
  return { query = self._parsed and self._parsed.raw or "", status = self._status, items = items }
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
