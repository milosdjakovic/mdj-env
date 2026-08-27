# Adversarial review, the menu search step, 2026-08-27

Branch feat/menusearch-cache, worktree /Users/milos.djakovic/Development/personal/.worktrees/menusearch-cache,
two commits over main at 1b768e1. a98317d, the three geometry riders I filed as N1, N2 and N4.
5580de8, the menusearch migration onto the stage plus the snapshot cache, a near rewrite.
Contract read, docs/BRIEF-MENUSEARCH-CACHE.md six decisions, BRIEF-STAGE.md's presentation
contract, PLUGIN-CONTRACT.md's call kind rule. Rewritten files read whole.

Gates rerun by me from the worktree root.

    luac -p on host/stage/init.lua, lib/registrar.lua, plugins/menusearch/init.lua,
      plugins/menusearch/manifest.lua and root/compose.lua, all clean
    src/check-dependencies.sh, "Dependency check passed, 0 warning(s)", exit 0
    git status clean after the reconciler ran, no DEPENDENCIES manifest moved, decision six held

Counts. Three high, four medium, eight low, one sound section.

## High

### H1. Two menu items with the same path make every open a change, forever. Confirmed.

`plugins/menusearch/init.lua:283` through `:296`, `sameAsLive`, builds `live` as a set keyed by
`pathKey` while counting rows separately.

    live[pathKey(row.item.path)] = row.shortcut or false
    count = count + 1
    ...
    if count ~= #freshList then return false end

A set collapses duplicates and a count does not. An app with two menu items sharing an identical
full path stores one key and counts two, and on the merge side `mergeFresh` at `:246` builds
`freshByKey` the same collapsing way, so after a correction the display list holds one row for
that key while the fresh read holds two.

The sequence, and the everyday case is the Window menu.

1. Two windows of the same app carry the same title, two Finder windows both named Documents,
   two untitled TextEdit documents, two Safari windows on the same page. The Window menu then
   holds two leaves whose full path is identical, `Window \31 Documents`.
2. First read plants the baseline, `entry.snapshot` holds both, `buildRows` builds two rows.
3. Second open. `sameAsLive` counts 2 enabled rows, `#freshList` is 2, equal, then each fresh
   key finds the single live entry and matches. Equal, nothing happens. So far fine.
4. Now a correction runs once for any other reason, a genuinely added or removed item elsewhere
   in the menu. `mergeFresh` updates both duplicate rows from the same `freshByKey` entry, marks
   the key seen, and the append loop skips both fresh copies. The display list is unchanged in
   count here, so this step alone is stable.

The unstable shape is the reverse and it is the common one, since the snapshot on disk is
whatever the last read wrote and the live list is whatever the last open built.

1. Open while only one window is named Documents. Snapshot holds one such leaf.
2. Open a second window with the same title. Open menu search. The display list is built from the
   snapshot, one row for that key, `count` is 1 for it. The fresh read answers two.
3. `count ~= #freshList`, so not equal, merge runs, disk write, `notify()` fires.
4. `mergeFresh` marks the key seen after updating the one existing row, and the append loop skips
   both fresh copies because `seen[key]` is already true. So the display list still holds one row
   for a key the fresh list holds twice, and `entry.snapshot` is set to `freshList`, which holds
   two.
5. Next open rebuilds `entry.rows` from that snapshot, so it now holds two, and step 2's shape
   returns whenever a duplicate appears or disappears.

The steady state defect is step 4. Whenever the live list and the fresh read disagree only in how
many copies of one key exist, `sameAsLive` answers false and `mergeFresh` cannot make them agree,
because it refuses to append a key it has already seen. So the entry is stuck reporting changed on
every landed read, which means a `saveSnapshot` disk write and a `notify()` refresh on every single
open for as long as the duplicate is there, with nothing visible ever changing.

That defeats decision two outright, "equal means nothing happens at all, no refresh call", and it
turns the free case into the expensive one.

Both halves need fixing together. Compare multisets rather than sets, count occurrences per key on
both sides, and let the append loop add a fresh copy whose count exceeds what the display list
already holds. Or accept that `pathKey` is not an identity and disambiguate duplicates with an
occurrence index appended to the key, which also fixes `recency.touch` conflating two windows.

### H2. entry.reading has no timeout and no reset but the callback, so one wedged walk freezes that app for the load. Confirmed as a gap, plausible to reach.

`plugins/menusearch/init.lua:354` through `:371`.

    local function beginRead(entry)
      if entry.reading or not entry.app then return end
      entry.reading = true
      local app = entry.app
      app:getMenuItems(function(menus)
        entry.reading = false
        ...
      end)
    end

`entry.reading` is cleared in exactly one place, the first line of the callback. There is no
timeout, no error path, and no reset on a later open. `hs.application:getMenuItems` in its callback
form walks the accessibility tree on a background queue, and an accessibility read is precisely the
kind of call that can fail to return, an app terminating mid walk, the accessibility permission
revoked while a walk is in flight, or an AX call blocking on an unresponsive target.

If that callback never runs, `entry.reading` stays true for the life of the Hammerspoon load. Every
future `openApp` for that bundle id calls `beginRead`, hits the guard on the first line, and returns
without starting anything. The app's snapshot then freezes at whatever the last successful read
wrote, silently, with the menus drawing from a cache that can never be corrected again, and nothing
anywhere saying so.

