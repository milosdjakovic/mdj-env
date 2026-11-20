# The app's launcher on a trial key, step 3.2

A design note for step 3.2 of `docs/PLAN-STANDALONE.md`, written and agreed with Milos on
2026-11-13, the trial key Hyper and 0 and tool rows held in place, both as proposed. Step 3.1 left Hammerspoon able to run a launcher row
for the app, with only the test client asking. In this step the app shows a launcher of its own, on
a trial key set for this Mac alone. Hyper and Space still opens the Lua launcher, so nothing a
person relies on moves.

## What it proves

The trial is the plan's test. A person opens the app's launcher, types, picks rows, and the three
timings are recorded: the key to the list on screen, a keystroke to its rows, and Return to the
app in front. Before the flip of 3.5 lets the app take Hyper and Space, it has to be shown that
the app's launcher finds the same rows, ranks them the same, runs them the same, and is no slower.

## How it works

1. **The trial key.** The bridge host declares one action, `bridge.launcher`, "App Launcher". It
   opens `olm://launcher` through the same road the file search key takes, the distributed
   notification `local.olm.Olm.open`, with the screen named by Olm's placement choice. The key is
   one line in `machines/Jelenas-MacBook-Pro/hammerspoon-apps.lua`, then
   `src/setup-hammerspoon-apps.sh`, as rule 9 says. Since every action becomes a launcher row and
   a cheat sheet row, the action carries `when = "olmApp"`, a predicate that is true only where
   the olmapp piece is on. So on every other machine it shows nowhere.
2. **A source of its own.** The launcher a person sees is a second `BridgedLauncher`, separate
   from the one the shadow uses. This is how file search already keeps its shadow off the list a
   person has open, so the shadow's own `rows` never move the shown level's revision or `q`. The
   bridge attaches both. Each gets the memory on `open`, and the `memory` notification goes to
   each.
3. **One level for each show.** The stage's `open` sends `open {"launcher":true,"fromURL":true}`
   and the stage's `close` sends `close`, so a level lives exactly as long as the list is up. The
   shadow's source keeps its long-lived level as it does today. `fromURL` is sent, and the Lua
   side has nothing to hold back with it yet: the launcher hands a list over, as `vpn ` does, only
   while the Lua stage shows the launcher, so a bridged level's `rows` never start one before 3.3.
4. **Rows and generations.** `rows` is sent as today. An answer whose `q` is older than the newest
   one sent for that level is dropped, by the source rather than the stage, so the shadow's own
   requests never count. `h` is the stage's highlight generation, raised on every highlight move,
   and `choose` carries it. The `highlight` notification is not sent yet, since nothing on the Lua
   side reads it for the launcher before 3.4's list keys.
5. **Return.** `BridgedLauncher.choose` sends `choose {level,q,h,ref,row,query,mods}` and turns
   the effects into the stage's:
   - `hide` is `Effect.hide`, which the stage already applies first.
   - `after hidden` is a new effect, `afterHidden`. The stage sends the notification `hidden` once
     `panel.hide()` has returned. The panel is nonactivating and stops taking keys at that moment,
     so the app the person was in is already in front, and the fade needs no waiting.
   - `requery` searches again with the field's text and chooses nothing.
   - `unserved` keeps the list and the row as they are and logs one line. Until 3.3 a tool row
     does nothing in the app's launcher, which the trial instructions say.
   - No effects, a disabled row, does nothing.

   Return while a `rows` answer is still out sends `choose` at once with the query on screen, and
   the Lua side's `requery` covers a row that the newer answer would have removed.
6. **Icons.** `Icon` in OlmKit gains the protocol's shapes the launcher sends: `app` (the
   application's own icon, from `NSWorkspace`), `emoji` (drawn to an image once and cached), and
   `owner`/`key`. An owner's table is asked once per connection with `icons`, and its `sf` is
   preferred over its `emoji`, as `lib/icons/` prefers them. `mark` waits, since no launcher row
   carries one. `BridgedLauncher.take` reads `icon` instead of leaving it out.
7. **metrics.** After `hello`, and again whenever the panel's width changes, the app sends
   `metrics {textBudget, font}`, `textBudget` being the stage's `rowBudget`. The launcher reads
   none of it, but the protocol says 3.2, and 3.3's hosted file search will.
8. **The bottom bar.** The bar the app draws is read from the `keys` share, which the bridge
   writes only for a tool it serves. It also writes one for `launcher` where the olmapp piece is
   on, so the app's bar says what the Lua launcher's bar says, Run and the info pane's keys.

## What has to grow for it

- The Swift side:
  - `Bridge.attach` takes a list of launchers.
  - `BridgedLauncher` gains `choose`, `close`, an open on every show, `q` drops, and icons.
  - OlmKit's `Effect` gains `afterHidden`, `requery` and `unserved`, and `Icon` gains `app`,
    `emoji` and `owner`.
  - The stage sends `hidden` and its `h`.
  - `main.swift` answers `olm://launcher`.
