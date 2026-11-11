# Plan, Olm as an app of its own

Written 2026-11-05. The goal is the one Milos stated. Olm becomes a native macOS app that needs
no Hammerspoon, with a launcher that runs no Lua and never lets a search hold up typing, leader
keys built in so kanata and Karabiner are no longer needed, built in plugins written natively and
extensions beside them on a plugin API comparable to Raycast's. It gets there in small steps.
Olm.app is built first and runs beside Hammerspoon, kanata and the Karabiner driver, and each step
moves one responsibility across. The decision record is `decisions/olm-standalone.md` at the
repository root.

The route has a resting point, the end of stage 3, where Olm.app is its own thing. It owns every
list a person opens, the typing, the search and the navigation, on threads of its own, and it
reaches Hammerspoon as a dependency for keys, app switching, window management and every plugin
not moved yet, while kanata and the Karabiner driver stay as they are. Work can stop there for as
long as wanted, and everything after it is optional and taken at any pace.

## Progress

This list is the one place progress is kept, so any session on any machine starts here. A step is
ticked in the same commit that finishes it, with the date and the short hash of that commit after
it, and the Next line moves to the step after. A step started and not finished stays unticked and
gets one line under it saying where it stands and on which branch. A decided open question is
ticked with what was decided, and the decision goes into `decisions/olm-standalone.md` in the same
commit.

Next. 1.5 parity, with 1.3e, 1.4g, 1.4f, 1.4c, 1.4k, 1.4h, 1.4e, 1.4d and 1.4i ticked since. Then the flip
last.

Stage 0, contracts
- [x] 0.1 The decision record, 2026-11-05
- [x] 0.5 Gather LuaSkin into one Swift file, 2026-11-06
- [x] 0.2 Fixtures for ranking, 2026-11-07
- [x] 0.4 The bridge protocol, on paper, with its adversarial review, 2026-11-07
- [x] 0.6 A data source protocol in front of the library, and the package build, 2026-11-07
- [x] 0.3a Fixtures for the file search grammar, 2026-11-07
- [x] 0.3b Fixtures for the bottom bar model, 2026-11-07
- [x] 0.3c Fixtures for keymap resolution, 2026-11-07
- [x] 0.3d Fixtures for `KeyRemap.allocate`, 2026-11-07
- [x] 0.3e Fixtures for list keys, 2026-11-07

Stage 1, the file search pilot
- [x] 1.1 The app shell, 2026-11-07
- [x] 1.2 The trigger, 2026-11-07
- [ ] 1.3 Search, open and reveal, shadow then flip, in six parts
  - [x] 1.3a The file search grammar in Swift, its fixtures passing, 2026-11-07
  - [x] 1.3b Ranking in Swift, `match.lua` and `rank.lua`, the rule and corpus fixtures passing, 2026-11-07
  - [x] 1.3c The index in the app, the helper's sources searching on background work, 2026-11-07
  - [x] 1.3d The app's own list, rows ranked as typed, open and reveal, in the swift chooser's own look, 2026-11-08
  - [x] 1.3e The shadow, both sides answering each query and the differences logged, every one explained and fixed, 2026-11-09
  - [x] 1.3f The three timings against the Lua file search, and a trial, with no flip, 2026-11-08
  - [x] 1.3g The app's structure, `docs/DESIGN-APP.md`, file search moved onto it with nothing a person can see changed, 2026-11-08
- [x] 1.4a Preview pane, with its scroll keys, the keys themselves carried by 1.4f, 2026-11-08
- [x] 1.4b Thumbnails, the pane never stale and a picture on its way shown by the system spinner, 2026-11-09
- [x] 1.4c Quick Look, 2026-11-10
  - Its design note is agreed, `docs/DESIGN-APP-QUICK-LOOK.md`. The first build, the Lua helper's panel opened in the app's own process, went to its trial on 2026-11-10, where Milos asked for an Olm glass pane in the core instead. The note was revised and agreed the same day, and the Quick Look pane is built on branch `olm-app-quicklook` in the swift chooser's shared library for both lists, following the highlight. It passed its hand trial on 2026-11-10 in the app and in the Lua native list, with the header one actions pane line tall, the close the circled xmark symbol and the Return key cap at the inset's edge on the pane's corner radius, Milos's asks in that trial.
- [x] 1.4d Frecency, one owner, the history read but not yet owned, 2026-11-11
  - Its design note is agreed, `docs/DESIGN-APP-FRECENCY.md`. Built on branch `olm-app-frecency`, the store ported to `Frecency.swift` in the app's state folder, the bonus on every row, the float on the plain recent list, a use noted on every action but the `..` row's, USED in the preview pane, the Lua history handed over through the root's new history share and taken when it holds a newer use, and the shadow comparing the recent list with frecency left out on both sides. Its hand trial is next.
  - In that trial on 2026-11-10 Milos asked that the files you have used lead the list you land on by when you last used them, not how much. Built on branch `olm-filesearch-recent-order`, from `olm-app-frecency`, in both lists at once, the store naming two orders, `use` and `lastUse`, and `config/filesearch.lua` saying which leads with `recentFloatOrder`, read by both lists from the same share. It joins 1.4d's hand trial, `decisions/olm-filesearch.md` has it.
  - It passed its hand trial on 2026-11-11 in the app and in the Lua native list, the store taking the Lua history and keeping every use across a quit, Copy Path and Copy File noted, the new order leading in both. The trial found two faults in the Lua list, both fixed on the same branch and confirmed by Milos. Reveal in Finder, Copy Path and Copy File left it open, its manifest never having declared `stageHide`, and the file just used moved up only after the list appeared, now floated again in memory as the use is noted. A blank half width pane once lingered after the app's list closed and was gone before it could be read, open.
- [x] 1.4e Folder search, the scope, the folder aliases, Into Folder and Up a Level
  - Its design note is agreed, `docs/DESIGN-APP-FOLDER-SEARCH.md`. Built on branch `olm-app-folders`, a browse through `/bin/ls` with the `..` row, a search beneath a folder through fd as `walk.lua` runs it, fd's path handed over by the root's new tools share, the folder aliases and the prune list in the file search share, Into Folder and Up a Level through a `setQuery` effect, and the shadow comparing a browse. It passed its hand trial on 2026-11-10 in the app and in the Lua native list.
- [x] 1.4f The bottom bar, the actions pane, the info pane, Copy Path, and the person's list keys, the preview pane's scroll keys among them, 2026-11-10
  - Its design note is agreed, `docs/DESIGN-APP-LIST-KEYS.md`. Piece 1, the keys, is built on branch `olm-app-list-keys` and passed its hand trial on 2026-11-09, with the preview scroll moved to Hyper and D or U in both lists and every list's Delete on Hyper and R, asking first where the verb declares confirm, and merged. Piece 2, the bar, the info pane and the field keys from the share, passed its hand trial on 2026-11-09, with every pane closing on a key that acts on the list and on a scroll or a press behind it, and merged. Piece 3, the actions pane, passed its hand trial on 2026-11-09 and merged, its rows Open, Reveal in Finder and Copy Path, with Quick Look left to 1.4c and Into Folder and Up a Level to 1.4e. The actions pane's own search field at its foot followed, in every list, Milos's ask in that trial, passed its hand trial on 2026-11-10 and merged. Piece 4, Command and a digit checked against the Lua list, passed its hand trial on 2026-11-10 on branch `olm-app-digits`, with a pane closed by the key that also closes the list now going down whole with it, in the app and in the Lua native list.
- [x] 1.4g Short queries, file search answering from the first letter on both sides, 2026-11-09
- [x] 1.4h A type naming a bundle, `.app` listing every app rather than Safari alone, in both file searches
  - Built on branch `olm-app-bundles`, the helper's `recent` keeping a folder whose name ends in a type asked for. It passed its hand trial on 2026-11-10 in the app and in the Lua native list, and merged.
- [x] 1.4i Files iCloud has not downloaded, a Download action and the preview pane naming its shortcut, after 1.4f, 2026-11-11
  - Its design note is agreed, `docs/DESIGN-APP-DOWNLOAD.md`, Hyper and G and the list staying up. Built on branch `olm-app-download`, Download declared in the Lua manifest with a gate the Lua list always answers no, the app answering it over a placeholder, asking iCloud through `CloudFiles`, the pane pending until the stat flag clears and then reading the file, a new `refreshPreview` effect asking the pane again, and the body's `shortcut` the stage spells from the keys share.
  - It passed its hand trial on 2026-11-11 in the app and in the Lua native list. Milos found the spinner alone looked like nothing was happening, so the download now shows how far it has come, the bytes in the preview's words and `kit.meter` under its heading, a new component of the shared UI kit, a light grey track filled black, or with the macOS accent when the highlight follows it.
- [x] 1.4j Folder permissions asked up front on file search's first open, asked again from the list, and kept across rebuilds, 2026-11-09
- [x] 1.4k Copy File and Copy Folder in file search, both lists, the file itself put on the clipboard as Finder's Copy puts it, beside Copy Path, asked by Milos on 2026-11-10, after 1.4c
  - Built on branch `olm-app-copyfile`, Hyper and C, its word Copy Folder over a folder through the presentation's labels member by action name, which the bottom bar, the info pane and the actions pane all read, and in the app through the source's label. It passed its hand trial on 2026-11-10 in the app and in the Lua native list, and merged.