This is the same failure class the VPN rider closed one commit earlier in this same track, an async
leg with no answer for never landing, and the fix there was a per leg timeout racing the real answer
through a once only gate. The identical shape applies here. Give the read a bound, clear `reading`
on the timeout, and let the next open start a fresh walk. Note that unlike VPN nothing here even
counts down, one boolean is the whole state, so the fix is smaller.

The commit's own module comment at `:359` through `:361` addresses a different case, an answer that
lands late, and correctly says that is still worth keeping. It does not address an answer that never
lands at all.

### H3. A snapshot that parses but holds a malformed item raises on the open path and wedges that app permanently. Confirmed.

`plugins/menusearch/init.lua:195` through `:201`.

    local function loadSnapshot(bundleId)
      local path = snapshotPath(bundleId)
      if not hs.fs.attributes(path) then return nil end
      local data = hs.json.read(path)
      if type(data) == "table" and type(data.items) == "table" then return data.items end
      return nil
    end

The structural check is real and I credit it, a file of the wrong shape answers nil and the open
degrades to the first open reading row exactly as decision one wants. What is not checked is the
shape of the elements. `data.items` may be a table of anything.

The path from there to a raise is short. `openApp` at `:429` builds
`buildRows(sortForOpen(entry, entry.snapshot), ...)`, `buildRows` at `:165` calls `buildRow` per
element, and `buildRow` at `:150` opens with `titleAndParents(r.path)`, which at `:110` does
`local n = #path`. With `r.path` nil that is "attempt to get length of a nil value" and the error
propagates out of `openApp`, out of `menuSearchOnPresent`, out of the stage's own `_announce`, and
out of `Stage:present`, so the hotkey handler dies and the picker never opens.

It never recovers on its own. The bad file is not deleted, not rewritten, and not quarantined, and
every subsequent open of that app takes the identical path to the identical raise. The tool is dead
for that app until the sixty day rule removes the file, which per M1 may itself never fire, or until
the app is uninstalled.

How a file gets into that state. `saveSnapshot` at `:203` is `hs.json.write(..., true, true)`, which
is not atomic, so a crash or a kill mid write leaves a truncated file. A truncated json usually fails
to parse and answers nil, which is safe. The unsafe window is a write that ends on a structurally
valid boundary, and a schema change is the other route, since there is no version field anywhere in
the format, so a future shape whose `items` is still an array of tables with different keys parses,
passes the check, and raises here.

The brief is explicit that this must not happen, "The store must fail toward the empty first open
behavior, never toward a raise on the open path." Validate each element, a `path` that is a table
with at least one entry and a `shortcut` that is nil or a string, and answer nil for the whole file
on the first bad one. A version field in the written object is worth the four characters at the same
time.

Note that leaving `hs.json.read` unwrapped is not itself the defect. Three other stores in this tree
read it the same way, `plugins/displayprofiles/store.lua:43`,
`plugins/clipboard/manager/store.lua:268`, `plugins/emoji/filter-glyphs.lua:59`, so the plugin is
following the house idiom and `read` answers nil rather than raising. The element check is the
missing guard, not a pcall.

## Medium

### M1. The sixty day rule reads a timestamp that only a change advances, so a stable app used daily is pruned. Confirmed.

`plugins/menusearch/init.lua:381`, `local mtime = hs.fs.attributes(full, "modification")`, against
a cutoff of sixty days, and `os.remove(full)` when it is older.

The file's modification time only moves when `saveSnapshot` runs. `saveSnapshot` has three callers,
the first ever baseline at `:326`, the merge at `:352`, and the fold of a deferred correction at
`:427`. The ordinary path for an app whose menus have not changed is `onLanded` reaching
`if sameAsLive(entry, freshList) then return end` at `:333` and returning before any of them.

So an app with a stable menu tree has its snapshot written exactly once, at the first open ever, and
never again. Open menu search on it every single day for sixty one days and the file is deleted on
the sweep, because "untouched" in the code means "not rewritten" while the brief's decision five
means "not used". The next open then eats the full accessibility walk, which for Safari is the 552
milliseconds this whole track exists to remove.

The condition itself fails safe in the other direction and I checked that, `(mtime and mtime < cutoff)`
means a failed `hs.fs.attributes` never triggers a delete on age.

Fix is a line. Touch the file on every open, or record `lastUsed` inside the json and read that
instead of mtime, which also survives a copy or a backup restore that rewrites mtimes.

### M2. snapshotPath interpolates an unsanitized bundle id, so the write path can escape the cache directory. Confirmed by construction.

`plugins/menusearch/init.lua:192`.

    local function snapshotPath(bundleId)
      return cfg.storage.cacheDir("menusearch") .. "/" .. bundleId .. ".json"
    end

`bundleId` comes from `bundleIdFor` at `:236`, which returns `app:bundleID()` verbatim. That value is
whatever the application's own Info.plist declares in CFBundleIdentifier. Reverse DNS is a convention
that macOS does not enforce, and a bundle id containing a slash produces a path outside the snapshot
directory. `../x` writes to the cache root, and a longer run of `../` reaches anywhere under the
user's home that Hammerspoon can write, since it runs with full user privileges.

The damage is bounded to writing a json file at a name derived from a hostile or broken app's own
plist, so this is integrity rather than disclosure, but a file the user owns can be clobbered if the
name lands on one, and nothing here would ever say so.

