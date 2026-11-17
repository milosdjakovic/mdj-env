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

## Corrected after piece one's trial

Piece one passed Milos's trial on 2026-11-09 except the scroll keys. The preview pane scrolls on
Hyper and D or U in file search and in the clipboard, no longer Hyper with Command and J or K, and
the clipboard's Delete moved first to Hyper and Backspace and then, since that press never reaches macOS on this machine, to Hyper and R, the key every list's Delete now takes, one that declares confirm asking first. Wherever this note names Command and J or K as
the Lua list's scroll keys, read D and U. The verbs, `scrollPreviewDown` and `scrollPreviewUp`, are
unchanged, so the app needed no edit.

## How piece two was built

The share is `~/.olm/run/<tool>keys.json`, written by `host/bridge`'s `shareEach` for each tool it
serves, built by `lib/hints.lua`'s `appShare`. It holds `bar`, the swift view's own flattening of
`bottomBarModel` with each action already the verb the app runs, and `fieldKeys`, each a key code,
its modifiers and its verb. The info icon crosses as a PNG data URL, drawn by the same resolver the
Lua bar uses, so the icon set a person picks reaches the app too. The bar is read in Swift by one
reader over `Fields.swift`'s protocol, which Hammerspoon's panel now reads through as well, so the
two cannot read it two ways. The field keys replace the app's own Command and Return, and Command
and ? opens the info pane as it does in the Lua list. The actions pane's rows are piece three.

## How piece three was built

The share gained two fields. `actions` is `rowsFor`'s answer for the context, flattened by the
swift view as it sends the Lua pane's rows, each icon a PNG data URL, with the verb, the name of its
`applies` gate and whether it confirms or offers choices. `panelBar` is `bottomBarModel` with the
pane open, so the open bar follows the Lua rule, and the app writes the lit row's title into its
Return label. Both are read through `Fields.swift`, whose row reader Hammerspoon's panel now reads
through too. The gates are a new `ListSource` word, `applies`, which file search answers in Swift.
It answers no for `isFolder` and `isBrowsing` until the app's folder search, 1.4e, so Into Folder
and Up a Level stay off the app's pane until then, and Quick Look is not one of the source's
actions until 1.4c, so its row is left out too. A row the app cannot run is never listed. A verb
that confirms or offers choices opens a level in the Lua pane, which the app has not built, and
file search declares none. Copy Path is a new effect, a plain clipboard write.

The stage holds the pane the way `host/actionspane` does. The field is cleared as it opens and
filters its rows by the shared search, the list's text and highlight are kept and given back as it
closes, and a chosen row closes the pane first and then runs on the row it opened over. Moving,
Return and its own key are the pane's, a key on a verb it lists chooses that row, and any other
key, a scroll or a press behind it closes it, as the Lua pane now does.


## The actions pane's own input field

Asked by Milos in piece three's trial, for every list. The actions pane searches in an input field
of its own, its bottom line with no rule above it, at the size of the pane's rows, its text starting
exactly where the rows' icons do, its placeholder Search Actions, and the caret moves into it while
the pane is open. Typing that filters out every row leaves one dimmed line, No results, left aligned
where the first row would be, so the list's input field keeps
showing the text the pane opened over. Both fields are one field made customizable, handed a look.
In Swift that is `native/InputField.swift`, the list's field and the pane's foot both made from it,
the panel routing every key and every edit to whichever has the caret. On the canvas it is
`field/render.lua`, which already drew any rect in any style, now drawing the pane's foot too.

The engine still holds one text. The actions pane still clears it on opening and gives the list's
text back on closing, which no person sees any more, since the list's field draws the held text the
bar model carries, `panelField`, from `host/actionspane`'s `paneField`. So nothing in the engine, the
pane or the claim changed, only where each view draws the text. The app's stage hands the panel the
same held text, and the share carries the placeholder on the open bar.

## How piece four was checked

