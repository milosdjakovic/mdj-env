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
and the UI kit's describer nodes. The docked pane is built on `olm/native-pane`. Every pane is
reduced by `lib/dockedpane.lua` to hs.canvas element lists, and while the swift provider serves
the root hands each pane a native backend in the same library, which draws those lists on the
chooser panel's own glass, one shape spanning the list, the gap and the pane with a hairline in
the gap, so no plugin changed. Every CanvasPanel, the leader sheets and the three toasts, is drawn
by the same two backends through the same contract, on glass in a window of its own while the swift
chooser serves and on the canvas otherwise, built on `olm/native-panel`.

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

- **Drawing the docked pane by translating kit nodes into AppKit views.** 2026-10-28, considered
  and set aside before the pane was built. Of the three panes that describe with kit nodes, two
  drop to `ui.raw` for canvas elements, and two more panes paint canvas elements directly, so a
  node translation would have reached only one pane whole and needed four plugins rewritten.
  The element lists every pane is already reduced to are the contract instead.
- **Drawing the docked pane inside the chooser panel's own window.** 2026-10-28 12:06. A pane is
  made by a plugin and knows no chooser panel, the panel's frame is the canvas rect the engine
  reports while the companion rect is reported apart and may be absent, and one window across
  both would put one glass rectangle under the gap between them. The pane is a window of its own
  that never becomes key instead. Reopened 2026-10-28 12:58, see the next entry and the log. The
  one rectangle across the gap was chosen on 2026-10-28 13:12, see the entry after that.
- **The docked pane in a glass window of its own beside the chooser panel.** 2026-10-28 12:58,
  after Milos used it live. Each window samples what is behind it separately, so the list's glass
  read brighter than the pane's, and the pane's window animated in while the panel appeared with
  none. The two were never one surface. The chooser panel's window now spans both rects with two
  glass shapes in one container, which answers the reasons above without the one rectangle, and a
  pane's own window remains only as the fallback when no visible swift chooser owns its rect.
- **Two glass shapes in one NSGlassEffectContainerView, the list's and the pane's.** 2026-10-28
  13:12, after Milos used it live. The tone and the appearance matched, but each shape shaded its
  own edges and cast its own shadow where the two met, so the gap read as a dark band. Milos chose
  one surface, a single glass shape across the gap with a hairline divider in it.
- **Painting the surface elements onto the pane's glass.** 2026-10-28 12:06. The surface is a
  filled rounded rectangle under its border, and the fill covers the glass, so the pane would
  read as a painted card beside a glass panel. The native backend reads the surface's corner
  radius and stands the pane on the same glass as the panel instead.

- **A second native renderer for CanvasPanel.** 2026-10-28 15:18. `lib/panel.lua` already
  reduced every show to a surface and a content list of hs.canvas elements, the very lists a docked
  pane is reduced to, so `native/Pane.swift` draws them and a panel window is a `PaneConfig` on the
  same class rather than a class of its own.
- **Leaving the report toast on the canvas through a per panel opt out.** 2026-10-28 15:18. It is
  the one panel that takes a click, and the hit test the canvas does is a dozen lines in Swift, so
  every panel draws natively and the root keeps no knob with one consumer.
- **Reporting a panel's click through the chooser's one callback.** 2026-10-28 15:18. That callback
  belongs to the swift view and is registered only once a chooser is built, and a toast is shown
  with no chooser at all. Each clickable panel registers its own function with `paneNew` instead,
  held under the same state guard and dropped by the same cleanup.

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

### 2026-10-28 11:39

The first live load of the swift provider never reached the chooser. Hammerspoon refused
`root/compose.lua` with too many local variables, limit 200, in `obj.run`, which the wiring had
taken from 196 to 199 and past the limit once the compiler counted its temporaries. Every offline
gate had passed, since Homebrew's `lua` is 5.5.1 and accepts it, while Hammerspoon embeds Lua
5.4.7. So an offline gate here proves nothing about whether a file compiles where it runs. The
wiring moved into a helper beside `obj.run` and three blocks became `do` blocks, 190 at the peak,
and every Lua file of the worktree, 252, was then compiled by the running Hammerspoon with
`loadfile`, which executes nothing, and all of them compiled. Closing the blind spot for good,
running the offline gates under 5.4, is a question put to Milos.

