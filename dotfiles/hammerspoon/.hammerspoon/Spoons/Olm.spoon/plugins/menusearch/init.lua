--- === MenuSearch ===
---
--- Lists every menu bar item of an app and runs the chosen one. macOS exposes each
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
--- already settled for this open. Two windows sharing an identical title, the everyday case being
--- the Window menu, share an identical menu path too, which pathKey alone cannot tell apart, so
--- every identity this file builds, the disk compare, the live merge, and a recency touch alike,
--- runs through keyedList below, a path plus an occurrence count computed by walking a list in
--- its own order, so two same titled rows become two distinct identities rather than one that
--- silently absorbs the other.
---
--- Dead snapshots are swept as hygiene, decision five, a few minutes after this plugin's first
--- open of any app this Hammerspoon load, never on the open path itself. A file whose bundle id
--- no longer resolves to an installed app, or one untouched for sixty days, is removed, and its
--- own recency settings key is removed alongside it, so the two stores age out together rather
--- than one persisting a key nothing will ever prune again.
---
--- Every row carries only a serializable descriptor, its menu path as a list of titles, never a
--- function, since hs.chooser serialises each row and would silently drop a function. The chosen
--- item still runs deferred, after the chooser tears down and macOS restores focus to the
--- captured app, since a menu action acts on that app and this is genuine world dispatch, the
--- one piece of this file that was never a caching question.
---
--- This is the olm side extraction of menu search, made the seventh of August 2026, this
--- migration and cache build the twenty seventh, and the rework naming the three highs and four
--- mediums of that build's own adversarial review the same day.

local obj = {}
obj.__index = obj

obj.name = "MenuSearch"
obj.version = "2.1"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("MenuSearch", "info")

local cfg = nil -- injected collaborators, coveredApp, refreshLauncher, recencyLib, storage,
                 -- stagePresent, redrawPresented, stageSelectedRow, after

-- Deferred hygiene, decision five of the cache brief, never paid on the open path.
local PRUNE_DELAY = 300  -- five minutes into this Hammerspoon load's first open, plenty of
                          -- runway for the open itself to have long since drawn its rows
local STALE_DAYS = 60

-- A recency list nobody scrolls does not need to remember every menu item an app has ever
-- offered, review finding M4. Fifty is a generous ceiling for a list this shallow, and it
-- keeps every one of the settings keys this plugin ever writes small regardless of how large a
-- given app's own menu tree happens to be.
local RECENCY_LIMIT = 50

-- The written shape's own version, review finding L8. Bumping this the day the shape ever
-- changes is what lets a future read tell "this is not what I write" from "this predates the
-- field that would have said so", both of which must degrade identically, to nothing cached at
-- all, but only one of which this field can actually name.
local SNAPSHOT_VERSION = 1

-- The bound on the background accessibility walk, review finding H2, matching VPN's own
-- FETCH_TIMEOUT, comfortably past the worst the probe ever measured and short enough that a
-- wedged walk does not hold an app's own cache hostage for the rest of this Hammerspoon load.
local READ_TIMEOUT = 5

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

-- The joined menu path, used only as the raw material an identity is built from below, never
-- as an identity itself, review finding H1. Two different menus can share a leaf title, File
-- and a submenu both offering New for instance, and only the full path tells them apart, so the
-- join is by the unit separator rather than a space or an arrow, a title that happens to
-- contain either never colliding with it.
local PATH_SEP = "\31"
local function pathKey(path)
  return table.concat(path, PATH_SEP)
end