- [ ] 1.5 Parity, every feature of the Lua file search checked in the app, then the flip
  - The written list is `docs/PARITY-FILESEARCH.md`, on branch `olm-app-parity`, read from the code on 2026-11-11. It found four gaps, the index never rebuilt while the app serves, which blocks the flip, the subtitle not fitted to the row, the empty states as a plain line rather than rows, and `pruneLocal` missing from a scoped walk. Closing them is next, then the hand check of every line.

Stage 2, the bridge, read only
- [ ] 2.1 Probe the transport
- [ ] 2.2 `host/bridge` serves, read only
- [ ] 2.3 Shadow ranking for the launcher

Stage 3, every list in the app
- [ ] 3.1 Choosing a row over the bridge
- [ ] 3.2 The app's launcher on a trial key
- [ ] 3.3 Hosted lists, one tool per step, each tool added here when it is started
- [ ] 3.4 List keys reach the app
- [ ] 3.5 The flip of Hyper and Space
- [ ] 3.6 Every plugin's own list, each tool added here when it is started

The resting point
- [ ] All five conditions of the resting point hold, checked on every machine whose `olmapp` piece is on

Stage 4, plugins native, optional
- [ ] The app catalog and its recency
- [ ] Emoji
- [ ] Menu search
- [ ] Clipboard, the monitor and the store together
- [ ] The extension host and its first extension

Stage 5, keys, optional
- [ ] 0.3f Fixtures for the chord engine's timing
- [ ] 5.1 The app hears the leaders in shadow
- [ ] 5.2 Cheat sheets in the app
- [ ] 5.3 Key ownership, META
- [ ] 5.3 Key ownership, Hyper
- [ ] 5.4 The key daemon

Stage 6, self sufficient, optional
- [ ] Each system plugin, added here when it is started
- [ ] The settings window and its config model
- [ ] The first run through the permissions
- [ ] Signing and notarization
- [ ] Hammerspoon switched off on a machine

Open questions
- [x] 1 Where Olm.app lives, in this repository until Olm is decoupled, 2026-11-07
- [ ] 2 Unix socket or local HTTP
- [ ] 3 What extensions are written in
- [ ] 4 Leaders in a password field
- [ ] 5 The calculator
- [ ] 6 Lua after Hammerspoon

## Ledger

Kept at Milos's request, 2026-11-07, as the running account of each step. It says what went wrong
along the way, what fixed it, and what was left open. Each entry is a few lines and names its
commit. The reasoning behind a decision goes into `decisions/olm-standalone.md`, and this ledger
only points there. An entry is added in the same commit as the work it describes, and an item that
gets closed later is marked closed with the date. It is never deleted.

**Before 1.1, the file search freeze, `b08d43cf`, 2026-11-07.** This was not a plan step, and rule
7 welcomes it. Typing in file search froze because the preview pane stat-ed, read or listed the
highlighted path on the main thread on every keystroke. That took 1643 ms of one 1728 ms stall.
Fixed: reads go through `fileindex peek` in the helper, after the highlight has rested for
`preview.settleMs`. Issue: the first live trial ran on the fallback chooser, because a new build
serves only after a reload. Fixed: the Hammerspoon `AGENTS.md` now says to check
`providers.swift.serving()` before a trial. Result: the worst stall fell to 169 ms, median 43 ms.
Open:
- The trial lasted only about 20 s.
- These stalls were measured before the fix and not since:
  - `stage._show` up to 161 ms
  - `view.redraw` up to 27 ms
  - `native show` 47 ms
  - `native update` 28 ms, much of it the bottom bar's layout
  - thumbnails decoded on the main thread
  - `rowsOf` 55 ms per 2000 index lines

**0.5, `a0dcde27`, 2026-11-06.** Issue: the plan named too little. The plan listed seven lines of
`Pane.swift`, but all of `PaneReader` reads Lua, and so do five initialisers in `Model.swift`.
Fixed: all of them moved into `Lua.swift`.

**0.2, `178e05f1`, 2026-11-07.**
- Issue: the dry gate has no `hs.json`. Fixed: a reader of its own, `test/json.lua`.
- Issue: the ranking rules alone are about 60 cases, which is too few to check a Swift port of the
  matcher. Fixed: a recorded corpus of 74 queries.
- Issue: cases that use a hand-written matcher have no JSON form. Left: they stay in Lua tests.
- Open: `test/swiftpane.sh` failed once inside `suite.sh dry`, and it passed every run since. The
  output was not kept. If it fails again, keep the output.

**0.3a, `38781569`, 2026-11-07.** Issue: the grammar had no test of its own. Fixed: its cases are
taken from the rules in `query.lua`'s header. Issue: five comments claimed that `~/dev .js foo`
ranks by foo, which is false. Fixed: they now say `.js ~/dev/ foo`. Open, for Milos: should a
type after the scope filter? Today it does not, and `parse.json` pins that.

**0.4, `672d0bdc`, 2026-11-07.** Issue: the first adversarial review found 14 problems, 2 of them
critical. One of them: a single counter raised by typing starved the previews. The second review
found 9 more. Fixed: every one of them is answered in the text, and the designs turned down are
under Rejected in the decisions file. Left to the step that serves each tool:
- plugins that defer work and read the stage words later
- Clipboard's paste behind a nonactivating panel
- suppliers that build fresh item tables on every call
- fixed-header painters lagging on scroll

**0.6, `a7ac1b76` and `06c2f32f`, 2026-11-07.**
- Issue: SwiftPM in the command line tools fails with "Could not initialize build system". Fixed:
  the gate passes `--build-system native`, which is deprecated.
- Issue: the tools ship neither XCTest nor Swift Testing. Fixed: the smoke test is an executable.
- Issue: the package could not find `Perf`. Fixed: the probe moved out of `Entry.swift` into
  `Perf.swift`.
- Issue: `test/swiftpane.swift` still used the old initialiser. Fixed: it uses `NoSource`.
- Check: the live load served the swift chooser, and the console was clean.

**0.3b to 0.3e, `b74821b8`, 2026-11-07.** Issue: lifting these by hand meant transcribing a
1900-line module's tests. Fixed: `test/fixtures-record.lua` records the calls the existing tests
make. The recorder had these bugs:
- `dofile` was not hooked.
- The sandbox refused `io.open`.
- The module changes the tables it is handed, and copies broke that. Fixed: recorders are swapped
  in place and put back.
- The keycode proxies were not faithful, and the chords were hidden behind protected metatables.
- A callback that raised left no record.
- The dry gate's stand-in keycode table invents codes. Fixed: a table dumped from Hammerspoon,
  `test/fixtures/keys/keycodes.lua`.

Issue: two recordings differed between runs, because `lib/resolve.lua` filled its lists in `pairs`
order. Fixed: they are sorted. Result: 276 cases. Open: the live Hammerspoon has not been reloaded
since that sort. Recordings take 2.4 MB.

**1.1, the app shell, 2026-11-07.** Built:
- `app/` in the spoon, a Swift package with one executable, `Olm`, that depends on the swift
  chooser's package, so a change there that breaks the app fails its build.
- `app/build.sh` wraps it into `Olm.app`, signed ad hoc. The app has no Dock icon
  (`LSUIElement`), keeps one instance, and answers `olm://ping?nonce=N` by writing N to
  `~/.olm/run/ping`. Any other URL is logged and dropped.
- The `olmapp` machine piece, off by default. Where it is on, `src/setup-olmapp.sh` builds the
  app into `~/.olm/app` and registers it for `olm://`. Its tools are declared in
  `src/DEPENDENCIES`.
- `test/olmapp.sh`, eight checks.

Issues:
- The swift chooser's package passes unsafe flags. SwiftPM accepts that from a local path
  dependency, so nothing had to change.
- The release build takes about 56 s the first time.
- The test's check that Hammerspoon still answers failed at first, because `hs` read commands
  from a stdin that is no terminal and waited on it. Fixed: stdin is closed for it, and the
  Hammerspoon `AGENTS.md` now says so. This is probably also why `hs -q` seemed to print nothing
  earlier in the session.

Decided: the app's checks are programs, not `swift test`, so every machine with the command line
tools runs them.

Result: all eight checks pass. Quitting the app leaves Hammerspoon answering.

Open: `src/setup-olmapp.sh` has not run with the piece on, since switching it on for a machine
is Milos's call. It first runs at 1.2.

**1.2, the trigger, `9d531b5e`, 2026-11-07.** Built:
- `host/bridge`, a host with one question, `serves(identity)`. Where this machine's `olmapp` piece
  is on, the app is built and `open` resolved, it answers the function a served tool's open key
  runs instead, `open -g -a ~/.olm/app/Olm.app olm://filesearch?query=`, run as a task with its
  handle kept.
- The root swaps only that function on the keymap's open rows, after the keymap is built and
  before the binder binds, so the chord, the cheat sheet, the launcher row and every golden read
  the same. The composed record lists the swapped tools as `servedByApp`.
