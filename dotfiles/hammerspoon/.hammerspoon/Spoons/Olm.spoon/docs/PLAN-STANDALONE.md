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

Next. 0.4, the bridge protocol, on paper.

Stage 0, contracts
- [x] 0.1 The decision record, 2026-11-05
- [x] 0.5 Gather LuaSkin into one Swift file, 2026-11-06
- [x] 0.2 Fixtures for ranking, 2026-11-07
- [ ] 0.4 The bridge protocol, on paper, with its adversarial review
- [ ] 0.6 A data source protocol in front of the library, and the package build
- [ ] 0.3a Fixtures for the file search grammar
- [ ] 0.3b Fixtures for the bottom bar model
- [ ] 0.3c Fixtures for keymap resolution
- [ ] 0.3d Fixtures for `KeyRemap.allocate`
- [ ] 0.3e Fixtures for list keys

Stage 1, the file search pilot
- [ ] 1.1 The app shell
- [ ] 1.2 The trigger
- [ ] 1.3 Search, open and reveal, shadow then flip
- [ ] 1.4a Preview pane
- [ ] 1.4b Thumbnails
- [ ] 1.4c Quick Look
- [ ] 1.4d Frecency, one owner

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
- [ ] 1 Where Olm.app lives
- [ ] 2 Unix socket or local HTTP
- [ ] 3 What extensions are written in
- [ ] 4 Leaders in a password field
- [ ] 5 The calculator
- [ ] 6 Lua after Hammerspoon

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
   input and expected output in JSON, that the Lua side and the Swift side both run. A part moves
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
Hammerspoon. Where its code lives is open question 1, decided before this step.

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
against the Lua file search, and a live trial of a large result set while typing.

**1.4 The rest of file search, one per step.** The preview pane, thumbnails, Quick Look and
frecency, each its own step and trial. Frecency is a store, so it has one owner. The app reads the
Lua history once at its flip and owns it from then on, and the Lua side keeps its copy so the back
out loses nothing that came before.

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

1. Where Olm.app lives. A repository of its own is recommended, since it is a product rather than
   dotfiles, with this repository installing it as a piece. Decided before 1.1.
2. Unix socket or local HTTP for the bridge. Decided by 2.1.
3. What extensions are written in. JavaScriptCore with shims, as Tinycast runs Raycast's, needs no
   bundled runtime. Decided before the extension host in stage 4.
4. Whether leaders work in a password field, through a bundled virtual HID driver, or the tap
   backend is accepted with its blind spot. Decided before 5.4.
5. The calculator. A native engine with a rates source this project chooses, rather than bundling
   the GPL library behind `qalc`. Decided when convert moves in stage 4.
6. Whether Lua survives as an optional scripting runtime in an extension process once Hammerspoon
   is gone. Decided in stage 6.
