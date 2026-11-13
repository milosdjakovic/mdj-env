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