The good news, and I checked this specifically because it is what the coordinator asked to be made
impossible rather than unlikely, is that **the delete path cannot be steered this way**.
`pruneDeadSnapshots` at `:374` iterates `hs.fs.dir(dir)`, whose names are single path components by
construction and can never contain a slash, so `dir .. "/" .. name` is always a direct child of the
snapshot directory. A file written outside by a traversing bundle id leaks forever rather than
becoming a deletion target. Containment holds on the half that matters most.

Fix is one guard in `bundleIdFor` or `snapshotPath`, reject anything not matching `^[%w%.%-_]+$` and
fall back to the `noBundle:` shape or a hash. Note that `pruneDeadSnapshots` reverses the filename
back into a bundle id at `:377` to ask `pathForBundleID`, so any encoding scheme has to be reversible
or prune has to learn the same rule.

### M3. The highlight gate asks the shared window without knowing whose list is up, and a hidden chooser keeps its old row. Confirmed.

`plugins/menusearch/init.lua:335` through `:348`.

    local atRowOne = true
    if cfg.stageSelectedRow then
      local row = cfg.stageSelectedRow()
      if row then atRowOne = (row == 1) end
    end
    if not atRowOne then
      entry.pendingFresh = freshList
      return
    end

`stageSelectedRow` resolves to `Stage:selectedRow()`, `host/stage/init.lua:829`, which is
`self._instance:selectedRow()`, which is `self.chooser:selectedRow()` with no visibility guard,
`lib/chooser/providers/native.lua:884`. `hs.chooser` keeps its selected row across a hide, which this
tree already knows and states, `native.lua:756` through `:760` explaining that `show()` has to reset
the highlight to row one precisely because "hs.chooser reuses one instance across shows and would
otherwise restore the row the last open left highlighted".

So the question this gate asks is "what row is the one shared window sitting on", and the question it
means to ask is "is my own list up and still at the top". Two divergences follow.

The one that costs something. Open menu search, arrow down to row five, press Escape. The window is
gone but `selectedRow()` still answers five until the next show. The background read for that app
lands a moment later, the gate reads five, concludes somebody is looking part way down a list that is
not on screen at all, and defers. `entry.snapshot` is not updated and `saveSnapshot` is not called,
so the read is held only in `entry.pendingFresh`, in memory, and a Hammerspoon reload before the next
open of that app loses it entirely.

That also makes the module's own claim at `:315` through `:317` false. It says `onLanded` runs "for
every app this plugin has ever opened, whether or not anything is showing right now, so an app's own
standing snapshot keeps repairing itself between opens at no cost". It repairs itself between opens
only when the last open happened to end with the highlight on row one.

The one that costs nothing but is still wrong reasoning. A read for app A landing while the stage
shows something else entirely at row one passes the gate and applies. That is harmless, because
`notify` is guarded downstream, `redrawPresented` checking `stageModule:current() == name` at
`root/compose.lua:725` and `Launcher:refresh` reaching `Stage:refresh` which is gated on `isShowing`,
and because applying is the right outcome anyway. But it is right by luck rather than by asking.

The root of both is that this plugin's presentation declares no `onClose`, so it never learns its own
list closed and has no state saying whether it is the one on screen. Declaring `onClose` and clearing
a per entry `open` flag, then consulting the gate only when that flag is set, closes it with the
contract already in hand and no new root word.

### M4. Recency settings keys and instances are unbounded and the prune sweep never touches them. Confirmed.

`plugins/menusearch/init.lua:210` through `:218`.

    r = cfg.recencyLib.new({ settingsKey = "olm.recency.menuSearch." .. bundleId })

Three unbounded growths, none of them swept.

`recencyByApp` holds one instance per bundle id opened this session, never evicted. `entriesByBundle`
at `:230` likewise holds a full snapshot and a full row list per app, with row lists carrying image
handles. Both are bounded by apps used per load, so they are the mild ones.

`hs.settings` is the one that persists. One key per app ever opened, forever. `pruneDeadSnapshots`
deletes the json file for an app that no longer resolves, `:382`, and does nothing at all about
`olm.recency.menuSearch.<bundleId>`, so uninstalling an app leaves its key in the Hammerspoon plist
permanently. Decision five says pruning is hygiene, and half the store this plugin creates is outside
what it sweeps.

Per key size is better than it looks and I checked it rather than assumed. `onLanded` calls
`recency.prune(keys)` at `:311` with the fresh read's own path set on every landed read, and
`lib/recency.lua`'s prune drops every remembered key not in that set, so a key is bounded by the app's
live menu item count. For Safari that is the 1259 leaves the probe measured, each a joined path
string, so on the order of fifty kilobytes for one app. A hundred apps is a few megabytes inside
`org.hammerspoon.Hammerspoon`'s plist, which `hs.settings.set` rewrites on every `touch`.

No `limit` is passed to `recencyLib.new`, and `lib/services.lua:305` shows the auto instance path does
pass one through from the declaration when a plugin states it. So the one lever that exists for this
was not pulled. A limit of a few dozen is the right shape for a recency list nobody scrolls, and it
would make each key tiny regardless of how large the app's menu is.

Add the settings key removal to the same sweep that removes the file, since prune already holds the
bundle id at `:377`, and pass a limit.

## Low

**L1. A transient `pathForBundleID` miss deletes a live app's snapshot.** `:380` through `:383`.
Launch Services can answer empty for an installed app whose volume is unmounted or whose database is
rebuilding, and the sweep deletes on that answer. The blast radius is one regenerable file and the
next open rebuilds it, so this is correctly graded as cheap, but an app on an external disk that is
not mounted at sweep time loses its cache and pays a full walk later.

