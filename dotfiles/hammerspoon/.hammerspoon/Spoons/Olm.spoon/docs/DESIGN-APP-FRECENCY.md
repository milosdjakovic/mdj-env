# Frecency in the app, step 1.4d

A design note for step 1.4d of `docs/PLAN-STANDALONE.md`, written and agreed with Milos on
2026-11-10, both questions below answered as proposed. Today every bonus in the app's file search is zero and its recent list is
dates alone. This step gives the app the same memory of what you use that the Lua list has, in
`plugins/filesearch/frecency.lua`, so no feature is lost at the flip.

## What a person gets, the same as the Lua list

1. **What you use leads among equals.** A row you use carries a bonus, the use count saturated
   into zero to one, used over used plus two, `engine:preference`. The shared search reads it only
   between rows it calls equally good, so it never lifts a worse match. That holds on a search, on
   the recent list and on a folder.
2. **The list you land on starts with your habits.** With nothing typed, and below `minChars`,
   the eight paths you use most, `recentFloat`, lead the recent list, then the dates. A path the
   date list already holds is moved up, and one it lacks is built and stat'd, `engine:_float`. A
   path that is gone is forgotten as it is passed over.
3. **Every action on a row counts, all the same.** Open, Reveal in Finder, Copy Path, Copy File,
   Into Folder and Quick Look each note the row, `chooser.lua`'s `noteUse`. The `..` row and the
   permission rows do not.
4. **The preview pane says when you last used it.** A USED fact after ADDED, in the subtext tone,
   as `viewers/sidepanel.lua` draws it, and only on a row you have used.

## How it works

- **The same store, ported.** `Frecency.swift` holds one number and one time per path, decays by
  the half life when it is read, adds one on a use, and drops the weakest past `maxEntries`.
  `frecencyHalfLifeDays`, `frecencyMaxEntries` and `recentFloat` already come over in the file
  search share's limits. It is written to `~/.olm/state/filesearch/frecency.json`, the folder the
  app keeps for this plugin, outside the watched config tree for the same reason the Lua store is.
- **One owner at every moment.** The list that serves file search records the uses. While the
  Lua list serves, the app records nothing, since it is never opened.

## Two things Milos decided, 2026-11-10, both as proposed

1. **How the Lua history reaches the app.** Proposed: the root writes it into a share for a
   served list, `filesearchhistory.json`, from a word the plugin answers, `frecency.export()`, so
   the `hs.settings` key stays named once, in the plugin's `init.lua`. The other way, the app
   reading Hammerspoon's defaults domain itself, would put a second copy of that key and of
   Hammerspoon's bundle id in the app.
2. **When the app takes it.** The plan says once at the flip. Every trial is a flip and a back
   out, so "once ever" would freeze the history at the first trial and miss weeks of Lua uses at
   the real flip in 1.5. Proposed: the app takes the Lua history whenever it holds a use newer than
   the newest the app took last time. While the app serves, the Lua side records nothing, so its
   newest use stands still and a reload takes nothing. After a back out and more use in the Lua
   list, the next flip takes the newer history. The app's own uses since then are replaced, as
   the plan already accepts in the other direction, the Lua side keeping its copy so a back out
   loses nothing that came before.

## The shadow

The recent list skip goes. Its order follows each side's history, and in shadow the app's history
is not the one the Lua list is using, so the recent list is compared with frecency left out on
both sides, its floated rows and its bonus, as a search already leaves the bonus out. The date
half is then compared like any other list.

## Left out

- A frecency step in scope resolution, so an unaliased folder you use resolves. The Lua side has
  none either, and `plugins/filesearch/AGENTS.md` says why.

## How it is checked

- `olm-index-check` cases for the decay, the trim, the float moving a held row and building a
  missing one, a gone path forgotten, the bonus on a search row, each action noting a use and the
  `..` row noting none, the import taking a newer history and leaving an older one, and the USED
  fact.
- A unit case for `frecency.export()`, and a bridge check that the share is written only for a
  served list.
- A hand trial in the app, then in the Lua native list to see nothing moved there.

Revised in the build, 2026-11-10. The plugin's word is `history`, answering `frecency.export()` as
`{ entries = ... }`. The share's being written only for a served list is the bridge's `shareEach`,
which `test/bridge.lua` already checks for every share, so no check of its own was added, and the
unit case `test/cases/filesearch-frecency.lua` checks the export and the dates handed to the shadow.

Revised at the flip, 2026-11-12, Milos choosing it. Taking the other side's history whole, the
second answer above, would lose uses once the app serves for good, since the launcher's slash scope
stays on the Lua file search until stage 3 and records its uses there, and a newer Lua use would
then replace every use the app had made. Going back would lose the app's in the same way. So both
sides merge instead, each path keeping whichever side used it last, the higher score breaking a
tie, `Frecency.merge` and `frecency.merge`. The app merges the Lua history share on an open when the
file has changed, and the root hands the Lua plugin the app's store, `~/.olm/state/filesearch/
frecency.json` read through the bridge's `appState`, on every load, served or not, through the
plugin's new `takeHistory` word. A use counted on both sides keeps one side's count, the one used
last, which shifts that file's bonus a little and loses no file.