### 2026-10-28 11:52

Live under a manual hold from 11:39, the swift provider serving every list, confirmed by asking
the running config, the provider answering swift and the stage's instance carrying the Swift
view. Milos used it and asked to keep the look as it is, the capsule action bar, the actions
popover and the round Olm menu set aside for now, and to build the native docked pane next.
Merged to main with default still the shipped value, so a machine takes the swift chooser only
when `config/settings.lua` names it.

### 2026-10-28 12:06

The native docked pane was built on `olm/native-pane`, offline only. `lib/dockedpane.lua` already
reduced every pane, described or painted, to hs.canvas element tables before drawing, so those
lists, the surface and the content, became the contract with a drawing backend the root injects,
a Strategy with place, render, show, hide and destroy. `lib/dockedpane/canvas.lua` is the canvas
half moved out unchanged. `providers/swift/pane.lua` over `native/Pane.swift` is the other, a
nonactivating panel that never becomes key, at the canvas pane's floating level, in the same
library as the chooser panel and torn down by the same sentinel, which draws the content on the
same glass and takes the surface's corner radius rather than its fill. Read from the five panes
and the kit's layout, the elements in use are rectangle filled, stroked and clipped with rounded
radii, segments stroked with round caps, image with alpha, proportional scaling and top left or
centred alignment, text as an hs.styledtext, and resetClip, and every one is drawn with the
canvas's semantics, a clip adding to the region until resetClip clears it, as the kit's layout
assumes. hs.canvas's own binary names `drawInRect:` for text and the image call with
`respectFlipped`, which the Swift side uses too. Anything else is left out of that element and
named once in the console. `root/compose.lua` picks the backend in `dockedPaneBackend` beside
`wireSwiftChooser`, the native one only while the swift provider is chosen and its library is
loaded, and `obj.run` kept its 195 register slots, the change living in a closure it already
had. The library built with the provider's flags with no error and no warning, the new
`test/panebackends.lua` drives one pane over both backends for an empty, a described, a painted
and a scrolled pane and finds the native one handed the very content the canvas paints over its
surface, and `test/swiftview.lua`, the unit case `test/cases/dockedpane.lua` under plain Lua, the
dry gate and every golden pass. Not yet run live, so the glass beside the panel, the text
metrics against the canvas, a click on the pane keeping the list and the keyboard, and the
sentinel closing a pane at a reload are all unmeasured.

### 2026-10-28 12:58

Milos tried the native pane live on 7442f7aa. The list's glass read brighter than the pane's,
since each window sampled the screen behind it on its own, and the pane faded in while the panel
appeared at once. Reworked offline the same hour. The chooser panel's window now spans the canvas
rect and the companion rect, and the Lua view hands it the union and where each shape sits in it,
with the companion in screen space too. The window holds an `NSGlassEffectContainerView`, read
from the macOS 27 SDK header, with two `NSGlassEffectView` shapes. Its spacing is the proximity
at which it starts merging shapes, zero by default, which the header says still batches them, so
zero keeps the engine's gap between two shapes rather than one blob. Both windows set
`animationBehavior` to none. A pane still knows no chooser. `chooserHosting` in
`native/Entry.swift` is the one seam, matching the pane's rect to the companion rect a visible
chooser panel last reported, and the pane's view moves into that panel's pane shape, or into a
window of its own when nothing matches. Read from the canvas view, a press between the two hides
the list and passes through. Here a press in the clear gap that reaches the window is reported
as a press outside and hides the list too, though whether the window server passes it through to
the window below is unmeasured. The field, list and footer keep the canvas's own coordinates, so
every reported index and point is unchanged. closeAll closes every pane before the panels.
The library built with the provider's flags with no error and no warning, `test/swiftview.lua`
gained the shared window's rects, the gap press and the no companion case, `test/panebackends.lua`
the native pane placed on its current companion before it draws, and the dry gate, the goldens
and the dependency check pass. Not yet run live.

