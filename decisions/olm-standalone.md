# Olm as an app of its own

Status. Under way. Olm moves to a native macOS app in small steps beside Hammerspoon, by
`dotfiles/hammerspoon/.hammerspoon/Spoons/Olm.spoon/docs/PLAN-STANDALONE.md`, whose Progress
section is the one record of which steps are done. Stages 0 to 2 are done, file search is the app's
since 1.5's flip on 2026-11-12, and stage 3 is under way, 3.3d built and checked live and waiting on
Milos's own trial, as that section stood on 2026-11-16.

## Now

The goal is a native app that needs no Hammerspoon, whose launcher runs no Lua and never lets a
search hold up typing, with leader keys built in so kanata and Karabiner are no longer needed, and
with built in plugins written natively beside extensions on a plugin API comparable to Raycast's,
though not compatible with Raycast's extensions. Olm.app is built first and runs beside
Hammerspoon, kanata and the Karabiner driver. A bridge between the two processes is the one seam,
and each step moves one responsibility across it, a shadow comparison first and a flip that one
switch takes back, until nothing is left on the Hammerspoon side. Behaviour that moves is pinned
first as language neutral fixtures both sides run. No flip drops a feature. The app becomes the
daily path for a list only when every feature of the Lua one works in it, checked against a written
list, and until then that list stays on Lua. File search crossed that line on 2026-11-12 and is served by the
app where the olmapp piece is on, with turning the piece off as the way back. The launcher on Hyper
and Space is still Hammerspoon's, and the app's own launcher, which reaches Hammerspoon over the
bridge socket, runs on the trial key Hyper and 0 until step 3.5 gives it Hyper and Space.

## Rejected

- **Embedding Lua in the app to run today's core and plugins.** 2026-11-05 14:37. It was the first
  shape proposed in this conversation, a Swift app hosting Lua with the `hs` calls replaced by ports
  the app implements. Milos does not want the launcher on Lua, and a launcher whose rows and ranking
  are Lua calls on one thread is the stall this move exists to end. Lua may still run in places
  during the move, behind the bridge, and possibly later as a scripting runtime in an extension
  process.
- **Cutting over in one move.** 2026-11-05 14:37. It is the rewrite `decisions/olm-swift-chooser.md`
  turned down on 2026-10-27, every Hammerspoon module rebuilt before one plugin works, and it breaks
  everything at once. Milos asked for steps that break as little as possible.
- **Flipping file search to the app at the end of 1.3, before the rest of it.** 2026-11-08 00:23.
  The plan as first written flipped at 1.3f, with the preview pane, thumbnails, Quick Look,
  frecency and the folder search still to come in 1.4. Milos turned it down, every feature must be
  kept as the plan moves.
- **Writing the app's chooser look again in Swift.** 2026-11-08 00:58. The 1.3d window was drawn on
  sizes and fonts typed into the app by guess, and Milos saw the difference at once. A second copy
  of the look, however carefully matched, drifts the first time a setting, the theme or the
  typography changes. The app is handed the Lua view's own tables instead, until the app owns the
  look outright in a later stage.
- **Loading compiled Swift plugins while the app runs.** 2026-11-08 01:40. Milos asked whether a
  plugin could be Swift code dropped in. Loading it as a bundle is possible and fragile, since every
  plugin must match the app's Swift and build exactly, macOS signing refuses a library it did not
  see signed, and a fault in one takes the launcher down with it. A native plugin is built into the
  app, one rerun of `src/setup-olmapp.sh`, and a plugin someone else hands over is an extension in
  a process of its own, `docs/DESIGN-APP.md` in the spoon.
- **An app picker provider beside default, swift and legacy.** 2026-11-05 14:37. It would keep the
  Lua engine and put the view in another process, which is the helper process
  `decisions/olm-swift-chooser.md` turned down on 2026-10-27, since the picker contract asks
  synchronous questions a pipe answers only with a shadow copy of the panel's state. In this plan the
  app owns the engine and the view together and only plugin rows cross, asynchronously, so that
  rejection does not reach it.
- **Converting the manifests and the config to TOML first.** 2026-11-05 14:37. The bridge serves
  descriptors and the compiled keymap as JSON, so the app never needs to read a Lua manifest, and
  converting them would move every reader of a manifest, `dependencies-collect` among them, for no
  gain the app needs yet. It can come later for files the app reads itself.
- **One generation for the typed query and the highlight together.** 2026-11-07, the bridge
  protocol's first draft. Every arrow key made an in flight rows answer stale, so a list arrowed
  through while a slow supplier answered was never refreshed. The second draft then raised the
  highlight's on every keystroke too, which dropped every preview drawn while typing over one row.
  `docs/PROTOCOL-BRIDGE.md` keeps two, `q` per change of the input field and `h` per change of the
  highlighted row.
- **The Lua side acting on the highlight it last heard of.** 2026-11-07, the first draft. A Hyper
  chord heard by Hammerspoon and the app's highlight report travel on two channels nothing orders,
  so a delete could land on the row above. Every request that acts on a row names it, and a list key
  Hammerspoon hears is forwarded to the app, which owns the highlight.
- **A describe request answered with a preview per highlight.** 2026-11-07, the first draft. No
  plugin has such a member, each draws its preview pane itself from `onHighlight` and
  `onPositioned`, so the bridge is a backend of the shared preview pane instead.
- **One outcome word for what choosing did.** 2026-11-07, the first draft. The launcher's
  `intercept` answers true for a seeded query, a pushed tool and an action alike, and a plugin may
  pop and redraw in one handler, so the answer is the ordered list of stage effects the handler
  caused, recorded by a facade of the `Stage` the composition root hands out.
- **The app reading Hammerspoon's defaults domain for the frecency history.** 2026-11-10 17:05.
  It would put a second copy of the `hs.settings` key and of Hammerspoon's bundle id in the app.
  The root writes the history into a share for a served list instead, from the plugin's own word.
- **The app taking the Lua frecency history once ever.** 2026-11-10 17:05. Every trial is a flip
  and a back out, so the first trial would freeze the history and the real flip in 1.5 would miss
  every use made in the Lua list since.

## Log

- 2026-11-05 14:37. The route was settled with Milos in one conversation. Three read only sweeps
  of the spoon found about 1150 `hs` references in 180 files, 595 of them in plugins, the pure core
  libs the registry, keymap, binder, wiring, ranking, matching and geometry, the picker, preview
  pane and panel already behind backends the Swift library draws, and that library linking LuaSkin
  in three files. Milos asked first for no Lua in the launcher and leader keys built in, then for
  the move to be staged with Olm.app beside Hammerspoon, kanata and the Karabiner driver, then for
  a written plan with testing and the smallest blast radius per step, which is
  `docs/PLAN-STANDALONE.md` in the spoon.
- 2026-11-05 14:37. Two claims of those sweeps were checked and were wrong. FileSearch calls no
  `hs.execute` and no plugin calls `hs.alert`, every match was a comment. What the sweeps found
  that does hold is blocking `hs.execute` in dockautohide, tmuxsessions, the mullvad and ivpn
  providers, displayprofiles and the browsertabs permission check, and blocking
  `hs.osascript.applescript` in three tmuxsessions providers and the clipboard's Finder target.
- 2026-11-05 15:40, estimated from the conversation. The plan was reshaped at Milos's request
  around a resting point, the end of a stage in which Olm.app draws, searches and navigates every
  list on threads of its own and reaches Hammerspoon as a dependency for keys, app switching,
  window management and the plugins not yet native, with kanata and the Karabiner driver as they
  are. Everything after it is optional. File search was put first as a pilot, because its paints
  measured about 380 milliseconds on Hammerspoon's main thread, which stalls every leader key, and
  because its index is already Swift, so the pilot needs only an `olm://` URL and no socket
  bridge. Stage 0 keeps every step, reordered so the LuaSkin step runs first and the file search
  grammar fixtures come before the pilot.
- 2026-11-06 16:57. Step 0.5's scope was corrected before it was finished. The plan named seven lines of
  `native/Pane.swift`, and the whole of `PaneReader` reads Lua, as do five initialisers in
  `native/Model.swift` it did not name, which take a `LuaReader`. All of them moved into
  `native/Lua.swift`, so a file outside the seam touches no LuaSkin and no Lua. `LuaValue` is still
  named by `Panel.swift`'s `Ask`, a plain enum with no Lua in it, left for 0.6's data source protocol.
- 2026-11-07 10:51. Step 0.2 was finished. The fixtures are JSON under the spoon's
  `test/fixtures/<area>/`, read in Lua by `test/fixtures.lua` with a JSON reader of its own,
  `test/json.lua`, since the dry gate has no `hs.json`, and the dry gate runs them. Two sorts are
  kept apart. A rule fixture states the answer a rule gives and is never recorded. A corpus records
  what the Lua answered, 74 queries over one launcher shaped list using every field of the row
  vocabulary, because the rule cases alone are about 60 and the Swift port of the 878 line matcher
  needs to be checked far wider than that. It is refreshed with `--record` after a change made on
  purpose. Only the shared fuzzy matcher is pinned, since the rule cases written with a hand made
  matcher in `test/cases/rankvocabulary.lua` have no language neutral form, and the case with a
  150 character title in `test/ranking.lua` is covered by the bonus rule rather than copied.
  `test/ranking.lua` stays beside the fixtures. A broken rule case and a broken memory case each
  failed the gate, and bad JSON is refused with its offset.
- 2026-11-07 10:51. `test/swiftpane.sh` failed once inside `suite.sh dry` on the 0.2 worktree and
  passed on the next suite run and on three runs alone, with no Swift changed. The failing output
  was not kept, so the cause is not known. Recheck it if it fails again, keeping the output.
- 2026-11-07 11:13. Step 0.3a was finished, `test/fixtures/filesearch/`, the grammar of
  `plugins/filesearch/query.lua` as 29 parse cases and 16 cases of when a query narrows the held
  rows, each with a types table of its own so a change to `config/filesearch.lua` never moves them.
  The grammar had no test of its own, so the cases are its header's rules rather than a lifted test.
  A broken case failed the gate.
- 2026-11-07 11:10. Open question 1 was decided by Milos. Olm.app's code lives in this repository
  until Olm is decoupled, the resting point at the end of stage 3, in his words keep everything
  here until it is completely decoupled. A repository of its own, which the plan recommended, is
  not rejected, only deferred to after the resting point. The folder is chosen at step 1.1.
- 2026-11-07 11:24. Step 0.4 was finished, `docs/PROTOCOL-BRIDGE.md` in the spoon, after two rounds of
  adversarial review by a reviewer reading the code, who found fourteen problems in the first draft,
  two critical, and nine more in the second, three of them high. Every one was answered in the text,
  and the four designs turned down are under Rejected. The ones that held were checked against the
  code before being accepted, `root/compose.lua`'s `run` ignoring the row, `stageTextBudget` being
  pixels, the launcher's exclusive query sources and its own calls on `_stage`. What the protocol
  leaves to the step that serves each tool is said there, among it a plugin that defers work of its
  own and reads the stage words later, Clipboard History's paste behind a nonactivating panel, and
  how a supplier that builds fresh item tables on every call costs once rows are sent as changes.
- 2026-11-07 11:31. Step 0.6 was built, waiting only for its live load. The panel tells its driver through
  `ChooserSource` in the new `native/Source.swift`, with `PanelValue` in place of `LuaValue`, and
  Entry.swift answers it for Lua. The main thread probe moved out of Entry.swift into
  `native/Perf.swift`, since the drawing code calls it and the package has no Entry.swift.
  `Package.swift` beside `native/` builds every file but `Lua.swift`, `Entry.swift` and `bridge.h`,
  and `test/swiftpackage.sh`, run by `suite.sh dry`, builds it and runs `olm-chooser-smoke`, a list
  from a fake source with no window. Two facts about macOS 27's command line tools shaped it. Their
  SwiftPM's default build system fails to start, `Could not initialize build system`, and the older
  native one, deprecated, works, so the gate passes `--build-system native`. And they ship neither
  XCTest nor Swift Testing, so the check is an executable, and `swift test` for the app, which the
  plan names, works only with a full Xcode, which this machine has. Whether the app's tests need
  Xcode or stay executables is for step 1.1 to decide.
- 2026-11-07 11:43. Step 0.6's live load passed. Through the test lock the worktree's library built
  in the background, the fallback served until the reload as it should, and after it the swift
  chooser served the new image with the probe answering, and the console held no error, only the
  five warnings this machine always has, IVPN absent, a screen with no display profile and two keys
  the layout lacks.