Command and a digit was already the app's own, and piece four held it against the Lua list's
`leftoverKey` and `_chooseSlot`. Both choose the first nine rows by place, never by what is on
screen, and do nothing past the last row, and both close the info pane. Three things differed. The
app chose only where the list showed its numbers and the Lua list always does, so the app now always
does. The Lua list moves the highlight onto the row before choosing it, so the app does too. And over
an open actions pane the Lua list chose the pane's row in that place, rows that carry no number,
while the app closed the pane and chose the list's. Milos chose the app's answer on 2026-11-10, the
pane rule of 2026-11-09 applied to the digits, so the Lua engine now closes the pane first,
`test/swiftview.lua` pinning it.

The trial found one more thing. A pane closed by the key that also closes the list started folding
onto the bar and the list's fade cut the fold halfway, so such a pane now goes down whole with the
list. The app's stage leaves the panes standing until the row's answer is back and closes them only
when the list stays up, and the swift panel's hide takes back a fold that has drawn no frame yet,
ShapeMotion's `takeBackUnplayedClose`, which covers the Lua engine closing both in one turn.

## Step 3.4, the keys of a list pushed in the app

Written on 2026-11-17, built the same day on Milos's go.

**What is already done.** Most of 3.4 landed earlier, piece by piece:
- 1.4f: a served tool's list keys reach the app's list through `lib/nav.lua`, the app saying up and
  down and Hammerspoon posting each verb.
- 3.3c, brought forward on 2026-11-16: the launcher's own keys reach the app's launcher.
- 3.3: a hosted list's keys reach it while it is the app's top level, `_hostOf` in
  `host/bridge/init.lua` sending them to the launcher it sits in. Its own verbs and its field keys
  run there too, as Milos's trials of 3.3b to 3.3e showed.

**What is wrong today.** 3.3e pushes the app's own File Search over the launcher, and its own keys
do not reach it:
- The app still says the launcher is up, so Hammerspoon treats the launcher's keys as the live ones.
- File Search's own Hyper keys, Reveal in Finder, Copy Path, Into Folder, Up a Level, Quick Look and
  the preview pane's scroll, are bound only while File Search's list is up.
- So they do nothing, or fall through to their global meaning. Hyper and F opens its app, and Hyper
  and U opens Tmux Sessions.
- The field keys already work, Command and Return revealing the file, since the app reads them from
  the share of the list on top.

**What this step does.**
1. **The stage says which list's keys are live.** A list pushed over another whose keys Hammerspoon
   serves itself, a tool in `serves`, is told up as it is pushed, and the list under it down. On a
   pop, the one under it is told up again. A hosted Lua level keeps the launcher up, as today, since
   its keys go through the launcher.
2. **Which tools Hammerspoon serves** the stage is handed by `main.swift`, the same `serves` share
   it keeps warm, so the stage names no tool.
3. **A verb is run on the list on top.** It already is, since `Stage.verb` runs on the top source,
   and is checked against the tool now told up.

Nothing changes on the Lua side. File Search's context opens on its up as it does on its own key.

**What the build changed from the draft.** No offline check of the stage's tell, since the stage
only acts through its window. It was checked live instead, with the guarded driver and
Hammerspoon's own `showing`. File Search pushed over the launcher read File Search up and the
launcher down, Backspace gave the launcher back up, `st ` kept the launcher up with Speed Test
hosted on top, and Escape left both down. Copy Path sent as File Search's verb copied the path and
closed the window, as on its own key. The keys golden is unchanged.

**Not in this step:** a native list other than File Search, since no other tool is in `serves`.

**Tests.**
- `olm-bridge-check`, or a check beside it over the stage's tell: a push of a served tool says it
  up and the launcher down, a hosted push says nothing, and a pop gives the launcher back.
- The keys golden is unchanged, since no binding moves.

**The trial on Hyper and 0, once built:**
1. Type `/` and press Return on File Search, then type a name. Expect File Search with results.
2. Press Hyper and J, then Hyper and K. Expect the highlight to move down, then up.
3. Press Hyper and F. Expect the highlighted file shown in Finder, and no app opened.
4. Press Hyper and Y, then paste somewhere. Expect the file's path.
5. Press Hyper and D, then Hyper and U. Expect the preview pane to scroll down, then up.
6. Press Hyper and O. Expect File Search's actions pane. Press Escape.
7. Press Backspace until the launcher is back, then Hyper and J. Expect the launcher's highlight to
   move.
