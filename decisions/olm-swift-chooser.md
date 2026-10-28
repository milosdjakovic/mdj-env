# Olm swift chooser

Status. A third picker provider, `swift`, is built on `olm/swift-provider`, the chooser engine
composed with a native panel Olm compiles itself, chosen by one setting and serving the default
provider until its library is built. It has passed every offline gate and waits for its first
live load, where typing under secure input is still to be measured.

## Now

Hammerspoon stays the engine, and only the interface becomes native. A Swift library is built
on each machine by `lib/swiftbuild.lua`, the build Olm runs itself through `hs.task` and
`swiftc`, with nothing in `setup.sh`. It lands in `~/.olm/cache/swiftchooser/` and is loaded
with `package.loadlib`, into Hammerspoon's own process. It links Hammerspoon's LuaSkin, whose
headers ship inside the app, the same way Hammerspoon's own `libchooser.dylib` does.
`native/bridge.h` is the one place Lua's function like macros are wrapped for Swift.

It is the picker facade's third provider, `swift`, beside `default` and `legacy`, behind the
twenty five method contract, chosen by `chooser.provider` in `config/settings.lua`, which ships
as `default`. Its rules are the default provider's own, since that provider is
`lib/chooser/engine` composed with a canvas view, and the swift provider is the same engine
composed with `lib/chooser/providers/swift/view.lua`, a Humble Object over the library, behind
`lib/chooser/view.lua`, which did not change. The choice is made once at configure time, since
the one shared picker is built at startup. A library already built for the current sources is
loaded then, and otherwise the build starts, the default provider serves the session and the
swift provider takes over from the next reload, and a failed build serves default and logs the
compiler's error. The compiler is the `swiftc` inside the command line tools, `swiftc-clt` in
`root/manifest.lua`, resolved through the dependency door, and nothing is built or run unless
clang and an SDK for the running macOS sit beside it, the definition `src/install-xcode-clt.sh`
holds. A panel is torn down when the Lua state that made it closes, through a sentinel userdata's
`__gc` in the library's module table. The panel takes key itself, so the provider is handed no focus hold. The
bottom action bar, an anchored actions popover,
an Olm menu on a round button at the bar's left edge, and a native docked pane are planned on
top of it. Each one presents a model Olm already has, `footerModel`, ActionPanel's `rowsFor`,
and the UI kit's describer nodes.

## Rejected

- **Rebuilding Olm as a native app outside Hammerspoon, in MyGo or in Swift.** 2026-10-27.
  Olm is about 89,000 lines of Lua over some forty Hammerspoon modules, event taps, the
  accessibility layer, windows, screens and the pasteboard, and a rewrite rebuilds all of them
  before one plugin works. MyGo was also a poor fit on its own terms, version 0.7.1, pure Go
  with no cgo, and desktop APIs that stop at global shortcuts and a tray.
- **The panel in a separate helper process.** 2026-10-27. The picker contract asks synchronous
  questions, `selectedRow`, `rowCount`, `query` and `textWidth`, which a pipe answers only with
  a shadow copy of the panel's state in Lua, and keys would land in another process, against
  the secure focus work.
- **Committing a prebuilt binary.** 2026-10-27. It ties the repository to the SDK and the
  Hammerspoon it was built against and needs rebuilding and committing by hand after every
  change, where compiling on the machine keeps the source as the only tracked thing, which is
  how the three existing Swift helpers already work.
- **Naming the provider `native`.** 2026-10-28. The decision files already say native chooser
  and native provider for `hs.chooser`, the legacy one, so the word would make them ambiguous.
- **Hiding the panel when it stops being key.** 2026-10-28 11:15, before any live run. A click
  on the docked pane can hand key to that pane's window, and the canvas keeps the list up for a
  press inside the companion, so a resign key handler that hides would close the list under the
  pane. A press outside is heard by event monitors instead and decided in Lua against the same
  rects the canvas tests, and a press in the companion asks the panel to take key back.
