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
