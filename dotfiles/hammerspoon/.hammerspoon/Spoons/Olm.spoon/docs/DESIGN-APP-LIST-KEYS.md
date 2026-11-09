# How a list key reaches the app's list, step 1.4f

A design note for step 1.4f of `docs/PLAN-STANDALONE.md`, written 2026-11-09, to be agreed with
Milos before any code. It is step 3.4's shape brought forward for file search alone, on the
notifications the bridge already uses, so stage 2's socket later replaces only the transport.

## The problem

Hammerspoon holds Hyper. It decides what Hyper and J does by asking which list is open, and it only
knows about its own lists. While Olm.app's file search is up, Hammerspoon thinks no list is open,
so Hyper and J runs the global binding, the emoji picker, and Hyper with J, K, Command and J or K,
Command and Return and the rest never reach the app. The arrows, Return, Escape and the trackpad
do, because the app's own input field hears them.

## The shape

While the app's list is up, Hammerspoon treats it as an open list like any of its own:

1. The app says when its list goes up and comes down.
2. Hammerspoon's "is this list open" answers yes for file search while it is up, so every list key,
   every gate and the rule that no cheat sheet shows over an open list behave as for a Lua list.
3. A list key pressed then does not run in Lua. Hammerspoon sends the verb to the app, and the app
   runs it on its own highlighted row.

Nothing changes in `config/keymap.lua`, in the manifest or in the keys golden. The same bindings
fire, and they are answered by the app instead of by the stage.

## The pieces

### 1. The app says up and down

The app posts a distributed notification, `local.olm.Olm.state`, whenever its list shows or hides,
with the object `filesearch:up` or `filesearch:down`. It posts down on every way a list hides:
Escape, a choice that closes, a press outside and losing key.

`host/bridge` listens and keeps one flag per tool. Three guards keep the flag honest:

- **Opening.** The flag goes up the moment the served key posts its open note, before the app
  answers. A Hyper and J typed straight after Hyper and ; then still reaches the app rather than
  the emoji picker. If no `up` arrives within a second, the flag drops.
- **A quit app.** While the flag is up, the bridge also checks that the app is running, the same
  `_running()` it asks today. A crashed app cannot leave Hyper's list keys stuck on a list that is
  gone. The check runs only while the flag is up, so it costs nothing the rest of the time.
- **A reload.** A reloaded Hammerspoon has lost the flag, so at configure the bridge posts
  `local.olm.Olm.ask` and a running app answers with its current state.

### 2. "Is this list open" asks the bridge

`lib/listopen.lua`'s `isShowing` gains one question, asked before the stage: is this owner served by
the app with its list up? It is a function the root hands in, `deps.served(identity)`, answered by
the bridge. `listopen` names no plugin and no app. `anyListShowing`, the context predicates and the
leaders all read `isShowing`, so they follow without an edit of their own.

### 3. A verb goes to the app

`surfaceAdapterFor` in `root/compose.lua` gains the same branch, ahead of the stage's. While the
owner is served with its list up, every method the adapter is asked for becomes "post this verb to
the app". Two other places get the same branch: the dispatch exceptions for `showInfo` and
`openActionsPane`. Those open the info pane and the actions pane, which are the app's to draw.

The note is `local.olm.Olm.verb` with the object `filesearch:<verb>`, posted and never waited on.
The verbs are the method names `lib/nav.lua` already routes to, after `navMethodFor`:

| Verb | What the app does | Where |
|---|---|---|
| `selectNext`, `selectPrev` | moves its own highlight | this step |
| `hide` | closes the list | this step |
| `insertSelected` | the primary, Open | this step |
| `secondary` | Reveal in Finder, as Command and Return does | this step |
| `showInfo`, `openActionsPane` | opens the info pane or the actions pane | this step |
| `scrollPreviewDown`, `scrollPreviewUp` | scrolls the preview pane | this step |
| `reveal`, `copyPath` | Reveal in Finder on f, Copy Path on y | this step |
| `peekPreview` | Quick Look on q | waits for 1.4c |
| `browseInto`, `browseUp` | Into Folder on l, Up a Level on h | waits for 1.4e |

A verb the app does not know yet does nothing and is logged once, the same as `lib/nav.lua` does
for a method no surface answers. A verb naming a tool whose list is not up is dropped.

### 4. The right words and keys reach the app