- How the machine's piece reaches Hammerspoon, decided in this step:
  `src/setup-hammerspoon-apps.sh` writes `~/.hammerspoon/machine-pieces.lua` from
  `src/machine.sh`, `config/machine.lua` reads it, and `config/plugins.lua` hands it to the
  bridge with the list of served tools, `{ "fileSearch" }`. There is no per machine keymap.
- Olm.app answers `olm://filesearch?query=TEXT` by showing the swift chooser's own panel with the
  text in its input field and an empty list, which says that search arrives with 1.3. It hides on
  Escape, on a press outside and when it loses key. Its layout is fixed in the app until 1.3.
- `test/bridge.lua`, 14 checks, in the dry suite.

Issues:
- `root/compose.lua`'s main function is at Lua's limit of 200 locals, so the first try failed to
  load under the dry gate. Fixed: the list is kept on the keymap table rather than in a new local.
- The dry gate refuses a host that names a plugin. Fixed: the served tools are a list in
  `config/plugins.lua`, and the URL is the identity lowercased.
- The rename proof found that the bridge asked about the piece only for a tool it served, so
  renaming plugins changed what was asked. Fixed: it asks about the piece first.
- The app reaches the panel's internal types through `@testable import`. Open: 1.3 makes the
  panel's API public.

Result: the dry suite and the goldens pass unchanged, the unit cases pass, the dependency check
passes, and a live reload on main with the piece off has a clean console, nothing served and
swift serving.

Trial, by Milos with the piece on. Hyper and `;` showed the app's glass chooser, and Escape and a
press outside closed it. It showed no files, which is expected, since search arrives with 1.3.
File search in the launcher, typed `/`, still searched on the Lua side. Back out: with the piece off
again the same key opened the Lua file search. Both verdicts: it works.

Issue: the first reload with the piece on came up on the fallback chooser, because the swift
library rebuilt itself in the background, and a second reload brought swift back. Why it rebuilt
with no Swift source changed is not known. Open: watch for it at the next reload.

Left on this machine: `~/.olm/app/Olm.app` stays built and registered for `olm://`, since switching
a piece off removes nothing. The machine's pieces file has no `olmapp` row, so it takes the default,
off.

**1.3a, the grammar in Swift, 2026-11-07.** Built:
- `app/Sources/OlmSearch/Query.swift`, the port of `plugins/filesearch/query.lua`. It reads the
  query as UTF-8 bytes, the way Lua does: Lua's six whitespace characters, ASCII-only lowercasing,
  and lengths and prefixes in bytes. So a word with an accent stays exactly as typed.
- `app/Sources/olm-fixtures`, the Swift side of the shared fixtures. It reads the same JSON files
  `test/fixtures.lua` reads, runs each kind the app has ported, and counts the rest as not ported
  yet, never as passed.
- `test/olmfixtures.sh` builds and runs it, and `suite.sh dry` runs it after `swiftpackage.sh`.

Result: all 45 grammar cases pass in Swift, 29 parse and 16 narrows. Broken copies of both files
failed 7 cases, and the runner exited nonzero. No issues. The 231 cases of the other kinds are
reported as not ported.

**1.3c, the index in the app, 2026-11-07.** Built:
- `app/build.sh` compiles the file search plugin's own `sources/fileindex.swift` into the app's
  bundle, so the app and the Lua side ask the same program. The plugin is unchanged.
- `app/Sources/OlmSearch/Index.swift`, `FileIndex`. It builds the same arguments `index.lua`'s
  `argsFor` builds, runs the helper on a queue of its own and answers on the main queue. A newer
  ask ends the older one's process, and drops its answer by generation.
- The app reads the index the Lua side builds, `~/.olm/cache/filesearch/file-index.txt`, and
  never builds one. So the index keeps one owner until a later step moves it.
- `test/olmindex.sh` and `olm-index-check`, 18 checks over a small folder, in the dry suite.
  `test/olmapp.sh` also checks the bundle carries the helper.

Issues:
- The command line tools' `swiftc` could not find the standard library when run directly. Fixed:
  it is given the SDK, `-sdk $tools/SDKs/MacOSX.sdk`.
- Two of the check's own expectations were wrong at first: "report" matches `Reports.app` too,
  since the helper ignores case. The test was fixed, not the code.
- `test/olmapp.sh` failed two checks because the installed app from the 1.2 trial was still
  running. It shares the bundle id, so LaunchServices handed it the test's URLs. Fixed: the test
  stops with exit 2 and names the other copy. The leftover was quit. Worth knowing: the app stays
  running after its panel closes, as an accessory app should.

Decided: the helper is reused as a program, not as a library. Its source is one file with
top-level code, which a package library cannot compile, and splitting it would have changed the
Lua plugin's build in a step that should leave the plugin alone.

Measured: a search of the real index, 170,196 entries, takes about 10 ms including the process
start.

**1.3b, ranking in Swift, `6770799f`, 2026-11-07.** Done by an agent in a worktree of its own
while 1.3c was built, then checked and cherry-picked onto main. Built:
- `app/Sources/OlmSearch/Match.swift`, the shared fuzzy matcher as `Fuzzy`.
- `app/Sources/OlmSearch/Rank.swift`, `RankRow` and `Rank.apply`, which answers the order as
  indices into the rows, plus the cut for the row of more.
- The `rank.order` and `rank.corpus` runners in `olm-fixtures`.

Details that mattered:
- JSON booleans are told apart from numbers by their Core Foundation type. Otherwise
  `"bonus": 1` reads as true and `"pinned": true` as 1, and the Lua checks depend on the
  difference.
- The sort ends on the row's place in the supplier's list. That makes it a total order, so
  Swift's sort answers the same as Lua's unstable `table.sort`.
- Numbers are doubles, added in Lua's order and grouping.
- `RankCut.at` is 0-based in Swift, where Lua's is 1-based.

Result:
- All 100 ranking cases pass, 26 order and 74 corpus, so `olm-fixtures` passes 145, with 131
  not ported, the launcher's and the calls kinds.
- A broken corpus case failed when checked by hand.
- The agent also compared 5176 generated queries over 77 hard rows against the Lua answers, and
  all agreed. The rows covered long fields, separators, camel humps, accents and symbol words.

Left imperfect:
- The long-field memo is not ported, so a field over 256 bytes is folded again on every call.
  Results are the same, only slower. The clipboard will want it.
- `Fuzzy` keeps per-instance caches and is not thread-safe, so the search queue owns one.
- A `searchText` that raises, and the `substring` and `words` strategies, are not ported, and
  nothing in the app needs them.

**1.3d, the app's own list, 2026-11-07, waiting for the hand trial.** Built:
- `app/Sources/OlmSearch/FileSearch.swift`, `FileSearchEngine`, the counterpart of
  `plugins/filesearch/engine.lua` for the unscoped search and the recent list.
  - It parses with the grammar, asks the index on its queue and ranks on a queue of its own,
    with the file name as the one searched field, as the Lua rows set `filterText`.
  - It narrows as the Lua engine does, so a grown text over the same files asks the index
    nothing.
  - Below `minChars` it ranks the recent list by the text typed so far.
  - A newer query drops an older answer.
- The app's chooser lists what the engine answers, with each file's icon fetched as its row
  comes on screen. Return opens the highlighted file, Command and Return shows it in Finder, and
  either closes the list.
- The bridge writes what the app reads of the config, file search's types and limits, to
  `~/.olm/run/filesearch.json`, only where the piece is on. The app reads it on every show, so
  `config/filesearch.lua` stays the one owner.
- 8 engine checks in `olm-index-check`, and 3 share checks in `test/bridge.lua`.

Not in this part:
- A scoped query, a folder walk on the Lua side, says it comes later.
- Frecency is 1.4d, so every bonus is zero.
- The preview pane is 1.4a.
- The row of more is not drawn.

Decided: the panel's API stays reached through `@testable import`. The package compiles it with
testing enabled, which a release build accepts, and making some forty types public would touch
every file of the swift chooser that Hammerspoon loads, for no behaviour. It comes back when
signing in stage 6 needs it.

Result: the dry suite, the unit cases, `test/olmapp.sh` and the dependency check pass. A live
reload with the piece off has a clean console, nothing served, and no share written.

Trial, 2026-11-08, with the piece on. Typing listed results as it went and Return opened the
file. Two findings.
- Every icon flickered on each keystroke, even when the results did not change. The app sent
  each row without its icon, and the list fetched icons only once the row was on screen, so every
  answer drew a frame of blank icons. Fixed: the app keeps each file's icon in a cache and sends
  it with the row, and an answer with the same files in the same order redraws nothing.
- The window has no preview pane, which is 1.4a. Milos stated rule 9 from this, that no feature is
  lost as the plan moves. 1.3f no longer flips, and 1.4e, 1.4f and 1.5 were added.

Second trial, 2026-11-08. The icons stayed steady, and Command and Return showed the file in
Finder. Milos asked why the window looked different, and said he does not want to see a
difference in the core's UI. The app had drawn on sizes, fonts and a corner typed into
`main.swift` by guess. Built next, the shared look:
- `look` on the swift provider builds an engine over a view whose native table only records, and
  asks it to describe each half through `Engine:describe`, the restyle and the place a show runs,
  with nothing shown. So what the app is handed is the very style and size tables the Lua view
  sends Hammerspoon's panel, never a second description of them. The kit gained `tokensFor(half)`
  for it.