### 2026-10-28 13:12

Milos tried the two shapes on 320f9edd. The tone and the appearance were right, but the shapes'
edge shading and shadows met in the gap as a dark band, and he chose one surface. Reworked offline
the same hour. With a companion the chooser panel's window and one `NSGlassEffectView` span the
canvas rect, the engine's gap and the companion rect at the surface radius. The list's content sits
on the canvas rect, the pane's region on the companion rect, and a hairline divider is centred in
the gap from top to bottom. Its colour is the kit's border colour role and its width the kit's
border width token, both handed over by the Lua view, which also computes where it goes. With no
companion the window is the list's shape alone, as before. The glass container was dropped, since
one shape gives it nothing to batch or merge. The seam and the pane's own fallback window did not
change. One behaviour changed on purpose. A press in the gap now lands on glass, so it is inside,
keeping the list and the keyboard as a press on the pane does, and the Lua view's press outside
rule treats the span from the canvas to the companion as inside while there is a companion and
only then. The default chooser is unchanged and still hides for a press in its gap. The library
built with the provider's flags with no error and no warning, `test/swiftview.lua` gained the gap
press, a press past the companion, the divider's width, place and colour and the no companion
case, and the dry suite, the dry gate, the goldens and the dependency check pass. Not yet run live.

### 2026-10-28 13:42

Live under a manual hold from 13:14, the list and its pane as one glass shape with a hairline
divider. Milos found the tone one, the pane appearing with the list, and a press in the old gap
keeping the list, and said it works. Two things surfaced on the way. Holding Hyper showed RUNNING
wrong and no DORMANT group, and the app switcher came up first, because the test lock points
Hammerspoon at the worktree, whose folder has no `machine-apps.lua` or `machine-displays.lua`,
so every worktree test has run without this machine's Hyper app keys. Linking the two files into
the worktree for the test put both right, and the test lock is to do that itself. And the pane
does not scroll smoothly, since every scroll event rebuilds and redraws the whole element list
through Lua, as the canvas pane always did, which reads as stepping beside a natively scrolled
list. Merged to main with default still the shipped value.

### 2026-10-28 13:50

The native pane scrolls natively, built on `olm/pane-native-scroll`, offline only. The backend
contract in `lib/dockedpane.lua` gained a capability a backend may answer, `scrollsNatively`,
with `scrollBy` beside it. For such a backend a scrolling pane's content is laid out once at its
full height, unshifted and cut at the viewport grown by the overflow, and rendered with the whole
height, the pane's own, a reset flag and the thumb request. The pane then keeps no offset, clamps
nothing, draws no thumb and runs no timer, and `pane.scrollBy` becomes the backend's. Reset
follows today's rule, a show without `keepScroll` resets, a repaint, a redock and a `keepScroll`
show keep. A painter is called a second time with `view.viewport` grown by its overflow, which is
how the file search preview, which cuts its body at the viewport and lays out only the lines
inside it, hands over everything without a plugin change. One behaviour changes with it, its
header now scrolls with the body under the native backend. The canvas backend answers nothing and
its path is untouched. In `native/Pane.swift` the drawn elements sit in a flipped document view
inside an `NSScrollView`, which is what moves between the chooser's pane region and the fallback
window, with no scroller unless the pane asked for a thumb, then the overlay style, elasticity
only when there is something to scroll, the position kept and clamped across a redraw, and only
the elements reaching the dirty rect drawn. The scroll tap and the hosting meet in one place,
`View:_onScroll` in `providers/swift/view.lua`, which asks the panel through a new `hostsPane`
whether its window holds a shown pane and, if it does, leaves the scroll for AppKit. A pane in
its own window is still claimed by the tap and scrolled through `scrollBy`, instantly and without
a Lua repaint, since whether that window gets scroll events under an inactive Hammerspoon was not
something to rest on unmeasured. Scrolling natively under the swift chooser are speedtest, the
clipboard preview and the file search preview, the three panes that pass `scroll = true`. The
library built with the provider's flags with no error and no warning, `test/panebackends.lua`
gained the canvas scroll unchanged, the native full height content, the native scrollBy, the kept
and reset positions and a painter cut at the viewport, `test/swiftview.lua` the tap leaving a
hosted pane's scroll alone, and the dry suite, the dry gate, the goldens, the dependency check and
the docked pane unit case pass. Not yet run live, so momentum, the overlay scroller and the cost of
a tall file preview drawn once are unmeasured.