- 2026-11-07 12:04. Steps 0.3b to 0.3e were finished together, and stage 0 with them. Lifting the bottom bar,
  keymap resolution, the remap and the list keys by hand meant transcribing a 1900 line module's
  tests, so they were lifted mechanically instead. `test/fixtures-record.lua` runs an existing test
  with a module's functions wrapped and writes each call it makes and the answer as kind `calls`,
  a function handed in recorded with its whole dialogue, and `fixtures.lua` replays them, 276 cases
  in all. Four things had to be learned to make a recording faithful. A module changes the tables
  it is handed, so it is called with the real tables, recorders swapped in place and back, and the
  arguments after the call are kept when they changed. A table inheriting through `__index`, the
  keycodes, is read through its chain, and one whose `__index` is a function is carried as lazy,
  raising on replay if read. A `kbd` key or chord is a typed value. And the dry gate's stand in
  keycode table invents codes as names are asked, so the recordings use a real table dumped from
  Hammerspoon into `test/fixtures/keys/keycodes.lua`, and each composition run under the recorder
  is checked against its keymap's golden. Two recordings then differed, because `lib/resolve.lua`
  filled `plan.obligations` and each `degraded` list in pairs order, which changes per run, so both
  are now sorted once filled, which changes nothing but their order and makes the plan the same on
  every load. The bottom bar is recorded from `keymap-person.lua`, the only plain test that calls it,
  so it moves with the person's keymap as `keys.golden` does, and `goldens.sh --update` records the
  fixtures again. They take 2.4 MB, nearly all of it the plan each fixture keymap's run builds.
- 2026-11-07 12:21. Step 1.1 was finished. Olm.app's code is `app/` inside the spoon, beside the
  Lua it replaces piece by piece, so the spoon stays the one thing that is Olm, and its package
  depends on the swift chooser's by path. It is built into `~/.olm/app`, beside Olm's data and out
  of the Applications folder, since it is a part of Olm rather than an app a person opens, by
  `src/setup-olmapp.sh` where the `olmapp` piece is on, off by default. Its bundle id is
  `local.olm.Olm`, a placeholder until signing in stage 6 needs a real one. The app's checks are
  programs, `test/olmapp.sh` today, rather than `swift test`, because the command line tools ship
  no test framework and a check only a full Xcode can run would leave the other machines
  unchecked. `hs` was found to wait on a stdin that is no terminal, which made a captured call look
  as if it printed nothing.
- 2026-11-07 20:30. Step 1.2 was built, waiting for its hand trial. A machine's piece reaches the
  running config as `~/.hammerspoon/machine-pieces.lua`, written by `src/setup-hammerspoon-apps.sh`
  from `src/machine.sh` beside the two machine files it already copies, since Hammerspoon cannot
  ask `machines/` and a difference between machines is a piece, never a branch. The open key is
  taken by swapping the function its keymap row runs, in the root between the keymap and the
  binder, rather than by a keymap entry naming the chord, which would have had to repeat file
  search's chord on that machine and drift from it. So the keymap, the cheat sheets and the goldens
  are the same with the piece on or off. Which tools the app serves is a list in
  `config/plugins.lua`, since the dry gate keeps a host from naming a plugin. The key opens the app
  with `open -g`, which does not bring the app forward, since its chooser is a nonactivating panel.
- 2026-11-07 20:50. Step 1.2 was finished. Milos tried it with the olmapp piece on, and file
  search's key showed the app's chooser, which closed on Escape and on a press outside, while the
  launcher's file search scope still searched in Lua. With the piece off again the key opened the
  Lua file search, so the back out holds. The first reload with the piece on came up on the fallback
  chooser, the swift library rebuilding itself with no Swift source changed, cause not known.
- 2026-11-07 20:53. Step 1.3 was split into six parts in the plan, since it ports the grammar, the
  ranking and the index and also moves a list, each of which has its own gate. 1.3a was finished:
  the grammar is `app/Sources/OlmSearch/Query.swift`, read in UTF-8 bytes as Lua reads it, and
  `olm-fixtures` runs the shared JSON fixtures in Swift from the dry suite. A kind not ported yet
  is reported, never counted as a pass.
- 2026-11-07 20:58. Step 1.3c was finished. The app searches file search's index by running the
  plugin's own helper, `fileindex.swift` compiled into the app's bundle, rather than by compiling
  that source into the app as a library. The file has top level code, which a library target cannot
  hold, and splitting it would have changed how the Lua plugin builds its helper in a step meant to
  leave the plugin alone. The app reads the index the Lua side builds and never builds one, so the
  index has one owner. A search of the real index, 170,196 entries, measured about 10 milliseconds
  with the process start. The ranking port, step 1.3b, runs in parallel in a worktree of its own.
- 2026-11-07 21:04. Step 1.3b was finished, the shared ranking ported to Swift as `Match.swift` and
  `Rank.swift` in `OlmSearch`, by an agent in a worktree and checked here before it was taken. Every
  rank.order and rank.corpus case passes, and 5176 generated queries over 77 hard rows agreed with
  the Lua answers. The JSON reader tells a boolean from a number by its Core Foundation type, since
  `"bonus": 1` and `"pinned": true` otherwise read as each other and the engine's checks depend on
  the difference. The long field memo was left out, which costs time on a body over 256 bytes and
  changes no answer.
- 2026-11-07 21:10. Step 1.3d was built, waiting for its hand trial. The app's file search engine
  narrows, ranks and answers off the main thread over the index, and the app's chooser lists it.
  What the app reads of the config, file search's types and limits, the bridge writes to
  `~/.olm/run/filesearch.json` where the piece is on, so the Lua config stays its one owner and the
  app holds a copy it never edits. The panel's types stay reached through a testable import rather
  than made public, since making them public touches every file Hammerspoon loads for no behaviour.
- 2026-11-08 00:23. The 1.3d trial, with the piece on. Typing listed results and Return opened the
  file. Every icon flickered on each keystroke, since the app sent each row without its icon and the
  list fetched icons only once a row was on screen. Fixed: the app caches each file's icon and sends
  it with the row, and an answer with the same files in the same order redraws nothing. The window
  having no preview pane led Milos to state that all functionality must be preserved as the plan
  moves. That is rule 9 of the plan now. 1.3f keeps its timings and trial and loses the flip,
  1.4e adds the folder search, 1.4f the bottom bar, the actions and info panes and the remaining
  keys, and 1.5 checks every feature against a written list before the flip.
- 2026-11-08 00:58. The 1.3d second trial passed, the icons steady and Command and Return revealing
  the file. Milos said he does not want to see a difference in the core's UI, so the look is part
  of rule 9. The app's chooser now draws with the swift chooser's own style and sizes, which the
  swift provider's look builds by running the Lua view's restyle and place against a recording
  native table for each half, and the bridge writes to `~/.olm/run/chooser.json`. Both
  Hammerspoon's panel and the app read those tables through one field list, `native/Fields.swift`,
  and the app places them with a port of `geometry.resolve` pinned by a recorded fixture. Writing
  the look again in Swift was not done, since two descriptions of one look drift. The open key's
  URL now carries Olm's placement choice, since it changes with no reload.
- 2026-11-08 01:40. Milos asked for the app's structure to be designed before more of file search
  lands in it, and better than the Lua Olm's. `docs/DESIGN-APP.md` in the spoon is that design.
  Every plugin Olm ships becomes Swift, each a module that can import only the shared vocabulary,
  and JavaScript is kept for extensions someone else writes, only if wanted. Every list, native or
  bridged, answers through one `ListSource` protocol shaped like the bridge's requests, so a
  plugin's flip is which source the registry hands the stage. Step 1.3g moves the pilot onto it
  before 1.4a.
- 2026-11-08 08:05. The look trial of 1.3d passed. Milos found the app's file search matching the
  Lua one apart from the preview pane, step 1.4a, so handing the app the swift chooser's own
  tables holds, and 1.3d is ticked.
- 2026-11-08 08:45. The shadow of 1.3e runs from the Lua side. The plan had the app ask Lua for
  each query, which needs the app to be the list a person types into for those days. Milos chose to
  keep the Lua file search as the daily one, rule 9, so the Lua list hands each settled answer to
  the app, `olm://shadow`, and the app answers it with an engine of its own and logs the
  difference. While it runs, the bridge serves no key, and a trial adds file search back for the
  trial alone.
- 2026-11-08 09:10. Step 1.3g put the pilot on docs/DESIGN-APP.md's structure. Two choices came
  out of the code rather than the design. Opening a file and revealing it are effects the stage
  performs after hiding, not services a plugin calls, so the work never lands in Olm.app's window
  and a plugin is checked with no AppKit. And the index ask is cancelled with its task rather than
  superseded by a generation, since an async ask that never answers leaks its continuation. The
  design file was corrected in the same change.
- 2026-11-08 12:30. The three timings of step 1.3f are measured inside the swift chooser's panel,
  `native/Timings.swift`, not by signposts on the app's stage as docs/DESIGN-APP.md had it. The
  Lua file search inside Hammerspoon and Olm.app draw through the same panel, so one piece of code
  on one clock times both, which is what makes the numbers comparable. A signpost on the stage
  would have timed the app alone. It is off unless `~/.olm/run/timings` exists, so neither process
  pays for it outside a trial. The design file was corrected in the same change.
- 2026-11-08 17:40. Corrected. The entry of 08:45 had the bridge hand each settled answer to the
  app through `open -g` and `olm://shadow`. Running `open` while the Lua file search was up, opened
  by its own key, left that list with no rows for anything typed, while the same list reached
  through the launcher worked, found in the 1.3f trial and narrowed live, the shadow off and then
  only its open left out. The mechanism inside AppKit was not traced. The bridge now starts the app
  once, hidden, when the shadow is wired, and tells it each answer by the distributed notification
  `local.olm.Olm.shadow`. The note of 09:10 under 1.3g blaming a test for the same symptom was this
  fault too.
- 2026-11-08 21:30. Found. The one hidden start of 17:40, `open -g -j`, left the app hidden, and a
  hidden app's panel takes key but is never drawn, so with the app serving file search's key the
  key took focus and showed nothing. The stage now unhides the app as it opens a list, so the
  hidden start stays and a list is drawn however the app was started.
- 2026-11-08 21:45. Step 1.3f is ticked on its trial, the app's echo steadier and its worst
  settle 172 ms against the Lua file search's 9 s. The three character minimum on an unscoped
  file search is kept for now and became step 1.4g, since the shadow of 1.3e compares both sides
  and a limit lowered on one side would log every short query as a difference.
- 2026-11-08 22:35. Step 1.4a ports the parts of the Lua UI kit a preview pane uses into the app,
  `measure.lua`, `tabs.lua`, `layout.lua` and `sidepanel-nodes.lua`, rather than having Hammerspoon
  lay the pane out and hand the app its elements, since the app describes rows Hammerspoon never
  sees and rule 8 keeps that work off any main thread but the app's own. The tokens are not ported,
  they come from the kit through the bridge, `chooser.json` under `pane`, so the look keeps one
  owner as rule 9 asks. A width is NSString's size with the font alone, which equals
  `hs.drawing.getTextDrawingSize` to the last bit for every role's font, so the two sides break a
  line at the same character. The fixture `test/fixtures/chooser/pane.json` records every width the
  Lua layout asked for with what it drew, so the Lua runner checks the Lua code offline and the
  Swift runner checks the port and its measurer against the same answers. The read is the helper's
  peek done in process on a thread of its own, checked against the helper by `olm-index-check`.
- 2026-11-08 23:55. Step 1.4a is ticked on its trial. A served key reaches a running app by the
  distributed notification `local.olm.Olm.open` rather than `open`, some fifty milliseconds sooner,
  and `open` stays for an app not running. The stage shows a window only once its first rows and
  first preview are drawn, capped at 150 ms. The pane's scroll keys move to 1.4f with every other
  list key, since Hammerspoon holds the leader and no Hyper chord reaches the app's list today.
- 2026-11-08 23:40. Step 1.4h is added at Milos's request. `.app` listing Safari alone, seen in the
  1.4a trial, is the shared helper's `recent` skipping every folder, so a folder named with the type
  asked for is kept. It changes the helper both file searches ask, so both move in one step.