**L2. The sweep does not verify each entry is a regular file, nor that the directory is not a
symlink.** `os.remove` on a symlink removes the link rather than its target, which is what keeps a
planted symlink from turning into a wrong deletion, and I confirmed that is the containment. The
uncovered shape is the directory itself being a symlink to somewhere holding json files, in which
case every one of them whose stem does not resolve as a bundle id is deleted. Requires the user to
have replaced the cache directory, so informational, but `hs.fs.symlinkAttributes` on each entry and
on the directory is two lines.

**L3. `noBundle:<pid>` keys collide as the OS reuses pids.** `:236` through `:239`. The comment
names the identity as unstable across a relaunch and the sweep as dropping such files quickly, both
true. What it does not name is that within one session two different bundle id less apps can be given
the same key and merge each other's menus into one snapshot and one recency slot.

**L4. `recencyFor` trusts that `cfg.recencyLib` is the module, and the coupling that makes that true
is documented on only one side.** `:213` calls `cfg.recencyLib.new` with no check. The reason it is a
module is that `lib/services.lua:304` keys its automatic instance off the literal field name
`recency`, so declaring `recencyLib = { from = "recency" }` slips past it and takes `lib/wire.lua:107`
through `:135`'s generic grant, which hands the raw module. That is a legitimate use of a documented
field, `decl.from` is first class at `wire.lua:110`, so I do not read it as a contract violation. The
fragility is the reverse direction. If `perPlugin` ever learns to match on `from` as well as on the
field name, menusearch silently receives an instance, `.new` is nil, and the open path raises. The
manifest explains all of this at length. `lib/services.lua` says nothing about a plugin deliberately
opting out, which is exactly the one sided documentation this repo has been burned by before. A
sentence there, and a `type(cfg.recencyLib.new) == "function"` guard here, cost nothing.

**L5. `os.remove` at `:383` ignores its return.** A file that cannot be removed is retried on the next
Hammerspoon load and never reported.

**L6. An empty snapshot reads as an empty list rather than as the reading row.** `menuSearchRows` at
`:441` and `scopeMenuRows` at `:511` both use `entry.rows or { readingRow(...) }`, and an empty table
is truthy, so an app whose last read genuinely answered nothing shows "no results" instead of saying
it is reading. Narrow, since an app with no enabled menu items is rare.

**L7. The plugin still earns the docked panel triple it no longer reads.** `panelAs = "panel"` is gone
from the manifest but `manifest.surface` and the `menuSearch` context remain, and
`lib/services.lua:268` through `:284` builds the panel for any plugin with a surface and a context,
now handing three flat fields, `onPositioned`, `onActivity`, `onClose`, that this plugin's configure
never reads. Harmless, and VPN carries the same residue, but the tree's own audit calls handing a
plugin fields it never reads a defect class, so it is worth one sentence somewhere saying it is
deliberate now.

**L8. No schema version in the written snapshot.** `saveSnapshot` at `:203` writes `{ items = items }`
with nothing naming the shape. Today's structural check catches a wholesale shape change and answers
nil, which is the right degradation, but it cannot catch a same shaped format whose element meaning
moved, which is what H3's second route is. Four characters at write time buys the next change a clean
answer.

## What I checked and found sound

**The riders, all three, against my own findings.** N1, `_lastShowAt` moves below `show()`,
`host/stage/init.lua:396`, which is what the finding asked for and for the stated reason, the atom
arms its settle at the end of `_positionAndShow` after `chooser:show()` runs. The stage's gate now
fires after the settle rather than a full `show()` before it. N2, the unconditional
`_geometryTimer` cancel moves to the top of `_show`, `:346` through `:357`, and is correctly removed
from `_applyPaneGeometry`, `:480`. I confirmed `_applyPaneGeometry` is the only place that ever arms
that timer and that it is only ever reached from `_show`, so a cancel at the top of `_show` covers
every door, which is what the old unconditional cancel was doing before the swap only refactor lost
it. N3 I did not ask to be closed and it is not. N4, `lib/registrar.lua:465`,
`type(p.rowCount) ~= "number" or p.rowCount < 1 or p.rowCount % 1 ~= 0`, and the message widened to
"not a positive whole number". I walked the odd numbers, a NaN fails the modulo clause since `nan % 1`
is not zero, an infinity fails it the same way, so both refuse rather than slipping through the
comparison. All three riders are faithful.

**The three root words are published once each, delivered through the established channel, and do not
collide.** `stagePresent` at `root/compose.lua:714`, `redrawPresented` at `:724`, `stageSelectedRow`
at `:736`, siblings in the same table, one closure apiece, and the manifest declares all three under
`needs.data` with `source = "root"` and `policy = "optional"` with a real `breaks` sentence each, the
identical shape VPN uses. `Stage:selectedRow()` is the plain counterpart of `selectedItem()` and reads
the same instance member ActionPanel already relies on.

**The prune timer is held and the sweep genuinely cannot run on the open path.** `pruneTimer` is a
file local upvalue assigned at `:394`, so the documented Hammerspoon hazard of an unreferenced timer
being collected before it fires is closed. `scheduleFirstUsePrune` is called at the top of `openApp`,
`:409`, and does nothing but set a boolean and arm a five minute timer on the first call of the load,
so the open path pays one comparison. Decision five held.