- **Switching to the swift provider the moment a background build finishes.** 2026-10-28 11:15.
  The one shared picker instance is built at startup and lives for the session, so a provider
  that changed under it would leave that instance on the old one and any later instance on the
  new one. The choice is made at configure time and a finished build waits for the next reload.
- **Rebuilding when a source is newer than the output, under one fixed name.** 2026-10-28,
  before any build ran. A library that defines Objective C or Swift classes is never unloaded,
  so the next load of the same path is handed the old image and a rebuild is never seen until
  Hammerspoon quits. The output is named by a hash of its inputs instead, and the module name
  carries the same hash so the classes of two images never collide.

## Log

### 2026-10-27 20:00

Estimated time, before the first file of the spike existed. Asked how hard Olm would be to
rebuild as a native app, the answer was the rewrite above and its rejection, then the narrower
shape it led to, a native interface inside Hammerspoon behind the existing provider seam. The
facade's own header already promised that a backend is a provider file plus one branch.

### 2026-10-28 08:47

The first compile from the shell. `lua_State` arrives as a typed pointer rather than an opaque
one, since LuaSkin's headers make its struct complete, so the Swift side names it through a
public alias. `LuaSkin.shared(with:)` is the Swift name of `sharedWithState:`, and callbacks run
on `LuaSkin.mainLuaState`, the state the header says every callback belongs on. One command,
about a second, a 109 KB library exporting `luaopen_olm_swiftchooser` and linking LuaSkin
through `@rpath`.

### 2026-10-28 08:48

Built and loaded inside the live Hammerspoon through `lib/swiftbuild.lua`, 1.34 seconds for the
first build, no new console line, Hammerspoon still running. The second load came from the
cache in under a hundredth of a second.

### 2026-10-28 08:49

Shown over Ghostty. The surface was `NSGlassEffectView`, the panel was key half a second later,
and Ghostty stayed frontmost, so a nonactivating panel takes the keyboard without activating
Hammerspoon, the shape Spotlight uses. Milos tried it by hand and called it good.

### 2026-10-28 09:01

Shown over Safari. Key, Safari still frontmost, twelve queries typed and filtered live, then a
dismiss. Secure input read off at the moment the panel appeared and through every query, so
this run does not yet say whether the panel takes the keyboard while a password field holds
secure input or whether the field had focus at all. The next run reads it before the panel
shows.

### 2026-10-28 09:20

The default provider was split into an engine and a canvas view, with no change in behaviour,
before any Swift provider code was written. The provider's one file mixed Olm's picker rules with
canvas drawing, and a third provider written beside it would have copied the rules and drifted
from them. `lib/chooser/engine/init.lua` now owns every rule and all state and implements the
picker contract, `lib/chooser/providers/default/canvas.lua` owns the surface, the field and its
editing, the rows, the action bar, the pointer and the caret, and `lib/chooser/view.lua` is the
contract between them, checked at construction. The default provider is the two composed, so the
facade, the stage, the action panel and the composition root did not change. The engine is shaped
so a view whose field edits text natively can sit under it, it reads and sets the text and is told
of each change, and a key is asked of it before the field edits and after. Checked offline by
driving the provider through the facade with a stub `hs` before and after the split, every
callback, draw, frame, tap and timer event identical across about seven hundred lines, and by the
unit cases that drive a real instance, three of which were moved from the instance's `field` to
its `view` since the field now belongs to the view.

### 2026-10-28 09:28

The entry above counted three unit cases that reached into the provider instance. Review found a
fourth, the parity probe `Spoons/Olm.spoon/test/parity-canvasprovider.lua`, run by
`test/parity.sh`, which called the styles and the redraw on the instance and replaced its field,
surface and caret flag, all of which belong to the view since the split. It was ported to reach
them through `p.view`, keeping the old steps for a tree from before the split, since the probe
builds one provider from an exported older tree and one from this checkout. Its stand in surface
also gained the `interior` method the redraw calls, missing since that call was added, so the
probe had been failing at HEAD before the split and could not have compared anything.

### 2026-10-28 09:30