- The bridge writes it to `~/.olm/run/chooser.json` through the new `share`, built only where the
  piece is on.
- `native/Fields.swift` is the one list of field names a style, a placement and the motion are
  read by. Hammerspoon's panel reads them off the Lua stack through `LuaFields` and the app out of
  the JSON through `JSONFields`, so the two cannot read a look two ways.
- `OlmLook` ports `geometry.resolve`, pinned by `test/fixtures/chooser/geometry.json`, 16 cases
  recorded from the Lua answer and checked by both runners. A copy with one value changed fails
  14 of them in Swift.
- The open key's URL carries Olm's placement choice at the press, `screen=activeWindow` or
  `screen=cursor`, since the Placement page changes it with no reload. The app finds the active
  window's screen through the window list, which needs no grant.
- The app now shows the row numbers and the Return key cap the Lua list shows. Command and a digit
  opens that row. A typed query with no rows says No results. The placeholder is file search's,
  shared with its settings, which is empty today, as the Lua list's is.

Still different, each one its own step: the preview pane, 1.4a. The bottom bar, 1.4f. The app
keeps the bar's height so its window is the Lua one's size, with its rows running on where the
bar will stand.

Result: the dry suite, 2124 unit cases, every Swift check and the dependency check pass. Two
reloads, the first building the changed library while the default chooser served, then swift
serving with a clean console. A live call of `look` answered both halves, the motion and a layout
of 480 by rows of 47 with a bar of 56.

Open: the trial of the shared look.
Closed 2026-11-08, the trial passed, below.

**The app's design, before 1.4, 2026-11-08.** Milos asked whether there is a plan for the app's
own architecture, better than the Lua Olm's. There was none, and the pilot lives in one
`main.swift`. `docs/DESIGN-APP.md` is that design now. It keeps the Lua Olm's principles, a
composition root, a plugin handed its whole world, a manifest as data and a plugin that never
draws, and lets the compiler hold them, each plugin a module that can import only the vocabulary,
the contract a protocol, and the threads checked by Swift 6's strict concurrency. Every list is
answered through one protocol, so a plugin going native is a second source under the same name
and the shadow is written once. Step 1.3g moves the pilot onto it before 1.4a.

Open: the design is on paper. 1.3g is the first time it meets code.

**1.3d ticked, the look trial, 2026-11-08.** With the piece on, Milos compared the app's file
search with the Lua one and found it good, the only difference the preview pane, which is 1.4a.
The swift library rebuilt itself once after the lock relaunched Hammerspoon, so the first reload
served the fallback and a second one served swift, as the Hammerspoon `AGENTS.md` warns. Then the
piece was switched off again, the app quit and the lock released, and Hammerspoon is on main.

**1.3e built, the shadow, 2026-11-08.** The plan had the app ask Lua through the command line.
Milos chose to keep the Lua file search as the daily one while the shadow runs, rule 9, so the
asking runs the other way. Each answer the Lua list settles on is ranked as the stage ranks it and
handed to the app, through `~/.olm/run/filesearchshadow.json` and `olm://shadow`. The app answers
it with an engine of its own and logs one line per query to `~/.olm/log/shadow-filesearch.jsonl`.
`serves` is empty while it runs, so file search's key opens the Lua list, and a trial adds the tool
back for the trial alone. A search leaves out frecency's bonus on both sides, and the recent list
and a folder search are logged as skipped, steps 1.4d and 1.4e.
Issue: the dry gate refused the shadow's `rank.apply` in `root/compose.lua`. Fixed: it ranks only
to compare and shows nothing, so both lines carry a search-exempt reason.
Result: the dry suite, 2124 unit cases and 40 bridge checks pass. A live check, with no screen
and no key, ran the Lua engine headless: `report` gave the same 155 files in the same order on
both sides, `invoice` nothing on both, and the empty query was skipped.
Open: a few days of real use. Then the log is read, and every line that is not `same` is a bug
fixed before 1.3e is ticked.

**1.3g built, the app's structure, 2026-11-08.** The pilot is on `docs/DESIGN-APP.md`'s layers.
`OlmKit` holds the vocabulary and `ListSource`. `OlmCore` holds the stage, which took the
highlight, the slots, the keys, the icon cache and the redraw that skips an unchanged answer out of
`main.swift`, the searcher that ranks every list on an actor of its own, the look and the shadow,
now written once for any source. File search is the module `FileSearchPlugin` under
`app/Plugins/FileSearch`, its grammar, its index and its source, depending on `OlmKit` alone, and
it answers rows unranked, the stage ranking them, and Return and reveal as effects. `main.swift` is
the composition root alone. The new layers build in Swift 6's language mode, the ported search,
the geometry and the check programs in Swift 5's.
Issue: a superseded index ask never answered, which an async ask cannot do without leaking its
continuation. Fixed: a cancelled ask ends the helper and throws, and the stage cancels the task
before it on every keystroke.
Issue: the shadow's headless check stopped writing lines. Cause: with no list open, the Lua stage
refreshes file search with its own empty query right after a search started from the console, so
the test, not the code, lost its query. The app half was checked with a request written by hand
instead, `report` answered with 155 files as before, and a folder query skipped.
One change a person can see: a long file name now loses its middle rather than its end, the
`truncateMiddle` the Lua file search declares, which the pilot never read.
Result: the dry suite, 161 fixtures, 24 index and source checks, and the dependency check pass.
Open: the trial by hand.

**1.3g ticked, 2026-11-08.** The trial by hand passed, with the app serving file search's key for
the trial alone. Typing, steady icons, a long name cut in the middle, Return opening, Command and
Return revealing and Command and a digit opening its slot all worked, and Milos called it good.
Its key went back to the Lua file search after, and the shadow runs on.

**1.3f built, the three timings, 2026-11-08.** The swift chooser's panel times itself,
`native/Timings.swift`, so the Lua file search inside Hammerspoon and Olm.app's are measured by the
same code on the same clock. Echo is a key down to the commit that draws the field with it, rows a
key down to the commit that draws the first rows sent after it, settled to the last rows sent
before the next key, and stall the longest gap on the main thread while the list is open. A key
whose rows did not change sends none, so it has no rows time. It runs only while
`~/.olm/run/timings` exists, each open writes one line to `~/.olm/log/timings.jsonl`, and
`test/timings.lua` reads it as a table per process and list.
Result: the dry suite, 2124 unit cases, the swift pane and package checks, 161 fixtures and the
index check pass, and the reader was checked on lines written by hand.
Open: the trial by hand, the same searches typed in each, large result sets among them.
Issue: in the trial, file search opened by its own key showed no rows for anything typed, while
the launcher's route to it worked. Cause: the shadow of 1.3e ran `open` to hand each answer to the
app, and running it while that list was up emptied it. The headless check of 1.3g that stopped
writing lines was the same fault, not the test. Fixed: the bridge starts the app once when the
shadow is wired and tells it each answer by a distributed notification, so nothing runs `open`
while a list is up. Milos checked file search by its own key with the shadow on.
Issue: with the app serving the key in round 2 of the trial, the key took focus and no list was
drawn. Cause: the bridge starts the app with `open -j`, hidden, and a hidden app's panel takes key
but is never drawn. Fixed: the stage unhides the app as it opens a list, checked by starting the
app hidden and Milos opening file search by its key.

**1.3f ticked, 2026-11-08.** The trial by hand ran the same searches in each, five lists in the
Lua file search and two with typing in the app, which is a first look rather than a large sample.
In milliseconds, median, 95th percentile and worst. Echo, Lua 46, 90 and 99, the app 28, 39 and
39. First rows, Lua 46, 90 and 99, the app 67, 172 and 172, since Lua draws its rows in the key's
own turn and the field waits for them. Settled, Lua 57, 198 and 9133, the app 67, 172 and 172.
Stall, Lua 58 and 95, the app 48 and 71, likely the window opening and not measured further.
Typing in the app never waited on the search, and Milos called it good. Short queries became 1.4g.

**1.4a built, the preview pane, 2026-11-08.** File search's manifest has a preview pane, so the
app's window opens as wide as the Lua one, the window, the list and the pane's region placed as
`windowRects` in `view.lua` places them. The highlight resting for `settleMs` asks the source's new
`preview`, which reads the row in process, the helper's own stat, folder scan and head read, on a
thread of its own and bounded by `peekSeconds`, and answers a `Preview`, the header's facts and a
body, ported from `sidepanel.lua`'s describers. OlmCore lays it out with a port of the parts of
`lib/ui` a pane uses, `measure.lua`, `tabs.lua`, `layout.lua` and `sidepanel-nodes.lua`, off the main
thread, along `previewpane.lua`'s native scroll path, so the header scrolls with the body as it does
under the swift chooser. The elements are drawn by the swift chooser's own `PanePanel`, in the
chooser's window. No row, or a status in its place, shows the empty state. Command and J or K
scroll it by 120 points, a scroll over it is the view's own.
- The bridge hands what the app lacked. `chooser.json` has a `pane` section, each half's type roles,
  colours, spaces, pad, nested radius and the interior's inset and radius, from
  `providers/swift/pane.lua`'s `tokens`. `filesearch.json` has the `preview` block.
