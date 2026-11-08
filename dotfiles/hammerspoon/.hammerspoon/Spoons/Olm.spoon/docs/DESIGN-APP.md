# Design, the structure of Olm.app

Written 2026-11-08, at Milos's request, before step 1.4 of `docs/PLAN-STANDALONE.md` adds most of
file search to the app. The plan says how Olm moves into the app one step at a time. This says what
the app is built as, so every step lands in the same structure rather than in a file that grows.
The plan's rules hold here unchanged, and the decision record is `decisions/olm-standalone.md` at
the repository root.

Today the app is a pilot. `app/Sources/Olm/main.swift` holds the URL handling, the file search
list and its key handling in one class, and that was right for proving the path. It is not what
the plan's later steps can stand on, since every list after file search would grow the same class.

## What carries over from the Lua Olm, and why

The Lua Olm's structure is the thing that works best about it, and the app keeps every part of it
that is a principle rather than a workaround for Lua.

1. **A composition root names every concrete piece.** `root/compose.lua` builds the hosts, the
   registry and the plugins and wires them, and nothing else constructs anything. The app has one
   too, and it is the only file that names a concrete plugin.
2. **A plugin is handed its whole world.** A Lua plugin receives everything through
   `configure(opts)` and reaches nothing else, never `spoon.Olm`, never a lib by path. A Swift
   plugin is handed a context the same way, and there is no global it could reach instead.
3. **A manifest is data.** It says what the plugin is, what it needs and what it offers, and it can
   be read without running the plugin, which is what lets the root order and validate everything
   before anything starts.
4. **A plugin never draws.** It answers rows, a preview description and actions, and the core
   shows them with the one look, the one motion and the one search. That is why every list feels
   like the same instrument, and the app keeps it.
5. **One owner per responsibility,** rule 1 of the plan, for every store, key and list.
6. **Behaviour is pinned by fixtures** both languages run, rule 4 of the plan.

## What Swift lets the app do better

Each of these replaces something the Lua Olm can only check by a gate, a convention or a report at
load, with something the compiler refuses.

1. **Boundaries are module boundaries.** A plugin is its own Swift module that depends on
   `OlmKit` alone, the vocabulary below. It cannot import the panel, the stage or another plugin,
   so "a plugin never draws" and "a plugin never reaches another plugin" stop being dry gate rules
   and become imports that do not compile. `test/drygate-surfaces.lua` has no Swift counterpart to
   write.
2. **The contract is a protocol.** A Lua presentation is a table of member specs, `{ member, call
   = "dot" }`, checked at load, and a wrong one fails quietly on a keystroke. A Swift plugin
   conforms to a protocol and a missing or misspelt member is a build error.
3. **Threads are checked.** The app builds in Swift 6 language mode with strict concurrency. The
   panel, the input field, the highlight and the stage are `@MainActor`, each plugin's work runs on
   its own actor, and a call that would put plugin work on the main thread does not compile. Rule
   8 of the plan, typing never waits, is enforced where it can be and measured where it cannot.
4. **A slow plugin holds only itself.** In the Lua Olm everything shares Hammerspoon's one thread.
   In the app a plugin that takes a second to answer leaves typing, the highlight and every other
   list live, and its late answer is dropped by its generation.
5. **An extension cannot take the app down.** Code someone else wrote runs in a process of its
   own, so a crash there closes one list, never the launcher.
6. **Stage words become effects.** A Lua plugin changes the list it stands on by calling stage
   words. A Swift plugin returns effects, the same list the bridge protocol already defines, so the
   stage has one place that applies them, whoever answered.

## The layers

Each layer depends only on the layers above it in this list. The package's target graph is this
list, so a dependency the other way does not build.

1. **`OlmKit`, the vocabulary.** Value types with no AppKit and no behaviour: `Row`, `Text` with
   its runs, `Icon`, `Picture`, `Chord` and its key names, the eight colour roles and the five
   typography roles by name, `Level`, `Effect`, `Action`, `Preview`, and the manifest types. They
   are the bridge protocol's shapes, `docs/PROTOCOL-BRIDGE.md`, written once as Swift types, so a
   row from a native plugin and a row from the bridge are the same value. Everything is `Sendable`.
2. **`OlmSearch`, the search.** The matcher and the ranking, ported from `match.lua` and
   `rank.lua` and checked by the rank fixtures, plus file search's grammar and index today. The
   grammar and the index move into the file search plugin at 1.3g, since they are file search's
   own and not shared, and what stays is the search every list ranks with.
3. **`OlmLook`, the look.** The geometry port today, pinned by its fixture, and the reading of
   `~/.olm/run/chooser.json`. In a later stage it owns the theme and the typography outright, as
   `lib/ui` does now, and only then does the app stop being handed the look.
