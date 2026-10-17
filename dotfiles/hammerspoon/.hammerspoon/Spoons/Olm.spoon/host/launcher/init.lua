--- === Launcher ===
---
--- A filterable app switcher and command runner, the built-in Hyper+Space launcher.
---
--- This is a coordinator. It combines several plain spoons into one feature and
--- owns real state, the app scan caches and an hs.application.watcher, so it is a
--- spoon of its own rather than inline wiring in the composition root. It never
--- names a domain spoon. The root injects every collaborator through configure,
--- the stage it presents into, the pure keys and apps data, a glyph resolver, the
--- shared predicate registry, the tool registry from phase seven of the build plan,
--- the rows other plugins contribute and the runners that take them back, and a
--- small dispatch of leaf actions that close over core alone. So the launcher owns
--- the row building, the matching, the app enumeration, and the command dispatch
--- structure, and knows nothing about what a row ultimately does or which plugin
--- it came from.
---
--- The Command pattern is preserved. Each row carries only a serializable
--- descriptor, its kind plus a name or bundle id, and the owner identity of a row a
--- plugin contributed, never a function, because the Chooser hands each row to
--- hs.chooser which serialises it and would drop a function. runItem turns that
--- descriptor back into the injected call, the owner's runner first.
---
--- Since the chooser stage build's phase two, this host owns no chooser instance of its own.
--- It builds one presentation, a plain table of policy, and hands it to host/stage, the one
--- host owning the single live instance every tool presents into, so its own show is a
--- present into that stage, its hide and refresh and its navigation surface are the stage's
--- own. Its rows supplier, its dispatcher, its intercept routing, its page mechanism, and its
--- recency all stay exactly here, unchanged, the stage only owns the window they show in.
---
--- This is the olm side copy of Launcher, made in the host into olm pass on 2026-08-07, and
--- the original this was copied from lived at Spoons/Launcher.spoon.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Launcher"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("Launcher", "info")

-- Injected via configure
obj._stage = nil            -- host/stage, the one host owning the live chooser instance
obj._placeholder = nil
obj._placeholderExamples = nil  -- example field hints, one per computed row source that proposes one
obj._keys = nil
obj._appDetails = nil       -- function() -> bundle id to { chord, description, url }, see _buildConfiguredApps
obj._glyphFor = nil         -- function(key, mods) -> chord glyph string
obj._rowSuppliers = nil     -- functions answering contributed rows, owner already stamped
obj._runners = nil          -- owner identity -> function(item), runs a chosen contributed row
obj._predicates = nil       -- shared predicate registry, for `when` gating
obj._actions = nil          -- leaf dispatch, app, copy, special, rowIntercept, scope
obj._queryProviders = nil   -- ordered query row sources, each answering rows(query)
obj._aliasHint = nil        -- function(name) -> subtitle fragment, "" when there is none
obj._registry = nil         -- the tool registry, dot called, optional, see configure and _runItem
obj._iconOwner = nil        -- the identity this host's own manifest icons are declared under

-- Owned state
obj._presentation = nil     -- this host's one presentation, handed to the stage, never rebuilt
obj._placeholders = nil     -- the rotation pool, this host's own placeholder first
obj._placeholderLast = nil  -- the previous open's own pick, never repeated immediately
obj._surface = nil          -- the stage's own nav adapter, delegated to rather than built here
obj._actionRows = nil
obj._installedApps = nil         -- the disk scan, cached until a watched app directory changes
obj._appRowsCache = nil          -- app rows only, invalidated on running-set change, activation, or a directory change
obj._orderedRowsCache = nil      -- all rows, recency-sorted, invalidated on any promote or a directory change
obj._appRowsWatcher = nil
obj._appDirWatchers = nil        -- hs.pathwatcher list, one per watched app directory
obj._warmTimer = nil             -- the debounced disk scan warm up, see _warmAppScan
obj._chordWarned = nil           -- one shot flag, so a missing chord speller warns once, at the first open
obj._mru = nil              -- most-recently-used item keys, front is most recent
obj._assoc = nil            -- the query association store, what each typed query has come to mean
obj._matcher = nil          -- the shared fuzzy strategy, since this host scores its own rows now
obj._rank = nil             -- the one rank engine, lib/chooser/rank.lua, handed over by the root
obj._ranking = nil          -- the two numbers the association store is built with
obj._selfKey = nil          -- our own app key, never promoted
obj._page = nil             -- an opaque query prefix while somebody else's list is hosted

-- App enumeration roots and the depth guard against a symlink-looped tree.
local APP_DIRS = {
  "/Applications",
  "/System/Applications",
  os.getenv("HOME") .. "/Applications",
}
local APP_SCAN_MAX_DEPTH = 4

-- Unified recency ordering. Every row kind shares one most recently used
-- timeline, keyed by a kind qualified item key, see recencyKey, so the last
-- thing picked through the launcher bubbles to the top whether it was an app
-- or a command. The timeline is fed by launcher picks alone, on the user's
-- decision of 2026-08-07, a chooser selection or a row taken through the
-- intercept below. The app watcher further down stays only to refresh the
-- running set, it feeds nothing into this timeline any more.
-- Persisted under one hs.settings key so it survives a reload (frequent here) and
-- a reboot, and capped so it stays small. The key is new (was app-only bundle ids
-- under "launcherAppMRU"), so old data is ignored and the order relearns at once.
local MRU_SETTINGS_KEY = "launcherRecency"
local MRU_MAX = 50
-- Where the query associations persist, separate from the timeline above because they answer
-- a different question. The timeline says what was picked last, which is what an untouched
-- list opens on. This says what a particular query has come to mean, which is what orders the
-- list once something has been typed, and the two are wanted at different moments.
local ASSOC_SETTINGS_KEY = "launcherQueryAssoc"
-- How close to the best match a row must score before what was picked before is allowed to
-- decide, as a proportion of that best score rather than a number of points, since the score
-- grows with every character typed. See _rankCatalog for the measurements this sits between.
-- Overridable through the ranking defaults beside the other two numbers.
local DEFAULT_NEARNESS = 0.9
-- Our own activations must not reorder the list, else opening the launcher would
-- float Hammerspoon to the top instead of the app the user was just in.
local SELF_BUNDLE = hs.processInfo and hs.processInfo.bundleID

-- The recency key for a row's serializable descriptor, qualified by kind so an app
-- and a command never collide. Returns nil for a missing item, which sorts as unused.
local function recencyKey(item)
  if not item then return nil end
  -- A computed row is a different thing from a command. It exists only for the query that
  -- produced it, so it has no identity to remember and returning nil keeps it out of the
  -- timeline entirely. Without this every result would share one key and float to the top
  -- of an empty launcher, which is the last thing a fresh open should show.
  -- A scoped row is the same case for the same reason. It belongs to the tool the query
  -- named and exists only for that query, so remembering it would float a stale answer to
  -- the top of the next fresh open.
  if item.kind == "calc" or item.kind == "scope" then return nil end
  -- A row whose owner says it has no identity worth remembering, the same case a third time.
  -- The owner decides, since only it knows whether a row was computed from what was typed, a
  -- window size being the shipped example, and this host must not guess from the fields a
  -- row of somebody else's happens to carry.
  if item.remember == false then return nil end
  -- An app is this host's own kind, keyed by its bundle id.
  if item.kind == "app" then return "app:" .. tostring(item.bundleID) end
  -- Every other row is its kind joined to its identifying string, `key` when the row states
  -- one and its name otherwise, so a plugin decides what identifies its own row. A System
  -- Settings pane states its url as the key, which is exactly the key this host used to build
  -- for it by name, so no pick persisted before is forgotten.
  return item.kind .. ":" .. tostring(item.key or item.name)
end

--- Launcher:init()
--- Method
--- Initialize the spoon.
function obj:init()
  self._mru = {}
  self._selfKey = SELF_BUNDLE and ("app:" .. SELF_BUNDLE) or nil
  return self
end

--- Launcher:_promote(key)
--- Method
--- Move an item to the front of the shared recency list, persist, and drop the
--- ordered-rows cache so the next open re-sorts. Ignores our own app so opening
--- the launcher never reorders the list, and a nil key (an item with no
--- descriptor) is a no-op.
function obj:_promote(key)
  if not key or key == self._selfKey then return end
  local mru = self._mru
  for i, k in ipairs(mru) do
    if k == key then table.remove(mru, i); break end
  end
  table.insert(mru, 1, key)
  while #mru > MRU_MAX do table.remove(mru) end
  hs.settings.set(MRU_SETTINGS_KEY, mru)
  self._orderedRowsCache = nil
end