Run after the port, the parity probe still does not reach a comparison, and for a reason older
than both entries above. `test/parity-lib.lua`'s `largestStep` reads `chooserTheme` colours from
the exported tree's `config/settings.lua`, which has carried none since cafd002a moved the colour
themes into their own files, so it raises before either provider is built. The probe is left as
it is rather than repaired inside this change. The stub driven trace above already compares every
draw event of the provider before and after, a hundred and twenty four of them, and it ran
identical against `main` as well as against the split.

### 2026-10-28 10:55

Live under a manual hold of the test lock on this branch, from 10:44, Milos used his own lists on
the split chooser, the launcher, the action panel, the key panel, the clipboard and file search
with their panes, and a list over a password field, and said all of it works. The console after
the load carried no problem. Merged to main the same minute.

### 2026-10-28 11:15

The swift provider was built on `olm/swift-provider`, offline only. `providers/swift/init.lua`
composes the engine with `providers/swift/view.lua` and loads the library, `native/` grew from
the spike into the view, a field, an `NSTableView` list with the image, title, subtitle, a dimmed
disabled row and the Command digit column, and a plain action bar with its key panel, and
`spike.lua` was deleted. Every colour, font, size, radius and space step comes from the kit's
tokens through the scene, and every rectangle and row metric from the engine's geometry, so the
panel sits exactly on the canvas rect and the docked pane lines up. Swift runs the view
contract's key order in its window's `sendEvent` and `performKeyEquivalent`, asking Lua
synchronously and reading the answer off the stack, and hands each key over as its event's bytes,
which `hs.eventtap.event.newEventFromData` turns back into the event the engine reads. One
library serves every picker instance, each with a panel of its own named by an id. The view
contract was not extended. The library built from the shell with the provider's own flags with no
error and no warning, the stub driven `test/swiftview.lua` passes, the dry gate reports 0
findings with every golden matching, and `check-dependencies.sh` passes with `swiftc` declared by
the root. Not yet run live, so the glass, the key routing under a real field editor, the click
outside with the companion, the hover and the scroll sync are all unmeasured.

### 2026-10-28 11:30

An adversarial review of 88306fd4 found six faults, all fixed the same hour, offline. One, high,
`Entry.swift` and the Olm `AGENTS.md` both said `luaopen` cleans up after a reload, which was
wrong, since a reload that switches
the provider off, names a new image by a changed hash, or only builds never calls this image's
`luaopen` again, which left a panel on screen as key with its monitors running and let the
callback read an integer reference out of the new state's registry. The module table now holds a
sentinel userdata whose `__gc` stops, hides and forgets every panel and the reference, guarded by
a load generation so an old sentinel never clears a newer load, and a callback is refused unless
the main Lua state is the one it was registered on. That `__gc` runs at a reload rests on two
facts read offline, LuaSkin's `destroyLuaState` calls `lua_close` on the main state, read from its
disassembly, and `lua_close` runs every pending finalizer, which plain Lua showed. It has not run
in Hammerspoon yet. Two, a scroll over the companion reached the window under it as well, since a
monitor cannot consume, so the Lua view now claims it with its own scroll wheel tap, as the canvas
does, and the Swift path was removed. Three, `/usr/bin/swiftc` exists without the command line
tools and raises Apple's dialog when run, so the root now declares `swiftc-clt`, the compiler
inside the tools, mapped in `DEPENDENCIES.map`, and `swiftbuild.toolchain` checks clang and the
SDK for the running macOS on disk before anything runs, handing that SDK to the compiler. The
three plugins that compile Swift still declare `/usr/bin/swiftc` and carry the same exposure.
Four, every Control chord reached Cocoa's bindings, Control and O putting a line break in the
field, so only the Control keys the canvas keymap reads reach it, named in
`providers/swift/fieldkeys.lua`, and the field's command filter lets through only the commands
those produce. Five, the root checked list keys against the default field whatever served, so the
provider now has its own `uses` and the root asks the one that serves. Six, old libraries were
never removed, so a successful build now keeps the newest three of its name.
