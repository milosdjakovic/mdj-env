--- === Launcher ===
---
--- A filterable app switcher and command runner, the built-in Hyper+Space launcher.
---
--- This is a coordinator. It combines several plain spoons into one feature and
--- owns real state, the app scan caches and an hs.application.watcher, so it is a
--- spoon of its own rather than inline wiring in the composition root. It never
--- names a domain spoon. The root injects every collaborator through configure,
--- the Chooser factory, the pure keys and apps data, the window actions table, a
--- glyph resolver, the settings pane descriptors, the shared predicate registry,
--- the docked shortcut panel callbacks, the tool registry from phase seven of the
--- build plan, and a small dispatch of leaf actions that do name the domain
--- spoons. So the launcher owns the row building, the matching,
--- the app enumeration, and the command dispatch structure, and knows nothing
--- about what a row ultimately does.
---
--- The Command pattern is preserved. Each row carries only a serializable
--- descriptor, its kind plus a name or bundle id, never a function, because the
--- Chooser hands each row to hs.chooser which serialises it and would drop a
--- function. runItem turns that descriptor back into the injected call.
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
obj._chooser = nil          -- the Chooser factory (has .new)
obj._theme = nil
obj._placeholder = nil
obj._keys = nil
obj._apps = nil
obj._windowActions = nil
obj._windowLeaderName = nil
obj._glyphFor = nil         -- function(key, mods) -> chord glyph string
obj._settingsPanes = nil    -- raw settings pane descriptors, injected by the root
obj._predicates = nil       -- shared predicate registry, for `when` gating
obj._shortcutPanel = nil    -- { onPositioned, onActivity, onClose }
obj._actions = nil          -- leaf dispatch: app, capture, settingsPane, special, rowIntercept
obj._queryProviders = nil   -- ordered query row sources, each answering rows(query)
obj._aliasHint = nil        -- function(name) -> subtitle fragment, "" when there is none
obj._registry = nil         -- the tool registry, dot called, optional, see configure and _runItem

-- Owned state
obj._instance = nil         -- the built Chooser instance
obj._surface = nil          -- dot-called navigation adapter over the instance
obj._glyphIconCache = nil
obj._actionRows = nil
obj._settingsPaneRows = nil
obj._configuredApps = nil
obj._installedApps = nil
obj._appRowsCache = nil          -- app rows only, invalidated on running-set change or activation
obj._orderedRowsCache = nil      -- all rows, recency-sorted, invalidated on any promote
obj._appRowsWatcher = nil
obj._mru = nil              -- most-recently-used item keys, front is most recent
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
  if item.kind == "app" then return "app:" .. tostring(item.bundleID) end
  if item.kind == "settingsPane" then return "settingsPane:" .. tostring(item.url) end
  return item.kind .. ":" .. tostring(item.name)
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
  self._chooser = opts.chooser
  self._theme = opts.theme
  self._placeholder = opts.placeholder or "Search apps and commands"
  self._keys = opts.keys or {}
  self._apps = opts.apps or {}
  self._windowActions = opts.windowActions or {}
  self._windowLeaderName = opts.windowLeaderName or "Meta"
  self._glyphFor = opts.glyphFor or function(key) return tostring(key) end
  self._settingsPanes = opts.settingsPanes or {}
  self._predicates = opts.predicates or {}
  self._shortcutPanel = opts.shortcutPanel or {}
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

  self._glyphIconCache = {}

  self._configuredApps = self:_buildConfiguredApps()

  -- The Chooser instance, wired with the docked shortcut panel callbacks. The row
  -- runs deferred, after the chooser tears down and macOS restores focus to the app
  -- that was frontmost before the launcher opened, since a window action acts on
  -- hs.window.focusedWindow().
  local sp = self._shortcutPanel
  self._instance = self._chooser.new({
    theme = self._theme,
    placeholder = self._placeholder,
    rows = function(query) return self:_commandRows(query) end,
    onSelect = function(item)
      if item then
        -- Promote now, on the true "user chose this row" moment, so the order
        -- persists at once even though the run is deferred below. Any kind counts.
        self:_promote(recencyKey(item))
        -- The run waits a beat for focus to return to the app the launcher covered, and the
        -- timer is held in a field for the length of that wait. A Hammerspoon timer is
        -- userdata whose finalizer stops it, so one nothing refers to can be collected
        -- before it fires, and the chosen row would then do nothing at all. Only one is
        -- ever pending, because choosing a row closes the chooser.
        self._runTimer = hs.timer.doAfter(0.1, function() self:_runItem(item) end)
      end
    end,
    -- Whether a row means this list becomes another list rather than being taken, asked by the
    -- atom before it lets a row close. The launcher only routes the question, exactly as it
    -- routes running a row and peeking at one, so it still learns nothing about what a scope or
    -- a tool is. Whoever answers acts through the two public doors below, seedQuery and
    -- enterPage.
    --
    -- Promoting happens HERE and not in _replacementFor, because the atom calls this closure only
    -- when a row is actually being taken while the shortcut hint asks _replacementFor on every
    -- highlight move to decide what to call the key. Taking a row that replaces the list is
    -- still using the thing it points at, so it belongs in the shared recency order exactly as
    -- running it did, and it lands under the same key running it produced. A row with no
    -- identity to remember, which is every row a scope computed, answers nil to recencyKey and
    -- so stays out of the timeline as it always has.
    intercept = function(item)
      local replace = self:_replacementFor(item)
      if not replace then return false end
      replace()
      self:_promote(recencyKey(item))
      return true
    end,
    -- Backspace on an empty field, which is how you leave a hosted list. The atom asks only
    -- when there is nothing to delete, so this never competes with ordinary editing.
    back = function() return self:leavePage() end,
    onPositioned = sp.onPositioned,
    onActivity = sp.onActivity,
    onClose = sp.onClose,
  })

  -- Dot-called navigation adapter over the colon-called Chooser instance, so the
  -- root's shared activeChooser / routeNav registry drives it like the other pickers.
  local instance = self._instance
  self._surface = {
    isShowing = function() return instance:isShowing() end,
    selectNext = function() instance:selectNext() end,
    selectPrev = function() instance:selectPrev() end,
    insertSelected = function() instance:insertSelected() end,
    -- The same verb name the tools' own pickers answer, so one routed action reaches whichever
    -- list is open and this one needs no case of its own in the root.
    peekPreview = function() self:peekSelected() end,
    hide = function() instance:hide() end,
  }

  return self
