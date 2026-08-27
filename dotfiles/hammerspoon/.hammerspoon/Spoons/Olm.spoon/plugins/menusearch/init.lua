--- === MenuSearch ===
---
--- Lists every enabled menu bar item of an app and runs the chosen one. macOS exposes each
--- app's menus through the Accessibility API, which hs.application:getMenuItems reads, the
--- callback form doing the tree walk off the main thread so a large menu never blocks
--- Hammerspoon. That walk is also the whole of what made this tool feel slow, fifty to five
--- hundred and fifty milliseconds by app depending on how much a menu tree holds, paid again
--- on every single open before this file ever showed a row.
---
--- Migrated onto host/stage, phase five of the chooser stage build, docs/PLAN-CHOOSER-STAGE.md.
--- This file owns no chooser of its own any more, builds no window, and wires no docked panel
--- by hand. Its rows and its selection dispatch are named on the manifest's own presentation
--- block instead of handed to a Chooser.new call this file no longer makes, following VPN's own
--- migration exactly. Its leader key still opens it, through cfg.stagePresent, the root
--- published word every presenting plugin's own hotkey door shares.
---
--- Paired with that migration, and built as one step with it per docs/BRIEF-MENUSEARCH-CACHE.md,
--- is the reason the migration was promoted ahead of every other plugin still waiting its turn.
--- A per app snapshot on disk, paths and shortcut glyphs only, is what an open draws from
--- instantly, never waiting on the accessibility walk. That walk still runs, in the background,
--- on every open, and when it lands its answer is compared directly against what is already on
--- screen. Equal means nothing happens, not even a redraw. Different means a quiet correction,
--- a newly appeared item is appended at the bottom, an item that vanished is dimmed in place
--- through the same disabled row style a first ever open already shows, and nothing above the
--- highlight ever moves, since neither an append nor an in place dim can shift anything that was
--- already there. The correction defers whenever the highlight has moved off row one, since a
--- list a person is part way down should not visibly change under them, applying instead as the
--- next open's own starting point, a fresh open always landing back on row one being exactly the
--- gate the deferred correction was waiting on. host/stage's own Stage:selectedRow, reached
--- through the root published stageSelectedRow, is what answers whether the highlight has
--- moved, a plain row number rather than an item, since the question is only ever "is it still
--- row one" and never which item happens to sit there.
---
--- Two doors used to run two separate reads, this plugin's own hotkey and the launcher's scope.
--- Both now converge on one function, openApp below, the one source owning the disk read, the
--- in memory snapshot, the recency ordering, and the deferred correction, with the presentation
--- and the scope as its two consumers, decision four of the cache brief. State is kept in one
--- table per bundle id rather than per open, so a hotkey open and a scope open of the same app
--- share the identical entry, and a background read that lands after its own open has already
--- closed still updates that app's own standing snapshot for whichever door opens it next.
---
--- Recency is per app, decision three, one lib/recency instance per bundle id, built lazily and
--- keyed by the joined menu path, since a shared instance across every app would prune one app's
--- own dead paths using a different app's own fresh read. The sort it drives applies once, when
--- an open's own display list is first built from the standing snapshot, never again while that
--- list is up, so a live correction only ever appends and dims, it never reshuffles what recency
--- already settled for this open.
---
--- Dead snapshots are swept as hygiene, decision five, a few minutes after this plugin's first
--- open of any app this Hammerspoon load, never on the open path itself. A file whose bundle id
--- no longer resolves to an installed app, or one untouched for sixty days, is removed.
---
--- Every row carries only a serializable descriptor, its menu path as a list of titles, never a
--- function, since hs.chooser serialises each row and would silently drop a function. The chosen
--- item still runs deferred, after the chooser tears down and macOS restores focus to the
--- captured app, since a menu action acts on that app and this is genuine world dispatch, the
--- one piece of this file that was never a caching question.
---
--- This is the olm side extraction of menu search, made the seventh of August 2026, and this
--- migration and cache build the twenty seventh.

local obj = {}
obj.__index = obj

