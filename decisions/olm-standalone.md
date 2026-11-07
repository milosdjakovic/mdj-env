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
first as language neutral fixtures both sides run.

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