- A width is NSString's size with the font alone, which is what `hs.drawing.getTextDrawingSize`
  answers, equal to the last bit for every role's font on this machine.
- `test/fixtures/chooser/pane.json`, 19 cases recorded from the live Hammerspoon read only by
  `test/fixtures-pane-record.lua`: wrapped lines and tabs, a long word, a carriage return, a head
  past its budget, two cut by the read cap, an empty file, three folders, a bundle, a gone path, two
  picture types, a binary, a read that never answered, a dotfile, a deep folder, and the empty state,
  both halves. `test/fixtures.lua` lays them out again through the Lua files over the recorded
  widths, and `olm-fixtures` through the app's port with its own measurer, frames within half a
  point. `olm-index-check` checks the in process read against the helper's peek.

Not in this part:
- Pictures are 1.4b. A type the thumbnail chain draws shows PREVIEW and "no preview", the words
  the Lua pane shows when no generator answers.
- The USED fact is frecency, 1.4d.
- What reaches the app for the scroll keys is believed and not seen. The list's leader is held in
  Hammerspoon, and with no Lua list open Hyper with Command and J is unbound there, so ChordKey's
  passthrough posts the leader's key and then Command and J, which is what the app reads.

Result: the dry suite, `olm-fixtures` with 20 pane checks, `olm-index-check` and a release build of
the app pass. `test/units.sh` was not run, since it runs through the live Hammerspoon on main.

**1.4a ticked, 2026-11-08.** Committed as `b987dafd`, then the trial by hand. Milos found the pane
good and the open slow, a blank window, then the list, then the preview, and the scroll keys dead.
- Issue: the slow open. Cause: three steps of fifty to a hundred milliseconds each, `open` handing
  the key to the app, measured at 55 ms a round trip, the window shown before its first rows, and the
  first preview waiting out the settle. Fixed: host/bridge tells a running app by the distributed
  notification `local.olm.Olm.open` and starts one not running with `open`, the stage holds the
  window until its first rows land and the first row is described, at most 150 ms, and that first
  row skips the settle, as the Lua pane's first dock does. Milos saw it open in one go.
- Issue: Hyper with J or K, and with Command and J or K, reach nothing in the app's list. Cause: the
  leader is held in Hammerspoon, which with no Lua list open swallows the list keys whose list is
  closed and runs Hyper and J's global binding, so the passthrough the build believed in never
  happens. Open: the list keys over the bridge, 1.4f, the scroll keys among them. The arrows and the
  trackpad work.
- Seen, not a fault of this step: `.app` lists Safari alone in both file searches, since the helper's
  recent list skips folders and Safari's bundle is the one the index does not mark as one.
Open: the trial by hand, after a reload writes the new run files.

**1.4b built, thumbnails, 2026-11-08.** File search's pane draws the picture the Lua pane draws for
every type `thumbs.lua` covers. `Thumbs.swift` in the plugin ports the chain, a raster or an icon
set no larger than `nativeMaxBytes` drawn from the file, everything else the chain covers, a larger
raster among it, rendered by `qlmanage -t -s imageEdge -o SCRATCH FILE`, the Lua invocation, so
both panes are handed the same pixels, checked at 72 dpi and 600 pixels on the larger edge. A
plugin hands a path, `Preview.Body.picture` in `OlmKit`, never an image. A render not made yet
answers PREVIEW and "rendering" with the preview `pending`, and the stage then asks
`previewLanded` on the same generation and repaints where the pane is scrolled, the picture or
"no preview", as `sidepanel.lua`'s `_image` repaints. A raster the system cannot read says no
preview at once. OlmCore's `PanePicture` reads the file through NSImage, the size `hs.image`
reports, and decodes it once into a bitmap at the pixels it is shown at, on the task the pane is
laid out on, so the main thread draws decoded pixels. `PaneLayout` ports `kit.image` and
`imageFit`, the slot's width or the picture's own with upscale false, the nested radius clip and
the layout's own clip put back after it.
- The renders keep one owner each, rule 1. The app writes its own under
  `~/.olm/cache/filesearch/previews-app`, named and swept as the Lua side names and sweeps its own,
  and only reads the Lua side's `cacheDir`, so a file rendered there is not rendered twice.
- A render is bounded at 20 s, two asks for one file join one render, and the last row to stop
  waiting ends it, which is not remembered as a failure. A failure is remembered for the open.
- `pane.json` gains six picture cases, wide, tall past the pane so it scrolls, smaller than the
  pane, rendering, a render landing after the first paint, and wide on the light half, recorded
  read only from the live Hammerspoon, the old cases unchanged. `olm-index-check` pins the
  cache name against one the Lua side made, the Quick Look arguments, the chain's choice, a real
  raster, a real svg rendered into its own folder, a cancelled wait, and the decode's size.

Not in this part:
- The Lua pane holds a picture for the open, the app decodes it again on each return to a row.

Result: the dry suite, `olm-fixtures` with 26 pane checks, `olm-index-check` and a release build of
the app into a scratch folder pass. `test/units.sh` was not run, since it runs through the live
Hammerspoon on main.
Open: the trial by hand.

**1.4b ticked, 2026-11-09.** The build was `0ea03917`, then the trial by hand, in three rounds.
- Milos found the pane stale. Moving from a row whose picture was rendering left the old row up
  until the render finished, and then the pane jumped. A trace was added to find the hold and could
  not be read, since the unified log redacts an NSLog argument, so the cause is not known. What
  holds it is a rule rather than a fix, Milos's, that the pane never shows a row the highlight has
  left. `Stage` clears it after 150 ms, `staleMs`, to the row's name over a spinner, whatever the
  read waits on, and a row cleared is read again on a return.
- A picture on its way is drawn with the system's spinning `NSProgressIndicator`, centred and
  floating over the scrolled content, in place of the word rendering, which the Lua pane still
  shows, so the two panes differ there by Milos's call. The stage asks `previewLanded` again while
  an answer is still pending.
- The second round found PDFs in `~/Documents` showing only the spinner. They were iCloud
  placeholders, `dataless` in the stat flags, and reading the head downloaded the file first. The
  pane now reads the stat alone for such a file, draws the heading and the facts, and says in
  iCloud, not downloaded, never downloading it, Milos's call. A Download action is 1.4i.
- The third round passed, ten numbered checks, placeholders, rendered PDFs, a small PNG, a video,
  fast arrows, typing and Escape during a render, Return on a placeholder, flicking between drawn
  rows.

Result: the dry suite with 317 fixture cases, and `test/units.sh` with 2124 passing.
Open: the Lua pane keeps downloading a placeholder on a preview, rule 7.

**1.4j built, folder permissions, 2026-11-09.** Three parts, as the step says.
- `app/build.sh` signs ad hoc with `--identifier local.olm.Olm` and the designated requirement
  `identifier "local.olm.Olm"`, so `codesign -d -r-` no longer names the build's hash. Whether the
  privacy system keeps a grant across a rebuild for such a requirement is known only live, so the
  trial checks it first. A certificate made once on the machine is the fallback.
- `Info.plist` carries `NSDesktopFolderUsageDescription`, `NSDocumentsFolderUsageDescription` and
  `NSDownloadsFolderUsageDescription`, each saying file search reads the files it finds to preview
  them.
- `Access.swift` in the plugin keeps the answers in `~/.olm/state/filesearch/folder-access.json`,
  the store `docs/DESIGN-APP.md` names, through a new `store` on `PluginContext`. Until they are
  asked, the person's list answers one pinned row, Allow File Search to Read Your Folders, whose
  preview says why. Choosing it touches each folder in turn on a background thread and answers the
  new effect `reopen`. A refusal leads the next open with Turn On Documents in System Settings,
  once, which answers `openURL` with Files and Folders. A refused folder is tried again at each
  open, which raises no prompt. The shadow's source is built without asking.
- `olm-index-check` gains 13 checks, with macOS's answer handed in, so no prompt is raised.

Open: the trial by hand, a rebuild keeping the grants first.

**1.4j ticked, 2026-11-09.** The build was `44570926`, then the trial by hand, in three rounds.
- The first round allowed all three folders, so the refusal was not tried, and Milos asked for an
  icon on the row. It wore `hand.raised` ✋, Olm's symbol for a permission held back, and he read it
  as stop. His rule, a row a person chooses wears what choosing it does, never the state it is
  about, so both rows wear `checkmark.circle` ✅, Apply's, the lock being a VPN's alone. The rule is
  in the hammerspoon `AGENTS.md`, the olm-plugin skill and `decisions/olm-icons.md`.
- The second round refused Documents. The files there were still listed, since Hammerspoon builds
  the index, and the pane said nothing about the refusal. Turn On in System Settings was said once
  and gone, and System Settings gave no clear switch. Replaced by Ask Again for Documents, which
  stays while a folder is refused and resets the app's own answer for that folder alone with
  `tccutil reset SERVICE local.olm.Olm`, then touches it, so macOS asks once more. A failed reset
  opens Files and Folders. A file in a refused folder says so in the pane. `tccutil` is declared in
  file search's manifest beside `qlmanage` and mapped as shipping with macOS.