obj.name = "MenuSearch"
obj.version = "2.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local cfg = nil -- injected collaborators, coveredApp, refreshLauncher, recencyLib, storage,
                 -- stagePresent, redrawPresented, stageSelectedRow, after

-- Deferred hygiene, decision five of the cache brief, never paid on the open path.
local PRUNE_DELAY = 300  -- five minutes into this Hammerspoon load's first open, plenty of
                          -- runway for the open itself to have long since drawn its rows
local STALE_DAYS = 60

--------------------------------------------------------------------------------
-- Menu shapes shared by the disk cache, the fresh accessibility read, and both row suppliers
--------------------------------------------------------------------------------

-- hs decodes AXMenuItemCmdModifiers into a list of modifier names (e.g. { "cmd" }
-- or { "cmd", "shift" }). Turn it plus the command char into a readable glyph for
-- the row subtitle, in the canonical ⌃⌥⇧⌘ order, or nil when the item has no
-- keyboard shortcut. Both alt/option and ctrl/control spellings are accepted.
local function menuShortcutGlyph(char, mods)
  if not char or char == "" then return nil end
  local has = {}
  for _, m in ipairs(mods or {}) do has[tostring(m):lower()] = true end
  local g = ""
  if has.ctrl or has.control then g = g .. "⌃" end
  if has.alt or has.option then g = g .. "⌥" end
  if has.shift then g = g .. "⇧" end
  if has.cmd or has.command then g = g .. "⌘" end
  return g .. char:upper()
end

-- The one identity a menu item ever has, for the disk cache, the live correction diff, and
-- recency alike. A joined path rather than the title alone, since two different menus can
-- share a leaf title, File and a submenu both offering New for instance, and only the full
-- path tells them apart. The unit separator, not a space or an arrow, so a title that happens
-- to contain either never collides with the join itself.
local PATH_SEP = "\31"
local function pathKey(path)
  return table.concat(path, PATH_SEP)
end

-- The leaf title and the parent trail, both derived from a path rather than carried
-- separately, since a path already says both and a second copy is only ever a second place
-- for them to disagree once an app renames a menu.
local function titleAndParents(path)
  local n = #path
  local parents = {}
  for i = 1, n - 1 do parents[i] = path[i] end
  return path[n], table.concat(parents, " ▸ ")
end

local function subtitleFor(parents, shortcut)
  if shortcut then
    return (parents ~= "" and (parents .. "   ") or "") .. shortcut
  end
  return parents
end