- The Lua side:
  - `serve.lua` reads `fromURL`.
  - The bridge host's manifest declares `bridge.launcher` with its predicate.
  - `compose.lua` writes the launcher's `keys` share.
- This machine's keys file gains the trial key.

## Tests

- `olm-bridge-check` grows these checks, replayed from the fake Lua side:
  - a shown level opened and closed per show
  - a stale `q` dropped
  - each effect of a `choose` answer mapped
  - `hidden` sent after the hide
  - the icon shapes read
- `test/bridge.lua` pins the trial action, its predicate and the launcher's keys share.
- The keys goldens gain the trial action's row, and nothing else moves.
- Live, by hand, after the gates. A numbered trial for Milos:
  - open on the trial key
  - type a few queries
  - Return on an app, a window action and a calculator answer
  - a tool row, to see it held in place
  - Escape

  The three timings are 1.3f's, the panel timing itself while `~/.olm/run/timings` exists, one
  line per open in `~/.olm/log/timings.jsonl`, read by `test/timings.lua`, the same code in both
  launchers. A `choose` over 250 ms is logged. I read the shadow log before and after.

## Back out

Remove the line from this machine's keys file and run the setup script. The action stays and is
reached by nobody.

## Two things Milos decided, 2026-11-13, both as proposed

1. **The trial key.** Proposed: Hyper and 0, which nothing binds. This Mac sends Hyper as four
   modifiers through kanata, so a chord with Shift beside Hyper would answer only on Caps Lock and
   is ruled out. Other free keys are 6 to 9, period, the brackets and minus.
2. **Tool rows during the trial.** Proposed: held in place and logged, as the protocol says
   for 3.3. The other way is closing the app's list and opening the Lua launcher on that tool. That
   is the close and reopen the rules forbid, so it isn't proposed.

## As built, 2026-11-13

- Return's after hidden needs no effect of its own. The stage already closes the list's source as
  it hides, so the shown launcher sends `hidden` from its `close`, before closing the level, and a
  hide followed by its close is the order the protocol asks. The stage's next open of the same
  source waits for that close, so a level opened for a show is never closed by the hide before it.
- `requery` became an effect of OlmKit's, `unserved` a log line, and `Pick` carries the row's place
  and the highlight generation.
- An owner's icons are asked once a connection, after the first rows that name the owner, an `sf`
  preferred over its `emoji`. An app's icon is the system's for its bundle id, and an emoji is drawn
  at 60 points on a 72 point square, as the Lua emoji source draws it.
- `olm-bridge-check` grew to 61 checks, the shown launcher's metrics, its level per show fromURL,
  its icons, `choose` and each effect, `hidden` before the close, and an older rows answer dropped.
- Found in the trial, 2026-11-13. Return on Left Half moved Olm.app's own list, not the window in
  front. The stage closed its source the moment it called the panel's hide, and the panel stays key
  while it fades, so the window action, run on `hidden`, found the fading list the focused window.
  The protocol says `hidden` comes once the window is ordered out, so the panel now says when its
  fade has ended, `onDown`, and the stage closes the source then. A show cutting the fade short
  wakes the wait, and so does a cap of 1 s.


# Step 3.5, the flip of Hyper and Space

A design note for step 3.5 of `docs/PLAN-STANDALONE.md`, written on 2026-11-17 and agreed with
Milos the same day, as proposed. Hyper and Space opens Olm.app's launcher where the `olmapp` piece is on, and the Lua
launcher whenever the app cannot answer. It is the first step a person relies on.

## The gate

2.3's shadow log, `~/.olm/log/shadow-launcher.jsonl`, held 86 lines and no difference on
2026-11-17, so the condition carried here on 2026-11-13 holds.

## How it works

1. **The open row's run is swapped, the way a served tool's is.** `root/compose.lua` already
   swaps the run of each `open` row whose owner the app serves, 1.2's road, and leaves the chord,
   the words, the cheat sheet row and the goldens alone. The launcher is not added to `serves`,
   since that share also warms a list and names the tools the launcher hands over natively. The
   bridge instead answers a new `launcherOpen(fallback)`, and compose swaps `launcher.open`'s run
   for what it answers. It answers nil where `_launcherReady` is nil, the piece off, the app not
   built or the socket setting off, and the row keeps the Lua launcher.
2. **Asked at every press.** The swapped run opens the app's launcher, the trial key's own
   `_openLauncher`, while the socket is up, and runs the Lua launcher's own run otherwise. The
   socket is the right question, since the app's launcher answers only over it, and asking it costs
   nothing. The transport gains `c:isUp()`, which reads the `up` it already keeps. So:
   - App running and connected: the app's launcher.
   - App quit, mid session or never started: the Lua launcher, at once, with no wait.
   - App started but not connected yet, the moment after a launch or a reload: the Lua launcher.