**No double fetch between the two consumers, and both serve the identical rows for the same app.**
`entriesByBundle` is keyed by bundle id rather than by open, `beginRead` guards on `entry.reading`
at `:355`, and both `menuSearchOnPresent` at `:487` and `scopeMenuRows` at `:513` reach the same
`openApp`. A picker open and a launcher scope open of the same app in quick succession share one walk
and one entry. `entry.notify` being overwritten by the second opener is correct, since only one of the
two can be on screen at a time and the later one is the one worth telling.

**The scope path's own reopen guard survived intact.** `scopeSeen = { app, openId }` at `:501` and
the comparison at `:512` are the same shape the retired per open state kept, so `scopeMenuRows` still
reopens the app only when the launcher's covered app or open id actually changed, not on every
keystroke.

**The two collaborators from the launcher still resolve, which is the wiring that broke once before.**
`coveredApp` is `{ plugin = "launcher", member = "coveredApp", call = "method", policy = "required",
ordering = false }` and `refreshLauncher` the same shape with `member = "refresh"` and optional. Both
are delivered by `lib/wire.lua`'s sibling block, which the file's own comment records as having been
the missing half last time. `Launcher:refresh` is `self._stage:refresh()`, which is gated on
`isShowing` inside `Stage:refresh`, and it passes no `resetRow`, so a landed correction redraws
without moving the highlight, which is exactly what an append and dim correction needs.

**`provides` and `registry.scope` are not two competing wirings, and they match VPN exactly.**
`provides = { rows = "rows", select = "select" }` is a membership claim read by
`lib/plugins.lua:211` for the launcher's own `scopes = { provides = { "rows", "select" } }` set query,
deciding that this plugin is a scope at all. `registry.scope.rows` and `.run` are what name the
functions that serve it, `scopeRows` and `scopeRun`. The picker's own `rows` never reaches the scope
path. VPN's manifest carries the identical pair, so there is no drift.

**The migration matches VPN's shape on every point I compared.** `Chooser.new`, the hand rolled
surface adapter, the panel wiring and `panelAs` are all gone, confirmed against the removed lines. The
hotkey goes through `cfg.stagePresent("menuSearch")` at `:496`. `registry.surface` is deleted, and I
verified that does not orphan navigation, because `root/compose.lua:1349` drives the surface adapter
loop off `contextOwners`, which comes from `manifest.surface.context`, still declared, and the proxy
at `:1311` asks `wiredRegistry.presentationFor(identity)` on every access and routes to
`stageModule:surfaceFor(identity)` when it answers. `surface.context` is `menuSearch` and the identity
is `menuSearch`, so the registrar's own divergence warning at `lib/registrar.lua:483` stays quiet.

**Every presentation member states its call kind explicitly and resolves on the real module.** `rows`,
`select`, `placeholder` and `onPresent` are all `{ member = ..., call = "dot" }`, never the bare string
shorthand, which is what `callKindStated` in the registrar refuses. All four are assigned as plain dot
called closures in `configure` at `:551` through `:555`, so `memberResolves` finds real functions on
the finished module at register. `placeholder` correctly answers a plain static string, since the
contract resolves it once. No `rowCount` and no `paneWidth`, so the two new type checks are not
exercised and cannot refuse this plugin.

**The dispatch into the world kept its deferral and its target.** `menuSearchSelect` at `:452` acts on
`pickerEntry.app`, the app captured at `onPresent`, never on whatever is frontmost when the row runs,
and defers through `cfg.after(0.1, ...)` so the chooser has torn down and focus has returned first.
`scopeMenuRun` at `:527` acts on `scopeEntry.app` and correctly does not defer, since the launcher
already defers a scope run.

**Append and dim genuinely preserve every surviving position.** `mergeFresh` at `:245` through `:271`
iterates `entry.rows` in order and mutates in place, never removing and never reordering, then appends
new keys at the end. Nothing above any row can move, which is what makes redrawing without resetting
the highlight safe. Duplicates are the one case it cannot settle, H1.

**Equal really does mean no refresh call.** `onLanded` returns at `:333` before `notify()` is reached,
so an unchanged read costs the comparison and nothing else, no redraw, no disk write. Decision two
held, again modulo H1.

**Recency applies once per open and never while a list is up.** `sortForOpen` has exactly one caller,
`openApp` at `:429`, and `mergeFresh` runs no recency pass of its own, which the comment at `:224`
states and the code keeps. `recency.prune` is fed the fresh read's own path set at `:311` rather than
the display list, decision three's own wording, and `lib/recency.lua`'s prune persists only when
something actually changed.

**The deferred correction really is folded in at the next open.** `openApp` at `:422` through `:426`
consumes `entry.pendingFresh`, makes it the snapshot, writes it, and then rebuilds `entry.rows` from
it, so a fresh open lands on row one with the correction already applied as its starting point rather
than as a live change. The rebuild also discards a previous open's accumulated dims, which is what
keeps a correction from bleeding across opens.

**The reading row cannot poison the diff.** `readingRow` at `:174` carries no `item` field, and it is
only ever returned inline by the two row suppliers, never stored into `entry.rows`, so `pathKey(row.item.path)`
in `sameAsLive` and `mergeFresh` can never meet it.

**Decision six held.** No new lib unit, no new tool, no DEPENDENCIES manifest touched, and the
reconciler regenerated every generated manifest and left git status clean.

## Verdict

Not ready.

The migration half is clean and I would take it as it stands, it follows VPN's proven shape without
drift and I could not find a wiring that fails to resolve. The cache half is where the three highs
live, and none of them is exotic.