8. Type `st `, then Hyper and J and Hyper and O. Expect Speed Test's highlight to move and its
   actions pane to open, as before.

What can go wrong, and what to tell me:
- A key at step 3, 4 or 5 opens an app or a tool. Say which key.
- After step 7 the launcher's keys stop working.

## Step 3.4's trial, the preview pane appearing whole

Written on 2026-11-17 from Milos's trial of 3.4, revised the same day with his answers, and built
the same day on his go.

**The actions pane stays as it is.** Milos first asked for Hyper and O to behave the same in every
list. His answer settled it: a list whose actions pane would only repeat Return and Command and
Return hides it, and that must be decided by Olm's code, never by a rule in a plugin. That is the
rule already in force since 2026-11-02, `hints.dropIdleActionsPanes`, read from every manifest's
declared verbs once per load. So nothing changes. A list with verbs of its own where Hyper and O does
nothing would be a defect, to be reported by name.

**What Milos saw.** File Search opened inside the launcher widens the window for its pane. The pane
stays empty while the window widens, and its content lands right at the end, with a visible jank. He
asks that the content be prepared away from the main thread and shown as soon as it is ready, even
while the window is still widening, with a quick fade. Snappy over smooth.

**What is known.** The app reads the preview and lays it out off the main thread already. The main
thread then turns the layout into the pane's elements, decodes the pictures, lays out the text in
the pane's scroll view and draws it. If that lands while the window is widening, it competes with
the motion's frames. This is the likely cause, and not yet measured.

**What this step does.**
1. **Measure first.** Time the main thread around the pane's first draw while the window widens,
   with the probe the swift chooser uses, `native/Perf.swift`. Report what took the frames before
   changing anything.
2. **Prepare everything off the main thread.** The elements, the attributed text and the decoded
   pictures are built in the preview task. The main thread only installs what is ready, so it is on
   screen as soon as it is read, widening or not.
3. **A short fade.** New content, and the empty state, fade in over a new `paneContent` timing in
   the `motion` block of `config/settings.lua`, about 120 ms. A repaint of the same row, a picture
   landing, stays in place with no fade.
4. The fade lives in the shared native pane, so the swift chooser in Hammerspoon gets it too.

If the measurement shows something else took the frames, the note's build section says what, and
the fix follows the measurement.

**What the measurement found, and what was built.**
- The pane's own drawing was never the cost, never over 1 ms.
- The preview came late. After the push, the first rows took about 95 ms, then the 60 ms settle a
  moving highlight waits, so the preview landed as the widening ended. A pushed list's first rows
  are now described at once, and the preview lands 20 to 30 ms before the widening ends.
- Most of each stall was AppKit setting the cursor again on every frame of the window's new shape,
  through the accessibility cursor generator, which draws the cursor image anew. The window's
  cursor rects are off for the reshape, in `ReshapeMotion`. Over five warm pushes each, a widening's
  stalls went from about 61 ms to 44 ms. Ignoring the mouse for the reshape as well changed nothing
  and was taken out.
- What is left, one or two stalls of 30 to 50 ms a widening, is AppKit composing the window at its
  new shape. The source and the searcher already run off the main thread. Removing it would mean
  widening the window another way, for Milos to decide.
- The probe stays: `OLM_PERF=1` on Olm.app's launch, `open --env OLM_PERF=1`, writes the main
  thread's notes to `~/.olm/cache/perf.log` on each hide.

**Tests.** `test/swiftpane.sh` for the fade, and the probe's numbers before and after.

**The trial, once built:**
1. On Hyper and 0, type `/` and press Return on File Search. Watch the window widen. Expect the
   pane's content to appear quickly, fading in, with no stutter at the end of the widening.
2. Move the highlight down a few rows. Expect each preview to fade in quickly, and no flicker.
3. Open File Search on its own key. Expect it to open as before.

What can go wrong, and what to tell me:
- The stutter at step 1 remains.
- The fade feels slow, or a preview flickers at step 2.