-- Flatten the nested AX menu tree into leaf descriptors. An entry's submenu is its
-- AXChildren[1] (a list); an entry with one is a container recursed into, an entry without is
-- a runnable leaf. Blank title entries (separators) are skipped, and disabled items are
-- dropped so the list stays actionable, which is also why enabled state is never part of what
-- either the disk cache or a fresh read carries, only paths and shortcuts, decision one of the
-- cache brief. Every leaf this walk answers was enabled the moment it was asked.
local function flattenMenus(entries, path, out)
  for _, e in ipairs(entries) do
    local title = e.AXTitle
    if title and title ~= "" then
      local kids = e.AXChildren and e.AXChildren[1]
      local newPath = {}
      for i = 1, #path do newPath[i] = path[i] end
      newPath[#newPath + 1] = title
      if type(kids) == "table" and #kids > 0 then
        flattenMenus(kids, newPath, out)
      elseif e.AXEnabled ~= false then
        out[#out + 1] = { path = newPath, shortcut = menuShortcutGlyph(e.AXMenuItemCmdChar, e.AXMenuItemCmdModifiers) }
      end
    end
  end
end

-- Row descriptors, shared by the picker's own presentation and the launcher's scope, so the
-- two present a menu item identically and cannot drift. Extra fields beyond what hs.chooser
-- itself reads, iconKey and shortcut, ride along on the row table the same harmless way this
-- plugin's own iconKey always has, one for icon memoisation and one this file's own live
-- correction reads back later to tell an unchanged shortcut from a changed one.
local function buildRow(r, icon, iconKey)
  local title, parents = titleAndParents(r.path)
  return {
    title = title,
    subTitle = subtitleFor(parents, r.shortcut),
    image = icon,
    iconKey = iconKey,
    item = { path = r.path },
    filterText = title .. " " .. parents,
    enabled = true,
    shortcut = r.shortcut,
  }
end

local function buildRows(list, icon, iconKey)
  local out = {}
  for _, r in ipairs(list or {}) do out[#out + 1] = buildRow(r, icon, iconKey) end
  return out
end

-- The one row shown while a first ever read for this app is still in flight, no disk snapshot
-- and nothing yet drawn to correct. filterText carries whatever was typed so the shared
-- matcher can never rank this row away while it is the only thing there is to show.
local function readingRow(entry, filterText)
  local app = entry and entry.app
  return {
    title = "Reading the menus",
    subTitle = (app and app:name() or "this app") .. ", one moment",
    glyph = "⏳",
    enabled = false,
    filterText = filterText or "",
  }
end

--------------------------------------------------------------------------------
-- The snapshot cache on disk, one json file per bundle id
--------------------------------------------------------------------------------

local function snapshotPath(bundleId)
  return cfg.storage.cacheDir("menusearch") .. "/" .. bundleId .. ".json"
end

local function loadSnapshot(bundleId)
  local path = snapshotPath(bundleId)
  if not hs.fs.attributes(path) then return nil end
  local data = hs.json.read(path)
  if type(data) == "table" and type(data.items) == "table" then return data.items end
  return nil
end

local function saveSnapshot(bundleId, items)
  hs.json.write({ items = items }, snapshotPath(bundleId), true, true)
end

--------------------------------------------------------------------------------
-- Recency, one lib/recency instance per bundle id, built lazily
--------------------------------------------------------------------------------

local recencyByApp = {}
local function recencyFor(bundleId)
  if not cfg.recencyLib then return nil end
  local r = recencyByApp[bundleId]
  if not r then
    r = cfg.recencyLib.new({ settingsKey = "olm.recency.menuSearch." .. bundleId })
    recencyByApp[bundleId] = r
  end
  return r
end

-- Applied once, when an open's own display list is first built from the standing snapshot,
-- decision three of the cache brief. Never called again while that list is up, which is what
-- keeps a live correction to an append and an in place dim rather than a reshuffle.
local function sortForOpen(entry, items)
  local recency = recencyFor(entry.bundleId)
  if not recency then return items end
  return recency.order(items, function(r) return pathKey(r.path) end)
end

--------------------------------------------------------------------------------
-- Per app state, one entry per bundle id, the one source every consumer reads
--------------------------------------------------------------------------------

local entriesByBundle = {}

-- An app Launch Services never gave a bundle id is rare and has no identity stable across a
-- relaunch. The pid at least keeps this session's own cache and recency from colliding with a
-- different app that also has none, and the prune sweep drops a file keyed this way quickly,
-- since pathForBundleID can never resolve a pid shaped id back to an installed app.
local function bundleIdFor(app)
  local id = app:bundleID()
  if id and id ~= "" then return id end
  return "noBundle:" .. tostring(app:pid())
end

-- Merge a fresh read into an entry's own display list without disturbing anything already on
-- screen, decision as agreed in the cache brief's own mechanism section. A survivor keeps its
-- exact position and picks up whatever changed about it, a shortcut most likely. An item the
-- fresh read no longer has is dimmed in place, enabled false, rather than removed, so nothing
-- below it shifts. A genuinely new item is appended at the bottom, in the fresh read's own
-- order. No recency pass runs here, that already happened once when this open's own display
-- list was first built.
local function mergeFresh(entry, freshList)
  local freshByKey = {}
  for _, r in ipairs(freshList) do freshByKey[pathKey(r.path)] = r end
  local seen = {}
  for _, row in ipairs(entry.rows or {}) do
    local key = pathKey(row.item.path)
    local fresh = freshByKey[key]
    if fresh then
      seen[key] = true
      row.enabled = true
      row.shortcut = fresh.shortcut
      local title, parents = titleAndParents(fresh.path)
      row.title = title
      row.subTitle = subtitleFor(parents, fresh.shortcut)
      row.filterText = title .. " " .. parents
    else
      row.enabled = false
    end
  end
  for _, r in ipairs(freshList) do
    local key = pathKey(r.path)
    if not seen[key] then
      entry.rows[#entry.rows + 1] = buildRow(r, entry.icon, entry.iconKey)
      seen[key] = true
    end
  end
end

-- Whether a fresh read matches exactly what is already live on screen, decision two of the
-- cache brief, no checksum, the two lists are already in memory so a direct compare costs
-- nothing next to the walk that produced them. Only the live, enabled rows count, an item
-- already dimmed by an earlier correction has already told its own story once. Order is
-- deliberately not part of this comparison, since the display list is recency sorted and a
-- fresh read is not, so a sequence compare would read every open as changed even when nothing
-- moved. false is stored in place of a nil shortcut so a present key with no shortcut can
-- never be confused with an absent one, a plain table cannot tell those two apart by indexing
-- alone.
local function sameAsLive(entry, freshList)
  local live, count = {}, 0
  for _, row in ipairs(entry.rows or {}) do
    if row.enabled ~= false then
      live[pathKey(row.item.path)] = row.shortcut or false
      count = count + 1
    end
  end
  if count ~= #freshList then return false end
  for _, r in ipairs(freshList) do
    local seen = live[pathKey(r.path)]
    if seen == nil or seen ~= (r.shortcut or false) then return false end
  end
  return true
end

-- Where a landed background read is actually reconciled against an entry's own state. Runs
-- for every app this plugin has ever opened, whether or not anything is showing right now, so
-- an app's own standing snapshot keeps repairing itself between opens at no cost, decision
-- three's own prune line among them.
local function onLanded(entry, freshList)
  local recency = recencyFor(entry.bundleId)
  if recency then
    local keys = {}
    for _, r in ipairs(freshList) do keys[#keys + 1] = pathKey(r.path) end
    -- Pruned against THIS read's own path set, the confirmed live truth, rather than against
    -- whatever the display list happens to be built from right now, which may still be a
    -- stale snapshot from disk. Decision three, "the fresh read's own path set feeds prune".
    recency.prune(keys)
  end

  if not entry.snapshot then
    -- The first read this app has ever answered, this session or ever on disk. Nothing to
    -- compare it against and nothing on screen to preserve, so this plants the baseline
    -- rather than correcting one.
    entry.snapshot = freshList
    entry.rows = buildRows(sortForOpen(entry, freshList), entry.icon, entry.iconKey)
    saveSnapshot(entry.bundleId, freshList)
    if entry.notify then entry.notify() end
    return
  end

  if sameAsLive(entry, freshList) then return end

  local atRowOne = true
  if cfg.stageSelectedRow then
    local row = cfg.stageSelectedRow()
    if row then atRowOne = (row == 1) end
  end

  if not atRowOne then
    -- Somebody is already looking part way down the list. The correction is not lost, it
    -- waits as this app's own next baseline, since a fresh open always lands back on row
    -- one, which is exactly the gate this deferral is waiting on, decision as agreed.
    entry.pendingFresh = freshList
    return
  end

  mergeFresh(entry, freshList)
  entry.snapshot = freshList
  saveSnapshot(entry.bundleId, freshList)
  if entry.notify then entry.notify() end
end

-- Kicks the background accessibility walk for this entry unless one is already running. Off
-- the main thread by construction, hs.application:getMenuItems's own callback form, so this
-- never blocks the open that asked for it.
local function beginRead(entry)
  if entry.reading or not entry.app then return end
  entry.reading = true
  local app = entry.app
  app:getMenuItems(function(menus)
    entry.reading = false
    -- The answer can land after the app has quit or after this open has long since moved
    -- on. There is no one left to redraw in that case, onLanded's own notify simply does
    -- nothing, but the read is still worth keeping, the next open of this same app reads
    -- it fresh off entry.snapshot regardless of who was watching when it arrived.
    local fresh = {}
    if menus then flattenMenus(menus, {}, fresh) end
    onLanded(entry, fresh)
  end)
end

-- Deferred hygiene, decision five, scheduled once per Hammerspoon load, on this plugin's own
-- first open of any app, never at load time and never on the open path itself.
local pruneScheduled, pruneTimer = false, nil
local function pruneDeadSnapshots()
  local dir = cfg.storage.cacheDir("menusearch")
  local ok, iter, dirObj = pcall(hs.fs.dir, dir)
  if not ok or not iter then return end
  local cutoff = os.time() - STALE_DAYS * 24 * 60 * 60
  for name in iter, dirObj do
    if name:sub(-5) == ".json" then
      local bundleId = name:sub(1, -6)
      local full = dir .. "/" .. name
      -- pathForBundleID answers an empty string, never nil, for a bundle id it cannot
      -- place, so both are checked, the same idiom lib/deps.lua and tmuxsessions already
      -- read it by.
      local installed = hs.application.pathForBundleID(bundleId)
      local mtime = hs.fs.attributes(full, "modification")
      if installed == nil or installed == "" or (mtime and mtime < cutoff) then
        os.remove(full)
      end
    end
  end
end
local function scheduleFirstUsePrune()
  if pruneScheduled then return end
  pruneScheduled = true
  pruneTimer = hs.timer.doAfter(PRUNE_DELAY, pruneDeadSnapshots)
end

-- The one source, decision four of the cache brief. Called at the start of a fresh open of
-- this app's menus, whichever door asked, folding in whatever a deferred correction left
-- waiting from the last open, since a fresh open always lands on row one, rebuilding the
-- display list from the standing snapshot so a previous open's own live only dimming and
-- appending never bleeds into this one, and starting this open's own background read. notify
-- is how THIS open wants to be told a later correction landed, cfg.redrawPresented for the
-- picker or cfg.refreshLauncher for the scope, kept on the entry rather than decided here,
-- since only one of the two can genuinely be on screen at a time.
local function openApp(bundleId, app, notify)
  scheduleFirstUsePrune()
  local entry = entriesByBundle[bundleId]
  if not entry then
    entry = {
      bundleId = bundleId,
      icon = hs.image.imageFromAppBundle(bundleId),
      iconKey = "menuapp:" .. bundleId,
      snapshot = loadSnapshot(bundleId),
      reading = false,
    }
    entriesByBundle[bundleId] = entry
  end
  entry.app = app
  entry.notify = notify
  if entry.pendingFresh then
    entry.snapshot = entry.pendingFresh
    entry.pendingFresh = nil
    saveSnapshot(bundleId, entry.snapshot)
  end
  entry.rows = entry.snapshot and buildRows(sortForOpen(entry, entry.snapshot), entry.icon, entry.iconKey) or nil
  beginRead(entry)
  return entry
end

--------------------------------------------------------------------------------
-- The picker, this plugin's own presentation
--------------------------------------------------------------------------------

local pickerEntry = nil -- which entry this plugin's own presentation is currently showing

local function menuSearchRows(query)
  if not pickerEntry then return {} end
  return pickerEntry.rows or { readingRow(pickerEntry, query) }
end

-- Acts on the app the open captured, never on whatever is frontmost when the row runs, since
-- showing the chooser takes focus and by the time a selection completes the frontmost app is
-- this one. Deferred, genuine world dispatch, so the picker has torn down and focus has
-- actually returned to the target app before its own menu item is asked to run, unchanged by
-- either half of this migration.
local function menuSearchSelect(item)
  if not (item and item.path and pickerEntry and pickerEntry.app) then return end
  local app = pickerEntry.app
  local recency = recencyFor(pickerEntry.bundleId)
  if recency then recency.touch(pathKey(item.path)) end
  cfg.after(0.1, function() app:selectMenuItem(item.path) end)
end

-- Resolved once, at register, per the presentation contract, so a plain static string is all
-- this needs to answer.
local function menuSearchPlaceholder()
  return "Search menu items"
end

-- The presentation contract's own onPresent, called whenever this plugin's own presentation
-- becomes current, before the window itself is shown or swapped into. Captures the frontmost
-- app, the dispatch target, and opens its entry, which draws the standing snapshot instantly
-- and starts this open's own background read without blocking the swap that is about to
-- happen, VPN's own onPresent, phase three review finding eleven, being the identical shape.
local function menuSearchOnPresent()
  local app = hs.application.frontmostApplication()
  if not app then
    pickerEntry = nil
    return
  end
  pickerEntry = openApp(bundleIdFor(app), app, function()
    if cfg.redrawPresented then cfg.redrawPresented("menuSearch") end
  end)
end

-- The hotkey door, decision one of the handoff brief, the only remaining caller being the key
-- registry.open binds directly. cfg.stagePresent asks the registry for this plugin's own
-- presentation and hands it to the stage, which calls menuSearchOnPresent above before the
-- window itself is touched.
local function openMenuSearch()
  if cfg.stagePresent then cfg.stagePresent("menuSearch") end
end

--------------------------------------------------------------------------------
-- The launcher's menu scope, unchanged in shape, now drawing from the same one source
--------------------------------------------------------------------------------

-- A fresh (app, openId) pair is what tells this apart from every other keystroke of the same
-- launcher open, the identical shape the retired per open state kept before this migration,
-- since scopeMenuRows is asked again on every keystroke and must not reopen the app each
-- time.
local scopeSeen = { app = nil, openId = nil }
local scopeEntry = nil

-- The launcher's menu scope. It lists the menus of the app the launcher covered rather than
-- the frontmost one, since once the chooser is up the frontmost app is this one, which is why
-- the launcher hands over both that app and an id for the open. A read in flight, or no
-- snapshot yet, shows as one disabled row, so the list says what it is doing rather than
-- briefly claiming nothing matched.
local function scopeMenuRows(rest)
  local app, openId = cfg.coveredApp()
  if not app then return {} end
  if app ~= scopeSeen.app or openId ~= scopeSeen.openId then
    scopeSeen.app, scopeSeen.openId = app, openId
    scopeEntry = openApp(bundleIdFor(app), app, function()
      if cfg.refreshLauncher then cfg.refreshLauncher() end
    end)
  end
  return scopeEntry.rows or { readingRow(scopeEntry, rest) }
end

-- Acts on the app the read was for, not on whatever is frontmost when the row runs, so a menu
-- item can never be sent to the wrong app. No deferral of its own, the launcher already defers
-- a scope's own run by a beat before calling this.
local function scopeMenuRun(payload)
  if not (scopeEntry and scopeEntry.app and payload and payload.path) then return end
  local recency = recencyFor(scopeEntry.bundleId)
  if recency then recency.touch(pathKey(payload.path)) end
  scopeEntry.app:selectMenuItem(payload.path)
end

--------------------------------------------------------------------------------

--- MenuSearch:init()
--- Method
--- Initialize the plugin. Returns self and does no side effects.
function obj:init()
  return self
end

--- MenuSearch:configure(opts)
--- Method
--- Configure with every collaborator this plugin needs, opts.coveredApp and opts.refreshLauncher
--- from the launcher, opts.recencyLib the raw recency module this plugin builds its own per app
--- instances from, opts.storage the path mechanism its snapshots are written under,
--- opts.stagePresent, opts.redrawPresented and opts.stageSelectedRow the three root published
--- words the stage migration and the cache both lean on, and opts.after the root's deferred call
--- helper. Assigns the public surface, the open action, and the launcher's two menu scope
--- functions, all as plain dot called closures. Returns self.
function obj:configure(opts)
  cfg = opts or {}
  -- Required exactly the way VPN's own opts.recency is, rejected loudly rather than left to
  -- fail quietly three calls later inside loadSnapshot the first time an open actually
  -- reaches for it. The manifest already declares storage required, so this is a second,
  -- structural guard rather than the only one, the same discipline the manifest's own
  -- comment names.
  if not cfg.storage then
    error("MenuSearch configure requires opts.storage, lib/storage.lua's own cacheDir mechanism, the disk half of an open that never waits on the accessibility walk")
  end
  cfg.storage.ensure(cfg.storage.cacheDir("menusearch"))

  self.open = openMenuSearch
  self.rows = menuSearchRows
  self.select = menuSearchSelect
  self.placeholder = menuSearchPlaceholder
  self.onPresent = menuSearchOnPresent

  self.scopeRows = scopeMenuRows
  self.scopeRun = scopeMenuRun

  return self
end

return obj