The bar, the info pane and the actions pane need the words and the key caps a Lua list shows. Those
come from the same plan, read after the person's `lists` section is laid over it. At each load the
root has `host/bridge` write one share, `~/.olm/run/filesearchkeys.json`, built the way
`chooser.json` is built:

- **The bar at rest**, from `lib/hints.lua`'s `bottomBarModel` for the `fileSearch` context: the right
  side, the info pane's keys, `keysChord`, the title and the info icon.
- **The actions pane's rows**, from `rowsFor`. Each row keeps its action, title, chord, icon, section
  and the name of its `applies` gate, not evaluated.
- **The field keys**, every binding of the list that opens with no held leader: Command and Return,
  Command and ?, and any `ctrl+…` a person adds in `lists`. Each comes with its verb. The app's own
  input field answers these, since Hammerspoon's field watcher only serves the default chooser's
  field.

Each gate is answered on the side that can answer it:

- **`needs`** (`scrollablePreview`, `askedPreview`) is a choice made at load. Lua has already dropped
  any binding whose need was not met before it builds the share.
- **`applies`** (`isEntry`, `isFolder`, `isBrowsing`) is about the highlighted row, and the row
  lives in the app. File search's Swift source answers these three itself, the way its Lua
  submodule answers them for the Lua list. The actions pane leaves out a row whose gate is closed.
- **Live `when` gates.** File search's bindings carry none beyond the list being open, so a model
  written at load is exact. A list with a live gate waits for stage 2's `bar` notification, which
  `docs/PROTOCOL-BRIDGE.md` already describes. The note says so where the share is written.

The bar's labels change while the actions pane is open, with Return labelled by the lit row and no
secondary. The app works that out from the same rows, following the rule `bottomBarModel` states
for that case.

### 5. The look

The app already compiles the swift chooser's library. `native/Bar.swift` draws the bar and
`native/FloatingPane.swift` draws both floating panes, from the same model types `Model.swift`
reads for the Lua view. So the app hands them the share's words, and nothing of the look is written
again, which rule 9 requires.

## What goes away in the app

`Stage.listKey` answers plain Command and J or K by scrolling the preview pane, and plain Command
and Return by looking up a chord in the manifest. Both were stopgaps. In the Lua list the scroll
keys are Hyper with Command and J or K, and plain Command and J does nothing. Once verbs arrive the
scroll comes as a verb, and Command and Return comes from the share's field keys, so both stopgaps
are removed. Command and a digit stays the field's own, as the protocol says.

## How it is tested

- **The keys golden stays unchanged.** No binding moves.
- **Unit cases over fakes, in the dry gate.** `test/rootmechanism.lua` pins `listopen.isShowing`
  with a fake `served`, and `listopen.servedOpen`, which the two pane verbs ask. `test/bridge.lua`
  pins the flag: up, down, the one second opening window, a down from the list before, the quit
  app, the ask on reload and the verb note.
- **The app's half in the hand trial.** The note first said `test/olmapp.sh` would check that a
  posted verb moves the app's highlight. That was corrected on 2026-11-09 while building. A list
  that is up is a window on screen, and that script shows none, so the app's up, down and verbs are
  checked by hand.
- **A hand trial for each build piece**, given as numbered steps with expected results, after Milos
  says go.

To back out, set `serves = {}`. With no served tool the bridge answers no for every identity, and
everything runs as today.

## The build, in pieces

1. **The keys.** Up and down, the bridge's flag, the `listopen` and adapter branches, and the verb
   note with the move, close, open and secondary verbs. This piece is done when Hyper and J and K
   move the app's list.
2. **The bar and the info pane**, from the share.
3. **The actions pane**, with Copy Path, Reveal in Finder on f, and the scroll keys.
4. **Command and a digit**, checked against the Lua list.

## Decided

Milos agreed the note on 2026-11-09 and left these three to whatever best guarantees speed and
consistency. All three were taken as proposed.

1. **The one second opening window**, where the flag goes up before the app confirms. A Hyper and J
   typed straight after Hyper and ; always lands in the app, never in the emoji picker.
2. **A share written at load** rather than a bar model sent live. Nothing crosses per keystroke or
   per highlight, and the words come from the same plan the Lua list reads. It is exact for file
   search today, and stage 2 brings the live version for a list with a live gate.
3. **Dropping the app's plain Command and J or K scroll**, so the app answers exactly the keys the
   Lua list does.
