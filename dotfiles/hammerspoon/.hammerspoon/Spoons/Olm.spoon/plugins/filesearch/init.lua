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
---   thumbs.lua      pictures of files, a chain of generators behind the docked pane
---   sources/*.lua   the concrete search backends, one self contained file each
---   viewers/*.lua   the concrete preview providers, one self contained file each
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
---
--- This is the olm side copy of FileSearch, landed whole in phase six of the build plan
--- behind a root toggle. It is a faithful copy, every sibling file unchanged, since every
--- path in this spoon resolves through debug.getinfo off its own file rather than through
--- hs.loadSpoon mechanics, so loading this copy by dofile changes nothing it depends on.
--- The original this was copied from still lives at Spoons/FileSearch.spoon.

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

--- FileSearch.PreviewProvider
--- Constant
--- How the highlighted file is shown. Two implementations of one contract, so which one is in
--- use is a choice the composition root makes and nothing else in the spoon knows the answer.
---
--- `SidePanel` docks a canvas beside the list and follows the highlight, a permanent summary in
--- the corner of your eye. `QuickLook` opens the native panel over the picker when a key asks
--- for it, a full size preview of anything the system can render, and reserves no room at all.
--- The difference is not only how they draw but WHEN, which is why the contract carries
--- `followsHighlight` and why they cannot simply be swapped without the surface noticing.
---
--- QuickLook belongs in the peek seat instead, reached through `opts.peekProvider` on configure.
--- It never follows the highlight, so naming it here as `previewProvider` still wins the docked
--- seat and yields no preview at all, with no console line saying why.
---
--- The members are the modules themselves rather than names, so a caller writes
--- `PreviewProvider.SidePanel` and no string for a provider appears at any call site. A mistyped
--- member raises here instead of silently reading as nil and leaving the picker with no preview
--- and no explanation, which is as close to an enum as a structural language gets.
obj.PreviewProvider = setmetatable({
  SidePanel = load("viewers/sidepanel.lua"),
  QuickLook = load("viewers/quicklook.lua"),
}, {
  __index = function(_, key)
    error("FileSearch.PreviewProvider has no member " .. tostring(key), 2)
  end,
  __newindex = function()
    error("FileSearch.PreviewProvider is a constant", 2)
  end,
})

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
--- opts.onResults  optional, told when the rows changed, for a surface other than this spoon's
---                 own picker. Composed with the picker's redraw rather than replacing it
--- opts.previewProvider  a member of FileSearch.PreviewProvider, defaulting to SidePanel. The
---                 root names it by reference rather than by string, see the enum above.
---                 QuickLook here still wins the docked seat and yields no preview at all,
---                 since it never follows the highlight, so it belongs on opts.peekProvider
---                 below instead
--- opts.peekProvider  a member of FileSearch.PreviewProvider, or nil for none, the seam a key
---                 asks for rather than the one that follows the highlight. Kept apart from
---                 previewProvider above because the two answer different callers and either
---                 can be QuickLook, SidePanel, or absent without the other changing
---
--- Wraps the engine's own configure so this file stays the only place that knows both which
--- sources exist and which part of the policy each one reads. The engine is handed only what it
--- uses itself and never forwards opaque config it cannot read.
-- The chosen provider first and the side panel behind it, deduplicated, since a chain of one is
-- what asking for the side panel means. Named here because this is the spoon's composition root
-- and the surface must not learn that a second provider exists.
local function previewChain(chosen)
  local first = chosen or obj.PreviewProvider.SidePanel
  if first == obj.PreviewProvider.SidePanel then return { first } end
  return { first, obj.PreviewProvider.SidePanel }
end

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
    -- Where an unscoped search starts from. This is the one source that answers a query naming
    -- no folder, so it is the only one the list means anything to.
    searchAlso = policy.searchAlso,
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
    --
    -- A second surface says so through opts.onResults and is COMPOSED here rather than replacing
    -- this, because the spoon's own picker must keep painting whoever else is listening. Each
    -- surface's redraw already does nothing when it is not on screen, so both being told costs
    -- one dead call.
    onResults = function()
      obj.chooser.refresh()
      if opts.onResults then opts.onResults() end
    end,
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
      -- For a surface with no open of its own, which must not restart a session it is only
      -- joining. The warm goes with it, since it is the same beginning either way and doing it
      -- twice is free.
      ensureSession = function()
        obj:ensureSession()
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
    -- The preview slice of the policy, forwarded whole rather than picked apart here. The
    -- surface owns the provider and the thumbnail chain, so it is the layer that knows which of
    -- these numbers belongs to which, and this root stays the only place that reads the config.
    preview = policy.preview,
    -- The provider, and the side panel behind it as the fallback, which is what turns an
    -- unavailable first choice into a working picker with a console line rather than into no
    -- preview at all. This is the only place in the spoon that names a concrete one, and it
    -- names them by reference so no provider string exists anywhere.
    viewers = previewChain(opts.previewProvider),
    -- The seam a key asks for, passed straight through with no chain and no fallback behind it,
    -- since asking for nothing when it steps aside is the right answer and there is no second
    -- provider here to hand the key to instead. Nil is a valid answer too, meaning the root
    -- wants no peek seam at all, and the key it would have earned drops out on its own.
    peekProvider = opts.peekProvider,
  })

  return self
end

return obj
