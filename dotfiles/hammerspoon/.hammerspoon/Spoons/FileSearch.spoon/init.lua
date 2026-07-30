--- === FileSearch ===
---
--- Find a file and do something with it. Type a name and it searches everywhere, put a slash
--- after a folder and it searches or browses inside it, put a dot in front of a token and it
--- filters by type, and a dot on its own reaches the files macOS refuses to index.
---
--- This file is the composition root of the spoon, and only this. It loads the pieces, names
--- the concrete sources, sets the order that settles which one answers, hands each source the
--- slice of policy it needs, and returns the assembled spoon.
---   query.lua       the pure grammar, no Hammerspoon in it at all
---   engine.lua      the Context, owns debounce, narrowing, ordering and dispatch
---   contract.lua    the interface every source must implement
---   util.lua        the shellout runner, the held timer, and row building
---   frecency.lua    what you actually use, the one ordering that is not a date or a text score
---   chooser.lua     the list surface, pure policy over the engine's api
---   sources/*.lua   the concrete backends, one self contained file each
---
--- THE SOURCE ORDER IS THE WHOLE CONFLICT RESOLUTION and it is not a preference. Each source
--- answers whether it supports a query shape and the first one that says yes owns it, so the
--- order below is the only place that decides who wins when two could answer.
---
--- Walk is first because a named directory beats everything else. Measured, walking Downloads
--- took 13 milliseconds where the index takes about 105, and the walk also sees dotfiles the
--- index does not hold at all. So a scope going anywhere but here would be both slower and less
--- complete, which makes this the one ordering decision with two independent reasons.
---
--- Hidden is second, and it claims only what is left that Spotlight physically cannot answer,
--- an unscoped search asking for paths with a dot segment. Putting it first would steal every
--- scoped hidden query from the walk, which would answer them from a cache that can be minutes
--- stale when the live filesystem was right there.
---
--- Spotlight is last and claims everything else, which is most searches. Last is correct
--- because it is the only source with no precondition, so anything earlier would never be
--- reached if this came first.
---
--- Adding a backend is a new file in sources/ plus two lines here, the registration and its
--- policy slice, with no edit to the engine.

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(spoonPath .. name)
  if not chunk then
    error("FileSearch: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end

local obj = load("engine.lua")

-- Inject the contract the engine validates the source list against.
obj._contract = load("contract.lua")

-- The grammar, exposed so a caller can parse a query without going through a search. Nothing
-- outside needs it today, and it is here because it is the one piece of this spoon that is
-- worth reading on its own.
obj.query = load("query.lua")

-- Register the concrete sources. This table is by name for readability and the ordered list
-- below is what the engine actually receives, since order is the decision, see the note above.
obj.sources = {
  walk = load("sources/walk.lua"),
  hidden = load("sources/hidden.lua"),
  spotlight = load("sources/spotlight.lua"),
}
obj._defaultSources = { obj.sources.walk, obj.sources.hidden, obj.sources.spotlight }

-- What you actually use. Exposed so it can be inspected or cleared from the console, since it is
-- the one part of this spoon that accumulates state about the person using it.
obj.frecency = load("frecency.lua")

-- The list surface. It reaches the engine only through the api built in configure below, so it
-- never learns that sources exist.
obj.chooser = load("chooser.lua")

--- FileSearch:configure(opts)
--- Method
--- opts.policy   the pure data from config/filesearch.lua
--- opts.sources  an ordered source list, overriding the default order above
--- opts.deps     the per consumer dependency adapter from the root, the only way a source
---               here learns where its CLI lives
--- opts.matcher  the shared matching strategy, used for the local narrow between round trips
---
--- Wraps the engine's own configure so this file stays the only place that knows both which
--- sources exist and which part of the policy each one reads. The engine is handed only what it
--- uses itself and never forwards opaque config it cannot read.
local configureEngine = obj.configure
function obj:configure(opts)
  opts = opts or {}
  local policy = opts.policy or {}
  local deps = opts.deps
  local limits = policy.limits or {}

  -- One combined prune list per consumer. The general package noise and the names that are
  -- specific to one machine are separate in config on purpose, since they are edited for
  -- different reasons, and they are joined here because no source cares about the distinction.
  local prune = {}
  for _, name in ipairs(policy.prune or {}) do prune[#prune + 1] = name end
  for _, name in ipairs(policy.pruneLocal or {}) do prune[#prune + 1] = name end

  local function toolPath(name)
    return deps and deps.path(name) or nil
  end

  obj.sources.walk.configure({
    path = toolPath("fd"),
    prune = prune,
  })

  obj.sources.hidden.configure({
    fdPath = toolPath("fd"),
    fzfPath = toolPath("fzf"),
    prune = policy.prune,
    pruneLocal = policy.pruneLocal,
    maxAgeSeconds = limits.hiddenMaxAgeSeconds,
  })

  obj.sources.spotlight.configure({
    prune = prune,
    limits = limits,
  })

  -- The settings key is named HERE rather than inside frecency.lua, so the one piece of global
  -- state this spoon owns is visible from the root like every other concretion. The store lives
  -- in the user defaults deliberately, since it is written on every action and anything inside
  -- ~/.hammerspoon would reload the whole config each time a file was opened.
  obj.frecency.configure({
    key = "fileSearchFrecency",
    halfLifeDays = limits.frecencyHalfLifeDays,
    maxEntries = limits.frecencyMaxEntries,
  })

  configureEngine(self, {
    types = policy.types,
    roots = policy.roots,
    prune = prune,
    limits = limits,
    sources = opts.sources or obj._defaultSources,
    contract = obj._contract,
    matcher = opts.matcher,
    -- The engine ranks and does not care where a preference came from, so it takes the two verbs
    -- it needs and never learns that a store exists. Drop this line and every ordering goes back
    -- to being a file date or a text score, which is what it was before.
    ranker = {
      score = function(path) return obj.frecency.score(path) end,
      top = function(n) return obj.frecency.top(n) end,
    },
    -- The engine never touches a picker. It reports that rows changed and the surface decides
    -- what to do about it, which is what lets a second surface reuse the engine unchanged.
    onResults = function() obj.chooser.refresh() end,
  })

  -- The api the list surface talks through. A handful of verbs and nothing else, so the surface
  -- cannot reach a source, cannot reorder the sources, and cannot learn what an index is.
  obj.chooser.configure({
    api = {
      rowsFor = function(q) return obj:rowsFor(q) end,
      -- Walking a directory tree is two verbs, one down and one up, and both answer with a query
      -- string rather than performing a move. So the surface only ever sets the field, and there
      -- is no second notion of where the picker is that could disagree with what is typed.
      upQuery = function() return obj:upQuery() end,
      -- Read only, so the surface can tell a browse from a search without parsing the query a
      -- second time. It is what decides whether the back row is drawn.
      parsed = function() return obj:parsed() end,
      reset = function()
        obj:reset()
        -- Warming the hidden index belongs here rather than in the engine, because it names one
        -- concrete source and the engine names none. It puts the index in the page cache while
        -- the user is still reading the recent list, measured at 240 milliseconds cold against
        -- 6 warm, and rebuilds it instead when it is missing or stale.
        obj.sources.hidden.warm()
      end,
      cancel = function() obj:cancel() end,
      browseQueryFor = function(row) return obj:browseQueryFor(row) end,
    },
    -- Doing anything to a row is what teaches the ranking. The surface reports the path and
    -- learns nothing about what happens to it, the same seam as the injected clipboard write.
    onUse = function(path) obj.frecency.note(path) end,
    -- The other half of that seam, so a row can report the use it just recorded. Still no
    -- concrete name on the surface, only a question it is allowed to ask.
    usedAt = function(path) return obj.frecency.usedAt(path) end,
  })

  return self
end

return obj