end

--- Launcher:_glyphIcon(glyph)
--- Method
--- An action row has no app icon of its own, so draw one from a glyph, once per
--- glyph and cached, sized to line up with the real app icons. nil glyph yields none.
function obj:_glyphIcon(glyph)
  if not glyph then return nil end
  local cache = self._glyphIconCache
  if cache[glyph] == nil then
    local size = 72
    local c = hs.canvas.new({ x = 0, y = 0, w = size, h = size })
    c[1] = { type = "text", text = glyph, textSize = 52, textAlignment = "center",
             frame = { x = "0%", y = "8%", w = "100%", h = "100%" } }
    cache[glyph] = c:imageFromCanvas() or false -- false marks "tried, none"
    c:delete()
  end
  return cache[glyph] or nil
end

--- Launcher:_chordLabel(leader, key, mods)
--- Method
--- Readable row text for a chord, the leader name plus the key glyph. Words, not
--- badges, since a chooser row is plain text.
function obj:_chordLabel(leader, key, mods)
  return leader .. " " .. self._glyphFor(key, mods)
end

-- camelCase action name -> "Title Case" label, applied when a binding sets no
-- explicit description.
local function humanize(name)
  local s = tostring(name):gsub("(%l)(%u)", "%1 %2")
  return s:sub(1, 1):upper() .. s:sub(2)
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
  self._settingsPaneRows = self:_buildSettingsPaneRows()
end