- 2026-11-08 23:45. Step 1.4b, built and not yet tried by hand. Olm.app's file search keeps its
  Quick Look renders in a directory of its own, `~/.olm/cache/filesearch/previews-app`, named and
  swept as `thumbs.lua` names and sweeps its own, and only reads the Lua side's `cacheDir`, rather
  than sharing one directory. Rule 1 asks one owner per store, and the Lua side's scratch folder
  for a render is named after the render, so a second writer running the same render would rename
  the result out from under the first, and two sweeps would each count the other's files. Reading
  costs nothing and saves a second render of a file the Lua side already drew, and a file swept
  between the look and the read is only a miss. The renders are `qlmanage -t -s imageEdge`, the Lua
  invocation, rather than `QLThumbnailGenerator`, so both panes are handed the same pixels, 72 dpi
  and 600 on the larger edge, and the same type answers the same way. A raster within
  `nativeMaxBytes` is drawn from its own file as on the Lua side, though the app has no main thread
  reason for the cap, since a picture through Quick Look is 600 pixels and one drawn from its file
  is its own size, and keeping the cap is what keeps the two panes alike. Unlike the Lua side a
  render is bounded at 20 s and ended once no row waits on it.
- 2026-11-09 10:10. Step 1.4b ticked after a trial by hand in three rounds. The app's preview pane
  never shows a row the highlight has left, Milos's rule. Past 150 ms without the highlighted row
  drawn, the pane shows that row's name over the system spinner, whatever the read waits on. Fixing
  the one hold he saw was tried first, by a trace through NSLog, and could not be read, since the
  unified log redacts an NSLog argument, so a rule that covers every hold was chosen over a fix for
  one. A picture on its way shows the spinner in place of the word rendering, so the app's pane
  differs from the Lua one there, by his call over rule 9's look.
- 2026-11-09 10:10. A file iCloud holds as a placeholder, `dataless` in its stat flags, is never read
  by the app's pane, Milos's call, since reading its head or rendering it downloads it, which held
  the whole pane on the download. It is described from its stat, heading and facts, and said to be
  in iCloud and not downloaded. Downloading it on the preview, as the Lua pane does, was rejected.
  A Download action with its shortcut named in the pane is step 1.4i, after the actions pane of
  1.4f. The Lua side is left downloading, rule 7.
- 2026-11-09 10:10. Every trial handed to Milos is written out as a numbered list of actions with
  what each should show, a few scenarios that might hold a hiccup, and what to report, his rule,
  in the plan's How we test.
- 2026-11-09 10:25. Found while planning 1.4j. Olm.app is signed ad hoc, `codesign -d -r-` answers
  `designated => cdhash H"..."`, so the privacy system takes every build for a new app and forgets
  its folder grants on each `setup-olmapp.sh`, which is why the prompts kept coming back during the
  1.4b trial. Asking up front is worthless until the identity holds across builds, so 1.4j fixes
  that first, by a designated requirement naming the bundle id or a certificate made once on the
  machine, chosen by which one macOS is seen to keep a grant for.
- 2026-11-09 10:40. Step 1.4j built, not yet tried by hand. The app is signed ad hoc with a
  designated requirement naming its bundle id, so a rebuild is meant to keep its folder grants, which
  only a live rebuild can show. A signing certificate made on the machine was kept as the fallback,
  since it needs a keychain step a person takes. File search asks for Desktop, Documents and
  Downloads from one pinned row on its first open, rather than a window of its own, since a row in
  the list is how every Olm choice is offered, and its preview says why. Asking at the app's launch
  was turned down, since the shadow starts the app hidden and a prompt nobody expects would arrive
  then. The answers live in the plugin's store, `~/.olm/state/filesearch`.
- 2026-11-09 11:40. Step 1.4j ticked after a trial by hand in three rounds. The designated
  requirement naming the bundle id keeps a folder grant across a rebuild, seen live, so the
  certificate fallback is not needed. A refused folder is asked again from the list, Ask Again,
  which resets the app's own answer with `tccutil` and touches the folder, rather than sending the
  person to System Settings, where Milos could not find the switch. Saying a refusal once was
  rejected, since the row was gone before he could use it, and the row now stays while a folder is
  refused. Both rows wear ✅, his rule that a row wears its intent and never its state.
- 2026-11-09 14:45. Step 1.4f's design note agreed, `docs/DESIGN-APP-LIST-KEYS.md` in the spoon.
  While Olm.app's file search is up, the app tells the bridge so by a distributed notification,
  `lib/listopen.lua` answers that list open through a question the root hands in, and every list
  key routed to it is posted to the app as a verb the app runs on its own highlight, step 3.4's
  shape on 1.2's notifications. Milos left the three open choices to whatever best keeps speed and
  consistency. The bridge marks the list open the moment its key posts the open note, dropped if
  the app has not confirmed within a second, so a list key typed straight after the open key never
  runs the global binding. The words for the bar and both floating panes are a share written at
  load from the same plan, since nothing then crosses per keystroke and file search has no live
  gate, a live bar model being stage 2's. The app's plain Command and J or K scroll goes, since the
  Lua list answers only Hyper with Command and J or K.
- 2026-11-09 16:20. Piece one of step 1.4f passed Milos's hand trial, every step but the preview
  scroll, whose key he turned down. Hyper with Command and J or K read as no key at all, a second
  modifier under a leader that is held, so both lists with a preview pane, file search and the
  clipboard, now scroll it on Hyper and D or U, down and up, Vim's Control and D or U. Keeping
  Command and J or K was rejected for that reason. Moving only file search was rejected, since the
  two lists would then scroll on different keys. The clipboard's Delete, which held D, moved to
  Hyper and Backspace, Milos's pick over Hyper and R. Hyper and U opens tmux sessions with no list
  open, and the open list's own key wins over it, as Hyper and J does over the emoji picker.
- 2026-11-09 18:05. Corrects the entry of 16:20 on the clipboard's Delete. Hyper and Backspace
  never reached macOS on this machine. A key watcher below Hammerspoon's hotkeys saw nothing for
  a physical press while a synthetic one arrived, so the press is lost under the system, kanata or
  its driver, and kanata's own log says nothing. Delete now sits on Hyper and R, for remove, in
  every list that has one, the clipboard, Display Profiles and Workspaces, Milos's pick over
  Hyper with Shift and D and over looking into kanata first. A key on a verb that declares
  confirm now asks first, the actions pane opening straight on that verb's Cancel and confirm
  rows, so the key and the pane ask the same question. Running the verb immediately was rejected
  as deleting a profile or a layout with no question. The same trial found the actions pane
  drawing the list on row one between giving the query back and putting the row back, a flicker
  through the first row's preview on every verb chosen there, so the row now comes back in the
  same turn and a chosen verb answers stay.
- 2026-11-09 19:10. Piece two of step 1.4f built, the bar, the info pane and the field keys of a
  list Olm.app serves, from a share the bridge writes at load, `<tool>keys.json`, as the design
  note decided. The bar is read in Swift through the shared field protocol, so Hammerspoon's panel
  and the app read it alike, rather than a second JSON reader beside the Lua one. The info icon
  crosses as a PNG data URL drawn by the Lua resolver, rather than an SF Symbol name the app would
  draw, since a person whose icon set is emoji would then see a different icon in the app. The
  app's own Command and Return lookup is gone, the share's field keys answering it.
- 2026-11-09 21:57. Piece two's trial found Escape over the app's info pane closing the whole list,
  since the app's stage hid on dismiss without asking the pane. Milos then stated the rule for both
  panes. A key that acts on the list closes an open info pane or actions pane and still does what it
  does, a move, typing, the preview pane's scroll or a verb, since a pane left open over a list the
  keys go on changing is not natural. Escape closes only the pane, and a shortcut that closes the
  list, a Hyper key opening another tool, closes everything as before. The app's info pane now
  closes on Escape, typing, a move by key, Backspace and every verb but its own, and a pointer
  passing over a row leaves it open. In the Lua lists the info pane already did all of this. The
  actions pane keeps its own keys, moving, Return, typing to filter and its toggle, and any other
  list key closes it first through the root's claim. The app's actions pane is piece three and
  takes the same rule.
- 2026-11-09 22:20. Milos asked, during the same trial, that the pointer follow the rule too. While
  the info pane or the actions pane is open the list behind it takes no hover, so its highlight
  and its preview hold, a scroll anywhere but on the pane closes the pane and moves nothing, and a
  press behind the actions pane closes it and chooses nothing, as a press behind the info pane
  already did. The bar keeps its own presses. One engine word, closePanes, closes whichever pane is
  open, asked by the Lua canvas, the native panel through the swift view and the app's stage alike.
- 2026-11-09 23:05. Piece three of step 1.4f built, the actions pane in the app's file search. Its
  rows and its open bar come from the same share as the bar, rowsFor and bottomBarModel with the pane
  open, rather than a second list of verbs written in Swift, so the words, icons and keys are the Lua
  pane's. A row the app cannot run is left out rather than shown dead, which keeps Quick Look until
  1.4c and Into Folder and Up a Level until 1.4e off the app's pane, written down so the parity list
  of 1.5 asks for them. The applies gates are answered by the source through a new ListSource word,
  as the Lua surface answers them through its colon methods.
- 2026-11-09 23:52. Piece three passed its hand trial and merged. Milos asked in it that the actions
  pane's search leave the list's input field, in every list. The pane carries its own search field
  as its bottom line, at the size of the pane's rows, its placeholder Search Actions, and the caret
  moves into it while the pane is open, so the list's field keeps its text and nothing has to be
  given back on close. Both fields derive from one base field made customizable, rather than a
  second text field written beside the first. Built next, before Command and a digit.
- 2026-11-10 00:40. The actions pane's own input field built, in the swift chooser, the canvas
  chooser and Olm.app alike. Both fields come from one, `native/InputField.swift` in Swift and
  `field/render.lua` on the canvas, rather than a second text field written beside the first. The
  engine keeps its one text and the pane still clears and restores it, rather than the engine
  growing a second query, since the views drawing the held text in the list's field and the live
  one at the pane's foot gives what Milos asked for with no change to how any key is decided.
- 2026-11-10 00:15. Milos placed the pane's field in its trial. Its text starts exactly at the left
  edge of the rows' icons rather than under the labels, and no rule stands above it, so it reads as
  one more line of the pane. Typing that filters out every row shows one dimmed line, No results,
  the list's own words, left aligned where the first row would be, rather than an empty pane.
- 2026-11-10 00:55. Piece four of step 1.4f, Command and a digit held against the Lua list. Over an
  open actions pane the Lua list chose the pane's row in that place, though the pane's rows carry no
  number, and the app closed the pane and chose the list's row. Milos chose the app's answer, the
  pane rule applied to the digits, so the Lua engine closes the pane before choosing the slot. The
  app now also chooses whether or not the list shows numbers and moves the highlight first, as the
  Lua list does.
- 2026-11-10 08:28. Piece four's trial found a pane closed by the key that also closes the list,
  Command and a digit or an action chosen in the actions pane, starting its fold onto the bar and
  the list's fade then cutting the fold halfway. Such a pane now goes down whole with the list, the
  way the list closing over an open pane looks. The app leaves both panes standing until the row's
  answer is back and closes them only when the answer keeps the list up, and the swift panel takes
  back a fold that has drawn no frame yet when it hides, which is the Lua engine closing the pane
  and the list in one turn. Milos confirmed it in the app. The clipboard list he tried was the
  canvas chooser, so the panel's take back has no hand trial in a Lua native list yet.
- 2026-11-10 08:40. The panel's take back was then tried by hand in the Lua native list, file
  search served by Hammerspoon again, and Milos confirmed it, so piece four passed and step 1.4f is
  done.
- 2026-11-10 09:10. Step 1.4c, Quick Look in the app, design note `docs/DESIGN-APP-QUICK-LOOK.md`
  agreed by Milos. The app opens the Lua helper's own panel, `viewers/quicklook.swift`, in its own
  process, `OlmCore/QuickLook.swift`, rather than compiling and starting the helper per file, so
  the two lists look the same. The source answers a `quickLook` effect for its `peekPreview`
  action, the Lua verb's name, and the stage owns the panel and the list's rules, Escape closing
  it first, the list closing it with itself and a press on it not counting as outside the list.
  The panel refuses key, since in the app's process it would take key from the list, which closes
  on resigning it. The use Quick Look notes for frecency is left to 1.4d, and the app offers Quick
  Look without the Lua list's `askedPreview` gate, having no helper to compile.
