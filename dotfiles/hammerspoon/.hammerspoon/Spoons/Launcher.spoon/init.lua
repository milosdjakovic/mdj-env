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
--- the docked shortcut panel callbacks, and a small dispatch of leaf actions that
--- do name the domain spoons. So the launcher owns the row building, the matching,
--- the app enumeration, and the command dispatch structure, and knows nothing
--- about what a row ultimately does.
---
--- The Command pattern is preserved. Each row carries only a serializable
--- descriptor, its kind plus a name or bundle id, never a function, because the
--- Chooser hands each row to hs.chooser which serialises it and would drop a
--- function. runItem turns that descriptor back into the injected call.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Launcher"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

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
obj._actions = nil          -- leaf dispatch: app, capture, settingsPane, special

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

-- App enumeration roots and the depth guard against a symlink-looped tree.
local APP_DIRS = {
  "/Applications",
  "/System/Applications",
  os.getenv("HOME") .. "/Applications",
}
local APP_SCAN_MAX_DEPTH = 4

-- Unified recency ordering. Every row kind shares one most-recently-used
-- timeline, keyed by a kind-qualified item key (see recencyKey), so the last
-- thing used bubbles to the top whether it was an app or a command. Two observers
-- feed it with equal weight: an app activation (the same signal Command+Tab
-- follows, so open+Enter still lands on the last app) and any launcher selection.
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

  self._glyphIconCache = {}

  -- Static rows, built once now that the deps are in. Apps are built live per open
  -- (their running state changes), so they are not here.
  self._actionRows = self:_buildActionRows()
  self._settingsPaneRows = self:_buildSettingsPaneRows()
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
        hs.timer.doAfter(0.1, function() self:_runItem(item) end)
      end
    end,
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

--- Launcher:_buildActionRows()
--- Method
--- The static action rows. Each is { title, subTitle, image, item, when? } where
--- item is a serializable descriptor for the dispatcher.
function obj:_buildActionRows()
  local keys = self._keys
  local rows = {}
  local function add(title, subTitle, item, glyph, when)
    rows[#rows + 1] = { title = title, subTitle = subTitle, image = self:_glyphIcon(glyph), item = item, when = when }
  end
  -- Window actions share one glyph, the chord in the subtitle tells them apart;
  -- capture and the system actions get a per-action one.
  local captureGlyphs = { ocrArea = "🔤", captureArea = "📸", captureAreaClipboard = "📸", recordArea = "🎥" }
  add(keys.colorPicker.description, "Tools · " .. self:_chordLabel("Hyper", keys.colorPicker.key), { kind = "special", name = "colorPicker" }, "🎨")
  add(keys.emoji.description, "Tools · " .. self:_chordLabel("Hyper", keys.emoji.key), { kind = "special", name = "emoji" }, "😀")
  for _, c in ipairs(keys.capture) do
    add(c.description or humanize(c.action), "Capture · " .. self:_chordLabel("Hyper", c.key, c.mods),
      { kind = "capture", name = c.action }, captureGlyphs[c.action] or "📸")
  end
  add(keys.caffeinate.description, "System · " .. self:_chordLabel("Hyper", keys.caffeinate.key), { kind = "special", name = "caffeinate" }, "☕")
  add(keys.vpn.description, "Network · " .. self:_chordLabel("Hyper", keys.vpn.key), { kind = "special", name = "vpn" }, "🌐")
  add(keys.clipboardHistory.description, "Clipboard · " .. self:_chordLabel("Hyper", keys.clipboardHistory.key), { kind = "special", name = "clipboard" }, "📋")
  -- Display profiles has no dedicated chord, it opens from here only, so its subtitle names
  -- what it does rather than a shortcut. The two display commands sit under a Displays
  -- category rather than System, so their subtitle does not read like the "System Settings"
  -- subtitle the Displays settings pane row carries.
  if keys.displayProfiles then
    add(keys.displayProfiles.description, "Displays · inspect and manage arrangements", { kind = "special", name = "displayProfiles" }, "🖥️")
  end
  add("Search Settings", "System · opens the System Settings search field", { kind = "special", name = "searchSettings" }, "🔍")
  add("Overlay Display", "Displays · where panels and choosers appear", { kind = "special", name = "overlayDisplay" }, "🖥️")
  -- Text case has no dedicated chord, it opens from here only, so its subtitle names what
  -- it does rather than a shortcut.
  if keys.textCase then
    add(keys.textCase.description, "Text · recase the selection in place", { kind = "special", name = "textCase" }, "🔠")
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

--- Launcher:_commandRows()
--- Method
--- The row supplier. Returns the full recency-ordered list and lets the atom's shared
--- matcher filter and rank it, exposing the visible text plus any hidden keywords as
--- filterText so a settings pane is still found by a synonym its name lacks. On the
--- empty query the atom keeps the recency order untouched, and when the user types, match
--- quality leads with recency breaking ties. Gated rows drop out live through the shared
--- predicate registry the window bindings use.
function obj:_commandRows(_)
  local out = {}
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
    local fn = a.special and a.special[it.name]
    if fn then fn() end
  elseif it.kind == "settingsPane" then
    if a.settingsPane then a.settingsPane(it.url) end
  end
end

--- Launcher:start()
--- Method
--- Begin owning live state. Load the persisted recency order and seed the current
--- frontmost app so the top row is right before the first switch. The watcher
--- promotes the activated app into the shared timeline and invalidates the cached
--- rows when the running set or the focused app changes, so the order tracks
--- Command+Tab without rescanning on every open. Idempotent.
function obj:start()
  if self._appRowsWatcher then return self end
  self._mru = hs.settings.get(MRU_SETTINGS_KEY) or {}
  self._orderedRowsCache = nil
  local front = hs.application.frontmostApplication()
  local frontID = front and front:bundleID()
  if frontID then self:_promote("app:" .. frontID) end
  self._appRowsWatcher = hs.application.watcher.new(function(_, event, app)
    if event == hs.application.watcher.activated then
      local id = app and app:bundleID()
      if id then self:_promote("app:" .. id) end -- also clears the ordered cache
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

--- Launcher:show()
--- Method
--- Open the launcher.
function obj:show()
  if self._instance then self._instance:show() end
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