### 2026-10-28 14:18

Milos tried the native scroll on d4ff8f11 under the swift chooser. The clipboard, file search and
speed test panes drew nothing, with no console line, and row and action bar icons read a little
blurry. Both found offline the same hour.

The blank pane. The pane's view is now an `NSScrollView`, made in the pane's own window, where
`NSGlassEffectView` takes it as its content view, turns off its autoresizing mask and pins it
with constraints of its own. When the pane docked into the chooser's region those pins stayed
with the glass, so the scroll view stood there placed by constraints with none, and since an
`NSScrollView` carries constraints of its own the layout engine owned its frame and the first
layout after its frame changed, a redock at a new companion size among them, sized it to zero by
zero. The old pane was a plain view with no constraints, which the engine leaves alone, so the same
handover never showed. Found by building the real classes into a program with no window shown,
which read the frame as 300 by 400 before the window's layout and 0 by 0 after. `holdPane` now
gives the view its autoresizing mask back, and a pane leaving its own window has the glass drop
its claim through a new `Surface.release`, since a glass that still named the view took handing
it back as no change and left it with no superview, the fallback blank too. Whether every live
blank was this is for the next live look, which `paneDebug` on the swift provider module answers,
hosting, frames, document, clip and element count.

The icons. An icon reaches the native list as an hs.image whose bitmap is bigger than its box,
and an `NSImageView` hands it to Core Animation, which shrinks it with a linear filter at a frame
that may sit on half a point, where the canvas list draws it through Core Graphics. Now the frame
is moved to whole pixels and the picture drawn once at high quality into a bitmap of exactly the
pixels it covers, through `Crisp` in `native/List.swift`, for the rows and the action bar's key
icon, and the pane draws images on whole pixels at high interpolation. Nothing knows which source
made a picture. The symbol source itself is lower than it should be. `lib/icons/sources/sf.lua`
renders a 64 point symbol and writes it through `TIFFRepresentation`, whose first and only
representation was measured at 75 by 75 pixels for 75 points, a 1x bitmap, which `hs.canvas` then
enlarges to 60 points in a 72 point box before the engine sizes it down. Rendering at 2x would
mean drawing the symbol into an `NSBitmapImageRep` of twice its point size with that size set as
its points, or rendering the symbol at 128 points, in that script. Not changed yet.

The library built with the provider's flags with no error and no warning. The new
`test/swiftpane.sh`, run by `suite.sh dry` and skipped with exit 2 on a machine without the
command line tools or Hammerspoon, builds the library's sources into a program that pins the pane
filling the chooser's region after a redock at a new size, its return to its own window and back,
the scroll's reset, scrollBy, kept place and clamp, the drawn content at the top, and an icon's
pixel size, points and template flag. With the autoresizing line removed it fails on the redock.
The dry suite, the dry gate, the goldens, the dependency check and the docked pane unit case
pass. Not yet run live.

### 2026-10-28 14:21

Live under a manual hold from 14:20 with the docking fix, the clipboard, file search and speed
test panes drew their content and scrolled natively, and Milos said it works great. The file
search preview's header scrolling away with its body stands as it is for now, since nothing was
said against it. Merged to main with default still the shipped value.

### 2026-10-28 14:53

Swift became the shipped chooser. Before it did, the two cases never measured under it were tried
live under a manual hold on this branch, typing into the launcher opened over a Safari password
field, and the fn cycle, a letter typed straight after a tap, three taps and a wait, and a tap then
Escape. Milos reported all of it working. A logger meant to record each case stopped after its
four minute window before the cases were run, so the record of these two is his report and not a
log, and a later doubt about either should start by running them again with the logger, which
keeps no window at all next time.