--- Launcher:_buildActionRows()
--- Method
--- The static action rows. Each is { title, subTitle, image, item, when? } where
--- item is a serializable descriptor for the dispatcher.
function obj:_buildActionRows()
  local keys = self._keys
  local rows = {}
  -- keywords is hidden text the matcher sees and the row does not show, the same field
  -- the injected rows already carry. It exists so a row can answer to a word its title
  -- and subtitle have no room for, rather than that word being padded into the visible
  -- subtitle where it would cost a reader something to buy a searcher something.
  local function add(title, subTitle, item, glyph, when, keywords)
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
    if item and item.kind == "special" then
      subTitle = (subTitle or "") .. self._aliasHint(item.name)
    end
    rows[#rows + 1] = { title = title, subTitle = subTitle, image = self:_glyphIcon(glyph),
                        item = item, when = when, keywords = keywords }
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
  -- glyph, its detail or its chord, now lives on the descriptor rather than here.
  --
  -- Adding a tool still costs one addTool line below, so this is not yet one
  -- registration, only where a row's own data lives now rather than a change to how
  -- many places know a tool exists. Removing that last line would move the whole row
  -- order into the composition root, taking the capture loop and the window loop with
  -- it since they sit in this same build, and that is a decision for later rather than
  -- a thing to sneak in here.
  local function addTool(name)
    local row = self._registry and self._registry.rowFor(name)
    if not row then return end
    local keysName = row.keysName or name
    local keyEntry = keys[keysName]
    if not keyEntry then
      log.w(string.format(
        "Launcher addTool skipped '%s', its row names '%s' in config/keys.lua and nothing is there",
        name, keysName))
      return
    end
    local subTitle
    if row.detail then
      subTitle = row.category .. " · " .. row.detail
    elseif row.chord then
      subTitle = row.category .. " · " .. self._glyphFor(keyEntry.key, keyEntry.modifiers)
    else
      subTitle = row.category .. " · " .. self:_chordLabel("Hyper", keyEntry.key)
    end
    add(keyEntry.description, subTitle, { kind = "special", name = name },
      row.glyph or keyEntry.glyph, nil, row.keywords)
  end
  -- Window actions share one glyph, the chord in the subtitle tells them apart;
  -- capture and the system actions get a per-action one.
  local captureGlyphs = { ocrArea = "🔤", captureArea = "📸", captureAreaClipboard = "📸", recordArea = "🎥" }
  addTool("colorPicker")
  addTool("emoji")
  for _, c in ipairs(keys.capture) do
    add(c.description or humanize(c.action), "Capture · " .. self:_chordLabel("Hyper", c.key, c.mods),
      { kind = "capture", name = c.action }, captureGlyphs[c.action] or "📸")
  end
  addTool("caffeinate")
  addTool("vpn")
  addTool("clipboard")
  -- The two clipboard actions that are global combos rather than Hyper bindings, so their
  -- subtitle carries the whole chord and names no leader. They are listed here because a
  -- global binding appears in no leader's cheat sheet, leaving this their only listing.
  addTool("appendCopy")
  addTool("pasteNext")
  addTool("browserTabs")
  -- Display profiles has no dedicated chord, it opens from here only, so its subtitle names
  -- what it does rather than a shortcut. The two display commands sit under a Displays
  -- category rather than System, so their subtitle does not read like the "System Settings"
  -- subtitle the Displays settings pane row carries.
  addTool("displayProfiles")
  add("Search Settings", "System · opens the System Settings search field", { kind = "special", name = "searchSettings" }, "🔍")
  add("Overlay Display", "Displays · where panels and choosers appear", { kind = "special", name = "overlayDisplay" }, "🖥️")
  -- Text case has no dedicated chord, it opens from here only, so its subtitle names what
  -- it does rather than a shortcut.
  addTool("textCase")
  -- Processes has no dedicated chord either, so its subtitle names what it does, and it
  -- names all three tiers rather than just servers because that is what the list holds.
  -- The keywords carry the words the title used to and no longer does, so the habit of
  -- typing process or port still lands on it.
  addTool("processes")
  -- Dock auto hide has no dedicated chord either, it lost its standalone one when it moved
  -- into Olm, so its subtitle names what it does.
  addTool("dockAutoHide")
  -- File search does have a chord, so its subtitle names it like the other keyed tools. The
  -- keywords carry the words a habit reaches for, since the title says file search and the
  -- thing people type is find.
  addTool("fileSearch")
  -- The alias directory, which has no chord because it opens from here, and is also reached by
  -- its own alias like the tools it lists. Its subtitle says what it holds rather than naming
  -- the word that reaches it, since that word is appended by the same hint every other row
  -- gets, so the row reads as one thing and the alias is stated once.
  if keys.aliasDirectory then
    add(keys.aliasDirectory.description, "Tools · every word that scopes this list",
      { kind = "special", name = "aliasDirectory" }, keys.aliasDirectory.glyph, nil,
      "alias aliases scope scopes shortcut words prefix")
  end
  add(keys.lock.description, "System · " .. self:_chordLabel("Hyper", keys.lock.key), { kind = "special", name = "lock" }, "🔒")
  add(keys.sleep.description, "System · " .. self:_chordLabel("Hyper", keys.sleep.key), { kind = "special", name = "sleep" }, "🌙")
  for _, b in ipairs(keys.windowManagement) do
    if self._windowActions[b.action] then
      add(b.description or humanize(b.action), "Window · " .. self:_chordLabel(self._windowLeaderName, b.key, b.mods),
        { kind = "window", name = b.action }, "🪟", b.when)
    end
  end
  return rows