- 2026-11-10 10:05. Step 1.4c's first trial. Milos asked that Quick Look be one Olm glass pane
  following Olm's radius, paddings, fonts and colours rather than macOS's panel, with a top line
  of close disc, file name and an Open in button carrying the Return key cap, the content in a
  rounded inset below, and that it live in the core for every plugin and both lists. He chose the
  header and the core placement, and agreed that the pane follows the highlight, which the Lua
  helper never did only because a process per arrow key was too slow, and which keeps the Return
  key cap honest. Built as `native/QuickLook.swift` in the swift chooser's shared library, owned
  by the panel, which keeps Escape, closing with the list and a press on it, and reached from Lua
  by a root word `quickLook(path, follow)`. The note had the helper move into the core as the
  word's fallback for the canvas chooser. In the build it stayed in file search instead, run only
  where the word answers false, the same behaviour with no dependency moved. The app's own
  `OlmCore/QuickLook.swift` from the first build was removed.
- 2026-11-10 12:16. Step 1.4c's look, from Milos in the app's trial. The header is one actions
  pane line tall with its paddings, the close is the `xmark.circle.fill` symbol at the info pane's
  icon size in the dim text colour, and the Open button's Return key cap ends at the inset's right
  edge. He asked for the cap to round on the pane's corner. A top right corner of its own was
  built first and he rejected rounding one corner alone, so a key cap keeps one radius for all four
  corners, nested in its holder's as before, and a host may drive it instead, which only the Quick
  Look pane does, at the glass's radius less the padding.
- 2026-11-10 12:40. Step 1.4c's hand trial passed in the Lua native list too, file search served
  by Hammerspoon again, Milos confirming every step, the pane's look, following the highlight,
  Escape closing the pane alone, a press on the pane, Return and the Open button opening the file
  shown, and the pane closing with the list. Step 1.4c is done, and 1.4k is next.
- 2026-11-10 13:30. Step 1.4k, Copy File and Copy Folder, built, Milos having asked for it and
  then for the build. One verb, `copyFile` on Hyper and C, puts the file or folder itself on the
  clipboard as a file URL, the way Finder's Copy does, in the Lua list through
  `hs.pasteboard.writeObjects` and in the app through a `copyFile` effect. Two verbs sharing c,
  one per kind, was turned down, since the keymap refuses two actions on one slot. Its word over a
  folder comes from the presentation's existing `labels` member, which now answers any verb by its
  action name beside `primary` and `secondary`, so the bottom bar, the info pane and the actions
  pane read one answer, and the app's source answers the same through a new `label` call. The
  app's info pane now opens once the source has given its lines their words, so a line never
  changes under the eye.
- 2026-11-10 13:55. Step 1.4k's hand trial passed in the app and in the Lua native list, Milos
  confirming the word over a file and a folder in the actions pane and the info pane and a paste
  in Finder copying the file and the folder, and he asked for the merge. Step 1.4k is done.
- 2026-11-10 14:20. Step 1.4h built. The helper's `recent` keeps a folder when a type is asked
  for and the folder's name ends in it, a bundle such as an app, and leaves every folder out of
  the untyped recent list as before. Both file searches ask the one helper, so both change, and a
  bundle's row and preview pane stay a folder's, as the plan has it.
- 2026-11-10 14:40. Step 1.4h's hand trial passed in the app and in the Lua native list, Milos
  confirming `.app` listing every app, an app opening on Return, the plain recent list keeping
  files only and another type unchanged. Step 1.4h is done.
- 2026-11-10 15:20. Step 1.4e, folder search in the app, design note
  `docs/DESIGN-APP-FOLDER-SEARCH.md` agreed and built. The app runs the Lua side's own tools, a
  browse through `/bin/ls` and a search through fd with walk.lua's arguments, so gitignore and the
  bang mean the same in both lists. Milos chose how the app finds fd, the root writing each served
  list's declared tools as the door resolved them into a `<tool>tools.json` share, so fd stays
  declared once and resolved once, over the app looking for it itself, which would be a second
  resolver. He chose too that the shadow compares a browse, which ls orders, and keeps skipping a
  search beneath a folder, which fd answers in no fixed order and cuts at its cap. Into Folder, Up
  a Level and the `..` row write a query into the field through a new `setQuery` effect. The note
  had shared fixtures pin the resolution, and since the Lua resolver asks `hs.fs`, which the
  fixture runner cannot stand in for, the Swift port is pinned by the index check instead.
- 2026-11-10 15:50. Step 1.4e's hand trial passed in the app and in the Lua native list, Milos
  confirming a browse with its `..` row going up in place, Into Folder and Up a Level, a search
  beneath a folder, a hidden one, a folder that is not there, an empty folder, and an unscoped
  search unchanged. Step 1.4e is done.
- 2026-11-10 17:05. Step 1.4d, frecency in the app, design note `docs/DESIGN-APP-FRECENCY.md`
  agreed and built. The app keeps a port of `frecency.lua` in its own state folder, gives every row
  its use as a bonus, floats the paths used most to the top of the plain recent list, notes a use
  on every action but the `..` row's, and shows USED in the preview pane. Milos chose the history
  reaching the app through a `<tool>history.json` share the root writes for a served list from the
  plugin's `history` word, and the app taking it whenever it holds a use newer than the newest it
  took last time, so each flip carries the latest Lua history over and a reload while the app
  serves takes nothing. The shadow now compares the recent list, frecency left out on both sides,
  the Lua engine handing its dates before the float and the shadow's own source keeping no store.
- 2026-11-11 12:30. Step 1.4i, Download in the app, design note `docs/DESIGN-APP-DOWNLOAD.md`
  agreed and built. Milos chose Hyper and G, and the list staying up while the file comes down. The
  verb is declared once, in the Lua manifest the app reads its actions and keys from, behind an
  `isPlaceholder` gate the Lua list always answers no, since its preview downloads the file anyway.
  The app asks iCloud with `startDownloadingUbiquitousItem`, the pane says downloading and stays
  pending until the stat flag clears, then reads the file. The pane names Download's shortcut by
  verb and the stage spells it, so no source writes a key.

- 2026-11-11 15:14. Step 1.4i, the download shows how far it has come. Milos found the spinner
  alone looked like nothing was happening. macOS publishes a file's download progress, the one
  Finder's pie reads, through `Progress.addSubscriber(forFileURL:)`, measured here on a 6 MB
  placeholder at about four answers a second with no entitlement. `CloudFiles.watch` follows it,
  the preview carries `progress`, its words say the bytes, and the pane draws a meter under the
  heading, edge to edge, in place of the spinner. A floating AppKit bar in the pane's centre came
  first and was replaced the same hour at Milos's ask, by `kit.meter`, a component of the shared
  kit in our own colours, `decisions/olm-colour-roles.md` 15:14. `OLM_DEMO_DOWNLOAD=0.6` launches
  the app with Download standing still at that fraction, to look at the meter.
- 2026-11-11 15:30. Step 1.4i passed its hand trial in the app and in the Lua native list, the
  meter included, and is ticked. 1.5 parity is next.
- 2026-11-11 16:30. Step 1.5, the parity list `docs/PARITY-FILESEARCH.md` found five gaps and all
  five are built on `olm-app-parity`. The index never moved while the app served, since only the
  Lua list's open rebuilt it, and Milos chose that the list that serves owns it, as frecency's
  owner was chosen in 1.4d. `IndexBuild.swift` warms it on an open as `index.lua` does, and an
  answer while it runs is pending, a new `rowsLanded` the stage asks the way it asks
  `previewLanded`. The helper's temporary file is now its run's own, since a Lua build from the
  launcher's slash scope can run beside the app's until stage 3. The folder under a row is fitted
  by `PathFit`, a port of `elideDir`, the empty states are rows through a manifest's `statuses`, a
  question mark shows the grammar, found while porting the statuses, and `pruneLocal` reaches the
  app through the share. A status and a help line are inert rows, never chosen, previewed or acted
  on, the Lua row's enabled false.
- 2026-11-12 10:05. In 1.5's hand check Milos found the list slow to answer its first keys after
  the app had sat idle, keys doing nothing and then arriving together. Sampled live during the
  lag, both apps' main threads were idle and Olm's was sampled at half the rate Hammerspoon's
  was, so the app was being throttled, not busy. The index build that ran at the same time was
  measured and ruled out, the list's own asks taking 14 to 89 ms beside it. Olm.app is a
  background agent idle between opens, which App Nap throttles, and its Info.plist never said
  otherwise, while Hammerspoon's carries `NSAppSleepDisabled`. Olm's now carries it too, since an
  app that answers a key has to answer at once.
- 2026-11-12 10:40. The slow first open, traced the same morning, is answered rather than left for
  a later step, Milos finding it still sluggish after the App Nap change. While the list is hidden
  the stage now reads what a first open reads, a source's new `prepare`, file search's recent
  list, and the icons and the top row's preview of the rows a screen shows, at launch, a second
  after every close and every ten minutes, for the tools the bridge's new `serves` share names.
  Nothing is drawn and a warm never checks the folder permissions, so it can raise no prompt. It
  does not rebuild the index, which stays on an open, since a crawl every ten minutes while idle
  costs more than a stale index the next open replaces.
- 2026-11-12 15:20. The warm made the first open fast, and Milos still felt a stutter in its first
  seconds. A trace of both processes on one clock found Hammerspoon handing each Hyper J on within
  2 ms and the app's main thread mostly idle, sampled at 86 percent waiting, while its timers and
  frames ran 40 to 370 ms late. So the app was not doing too much, it was not given the machine.
  During those seconds the window server sat near 90 percent, the Mac had 75 MB free with 3.8 GB in
  swap, and the index rebuild an open starts was crawling beside it. The Lua list, opened the same
  way with the index aged, stuttered the same until its rebuild finished, Hammerspoon's own main
  thread held 30 to 210 ms at a time, so the app is no worse and this is not a flip blocker. The
  app's rebuild now runs at background priority, `qualityOfService = .background` on the helper,
  so the crawl takes CPU and disk only when nothing else wants them. Ruled out, the icon lookup,
  the row fit, the preview's layout and draw, each under 15 ms and off the main thread where heavy.
- 2026-11-12 15:45. The flip's design, with Milos. Going back is the olmapp piece turned off and a
  reload, as the plan says, rather than the serves line, which would be a config edit. He chose
  that going back carries the app's uses to the Lua list. Reading for it found that 1.4d's import,
  the app taking the Lua history whole whenever it holds a newer use, would lose uses after the
  flip, since the launcher's slash scope stays on the Lua side until stage 3 and records there, and
  one such use would replace every use the app had made. Rejected, keeping the replace and adding
  the same on the Lua side, for that loss. Chosen, both sides merge, each path keeping whichever
  side used it last, the app on an open and the Lua plugin on every load through the bridge's
  `appState` and its `takeHistory` word. The shadow line stays in `config/plugins.lua` at the flip,
  revising the plan's note that the shadow ends there, since it compares nothing while the app
  serves and resumes by itself after a back out. Found beside it, a config with no serves line left
  the last load's serves share in place, so the app went on warming a tool taken back. The bridge
  now writes an empty list then.
- 2026-11-12 16:30. The flip of step 1.5. `config/plugins.lua` commits `serves = { "fileSearch" }`,
  so Hyper and semicolon opens Olm.app's file search wherever the olmapp piece is on, today only
  Jelenas-MacBook-Pro. Going back was tried with Milos before the commit, as rule 2 asks. The piece
  turned off and a reload opened the Lua list, with the file he had just revealed in the app
  leading its recent list, and turned on again the app opened with the file he revealed in the Lua
  list leading. A piece turned off leaves the serves share as the app last read it, since the bridge
  writes no share where the piece is off, which is harmless, the app warming a list nothing opens.
- 2026-11-13 11:10. Step 2.1, the transport probe, open question 2. A scratch echo in the live
  Hammerspoon, nothing in the config changed, answered a compiled Swift client over a Unix socket
  under `~/.olm/run` and over `hs.httpserver` on localhost, decoding and encoding the JSON as the
  bridge will. Round trips, median, socket read to a newline against HTTP: 200 B 0.34 ms and
  1.65 ms, 10 KB 1.2 and 4.1, 100 KB 9.6 and 4.8, 1 MB 219 and 35, 4 MB 3130 and 84. The socket
  read to a newline grows far faster than its size, inside `hs.socket` off the main thread, which
  was held at most 82 ms, the JSON. Reading a length sent first instead, 200 B 0.67 ms, 100 KB 4.4,
  1 MB 22, 4 MB 85, in step with size. Found besides. An `hs.socket` server writes every message to
  every client connected and cannot tell them apart, tried with two clients. It cannot check its
  peer. The socket is created mode 0755 in a `run` folder of 0755. `connected()` answers a boolean.
  `hs.httpserver` 1.1.1 has no `setMaxBodySize`. Chosen by Milos, a Unix socket, the app listening
  and the Lua side connecting, so the app holds one private connection and checks its peer, and
  each message its length on a line and then the JSON. Rejected, the socket as 0.4 wrote it, the
  Lua side listening and a newline ending each message, for the broadcast, the missing peer check
  and the slow large read. Rejected, local HTTP, which carries only the app's requests, so the Lua
  side could send nothing unasked without polling or a second server, and which needs a token and
  Origin and Host checks. `docs/PROTOCOL-BRIDGE.md` is revised to it.