### 2026-10-28 15:03

Live on a Retina built in display, every row icon of the swift chooser was half size and sat
towards the bottom left, while the same icons were correct on a 1x external display. The cause was
the order in Crisp.image. It made the graphics context from the bitmap rep and only then set the
rep's size in points, and a context made from a rep still sized in pixels measures its user space
in pixels, while the drawing rect is computed in points. At scale 2 that draws a quarter of the
area. The size now goes on before the context is made. Pane.swift and Bar.swift were checked and
make no bitmap context of their own, since the pane draws into its view's current context and the
bar goes through Crisp.image. A check in swiftpane.swift draws a full bleed opaque square at
scales 2 and 1 and asserts every pixel is opaque. It failed with the old order, 400 of 1600 pixels
at scale 2, and passes with the fix.

### 2026-10-28 15:18

Every CanvasPanel draws natively while the swift chooser serves, built on `olm/native-panel`,
offline only. `lib/panel.lua` keeps every rule, the placement, the sizing, the reveal timing, the
appearance and the surface style, and where it made an hs.canvas it now calls the drawing backend
the docked pane already takes, injected by the root through `CanvasPanel.configure({ backend })`,
so the pane's contract has its second consumer. The canvas half moved into
`lib/dockedpane/canvas.lua` unchanged. The contract was extended in one place for both, in
`lib/dockedpane.lua`'s header, by an optional second argument to the factory, the panel's window,
`{ level, onClick, activates }`, which a pane never passes, and by `isShowing()`, which only the
panel asks. On the canvas a panel is made exactly as before, its level, its mouse callback only for
content that takes a click, and hs.canvas's own click activation left on, so `activates` asks for
it. Driven over a recording canvas stub against the old `lib/panel.lua` from HEAD, every call was
the same but one, a `frame` call to the frame the canvas was just made at on the first show, since
a backend is placed before every render.

The native backend is the pane's, `providers/swift/pane.lua`, and with a window it asks the
library for a panel window, `paneNew({ panel, level, onClick })`. That window is never drawn into a
chooser's, whatever its rect, stands at the panel's level, popUpMenu for all four panels, is
ordered front on every show as hs.canvas is, never becomes key or main and never activates
Hammerspoon, and is click through unless onClick is given. Then `PaneCanvas` takes the first press
and answers the mouse up with the id of the topmost element built with id and trackMouseUp, by its
path or its bounds, or `_canvas_` off every one, the way hs.canvas reports, through a Lua function
the library holds for that panel alone, refused off its own state, released on delete and dropped
by the sentinel. The surface becomes glass at its radius, with the pane window's shadow and no
animation, as the canvas had none. The report toast is the only panel that takes a click. The
message and colour toasts and the cheat sheet behind every leader sheet are click through. None
fades or waits, `delay` being unused today, and the timing stays in Lua either way.

The library built with the provider's flags with no error and no warning. The new
`test/panelbackends.lua`, run by `suite.sh dry`, drives a sheet, a clickable toast and a panel
docked below an anchor over the canvas backend against a copy of the old canvas code and over the
native backend, and finds the same frame, level, mouse settings, elements, shown state and click,
and the native one handed the very content list over its surface at the surface's corner radius in
a panel window. `test/swiftpane.swift` gained a panel window that stays out of a chooser on the
companion rect, its level, click through with no handler, the hit test and a mouse up reaching the
handler, and a full bleed surface covering every pixel at backing scale 2 as at 1. The dry suite,
the dry gate, the goldens and the dependency check pass. Not yet run live, so the glass behind a
leader sheet and a toast, a click on Dismiss with another app frontmost, the stacking of a sheet
over an open swift chooser, and text metrics against the canvas are all unmeasured. One thing
differs from the canvas on purpose, a click on Dismiss no longer activates Hammerspoon.