end

--- Launcher:_buildSettingsPaneRows()
--- Method
--- System Settings panes as rows. The injected descriptors are pure (title,
--- subTitle, glyph, keywords, item); render each glyph into an icon the same way
--- the action rows do and keep the hidden keywords for the matcher.
function obj:_buildSettingsPaneRows()
  local rows = {}
  for _, r in ipairs(self._settingsPanes) do
    rows[#rows + 1] = {
      title = r.title, subTitle = r.subTitle, image = self:_glyphIcon(r.glyph),
      keywords = r.keywords, item = r.item,
    }
  end
  return rows
end

--- Launcher:_buildConfiguredApps()
--- Method
--- The configured Hyper toggle for each app, keyed by bundle id, so an app row can
--- show its shortcut and reuse its url-pane behavior.
function obj:_buildConfiguredApps()
  local out = {}
  for _, t in ipairs(self._keys.appToggles or {}) do
    local bundleID = self._apps[t.app]
    if bundleID then out[bundleID] = { key = t.key, url = t.url } end
  end
  return out
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
--- recency re-sort on a selection never rescans apps.
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

  local rows = {}
  for _, e in ipairs(list) do
    local cfg = self._configuredApps[e.bundleID]
    local status = e.running and "Open" or "Not running"
    local subTitle = cfg and (status .. " · Hyper " .. cfg.key) or status
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
--- action rows then the settings panes; each row carries that position as _n. A
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
  for _, row in ipairs(self._settingsPaneRows) do push(row) end
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
--- A source returns a glyph rather than an image, and this renders it through the same
--- cache the action rows use, so a source never draws anything and there is one glyph
--- cache rather than one per source. A source is fully trusted for its own rows but not
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
          image = r.image or self:_glyphIcon(r.glyph),
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
  for _, row in ipairs(self:_orderedRows()) do
    if not (row.when and not (preds[row.when] and preds[row.when]())) then
      local filterText = row.title .. " " .. row.subTitle
      if row.keywords then filterText = filterText .. " " .. row.keywords end
      out[#out + 1] = { title = row.title, subTitle = row.subTitle, image = row.image,
                        item = row.item, filterText = filterText }
    end
  end
  return out
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
      local filterText = row.title .. " " .. row.subTitle
      if row.keywords then filterText = filterText .. " " .. row.keywords end
      out[#out + 1] = { title = row.title, subTitle = row.subTitle, image = row.image,
                        item = it, filterText = filterText }
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
  local it = self._instance and self._instance:selectedItem()
  if not it or it.kind ~= "scope" then return end
  if self._actions.scopePeek then self._actions.scopePeek(it) end
end

--- Launcher:canPeekSelected() -> bool
--- Method
--- Whether peeking the highlighted row would do anything, asked by the predicate that gates the
--- binding. A key that is bound and inert is the disagreement the shortcut hints exist to avoid,
--- so the question is answered live rather than assumed from the list being open.
function obj:canPeekSelected()
  local it = self._instance and self._instance:selectedItem()
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
  local it = self._instance and self._instance:selectedItem()
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
  if not self._instance or type(text) ~= "string" or text == "" then return false end
  self:leavePage()
  self._instance:setQuery(text)
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
  if not self._instance or type(prefix) ~= "string" or prefix == "" then return false end
  self._page = prefix
  self._instance:setQuery("")
  self._instance:setPlaceholder(title or "This list")
  return true
end

--- Launcher:isHostingList() -> bool
--- Method
--- Whether somebody else's list is showing rather than this catalog. Asked by whoever decides
--- whether to print the way back, so the way back is listed exactly while there is one.
function obj:isHostingList()
  return self._page ~= nil
end