- 2026-11-13 11:45. Step 2.2, the bridge serving the launcher read only over the socket 2.1
  chose. Four files under `host/bridge`, the framing, the routing, the methods and the
  connection, the first three pure and replayed in the dry gate, so only `transport.lua` meets
  `hs.socket`. It serves `hello`, `metrics`, `catalog`, `icons`, `open` for the launcher, `rows` and
  a `close` the protocol had named and not written, and every other method, `choose` among them,
  answers -32601, so nothing can be run. The rows are the launcher's own supplier through a new
  `bridgeRows`, which also answers whether a scope claimed the query, `exclusive`, so the app's
  launcher and the Lua one cannot list different rows. A row's key is its memory key where it has
  one, recencyKey, and is minted per item table otherwise, so a launcher row keeps its key across
  answers. A superseded `rows` is answered stale on the next turn of the run loop, since
  Hammerspoon hands one message per read and the turn is how the bridge sees what else had come.
  The changes a row needs are found by a signature with its keys sorted, since hs.json need not
  keep an order and every row would read as changed. While no socket file is there the connection
  tries nothing and says nothing. Off by `socket = false` in `config/plugins.lua`. Live, a command
  line client in the app's place, `test/bridgecheck.sh`, had Hammerspoon connect within moments of
  its listening note, its peer this user, hello in 1.2 ms, the catalog of 219 rows in 37 ms, the
  launcher's rows in 16.5 ms and an unchanged answer in about 5 ms, and the console said connected
  and went and nothing else.
- 2026-11-13 13:46. Step 2.3, the launcher's shadow, its design note `docs/DESIGN-APP-BRIDGE.md`
  agreed with Milos. He chose the socket setting committed as true, since the olmapp piece already
  keeps the bridge to this Mac, over a per machine row, a second switch for the same thing, and the
  Lua launcher's settled answer told over the socket as a new notification, `shadow`, over file
  search's road of a file and a distributed notification, which would leave two roads to retire at
  3.2's flip. The app listens from launch in a new target, `OlmBridge`, on its own queue, and holds
  the launcher as a bridged source, its rows patched by each answer's changes and its bonus worked
  out from the memory the open sent and each `memory` notification moves, the Lua row's own bonus
  not read. `lib/queryassoc.lua` is ported into `OlmSearch` only so `olm-fixtures` runs
  `memory.json` whole and the eight `launcher.json` cases that do not step through the launcher's
  own supplier, through the same lookup the app reads the sent memory with. The shadow ranks a
  launcher level's `rows`, the road 3.2 takes, rather than `catalog`, which 2.2 served for it. Found
  while building. `limits.rowLimit` was 200 where the Lua stage cuts a list naming no limit at
  `chooser.rowLimit`, 50, so it is that setting now and the protocol's text naming the engine's
  `ROW_LIMIT` was wrong. The memory keeps a pick's spellings cut by bytes, so a query of letters
  outside ASCII can leave a spelling that is not UTF-8, which would have failed the JSON of the
  whole open answer, so `serve.lua` leaves such a spelling out. `metrics` waits for 3.2, since
  nothing asks for a width before the app has a list. The check program first hung, its blocking
  read on the main thread while the shadow it drove ran on the main actor, a fault of the check and
  not of the app. Result: `olm-bridge-check` 29 checks, `test/bridgeserve.lua` 34, the dry suite
  and the unit cases clean. Live with the lock, Hammerspoon connected moments after it loaded and
  fourteen queries through the launcher's supplier, an empty one, one letter cut at the row limit, a
  calculator answer, a capital and a claimed scope among them, all logged same, the console clean.
  Open: the gate, the log empty over a few days of Milos's own use.
- 2026-11-13 17:12. Step 2.3's gate moved, Milos's call. He did not want the plan held on the days
  of use the gate asks for, so 2.3 is ticked as built and live, the shadow keeps logging, its log is
  read at every step from here, and an empty log is a condition of 3.5, the flip of Hyper and Space,
  the first step a person relies on. The 13:46 entry above says the `shadow` notification retires
  at 3.2's flip, which was wrong, the flip is 3.5 and 3.2 is a trial key. Corrected in the design
  note and the protocol.
- 2026-11-13 17:12. Step 3.1, `choose` over the bridge, as the protocol's Running anything section
  wrote it, with no design note of its own since the protocol had settled the shape. It runs the row
  through a new `Launcher:bridgeChoose`, which does what onSelect does for the stage, the promote,
  the memory under the request's query and the run, so app switching and every command still run in
  Hammerspoon. No stage facade yet. A row whose intercept would make the list another list, a tool,
  an alias or a scope's word, is the only path that touches the stage, and it answers `unserved`
  without being asked to act until 3.3 serves hosted lists, so the facade joins there. The run waits
  behind `after hidden`, the app's `hidden` or a 1 s fallback, and `_runItem` gained `now` so the
  launcher's own 0.1 s wait is not added on top. A row its supplier no longer shows for the
  request's query answers `requery`, and a disabled row answers no effects. Found while building,
  an empty expected list in a transcript step accepts any answer, so the strict cases are pinned in
  `test/bridgeserve.lua` beside it.
- 2026-11-13 17:41. Step 3.1 live, Milos watching. `test/bridgecheck.sh calc --choose Calculator`
  with the lock on the branch answered `hide` and `after hidden` in 1.7 ms, the client sent
  `hidden`, and Calculator opened, the pick remembered under `calc` in the real memory, as Return in
  the Lua launcher would have done. Three things were found on the way. The first run's client read
  the `memory` notification, which the pick sends before the answer, as the answer and stopped, the
  run going through the 1 s fallback instead, which is the protocol working and the client wrong, so
  the client now says and passes a notification. Editing a file in the worktree while its config was
  live reloaded Hammerspoon mid run, and that load's shadow wiring started Olm.app, which took the
  socket's path back from the client, so a live check edits nothing in the live tree. And the
  transport ignored the app's listening note while it believed itself connected, while
  `hs.socket`'s `connected()` kept answering true for a peer that had died, so the bridge sat on a
  dead connection and never reached the new listener. A listening note now always reconnects, since
  it means a listener has just bound the path. Closing the level after the choose took 1.7 s, the
  run launching Calculator cold on Hammerspoon's thread as the Lua launcher does. The app sends
  nothing it waits on there, so it costs the app's list nothing.
- 2026-11-13 18:31. Step 3.2's design note agreed with Milos, `docs/DESIGN-APP-LAUNCHER.md`, the
  trial key Hyper and 0 and tool rows held in place, both as proposed. The key is the bridge host's
  action `bridge.launcher`, bound in this machine's keys file alone, since rule 9 puts a machine's own
  key there, and gated on a predicate of the piece, the app and the socket, so its launcher row shows
  nowhere else. A chord with Shift beside Hyper was ruled out, since this Mac sends Hyper as four
  modifiers through kanata and such a chord answers only on Caps Lock. Closing the app's list to open
  the Lua launcher on a tool row was turned down, the close and reopen one list becoming another
  forbids. Built the same hour. The shown launcher is a second bridged source beside the shadow's,
  as file search keeps its shadow apart, with a level for each show. Return's `after hidden` needed
  no effect of its own, since the stage already closes its source as it hides, so `hidden` goes out
  from that close, and the next open waits for it. The note first said `fromURL` would be served on
  the Lua side, and building showed nothing to hold back yet, since the launcher hands a list over
  only while the Lua stage shows it, corrected in the note and the protocol. The three timings are
  1.3f's, not a new log.
- 2026-11-13 23:38. Step 3.2's trial, Milos at the keys. Opening, typing, an app row, the
  calculator, the VPN row held in place and Escape all did what the steps said, and Hyper and 0 felt
  snappier than Hyper and Space. Return on Left Half moved Olm.app's own list to the left rather than
  the Herdr window. The stage told its source the list was closed, and so sent `hidden`, the moment
  it called the panel's hide, while the swift panel stays key through its fade, so the window action
  Hammerspoon ran on `hidden` found the fading list the focused window. The note and the build had
  read "hidden once `panel.hide()` returns" as enough, which the protocol never said, it says once
  the window is ordered out. The panel now reports the end of its fade, `onDown`, and the stage waits
  for it before closing the source, woken early by a new show and capped at 1 s. The shadow log stood
  at 23 lines and no difference after the trial.
- 2026-11-15 12:01. Step 3.2 verified. Milos tried the window actions again after the fade fix,
  Left Half and Right Half moved the Herdr window and an app row brought Safari to the front, and
  called it good. Ticked. The shadow log stood at 26 lines and no difference. The timing log was
  switched off again, `~/.olm/run/timings` removed. Hyper and 0 stays as the way into the app's
  launcher until 3.5.
- 2026-11-15 15:33. Step 3.3 built, Keep Awake shown inside the app's launcher on Hyper and 0,
  docs/DESIGN-APP-HOSTED.md in the spoon. One change from the note's first draft. The note had the
  root wrap the row intercept's `push` so a bridged choose would record it. Built that way, a
  bridged Return would have to run the row's whole intercept, and an alias row's seed or a scope's
  act run on the way would act on the hidden Lua stage. So the launcher asks
  `lib/rowintercept.lua`'s new `presentationFor` what the row would push and runs nothing, and only
  `redrawPresented` is recorded by the facade. The config's `hosts` beside `serves` names the hosted
  tools, `{ "caffeinate" }`, and taking a name out is the way back. Not yet tried live.
- 2026-11-15 20:58. Step 3.3's first tool verified. Milos ran the eight step trial of Keep Awake
  inside the app's launcher on Hyper and 0, opening it, a duration, Backspace back with the
  highlight, a timed session's redraw, `k 2h` fitting, Escape closing every level, and the Lua
  launcher's field after the shared input field's fix, and called it all good. Caffeinate ticked
  under 3.3, which stays open for the other tools. The shadow log stood at 50 lines and no
  difference.
- 2026-11-15 21:10. Volume is 3.3's second hosted tool, Milos's choice. Its note, a section of
  docs/DESIGN-APP-HOSTED.md, found nothing to grow, one typed row that fits with no stage word but
  its own open, so the config's `hosts` gains `volume` and nothing else changes. The note said the
  bridge fixture would gain a Volume case. It did not, since that case would replay the Caffeinate
  one over the same fake, and `test/bridgeserve.lua` drives the real plugin instead. Not yet tried
  live.
- 2026-11-15 21:14. Volume verified. Milos ran the eight step trial inside the app's launcher on Hyper and 0,
  the disabled rows answering nothing, a level, mute and unmute, Backspace back with the
  highlight, `vol 40` fitting and Escape, and called it all good. Ticked under 3.3, which stays
  open for the other tools. The shadow log stood at 62 lines and no difference.
- 2026-11-15 22:04. 3.3 is finished in five steps, Milos's go: open and close, the actions pane,
  the stage words, the preview pane, and file search answered by the app's own list. A survey of
  the ten tools left showed each needs one piece the bridge lacks, so a step adds one piece and
  hosts the tools that needed only it. The cycle keys stay with 3.6, a tool's own chord. The
  launcher's own actions pane on Hyper and 0, absent since `actions` was never served, joins
  3.3b, since it would block 3.5. 3.3a built: a hosted level is told its presentation's
  `onPresent` and `onClose` as the Lua stage tells them, under the facade, and a new session or a
  socket that went closes every level. Audio, Wi-Fi and Input Sources join `hosts`. Dock Auto
  Hide's row only toggles and needs nothing. Not yet tried live.
- 2026-11-15 23:13. 3.3a verified. Milos ran the seven step trial of Audio, Wi-Fi and Input Sources inside the
  app's launcher on Hyper and 0 and called it good. He asked why Audio and Wi-Fi keep their full
  height while a search leaves fewer rows. Neither declares `fit`, the only lever a list has, so
  both stay full height in the Lua list too, and nothing was changed. The shadow log stood at 69
  lines and no difference.