### 2026-10-28 15:38

Milos tried eab2114f live, the leader sheets, a long toast, a full screen app and the report panel, and said all seems good, shadows included. Review found that nothing destroyed a CanvasPanel backend, which a dropped hs.canvas never needed since its __gc deleted it, while a dropped native backend kept its window and its click reference until the next reload, so a cheat sheet configured again while its sheet was up would have left glass on screen. Panel instances now have destroy, which hides and destroys the backend, and `lib/cheatsheet.lua` calls it on the panel its configure drops, the one place a panel is replaced, the toasts in `root/compose.lua` being made once per load. `test/panelbackends.lua` pins it on both backends, offline only.

### 2026-10-29 15:16

Milos asked for the action bar to span both the chooser and the docked pane when one is up. The
view contract gained one optional capability, `spansFooter`, which the engine asks once after the
view is built, and the swift view answers true since its one shape of glass already spans the
canvas, the gap and the companion. The engine then sets `footerSpan` on its layout, and
`geometry.resolve` widens the footer rect from the canvas's left edge to the companion's right
edge and stops the companion rect at the bar's top edge, so the pane is laid out at the height it
is shown rather than drawn under the bar. Doing it in the geometry rather than only in Swift is
what keeps the pane's own layout honest, since a pane reads the companion rect it is docked on.
In Swift the bar and its key panel moved from the list's content view onto the shared surface's
stage, above the pane's region, placed in window space, and the key panel takes the bar's width,
so it opens over the pane too. The divider stops at the bar's top edge. The default chooser
answers nothing and is unchanged, since its pane is a canvas of its own beside the list and a bar
across the gap would need its canvas to grow. `test/geometry.lua` and `test/swiftview.lua` pin
the spanning bar, the shorter companion and the divider, and the dry suite, `swiftpane.sh`, the
dry gate and the goldens pass. Not yet run live.

### 2026-10-29 15:45

The surface radius went from 0 to 17, the macOS 27 window corner measured off Finder, Calendar and
Reminders, and Milos saw a square edge outside the glass at the chooser's bottom corners and a
doubled edge at its top ones. A first guess, a stale window shadow, was wrong and was taken back,
since a capture with no shadow still carried it. Measured in a test program, a borderless window
holding only an `NSGlassEffectView` drew a faint fill in its square corners, alpha 7 to 15, and a
half covered edge column, on a 1x and a 2x display and with or without a shadow, exactly while it
was key and not a moment after it lost key. So the window server draws a key window's edge along
the window's outline, and a borderless window's outline is square. A titled window with its title
bar transparent, hidden and empty has a rounded outline at the system window corner, measured at
the same diagonal inset as Finder's, and drew clean corners while key. The chooser's panel is that
now, unmovable and unconstrained so it keeps the canvas rect, and the list's and the pane's scroll
views stop insetting their content by the title bar's height, which `swiftpane.sh` caught as three
failing scroll cases first. Captured live after the change, every corner pixel outside the curve is
clear and the diagonal inset is 5 points, a 17 point corner. The panel windows and the docked
pane's own window stay borderless, since they never become key. A click on the top strip of the
chooser lands on the hidden title bar rather than the field, which nothing has needed yet.

### 2026-10-29 17:53

Milos asked for the action bar to float as two groups, keys on the left and actions on the right,
each the window's padding from the bottom edge and its side, with the rest of the list visible
behind it. Built on `olm/floating-bar` and checked live by him in three rounds. A first fill of
the highlight colour at 40 percent read as too transparent, then the full highlight as the wrong
style, and what stayed is each group being exactly the window's own glass, an untinted
`NSGlassEffectView` from the same `Surface`, with the highlight tint only while the key panel is
open, and every word and chord in the row title's font and colour rather than caption. The bar no
longer reserves a band. The engine's list rect and viewport are unchanged, so numbering, the
highlight's scroll and the furthest scroll all read as before, and only Swift grows the table's
frame and its bottom content inset by the bar's height, which shows the rows past the viewport
behind the groups without any row the engine numbers sitting under them. The bar view answers no
hit outside its groups, so a press or a scroll between them reaches those rows. The view contract
gained a second optional capability, `footerHeight`, since the floating bar's region is a group
and the padding below it rather than the default row.