- The third round passed. The app was rebuilt and installed over the answers, and Desktop and
  Downloads previewed with no prompt, so the requirement naming the bundle id keeps a grant across
  a rebuild and no certificate is needed. Ask Again raised the prompt, Allow removed the row, and a
  file in Documents previewed.

Result: `olm-index-check` with 19 checks of the permissions, the dry suite and `test/units.sh`.
Open: nothing.

**1.3e read, the shadow's log, 2026-11-09.** 49 lines from 2026-11-08 to 2026-11-09, 25 skipped by
design, the recent list for 1.4d and a folder for 1.4e, 16 the same and 8 not.
- One, ids 900 and 901 with `/nonexistent/report.pdf`, is taken to be a made up answer written
  while the shadow was built, from its time and its path. Not traced to the command.
- Seven were one fault, on the Lua side. The helper kept a name only when it held every word
  whole, and the list ranks with the shared search, which keeps a word one edit away or spelled in
  pieces. Lua typed on over rows a shorter word brought back, so `repo` brought `repost.svg` and
  `report` kept it, while the app asked afresh for the settled query. The app's counts were a fresh
  helper search's exactly. Which files a query found hung on how it was typed.
- Fixed in the shared helper, so both sides. `fileindex.swift` is compiled with
  `app/Sources/OlmSearch/Match.swift`, handed to the plugin as the `matchsource` lib, and keeps a
  name exactly when the list would, behind a prefilter. A fresh `report` gives 156 as the narrow
  did. A search is 20 to 60 ms in its own process, one and two letters about 100 ms. Making the
  narrow as strict instead, and a third copy of the matcher, were rejected,
  `decisions/olm-filesearch.md`.
Result: the dry suite, `olm-index-check` with three new checks, a typo, a fresh search agreeing with
the narrow and an accent folded either way, and `test/units.sh`.
Open: Milos's trial on the Lua file search, then the shadow from line 50 on, and 1.3e is ticked
when that stays clean. A scoped search still hands its first word to fd as typed, for 1.4e.

**1.3e trial, round one, and 1.4g built, 2026-11-09.** Milos typed the queries on the Lua file
search. `report`, `hello`, `index.js` and `repo` were fine. `heelo` typed quickly led with
`HelloWorld.jsp` and typed slowly showed only the Heebo fonts. Cause: the engine asked nothing more
when a text only grew and ranked the held rows again, which is sound only for a substring. `hee`
gets no typo at three letters, so it never brought `HelloWorld.jsp`. Fixed: no narrow on either
side, the held rows shown with the searching row until the round trip after the debounce lands.
He asked too for the search to start on the first letter, which is 1.4g, so `minChars` is 1 in
`config/filesearch.lua`, `engine.lua` and `Source.swift`, both sides together as 1.4g said.
Result: the dry suite, `test/units.sh` with the typing on cases rewritten, `olm-index-check` with a
grown text asking again.
Open: round two of the trial, then the shadow from its next line, and 1.3e and 1.4g are ticked.

**1.3e and 1.4g ticked, 2026-11-09.** Round two of the trial passed, `heelo` quick and slow, one
letter, two, back to the recent list and a long query typed quickly. Before it, the Lua engine was
driven headless with no list open, six queries typed at once and one letter at a time a second
apart, `heelo`, `report`, `scre`, `index.js`, `hello` and `r`, and each ended on the same paths
both ways, 13, 156, 630, 9, 11 and 2000. The shadow after the second fix, from 12:21 UTC, is the
same on every search, and its one difference since line 50, `repo` at 12:15 UTC, was six minutes
before it, the two sides first apart at row 176, the narrow's fault. Its recent list is still
skipped, which 1.4d answers.
Result: the shadow clean, the dry suite, `test/units.sh` and `olm-index-check`.
Open: the shadow keeps running until 1.5. A scoped search hands its first word to fd as typed,
for 1.4e.

## Where the facts come from

The facts below were checked on 2026-11-05 by three read only sweeps of the spoon. Recheck any
citation before acting on it, since the spoon moves.

## The rules every step follows

These are what keep the blast radius small, and a step that cannot meet all of them is split
until it can.

1. **One owner per responsibility at every moment.** The chooser, each key, each plugin, the
   clipboard monitor, each store and each window action belong to exactly one process. A step
   moves one owner and never two.
2. **Off by default, and one switch to go back.** Every new path is off until it is turned on on
   one machine, through the `olmapp` machine piece or one setting. Going back is turning it off
   again, and the step is not finished until going back has been tried and shown to restore the
   old path.
3. **Shadow before flip.** Wherever the app is about to take over a decision the Lua side makes
   today, a ranking, a keymap, a list of rows, it first computes the same answer beside the Lua
   one and logs every difference, and nothing is shown. The flip comes only when the log has
   stayed empty over real use.
4. **Fixtures are the gate.** Behaviour that moves is pinned first as language neutral fixtures,
   input and expected output in JSON, that the Lua side and the Swift side both run. The Swift side
runs them from programs rather than `swift test`, decided at 1.1. A part moves
   only when its fixtures pass in Swift.
5. **Plugins do not learn they are bridged.** The Lua side of the bridge is one core host the
   composition root names, wrapping the registry and the stage presentations, so no plugin file
   changes for a step that serves it over the bridge.
6. **Nothing is removed by a step.** Switching the Lua path off is a switch. Deleting a Lua
   plugin, a lib or the Hammerspoon cask is a separate act with Milos's go ahead, after its
   replacement has run on every machine that uses it, as rule 4 of the root `AGENTS.md` says.
7. **No new Lua work that the bridge will retire.** No more work on the canvas chooser or the
   legacy provider. Work that helps Lua plugins while they are still served, such as moving a
   blocking call off the main thread, is welcome.
8. **Typing never waits.** In the app the main thread holds the input field and the list and
   nothing else. Ranking runs on a search actor cancelled by every keystroke, and indexing,
   walking, thumbnails and every answer from Hammerspoon arrive on background work and stream
   into the list. A step that puts other work on the main thread is not finished.
9. **Nothing is lost at a flip.** Stated by Milos on 2026-11-08. A person using the machine
   never loses a feature as the plan moves. The app may be tried with fewer features while the
   piece is on for a trial, but the app becomes the daily path only when every feature of what it
   replaces works in it, checked one by one against a written list of those features. A feature
   the app does not have yet keeps the Lua path, so a flip that would drop one waits. The core's
   look is a feature too, stated by Milos the same day. The app's chooser draws with the swift
   chooser's own style, sizes and placement, handed over by the bridge rather than written again
   in Swift, so the only difference a trial shows is a part not built yet, each named in its step.

## How we test

Five layers, each catching what the one before cannot.

**Fixtures.** One shared directory of JSON cases per behaviour, ranking, keymap resolution,
leader allocation, list keys, the bottom bar model and the file search grammar to begin with. A
Lua runner in the dry gate reads them, so they can never drift from the Lua behaviour they
describe, and `swift test` in the app reads the same files. A fixture is added in the commit that
changes the behaviour it pins.

**The existing gates, unchanged.** Every step that touches the spoon still passes
`test/drygate.sh`, `test/goldens.sh`, `test/units.sh` through the running Hammerspoon,
`test/swiftpane.sh` where the Swift library moves, the BrowserTabs suite where that plugin moves,
and the console gate after every load. The goldens are the strongest proof that a Lua side step
changed nothing, since they record every chord, the launcher catalog and each cheat sheet.

**Bridge transcripts.** A recorded set of requests and the replies the Lua side gave, written as
a golden. The Lua side replays it over fakes in the dry gate and the app replays it against a fake
bridge in `swift test`, so either side changing what it says fails offline before anything runs
live.

**Shadow logs.** Rule 3 above. Each shadow writes its differences to a file under the olm data
root, and a step reads that file before its flip. An unexplained difference blocks the flip.

**Live trials, by hand.** The Hammerspoon side through `bin/hs-devlock`, the app as a separate
process. Nothing drives the screen or the keyboard until Milos says start. Each trial includes the
back out, switching the new path off and checking that the old one answers.

Every trial handed to Milos is written out explicitly, stated by him on 2026-11-09. He is never
asked to work out what to try. The hand over is a numbered list, each line one thing to do and what
he should see when it is right, followed by a few scenarios that might hold a hiccup, each saying
what to do and what a fault would look like, and it ends with what to report back. Whatever needs
him outside a trial, a command, a setting, a password, is written the same way.

Performance is measured rather than felt. From stage 1 on, the app records the time from a key
down to the field showing it and to the first rows, and the longest main thread stall while a list
is open. A step that moves search or rows must not make any of the three worse.

## Stage 0, contracts, inside this repository

Nothing a person sees changes in this stage. The steps run in the order listed.