- 2026-11-15 23:23. A correction to the entry of 22:04, which said the launcher's own actions pane
  on Hyper and 0 was absent and would block 3.5. It is not absent. The launcher's only action
  would repeat Run, so `hints.dropIdleActionsPanes` gives the Lua launcher no Actions either, and
  there is nothing to bring over. 3.3b built: `actions`, `choices` and `run` served for a hosted
  level. The verbs are run on the owning tool's surface by its owner, not through the dispatch
  table, since that routes by the list showing and the list showing is the app's. A confirm's level
  is answered by `choices` too, Cancel and then the confirm row, so the app holds no confirm title,
  a small widening of the protocol written into its 3.3b section. The app's actions pane opens a
  level for a verb with choices or a confirm. Tmux Sessions and VPN join `hosts`. Not yet tried
  live.
- 2026-11-15 23:45. 3.3b verified, Milos's trial of Tmux Sessions and VPN with their actions pane levels inside
  the app's launcher. Two reports. Tmux's own list shows nothing with no session and nothing typed,
  the same as the Lua list, since its "No tmux sessions" row is answered only for the launcher's
  scope, left as it is. VPN's first open after a reload once stayed on "Reading the locations"
  until closed and opened again. Traced on both sides with a debug build never merged: the Lua side
  sends the redraw to the open level and its rows come back whole, and a traced cold open drew the
  locations 55 ms after the list. The app holds a pushed level before it first asks its rows, so a
  fetch landing after that answer reaches it and one landing before makes that answer whole, and
  no drop was found by reading. Believed a slow or timed out first fetch, which would hold the Lua
  list the same way, not proven. The debug build is reinstalled when it is seen again. The shadow
  log stood at 71 lines and no difference.
- 2026-11-15 23:54. 3.3c built. The stage words a hosted list's code calls are answered from the request's own
  row and query or recorded as its effects, through the bridge host's `hostedWord`, which the
  root's words ask first. The helper sits at the root file's own scope, since the root's function
  is at the 200 locals Lua allows and one more refused to compile. Measuring Emoji before the trial
  found every keystroke sending all 5648 rows, 0.9 MB, since a hosted row was keyed by its item's
  table and a glyph is a string. A hosted row is keyed now by the key it states, else by a plain
  item's value, and a keystroke sends 56 bytes, the first open still sending them all once. Emoji
  and Browser Tabs join `hosts`. Not yet tried live.
- 2026-11-16 11:05. Milos's 3.3c trial passed for Emoji and Browser Tabs open and select. In the
  Browser Tabs rework he found Hyper and O in the app's launcher opening Obsidian. The app's launcher
  was never a list Lua counted open, since only the serves share's tools were, so none of its keys
  reached it. Brought forward from 3.4 for the launcher: the bridge counts the socket's launcher
  open while the app says it is up, and a hosted list on top of it, `hostedTop` in the serve side,
  has its own context's keys live, posted to the launcher, whose stage runs them on the level on
  top. A hosted list is asked apart from served, `hosting`, since counting it served first sent
  the actions pane's own calls into the tool, its choices among them, to the app as keys. The rest
  of 3.4 stands, a tool's own verbs on its chords still reach only the shared ones the app's stage
  knows.
- 2026-11-16 11:54. 3.3c ticked, Milos's trial good, Emoji and Browser Tabs inside the app's launcher,
  and the round above with them, Hyper and O on a hosted list, the icons and the Browsers checkboxes.
  The shadow log stood at 77 lines and no difference. Found on the way and not fixed, an open
  problem: restarting Olm.app while Hammerspoon runs left the bridge connected, dropped a second
  later and never connected again, so the app's launcher showed no row at all, and a Hammerspoon
  reload alone did not bring it back while the app kept that session. Restarting the app and then
  reloading Hammerspoon did. It predates this round, and it matters before 3.5's flip, when the app
  answers Hyper and Space.
  Corrected 2026-11-16 12:06, the cause was not a restart, see the entry of that time.
- 2026-11-16 12:06. The bridge that never reconnected, corrected. Restarting the app was not the cause, a restart
  read again reconnected within the second. `test/bridgecheck.sh` was, run as one of the gates before
  the merge while Olm.app listened. It stands in for the app on the same socket path, so it removed the
  app's file, bound its own, took Hammerspoon's connection, and removed its file as it ended, which left
  the app listening on a path nobody could reach. That was the "went", "connected", "went" of 11:05:17,
  and why a Hammerspoon reload did not help and an app restart did. The live check's header said to
  relaunch the app afterwards, and it was run as if it were offline. Fixed in the app, Milos's go: the
  listener watches its run folder and binds again a quarter second after its file is gone, leaving the
  path to a program that bound its own meanwhile and taking it back once that one's file goes, so the
  live check can run beside the app. The launcher a person opens with no session shows a status row,
  Hammerspoon is not connected, and asks again at each query. The live check says it stands in for the
  app and is no offline gate. `olm-bridge-check` 115 checks, the five on the file going failing with
  the watch taken out.
- 2026-11-16 15:52. 3.3d built, Speed Test's preview pane in the app, Milos's go. The plugin is
  unchanged. The bridge is one more drawing backend of `lib/previewpane.lua`, sending what the pane
  drew as `paneDrawn`, a styled text as a Text, a picture as a cached file path, a colour as its
  values, and a router per plugin picks it while the app shows that plugin's list hosted and the
  backend the root chose before otherwise, which needed the pane grant made per plugin. The app tells
  the level `positioned` and `highlight`, draws the elements in the pane view the file search pane
  uses, and drops a drawing made for a highlight it has since left. A stage word asked outside any
  request answers the app's highlighted row, the open question 3.3c left, which Speed Test's ticks
  read. Found while building: a list pushed over the launcher kept the launcher's placement, so a
  hosted list with a pane had nowhere to draw it, and the window is now placed again on a push and a
  pop when the pane changes. Not sent, against the first draft: `scrolled`, since under a native
  scroll the Lua view's offset is always zero, and the empty form of `paneDrawn`, the Lua pane's
  empty state crossing as elements like any paint. Checked live with screenshots: the trend, a
  finished run with its curves and arrows, a run drawn live as it ticked, the trend after it ended
  and the actions pane over a run. Also found live, a rebuilt row keeping its key with a new item was
  never told to the pane again, which the Lua chooser's refresh does, fixed and pinned.
  `bridgeserve.lua` 125 checks, `olm-bridge-check` 128, units 2167.
- 2026-11-16 15:52. A screen drive went wrong. While checking 3.3d live, a Delete, a typed word and
  Return went into Milos's own Claude Code pane, since the app's launcher had closed between two of
  my keys while he was typing. The drive now checks before every key that the bridge says the
  launcher is up and stops otherwise.
- 2026-11-16 15:59. Status was out of date. It said Planned, while the plan's Progress section
  shows stages 0 to 2 done, file search served by the app since the flip of 2026-11-12, and stage 3
  under way with 3.1 and 3.2 ticked, and Caffeinate, Volume and 3.3a to 3.3c ticked under 3.3, and 3.3d waiting on Milos's trial. Status now
  says so, and Now gained what is true today, which list the app serves and on which key its
  launcher runs. Found by an audit against the repo on 2026-11-16.
- 2026-11-16 16:09. 3.3d ticked, Milos's trial good. The shadow log stood at 82 lines and no
  difference. Open: once, leaving Speed Test with Backspace while a run was going and coming back
  showed an empty pane. Not seen again in his trial, and not reproduced in two tries of mine, the
  second stopped by the guard before any key since the list had closed. The likeliest cause, not
  confirmed, is a Speed Test paint landing in a moment the app said its list was not up, which the
  pane router then draws through Hammerspoon's own backend.
- 2026-11-17 11:05. 3.3e built on Milos's go. File Search's launcher row and its typed word open
  the app's own file search, answered `native` over the bridge, since the app has served File
  Search since 1.5's flip and a Lua list of it inside the app would be the old one. A typed word
  that hands its list over, `/ ` or `st `, now crosses as the launcher's `handOver`, which the Lua
  launcher dropped because its own hand over runs only while it is on screen. The app stage keeps
  the word in the field as the level's prefix, as the Lua stage does. Rejected: running the Lua
  hand over and recording its push, since the push lands on the hidden Lua stage and not on the
  app's.
- 2026-11-17 11:55. 3.3e ticked, Milos's trial good, after one finding: File Search's empty field
  had no placeholder, on its own key as well, since the plugin's default is empty and the config set
  none. The config now says Search files and folders. That closes 3.3. 3.4 is next.
- 2026-11-17 12:40. 3.4 built on Milos's go. Its design note found most of it already done, by 1.4f,
  3.3c and 3.3, and one gap left: File Search pushed over the launcher since 3.3e kept the launcher
  told up, so File Search's Hyper keys were never bound and some fell through to their global
  meaning, Hyper and F opening its app and Hyper and U Tmux Sessions. The app stage now tells a
  served tool's list up while it is pushed on top. A hosted Lua level keeps the launcher up, since
  its keys already go through it.
- 2026-11-17 16:15. 3.4 ticked, Milos's trial good, after Piece B of the trial note: the preview pane
  in a pushed list lands before the window finishes widening and fades in over `paneContent`, which
  he found better, with a slight stutter left. The shadow log stood at 86 lines and no difference.
  The stutter left is the window server drawing the glass and its shadow at each new size, which the
  2026-11-06 12:55 entry of `olm-swift-chooser.md` measured and Milos judged good then. A proposal
  of mine the same hour, drawing the window at full width and revealing the pane's region, is the
  mask over glass that file rejected on 2026-11-06 10:55, so it was withdrawn before a note was
  written. 3.5 is next.
- 2026-11-17 17:42. 3.5 built on Milos's go, as its design note proposed. Hyper and Space opens
  Olm.app's launcher while the bridge's socket is up and the Lua launcher otherwise, asked at every
  press, and the fallback never starts the app, so quitting it is the back out. The launcher is
  not added to `serves`, since that share also warms a list and names what the launcher hands over
  natively, so the bridge answers `launcherOpen` and compose swaps that run in. The trial key Hyper
  and 0 was removed from this machine's keys file. Checked live, the app's launcher, its close on
  the same key, and the Lua launcher with the app quit. The app's launcher's keystroke timings were
  recorded for the first time, echo 23 to 45 ms and rows 66 to 112 ms, and its key to list and
  Return to app times are still not recorded.
- 2026-11-17 18:50. 3.5 held off on Milos's trial. Clipboard History did nothing when chosen in the app's
  launcher, since a row leading to a tool not in `hosts` answers `unserved`, held in place by design
  since 3.2. My design note for 3.5 missed that the flip makes every such row dead, Clipboard
  History, Menu Search, Display Profiles, Workspaces, Obsidian, Processes and Olm's own pages among
  them, a feature loss the plan's rules forbid. Milos chose to hold the flip: it stays built behind
  `launcherFlip` in `config/plugins.lua`, false, and Hyper and 0 is back. Rejected: closing the
  app's launcher to open the tool's Lua list, the close and reopen the rules forbid. The flip goes
  on again once no launcher row answers `unserved`. A Quit Olm App row was added on his ask.
- 2026-11-17 20:02. 3.6 built on Milos's go to complete the phase. The rows that still answered
  `unserved` were found by asking the live launcher what Return on each row would do in the app,
  with nothing on screen, rather than from the list in the 18:50 entry. That list was close but not
  exact. Menu Search has no launcher row, its `m ` rows already run. Text Case, Olm Keys, Olm
  Aliases and the Dock's `d ` switches were missing from it. Each of the ten tools was then pushed as
  a hosted level inside the running bridge and asked for its rows. All answered, so they joined
  `hosts` with nothing grown. Olm Aliases and the Dock's switches are rows that change the list in
  place without showing another, so the launcher now answers them `setQuery` and `rows`, effects the
  app already applied. Rejected: renaming the Olm Keys page away from `launcher` so `hosts` reads
  better, since the page carries the launcher's name for its icons and its keys, and a host named
  `launcher` costs nothing.

### 2026-11-18 08:45, the info icon white in Olm.app's bar on a light screen

Milos saw the info icon beside ⌘? white under Hyper and 0 while the words around it followed the
light half. The bridge draws that picture once at load in the foreground of that moment, the share
of 20:02 the evening before, and the bar recoloured a one colour picture only when its item was lit,
so the app kept the half it was drawn in. The bar now draws it in the text colour at rest too,
`Bar.swift`, which in Hammerspoon's own panel is the colour it was already drawn in.