Asked whether every padding is uniform, measuring found one that was not. The native field's
editor starts its text one line fragment padding in, 2 points, so the caret sat at 16 from the
edge where the field rect, the highlighted rows, the pane's content and the groups all sat at 14.
The field now stands left of its rect by the padding its own field editor reports. The gap between
the chooser and its pane was a borrowed 12 from the legacy chooser and is the inset now.

Then the paddings were split by meaning rather than made one. `spacing.outer` in
`config/settings.lua` is how far content stands from any edge of the glass, the field, the list
margin, a pane's content, the bar groups and the gap, and `spacing.inner` the room inside a filled
shape, a row's edge to its icon and the inside of a bar group. They were one value before, so a
roomier window fattened every row. Both ship at 14, so rows look as they did and the groups grew
from 8 to 14 inside. A row's and a group's corner stays the surface radius less the outer padding,
14 giving 3, 10 giving 7 and 17 or more square. A gap value was considered and left as the kit's
space steps, since nothing asked to move it.

### 2026-10-29 17:58

Milos asked for the pane to run behind the bar as the list does. The first attempt kept the
companion rect stopped at the bar's top and only grew the pane's region in Swift with a bottom
content inset, and Milos's screenshot showed the glass reaching the bottom while the text was
still cut at the bar's top, since the docked pane lays its content out and clips it in the
companion rect. So the companion keeps the canvas's height again, as it did before the bar
spanned, and carries `under`, the bar's height, which `lib/dockedpane.lua`'s inner box leaves out.
Content is laid out above the bar, the clip is the whole companion so a cut line shows behind the
bar, and a native pane's scroll height grows by the same amount, so its last line scrolls clear
with no inset in Swift. A view that does not span, the default chooser, gets no `under`.
The same day the names for the chooser's parts were settled, chooser, field, list, pane and bar
with a keys group and an actions group, in the Names section of `Spoons/Olm.spoon/AGENTS.md`.

### 2026-10-29 18:13

The key panel became a popover, `native/Popover.swift`, a shape of the window's own glass
standing above the keys group with its left edge on the group's, an optional header and one
column of lines, each a label in the row title's font and colour and its chord in subtext, and
scrolling once it would rise above the list's top. It replaced the flat two column panel over the
bottom of the list, which `decisions/olm-chooser-keys.md` chose on 2026-10-23 over a dropdown
anchored to the key button, turned down then as a new component for one list of about a dozen
keys. That reason no longer holds, since the popover is built to be the action panel's too. Its
header is this Olm's name and version, `title` in the footer model, which the root hands in from
`olm.version`. Its padding is the inner padding, each line as tall as a group, and its corner the
groups'. Milos checked it live and kept it as built.

### 2026-10-29 18:38

The action panel became the popover's second user, above the actions group, built on the panel
the action panel host already runs rather than a second one. The footer model says `panelOpen`
while the panel is open, and the swift view then keeps the list's own rows, highlight and scroll
on screen and draws the engine's rows, which are the panel's, in the popover with the engine's
highlight, the list answering no pointer meanwhile. The engine re reads the footer model before
the redraw that first shows the panel's rows, so the list never flashes them. The view answers
`floatsActionPanel`, so the panel leaves out its Back row, and Escape closes the panel alone
through the model's `panelAction`. Each entry of the actions group runs its own action through a
new `footerAction` on the engine, which the stage hands from the root's dispatch.

Milos checked it live in four rounds. The first showed the highlight 14 from the popover's top and
bottom and 7 from its sides, so a chosen line now stands the outer padding from all four edges with
its text the inner padding inside. The key panel then read uneven, since its lines are never lit,
so a popover of read lines stands its text itself the outer padding from every edge, top and
bottom measured to the text. Its header went from caption to the row title's size and colour, and
the rule from half the outer padding on each side to the whole of it.