--- Launcher:configure(opts)
--- Method
--- Configure with every injected collaborator. See the field list above.
function obj:configure(opts)
  opts = opts or {}
  self._stage = opts.stage
  self._placeholder = opts.placeholder or "Search apps and commands"
  -- One example field hint per computed row source that proposes one, in the order the root
  -- assembled the sources themselves, so a source that computes rows from what is typed can
  -- say so in the empty field rather than being findable only by a person who already knows
  -- it exists. This host names none of them and reads none of their manifests, it receives
  -- whatever arrived and rotates it.
  --
  -- Kept rather than overwritten when a later call arrives without one, for the reason the
  -- chord speller below already documents, this host is configured twice and only the root's
  -- own call can compute this.
  self._placeholderExamples = opts.placeholderExamples or self._placeholderExamples
  -- What an app row shows beyond the app, its chord and the url it opens, answered by whichever
  -- plugins supply launcher app details and merged by the root. This host read the person's
  -- toggle list and app registry itself until the core split finished, which made a core host
  -- know one plugin's data and its shape. It shows what it is given now and never learns where
  -- it came from. Kept rather than overwritten when a later call arrives without one, for the
  -- reason the chord speller below documents, this host is configured twice.
  self._appDetails = opts.appDetails or self._appDetails
  -- The display name for each leader role, so a row's subtitle can say which physical key
  -- opens it without this file deciding what any leader is called. The word Hyper used to be
  -- written into every one of those subtitles literally, which was correct only for as long as
  -- nobody moved a tool to the other leader. Every role is here, the window leader's too, so a
  -- contributed row names its leader by role and reads the same word the hint bar prints.
  self._leaderNames = opts.leaderNames or {}
  -- The rows other plugins add to this catalog, one supplier per contributing plugin in the
  -- order the root's set answer put them, and the runners that take a chosen row back. Each
  -- supplier answers plain descriptors with its owner already stamped on every item, so this
  -- host routes a row by that one word and never learns which plugin it came from. See
  -- _buildActionRows for how they are placed and _runItem for how they run.
  self._rowSuppliers = opts.rowSuppliers or {}
  self._runners = opts.runners or {}
  -- This host's own rows that answer to no registration, declared rather than written out,
  -- and the place they take among the contributed rows, this host's own defaults.launcherOrder.
  -- Kept rather than overwritten when a later call arrives without one, for the reason the
  -- chord speller below documents, this host is configured twice.
  self._specialRows = opts.specialRows or {}
  self._launcherOrder = opts.launcherOrder or self._launcherOrder
  self._glyphFor = opts.glyphFor or function(key) return tostring(key) end
  -- The shared chord speller, held as data rather than wrapped in a method of its own, so a
  -- row states the exact same words the docked hint bar and the action panel already agree
  -- on. There is deliberately no fallback function, since inventing one would be a second
  -- speller rather than the shared one, which is the whole defect this closed.
  --
  -- Kept rather than overwritten when a later call arrives without one, because this host is
  -- configured twice, once by the generic wiring stage and once by the composition root with
  -- the values only it can compute. Written as a plain assignment the first of those two
  -- silently erased the speller whenever it happened to run second, which is a landmine
  -- rather than a bug today only because of the order those two stages happen to run in.
  self._chordLabel = opts.chordLabel or self._chordLabel
  -- The two numbers the association store is built with, and the store itself. Built here
  -- rather than by lib/services.lua, whose per plugin instance is keyed to a field literally
  -- named recency, and building it in the consumer also means the dry gate and the live root
  -- hand this host the same thing, the raw module, rather than one shape each.
  --
  -- Kept rather than rebuilt, for the reason the chord speller above documents. This host is
  -- configured twice and only the generic wiring stage carries a lib grant, so a plain
  -- assignment would throw the store away whenever the root's own call happened to run second.
  self._ranking = opts.ranking or self._ranking or {}
  if not self._assoc and opts.queryassoc then
    self._assoc = opts.queryassoc.new({
      settingsKey = ASSOC_SETTINGS_KEY,
      decay = self._ranking.decay,
      margin = self._ranking.margin,
    })
  end
  -- The shared matching strategy. This host has always been handed one and never read it,
  -- because the chooser atom underneath did the scoring itself. It scores its own rows now,
  -- see _rankCatalog, so this is the function that does it, and the same keep rather than
  -- overwrite rule applies since only the generic stage supplies it.
  self._matcher = opts.matcher or self._matcher
  -- The one rank engine the catalog scores and sorts through, kept rather than overwritten for
  -- the same reason, since only the root's own call hands it over.
  self._rank = opts.rank or self._rank
  self._predicates = opts.predicates or {}
  self._actions = opts.actions or {}
  -- The tool registry, phase seven of the build plan. Optional, and a launcher configured
  -- without one dispatches a special row through actions.special alone, exactly as it did
  -- before the registry existed, since a host that hard requires one cannot be tested
  -- without one. See _runItem for the two places a special row is now looked up.
  self._registry = opts.registry
  -- Query row sources, in the order their rows should appear. Each is any table
  -- answering rows(query), so the launcher composes them without knowing what any of
  -- them computes, and the root decides which exist. An empty list is the whole
  -- feature switched off, which is how a source whose tool is missing disappears.
  self._queryProviders = opts.queryProviders or {}
  -- What a row says about being reachable by a typed word. One question asked per row while
  -- the rows are built, so this file states no alias anywhere and a tool that gains one needs
  -- no edit here. The default answers nothing, which is the whole feature absent rather than
  -- broken. See _buildActionRows for why it is asked there and not at each call site.
  self._aliasHint = opts.aliasHint or function() return "" end
  -- The identity the launcher's own manifest icons are declared under, which the rows this host
  -- states itself read their keys against, lock and sleep and the three catalog scopes. A
  -- registered tool's row reads against the tool's own name instead, and a contributed row
  -- against its owner.
  self._iconOwner = opts.iconOwner or "launcher"

  self._placeholders = self:_buildPlaceholders()

  -- The one presentation this host hands the stage, built once here and reused for the life
  -- of this spoon, never rebuilt, mirroring decision one of the stage design brief that the
  -- instance behind it is never rebuilt either. Every function below is exactly what used to
  -- go straight into Chooser.new's own config in this same place. The row still runs
  -- deferred, after the chooser tears down and macOS restores focus to the app that was
  -- frontmost before the launcher opened, since a window action acts on
  -- hs.window.focusedWindow(). What is gone is the docked shortcut panel triple, onPositioned,
  -- onActivity, and onClose, which this host no longer passes anywhere. The stage owns that
  -- triple now as fixed, atom level policy rather than something a presentation carries, and
  -- the composition root hands it this host's own panel directly when it configures the
  -- stage, before the stage is ever handed to this host.
  self._presentation = {
    name = "launcher",
    -- The opening value only. Every show replaces this field before handing the table to the
    -- stage, see _nextPlaceholder, so what a person actually reads is whichever hint this
    -- open's random pick landed on.
    placeholder = self._placeholder,
    rows = function(query) return self:_commandRows(query) end,
    onSelect = function(item)
      if item then
        -- Promote now, on the true "user chose this row" moment, so the order
        -- persists at once even though a kind that acts on the world still defers its own
        -- run below. Any kind counts.
        self:_promote(recencyKey(item))
        self:_noteAssociation(item)
        -- _runItem is called straight, not deferred here any more. Decision four of the
        -- handoff brief, the deferral moves inside the dispatcher's own branches, since a
        -- presenting tool's row never reaches onSelect at all, decision two, it completes
        -- through intercept above and stage.push, and the kinds that do still reach here,
        -- an owned row its owner runs, app, calc, scope, and an unmigrated special, are
        -- the only ones that still genuinely need to wait for focus to return before acting,
        -- so each of those branches now owns its own wait rather than one wrapper owning it
        -- for a switch it cannot see inside.
        self:_runItem(item)
      end
    end,
    -- Whether a row means this list becomes another list rather than being taken, asked by the
    -- stage before it lets a row close, routed straight through to the atom underneath exactly
    -- as it always reached the atom directly. The launcher only routes the question, exactly as
    -- it routes running a row and peeking at one, so it still learns nothing about what a scope
    -- or a tool is. Whoever answers acts through the two public doors below, seedQuery and
    -- enterPage.
    --
    -- Promoting happens HERE and not in _replacementFor, because the stage calls this closure
    -- only when a row is actually being taken while the shortcut hint asks _replacementFor on
    -- every highlight move to decide what to call the key. Taking a row that replaces the list
    -- is still using the thing it points at, so it belongs in the shared recency order exactly
    -- as running it did, and it lands under the same key running it produced. A row with no
    -- identity to remember, which is every row a scope computed, answers nil to recencyKey and
    -- so stays out of the timeline as it always has.
    intercept = function(item)
      local replace = self:_replacementFor(item)
      if not replace then return false end
      replace()
      self:_promote(recencyKey(item))
      self:_noteAssociation(item)
      return true
    end,
    -- Backspace on an empty field, which is how you leave a hosted list. The stage asks only
    -- when the presentation below declines, and the atom underneath only asks the stage at
    -- all when there is nothing to delete, so this never competes with ordinary editing.
    back = function() return self:leavePage() end,
    -- The same verb name the tools' own pickers answer, carried on the presentation rather
    -- than the formal contract's own nine fields since it is UI surface rather than chooser
    -- policy, so one routed action reaches whichever list is open and this one needs no case
    -- of its own in the root. See host/stage's own surface, which delegates it to whichever
    -- presentation is current when one answers it.
    peekPreview = function() self:peekSelected() end,
    -- The atom does no scoring and no sorting for this list. _commandRows below hands back
    -- rows already filtered and already in their final order, because the order depends on
    -- something the atom cannot see, what this query has come to mean. Left to the atom, the
    -- text score decides outright and the arrival order it falls back to for a tie never gets
    -- a chance, since two rows matching equally well still differ by hundredths of a point
    -- over incidental things like how long their subtitle happens to be.
    --
    -- This is the presentation's own field and not the manifest's. The manifest states which
    -- STRATEGY to inject and this host wants the shared one, so its surface names no matcher
    -- and receives the real function on opts. Writing false there instead would inject
    -- nothing and leave this host with no way to score anything at all, which is the exact
    -- trap that once degraded BrowserTabs to an unranked list.
    matcher = false,
  }

  -- The stage's own nav adapter, scoped to this presentation's own name rather than the
  -- shared, unscoped one. Phase two pointed this at self._stage.surface directly, which
  -- answers isShowing for the window itself, correct only because the launcher was the one
  -- presentation there was. Now that VPN presents too, host/stage's own surfaceFor is what
  -- keeps j, k, and every other routed key reaching whichever presentation is actually on
  -- screen rather than whichever one is earliest in plan.order, review finding ten.
  self._surface = self._stage and self._stage:surfaceFor(self._presentation.name) or nil

  return self
end

--- Launcher:_chordSuffix(category, leader, key, mods)
--- Method
--- A row's subtitle tail. The bare category is what a row with no configured chord already
--- reads as, so that is exactly what this falls back to when no chord speller was injected.
--- Otherwise the category joined to the chord by the shared middot.
function obj:_chordSuffix(category, leader, key, mods)
  if not self._chordLabel then return category end
  return category .. " · " .. self._chordLabel(leader, key, mods)
end

--- Launcher:_leaderName(role)
--- Method
--- What to call one leader role in a row subtitle. A role is a word like app or window that a
--- manifest uses to say which leader a tool opens on, and what that role is called on this
--- machine is the composition root's answer since it owns the catalog. No role at all means
--- the app leader, so this reads the catalog's own name for that role too rather than a
--- literal word kept here, which is what let this file keep saying Hyper after the app leader
--- itself moved to another physical key. The literal is the answer only when the catalog has
--- nothing for that role either.
function obj:_leaderName(role)
  if not role then return self._leaderNames.app or "Hyper" end
  return self._leaderNames[role] or tostring(role)