**0.5 Gather LuaSkin into one Swift file.** LuaSkin and the Lua C API are used in
`native/Entry.swift`, `native/Lua.swift`, `PaneReader` in `native/Pane.swift` and the five
initialisers in `native/Model.swift` that take a `LuaReader`. Those last two move into `Lua.swift`,
so the Lua facing code is two files commented as the seam, with no behaviour change. Test, `test/swiftpane.sh`, `test/swiftview.lua`, a live load with the swift
chooser serving and a clean console. Back out, revert the commit.

**0.1 The decision record.** Done 2026-11-05, `decisions/olm-standalone.md`.

**0.2 Fixtures for ranking.** The cases in `test/ranking.lua` are written as JSON in a fixtures
directory, and a Lua runner in the dry gate reads them. The old test stays until the runner covers
everything it did. Blast radius, test code only. Test, the runner and the old test agree on every
case, and a deliberately broken case fails the gate. Done as `test/fixtures.lua` and
`test/fixtures/ranking/`, rule cases for the rank engine, the launcher's memory and its ordering, and a
recorded corpus of 74 queries over one launcher shaped list, so the Swift port is checked beyond the
rules. Only the shared fuzzy matcher is pinned, since a hand written test matcher has no JSON form.

**0.4 The bridge protocol, on paper.** `docs/PROTOCOL-BRIDGE.md`. Line delimited JSON RPC. The
messages are the catalog, rows for a query tagged with a generation so a stale answer is
dropped, choose a row, run an action, the actions pane verbs, preview panes as the canvas element
lists `native/Pane.swift` already draws, icons as keys, pictures as paths and never `hs.image`
userdata, and surface state for the list keys. The row fields are the ones `rank.lua` already
states. It also names the `olm://` URLs the pilot uses. No code. It gets an adversarial review,
since everything after it stands on it.

**0.6 A data source protocol in front of the library.** The Swift sources compile a second way,
as a Swift package with no LuaSkin and no Lua, with the Lua entry as one adapter of that protocol.
The Hammerspoon build is unchanged. Test, both builds succeed, the Hammerspoon one passes 0.5's
tests, and the package build has a smoke test that shows a list from a fake data source with no
window.

**0.3 Fixtures for the rest, one area per step.** The file search grammar from
`plugins/filesearch/query.lua`, the bottom bar model, keymap resolution, `KeyRemap.allocate` and
list keys, each lifted from its existing plain Lua test and golden the same way as 0.2. The file
search grammar comes first, since stage 1 needs it. The chord engine's tap and hold timing waits
for stage 5, since it needs fixtures of a different shape, event traces with timestamps.

## Stage 1, the pilot, file search in the app

File search goes first because it is where Olm freezes today and because it needs almost nothing
from Hammerspoon. `plugins/filesearch/AGENTS.md` measured paints holding Hammerspoon's main thread
for about 380 milliseconds, and since Hammerspoon owns every leader key, a stall there is a stall
of the whole keyboard. Its index helper is already Swift, `sources/fileindex.swift`, and opening,
revealing and Quick Look are native APIs, so the pilot needs no socket bridge. Hammerspoon only
says show file search, through an `olm://` URL.

**1.1 The app shell.** Olm.app builds from the package 0.6 made, runs with no Dock icon, keeps one
instance, and answers `olm://` URLs. It is the machine piece `olmapp`, off by default, built on the
machine from source the way the swift chooser library is, with its toolchain declared like every
other tool. Test, it starts and answers a test URL, and quitting it changes nothing in
Hammerspoon. Where its code lives is open question 1, decided before this step. Done as `app/` in
the spoon, a package depending on the swift chooser's, wrapped into a bundle by `app/build.sh`,
built into `~/.olm/app` by `src/setup-olmapp.sh` where the piece is on, and checked by
`test/olmapp.sh`.

**1.2 The trigger.** A core action in `host/bridge` opens the app's file search through the URL,
and only where the `olmapp` piece is on. It takes file search's open key on that machine, how it
does so being decided in this step without a per machine copy of `config/keymap.lua`, since a
difference between machines is a piece and never a branch. The Lua file search stays exactly as
it is, reached by its launcher scope until the launcher moves in stage 3, which is a known second
route for that time. Test, the keys golden on a machine without the piece is unchanged, and on one
with it the chord opens the app. Back out, the piece.

**1.3 Search, open and reveal.** The app's file search on the threads rule 8 names, the index
built from the same Swift sources the helper uses, the walk on background work, ranking through
the Swift port of `rank.lua` and the file search grammar. Gate, the ranking and grammar fixtures
pass in Swift before the flip. Shadow, for a few days each query is answered by both, the Lua one
through a command line ask, and the differences are logged. Test, the three timings measured
against the Lua file search, and a live trial of a large result set while typing. There is no flip
in 1.3. The app still lacks the preview pane and the rest of 1.4, and rule 9 holds the flip until
1.5.

**1.3g The app's structure.** Written at Milos's request on 2026-11-08, before 1.4 adds most of
file search to the app. `docs/DESIGN-APP.md` is the design, the layers, one `ListSource` protocol
every list answers through, native or bridged, and a plugin as a module of its own. This step
moves the pilot onto it as that file's last section lists, with nothing a person can see changed.
Test, the fixtures, the index check and a trial by hand. Every step after it builds on that
structure and never grows `main.swift`.

**1.4 The rest of file search, one per step.** The preview pane, thumbnails, Quick Look and
frecency, each its own step and trial. Frecency is a store, so it has one owner. The app reads the
Lua history once at its flip and owns it from then on, and the Lua side keeps its copy so the back
out loses nothing that came before. Two more steps came out of rule 9 on 2026-11-08. 1.4e is
the folder search, the scope with a folder walk, the directory aliases from `config/filesearch.lua`,
Into Folder and Up a Level. 1.4f is the bottom bar, the actions pane and the info pane, Copy Path,
Reveal in Finder on its own key, Command and a digit, and the person's `lists` keys for file
search read over the bridge.

1.4f, where to start, written 2026-11-09 after 1.3e and 1.4g. Nothing is built yet. Its first piece
is a short design note, for Milos to agree before any code, on how a list key reaches the app's
list, since today none does. The leader is held in Hammerspoon, and with no Lua list open the leader
swallows a key whose list is closed and runs the global binding instead, Hyper and J for one, so
Hyper with J or K and with Command and J or K never reach the app, which the 1.4a trial found. The
arrows and the trackpad do, being the app's own. The shape to start from is 3.4's, brought forward
for file search alone. While the app's list is open the app is a surface to `lib/nav.lua`, its
`isShowing` answered from state the app pushes over the bridge and its verbs sent as bridge
messages, so a list key moves the app's list as it moves a Lua one and the keys golden is
unchanged. The facts it rests on. `host/bridge/init.lua` hands a served tool `olm://filesearch` and
talks to a running app by distributed notifications, `local.olm.Olm.open` and
`local.olm.Olm.shadow`, so a third note for a verb fits that, and the app needs a way to tell
Hammerspoon its list is up and down. File search's verbs are its manifest's `surface`, the primary
Open, the secondary Reveal in Finder on Command and Return, and the extras, scroll the preview pane
on Command and J and K, Quick Look on q, Into Folder on l, Up a Level on h, Reveal in Finder on f
and Copy Path on y, each with its `applies` or `needs`, and the person's `lists` section of
`config/keymap.lua` moves them. The app already compiles the swift chooser's own library,
`lib/chooser/providers/swift`, whose `native/Bar.swift` and `native/FloatingPane.swift` draw the
bar and both floating panes, so the look comes from there under rule 9 and the words from
`lib/hints.lua`'s `bottomBarModel`, handed across the way `chooser.json` hands the look. Then the
build, in pieces each with its trial, the keys first since the panes need them, then the bar and
the info pane, then the actions pane with Copy Path and Reveal in Finder, then Command and a digit.
Quick Look on q waits for 1.4c, Into Folder and Up a Level for 1.4e, and Download for 1.4i.

1.4g came out of the 1.3f trial on 2026-11-08. File search holds an unscoped query under three
characters on the recent list with a keep typing row, `minChars` in `plugins/filesearch/engine.lua`
and the app's copy in its `Source.swift`, a limit from when every search ran Spotlight and one
letter matched nearly every file. The app's index answers in memory, so it no longer needs it. It
waits for 1.3e, since a limit changed on one side only would log every short query as a
difference. Both sides then lower it together where the Lua side's Spotlight keeps up, measured
with the 1.3f timings, and otherwise the app alone once it serves file search for good.

1.4h came out of the 1.4a trial on 2026-11-08, asked for by Milos. A bare type token is the recent
list of that type, and the helper's `recent` in `plugins/filesearch/sources/fileindex.swift` skips
every folder, so `.app` lists only Safari, whose bundle the index does not mark as a folder, and
leaves out the sixty other apps in `/Applications`. A folder whose name ends in the type asked for is
a file to the person, a bundle, so `recent` keeps it when a type is given. The helper is the one
both file searches ask, so both change in the same step and the shadow of 1.3e sees no difference.
A bundle's row and its preview pane stay a folder's, KIND Application for an app.