H1 fires on an ordinary Window menu with two same titled windows and turns the free case, an
unchanged read, into a disk write and a refresh on every open, which inverts the point of decision
two. H2 and H3 are both permanent wedge shapes, one freezing an app's cache for the load and one
killing the open path for that app until a file is removed by a sweep that M1 may prevent from ever
running. H3 in particular is the one thing the brief's acceptance names outright, the store must fail
toward the empty first open, and it does not.

The rework I would ask for. Compare and merge duplicates by multiset rather than by set. Bound the
accessibility read the way the VPN legs are bounded and clear `reading` on the timeout. Validate the
elements of a loaded snapshot and answer nil for the file on the first bad one, with a version field
written alongside. Advance the freshness timestamp on use rather than on change. Sanitize the bundle
id before it becomes a filename. Gate the correction on this plugin's own list being up, which means
declaring the `onClose` the presentation contract already offers. Sweep the recency settings key
beside the file, and pass a limit.

The four mediums are each a few lines and I would not split them into a second pass. The lows can
travel with them or wait.

---

# Second pass, 2026-08-27, verification of the rework at 7f5d1c3

feat/menusearch-cache, 7f5d1c3 on top of 5580de8, same worktree. Focused verification of the
three highs, four mediums and eight lows, plus the builder's dispute of L6. Gates rerun by me
from the worktree root.

    luac -p on lib/services.lua, plugins/menusearch/init.lua and plugins/menusearch/manifest.lua,
      all clean
    src/check-dependencies.sh, "Dependency check passed, 0 warning(s)", exit 0
    git status clean after the reconciler ran

One medium still open, four new lows, one finding conceded.

## Verdict per finding

### H1, duplicate paths. Fixed for the realistic case, one narrow residual.

`plugins/menusearch/init.lua:146`, `keyedList` walks a list in its own order and appends an
occurrence count, so two same pathed leaves become `path#1` and `path#2`. Every identity site now
reads `r.key` rather than recomputing `pathKey`, so `sameAsLive` compares keyed sets that are
multisets in effect and `mergeFresh` appends a second occurrence instead of swallowing it.

I attacked the reordering case the coordinator named and it holds. `sortForOpen` at `:356` calls
`keyedList(items)` first and hands the result to `recency.order`, so keys are assigned from the
stored list's own order and only then reordered for display. Both sides of every comparison key
the same raw list the same way, `onLanded` keying `freshList` and the next open keying
`entry.snapshot`, which is that same raw list. So the recency sort can never shift a key.

If the accessibility walk returns two same pathed leaves in the opposite order between two reads,
the key set is unchanged, and because duplicates share a path they also share a shortcut, so
`sameAsLive` still answers equal. No flap. Recency cannot cross wire either, and for a stronger
reason than the keying. Both duplicates dispatch `app:selectMenuItem(item.path)` with the identical
path, `menuSearchSelect` at `:660` and `scopeMenuRun` at `:735`, which macOS resolves to the first
match, and both rows render identically from the same path and shortcut. So a touch landing on the
other occurrence after a flip is unobservable in what is shown and in what runs.

The residual is N4 below, two leaves sharing a path but carrying different shortcuts.

### H2, the unbounded walk. Fixed. On the disputed point the builder is right and their own comment is wrong.

`beginRead` at `:514` races `entry.readTimeout` against the real callback through one `finish`
closure, timer held on the entry rather than a local, the hazard this track already names twice.
The stuck `reading` flag is gone, a wedged walk now clears itself after five seconds and the next
open starts a fresh one.

On the generation counter, I traced it rather than reasoned about it. `local fired = false` at
`:520` is one upvalue per walk, and both the timeout and the real callback call the same `finish`,
which opens with `if fired then return end` at `:526`. So exactly one of the two ever runs the
body.

The coordinator's hypothesis is half true and the half that matters fails. The timeout path does
clear `entry.reading`, and a second walk can indeed start while the first callback is still
pending. But when that first callback finally fires it calls the same `finish`, finds `fired`
already true, and returns at `:526`. It never reaches the generation check at `:532`. And the
generation check cannot fail for any other reason either, because `entry.reading` is cleared only
inside `finish`, below `fired`, so no newer walk can have begun at the moment a walk's own `finish`
body runs. The guard is unreachable.

So the builder is right that it is redundant, and right about the mechanism, `entry.reading` blocks
a new walk until `fired` flips. What is wrong is the code comment at `:509` through `:513` and the
commit message, both of which describe the guard as catching a late answer after a newer walk began.
That late answer is caught by `fired`, not by the generation. See N2, which is sharper than the
redundancy itself.

### H3, the malformed snapshot. Fixed.

`validItems` at `:271` checks every element, a path that is a table of at least one string and a
shortcut that is nil or a string, which is exactly the shape `titleAndParents` would otherwise raise
on. `loadSnapshot` at `:294` requires both the version match and that check before it trusts
anything, and removes the file otherwise at `:296`, logging a removal it could not perform. So a bad
file degrades to the first open reading row once rather than raising on every open forever, which is
what the brief's acceptance sentence asks for.

The version field also gives the 5580de8 era file a clean exit. Its `data.version` is nil, the
comparison fails, the file is deleted, and the open falls back to a fresh walk. L8 is closed by the
same edit.

### M1, the sixty day clock. Fixed.