3. **A quit app stays quit.** The fallback never starts the app, so quitting it is the back out
   the plan names and holds until the next Hammerspoon load, which starts the app once as it does
   today for the shadow.
4. **Closing on Hyper and Space.** The launcher's own close key is its open key. While the app's
   launcher is up, `showing("launcher")` is already true and the launcher's list keys reach it
   since 3.3c, so the same chord closes it. That is checked live, not assumed.
5. **The trial key goes.** `hyper+0` is removed from this machine's keys file and
   `src/setup-hammerspoon-apps.sh` runs, as rule 9 says. The `bridge.launcher` action stays,
   reached by nobody, as the 3.2 back out said.

## What does not change

Any other road into the Lua launcher, a tool's Back to it or a call from another plugin, stays
Lua. Only the key flips. On a machine whose `olmapp` piece is off, nothing changes at all.

## Tests

- `test/bridge.lua` pins `launcherOpen`: nil with the piece off, and with it on, the app opened
  while the transport is up and the fallback run while it is down.
- The keys goldens are unchanged, since only a run is swapped.
- The dry suite, the unit cases and `test/bridgeserve.lua` as at every step.
- Live, with the guarded driver while Milos is idle:
  - Hyper and Space opens the app's launcher, and again closes it.
  - Olm.app quit, Hyper and Space opens the Lua launcher. The app started again and connected,
    Hyper and Space opens the app's.
  - The three timings of 1.3f for the app's launcher, which `~/.olm/log/timings.jsonl` does not
    hold yet and the resting point's second condition asks for.

## Back out

Quit Olm.app, or switch the `olmapp` piece off. Either gives Hyper and Space back to the Lua
launcher without a change to any file.

## As built, 2026-11-17

- `host/bridge/transport.lua` gained `isUp`, `host/bridge/init.lua` gained `launcherOpen`, and
  `root/compose.lua` swaps the launcher's open run beside the served tools' and names `launcher` in
  `servedByApp`.
- `test/bridge.lua` 132 checks, the piece off, the socket setting off, no fallback, the socket not
  yet up, a socket that went, and the app opened when it is up, each asked at the press.
- The dry suite, the goldens, the fixtures and the unit cases pass, and the keys goldens are
  unchanged.
- Checked live on 2026-11-17 with the guarded driver while Milos was idle. With the app connected,
  Hyper and Space opened the app's launcher and a second press closed it. With Olm.app quit, the
  socket went within a second and Hyper and Space opened the Lua launcher, and the app stayed quit.
  A Hammerspoon load started it again, as the note says.
- The timings of 1.3f for the app's launcher, three opens with three keystrokes each, from
  `~/.olm/log/timings.jsonl`: a keystroke to its echo 23 to 45 ms, a keystroke to its rows 66 to
  112 ms. The record holds no key to list time and no Return to app time, so those two of the three
  are still not recorded.

## Held off, 2026-11-17

Milos's trial found Clipboard History doing nothing when chosen in the app's launcher. A launcher
row leading to a tool's own list is answered `unserved` for any tool not in `hosts`, held in place
by design since 3.2, and that was harmless while Hyper and Space still opened the Lua launcher.
This note missed it, so the flip took away every such row: Clipboard History, Menu Search, Display
Profiles, Workspaces, Obsidian, Processes and Olm's own pages among them. On his choice the flip is
held behind a setting, `launcherFlip` in `config/plugins.lua`, false, so Hyper and Space opens the Lua
launcher and Hyper and 0 the app's again. Turned down: closing the app's launcher and opening the
tool's Lua list, the close and reopen the rules forbid. The flip goes on again once no row of the
launcher answers `unserved`.

A Quit Olm App row came with it, Milos's ask, a second action of the bridge host gated on
`olmAppRunning`, the piece on and the app running. Choosing it asks the app to quit, the plan's
back out as a row.

# Step 6.1, the launcher's catalog in the app

Written on 2026-11-20, once Milos put the launcher's catalog second after the keys. Today every
keystroke in the launcher asks Hammerspoon for the whole list, a round trip of 73 ms median at the
resting point. After this step typing asks Hammerspoon only for the rows made from what was typed.

## How it works

**The app builds the catalog.** It finds the applications itself, `AppScan`, the folders, depth and
rules of `host/launcher/init.lua`'s scan, and every other row, the tools, the rows plugins
contribute and Olm's own, comes from `~/.olm/run/launchercatalog.json`, which the launcher host
writes a few seconds after a load and again after every pick, `catalogShare`. The share carries each
row as data, its title, subtitle, keywords, icon, the key it is remembered by, the gate it waits on
and the item Hammerspoon runs, the subtitle an application with a chord wears closed and open,
since chords are spelled in Lua, and the recency timeline. `Catalog` orders it exactly as
`_orderedRows` does.

