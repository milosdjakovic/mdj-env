# Olm swift chooser

Status. A spike on `olm/swift-chooser-spike` proves a Swift library compiled by Olm itself loads
into Hammerspoon and draws a glass panel that takes the keyboard over another app without
activating Hammerspoon. The provider behind the picker contract is the next step.

## Now

Hammerspoon stays the engine, and only the interface becomes native. A Swift library is built
on each machine by `lib/swiftbuild.lua`, the build Olm runs itself through `hs.task` and
`swiftc`, with nothing in `setup.sh`. It lands in `~/.olm/cache/swiftchooser/` and is loaded
with `package.loadlib`, into Hammerspoon's own process. It links Hammerspoon's LuaSkin, whose
headers ship inside the app, the same way Hammerspoon's own `libchooser.dylib` does.
`native/bridge.h` is the one place Lua's function like macros are wrapped for Swift.

It will join the picker facade as a third provider named `swift`, beside `default` and `legacy`,
behind the twenty five method contract, chosen by one setting, with `default` served whenever
the library is missing or fails to build. The bottom action bar, an anchored actions popover,
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