-- pathKey alone stops being an identity the moment an app's own menu genuinely repeats a full
-- path, which is the everyday case rather than a rare one, review finding H1. Two windows
-- sharing a title, two Finder windows both named Documents, two blank TextEdit documents, both
-- show up as identical leaves under Window. Walking a list in its own order and appending how
-- many times a path and shortcut pair has already been seen turns that collision into two
-- distinct keys, first Documents and second Documents, so a set built from these keys is
-- already a multiset in effect, one entry per real row rather than one per distinct path. The
-- shortcut rides inside the grouping itself, review finding N4, rather than only on the row
-- built from it, since two leaves that share a path but not a shortcut are not really
-- duplicates of one another and grouping them as though they were let an unstable walk order
-- hand one leaf's shortcut to the other's key from one read to the next, reading as changed
-- and back with nothing visibly different. Grouping by path and shortcut together means an
-- occurrence index only ever has to break a tie between leaves that are genuinely
-- interchangeable, identical in every field this file reads, which is the one case H1's own
-- review already found harmless at dispatch. The index is recomputed fresh from a list's own
-- order every time rather than persisted, since order survives the json round trip untouched
-- and a derived value is one less thing that could ever disagree with what produced it. Every
-- caller that needs an identity, the live and fresh comparison, the merge, and a recency
-- touch, reads r.key from this rather than recomputing pathKey on its own.
local function keyedList(list)
  local seen, out = {}, {}
  for _, r in ipairs(list or {}) do
    local base = pathKey(r.path) .. PATH_SEP .. (r.shortcut or "")
    seen[base] = (seen[base] or 0) + 1
    out[#out + 1] = { path = r.path, shortcut = r.shortcut, key = base .. "#" .. seen[base] }
  end
  return out
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
-- a runnable leaf. Blank title entries (separators) are skipped, and that is the only filter.
-- Disabled leaves used to be dropped here too and no longer are, because the enabled state
-- accessibility answers is only honest while the app owns the menu bar, a read of a background
-- app reports nearly everything disabled, and it flips constantly besides, Undo and Paste,
-- which is exactly why decision one of the cache brief never let it into the snapshot. So
-- neither the disk cache nor a fresh read carries it, only paths and shortcuts, every leaf
-- becomes a row, and a chosen item that is genuinely disabled when it runs simply does
-- nothing, the same answer the menu bar itself gives a click on a dimmed item.
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
      else
        out[#out + 1] = { path = newPath, shortcut = menuShortcutGlyph(e.AXMenuItemCmdChar, e.AXMenuItemCmdModifiers) }
      end
    end
  end
end

-- Row descriptors, shared by the picker's own presentation and the launcher's scope, so the
-- two present a menu item identically and cannot drift. r is a keyedList element, path,
-- shortcut and key. item carries key alongside the real path, so a chosen row can touch the
-- right occurrence's own recency slot rather than one every duplicate shares, review finding
-- H1's own second half. iconKey and the plain shortcut and key fields beyond what hs.chooser
-- itself reads ride along on the row table the same harmless way this plugin's own iconKey
-- always has, kept for the live correction to read back later.
local function buildRow(r, icon, iconKey)
  local title, parents = titleAndParents(r.path)
  return {
    title = title,
    subTitle = subtitleFor(parents, r.shortcut),
    image = icon,
    iconKey = iconKey,
    item = { path = r.path, key = r.key },
    filterText = title .. " " .. parents,
    enabled = true,
    shortcut = r.shortcut,
    key = r.key,
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
-- Bundle id to filename, sanitized both ways
--------------------------------------------------------------------------------

-- CFBundleIdentifier is whatever an app's own Info.plist declares under it, reverse DNS by
-- convention and never by enforcement, review finding M2. A slash, or a run of dots that
-- forms a parent directory reference, would otherwise let a hostile or merely broken plist
-- steer a write outside the cache directory entirely. Every character outside the plainly safe
-- set is percent encoded, the identical escape a URL uses, which is reversible, so the sweep
-- below can turn a filename back into the bundle id it names.
local function encodeBundleId(bundleId)
  return (bundleId:gsub("[^%w%.%-_]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function decodeBundleId(name)
  return (name:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

--------------------------------------------------------------------------------
-- The snapshot cache on disk, one json file per bundle id
--------------------------------------------------------------------------------

local function snapshotPath(bundleId)
  return cfg.storage.cacheDir("menusearch") .. "/" .. encodeBundleId(bundleId) .. ".json"
end

-- Every element a loaded snapshot claims to hold, checked before this plugin trusts a single
-- one of them, review finding H3. A path must be a list of at least one string, since an
-- empty or malformed one is exactly what titleAndParents would otherwise raise on trying to
-- read a leaf title from, and a shortcut, when present at all, must be a string. The brief's
-- own sentence is explicit that a bad store must fail toward the empty first open, never
-- toward a raise on the open path, and this is the whole of what makes that true regardless of
-- how the file came to hold something this plugin never wrote.
local function validItems(items)
  if type(items) ~= "table" then return false end
  for _, r in ipairs(items) do
    if type(r) ~= "table" or type(r.path) ~= "table" or #r.path < 1 then return false end
    for _, part in ipairs(r.path) do
      if type(part) ~= "string" then return false end
    end
    if r.shortcut ~= nil and type(r.shortcut) ~= "string" then return false end
  end
  return true
end

-- A file that fails to parse at all already answers nil safely through hs.json.read, the house
-- idiom three other stores in this tree already lean on. A file that parses as a table but not
-- as this plugin's own shape, a version mismatch or an element that fails validItems, is the
-- one case review finding H3 names, and it is removed here rather than left to fail the
-- identical check on every future open of this same app, since nothing about a file in that
-- state will ever become valid on its own.
local function loadSnapshot(bundleId)
  local path = snapshotPath(bundleId)
  if not hs.fs.attributes(path) then return nil end
  local data = hs.json.read(path)
  if type(data) ~= "table" then return nil end
  if data.version == SNAPSHOT_VERSION and validItems(data.items) then
    return data.items
  end
  local ok = os.remove(path)
  if not ok then
    log.w("could not remove a malformed snapshot at " .. path .. ", the same file will fail the identical check on the next open too")
  end
  return nil
end

local function saveSnapshot(bundleId, items)
  hs.json.write({ version = SNAPSHOT_VERSION, items = items }, snapshotPath(bundleId), true, true)
end

-- Review finding six. A landed read that finds the snapshot already true still has to advance
-- the file's own clock, or the sixty day sweep measures how long ago the menu last CHANGED
-- rather than how long ago it was last USED, and a stable app opened daily would still age out
-- from underneath a person who never stopped using it. hs.fs.touch, LuaFileSystem's own touch,
-- is used when this Hammerspoon build carries it. A build that does not is answered by reading
-- the file back and writing the identical bytes, which still advances the modification time
-- and costs one extra read and write on a read that already proved nothing changed.
local function touchSnapshot(bundleId)
  local path = snapshotPath(bundleId)
  if hs.fs.touch then
    hs.fs.touch(path)
    return
  end
  local data = hs.json.read(path)
  if data then hs.json.write(data, path, true, true) end
end

--------------------------------------------------------------------------------
-- Recency, one lib/recency instance per bundle id, built lazily
--------------------------------------------------------------------------------

local function recencySettingsKey(bundleId)
  return "olm.recency.menuSearch." .. bundleId
end

local recencyByApp = {}
local function recencyFor(bundleId)
  -- The guard past mere truthiness, review finding L4. cfg.recencyLib is trusted to be the
  -- raw recency module rather than an auto built instance only because the manifest declares
  -- it under a field name lib/services.lua's own auto instance path does not watch. A future
  -- change to that path answering an instance here instead would otherwise raise on .new
  -- rather than degrade, the one place this plugin takes that coupling on faith is worth one
  -- cheap check.
  if not (cfg.recencyLib and type(cfg.recencyLib.new) == "function") then return nil end
  local r = recencyByApp[bundleId]
  if not r then
    r = cfg.recencyLib.new({ settingsKey = recencySettingsKey(bundleId), limit = RECENCY_LIMIT })
    recencyByApp[bundleId] = r
  end
  return r
end

-- Applied once, when an open's own display list is first built from the standing snapshot,
-- decision three of the cache brief. Never called again while that list is up, which is what
-- keeps a live correction to an append and an in place dim rather than a reshuffle. items is
-- raw, path and shortcut only, keyed here rather than by the caller so every consumer of this
-- function's own answer already carries the disambiguated identity buildRows and the rest of
-- this file expect.
local function sortForOpen(entry, items)
  local keyed = keyedList(items)
  local recency = recencyFor(entry.bundleId)
  if not recency then return keyed end
  return recency.order(keyed, function(r) return r.key end)
end

--------------------------------------------------------------------------------
-- Per app state, one entry per bundle id, the one source every consumer reads
--------------------------------------------------------------------------------

local entriesByBundle = {}

-- An app Launch Services never gave a bundle id is rare and has no identity stable across a
-- relaunch. The pid at least keeps this session's own cache and recency from colliding with a
-- different app that also has none, and the prune sweep drops a file keyed this way quickly,
-- since pathForBundleID can never resolve a pid shaped id back to an installed app. Two
-- different bundle id less apps sharing a recycled pid within one session is a real gap this
-- does not close, review finding L3, narrow enough and expensive enough to close properly,
-- a stable identity beyond the pid, that it is left rather than patched partway.
local function bundleIdFor(app)
  local id = app:bundleID()
  if id and id ~= "" then return id end
  return "noBundle:" .. tostring(app:pid())
end

-- Merge a fresh, keyed read into an entry's own display list without disturbing anything
-- already on screen. A survivor keeps its exact position and picks up whatever changed about
-- it, a shortcut most likely. An item the fresh read no longer has is dimmed in place, enabled
-- false, rather than removed, so nothing below it shifts. A genuinely new item, or a fresh
-- occurrence of a path this entry already showed once, is appended at the bottom, in the fresh
-- read's own order, review finding H1, since each occurrence now carries its own key rather
-- than sharing one every duplicate would otherwise collide under. No recency pass runs here,
-- that already happened once when this open's own display list was first built.
local function mergeFresh(entry, freshKeyed)
  local freshByKey = {}
  for _, r in ipairs(freshKeyed) do freshByKey[r.key] = r end
  local seen = {}
  for _, row in ipairs(entry.rows or {}) do
    local fresh = freshByKey[row.key]
    if fresh then
      seen[row.key] = true
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
  for _, r in ipairs(freshKeyed) do
    if not seen[r.key] then
      entry.rows[#entry.rows + 1] = buildRow(r, entry.icon, entry.iconKey)
      seen[r.key] = true
    end
  end
end

-- Whether a fresh, keyed read matches exactly what is already live on screen, decision two of
-- the cache brief, no checksum, the two lists are already in memory so a direct compare costs
-- nothing next to the walk that produced them. Only the live, enabled rows count, an item
-- already dimmed by an earlier correction has already told its own story once. Order is
-- deliberately not part of this comparison, since the display list is recency sorted and a
-- fresh read is not, so a sequence compare would read every open as changed even when nothing
-- moved. Because every occurrence of a duplicated path now carries its own key, review finding
-- H1, comparing the keyed sets already is comparing multisets, one entry per real row rather
-- than one per distinct path, so two windows sharing a title no longer report changed on every
-- single open with nothing visibly different. false is stored in place of a nil shortcut so a
-- present key with no shortcut can never be confused with an absent one, a plain table cannot
-- tell those two apart by indexing alone.
local function sameAsLive(entry, freshKeyed)
  local live, count = {}, 0
  for _, row in ipairs(entry.rows or {}) do
    if row.enabled ~= false then
      live[row.key] = row.shortcut or false
      count = count + 1
    end
  end
  if count ~= #freshKeyed then return false end
  for _, r in ipairs(freshKeyed) do
    local seen = live[r.key]
    if seen == nil or seen ~= (r.shortcut or false) then return false end
  end
  return true
end

-- Whether stageSelectedRow's own answer means anything for this entry right now, review
-- finding M3. hs.chooser keeps its own selected row across a hide, so asking it while
-- nothing of this entry's own is actually on screen reads a row belonging to a window that may
-- already have closed. entry.open, cleared by the picker's own onClose below the moment its
-- presentation genuinely hides, is what tells the difference, so a correction landing after an
-- escape mid scroll applies at once rather than deferring forever against a stale row number a
-- hidden widget happens to still be sitting on.
local function atRowOneNow(entry)
  if not entry.open then return true end
  if not cfg.stageSelectedRow then return true end
  local row = cfg.stageSelectedRow()
  if not row then return true end
  return row == 1
end

-- Where a landed background read is actually reconciled against an entry's own state. Runs
-- for every app this plugin has ever opened, whether or not anything is showing right now, so
-- an app's own standing snapshot keeps repairing itself between opens at no cost, decision
-- three's own prune line among them.
local function onLanded(entry, freshList)
  local freshKeyed = keyedList(freshList)

  local recency = recencyFor(entry.bundleId)
  if recency then
    local keys = {}
    for _, r in ipairs(freshKeyed) do keys[#keys + 1] = r.key end
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

  if sameAsLive(entry, freshKeyed) then
    touchSnapshot(entry.bundleId)
    return
  end

  if not atRowOneNow(entry) then
    -- Somebody is already looking part way down the list, or nobody is looking at all and the
    -- gate has nothing honest to ask. Either way the correction is not lost, it waits as this
    -- app's own next baseline, since a fresh open always lands back on row one, which is
    -- exactly the gate this deferral is waiting on, decision as agreed.
    entry.pendingFresh = freshList
    return
  end

  mergeFresh(entry, freshKeyed)
  entry.snapshot = freshList
  saveSnapshot(entry.bundleId, freshList)
  if entry.notify then entry.notify() end
end

-- Kicks the background accessibility walk for this entry unless one is already running. Off
-- the main thread by construction, hs.application:getMenuItems's own callback form, so this
-- never blocks the open that asked for it. Review finding H2.
--
-- fired is the single mechanism, deliberately, second review pass finding N2. An earlier
-- version of this also carried a per entry generation counter, reasoning that a stale
-- callback landing after a newer walk had begun needed a second guard beyond fired. It did
-- not. entry.reading, the one thing that lets a newer walk start at all, is only ever
-- cleared inside finish, below the fired check, so no newer walk can exist yet at the moment
-- any walk's own finish body is running, which makes a generation compare unreachable. Worse
-- than unreachable, since finish also stops entry.readTimeout above where that compare would
-- sit, so a version of this that DID reach the compare and returned early would have already
-- disarmed the newer walk's own timeout on the way out, reopening H2 for the walk the guard
-- was meant to protect. One flag, checked once, first, is both sufficient and correct. A
-- walk that genuinely outlasts READ_TIMEOUT has its real answer discarded when it finally
-- lands, fired already true by then, the same choice VPN's own timed out leg makes.
local function beginRead(entry)
  if entry.reading or not entry.app then return end
  entry.reading = true
  local app = entry.app
  local fired = false

  -- fresh is nil on a timeout, meaning nothing landed to report, and a real menu list
  -- otherwise, never both, and never called twice for the same walk regardless of which of
  -- the two races in first.
  local function finish(fresh)
    if fired then return end
    fired = true
    if entry.readTimeout then
      entry.readTimeout:stop()
      entry.readTimeout = nil
    end
    entry.reading = false
    if fresh then onLanded(entry, fresh) end
  end

  -- Held on the entry itself rather than a bare function local, the identical hazard this
  -- track already names for VPN's own fetchTimers and the stage's own _geometryTimer, a
  -- Hammerspoon timer being userdata whose finalizer stops it the moment nothing on the Lua
  -- side still refers to it, which a local alone cannot promise once this call has returned.
  -- Only one walk is ever in flight per entry, guarded by entry.reading above, so reusing
  -- one field is safe the identical way fetchTimers reuses one table across rounds.
  entry.readTimeout = hs.timer.doAfter(READ_TIMEOUT, function() finish(nil) end)
  app:getMenuItems(function(menus)
    local fresh = {}
    if menus then flattenMenus(menus, {}, fresh) end
    finish(fresh)
  end)
end

-- One file's worth of the sweep below, pulled out so it can be run under its own pcall,
-- review finding N3. A raise anywhere in here used to abort every file after it for the rest
-- of this Hammerspoon load, since the loop that calls this carried no protection of its own,
-- and the one call in this body that was already capable of raising on some Hammerspoon
-- builds, per the same finding, sat unguarded in the middle of it.
local function sweepOne(dir, name, cutoff)
  if name:sub(-5) ~= ".json" then return end
  local full = dir .. "/" .. name
  -- Review finding L2, the other half. A planted symlink among real snapshots is left
  -- alone rather than followed and removed on its target's own behalf, os.remove already
  -- removing only the link itself, never its target, which is the containment this file
  -- already had. This is what keeps a foreign file from being reached at all.
  local entryLink = hs.fs.symlinkAttributes(full)
  if entryLink and entryLink.mode == "link" then return end
  local bundleId = decodeBundleId(name:sub(1, -6))
  -- pathForBundleID answers an empty string, never nil, for a bundle id it cannot
  -- place, so both are checked, the same idiom lib/deps.lua and tmuxsessions already
  -- read it by.
  local installed = hs.application.pathForBundleID(bundleId)
  local mtime = hs.fs.attributes(full, "modification")
  if not (installed == nil or installed == "" or (mtime and mtime < cutoff)) then return end
  local removedOk = os.remove(full)
  if not removedOk then
    log.w("could not remove a dead snapshot at " .. full .. ", it will be retried on the next Hammerspoon load")
  end
  -- Review finding M4, the deletion call itself corrected under review finding N3.
  -- hs.settings.clear is the documented door this tree otherwise reaches for nowhere else
  -- had reached for at all, hs.settings.set(key, nil) being an undocumented way to ask the
  -- identical question that a future Hammerspoon build owes nothing to keep answering the
  -- same way. The recency settings key ages out with the file it belongs to, rather than
  -- persisting in the Hammerspoon plist forever once an app that no longer resolves has had
  -- its cache dropped, and the in memory instance is dropped too, so nothing this session
  -- resurrects the key on its own next touch.
  hs.settings.clear(recencySettingsKey(bundleId))
  recencyByApp[bundleId] = nil
end

-- Deferred hygiene, decision five, scheduled once per Hammerspoon load, on this plugin's own
-- first open of any app, never at load time and never on the open path itself.
local pruneScheduled, pruneTimer = false, nil
local function pruneDeadSnapshots()
  local dir = cfg.storage.cacheDir("menusearch")
  -- Review finding L2, half of it. A cache directory itself replaced by a symlink to
  -- somewhere else would otherwise let this sweep delete files it was never meant to reach.
  local dirLink = hs.fs.symlinkAttributes(dir)
  if dirLink and dirLink.mode == "link" then return end
  local ok, iter, dirObj = pcall(hs.fs.dir, dir)
  if not ok or not iter then return end
  local cutoff = os.time() - STALE_DAYS * 24 * 60 * 60
  for name in iter, dirObj do
    -- Review finding N3. Each file's own sweep runs under its own pcall now, so a raise
    -- on one file, malformed on disk, a settings call an unexpected Hammerspoon build
    -- answers differently, or anything else, is logged and the sweep still reaches every
    -- file after it rather than stopping cold for the rest of this Hammerspoon load.
    local sweepOk, sweepErr = pcall(sweepOne, dir, name, cutoff)
    if not sweepOk then
      log.w("the dead snapshot sweep raised on " .. tostring(name) .. ", " .. tostring(sweepErr) .. ", continuing with the rest")
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
-- since only one of the two can genuinely be on screen at a time. entry.open is stamped true
-- on every call, review finding M3, the picker's own onClose being the one place it is ever
-- cleared, so the highlight gate above has something honest to ask about.
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
  entry.open = true
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
-- this one. Touches the chosen occurrence's own recency key, review finding H1's own second
-- half, rather than a key every duplicate of that path would otherwise share. Deferred, genuine
-- world dispatch, so the picker has torn down and focus has actually returned to the target app
-- before its own menu item is asked to run, unchanged by either half of this migration.
local function menuSearchSelect(item)
  if not (item and item.path and pickerEntry and pickerEntry.app) then return end
  local app = pickerEntry.app
  local recency = recencyFor(pickerEntry.bundleId)
  if recency and item.key then recency.touch(item.key) end
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

-- The presentation contract's own onClose, review finding M3, told once whenever the stage
-- hides entirely, never on a swap. Clears the highlight gate's own bookkeeping for whichever
-- entry the picker was last showing, so a correction that lands after this window has
-- genuinely closed is judged on its own terms, applied at once, rather than held back by a row
-- number a hidden hs.chooser instance happens to still be sitting on from before the hide.
local function menuSearchOnClose()
  if pickerEntry then pickerEntry.open = false end
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
  if recency and payload.key then recency.touch(payload.key) end
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
  self.onClose = menuSearchOnClose

  self.scopeRows = scopeMenuRows
  self.scopeRun = scopeMenuRun

  return self
end

return obj