4. **`OlmChooser`, the panel.** The swift chooser's own panel, the same sources Hammerspoon
   compiles, `lib/chooser/providers/swift/native`. It draws and reports events through
   `ChooserSource` and decides nothing. It is shared with Hammerspoon until the resting point, so
   it changes only in ways both sides take.
5. **`OlmCore`, the stage.** The level stack, the query and its generation, the highlight and its
   generation, the authority on both as rule 2 of the bridge protocol says, ranking a level's rows
   with `OlmSearch` on the search actor, applying effects, the Show more row, the registry of
   sources and the catalog the launcher lists. It is the one `ChooserSource` the panel talks to,
   so the panel never meets a plugin.
6. **The sources.** Everything that answers a list, below. Each depends on `OlmKit`, and the
   bridged source on the transport too.
7. **`Olm`, the app.** `main.swift` is the composition root. It reads the config, builds the
   look, the stage and the panel, constructs every source, registers it under its name, and
   answers `olm://` URLs by asking the stage to open a level. Nothing else lives there.

## The source, one protocol for every list

Every list the app shows, whoever computes it, is answered through one protocol in `OlmKit`. It
is the bridge protocol's requests turned into Swift, so its shape is already settled and
reviewed.

```swift
public protocol ListSource: Actor {
  var manifest: Manifest { get }
  func open(_ what: Open, query: String) async throws -> Level
  func rows(level: Level.ID, query: Query) async throws -> RowsAnswer
  func choose(_ pick: Pick) async throws -> [Effect]
  func run(_ action: Action.ID, on pick: Pick, choice: String?) async throws -> [Effect]
  func preview(_ pick: Pick) async throws -> Preview?
  func back(level: Level.ID, query: Query) async throws -> [Effect]
  func close(level: Level.ID) async
}
```

`Query` carries the text and its generation, `Pick` names the row by its key, the query and the
highlight's generation, exactly as `choose` does on the wire, so a source always answers about the
row the person chose and never about one it remembers. A source never sees a keystroke it did not
ask for, never moves the highlight, and never ranks its own rows unless its level says
`ranking: source`, the `matcher = false` of the Lua contract. Every method is cancelled when its
generation is passed, through Swift's own task cancellation, so a source that checks
`Task.isCancelled` stops early and one that does not is dropped on arrival.

Three kinds of source conform to it, and the stage cannot tell them apart.

1. **A native plugin,** a Swift module of its own, built into the app. File search is the first,
   at 1.3g.
2. **The bridged source,** one for all of Hammerspoon. It turns each method into a bridge request
   and each answer back into the same values. Every plugin not yet native is served through it,
   stage 2 and 3 of the plan.
3. **An extension host,** later and only if wanted, which runs extensions someone else wrote in a
   process of its own and answers for them, open question 3 of the plan.

This is what makes the plan's moves small. A plugin going native in stage 4 is a second source
registered under the same name, and the flip is which one the registry hands the stage, one
setting, rule 2 of the plan. The shadow of rule 3 is a fourth conformance, a source wrapping the
native and the bridged one, answering with the bridged one and logging every difference, and it
is written once for every plugin rather than once per plugin.

## A native plugin

A plugin is a folder under `app/Plugins/`, one Swift module named for it, and the package lists it
as a target that depends on `OlmKit` and nothing else of Olm's. It holds the same three parts a Lua
plugin does.

- **The manifest,** a static value of the `Manifest` type: its name, its title, the aliases a
  typed word opens it by, the icons it declares, the actions it offers and the keys it suggests,
  the tools it needs, its settings with their defaults, and whether its level has a preview pane.
  It is Swift rather than JSON so the compiler checks it, and it is read without the plugin
  running, as a Lua manifest is. The fields keep the Lua contract's names, `docs/PLUGIN-CONTRACT.md`,
  wherever the field means the same thing, so a person who knows one knows the other.
- **The source,** an actor conforming to `ListSource`.
- **A `README.md`** in the house shape, and an `AGENTS.md` only where it holds findings.

A plugin is constructed with a `PluginContext` and nothing else. It holds what the Lua `opts`
holds, each one only when the manifest earns it, by the same rule that decides it in Lua, Olm
derives what follows from a declaration rather than asking for it twice.

- `settings`, the plugin's own settings, read from the config, typed.
- `tools`, the resolved path of every tool the manifest needs, the `deps` adapter. A tool not
  declared has no path to ask for.
- `store`, a directory of its own under `~/.olm/state/<plugin>/`, which nothing else writes.
- `recency`, the shared frecency, where the manifest asks for it.
- `notify`, the one way a plugin tells the person something.
- `open`, a word that asks the stage to open another plugin's level by name, which is the only way
  one plugin leads to another.