`touchSnapshot` at `:315`, called from the unchanged branch of `onLanded` at `:488`, so the file's
clock now advances on use rather than only on change. `hs.fs.touch` when the build carries it, with a
read and rewrite fallback otherwise. See N5 on the cost of that fallback.

### M2, the bundle id as a filename. Fixed, and the encoding is genuinely reversible.

`encodeBundleId` at `:248` percent encodes everything outside `[%w%.%-_]`. I checked that `%`
itself is outside that class, since it is not alphanumeric, so it is encoded to `%25` and the
encoding is injective. `decodeBundleId` at `:252` is a true inverse, and a bundle id that already
contained a literal `%41` round trips as `%2541` and back rather than decoding into something else.

Traversal is closed. A slash becomes `%2F`, so `../../x` writes `..%2F..%2Fx.json` inside the
snapshot directory. Dots stay safe, so a bundle id of `..` produces a file literally named
`...json` rather than a parent reference, since traversal needs a separator and there is none.

The sweep stays reversible with it, decoding at `:578` before asking `pathForBundleID`, and an
ordinary reverse DNS id encodes to itself so nothing already on disk is orphaned.

### M3, the highlight gate. Partially fixed. Closed on the picker, still open on the launcher scope.

`atRowOneNow` at `:451` consults `entry.open` first and only then the shared row, and
`menuSearchOnClose` at `:688` clears it. My original scenario is closed and I walked it. Open menu
search, arrow to row five, press Escape, the stage fires the presentation's own onClose, `entry.open`
goes false, the read lands, the gate answers true, the correction applies and is written to disk
instead of sitting in memory against a row number a hidden widget is still holding.

The launcher scope door is not closed, N1 below.

### M4, the recency store. Fixed, with one new low.

A limit of fifty at `:92`, so each settings key stays small regardless of how large an app's menu is,
and the sweep drops the key and the in memory instance beside the file at `:587` and `:588`. The key
is built from the decoded bundle id, so it matches what `recencyFor` wrote. See N3 on how the key is
deleted.

One consequence worth naming rather than a defect. This widens L1 slightly. A transient
`pathForBundleID` miss, an app on an unmounted volume at sweep time, now costs the remembered order
as well as the regenerable file. Still cheap, still self healing except for the ordering, and L1 was
left deliberately.

### The lows

L2 fixed, both halves, a symlink guard on the cache directory at `:558` and on each entry at `:570`.
L5 fixed, both `os.remove` sites check and log, `:296` and `:583`. L4 fixed, the type guard at `:341`
plus the sentence in `lib/services.lua:247` naming the opt out as deliberate and naming the condition
under which it stays correct, which is the two sided documentation the finding asked for. L7 fixed, a
manifest sentence naming the unread panel triple as deliberate and matching VPN. L8 fixed inside H3.

L1 and L3 left, and both dispositions are honest. I graded L1 cheap and self healing and proposed no
fix, so leaving it is what my own text supports. L3 has no cheap fix and the code now names the gap
in place at `:370` rather than leaving it silent, which is better than when I filed it.

### L6, conceded.

The builder is right and I was wrong. Re reading the two sites, `openApp` at `:631` writes
`entry.rows = entry.snapshot and buildRows(...) or nil`, which yields an empty table for a snapshot
that exists and holds nothing, and nil only when there is no snapshot at all. `menuSearchRows` at
`:642` returns the reading row only on that nil. So nil means never confirmed and an empty table
means confirmed empty, a real distinction that the code implements deliberately, not the collapse I
described. Showing an empty list for a menu we have confirmed is empty is the honest answer, and the
reading row belongs to the genuinely unknown case. Withdrawn.

## New findings

### N1. The highlight gate is still blind on the launcher scope door. Medium, confirmed.

`openApp` at `:625` stamps `entry.open = true` on every call, both doors alike, and
`menuSearchOnClose` at `:688` clears only `pickerEntry.open`. The launcher's own close never reaches
this plugin, since the presentation that hid is the launcher's and not menu search's, so an entry
whose last open came through `scopeMenuRows` has its flag stuck true for the rest of the load.

The sequence is my original M3 scenario on the other door. Open the launcher, type the menu alias,
arrow down to row five, press Escape. `entry.open` is still true, so `atRowOneNow` falls through to
`cfg.stageSelectedRow()`, which reads the hidden `hs.chooser`'s retained row five,
`lib/chooser/providers/native.lua:756` through `:760` being this tree's own evidence that the row
survives a hide. The gate defers, the correction sits in `entry.pendingFresh` in memory only, no
disk write happens, and a reload before the next open of that app loses the read.

There is a second, smaller edge in the same place. `menuSearchOnClose` clears whichever entry
`pickerEntry` points at, so if the picker last ran on app A and the scope on app B, closing the
picker clears A's flag while B stays stuck.

The brief's own acceptance says "The launcher scope path behaves identically to the picker path", so
this is a contract miss and not only a defect.

The fix I would take is not in this plugin. `Stage:selectedRow()` at `host/stage/init.lua:829` is
`self._instance and self._instance:selectedRow() or nil`, with no visibility guard, which is the
root of the whole hazard and the reason `entry.open` had to be invented. Returning nil unless
`self:isShowing()` is one line, closes both doors at once, makes `entry.open` almost unnecessary,
and stops the next consumer of this new root word from having to rediscover that a hidden chooser
lies about its row.

### N2. The generation guard is unreachable, and its own timer stop is ordered above it. Low, confirmed.