**Typed rows stay Hammerspoon's, and are never waited for.** The calculator, convert, Window Size
and the scopes answer from a launcher level opened with `typed`, which serves `bridgeTypedRows`, the
query sources alone. `NativeLauncher` waits 50 ms for them. Later than that the catalog is shown at
once and the typed rows are merged when they land, through the stage's own `pending` and
`rowsLanded`. A claim, a scope's word, is the whole list as before.

**Choosing still runs in Hammerspoon.** A typed row by its ref, as before, and a catalog row by the
item the share carried, the bridge's new `chooseItem`, through the same path a ref takes. Bringing
an application's windows forward goes through `lib/appfocus.lua`, which needs Accessibility, and
moving it is the app toggler's step, 6.2. Choosing happens once per open, so it costs nothing while
typing.

**Recency and the memory stay Hammerspoon's in 6.1.** A pick is recorded there as now, and the app
reads the timeline from the share and the memory as the bridged launcher already has it, so the two
launchers can never order differently and backing out loses nothing. They move to the app with the
last core step that needs them.

## The shadow, and why it moved

The launcher's shadow compared the app's ranking against what the Lua launcher settled on. Since the
flip of Hyper and Space on 2026-11-18 the Lua launcher is not the one opened, so it settled nothing
and the shadow logged nothing after that day. Now the launcher a person opens is passed through
`ShadowTee`, and each answer it settles on, once typing pauses for 400 ms, ranked by the app's own
search, is compared with what `NativeLauncher` answers for the same query, in
`~/.olm/log/shadow-launcher.jsonl` as before. The gate for the flip is that log the same on every
line through a day of use.

## The flip, 2026-11-20

The launcher a person opens is `NativeLauncher` since 2026-11-20, flipped as soon as the two catalogs
agreed on this machine rather than after a day of the shadow's log, Milos's rule that development
never waits on a measurement, rule 10 of `docs/PLAN-STANDALONE.md`. It reads the `launcherCatalog`
switch from the share at each open, `inApp`, on in `config/plugins.lua`, and while it is off it asks
Hammerspoon for the whole list as before, through the bridged launcher it keeps as its fallback, so
`false` and a reload is the way back. The shadow now runs the other way round. Each answer the
launcher in use settles on once typing pauses is compared with Hammerspoon's whole list for the same
query, `app` the launcher in use and `lua` Hammerspoon's in each line of
`~/.olm/log/shadow-launcher.jsonl`, read as the work goes on.

## Rejected

- **Porting the action rows to Swift.** 2026-11-20. Every tool's row, every contributed row and every
  chord is declared in Lua manifests and spelled by Lua, and the app needs only the answer, as with
  the keys.
- **Running an application's row in the app now.** 2026-11-20. Cycling an app's windows needs
  Accessibility, which Olm.app does not hold, and choosing costs nothing while typing.
- **Moving recency and the memory into the app now.** 2026-11-20. Two stores would have to be kept in
  step in both directions to keep backing out free, and nothing in typing waits on them, since both
  are read from what Hammerspoon already hands over.
- **Watching the application folders.** 2026-11-20, for now. The Lua side watches them with
  FSEvents. The app scans again at an open when its scan is over 30 seconds old, which costs a few
  tens of milliseconds off the main thread, and the flip may want a watcher if the shadow shows an
  app arriving late.

## As built, 2026-11-20

- Hammerspoon: `catalogShare`, `bridgeTypedRows` and `onCatalog` in `host/launcher/init.lua`, a
  `typed` launcher level and `chooseItem` in `host/bridge/serve.lua`, the share written from
  `root/compose.lua`. `docs/PROTOCOL-BRIDGE.md` The launcher's catalog has the shapes.
- The app: `app/Sources/OlmLauncher`, `AppScan`, `Catalog` and `NativeLauncher`, the bridged
  launcher's `typed` mode, `claimed` and `chooseItem`, and `ShadowTee` in `OlmCore/Shadow.swift`.
- The check: `test/olmlauncher.sh`, in `suite.sh dry`, 17 cases on the order, the gates, the bonus and
  the subtitles, and `olm-launcher-check --live`, which builds the catalog from this machine, with
  `--dump F` writing its resting order.
- **Compared with Hammerspoon's on this machine, 2026-11-20.** The resting order of both catalogs,
  `bridgeRows("")` asked of the running config against `--dump`, the same 218 rows, every key, title
  and subtitle in the same order, once the app named an application by its `CFBundleName` as
  `hs.application.nameForBundleID` does. It first took the name Finder shows, so Chrome read Google
  Chrome and Code read Visual Studio Code, and eleven applications sorted elsewhere.