A plugin's work runs on its own actor. Work that touches the system, opening a file, Quick Look,
the pasteboard, is done through small services `OlmKit` declares and the root provides, so a
plugin is tested with fakes and never imports AppKit to do it.

## The look

The look stays one, rule 9 of the plan. Until a later stage it comes from Hammerspoon,
`~/.olm/run/chooser.json`, and the app reads it through `native/Fields.swift`, the field list
Hammerspoon's panel reads too. A plugin names a colour role and a typography role and never a
colour, a font or a size, as the Lua UI kit rule says, and `OlmKit` has no type that could carry
one. A preview is a description of kit nodes, text, a picture, a table of fields, a code block,
which the core draws, the same split `lib/previewpane.lua` keeps between the pane's lifecycle and
what a plugin hands it.

## Keys

The panel hears every key while a list is open. The stage owns the list keys the keymap names, the
highlight, Return, Command and a digit, Escape, Backspace on an empty field, and hands any other
chord to the source of the level as `key`, as the bridge does. Key names are `lib/kbd.lua`'s, one
vocabulary, and a plugin shows a chord as a `Chord`, never as glyphs. Leader keys stay in
Hammerspoon until stage 5 of the plan.

## Where the app keeps things

- `~/.olm/run/`, what Hammerspoon hands the app, rewritten on every load, never edited by the app.
- `~/.olm/cache/`, what can be rebuilt, the file index, thumbnails, pictures the bridge wrote.
- `~/.olm/state/<owner>/`, what cannot, frecency and each plugin's own store, one owner each, and
  a store whose owner is still Lua is only read by the app, 1.4d of the plan.
- `~/.olm/app/`, the built app.

## Diagnostics

The app logs through `os_log` under the subsystem `local.olm.Olm`, with one category per layer and
one per plugin, so `log stream --predicate 'subsystem == "local.olm.Olm"'` shows what it did. The
root validates every manifest before anything starts and reports each refusal by name, as the Lua
wiring layer does, rather than failing on the first keystroke. The three timings the plan records,
keystroke to drawn rows among them, come from signposts on the stage, so Instruments shows them
with no extra code.

## How it is tested

1. **Fixtures,** the language neutral ones under `test/fixtures/`, run by `olm-fixtures`, for
   everything ported from Lua.
2. **Sources against fakes.** A plugin is handed a fake context and asked through `ListSource`
   alone, so its tests never show a window.
3. **The stage against a fake source,** checking the generations, the highlight held on a key and
   every effect, the same cases the bridge protocol's transcript golden names.
4. **A trial by hand** for anything a person sees, as every plan step has.

The checks stay programs rather than `swift test`, decided at 1.1 of the plan.

## Moving the pilot onto this

Step 1.3g of the plan, after the 1.3d trial and before 1.4a, with no change a person can see.

1. `OlmKit` is made, with the types file search needs today, `Row`, `Icon`, `Level`, `Effect`,
   `Query`, `Pick`, `ListSource` and `Manifest`.
2. `OlmCore` is made with the stage, taking over what `FileSearch` in `main.swift` does for any
   list, the highlight, the slots, Command and a digit, the empty text, the generations, the icon
   cache and the redraw that skips an unchanged answer.
3. File search moves into `app/Plugins/FileSearch/`, its grammar, index and engine with it, as a
   source answering rows, `choose` as open and reveal as an action.
4. `main.swift` becomes the composition root alone.
5. The fixtures, the index check and a trial by hand confirm nothing changed.

After that, each 1.4 step adds to the file search plugin or to the stage, and never to
`main.swift`.

## Turned down

- **Loading compiled Swift plugins while the app runs.** 2026-11-08. Possible through bundles, and
  fragile, since every plugin must match the app's Swift and its own build exactly, macOS signing
  refuses a library it did not see signed, and a fault in one takes the whole app with it. A native
  plugin is built into the app instead, which on this machine is one rerun of
  `src/setup-olmapp.sh`, and a plugin someone else hands over is an extension in a process of its
  own.
- **SwiftUI for the chooser.** 2026-11-08. The panel is the swift chooser's AppKit panel, measured
  and shared with Hammerspoon, and drawing the list a second way would be a second look. SwiftUI
  may still draw a settings window in stage 6, which no list shares.
- **A plugin that reaches the stage or the panel directly.** 2026-11-08. It is the Lua Olm's
  stage words with the facade removed, and it would let a plugin hold chooser state, which the Lua
  contract already refuses. A plugin returns effects.
- **One module for every plugin.** 2026-11-08. It would let one plugin import another's types, the
  coupling the Lua contract refuses through `needs.siblings`. A plugin that needs another's
  capability is handed it by the root through its context.