1.4i came out of the 1.4b trial on 2026-11-09, asked for by Milos. A file in a synced Documents
folder can be a placeholder iCloud holds, `dataless` in its stat flags, and reading its head or
rendering its thumbnail downloads it first, so the pane waited on the download. Since 1.4b the
app's pane never reads such a file, it draws the heading and the facts from the stat and says the
file is in iCloud and not downloaded. 1.4i adds Download as a verb of file search's actions pane,
with a shortcut of its own in the manifest, the pane naming that shortcut beside not downloaded, and
the preview drawn once the download lands. It needs the actions pane and the list keys of 1.4f.
The Lua file search keeps downloading on a preview, rule 7, and the app alone carries this.

1.4j came out of the 1.4b trial on 2026-11-09, asked for by Milos. macOS asks once per protected
folder, Desktop, Documents, Downloads, iCloud Drive and a removable or network volume, the first
time the app touches a file there, so the prompts arrived one by one in the middle of a search as
a preview or the helper reached a folder. Worse, the app is signed ad hoc and its designated
requirement is its cdhash, so every build is a new app to the privacy system and a grant is
forgotten on each `setup-olmapp.sh`. Three parts, in order.
- One identity across builds. The app is signed with a designated requirement that names its
  bundle id rather than its hash, or with a signing certificate made once on the machine, whichever
  the trial shows macOS keeps a grant across a rebuild for. Test, grant Documents, rebuild, and
  open a file there with no prompt.
- The words macOS shows. `Info.plist` gains the usage descriptions for the folders file search
  reads, so each prompt says why.
- Asked up front. On the first open of file search, before any search, the list shows one pinned
  row asking to let file search read the protected folders among its roots, and choosing it
  touches each folder in turn, one prompt at a time, then shows the list. The answers are kept
  under the olm data root, so it is asked once. A folder refused is said once in the list, with a
  row that opens Files and Folders in System Settings, since macOS never asks a second time.

**1.5 Parity, then the flip.** A written list of every feature the Lua file search has, read from
its manifest, its README and `config/filesearch.lua`, each one tried in the app by hand and ticked.
Only when every line is ticked does the piece open the app as the daily path, and going back is
still the piece. The launcher's slash scope stays on the Lua file search until stage 3, as 1.2
says.

## Stage 2, the bridge, read only

**2.1 Probe the transport.** A scratch script checks whether `hs.socket` listens on a Unix
socket, and what one round trip costs. Nothing in the config changes. The answer decides between a
Unix socket and local HTTP, and goes into the decision record.

**2.2 `host/bridge` serves, read only and off by default.** The Lua side serves the catalog and
the launcher's rows for a query, and nothing else, so nothing can be run through it. Every reply
is computed on Hammerspoon's thread but sent without the app waiting on it, and a query the app
has moved past is dropped by its generation. Test, a unit case over fakes, the transcript golden,
and a live check with a command line client asking for the catalog. Back out, the setting.

**2.3 Shadow ranking for the launcher.** The app ranks every real launcher query beside the Lua
answer the bridge sends, and logs differences. Gate, the shadow log stays empty over a few days of
real use.

## Stage 3, the app shows every list, ending at the resting point

**3.1 Choosing a row over the bridge.** The bridge gains `choose`, which runs the row through the
Lua launcher's existing run path, so app switching, window actions and everything else still runs
in Hammerspoon. Only the test client calls it at first. Test, the transcript golden grows a choose
case, and a live choose from the client does what Return does today.

**3.2 The app's launcher on a trial key.** The app's launcher, opened by a trial chord set in this
machine's keymap. Hyper and Space still opens the Lua launcher, so nothing a person relies on
moves. Test, a live trial by hand, and the three timings recorded.

**3.3 Hosted lists, one tool per step.** A launcher row that leads to a tool's list replaces the
rows in place through the bridge, as the stage does today. Caffeinate first, since its list is
small and pure, then the others one at a time, file search answered by the app's own. Until a
tool is served, its row is held back in the app rather than closing the app and opening the Lua
chooser, since one list must become another in place.

**3.4 List keys reach the app.** Hammerspoon still owns Hyper. While the app's list is open the
app is a surface to `lib/nav.lua`, an adapter whose `isShowing` comes from state the app pushes
and whose verbs are bridge messages, so Hyper and J moves the app's list exactly as it moves a Lua
one. Test, the keys golden is unchanged, and a live trial of every shared verb.

**3.5 The flip.** Where the `olmapp` piece is on, Hyper and Space opens the app, and when the app
is not connected Hammerspoon opens the Lua launcher as before. Back out, quitting the app or
switching the piece off. Test, both paths live, including quitting the app mid session.

**3.6 Every plugin's own list.** A tool's own chord opens its list in the app over the bridge, one
tool per step, the same way the launcher's hosted lists do.

## The resting point, Olm decoupled

Stage 3 ends here, and the route can stop here. It is reached when all of these hold on a machine
whose `olmapp` piece is on.

1. Every list a person opens, the launcher, its scopes and every tool's own list, is drawn,
   searched and navigated by Olm.app.
2. Typing and moving through a list never wait on Hammerspoon, and the three timings are recorded
   for the launcher and for file search.
3. Hammerspoon does what remains, the leader keys and the cheat sheets, app switching, window
   management and every plugin not yet native, all reached through the bridge.
4. kanata and the Karabiner driver run as they do today.
5. On a machine whose `olmapp` piece is off, the Lua Olm runs in full, and quitting the app on a
   machine where it is on hands every list back to the Lua Olm.

What it does not yet give is worth saying, so the resting point is not mistaken for the end. A
bridged plugin still computes its rows on Hammerspoon's thread, so a slow plugin can still hold a
leader key there for that moment, though it can no longer hold up typing in the list. Moving that
plugin native in stage 4 is what ends it for that plugin.

## After the resting point, optional and at any pace

### Stage 4, plugins move native, one per step

Each plugin moves the same way. Its fixtures first, then a native implementation in the app
answering in shadow beside the bridged Lua one, then the flip, which switches the Lua plugin off
for that machine in `config/plugins.lua` and lets the app own it. Back out is the reverse switch.

The suggested order is by how often it is opened and how heavy it is in Lua. The app catalog and
its recency, emoji, menu search, then the clipboard.

The clipboard is the one with a second owner to worry about, since two monitors would capture
every copy twice. Its flip moves the monitor and the store together, and its store is read by the
app from the same files before the flip so no history is lost and the Lua side can take it back.

A TypeScript extension host, if chosen below, joins here as a second host on the same protocol,
with one small extension written first to prove the API.

### Stage 5, keys

**5.1 The app hears the leaders in shadow.** kanata and the driver keep remapping the physical
keys and Hammerspoon keeps every binding. The app reads the compiled keymap over the bridge,
listens for Hyper and META as the real modifiers kanata sends, and logs what it would have run
beside what the binder ran. Gate, the keys fixtures pass in Swift and the log stays empty.

**5.2 Cheat sheets in the app.** Drawn natively from the same keymap rows, while Hammerspoon still
binds the keys. Test, the sheets golden against what the app draws, then a live trial.

**5.3 Key ownership moves one leader at a time.** META first, since window management is one
plugin, then Hyper. The keymap names the owner of every row so the two processes never both bind
a chord. Back out, the owner setting.

**5.4 The key daemon.** `olmkeyd`, a root daemon that seizes the keyboard and types through the
same Karabiner VirtualHIDDevice driver, replaces kanata on a machine whose `kanata` piece is on,
with a tap backend for a machine without the driver that behaves as Hammerspoon does now, blind in
a password field. It takes over the pairing in `dotfiles/kanata/DRIVER`. kanata stays installed
and can be started again until the daemon has run long enough to be trusted.

### Stage 6, the system plugins and the rest of being self sufficient

Windows, workspaces, display profiles, the app toggler, audio, wifi and the rest, one per step in
the stage 4 way, each on native APIs rather than the command line tools they call today wherever a
native API exists. Alongside them, a settings window and the config model behind it, so a person
sets leaders, remaps, app keys and their styles, plugins and the look there rather than in files,
and a first run that walks through the permissions macOS asks for, Accessibility, Input
Monitoring, and the driver and the daemon where they are used. When the bridge serves no plugin on
a machine, that machine's Hammerspoon piece can be switched off, and removing it is the separate
act rule 6 describes. Shipping to another person adds signing with a Developer ID and
notarization.

## Open questions

1. Where Olm.app lives. A repository of its own was recommended, since it is a product rather than
   dotfiles, with this repository installing it as a piece. Decided 2026-11-07 by Milos, it lives
   in this repository until Olm is decoupled, the resting point, and the question of a repository
   of its own comes back after that. The folder is chosen at 1.1.
2. Unix socket or local HTTP for the bridge. Decided by 2.1.
3. What extensions are written in. JavaScriptCore with shims, as Tinycast runs Raycast's, needs no
   bundled runtime. Decided before the extension host in stage 4.
4. Whether leaders work in a password field, through a bundled virtual HID driver, or the tap
   backend is accepted with its blind spot. Decided before 5.4.
5. The calculator. A native engine with a rates source this project chooses, rather than bundling
   the GPL library behind `qalc`. Decided when convert moves in stage 4.
6. Whether Lua survives as an optional scripting runtime in an extension process once Hammerspoon
   is gone. Decided in stage 6.