### 2026-11-18 10:03, one look for every picture and word, step 3.7

Milos tried 3.6 good, and of the white info icon said no such isolated case should be allowed,
every icon and font must follow one global set. The survey found the hole is the ink's rule, a one
colour picture recoloured only on the highlight, which leaves every picture drawn ahead of time in
the half it was drawn in, the actions pane's icons in the app as well. It also found the symbol
weight written in three places and no check over the Swift files. Step 3.7's note in
`docs/DESIGN-APP-HOSTED.md` has the fix. Patching each icon as it is found was turned down, since
that is the isolated case he named.


### 2026-11-18 11:31, step 3.7 built

`Ink.icon` is never nil, the text colour at rest and the lit text on a solid highlight, and the
list, the floating panes and the bar all redraw a one colour picture in it, so the bar's own case
from `378d4d12` is the shared rule again. The symbol weight is `stroke.symbol` in
`lib/ui/style.lua`, handed to the sf source through the root and to the swift list and Olm.app as
the style's `symbolWeight`. A key cap's symbol takes the key cap font's weight, read from the font's
traits. The weight joined the sf source's file names, `w0.3` where `semibold` was, so every symbol
is drawn once more on the first load after the change, one background run. `test/drygate-swiftlook.lua`
refuses a font built by hand, a colour literal and a weight in the Swift files outside the readers.
Its first run found eight lines. InputField's defaults now come from `Style`, and the masks in
`Motion.swift` and `Surface.swift` and the emoji canvas in `Stage.swift` carry `look-exempt`.
`test/swiftpane.swift` pins a picture drawn white coming out in the text colour at rest in the
list, the floating pane and the bar, and a picture not marked one colour keeping its own.

### 2026-11-18 14:41, a light and dark switch while the list is up

Milos found that switching macOS between light and dark while Olm.app's list was up left the
text and icons on the half it opened on while the glass and the panes followed. Both hosts read
the half only at an open, `Look.style()` in the app and `Engine:_selectTheme` in Hammerspoon,
which the picker contract stated as a choice. The shared native panel now watches
`NSApp.effectiveAppearance` and asks `appearance` while it is up. The app's stage applies the new
half's style, pane tokens and row symbols and draws the preview pane again, and Hammerspoon's
engine answers through `Engine:followAppearance`, reselecting the theme, restyling and telling the
highlight again. One watch in the panel both hosts share, rather than one per host.
`test/swiftview.lua` pins the restyle in place with the highlight kept. The canvas provider, which
serves only as the fallback, has no such watch yet.

### 2026-11-18 15:10, step 3.5's flip on again

`launcherFlip` is true again in `config/plugins.lua`, so Hyper and Space opens Olm.app's
launcher while its socket is up and the Lua launcher otherwise, and Hyper and 0 is gone. It was
held off on 2026-11-17 because rows leading to tools the app did not show did nothing. 3.6 showed
every such tool and Milos tried it good on 2026-11-18, and 3.7 gave the app one look, tried good
the same day. The shadow log stood at 101 lines and no difference. Setting it false is the way back.

### 2026-11-18 15:32, step 3.5 ticked, stage 3 done

Milos tried Hyper and Space on Olm.app's launcher and called it good, so 3.5 is ticked and stage 3
is done. He found the Quit Olm App row's eject mark wrong, and it now wears `xmark.circle`, the
mark Processes quits an app with.

### 2026-11-18 17:04, the resting point checked, and stage 3 not done after all

Checking the five conditions of the resting point found the first one false. Every tool's own key
still opened Hammerspoon's list, since 3.6 built the launcher's rows only while its line in the
plan named a tool's own chord. The entry at 14:41 above that called stage 3 done was wrong on
that, and step 3.8 is added for the missing half, its design note in
`docs/DESIGN-APP-HOSTED.md`. The route chosen is the one door every plugin already shows its list
through, `stagePresent`, asking the bridge first, rather than swapping each tool's open key the
way `serves` and `launcherOpen` do, so a tool added to `hosts` gets its key in the app with no
further edit. A cycle list stays Hammerspoon's until the app has a bare mode. The second
condition is open too, the app's launcher rows measured at about 82 ms median against about 40 in
the Lua launcher on 2026-11-17, not yet explained.

### 2026-11-18 17:27, step 3.8 built

A tool's own key opens its list in Olm.app. The root's `stagePresent` asks the bridge host's
`presentInApp` first, which takes the list while `keysFlip` is on, the config hosts the tool and
the app's socket is up, and posts `olm://tool?name=<name>`. The app asks `open` for that tool,
which the bridge now serves as the hosted level a launcher row pushes, the only level, and opens
it. The app's own host for it, rather than a field on `olm://launcher`, because the stage reads a
list's manifest as it opens, so the level has to be asked first. The stage's Backspace on an empty
field asks a list with nothing under it for its `back` too, as the Lua stage does. `keysFlip`
ships true, and false is the way back. `test/bridge.lua` 150, `test/bridgeserve.lua` 140,
`olm-bridge-check` 150. `stagePresent` itself has no offline test, and the trial checks it.

### 2026-11-18 17:34, 3.8's trial, Clipboard History's pane drawn in a window of Hammerspoon's

Clipboard History opened by its own key showed its preview pane in a window of Hammerspoon's beside
the app's, which reserved the pane's room and drew nothing there. The bridge host decides whether a
hosted tool's pane, keys and verbs go to the app by asking which list of the app's it sits in,
`_hostOf`, and that knew only the launcher and a served tool. A list opened alone sat in neither, so
the pane went to the Lua backend and its keys stayed in Lua. 3.8 had added a second road into the
app and left the bridge's one rule for which hosted list is up as it was. A hosted list opened alone
is now its own host, so the same rule answers it as it answers one inside the launcher, and
`test/bridge.lua` pins it.

### 2026-11-18 17:48, 3.8's trial, a list opened by its own key took no Hyper key

Hyper and J, K and O did nothing in Clipboard History opened by its own key. A list key reaches the
app through the root's surface adapter and `servedOpen`, which asked only whether the app shows a
tool's own list, a served one or the launcher. A hosted list was left to the Lua stage, which shows
nothing. Inside the launcher that never showed, since the launcher's own keys answered first. Both
now ask `listopen.inApp`, served or hosted, and the bridge's verb sends a hosted list's key to the
list it sits in, the launcher or itself. `test/rootmechanism.lua` pins it.

### 2026-11-18 17:59, 3.8's trial, Manage History did not change its page in the app

Clipboard History's Manage History changes its page through three stage words, the placeholder,
the field's text and a redraw. The protocol has said since 3.3c that every stage word crosses to
the app inside a request and outside one alike, and only the redraw was built. `setPlaceholder`
was neither recorded nor applied, and outside a request `setQuery` and `hide` stayed on the Lua
stage. Now all three cross to the hosted level on top either way, the app applies `setPlaceholder`
and the effects notification carries every effect, and a placeholder set while a tool's own key is
still opening its list goes with that list's `open`. Inside the launcher it was the same gap, unseen
because nobody had opened Manage History there. `test/bridge.lua` 164, `test/bridgeserve.lua` 142,
`olm-bridge-check` 152.

### 2026-11-18 18:20, 3.8's trial, Hyper and M did nothing, and a hosted action could go round

Hyper and M, Manage History, did nothing in Clipboard History opened by its key. Two faults. The
app ran a list verb only when the list named it among its actions, and Manage History is a page and
no action, so the app dropped it. And since ea3edb92 the adapter that runs a hosted list's action in
Lua, asked by the app's `run`, saw the list in the app and sent the action back to it as a verb, a
road that could go round. The app now hands a hosted list every verb it does not run itself,
`runsEveryVerb`, and the root's hosted `run` closes the adapter's road to the app while it runs, so
the tool's own code answers on the app's row.

### 2026-11-18 19:17, step 3.8 ticked

Milos tried every step of 3.8 and called it good, every tool's own key opening its list in the app,
Hammerspoon's list after quitting the app, and a list opened over a password field in Safari taking
typing in the app. So a list opened over a secure field needs no exception. Left before the resting
point, Input Sources' cycle, which the app cannot show bare yet, and the timings of its second condition.

### 2026-11-18 19:27, a row's own picture reaches the app

Milos reported image rows in Clipboard History drawn with no icon in Olm.app. The protocol has had a
row `picture` since it was written, but the bridge's rows never sent one and the app never read it,
so every row whose only icon was an `hs.image`, a clipboard thumbnail, a file type's icon and a
colour chip alike, crossed with none. The rows now send it through the same `pictureOf` the preview
pane uses, and the app draws it as `Icon.picture`, keeping its own colours. It crosses only where
the row names no icon the app resolves itself, since every launcher app row also carries its icon
as a picture and encoding those would write hundreds of files for nothing.

### 2026-11-19 20:50, step 3.9, Input Sources' cycle in the app

Built on Milos's go. The cycle key asks the bridge first as every tool key has since 3.8, and the
app shows the list bare through the panel's existing bare posture, laid out as the Lua engine's
`_shapedLayout`, with the idle completion, the hand move that stops it and the keys its own. A
further press takes the list verb road as `cycleStep` rather than a new socket notification, since
that road already reaches the stage's own highlight, and a press heard while the list is still
opening is owed and taken when the rows land. A key typed over it is posted again by Hammerspoon
after the app says `hidden`, since Olm.app holds no Accessibility grant to post one, and a hosted
level learned to say `hidden`, which only the launcher's did. The idle is the Lua stage's
`CYCLE_IDLE`, now published and sent with the level, so the two cycles share one number.

### 2026-11-19 20:55, step 3.9 ticked

Milos tried all six steps of 3.9 and called it good, one tap, fast taps, an arrow then Return,
Escape, a letter typed straight after the taps landing in the new layout, and Hammerspoon's bare
list once the app was quit. Every list a person opens is now drawn by Olm.app while it runs. Left
before the resting point, the timings its second condition asks for.

### 2026-11-19 21:50, Olm Settings as a window of the app

Milos asked, while the timings record, for one Olm Settings entry replacing the four launcher rows,
opened by ⌘, from any Olm window as a real window, a sidebar with search and native controls, its
values saved on this Mac over the config files. The 2026-10-27 split of the Olm Settings plugin
does not stand against it, since that was a list opening as a second window and this is a window
opened as one. Olm Keys stays its own row, the 2026-10-21 decision. Hammerspoon declares and applies
every setting and the app draws the window, the line this session drew. `docs/DESIGN-APP-SETTINGS.md`.

### 2026-11-20 00:37, Olm Settings S.1, the store and the declarations

Milos said go with no trim, so the whole table stands and a reload setting applies when the window
closes. Built `lib/settings.lua` and one store, `~/.olm/state/settings.json`, which takes over the
five keys Hammerspoon's own settings held, moved once and removed there. A saved value is laid over
the policy, the typography, the icons and the stage as each loads, so no reader changed, and the
share `settings.json` is written at load. Window Management was first declared in the library, and
the dry gate refused it, since core may not name the window manager, and the rename proof showed the
overlay making an empty `windowSizing` group in its data. Both were right. The overlay no longer
makes a group a file leaves out, and the window manager declares its own settings through its
manifest in S.4. The icon sources' names and the kit's font names were refused the same way, so the
sources carry a title and the kit answers its shipped typography. On this Mac none of the five keys
was set, so the first load moves nothing.

### 2026-11-20 01:17, Olm Settings S.2, the window read only

Milos tried S.1 and said go. The window is SwiftUI in an NSWindow, in a module of its own,
`OlmSettings`, since a sidebar, a search and a grouped form of system controls is what SwiftUI draws
as System Settings does, and the chooser's look is not wanted here. `@State` does not build with the
command line tools, which ship no SwiftUI macro plugins, so the window owns an `ObservableObject`.
The launcher row is the bridge host's own action, not a plugin's, since the bridge is the host that
opens the app, and it is shown wherever the app is built, starting it when it is not running.

### 2026-11-20 09:14, Olm Settings S.2 trial, three faults and the corrected belief about the app's look

Milos found the window in the look from before Liquid Glass, opened behind the app in front, and
missing from Command Tab. The belief that Olm.app drew with the running system's look was wrong.
Its binary recorded SDK 14.0, the deployment target, because the build named no SDK, and macOS draws
an app linked against an SDK older than 26 in the old look, every window of it, the list panels
included. The build now passes `SDKROOT` and records SDK 27, beside Hammerspoon's 26. The window is
built on glass, with each glass falling back to the regular material before macOS 26. Olm Settings
is always handed to `open` in the foreground rather than told by notification, since a notified app
can only ask to come forward and the app in front declines. While the window is open the app is a
regular app with a Dock icon, Command Tab and a menu bar, and an accessory again once it closes.

