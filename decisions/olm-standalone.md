# Olm as an app of its own

Status. Planned. Olm moves to a native macOS app in small steps beside Hammerspoon, file search
first as a pilot, to a resting point where the app owns every list and reaches Hammerspoon as a
dependency, by `dotfiles/hammerspoon/.hammerspoon/Spoons/Olm.spoon/docs/PLAN-STANDALONE.md`, whose
Progress section is the one record of which steps are done.

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
list, and until then that list stays on Lua.

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