end

--- Launcher:_ensureStaticRows()
--- Method
--- Build the rows that do not change between opens, once, on first use rather than at
--- configure. The app rows are already lazy because their running state changes, and these are
--- lazy for a different reason, they ask questions of collaborators the root may not have
--- finished wiring when this spoon is configured. The alias hint is exactly that case, the
--- resolver behind it is configured after this spoon because it adapts tools wired later, so a
--- row built at configure time would ask too early and print nothing forever.
---
--- Waiting until the first open also means the answers are current rather than as of load,
--- which is what a hint has to be once the words behind it can change while Hammerspoon runs.
--- The cost lands on the first open, next to the app scan that is already lazy there and far
--- larger, and every open after it is served from the cache.
function obj:_ensureStaticRows()
  if self._actionRows then return end
  self._actionRows = self:_buildActionRows()
end

--- Launcher:_buildActionRows() -> rows
--- Method
--- The static action rows, the registry's first and then every contributed and declared row
--- in its declared order. Each is { title, subTitle, image, item, when? } where item is a
--- serializable descriptor for the dispatcher.
function obj:_buildActionRows()
  local rows = {}
  -- keywords is hidden text the matcher sees and the row does not show, the same field
  -- the injected rows already carry. It exists so a row can answer to a word its title
  -- and subtitle have no room for, rather than that word being padded into the visible
  -- subtitle where it would cost a reader something to buy a searcher something.
  local function add(title, subTitle, item, icon, when, keywords, subTitleFn, image, owner)
    -- A tool reachable by typing a word says so on its own row, and it says it here rather
    -- than at each call site. That is the difference between a hint a row can be forgotten
    -- from, which is how file search ended up advertising nothing, and one that cannot be,
    -- so giving a tool an alias now takes no edit in this file at all.
    --
    -- The row is asked about by its own descriptor name, which is that tool's key in the pure
    -- data, so there is one identity behind the row, the scope, and the hint instead of three
    -- strings that have to agree. Only a special row can be a tool, so nothing else is asked,
    -- which also means an action sharing a name with a scope cannot pick up a hint that was
    -- never about it. The usual answer is empty.
    -- A row a plugin contributed carries its owner and is never asked, since its name is that
    -- plugin's own word and a registered tool or a scope sharing it must not lend it a hint.
    -- What the row answers to beyond its name, the declared search terms of the shared search,
    -- lib/chooser/rank.lua. keywords arrives as a string or a list, and the alias hint joins it
    -- since the words it names are words this row is reached by.
    local terms = {}
    if type(keywords) == "table" then
      for _, k in ipairs(keywords) do terms[#terms + 1] = k end
    elseif type(keywords) == "string" then
      terms[1] = keywords
    end
    if item and item.kind == "special" and item.owner == nil then
      local hint = self._aliasHint(item.name)
      subTitle = (subTitle or "") .. hint
      if hint ~= "" then terms[#terms + 1] = hint end
    end
    -- An image handed in outright wins over the drawn icon, the one caller today being
    -- a registered tool whose row declares the bundle it fronts, so the row wears the
    -- real application icon the way the app rows below already do.
    --
    -- Otherwise the row names its icon and its owner and draws nothing. The rows are cached
    -- across shows, so a picture drawn here would keep the colour of the half the system was in
    -- when the cache was built, and the chooser draws the icon at paint instead. An action row
    -- has no app icon of its own, so the owner defaults to this host.
    rows[#rows + 1] = { title = title, subTitle = subTitle, image = image,
                        icon = image == nil and icon or nil,
                        iconOwner = image == nil and icon ~= nil and (owner or self._iconOwner) or nil,
                        item = item, when = when, keywords = terms, subTitleFn = subTitleFn }
  end
  -- addTool(name) asks the injected registry for this name's row and, when there is one,
  -- builds it exactly as the thirteen hand written calls this replaced built theirs,
  -- reading the description and the chord out of self._keys under the row's keysName or
  -- the name itself. Doing nothing when the registry has no row for that name, whether
  -- because nothing registered under it or because rowFor already answers nil for an
  -- inactive tool and every command it owns, is what will make an inactive tool's row
  -- disappear once the activation list finally means that, and that case is legitimate
  -- silence rather than a mistake.
  --
  -- A missing keys entry is not that. Eight of the thirteen calls this replaced were
  -- already guarded with an if keys.X check and stayed silent about it, but the other
  -- five, colorPicker, emoji, caffeinate, vpn, and clipboard, indexed straight into keys
  -- and would have raised at config load if the entry were ever missing, which is loud.
  -- A row declared for a name whose keys entry does not exist is a mistake in every one
  -- of the thirteen cases, somebody described how a row should look for a tool with
  -- nothing to build it from, so this logs one warning naming the tool and the keys name
  -- it looked for, then skips the row exactly as the silent five now would without it.
  -- That gives every one of the thirteen the same non fatal outcome, loudly, rather than
  -- the mixed loud and quiet failure the calls it replaced actually had.
  --
  -- This file still names no tool. It reads a name handed to it and the keys entry that
  -- name points at, and everything about how that name's row looks, its category, its
  -- icon, its detail or its chord, now lives on the descriptor rather than here.
  --
  -- The one addTool line per tool this once needed is gone, the registry loop below asks for
  -- every row, and the capture and window loops that sat beside it are gone too, since phase
  -- three of the core split, those rows arriving from their own plugins through the row
  -- suppliers further down.
  -- tool is the registered tool the row belongs to, which is its own name for a tool's row and
  -- the owning tool for a command's, and it is the owner a row's icon key is read against.
  local function addTool(name, tool)
    local row = self._registry and self._registry.rowFor(name)
    if not row then return end
    -- A row with no description names nothing a person could read, which is a defect in
    -- whichever manifest declared it rather than a state to draw badly, so it is named and
    -- skipped. Everything else a row needs it already carries, since the descriptor is now
    -- built from the plugin's own manifest merged with whatever the root overrode.
    if not row.description then
      log.w(string.format("Launcher skipped the row for '%s', its registration carries no description", name))
      return
    end
    -- A detail may arrive as a function rather than a string, the registrar having resolved
    -- a member spec the manifest declared, for a row whose subtitle depends on the world at
    -- open time. Such a row still bakes a static subtitle through the branches below, the
    -- answer shown whenever the live one declines, and carries a closure the per keystroke
    -- copy reads through _rowSubTitle, so these cached rows stay built once while their text
    -- stays honest per open.
    local detailFn = type(row.detail) == "function" and row.detail or nil
    local subTitle
    if row.detail and not detailFn then
      subTitle = row.category .. " · " .. row.detail
    elseif row.chord then
      -- A global combination rather than a leader chord, so the subtitle spells the whole
      -- thing out and names no leader, which is the only way it reads correctly.
      subTitle = row.category .. " · " .. self._glyphFor(row.key, row.mods)
    elseif row.key then
      subTitle = self:_chordSuffix(row.category, self:_leaderName(row.leader), row.key)
    else
      -- No chord at all, which is ordinary. Several tools open from this list and nowhere
      -- else, so the subtitle carries only what kind of thing they are.
      subTitle = row.category
    end
    local subTitleFn
    if detailFn then
      -- The alias hint is appended here exactly as add appends it to the static subtitle,
      -- since a live subtitle replacing the static one must not cost the row its typed word.
      local category, hint = row.category, self._aliasHint(name)
      subTitleFn = function()
        local d = detailFn()
        if type(d) == "string" and d ~= "" then
          return category .. " · " .. d .. hint
        end
        return nil
      end
    end
    -- A row declaring the bundle it fronts wears that application's real icon, resolved
    -- here once per cache build rather than per keystroke, with the icon standing in
    -- whenever the bundle resolves to nothing on this machine.
    local image = row.bundle and hs.image.imageFromAppBundle(row.bundle) or nil
    -- Only the declared keywords are searched beside the name, and the alias words add() puts
    -- with them. The category word and the chord name a kind of thing and a key, and do inside
    -- Window listed every window command. The description is prose, and searching it made
    -- set list Wi-Fi through "see the current network" and the list six tools.
    local terms = {}
    if row.keywords then terms[#terms + 1] = row.keywords end
    add(row.description, subTitle, { kind = "special", name = name },
      row.icon, nil, terms, subTitleFn, image, tool or name)
  end
  -- One row per registered tool, and one per registered command, asked of the registry in the
  -- order it holds rather than listed here by hand. This is what the thirteen addTool calls
  -- that used to sit here became, and it is the difference between a tool joining this list by
  -- being registered and a tool joining it by somebody remembering to add a line. The file's
  -- own note above said this was the last thing keeping a roster here, and this is it going.
  --
  -- Nothing is named. A tool that is not registered, or is registered and switched off, simply
  -- is not in the answer, which is also how deactivating one takes its row away without a
  -- second place having to agree.
  for _, entry in ipairs(self._registry and self._registry.listing() or {}) do
    addTool(entry.name, entry.tool)
  end

  -- Rows other plugins contribute, and this host's own declared rows beside them. A contributed
  -- row is plain data its plugin built from its own bindings or its own data, carrying its
  -- title, an icon key read against its owner, and either a finished subTitle or a group and a
  -- chord this host spells, so every chord in the list is spelled by the one shared speller.
  -- The owner is already on the item, stamped by the root, and it is what _runItem routes by.
  --
  -- THE ORDER, which is what a person sees scrolling an untouched list. Every row carries a
  -- number, `order`, declared rather than derived. A contributed row has its own when it states
  -- one and its plugin's defaults.launcherOrder otherwise, stamped by the root, and this host's
  -- own rows take this host's own launcherOrder. Rows sort by that number, a row with none
  -- after every numbered one, and a tie keeps the suppliers in the set's own stable order, then
  -- each supplier's rows in the order it answered them, then this host's rows last. So the place
  -- of a row is a number its owner wrote down and a person may move, and nothing here reads a
  -- kind word or a plugin name to decide it. The shipped numbers reproduce the order the list
  -- has always had, docs/PLUGIN-CONTRACT.md lists them.
  --
  -- A supplier that raises is dropped with a log line rather than costing the list every
  -- other row, the same rule a query row source lives under.
  local entries = {}
  local seen = {}
  local function push(entry)
    entry.seq = #entries + 1
    entries[#entries + 1] = entry
  end
  for _, supplier in ipairs(self._rowSuppliers or {}) do
    local ok, answered = pcall(supplier)
    if not ok then
      log.w("Launcher dropped a row supplier that raised, " .. tostring(answered))
    else
      for _, r in ipairs(answered or {}) do
        if type(r) == "table" and type(r.item) == "table" and r.title then
          -- Two plugins answering one kind and one identifying string would share a recency
          -- key and run whichever owner the row happened to carry, so the collision is named
          -- once, at build, with both owners, rather than discovered as a pick that floats the
          -- wrong row.
          local id = tostring(r.item.kind) .. ":" .. tostring(r.item.key or r.item.name or r.item.url)
          local first = seen[id]
          if first and first ~= r.item.owner then
            log.w(string.format("Launcher found two rows answering '%s', from '%s' and '%s'",
              id, tostring(first), tostring(r.item.owner)))
          elseif not first then
            seen[id] = r.item.owner
          end
          push({ contributed = r, order = r.order })
        end
      end
    end
  end
  for _, r in ipairs(self._specialRows or {}) do
    push({ own = r, order = self._launcherOrder })
  end
  table.sort(entries, function(a, b)
    if (a.order ~= nil) ~= (b.order ~= nil) then return a.order ~= nil end
    if a.order ~= nil and a.order ~= b.order then return a.order < b.order end
    return a.seq < b.seq
  end)

  -- The subtitle a contributed row shows. A finished one is taken as it stands, otherwise the
  -- group word joined to the chord, otherwise the group word alone, which is what a row with no
  -- key reads as everywhere else in this list.
  local function contributedSubTitle(r)
    if r.subTitle then return r.subTitle end
    if r.group and type(r.chord) == "table" and r.chord.key then
      return self:_chordSuffix(r.group, self:_leaderName(r.chord.leader), r.chord.key, r.chord.mods)
    end
    return r.group
  end

  for _, entry in ipairs(entries) do
    if entry.own then
      local r = entry.own
      local subTitle = r.subTitle
      if not subTitle and r.category and r.key then
        subTitle = self:_chordSuffix(r.category, self:_leaderName(r.leader), r.key)
      end
      add(r.description, subTitle, { kind = "special", name = r.name }, r.icon, nil, r.keywords)
    else
      local r = entry.contributed
      add(r.title, contributedSubTitle(r), r.item, r.icon, r.when, r.keywords, nil, nil,
        r.iconOwner or r.item.owner)
    end
  end
  return rows
end

--- Launcher:_buildConfiguredApps()
--- Method
--- What each app row shows beyond the app, keyed by bundle id, so a row can name the chord that
--- brings the app forward and open the url its supplier states. Asked of the injected answer
--- every time the app rows are built rather than once at configure, since a supplier knows what
--- it bound only after its own wiring step, and the rows are rebuilt only when the running set
--- changes. Which chord wins when two bindings name one app is the supplier's business, this
--- host shows the one entry it is handed. With nothing injected every row carries no chord.
function obj:_buildConfiguredApps()
  if type(self._appDetails) ~= "function" then return {} end
  local ok, details = pcall(self._appDetails)
  if not ok then
    log.w("the launcher app details raised, so no app row names a chord, " .. tostring(details))
    return {}
  end
  return type(details) == "table" and details or {}
end

-- Walk the standard app roots recursively so an app nested in a vendor subfolder
-- is found, but stop descending at every .app so the helper bundles inside an app
-- never leak in. Resolves each bundle id, name, and icon, deduped by bundle id.
local function scanAppDir(dir, depth, byId)
  if depth > APP_SCAN_MAX_DEPTH then return end
  -- hs.fs.dir raises on an unreadable directory, so guard the whole walk of it.
  local ok, iterFn, dirObj = pcall(hs.fs.dir, dir)
  if not ok or not iterFn then return end
  for entry in iterFn, dirObj do
    if entry:sub(1, 1) ~= "." then -- skips ".", "..", and hidden entries
      local path = dir .. "/" .. entry
      if entry:sub(-4) == ".app" then
        local info = hs.application.infoForBundlePath(path)
        local bundleID = info and info.CFBundleIdentifier
        if bundleID and not byId[bundleID] then
          byId[bundleID] = {
            name = hs.application.nameForBundleID(bundleID) or entry:sub(1, -5),
            bundleID = bundleID,
            icon = hs.image.imageFromAppBundle(bundleID),
          }
        end
        -- Deliberately do not descend: the .app is the leaf.
      elseif hs.fs.attributes(path, "mode") == "directory" then
        scanAppDir(path, depth + 1, byId)
      end
    end
  end
end
local function scanInstalledApps()
  local byId = {}
  for _, dir in ipairs(APP_DIRS) do
    if hs.fs.attributes(dir, "mode") == "directory" then
      scanAppDir(dir, 1, byId)
    end
  end
  return byId
end

--- Launcher:_appRows()
--- Method
--- The live app rows, every installed app plus any running app not on disk in the
--- scanned dirs, marked open when running. This is the app portion in its natural
--- order only, open apps first then alphabetical; the recency interleaving across
--- all row kinds happens once in _orderedRows. The disk scan is cached, and the
--- assembled rows are cached too, rebuilt when the running set changes, so the
--- recency re-sort on a selection never rescans apps. start installs its own
--- directory watchers that drop the disk scan cache too, so installing or
--- removing an app rescans on the next open rather than waiting for a reload.
function obj:_appRows()
  if self._appRowsCache then return self._appRowsCache end
  self._installedApps = self._installedApps or scanInstalledApps()
  local byId = {}
  for bundleID, a in pairs(self._installedApps) do
    byId[bundleID] = { name = a.name, bundleID = bundleID, icon = a.icon, running = false }
  end
  for _, app in ipairs(hs.application.runningApplications()) do
    local bundleID = app:bundleID()
    if bundleID then
      local e = byId[bundleID]
      if e then
        e.running = true
      elseif app:kind() == 1 then
        byId[bundleID] = { name = app:name() or bundleID, bundleID = bundleID, icon = hs.image.imageFromAppBundle(bundleID), running = true }
      end
    end
  end
  local list = {}
  for _, e in pairs(byId) do list[#list + 1] = e end
  -- Natural order only: open apps first, then alphabetical. Recency is applied
  -- across every row kind together in _orderedRows, not here.
  table.sort(list, function(x, y)
    if x.running ~= y.running then return x.running end -- open apps first
    return (x.name or ""):lower() < (y.name or ""):lower()
  end)

  local configured = self:_buildConfiguredApps()
  local rows = {}
  for _, e in ipairs(list) do
    local cfg = configured[e.bundleID]
    local chord = cfg and type(cfg.chord) == "table" and cfg.chord.key ~= nil and cfg.chord or nil
    local status = e.running and "Open" or "Not running"
    local subTitle = status
    if chord and chord.leader == nil then
      -- A literal combo on no leader never appears on a cheat sheet, so this row is its only
      -- discoverability surface, and it names its own chord and description rather than a
      -- leader's name, which would describe a modal it was never bound into.
      local glyphs = self._glyphFor and self._glyphFor(chord.key, chord.mods) or chord.key
      subTitle = status .. " · " .. glyphs .. (cfg.description and (" " .. cfg.description) or "")
    elseif chord then
      subTitle = status .. " · " .. self:_leaderName(chord.leader) .. " " .. tostring(chord.key)
    end
    rows[#rows + 1] = {
      title = e.name,
      subTitle = subTitle,
      image = e.icon,
      -- A stable key so the atom encodes each app icon once and reuses it across opens.
      iconKey = "app:" .. e.bundleID,
      item = { kind = "app", bundleID = e.bundleID, url = cfg and cfg.url },
    }
  end
  self._appRowsCache = rows
  return rows
end

--- Launcher:_orderedRows()
--- Method
--- Every row of every kind in one list, ordered by the shared recency timeline.
--- The natural order is apps (open first, then alphabetical) then the curated
--- action rows in their declared order. Each row carries that position as _n. A
--- row used before, of any kind, carries its recency rank as _rank. The sort puts
--- every used row above every unused one, used rows most-recent first, and unused
--- rows in their natural order, so the last thing used sits on top while an
--- untouched list keeps its sensible curated shape. Cached, rebuilt on any promote
--- (a selection or an app activation) or a running-set change.
function obj:_orderedRows()
  if self._orderedRowsCache then return self._orderedRowsCache end
  self:_ensureStaticRows()
  local rank = {}
  for i, k in ipairs(self._mru or {}) do rank[k] = i end
  local rows = {}
  local n = 0
  local function push(row)
    n = n + 1
    row._n = n
    row._rank = rank[recencyKey(row.item)]
    rows[#rows + 1] = row
  end
  for _, row in ipairs(self:_appRows()) do push(row) end
  for _, row in ipairs(self._actionRows) do push(row) end
  table.sort(rows, function(x, y)
    if (x._rank ~= nil) ~= (y._rank ~= nil) then return x._rank ~= nil end -- used before unused
    if x._rank and y._rank then return x._rank < y._rank end               -- more recent first
    return x._n < y._n                                                     -- natural order otherwise
  end)
  self._orderedRowsCache = rows
  return rows
end

--- Launcher:_queryRows(query)
--- Method
--- The rows the injected query sources compute from what was typed, in source order and
--- ahead of everything else. A source answers rows(query) and returns an empty list when
--- the query means nothing to it, which is the usual case, so this costs a handful of
--- cheap calls per keystroke and no work at all on an empty field.
---
--- A source returns an icon or an image, and an icon is drawn by the chooser at paint through
--- the one resolver, so a source never draws anything and there is one icon cache rather than
--- one per source. A source is fully trusted for its own rows but not
--- for the launcher's stability, so a source that raises is dropped for that keystroke
--- with a log line rather than emptying the whole list.
---
--- A source may also claim the query, returning true as a second value, which means these
--- rows are the whole list and the launcher's own catalog is not shown at all. That is how a
--- typed word can hand the list to one tool. A claim discards whatever earlier sources
--- contributed and stops the loop, so a claimed query means exactly one thing however the
--- root ordered the sources. The launcher learns nothing beyond the claim itself, neither
--- what made the source claim it nor what the rows now belong to.
function obj:_queryRows(query)
  if not query or query == "" then return {}, false end
  local out = {}
  for _, provider in ipairs(self._queryProviders) do
    local ok, rows, exclusive = pcall(function() return provider:rows(query) end)
    if not ok then
      hs.printf("Launcher: a query source failed, %s", tostring(rows))
    else
      if exclusive then out = {} end
      for _, r in ipairs(rows or {}) do
        out[#out + 1] = {
          title = r.title,
          subTitle = r.subTitle,
          image = r.image,
          icon = r.image == nil and r.icon or nil,
          iconOwner = r.image == nil and r.icon ~= nil and (r.iconOwner or self._iconOwner) or nil,
          enabled = r.enabled,
          item = r.item,
          filterText = r.filterText or query,
        }
      end
      if exclusive then return out, true end
    end
  end
  return out, false
end

--- Launcher:_rowSubTitle(row)
--- Method
--- The subtitle one cached row shows right now. Almost every row answers its baked string.
--- A row carrying a live closure, built in addTool from a registry detail that resolved to
--- a function, is asked fresh instead, and falls back to the baked string when the closure
--- declines or raises, so a broken plugin answer costs that one row its hint rather than
--- costing the launcher its list. The plugin behind the closure caches per open, so this
--- being read on every keystroke stays a table lookup rather than repeated work.
function obj:_rowSubTitle(row)
  if not row.subTitleFn then return row.subTitle end
  local ok, live = pcall(row.subTitleFn)
  if ok and type(live) == "string" then return live end
  return row.subTitle
end

--- Launcher:_commandRows(query)
--- Method
--- The row supplier. Any rows the query sources computed lead, then the full
--- recency-ordered list, and the atom's shared matcher filters and ranks what follows,
--- exposing the visible text plus any hidden keywords as filterText so a settings pane is
--- still found by a synonym its name lacks. On the empty query the atom keeps the recency
--- order untouched, and when the user types, match quality leads with recency breaking
--- ties. Gated rows drop out live through the shared predicate registry the window
--- bindings use.
---
--- A computed row sets filterText to the raw query, so the matcher scores it against what
--- was typed rather than against the answer it produced, which is what keeps a result at
--- the top of the list instead of being dropped for not resembling its own expression.
function obj:_commandRows(query)
  -- A hosted list. The field holds only what the user typed, so the page's own prefix goes in
  -- front of it before the sources are asked, and their answer is the whole list. One line,
  -- because hosting reuses the mechanism a typed word already goes through rather than adding a
  -- second one, and this spoon still cannot tell what it is hosting.
  if self._page then
    return (self:_queryRows(self._page .. query))
  end
  local out, exclusive = self:_queryRows(query)
  -- A source claimed the query, so its rows are the entire list and the catalog below is
  -- skipped. This one line is the whole of what the launcher knows about being scoped.
  if exclusive then return out end
  local preds = self._predicates
  local catalog = {}
  for _, row in ipairs(self:_orderedRows()) do
    if not (row.when and not (preds[row.when] and preds[row.when]())) then
      -- The name is searched first and the declared terms after it. The subtitle is not, since
      -- here it is a category, a status and a chord, which filterText set to the title says,
      -- lib/chooser/rank.lua.
      catalog[#catalog + 1] = { title = row.title, subTitle = self:_rowSubTitle(row),
                                image = row.image, icon = row.icon, iconOwner = row.iconOwner,
                                item = row.item, filterText = row.title, keywords = row.keywords }
    end
  end
  for _, row in ipairs(self:_rankCatalog(query, catalog)) do out[#out + 1] = row end
  return out
end

--- Launcher:_rankCatalog(query, rows) -> rows
--- Method
--- The catalog rows that match what was typed, in the order they should be read. The work the
--- chooser atom used to do for this list, taken over here because the answer depends on
--- something the atom has no way to know.
---
--- An empty query is returned untouched, which is the whole of what the resting list is. The
--- recency order _orderedRows decided stands, nothing is scored, and nothing is dropped.
---
--- Once something is typed the shared strategy scores every row and the misses go, exactly as
--- the atom did it. What differs is the order of the survivors. A row this query has been used
--- to pick before leads, in the order the store puts them, and everything else follows on match
--- alone with the resting position breaking a tie so recency still shows through underneath.
---
--- An association leads outright rather than adding points to the score, and that is a
--- deliberate departure from plugins/browsertabs/chooser.lua, whose own recency bonus is capped
--- so that it reorders and never overturns. That cap is right there, because general recency is
--- a guess about what is probably wanted. It is wrong here, because an association is not a
--- guess. It is a record that this exact query was typed and this exact row was chosen, which
--- is a statement of intent and the one thing that should be allowed to beat a better spelled
--- match.
---
--- BUT ONLY AMONG ROWS THAT MATCHED COMPARABLY, and the guard is not a refinement, it is what
--- keeps the feature from being an obvious bug. Every remembered spelling of a query answers
--- for the longer queries it begins, which is what makes the memory fill in as you type. So a
--- pick made at "ma" is also consulted when you type "mail", and Maps does match "mail",
--- weakly, by spending the scorer's own typo allowance on the letter it cannot place. Measured
--- against the real strategy, "mail" scores Mail at 43.90 and Maps at 12.56, while "ma" scores
--- them 21.86 and 21.72. Letting a remembered pick lead unconditionally puts Maps above Mail
--- when Mail is spelled out in full, which nobody would read as anything but broken.
---
--- So an association decides only where the scores are near each other, and near is a
--- proportion rather than a number of points, because the score grows with every character
--- typed and a fixed distance would mean something different on every query. The three cases
--- above sit at 99.4%, 65%, and 28.6% of their own best, so the two that must not be bridged
--- are nowhere close to the one that must, and the default leaves a wide margin either side.
---
--- Nothing is ever added to the list this way. A row must have matched to be ordered at all, so
--- a remembered pick that does not match what is typed now is simply not here.
function obj:_rankCatalog(query, rows)
  local matcher, rank = self._matcher, self._rank
  if query == "" or type(matcher) ~= "function" or not rank then return rows end

  -- Where each remembered key sits for this query, one being what it has most come to mean.
  local place = {}
  if self._assoc then
    for i, key in ipairs(self._assoc.orderFor(query)) do
      if place[key] == nil then place[key] = i end
    end
  end

  -- Scored by the one rank engine, the same loop every list runs, so the match itself means
  -- here exactly what it means anywhere else.
  local scored = rank.score(rows, query, matcher)
  local best = nil
  for _, entry in ipairs(scored) do
    if best == nil or rank.before(entry, best) then best = entry end
    entry.assoc = place[recencyKey(entry.item.item)]
  end

  -- What was picked before only decides between rows that matched about as well as the best
  -- one did, see the note above. A row further away than that keeps its place on the match
  -- alone, however often it has been chosen for some shorter spelling of this query.
  --
  -- About as well is two tests. The first is the kind of match. When the best row matches
  -- every word at the start of a word of its name, a remembered row that does not is never
  -- lifted over it, which is the Mail and Maps guard above stated as a kind rather than a
  -- number. Below that the shared search's levels do not lock a pick out, so a pick at a lower
  -- level can still be learned, Loes for lose against Local Servers for one example. The
  -- second is the proportion, taken of the score inside the level and never of the whole
  -- score, since the whole score carries a large step per level and a proportion of it would
  -- read every pair at the same level as near. The proportion is measured downward from the
  -- best row's own score by its size, so a best score below zero, which a matcher may answer,
  -- still admits the best row itself rather than inverting and dropping its own pick.
  local nearness = tonumber((self._ranking or {}).nearness) or DEFAULT_NEARNESS
  local nearFloor = best and (best.within - math.abs(best.within) * (1 - nearness))
  for _, entry in ipairs(scored) do
    if entry.assoc then
      local lockedOut = best.atStart and not entry.atStart
      if lockedOut or entry.within < nearFloor then entry.assoc = nil end
    end
  end

  -- The remembered rows lead in the order this query has come to mean them, and everything
  -- else follows the engine's own order, score first and the resting position breaking a tie.
  table.sort(scored, function(a, b)
    if (a.assoc ~= nil) ~= (b.assoc ~= nil) then return a.assoc ~= nil end
    if a.assoc and b.assoc then return a.assoc < b.assoc end
    return rank.before(a, b)
  end)
  local out = {}
  for i = 1, #scored do out[i] = rank.present(scored[i]) end
  return out
end

--- Launcher:_noteAssociation(item)
--- Method
--- Record that this row was chosen while this query was in the field, which is what makes the
--- next search for the same thing land on it. Keyed by the same recencyKey the timeline uses,
--- so a row with no identity to remember, a calculation, a scope, a typed window size, answers
--- nil and is never recorded, and the two memories can never disagree about what a row is.
---
--- Nothing is recorded while a page is hosted, because this host's own catalog is not the list
--- being shown then. The rows on screen belong to whichever tool the page reached, they are
--- built by that tool rather than ranked here, and the query carries that tool's own prefix.
function obj:_noteAssociation(item)
  if not self._assoc or self._page then return end
  local key = recencyKey(item)
  if not key then return end
  self._assoc.note(self:currentQuery(), key)
end

--- Launcher:rowsOfKind(kind) -> rows
--- Method
--- The launcher's own rows of one kind, filtered by the shared predicates exactly as the full
--- list is, in the same recency order. Exposed for a scope that narrows this catalog rather
--- than reaching a tool, which is what the window and settings scopes are. Reusing the built
--- rows rather than rebuilding them in the composition root keeps one row builder, so a
--- narrowed list can never show a row the whole list does not, or vice versa.
function obj:rowsOfKind(kind)
  local preds = self._predicates
  local out = {}
  for _, row in ipairs(self:_orderedRows()) do
    local it = row.item
    if it and it.kind == kind
      and not (row.when and not (preds[row.when] and preds[row.when]())) then
      out[#out + 1] = { title = row.title, subTitle = self:_rowSubTitle(row), image = row.image,
                        icon = row.icon, iconOwner = row.iconOwner,
                        item = it, filterText = row.title, keywords = row.keywords }
    end
  end
  return out
end

--- Launcher:runItem(item)
--- Method
--- Run one of this launcher's own row descriptors. The public door onto the dispatcher, for a
--- scope handing back a row that came from rowsOfKind, so such a scope needs no dispatch of
--- its own and the leaf calls stay in the one place that knows them.
function obj:runItem(item)
  self:_runItem(item)
end

--- Launcher:peekSelected()
--- Method
--- Show more about the highlighted row without running it, for a row that came from a source
--- claiming the query. The descriptor goes back out through an injected action exactly as a
--- chosen one does, so this learns no more about a peek than it does about a run, which is
--- nothing beyond the row belonging to somebody else.
---
--- Only a claimed row has anywhere to send the question. An app or a command is already fully
--- described by its own row, so there is deliberately no second thing to show for one.
function obj:peekSelected()
  local it = self._stage and self._stage:selectedItem()
  if not it or it.kind ~= "scope" then return end
  if self._actions.scopePeek then self._actions.scopePeek(it) end
end

--- Launcher:canPeekSelected() -> bool
--- Method
--- Whether peeking the highlighted row would do anything, asked by the predicate that gates the
--- binding. A key that is bound and inert is the disagreement the shortcut hints exist to avoid,
--- so the question is answered live rather than assumed from the list being open.
function obj:canPeekSelected()
  local it = self._stage and self._stage:selectedItem()
  if not it or it.kind ~= "scope" then return false end
  local ask = self._actions.scopeCanPeek
  return ask ~= nil and ask(it) == true
end

--- Launcher:_replacementFor(it) -> function or nil
--- Method
--- How taking this row would replace the list, as a callable, or nil when the row is a thing to
--- run. Asked by the atom before a row is allowed to close.
---
--- THE ANSWER IS A CALLABLE AND NOT A YES, which is what keeps asking a question rather than an
--- act. It was written that way because a second caller existed, a shortcut hint that asked on
--- every highlight move only to decide what to call the primary key, and the first version replaced
--- the list by being looked at. That hint has since stopped asking, so there is one caller today,
--- and the shape stays anyway. Collapsing it would put the effect back inside the answer and re-arm
--- exactly that defect for whoever next wants to know what a row would do. It is also the same
--- Command shape a row descriptor already has, one step further along.
---
--- EVERY KIND OF ROW IS ASKED, not only a row a source computed. Whether a row replaces the list
--- is not a property of where it came from, it is a decision about what that row is for, and the
--- only layer holding that decision is the one that named both the row and the thing it points at.
--- A curated command row is the case that proved it. A row for a tool with a list of its own is
--- better off putting that list here than closing this chooser to open a second one over the same
--- screen position. The launcher cannot tell which rows those are and does not try, it asks about
--- all of them and the usual answer is nil.
function obj:_replacementFor(it)
  if not it then return nil end
  local ask = self._actions.rowIntercept
  local replace = ask and ask(it) or nil
  return type(replace) == "function" and replace or nil
end

--- Launcher:selectedKind() -> string or nil
--- Method
--- The kind of the highlighted row, or nil when nothing is highlighted. For whoever prints what the
--- primary key does, since what that key is called depends on what sort of thing it would take, and
--- an application is opened where a command is run.
---
--- The kind is this spoon's own vocabulary, the same word its dispatcher switches on and the same
--- word the root already reads when it decides which rows replace the list, so answering with it
--- exposes nothing new. What any kind should be CALLED stays outside, since a word shown to a person
--- belongs to the root and to config by the rule the whole configuration follows.
function obj:selectedKind()
  local it = self._stage and self._stage:selectedItem()
  return it and it.kind or nil
end

--- Launcher:seedQuery(text) -> bool
--- Method
--- Put text in the field of the open launcher, answering whether it went in. One of the two things
--- a row that replaces this list can mean, the other being enterPage below. For a row that names a
--- query rather than an action, which is what an alias directory row is, so the word arrives in
--- the field and the next thing typed is that tool's own query. Plain text, and the launcher
--- attaches no meaning to it.
--- Seeding is about the launcher's OWN field, so any hosted list is left first. Without that the
--- page's invisible prefix would still be in front of the seeded text and the two would compose
--- into a query neither of them meant, which is what choosing an alias inside the hosted directory
--- did before, asking for the directory's own rows filtered by the word it had just handed over.
function obj:seedQuery(text)
  if not self._stage or type(text) ~= "string" or text == "" then return false end
  self:leavePage()
  self._stage:setQuery(text)
  return true
end

--- Launcher:enterPage(prefix, title)
--- Method
--- Host somebody else's list in the chooser that is already open. The other thing a row that
--- replaces this list can mean, and the one that needs no word in the field.
---
--- A PAGE IS A PREFIX THIS SPOON NEVER SHOWS. The query sources already answer a whole list for a
--- query that names a tool, so hosting one is just asking them with that text in front of whatever
--- the user typed, while the field itself holds only the typing. So this needs no second row
--- mechanism, no second matcher and no second definition of what choosing a row does, and a tool
--- reachable by a typed word is hostable with no work of its own.
---
--- The prefix is opaque. What it says, which tool it reaches, and whether one exists at all are
--- decided by whoever passes it, exactly as with the text seedQuery takes. The title is what the
--- field says while nothing is typed in it, which is what tells you where you are once no word is
--- visible. The way out is not said here. It is a listed key in the shortcut panel like every other
--- key, gated on a page existing, since a sentence in a placeholder was doing a panel's job worse.
function obj:enterPage(prefix, title)
  if not self._stage or type(prefix) ~= "string" or prefix == "" then return false end
  self._page = prefix
  self._stage:setQuery("")
  self._stage:setPlaceholder(title or "This list")
  return true
end

--- Launcher:isHostingList() -> bool
--- Method
--- Whether somebody else's list is showing rather than this catalog. Asked by whoever decides
--- whether to print the way back, so the way back is listed exactly while there is one.
function obj:isHostingList()
  return self._page ~= nil
end

--- Launcher:currentQuery() -> string
--- Method
--- The whole query this launcher's rows are currently being built from, `_page` followed by
--- whatever is typed, exactly the string `_commandRows` already assembles for itself. Answered
--- through one accessor rather than exposing `_page` raw, so a caller does not have to
--- reassemble something this spoon already knows how to say, and so the typed case and the
--- chosen case answer the same way, typing a scope's alias and a space shows the same query as
--- choosing that scope's row does.
---
--- With no page hosted this is simply what is typed, since `_commandRows` itself asks the query
--- sources with nothing in front of it in that case. With no stage at all this answers the
--- empty string, the same nothing typed answers.
function obj:currentQuery()
  local typed = (self._stage and self._stage:query()) or ""
  if self._page then return self._page .. typed end
  return typed
end

--- Launcher:leavePage() -> bool
--- Method
--- Give the launcher its own list back, answering whether there was a page to leave. False is how
--- Backspace on an empty field stays an ordinary press when nothing is hosted.
function obj:leavePage()
  if not self._page then return false end
  self._page = nil
  if self._stage then
    self._stage:setQuery("")
    -- Whatever this open is wearing rather than the base wording, since the hint was chosen
    -- for the open and leaving a hosted list is not a new open. Reading it off the
    -- presentation is what keeps the two answers one answer.
    self._stage:setPlaceholder(self._presentation and self._presentation.placeholder
      or self._placeholder)
  end
  return true
end

--- Launcher:refresh()
--- Method
--- Rebuild the list for the current query, keeping the highlight. A query source whose
--- answer arrives late calls this through the callback the root injects into it, so the
--- row appears without the user typing again. A no op while the launcher is closed OR
--- while some other presentation is what the stage is actually showing.
---
--- Scoped in the chooser stage close out, REVIEW-TRICKLE.md's own L5. Stage:refresh reruns
--- whichever presentation is current, not the launcher's specifically, and this call used to
--- reach for it unconditionally. Harmless while the launcher was the only presentation the
--- migrations had not yet reached, since it was also the only thing that could ever be
--- current, but the trickle and final batch migrations widened what "current" can mean to
--- every presenting tool in the config. A menu search scope answer landing late while the
--- clipboard's prune page is pushed on top used to rebuild the prune ladder instead of doing
--- nothing, silently and without touching any data, which is what kept it from ever being
--- reported as a defect. isCurrent(self._presentation), the same identity check a child's own
--- async answer already uses, docs/PLUGIN-CONTRACT.md's own redrawPresented, is table identity
--- against the exact object present() and push() hand the stage, never against the shared name
--- a child could borrow, so this asks the one question that can never be true for anything but
--- the launcher's own top level.
function obj:refresh()
  if self._stage and self._stage:isCurrent(self._presentation) then
    self._stage:refresh()
  end
end

--- Launcher:_runItem(it)
--- Method
--- The one dispatcher. Maps a row descriptor back to a call. A row a plugin contributed, or a
--- computed row a query source answered, carries its owner's identity, and an owner that
--- registered a runner gets the item back through it, so the run lives with the plugin that
--- built the row and this file names none of them. Everything else is the launcher's own kind
--- switch, app, special, calc and scope, whose leaf calls are injected and close over core.
---
--- Decision four of the handoff brief, the deferral moved inside these branches rather than
--- wrapping the whole switch from outside, review 9.7's own warning accepted and answered.
--- Every branch below still waits the same 0.1 seconds for focus to return to the app the
--- launcher covered before it acts, since an owner's run, app, calc, and scope all genuinely
--- act on the world once that focus is back, a window action the clearest case, reading
--- hs.window.focusedWindow(). special waits too, but only ever runs for an
--- unmigrated tool or a bare command, since a presenting tool's own row never reaches this
--- function at all, decision two, it completes through the presentation's own intercept and
--- stage.push before onSelect is ever asked, synchronously, with no close and no wait.
--- self._runTimer holds whichever branch's timer, one at a time, since only one kind ever
--- fires per call and a Hammerspoon timer nothing refers to can be collected before it runs.
function obj:_runItem(it)
  if not it then return end
  local a = self._actions
  -- An owned row whose owner runs it. The whole item goes back, so a plugin reads whichever
  -- fields it put there itself, a name, a url, a typed size, and the launcher interprets none
  -- of them. A row whose owner registered no runner, a computed sum for one, falls through to
  -- the kind switch below exactly as an unowned row does.
  local runner = it.owner ~= nil and self._runners[it.owner] or nil
  if runner then
    self._runTimer = hs.timer.doAfter(0.1, function() runner(it) end)
    return
  end
  -- An owned row with no runner may still be one of this host's plain kinds, a computed sum
  -- copied or an app opened, but never special or scope, since both act on another tool's name
  -- and an owned row must not reach a tool through a word its owner chose.
  if it.owner ~= nil and (it.kind == "special" or it.kind == "scope") then return end
  if it.kind == "app" then
    self._runTimer = hs.timer.doAfter(0.1, function()
      if a.app then a.app(it.bundleID, it.url) end
    end)
  elseif it.kind == "special" then
    -- Two sources, not a leak. A name the registry answers is a tool, and everything left
    -- in actions.special is a bare command with no tool behind it, so one lookup for each
    -- is honest rather than one pretending every special row is a plugin. The registry is
    -- asked first and only a name it does not run falls through to actions.special, which
    -- registration itself makes safe, since a name cannot be claimed by both. Reached only
    -- for an unmigrated tool or a bare command, see this method's own doc comment above.
    self._runTimer = hs.timer.doAfter(0.1, function()
      local ran = self._registry and self._registry.run(it.name)
      if not ran then
        local fn = a.special and a.special[it.name]
        if fn then fn() end
      end
    end)
  elseif it.kind == "calc" then
    -- A computed result is put somewhere useful by an injected action, so the launcher
    -- does not learn what a clipboard is, exactly as it does not learn what an app or a
    -- capture is. A pending row carries no value and is disabled, so it never arrives.
    self._runTimer = hs.timer.doAfter(0.1, function()
      if it.value and a.copy then a.copy(it.value) end
    end)
  elseif it.kind == "scope" then
    -- A row that came from a source claiming the query. It carries the name of whatever
    -- made it plus that thing's own descriptor, and an injected action hands both back, so
    -- the launcher routes the row without learning which tool it belongs to or what the
    -- payload inside it means, exactly as it does for a computed result.
    self._runTimer = hs.timer.doAfter(0.1, function()
      if a.scope then a.scope(it) end
    end)
  end
end

-- Whether a changed path under a watched app directory is worth dropping the disk scan for.
-- hs.pathwatcher fires for every file event anywhere beneath the root it watches, which
-- includes a write inside an app bundle that is already installed, a self updating app
-- rewriting its own files being the ordinary case, and that must not throw away the scan on
-- every one of those.
--
-- THE NESTED BUNDLE HOLE, which is what this comment mostly exists to record. The first
-- version of this asked whether the path ended in .app before it asked anything about depth,
-- and answered yes when it did, at any depth. That reads as "an app bundle itself arriving,
-- leaving, or being renamed", and it is not what it says, because an app bundle contains
-- other app bundles. /Applications on this machine holds 217 of them, Xcode carrying thirty,
-- Chrome twelve, Docker, 1Password, Arc, Figma and Claude their own handful each, and every
-- one of those is a helper inside a bundle that is already installed. So a self updating app
-- rewriting its own helpers, which is the single most ordinary event under this directory,
-- matched the very check written to exclude it, dropped the whole disk scan, and handed the
-- next launcher open a 299ms rescan on the main thread inside show, ahead of the window being
-- placed. That is the sluggish open, and it is also what made hs.chooser's own long standing
-- placement gap visible, since a stalled main thread is the difference between that gap being
-- sampled by the compositor and not.
--
-- So depth is asked FIRST now, and a path is noise the moment any ANCESTOR component is an
-- .app, which is exactly what "inside a bundle that already exists" means and what the old
-- prose already claimed. A .app that is not inside another .app still counts at any depth,
-- since the scan itself descends into vendor subfolders and an app one level down in one of
-- those is a real arrival. A direct child that is not a bundle at all counts too, since an
-- installer commonly writes a temporary name and renames it into place.
--
-- The watched directory's own bare path also counts, which is what FSEvents reports instead
-- of any real path once its queue overflows during a very large copy and it falls back to
-- saying only that something under here changed.
local function isTopLevelAppChange(path, dir)
  if not path then return false end
  if path:sub(-1) == "/" then path = path:sub(1, -2) end
  if path == dir then return true end
  local prefix = dir .. "/"
  if path:sub(1, #prefix) ~= prefix then return false end
  local rest = path:sub(#prefix + 1)
  if rest == "" then return false end
  -- An ancestor ending in .app means this write is inside a bundle that already exists.
  -- Checked on the part BELOW the watched root, so a watched root that itself sat inside
  -- something ending in .app could not make every path under it unreachable.
  if rest:find(".app/", 1, true) then return false end
  if rest:sub(-4) == ".app" then return true end
  return not rest:find("/", 1, true)
end

--- Launcher:start()
--- Method
--- Begin owning live state. Load the persisted recency order, fed only by
--- launcher picks. The app watcher refreshes the running set on activation,
--- launch, and termination, and invalidates the cached rows, so app rows
--- track the machine without rescanning on every open. Idempotent.
---
--- A second pair of watchers, one per directory the disk scan itself reads except
--- System's own, sits beside it for a different staleness. The disk scan that feeds
--- _appRows runs once and is cached in _installedApps forever, so an app installed
--- after this scan ran, or removed after it ran, was invisible until the next config
--- reload unless it happened to be running, since only the running set was ever
--- refreshed. Each watcher drops _installedApps along with both row caches when
--- isTopLevelAppChange says a path it was told about is a real arrival, departure, or
--- rename rather than noise from inside a bundle that already exists, so the next open
--- rescans lazily rather than the watcher paying for a scan nobody asked to see yet.
--- /System/Applications is left unwatched, since it only changes with an OS update, and
--- an OS update always brings a reboot and a fresh Hammerspoon load with it, so nothing
--- here would ever catch a change there without also seeing everything else start clean
--- first. A watcher is built only for a root that is genuinely a directory on this
--- machine, the same guard scanInstalledApps already puts in front of a scan, since
--- HOME/Applications is common enough to not exist that hs.pathwatcher.new should never
--- be asked to watch it anyway. A directory watcher can still fire several times in a
--- row while an installer writes an app bundle, and clearing an already nil cache costs
--- nothing, so none of this waits for the bursts to settle.
--- Launcher:_warmAppScan(delay)
--- Method
--- Run the disk scan off the first open and onto a timer, so the cost is already paid by
--- the time anybody presses the key.
---
--- The scan is the launcher's one genuinely expensive step, measured at 356ms warm over 146
--- apps on this machine and worse on a cold filesystem, almost all of it infoForBundlePath
--- reading a plist per bundle and imageFromAppBundle rendering an icon per bundle. It used
--- to run lazily inside the first _appRows, which is inside the first row build, which is
--- inside show, ahead of the window being placed. So the first open after every load stalled
--- the main thread for the whole scan before anything appeared. That is the sluggish first
--- open, and it also widens the window in which hs.chooser's own show can be caught drawing
--- at the wrong position, since that gap is a stalled main thread away from being visible.
---
--- Scanning here rather than in the lazy read keeps _appRows exactly as it was, still
--- scanning for itself when it finds no cache, so a warm up that has not fired yet or was
--- dropped a moment ago costs correctness nothing and only costs that one open its old
--- speed. This is a head start, not a new source of truth.
---
--- delay is what the caller thinks the scan should wait for. start passes a short one, long
--- enough that a reload finishes wiring everything else first, since nothing is waiting on
--- this. The directory watcher passes a longer one, because an installer writing an app
--- bundle fires many times while the bundle is still half written, and a scan taken mid write
--- reads a bundle that is not there yet. One timer, restarted on every call, is what turns
--- that burst into a single scan after the writing stops. The timer is held in a field for
--- the reason every timer in this config is, a Hammerspoon timer is userdata whose finalizer
--- stops it, so one nothing refers to can be collected before it fires.
function obj:_warmAppScan(delay)
  if self._warmTimer then self._warmTimer:stop() end
  self._warmTimer = hs.timer.doAfter(delay, function()
    self._warmTimer = nil
    -- Asked again here rather than trusted from the call site, since a real open may well
    -- have run the scan itself in the meantime and there is nothing to warm.
    if not self._installedApps then self._installedApps = scanInstalledApps() end
    -- The one moment this host actually knows which applications exist, so it is where a
    -- remembered pick for one that has gone is dropped. Off the critical path already, and
    -- run whether or not this timer did the scan itself, since a real open may have.
    self:_pruneAssociations()
  end)
end

--- Launcher:_pruneAssociations()
--- Method
--- Forget what was picked for applications that are no longer here. Only applications, and the
--- restraint is the point. A row for a registered tool can disappear because that tool was
--- switched off rather than removed, and this host cannot tell those apart, so deleting a
--- year of history on that ambiguity is worse than carrying a number no row will ever claim.
--- A dead key costs nothing, since a bonus is only ever looked up for a row that is in the
--- list, and the decay forgets it anyway within a couple of dozen picks of that query.
function obj:_pruneAssociations()
  if not self._assoc or not self._installedApps then return end
  local valid = {}
  for bundleID in pairs(self._installedApps) do valid[#valid + 1] = "app:" .. bundleID end
  -- A running application outside the scanned roots is a row this catalog builds too, so its
  -- key is just as valid even though no directory here holds it.
  for _, app in ipairs(hs.application.runningApplications()) do
    local bundleID = app:bundleID()
    if bundleID then valid[#valid + 1] = "app:" .. bundleID end
  end
  self._assoc.prune(valid, function(key) return key:sub(1, 4) == "app:" end)
end

--- How long each caller of _warmAppScan waits. START is short because nothing is racing it.
--- SETTLE is long because it is coalescing an installer's write burst, see _warmAppScan.
local WARM_START_DELAY = 3
local WARM_SETTLE_DELAY = 5

function obj:start()
  if self._appRowsWatcher or self._appDirWatchers then return self end
  -- Seeded once here rather than left to whatever Lua state Hammerspoon happens to start
  -- with, the same call plugins/clipboard/manager/init.lua's own start already makes for
  -- the identical reason, so the empty field's random pick does not run the same sequence
  -- after every single reload.
  math.randomseed(os.time())
  self._mru = hs.settings.get(MRU_SETTINGS_KEY) or {}
  self._orderedRowsCache = nil
  self._appRowsWatcher = hs.application.watcher.new(function(_, event, app)
    if event == hs.application.watcher.activated then
      self._appRowsCache = nil
    elseif event == hs.application.watcher.launched or event == hs.application.watcher.terminated then
      self._appRowsCache = nil
      self._orderedRowsCache = nil
    end
  end)
  self._appRowsWatcher:start()

  self._appDirWatchers = {}
  -- APP_DIRS holds all three roots in scan order, so this reaches into it by index rather
  -- than repeating the paths, and skips index two, /System/Applications, by the reasoning
  -- above.
  for _, dir in ipairs({ APP_DIRS[1], APP_DIRS[3] }) do
    if hs.fs.attributes(dir, "mode") == "directory" then
      local watcher = hs.pathwatcher.new(dir, function(paths)
        for _, p in ipairs(paths or {}) do
          if isTopLevelAppChange(p, dir) then
            self._installedApps = nil
            self._appRowsCache = nil
            self._orderedRowsCache = nil
            -- Dropped and then rebuilt in the background, so installing or removing an app
            -- does not hand the very next open the full scan it would otherwise inherit.
            self:_warmAppScan(WARM_SETTLE_DELAY)
            break
          end
        end
      end)
      watcher:start()
      self._appDirWatchers[#self._appDirWatchers + 1] = watcher
    end
  end
  self:_warmAppScan(WARM_START_DELAY)
  return self
end

--- Launcher:stop()
--- Method
--- Stop the app watcher and the directory watchers, and drop every cache they were
--- keeping honest. _installedApps goes too, for symmetry with the watchers that
--- stopped guarding it, a stopped launcher holding onto an old scan across to the
--- next start would reintroduce the same staleness this spoon just closed, only
--- through stop and start instead of through a missing watcher.
---
--- A pending warm up is stopped for the same reason and one more. It would fire into a
--- launcher nobody is watching any more and put back the very scan the line below drops,
--- so leaving it running would make stop quietly not mean what it says.
function obj:stop()
  if self._warmTimer then
    self._warmTimer:stop()
    self._warmTimer = nil
  end
  if self._appRowsWatcher then
    self._appRowsWatcher:stop()
    self._appRowsWatcher = nil
  end
  if self._appDirWatchers then
    for _, watcher in ipairs(self._appDirWatchers) do watcher:stop() end
    self._appDirWatchers = nil
  end
  self._appRowsCache = nil
  self._orderedRowsCache = nil
  self._installedApps = nil
  return self
end

--- Launcher:_buildPlaceholders() -> list of strings
--- Method
--- The pool the empty field rotates through, this host's own wording first and then every
--- example a computed row source proposed, in source order.
---
--- The launcher writes no example of its own and holds no list of what the sources can do. A
--- source that proposes nothing simply contributes nothing and the pool falls back to the one
--- string this host has always shown, which is why an install with no computed source at all
--- still reads exactly as it did before this existed.
---
--- Nothing is dropped for being too long. A hint wider than the field clips visibly and the
--- plugin that wrote it can then shorten it, while a hint silently discarded here would look
--- to its author like a feature that never arrived.
function obj:_buildPlaceholders()
  local pool = { self._placeholder }
  local seen = { [self._placeholder] = true }
  for _, hint in ipairs(self._placeholderExamples or {}) do
    if type(hint) == "string" and hint ~= "" and not seen[hint] then
      seen[hint] = true
      pool[#pool + 1] = hint
    end
  end
  return pool
end

--- Launcher:_nextPlaceholder() -> string
--- Method
--- The hint this open wears, a uniformly random pick from the pool that is never the same
--- string the previous open just showed.
---
--- Random rather than a fixed cycle now, since a cycle answers the same first hint after
--- every single reload, the plain base wording, and reload is frequent enough here that a
--- person almost never saw anything else. Random fixes that for free, the very first open
--- after a reload is as likely to land on a computed source's own line as on the base
--- wording, which is still one entry in the pool rather than a guaranteed opener. Never
--- repeating the immediately previous pick is the one constraint kept from the old cycle, so
--- two opens in a row still read two different things rather than risking the same line
--- twice by chance, which a person would read as the feature doing nothing. _placeholderLast
--- remembers only that one previous pick, deliberately not persisted, a reload forgetting it
--- being no loss since the very next open picks fresh anyway. A pool of one, the ordinary
--- shape when no computed source is present, has nothing to avoid repeating and answers
--- itself every time, which reads exactly as this field always did before any of this
--- existed.
function obj:_nextPlaceholder()
  local pool = self._placeholders
  if not pool or #pool == 0 then return self._placeholder end
  if #pool == 1 then return pool[1] end
  local pick
  repeat
    pick = pool[math.random(#pool)]
  until pick ~= self._placeholderLast
  self._placeholderLast = pick
  return pick
end

--- Launcher:show(query)
--- Method
--- Open the launcher. The app that was frontmost is captured first, before the chooser takes
--- focus, along with a counter marking this open. Both are the launcher's own business, since
--- it covers an app and its deferred dispatch already depends on focus going back there, and
--- a source that acts on that app cannot read it for itself once the chooser is up, where the
--- frontmost app is this one. The counter is what lets such a source cache per open, since a
--- second open of the same app is still a fresh read.
---
--- An optional query opens the launcher with the field already filled, which is how something
--- outside hands the list back with a word in it. It is plain text and the launcher attaches no
--- meaning to it, so this is not a way to open one tool, it is the same open with typing already
--- done. Four details are load bearing. It is set after the show, because showing clears the
--- field. It is followed by a refresh, because setting a chooser's query does not fire the
--- callback that rebuilds the rows, so without it the field would read one thing and the list
--- would show another. The refresh resets the highlight to the top, which is right for a list
--- the user has not seen yet. And the refresh is FORCED rather than left to the stage's
--- ordinary visibility guard, because hs.chooser:isVisible() can still read false for a moment
--- right after present has just shown the window, finding three of the phase two adversarial
--- review, and a guarded refresh landing in that gap silently drops the rebuild, leaving the
--- field reading one thing and the list showing another exactly as the sentence above warns
--- against.
function obj:show(query)
  -- Asked here rather than in start, and only once. start now runs at wire stage three,
  -- long before the composition root's own late configure call sets self._chordLabel
  -- hundreds of lines further into compose.lua, so asking there reported a gap that had
  -- not opened yet on every single load. By a person's first open every configure this
  -- host will ever receive has already run, which is the earliest moment the claim can
  -- honestly be made, and the flag is what keeps a launcher opened many times a day from
  -- printing the same line every time rather than the once a genuine gap deserves.
  if not self._chordLabel and not self._chordWarned then
    self._chordWarned = true
    log.w("no chord wording was injected, so every row that would name a shortcut reads its bare category instead")
  end
  self._openId = (self._openId or 0) + 1
  -- The app this launcher covers, which can never be this app. macOS answers with ourselves
  -- when our own chooser already holds focus, which is what happens when one open follows
  -- another closely enough that focus has not gone back yet, and the alias directory handing
  -- the list back is exactly that case. Keeping the previous answer is then correct rather
  -- than merely safe, because the app underneath never changed, while recording ourselves
  -- would quietly hand a source that acts on the covered app the wrong app, which is how
  -- menu search would come back listing Hammerspoon's own menus. This is the same self
  -- exclusion _promote makes, for the same reason, and it hardens any two opens in quick
  -- succession rather than only this one.
  local front = hs.application.frontmostApplication()
  if not (SELF_BUNDLE and front and front:bundleID() == SELF_BUNDLE) then
    self._coveredApp = front
  end
  if not self._stage then return end
  -- The hint for this open, chosen here and never while a list is up, so the field can only
  -- change wording between opens and never under somebody reading it. Chosen before leaving
  -- any hosted list on purpose, since leavePage writes straight onto the field's presentation
  -- when a page was left open, and that write must already carry this open's own wording
  -- rather than whatever turn the previous open landed on.
  self._presentation.placeholder = self:_nextPlaceholder()
  -- Every open starts on this catalog, whatever list the previous open was left hosting when it
  -- closed. Done before the show, since showing builds the first rows.
  self:leavePage()
  -- Stage:present sets a presentation's own placeholder before every show, so writing the
  -- field on the table above is the whole of it and no second call is wanted here.
  self._stage:present(self._presentation)
  if query and query ~= "" then
    self._stage:setQuery(query)
    self._stage:refresh(true, true)
  end
end

--- Launcher:coveredApp() -> hs.application, number
--- Method
--- The app the launcher opened over and the id of this open. Nil before the first open.
function obj:coveredApp()
  return self._coveredApp, self._openId
end

--- Launcher:isShowing()
--- Method
--- Whether the stage's window is actually up AND the launcher itself, rather than some other
--- presentation, is what it currently shows. Safe before configure. Delegates to self._surface,
--- host/stage's own surfaceFor, which answers exactly this question and is now the one place
--- that answer is written, so this predicate and lib/nav.lua's own routing can never drift
--- apart the way review finding ten warned two separate answers to the same question would.
--- Both halves stay load bearing inside that one answer. The name check is what keeps this
--- false once a future presentation is what the shared window actually holds. The visibility
--- check is what keeps this false the moment the window genuinely tears down even if the
--- stack briefly disagrees, finding two of the phase two adversarial review, a present that
--- lands in the narrow gap where the widget is still dismissing can leave the stack claiming
--- the launcher is current with no window behind it, and this predicate must not stay stuck
--- on through that, since launcherOpen gates j, k, space, and the action panel chord.
function obj:isShowing()
  return self._surface ~= nil and self._surface.isShowing()
end

--- Launcher:surface()
--- Method
--- The dot-called navigation adapter, for the root to register in its shared
--- choosers list. The stage's own, delegated to rather than built here.
function obj:surface()
  return self._surface
end

return obj