### 2026-11-20 10:02, Olm Settings layout after the glass trial

Milos asked for a larger window, a wider sidebar, the search nearer the top with the app's name and
version beside it in the style of System Settings' account row, and no band across the top of the
pane. The window is 1000 by 700 with a 270 point sidebar, the toolbar compact with its background
and separator hidden, and an Olm row with the bundle's version under the search. The frame autosave
name changed, since the saved frame would otherwise keep the old size.

### 2026-11-20 10:34, Olm Settings S.3, changing a setting, and live narrowed to three

The design note listed most settings as live. Reading the readers showed that only the placement,
the theme and the highlight have a word that applies them without a reload. The row limit, the
type, the corners, the paddings, the motion, the hold delay and the fn cycle's wait are all copied
as Olm loads, into list configs, the look's tokens, the leaders and the app's serve. Making each
live would mean a rebuild path per reader, so they declare reload instead, and the window reloads
once when it closes if any of them changed. A change goes over the bridge as `setting`, checked and
saved by `lib/settings.lua`'s `change`, and is answered with the whole share so the window draws
what Hammerspoon holds. Olm.app gained its icon, drawn by a script and committed as `app/Olm.icns`,
since the build has no Xcode to compile an asset catalogue, and the window opens centred under the
pointer.

**2026-11-20 11:57, the settings sidebar width set on AppKit's split view.** The belief at 10:34,
that `navigationSplitViewColumnWidth(min: 300, ideal: 320)` gives a 320 point sidebar, was wrong.
Milos's screenshot showed about 140 points, the same as before the 270 and 320 changes, so the
modifier is not honoured in a window made by hand around an `NSHostingController`, and no saved
split position was to blame, since the app's defaults hold only window frames. The window now
finds the `NSSplitView` after it is shown, gives its first item 300 to 400 points when a split view
controller owns it, and moves the divider to 320 when the sidebar is narrower, logging the width.

**2026-11-20 12:26, the settings sidebar a fixed 480 points on AppKit's own split, and one gap
round the page.** The 11:57 fix, forcing a width onto the split view NavigationSplitView builds,
was wrong too. Milos found it flickered as the window resized, since SwiftUI kept laying the column
out again, and that dragging the divider left collapsed the sidebar. He asked for a 480 point
sidebar that does not resize. The window's content is now an `NSSplitViewController` of two
hosting controllers, the sidebar a sidebar item, so it is glass on macOS 26, with 480 as both its
minimum and maximum, no collapse, and a divider that takes no drag. The search moved into the
sidebar as the system's search field, since `.searchable` lives with NavigationSplitView. The page
in the pane was 28 points from the left but about 52 from the top and capped at 820 wide, and Milos
asked for one gap on all four sides, so it is 28 everywhere, measured from the window's top edge.

**2026-11-20 12:51, the settings sidebar 280 points, and no toolbar.** Milos asked for 280 rather
than 480, so the sidebar stays fixed and undraggable at 280 and the window opens at 1100 by 740
again. With the pointer at the top of the pane the empty toolbar drew a band with a line under it
over the page, so the window has no toolbar now, its title bar see-through and without a separator,
and the page still meets the window's top edge.

**2026-11-20 13:30, the settings sidebar drawn by Olm as a floating glass panel.** AppKit's sidebar
split from 12:26 drew the sidebar flat grey, with no glass, and Milos asked for the glass back. The
window is now one SwiftUI view with no split view of any kind: the wash fills the whole window and
the sidebar is a 280 point panel over it, `glassEffect` on a rounded rectangle inset 8 points from
the window's edges, with the window's buttons sitting on it as System Settings draws on macOS 26.
The search is a glass capsule of its own. Since the width is the panel's frame, it cannot be
dragged, collapse or flicker, which closes the two split view attempts.

**2026-11-20 13:42, the settings sidebar back to the system's own, since macOS 27 left the floating
glass panel.** The 13:30 entry was built on a wrong belief, that the floating Liquid Glass sidebar
of macOS 26 is how a sidebar looks on this machine. This machine runs macOS 27, which abandoned that
panel, and the flat sidebar AppKit's sidebar split drew at 12:51 was the system's own look rather
than a fault. Milos asked for it back, so the window is again an `NSSplitViewController` with a
fixed 280 point sidebar item, no drag, no collapse and no toolbar, as at 12:51. Rejected for good:
a sidebar Olm draws itself as a glass panel, since it copies a look the running system dropped
instead of taking whatever the system draws.

**2026-11-20 13:58, S.4 of Olm Settings, ⌘, and one way in.** ⌘, opens Olm Settings from every list,
as a list key of Olm's own all layer beside the info pane's, so both the Lua lists and Olm.app's
take it with no code per list, and it is reserved, refused in the keymap's lists section and in a
manifest's surface. The four launcher rows Olm Chooser, Olm Placement, Olm Theme and Olm Plugins are
removed and their lists kept, opened only by a key a person gives their open action, since a
machine without Olm.app has no window and still needs a way to change these. A manifest may now
declare `settings`, read by `lib/settings.lua`'s `fromManifest`, and the window manager declares its
steps and sizes there, laid over its own data before configure, which is how a plugin's setting
reaches the window without the core naming the plugin. Considered and not taken: declaring the
window manager's settings in `lib/settings.lua`, refused because the dry gate fails any file outside
plugins that names a plugin.

**2026-11-20 14:29, the four launcher rows actually removed, and the settings window opens built.** The 13:58
entry said the rows Olm Chooser, Olm Placement, Olm Theme and Olm Plugins were removed, and they
were not. The script that edited the four manifests built the change and then wrote back the file
it started from, so only a comment moved, and the gates passed because nothing they check names
those rows. Milos found them still in the launcher. They are removed now, and the launcher goldens
lose exactly those four rows. Milos also found the window slow to open and flickering. Each
NSHostingController sized the window once SwiftUI had measured its views, after the window was up,
so both now have no sizing options, and the app builds the window hidden two seconds after it
starts, so the first open shows a window already laid out. The search is a Liquid Glass capsule 36
points tall above the sections, and the window has an empty unified toolbar over a see-through
title bar, as Finder has, so the buttons sit lower and further in, with the search and the app's
row starting where the close button does, read off the window.

**2026-11-20 14:38, the settings window on one spacing scale with no layout shift.** Milos found the sidebar's
highlights out of line with the search and badly spaced, the pane blue though he never asked for it,
and the line about applying on close pushing the card down when it appeared. The window now takes
every gap from five tokens, edge, group, pad, related and row, written in the design's Layout section
with the rules for no layout shift. The sidebar draws its own rows, since a sidebar List places its
highlight and symbols where the system decides and they did not line up with anything else, the
accent wash is gone, and the note sits in a fixed slot at the header's right. Rejected: keeping
List for the sections, since its insets cannot be set to match the search and the window's buttons.

**2026-11-20 14:51, Command and comma in Olm.app's lists opens the window through LaunchServices.** Milos found
that Command and comma in the launcher closed it and showed no window. In a list Olm.app draws, the
verb hid the list and showed the window from inside the app, but the panel never makes the app
active, and since macOS 14 an app may only ask to come forward, so the window opened behind the app
in front. It is the S.2 fault again, and it has the S.2 answer: the app hands olm://settings to
LaunchServices with activates set, the same route Hammerspoon's Olm Settings row takes with open.

**2026-11-20 15:33, the resting point called reached.** Milos asked why wait for days of timings when the Lua Olm
works in full and the app is the thing being built, and called it reached. The timings since
2026-11-19 19:55 UTC hold 62 opens of the app's launcher and 233 keystrokes. A key reaches the field
in 26 ms median and 62 at the 95th, whatever the rows do, so typing never waits on Hammerspoon. Rows
come in 73 ms median and 133 at the 95th, a round trip to Hammerspoon, which computes the launcher's
rows until stage 4 moves the catalog. The belief that the app's rows took about 82 ms against about
40 ms in the Lua launcher compared unlike lists, since every Lua sample is of another list, input
sources and the calculator, and none is of the launcher. Left as follow ups and not conditions: file
search's rows at 171 ms median from one open, and a main thread stall of 57 ms median once an open,
the app's own. Recording is switched off by removing ~/.olm/run/timings.

**2026-11-20 15:50, external plugins, a process each, run by the app.** After the resting point Milos settled the
end state, Hammerspoon out of the picture entirely, the core built into the app in Swift, and every
other plugin, display profiles, tmux sessions, VPN and the like, an external plugin anyone can write
and install without a build of Olm, ours in Swift as well, and Claude able to develop one in any
folder. He asked that plugins never clog the app and how they are run. The design note is
`docs/DESIGN-APP-PLUGINS.md` in the spoon. A runner actor inside the app starts one process per
plugin and speaks the bridge protocol to it over its pipes, every request to a budget, a plugin
that breaks one killed and one that keeps failing switched off, started only when needed and at a
lower priority than the app. Swift source is compiled on install with the command line tools.
Rejected there: a plugin in the app's own process in any form, one host process for every plugin,
and a socket per plugin. It answers the plan's open question 3 for our own plugins, Swift, with
JavaScriptCore kept for later. It waits on Milos's go.

**2026-11-20 16:10, external plugins sandboxed, asked once, Swift only for now.** Milos wanted plugins sandboxed
rather than run directly, asked whether that still lets a plugin run caffeinate, mullvad and the
IVPN command, and asked that it not be too limiting and that switching a plugin on ask for its
permissions at once. Tinycast, which he named, runs its extensions in JavaScriptCore inside the app
with no sandbox, trusting them once extensions are switched on, which is rejected here. Each plugin
now runs under macOS's sandbox engine with rules written from its manifest, in four groups a person
reads, programs, files, network and services, the programs a plugin runs sandboxed with it so the
services they use are asked for too. Files are granted as whole places a person recognises. One
sheet at install or switching on asks once, an update shows only what is new, our own plugins are
allowed by their install, and a block in use is offered as one line with Allow, the same denial
line that tells an author what to declare. Apple's App Sandbox was rejected, since it stops a plugin
running tools like tmux or mullvad at all. The sandbox's rule language is deprecated and the
disclaim flag private, so step 1 proves both here before anything leans on them. Swift is the one
language at first, other languages a later step.

**2026-11-20 16:15, the route to Olm alone written into the plan.** Milos asked for the plan written down. Stages 4
to 6 of `docs/PLAN-STANDALONE.md`, plugins native, keys and the system plugins, all optional, are
replaced by five stages and a checklist: 4 the plugin runner, the design note's steps with keep awake
as the first external plugin, 5 keys as before with the key daemon optional since kanata can keep
remapping, 6 the core in the app one plugin per step with the launcher's catalog first, 7 our
external plugins one per step with display profiles first, and 8 Olm alone, the first run,
Hammerspoon switched off, signing, and where Olm lives asked again. Open question 3 is answered,
Swift at first in a sandboxed process. The order may change a step at a time.

**2026-11-20 17:25, step 4.1 built, the sandbox and the disclaim proved on macOS 27.0.1.** Milos said
go. A probe ran a child under `sandbox-exec` with written rules, and caffeinate and `mullvad status`
ran while an undeclared program, `~/.zshrc`, `~/Documents` and the internet were refused. The
disclaim flag works: without it the child read the Accessibility grant of the program that started
it, with it none. `app/Sources/OlmPlugins` holds the runner, a plugin process each, and
`ExternalSource`, which is the bridge's own hosted level over a new `LevelPeer`, so a plugin and
Hammerspoon read the protocol one way. `test/olmplugins.sh` checks 40 things against a plugin
built to misbehave, and the main thread stayed within 5 ms at p99 through all of it.

Three beliefs were corrected while building it. The `ping` the design planned for a stuck plugin
was dropped for a cancel and a grace, since a plugin answering pings on one thread while another
spins would never be caught. A processor cap was added, a core kept 90 percent busy for 10 s, since
a plugin spinning in the background breaks no request's limit, and the first version of that cap
never fired, because readings were dropped at exactly the window's age and none was ever old
enough to judge by. And Foundation's `resolvingSymlinksInPath` strips `/private`, so rules written
from it named `/var/run/mullvad-vpn` while the sandbox matches `/private/var/run/mullvad-vpn`, and
mullvad was refused its daemon until every path went through `realpath`.