--- Launcher:leavePage() -> bool
--- Method
--- Give the launcher its own list back, answering whether there was a page to leave. False is how
--- Backspace on an empty field stays an ordinary press when nothing is hosted.
function obj:leavePage()
  if not self._page then return false end
  self._page = nil
  if self._instance then
    self._instance:setQuery("")
    self._instance:setPlaceholder(self._placeholder)
  end
  return true
end

--- Launcher:refresh()
--- Method
--- Rebuild the list for the current query, keeping the highlight. A query source whose
--- answer arrives late calls this through the callback the root injects into it, so the
--- row appears without the user typing again. A no op while the launcher is closed.
function obj:refresh()
  if self._instance and self._instance:isShowing() then
    self._instance:refresh()
  end
end

--- Launcher:_runItem(it)
--- Method
--- The one dispatcher. Maps a row descriptor back to a call. The launcher owns the
--- kind switch; the leaf calls are injected, so it names no domain spoon. Window
--- actions come straight from the injected windowActions table.
function obj:_runItem(it)
  if not it then return end
  local a = self._actions
  if it.kind == "app" then
    if a.app then a.app(it.bundleID, it.url) end
  elseif it.kind == "window" then
    local fn = self._windowActions[it.name]
    if fn then fn() end
  elseif it.kind == "capture" then
    if a.capture then a.capture(it.name) end
  elseif it.kind == "special" then
    -- Two sources, not a leak. A name the registry answers is a tool, and everything left
    -- in actions.special is a bare command with no tool behind it, so one lookup for each
    -- is honest rather than one pretending every special row is a plugin. The registry is
    -- asked first and only a name it does not run falls through to actions.special, which
    -- registration itself makes safe, since a name cannot be claimed by both.
    local ran = self._registry and self._registry.run(it.name)
    if not ran then
      local fn = a.special and a.special[it.name]
      if fn then fn() end
    end
  elseif it.kind == "settingsPane" then
    if a.settingsPane then a.settingsPane(it.url) end
  elseif it.kind == "calc" then
    -- A computed result is put somewhere useful by an injected action, so the launcher
    -- does not learn what a clipboard is, exactly as it does not learn what an app or a
    -- capture is. A pending row carries no value and is disabled, so it never arrives.
    if it.value and a.copy then a.copy(it.value) end
  elseif it.kind == "scope" then
    -- A row that came from a source claiming the query. It carries the name of whatever
    -- made it plus that thing's own descriptor, and an injected action hands both back, so
    -- the launcher routes the row without learning which tool it belongs to or what the
    -- payload inside it means, exactly as it does for a computed result.
    if a.scope then a.scope(it) end
  end
end

--- Launcher:start()
--- Method
--- Begin owning live state. Load the persisted recency order, fed only by
--- launcher picks. The watcher refreshes the running set on activation,
--- launch, and termination, and invalidates the cached rows, so app rows
--- track the machine without rescanning on every open. Idempotent.
function obj:start()
  if self._appRowsWatcher then return self end
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
  return self
end

--- Launcher:stop()
--- Method
--- Stop the app watcher and drop the caches.
function obj:stop()
  if self._appRowsWatcher then
    self._appRowsWatcher:stop()
    self._appRowsWatcher = nil
  end
  self._appRowsCache = nil
  self._orderedRowsCache = nil
  return self
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
--- done. Three details are load bearing. It is set after the show, because showing clears the
--- field. It is followed by a refresh, because setting a chooser's query does not fire the
--- callback that rebuilds the rows, so without it the field would read one thing and the list
--- would show another. And the refresh resets the highlight to the top, which is right for a
--- list the user has not seen yet.
function obj:show(query)
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
  if not self._instance then return end
  -- Every open starts on this catalog with this placeholder, whatever list the previous open was
  -- left hosting when it closed. Done before the show, since showing builds the first rows.
  self:leavePage()
  self._instance:show()
  if query and query ~= "" then
    self._instance:setQuery(query)
    self._instance:refresh(true)
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
--- Whether the launcher chooser is open. Safe before configure.
function obj:isShowing()
  return self._instance ~= nil and self._instance:isShowing()
end

--- Launcher:surface()
--- Method
--- The dot-called navigation adapter, for the root to register in its shared
--- choosers list.
function obj:surface()
  return self._surface
end

return obj