Beyond being redundant, which H2 above settles, the guard is placed so that it could not work even
if it were reachable. `finish` stops and nils `entry.readTimeout` at `:528` through `:530`, then
checks the generation at `:532`. In the exact scenario the comment describes, a stale callback
firing after a newer walk began, those two lines would already have stopped the newer walk's timer
before the guard returned, reintroducing H2 for that walk, an unbounded read with nothing left to
time it out.

So the code is correct today only because `fired` makes the whole path dead. Anyone who later
restructures `finish`, or moves the timeout onto its own gate the way VPN's `landedGate` does, gets
a live bug that the guard was supposed to prevent. Either delete the guard and the comment that
justifies it, or move the timer stop below the generation check so the two agree.

Related and worth one line rather than its own finding. A walk that genuinely takes longer than
`READ_TIMEOUT` has its real answer discarded permanently, since `fired` is already true when it
lands. That matches VPN's own precedent, where a timed out leg never writes, and five seconds is
roughly ten times the worst the probe measured, so it is a defensible choice rather than an
oversight. It is not stated anywhere.

### N3. The settings key is deleted through a call the tree uses nowhere else, inside an unprotected loop. Low.

`:587`, `hs.settings.set(recencySettingsKey(bundleId), nil)`. This is the only
`hs.settings.set(..., nil)` in the whole tree, and Hammerspoon's documented deletion call is
`hs.settings.clear(key)`. Passing nil as a value may delete, may store a null, or may fail argument
checking depending on the build.

The consequence of the third case is what makes it worth naming. The per file body of
`pruneDeadSnapshots` has no pcall around it, so a raise there aborts the rest of the sweep for that
Hammerspoon load, leaving every file after the failing one unswept with only whatever Hammerspoon
logs for the timer callback. `hs.settings.clear` is the same length and is the documented call.

### N4. Two leaves sharing a path but not a shortcut still flap under an unstable order. Low.

The keying is positional, so if two same pathed leaves carry different shortcuts and the walk
returns them in the opposite order between two reads, `sameAsLive` at `:412` compares
`live[key#1]` against a fresh `key#1` that is now the other leaf, the shortcuts disagree, and the
read reports changed. The merge then rewrites both rows, the snapshot is written, and a refresh
fires, with nothing visibly different once the two have swapped back.

This is the same class H1 closed, narrowed to a case that needs three things at once, duplicate full
paths, differing shortcuts between them, and an ordering that is not stable across reads. Duplicates
in practice come from same titled windows and documents, which carry no shortcut at all, so I could
not construct a realistic instance. Recording it because the identity is positional rather than
intrinsic, which is what makes it possible at all.

### N5. touchSnapshot's fallback turns the cheap path into the expensive one. Low.

`:315` through `:324`. When `hs.fs.touch` is absent the fallback reads the whole json back and
rewrites it. That runs on exactly the path decision two exists to make free, a landed read that
proved nothing changed, so on such a build every open of every app pays a full snapshot read and
write to advance a timestamp. `os.time` written into the file as a `lastUsed` field would cost the
same write, and reading the field rather than the mtime would survive a backup restore too, but the
simplest close is to leave the fallback out and accept that a build without `hs.fs.touch` ages
snapshots by change rather than by use.

## What I rechecked and found sound

**Both doors still serve one source and still cannot double fetch.** `beginRead`'s guard at `:515`
is unchanged, `entriesByBundle` is still keyed by bundle id, and both `menuSearchOnPresent` and
`scopeMenuRows` still reach the same `openApp`.

**The presentation still satisfies the call kind rule with its new member.** `onClose` is declared
`{ member = "onClose", call = "dot" }` beside the other four, stated rather than defaulted, and
`self.onClose = menuSearchOnClose` is assigned in configure at `:774`, so `memberResolves` finds a
real function on the finished module at register.

**Adding onClose did not disturb the stack semantics.** The stage tells a discarded level, a popped
level and every level on a genuine dismissal, so `menuSearchOnClose` fires exactly once per real
close and never on a swap, which is what the flag needs.

**The keyed identity reaches recency on both doors.** `menuSearchSelect` at `:660` and
`scopeMenuRun` at `:735` both touch `item.key` and `payload.key` while dispatching `item.path`, and
`buildRow` at `:207` carries `key` into `item`, so the two doors cannot disagree about which
occurrence was chosen.

**The sweep's containment is now belt and braces.** It already could not be steered outside the
directory, since `hs.fs.dir` names hold no separator, and `os.remove` on a symlink takes the link
rather than the target. The two new symlink guards close the one shape that was left, a directory
replaced wholesale.

**The reconciler still passes and nothing outside these three files moved.**

## Verdict

Not ready, by one line.

Every high is closed, three of the four mediums are closed, five lows are closed, and the two lows
left unfixed have honest dispositions. The rework is good and the H1 keying in particular survives
the reordering attack for a better reason than the commit message claims, since duplicates are
functionally interchangeable at dispatch.

What holds it back is N1. M3 is closed on the picker and open on the launcher scope, and the brief's
acceptance names that path explicitly as having to behave identically. The fix is not in this plugin
at all, it is a visibility guard on `Stage:selectedRow()` at `host/stage/init.lua:829`, one line,
which closes both doors and stops the next consumer of that root word from inheriting a method that
lies about its row while the window is hidden.

I would take N1 and N3 before the gate, since both are one line and N3 can abort a sweep. N2 is a
comment and a two line reordering and can travel with them. N4 and N5 can wait.
