# Hosted lists over the bridge, Caffeinate first, step 3.3

A design note for step 3.3 of `docs/PLAN-STANDALONE.md`, written on 2026-11-15, given Milos's go the
same day and built as below. Its one question, the window's height for Keep Awake's one row, was
answered first and built on its own, `docs/DESIGN-FIT-HEIGHT.md`. Where the build chose differently
from the first draft, the push asked rather than recorded, the text says so.

Step 3.2 left the app's launcher on Hyper and 0. A row that leads to a tool's own list, Keep Awake
among them, answers `unserved` there and stays put. In this step that row replaces the launcher's
rows in place with the tool's list, inside the app's window, as the Lua stage does today. Only
Keep Awake is served. Every other tool stays `unserved` until its own step, and Hyper and Space
still opens the Lua launcher.

## Why Caffeinate first

It is the plan's choice. Its list is one row computed from what is typed (a time, a span, or
"indefinitely"), and its only stage words are a redraw when a timed session ends and its own key's
open. It has no preview pane, no actions and no child levels, so it proves the road, not the
plugin.

## What a person sees

1. Hyper and 0, type `keep`, Return on Keep Awake. The launcher's rows give way to Keep Awake's one
   row in the same window, and the window glides down to that row as the Lua one now does. The
   input field empties and the placeholder changes.
2. Type `2h`. The row reads "Keep Awake for 2 hours". Return keeps the Mac awake and closes the
   list.
3. Backspace on the empty field goes back to the launcher's rows, with what was typed there before,
   the window gliding back to its full height.
4. While Keep Awake is up and a timed session ends, its row changes to match, as the Lua list's
   does.

Typing `k 2h` straight into the launcher, the scope, already runs through 3.1's road, since a scope
row that only runs is no list replacement. The trial checks it, and the window fitting the claim
the way the Lua launcher's now does, below.

## How it works

### The Lua side, a stage facade

The protocol already says it: while a bridged request runs, the stage words a handler calls are
recorded as effects instead of acting on the Lua stage.

1. **A small facade in the bridge host**, `host/bridge/facade.lua`, pure. `facade.during(fn)` runs
   `fn` with recording on and answers the effects in order, and what `fn` answered.
2. **The words that can cross.** Today that is `redrawPresented`, the word Caffeinate uses when a
   session ends. The root's word asks the bridge host's `presentedRedraw` first:
   - while a bridged request runs a hosted list's code, it records
   - otherwise it sends the `effects` notification, below, and the Lua stage's redraw runs as before
3. **The launcher's push is asked, not recorded.** The first draft wrapped the row intercept's
   `push` too. The launcher's `bridgeChoose` asks `lib/rowintercept.lua`'s `presentationFor`
   instead, what the row would push and nothing else, so the intercept never runs, since an alias
   row's seed or a scope's act run on the way would act on the Lua stage. A presentation the config
   hosts is promoted as the Lua intercept promotes it and answered `present`, and serve opens a new
   bridged level for it. It answers the effect `push {parent, level}`, the level carrying the
   presentation's own fields: its name, placeholder, `ranking` ("source" for Caffeinate, whose
   matcher is false), `rowLimit` and `fit`.
4. **Any other row that becomes a list**, a tool not hosted, an alias or a scope's word, answers
   `unserved`, as today, and runs nothing.
5. **What is served** is a list in `config/plugins.lua`, beside `serves`: `hosts = { "caffeinate" }`.
   Each later step adds one name.
6. **A presentation level in `serve.lua`** answers:
   - `rows`: the presentation's rows for the query, with icons stamped by the root's
     `stampIcons` as the Lua stage stamps them. Disabled rows cross as disabled.
   - `choose`: the presentation's `intercept`, then its `onSelect`, run inline as the Lua stage runs
     them. A true intercept asks the rows again, `"stay"` holding the highlight, a child
     presentation pushes, and nothing answered hides.
   - `back`: the presentation's `back`, answered `{handled, effects}`. It declines when it has
     none, and the app pops.
   - `close`: forgets the level.
7. **A redraw from outside any handler**, Caffeinate's session ending, goes as the `effects`
   notification with `rows {hold:true}`. It goes only while a bridged level shows that
   presentation, and the Lua stage's own redraw runs as before.
8. **The keys share**, the bar and the info pane, is written for each hosted tool as for the
   launcher, so Keep Awake's bar says Confirm.

### The app side, a stack of levels

1. **The stage gains a stack.** A `push` effect asks the source that answered it for the child
   source it names, `pushed`. The bridged launcher makes a `BridgedLevel` for the level the effect
   carries, a ListSource like the launcher's without the memory, both reading the wire through one
   `RowStore`. The stage parks the parent's source, level, text, highlight, rows and height, and
   shows the child in the same window: field emptied, placeholder and bar changed, rows asked.
2. **Backspace on an empty field** sends `back`. When the level declines, the stage closes the
   child level and gives the parent back as it was parked, its rows drawn at once and its height
   with them, then asks its rows again keeping the highlight.
3. **Return in a child** is `choose` with the same effects as 3.2: hide first, `after hidden`,
   `requery`, a deeper `push`, and `rows` re-asking the rows (`hold` keeps the highlight on its row).
4. **The `effects` notification** reaches the source that holds the level it names, and that
   source asks the stage to redraw it when it is on screen.
5. **The list's height** follows `fit`, the level's own and, in the launcher, the claim's. A rows
   answer carries `fit` while a scope whose tool fits claims the query, the same answer the Lua
   launcher hands its stage, and the stage places by `fitRows` as it does for a level that fits.
6. **Closing the window** closes every level on the stack, top first.

## What has to grow for it

- Lua:
  - `host/bridge/facade.lua`
  - `serve.lua`'s presentation level, `back`, and the `effects` notification
  - the root wrapping `push` and `redrawPresented`, and handing over `stampIcons`
  - `config/plugins.lua`'s `hosts`
- Swift:
  - a stack in the stage
  - `Effect.push` and `rows`
  - `BridgedLevel`
  - the bridge's level and rows answer read into `Level.fit` and a claim's fit
  - the bridge routing `effects` to a level's source
- The protocol: the `push` of 3.3 and "What 3.3 serves", in the same way 3.1's section reads.

## Tests

- `test/bridgeserve.lua` checks the facade:
  - a push recorded as an effect while a request runs
  - a push outside a request reaching the Lua stage
  - an unserved tool answering `unserved`
  - Caffeinate's level answering rows, choose with hide, and back declining
  - a redraw notification only while its level is open
- `test/fixtures/bridge/` gains a hosted case.
- `olm-bridge-check` checks the stack:
  - a push shows the child source
  - `back` declined pops back to the parent with its text and highlight
  - an `effects` notification reaching the right source
  - closing closing every level
- Live, by hand, a numbered trial of the four things a person sees above, and `k 2h` from the
  launcher. The shadow log is read before and after.

## Volume, the second tool

Added on 2026-11-15 with Milos's go. Volume asks nothing the road above lacks: one row computed
from what is typed (a level from 0 to 100, mute or unmute), `fit`, matcher false, no preview pane,
no actions, no child levels, and no stage word but its own open, not even a redraw. So it is one
name more in `hosts`, `{ "caffeinate", "volume" }`.

- An empty field, a level above 100 or below 0, a fraction or a word that is neither mute nor
  unmute is a disabled row, and Return on a disabled row answers no effects, as 3.1 serves it.
- Return on a level sets it, unmutes above zero, and closes the list.
- A change of the volume from the keyboard while the list is open is not redrawn until the next
  keystroke, the same as the Lua list, since the plugin watches nothing.
- `test/bridgeserve.lua` drives the real plugin over a fake output device. No fixture case was
  added, since the hosted case already replays the same road over a fake presentation.

## 3.3a, open and close

Written and built on 2026-11-15 with Milos's go, the first of the five steps that finish 3.3:
open and close, the actions pane, the stage words, the preview pane, and file search answered by
the app's own list.

A presentation's `onPresent` is what starts the work its rows read, Wi-Fi's scan and the device
reads of Audio and Input Sources, and the Lua stage tells it on every push. A hosted level was told
nothing, so its rows read whatever the last Lua open left. Now `serve.lua` tells it the same way:

- `onPresent` when a level opens, from the launcher's push and from a child a hosted level pushes.
  Never when a parent is given back, as the stage's pop tells none.
- `onClose` on the level's `close`, which the app sends for a child it pops and for every level as
  the window closes.
- Both run under the facade, so a stage word either calls acts on the app's list and not on the
  hidden Lua stage. What they record is dropped: the app asks the rows of a level it just opened,
  and a closed level has nothing to redraw.
- A new session's `hello` and a socket that went close every level the last session left, each
  hosted one told its `onClose` top down, since the app that held them is gone.

`hosts` gains `audio`, `wifi` and `inputsources`. Audio's Return switches a device and stays, the
intercept's `"stay"` that 3.3 already serves. Wi-Fi's scan landing redraws through
`redrawPresented`, served since Caffeinate. A join that needs a password asks in the system's own
dialog, deferred until the list is gone, as it does from the Lua list.

Dock Auto Hide needs nothing. Its launcher row toggles rather than leading to a list, so it runs
through 3.1's road and is not named in `hosts`.

## 3.3b, the actions pane

Written and built on 2026-11-15 with Milos's go. Tmux Sessions and VPN each carry one keyless verb
in their actions pane, Terminal and Provider, and each opens a level of choices.

- **The Lua side.** `serve.lua` answers `actions`, `choices` and `run` for a hosted level, the
  protocol's "What 3.3b serves". The root hands the bridge `verbs`, which reads the list the tool
  owns with `lib/hints.lua`'s `rowsFor`, the same rows the keys share is written from, asks a verb's
  `applies` and `choices` through the actions pane's own `call`, and runs a verb on the tool's
  surface by its owner, never the dispatch table, which routes by the list showing and the list
  showing is the app's. All three run under the facade.
- **The app.** The pushed level names its actions, so the stage keeps them in the pane. A source
  may answer `actions(on:)`, which the stage reads in place of the share's applies gates and labels,
  nil for file search's native one. A verb with choices or a confirm opens a level inside the
  actions pane, headed with the verb's title, its rows asked with `choices`. Return on a choice runs
  the verb with it and closes the pane, a dimmed one does nothing, and Cancel or Backspace on the
  pane's empty field goes back to the verbs.
- A verb's own key over the bridge, `key`, is not served. Neither tool has one, and Emoji's Command
  and Return copy is the first, at 3.3c.

The launcher on Hyper and 0 has no actions pane to add. Its only action would repeat Run, so the
Lua launcher carries no Actions either, `hints.dropIdleActionsPanes`.

`hosts` gains `tmuxSessions` and `vpn`.

## 3.3c, the stage words

Written and built on 2026-11-15 with Milos's go. Emoji's Copy reads the selected row and hides the
list, and Browser Tabs' settings page has a Back row that pops its own level.

- **The Lua side.** The facade carries the request's own context, its row, place and query.
  `host/bridge/init.lua`'s `hostedWord` answers the words that read the list from it and records
  the words that change it, and the root's words ask it first, through a helper at the file's own
  scope, since the root's function is at the 200 locals Lua allows. `serve.lua`'s `effectsOf` makes
  what was recorded into the effects for the level the request ran on, the protocol's "What 3.3c
  serves".
- **The app.** It applies `pop`, closing the level that answered it and giving the list below back
  as Backspace does, and `setQuery`, which writes the field and searches.
- **Emoji's Command and Return** reaches Lua with no `key` request. The keys share names it as the
  field key of `copySelected`, the pushed level names that action, and the app runs it as 3.3b's
  `run`.
- **A row keyed by its value.** A hosted row was keyed by its item's table, so Emoji's glyph rows,
  whose item is the glyph itself, were given new keys on every answer and every keystroke sent all
  5648 again, 0.9 MB. Measured live on 2026-11-15 after the fix, the first open sends them once,
  88 ms to build and 105 ms to encode on the Lua side, and a keystroke 56 bytes, the Lua side still
  rebuilding and comparing the rows in 60 to 84 ms, about what the Lua list spends rebuilding them.
- Insert pastes into the app underneath as it does from the Lua list, its paste delay standing
  between Return and the paste. Should it land in the wrong place, Insert waits for `hidden` as the
  launcher's runs do.

`hosts` gains `emoji` and `browserTabs`.

## 3.3d, the preview pane

Written on 2026-11-16 and built the same day with Milos's go, as below, with three changes from the
draft said at the end. Speed Test is the tool. Its list is a flat list,
and its preview pane draws every figure a run returns, a live curve while a run is going, a
finished run, and a network's trend. Its actions pane holds settings with choices, Name This
Network, which opens an input level, and two clears that ask first and show only when there is
something to clear. Everything but the pane is served already: choices, confirm and `applies`
since 3.3b, and `stagePush` and `stagePop` since 3.3c. So this step is the pane, as
`docs/PROTOCOL-BRIDGE.md` "The preview pane" describes it.

- **The plugin is unchanged.** Speed Test still draws through `pane.show` and `pane.clear`, from
  its own `onHighlight` and from the run's ticks.
- **The Lua side, a bridge backend.** `lib/previewpane.lua` already takes its drawing backend as
  a strategy. The bridge gets one more backend, which says it scrolls natively.
  - Its `render` sends `paneDrawn` with the content elements, the content height, and the `h`
    and `ref` of the highlight Lua was last told. It leaves out the surface, because the app
    draws its own glass.
  - Each element crosses as the protocol says:
    - A styled text becomes a Text: its string, font, size, colour, alignment and line break.
    - A picture becomes a PNG data URL, the way the bar items cross.
    - A colour becomes its red, green, blue and alpha values.
- **Choosing the backend.** The root's pane grant wraps the backend it picks today in a router,
  one per plugin. The router draws through the bridge while `bridge:hosting()` says the app
  shows that plugin's level, and through today's backend otherwise. When it switches, it hides
  the backend it leaves. The plugin never learns which backend draws.
- **What the app sends.** These are the three notifications the protocol already names:
  - `highlight`: when the highlighted row changes, and when a level opens or comes back to the
    top.
  - `positioned`: carries the pane's frame. `paneFrame` null hides the pane.
- **What Lua does with them.** It calls the presentation's `onHighlight` and `onPositioned`
  under the facade. It keeps the latest highlighted item, so `stageSelectedItem` outside a
  request answers the app's row while the app shows the level. Today that word reads the hidden
  Lua stage, the open question 3.3c left. Speed Test's run ticks read it to know whether the
  running row is still highlighted.
- **The level opens with its pane.** `pushLevel` sends `previewPane` true and
  `previewPaneWidth` from the presentation's own member, so the app reserves the same width the
  Lua list does.
- **The app draws what Lua drew.**
  - A JSON element reader, the counterpart of `PaneReader` in `native/Lua.swift`, turns elements
    into the `PaneElement`s that `PanePanel` already draws, curves and strokes included.
  - `PaneHost` hands them to the pane at the content height. It keeps the scroll offset when
    `keepScroll` says so, which is how a ticking run stays where it was scrolled.
  - The app drops a `paneDrawn` whose `h` is older than the level's.
  - The pane's scroll keys, Hyper with D or U, are the app's already, so they scroll natively.
- **Not in this step:**
  - `clicked`, since Speed Test has no element that takes a press.
  - Any pane the app draws itself. File search keeps its own native preview, which is 3.3e.

`hosts` gains `speedtest`.

**What the build changed from the draft.**
- A list pushed over the launcher kept the launcher's placement, so the window had no pane for it.
  The stage now places the window again on a push and on a pop when the pane changes, and tells a
  list whose pane is drawn in Lua where it stands each time.
- `scrolled` is not sent and `{"empty":true}` is not used. Under the native scroll the Lua view's
  offset is always zero, so `scrolled` would change nothing, and the Lua pane's empty state crosses
  as elements like any other paint.
- A rebuilt list whose highlighted row keeps its key with a new item tells `onHighlight` again, as
  the Lua chooser's refresh does after every rebuild. Found in the live check.

**Tests.**
- `test/bridgeserve.lua`:
  - `pushLevel` sends the pane width.
  - `highlight` calls `onHighlight` once per change of row.
  - The router sends `paneDrawn` while the app hosts the level and draws through the Lua backend
    otherwise.
  - A text, a picture and a colour each cross in their protocol form.
  - `stageSelectedItem` answers the app's row between requests.
- `olm-bridge-check`:
  - It reads a recorded Speed Test `paneDrawn`, curve included, into the elements `PanePanel`
    draws.
  - It drops a `paneDrawn` with a stale `h`.
  - It sends `highlight` and `positioned` when a level opens and when the highlight moves.

**The trial on Hyper and 0, once built:**
1. Type `st` and open Speed Test. Expect the list with the pane beside it, at the Lua list's
   width.
2. Move the highlight over a past run, then over the network row. Expect the run's figures, then
   the trend. Each lands as the highlight moves.
3. Start a run. Expect the curve to draw live and the figures to tick. Move the highlight away
   and back while it runs, and expect the live view to come back.
4. Scroll a finished run with Hyper and D or U, and with the trackpad. Expect it to scroll
   smoothly and stop at the end.
5. Open the actions pane, set Direction, then Clear This Network. Expect the confirm level, and
   the clear to show only on a network that has runs.
6. Run Name This Network, type a name and press Return. Expect the network row to show the new
   name.
7. Switch the system to light mode with the list open. Expect the pane to follow on the next
   paint.

What can go wrong, and what to tell me:
- The pane stays empty or keeps showing the previous row. Say which step.
- The curve stutters. Say whether the run's figures still tick.
- Text in the pane looks different from the Lua list, its font, colour or wrapping. A screenshot
  of both helps.

## 3.3e, file search and the typed word

Written on 2026-11-16, built on 2026-11-17 on Milos's go. The last step of 3.3.

**What is wrong today, in Hyper and 0:**
- File Search's row answers `unserved` and stays put. File Search is not in `hosts`, and it
  must never be. The app has served File Search itself since 1.5's flip, so a Lua list of it
  inside the app would be the old one.
- A typed word that hands its list over does nothing. In the Lua launcher, `/` and a space, or
  `st` and a space, push that tool's list with the word kept in the field, since a list with a
  preview pane has no scope rows of its own. Over the bridge the hand over is dropped, because
  the Lua launcher is not on screen. So the app shows the scope's plain rows with no pane: the
  file search rows Lua answers, or Speed Test's rows without its pane.

**What this step does:**
1. **The row.** `bridgeChoose` asks the bridge whether the app serves the row's tool itself,
   `serves`, before it asks `hosted`. If it does, the answer is a new effect,
   `{"native":{"name":"filesearch"}}`. The app pushes its own file search source over the
   launcher, the same push a hosted level takes:
   - The window is placed again with File Search's own pane.
   - Backspace on the empty field goes back to the launcher.
   - Escape closes both.

   Nothing of File Search runs in Lua.
2. **The typed word.** A `rows` answer whose claim hands over carries `handOver`, the level to
   push and the word typed:
   - `{"native":{"name":"filesearch"},"prefix":"/ ","query":"foo"}` for a tool the app serves.
   - For a hosted tool, `{"push":{level},"prefix":"st ","query":""}`, the level opened as
     Return on its row opens it.

   The app pushes it when the answer lands, and only while that query is still the field's text,
   so typing on past it hands nothing over.
3. **The word stays in the field, as in the Lua stage.** The app stage gains a level prefix, the
   Lua stage's `prefix` on a push:
   - The field shows `/ foo`, and the source is asked only `foo`.
   - Deleting into the word gives the launcher back with the field at what is left, `/`.

   Without this the field would show `foo` alone, and Backspace would behave differently from
   the Lua list.

**What the build changed from the draft.**
- `bridgeChoose` is unchanged. serve.lua hands it a `shows` that answers true for a tool the app
  serves or hosts, so the row answers `present` as a hosted tool's does, and `pushes` turns it into
  `native` where the app serves the tool and into `push` where it hosts it.
- The hand over is a table QueryScope answers in place of the bare function, still callable, with
  the rest, the word and `handOverTo`, the presentation the root names on the scope. The bridge
  reads those and never calls it, and `bridgeRows` asks quiet, so no timer is scheduled.
- A hosted level a hand over opens is opened once per query, and the app closes one it never
  pushed, when the next answer names another or none, or when the launcher closes.
- The prefix is checked by a shared fixture, `test/fixtures/stage/prefix.json`, run by the Lua
  stage's `_strip` and by `Stage.strip`, rather than in `olm-fixtures` alone.

**Not in this step:** File Search's own keys over the launcher (reveal, copy path, browse a
folder) beyond what the app's native list already answers. Its native list already carries its
own actions pane and keys, so this costs nothing new.

**Tests.**
- `test/bridgeserve.lua`:
  - A served tool's row answers `native`, and a hosted tool's row still answers `push`.
  - A claim that hands over carries `handOver` with its prefix and the rest typed.
  - A claim that does not hand over carries none.
- `olm-bridge-check`:
  - `native` becomes a push of the source the app holds under that name.
  - `handOver` pushes it with the prefix.
  - An unknown name pushes nothing and is logged.
- The stage's prefix is checked where its search already is, in `olm-fixtures`. It shows in the
  field, is left out of the query, and a delete into it pops.

**The trial on Hyper and 0, once built:**
1. Type `file`, highlight File Search and press Return. Expect the app's own file search in the
   same window, with its pane, its placeholder and its recent files.
2. Type a name. Expect results with previews, as on File Search's own key.
3. Press Backspace until the field is empty, then once more. Expect the launcher back.
4. Type `/ ` and then a name. Expect File Search to take over, with `/ name` still in the field
   and its pane beside it.
5. Delete back into the `/`. Expect the launcher, with `/` in the field.
6. Type `st `. Expect Speed Test with its pane, `st ` kept in the field.
7. Press Escape. Expect the whole window to close.

What can go wrong, and what to tell me:
- The window jumps or flickers as File Search takes over from the launcher. Say at which step.
- The field loses or doubles the typed word at step 4 or 6.
- Backspace at step 3 or 5 closes the window instead of giving the launcher back.

## 3.6, every row the launcher leads to

The flip of Hyper and Space, step 3.5, was held on 2026-11-17 because a launcher row leading to a
list the app does not show answered `unserved`. This step leaves no such row. It was found by
asking the live launcher, row by row, what Return would do in the app, with no screen touched. 23
rows replace the list. Ten were hosted already or File Search's own. The other 13 were:

- Ten tools not in `hosts`: Clipboard History, Display Profiles, Obsidian, Text Case, Workspaces,
  Local Servers (processes), Olm Chooser, Olm Placement, Olm Plugins and Olm Theme.
- Olm Keys, a page carrying the launcher's name, `launcher`.
- Olm Aliases, a row that types `? ` into the field rather than showing a list.
- Typed scopes were asked too. Only the Dock's, `d `, has rows that act in place, its two
  switches, and those answered `unserved` as well. Every other scope's rows run after the app
  hides, as before. Menu Search has no launcher row and is reached by `m `, whose rows run.

Each of the ten tools was then pushed as a hosted level inside the running bridge and asked for
its rows, again with no screen. Every one answered, with its preview pane, its actions and its
Command and Return where it declares them, since 3.3b to 3.3d carry those for any hosted list. So
they need nothing but their names in `hosts`.

**What grows:**
- `lib/rowintercept.lua` gains `inPlace(item, deps)`. It says what `forRow`'s callable would do,
  `{ present }`, `{ seed = word }` or `{ act = fn }`, and does none of it. The root hands it to
  the launcher as `rowInPlace`.
- `Launcher:bridgeChoose` asks it. A hosted presentation answers `present` as before. A word
  answers `setQuery`, which the app already applies by typing it and asking the rows again. An
  act runs at once and answers `rows` held, which the app already applies by redrawing the list in
  place. Both are what the row does in the Lua launcher. A row the app still cannot show answers
  `unserved` as before.
- `hosts` gains the ten tools and `launcher` for Olm Keys.

Nothing in the app changes.

**Tests:**
- `test/rootmechanism.lua` pins `inPlace` beside `forRow`, and that asking does nothing.
- `test/cases/launcher-bridgechoose.lua` pins every answer of `bridgeChoose`.

**The trial on Hyper and 0, once built:**
1. Choose Clipboard History. Expect its list and preview pane in the same window. Highlight an
   entry and press Return. Expect the window to close and the entry pasted where you were typing.
2. Open it again, highlight an entry and press Command and Return. Expect it copied, not pasted.
3. Open Olm Aliases. Expect `? ` typed in the field and the alias list in place.
4. Type `d ` and choose the first row. Expect the Dock setting to flip, the list to stay, and the
   row to read the other way.
5. Choose Display Profiles, Workspaces, Obsidian, Text Case, Local Servers, Olm Keys and each Olm
   page in turn. Expect each list in place, with Backspace on the empty field back to the launcher.
6. In Olm Theme, choose the other highlight. Expect it to change, as from the Lua list.

What can go wrong, and what to tell me:
- A row still does nothing. The console says which one: "becomes a list the app does not host yet".
- Clipboard History's paste lands nowhere, or in the wrong app.
- Text Case shows no rows. It reads the selection as it opens, so say which app had the selection.
- Local Servers stays on Nothing running when servers are up.

Once the trial is good, `launcherFlip` goes on, 3.5's step, and the trial there is Hyper and Space.

## 3.7, one look for every picture and every word

Milos found the info icon beside ⌘? white in the app's bar on a light screen on 2026-11-18, fixed
that day in `378d4d12`, and asked that no such case be possible: every icon and every font follows
one global set. A survey of the app and the Swift library on the same day found the cause is a
rule with a hole rather than one bad icon.

What was found:

- A one colour picture keeps the colour it was drawn in while it stands at rest. `Style.ink(lit:)`
  in `native/Model.swift` answers `icon: nil` off the highlight, meaning keep the picture's own,
  and only the lit ink recolours it. A picture drawn ahead of time, which is all the app gets from
  the share at load, keeps the half of that moment. The bar's info icon was one, and every actions
  pane row icon in the app is the same and still open, since `FloatingPane.swift` follows the same
  ink.
- The weight of a symbol is written in three places. The app's rows draw semibold, as
  `lib/icons/sources/sf.lua` does, a key cap's symbol regular in `Bar.swift`, and Quick Look's
  close mark regular in `QuickLook.swift`.
- Nothing checks the Swift side. The dry gate refuses a font, a size or a colour written by hand in
  Lua outside `lib/ui`, and no rule covers the Swift files.

What grows:

1. The ink answers a colour for a one colour picture everywhere, the text colour at rest and the
   lit ink on the highlight, so `Ink.icon` is never nil. The list, the floating panes and the bar
   all draw through it, so a picture follows the half on screen wherever it stands, and the bar's
   own case from `378d4d12` goes back to the shared rule. A picture with colours of its own, an app
   icon, a file or an emoji, is not marked one colour and keeps its own.
2. The symbol weight is a token of the look. The bridge writes `sf.lua`'s weight into
   `chooser.json`'s style, and the app's rows, Quick Look's close mark and every other symbol drawn
   as an icon read it from there. A symbol drawn as a key cap's key is a glyph of the key cap, so it
   takes the key cap font's weight, which is also the look's.
3. A Swift rule in the dry gate, `test/drygate-swiftlook.lua`, over `app/Sources` and
   `lib/chooser/providers/swift/native`. It refuses a font built by hand, a colour literal and a
   symbol weight, outside the files that read the look, `Fields.swift`, `Lua.swift`, the defaults in
   `Model.swift` and the element readers in `PaneElements.swift`. A line answers it with
   `look-exempt, <reason>`, the comma required, which the masks in `Motion.swift` and
   `Surface.swift` and the emoji canvas in `Stage.swift` carry.
4. `test/swiftpane.swift` pins that a one colour picture is drawn in the text colour at rest and in
   the lit ink on the highlight, in the list, the floating pane and the bar, and that a picture not
   marked one colour keeps its own.
5. The rule is written into the colour and icon sections of the hammerspoon `AGENTS.md`, so the
   Swift side carries it in words as the Lua side does.

The trial, on Hyper and 0 while the app runs:

1. Open the launcher and the actions pane on a row, then switch macOS between light and dark. Expect
   every icon in the pane and the info icon in the bar to follow the words around them, with no
   reload.
2. Open Clipboard History and Quick Look on a file entry. Expect the close mark as heavy as the row
   icons.
3. Look at the key caps in the bar and in the info pane. Expect the Caps Lock and Return symbols as
   heavy as the letters beside them.
4. Open Olm Theme and choose the other highlight. Expect a lit row's icon in the lit text colour, as
   before.

What can go wrong:

- An app icon or an emoji turns one flat colour. It was marked one colour by mistake, tell me
  which.
- A key cap's symbol looks heavier or lighter than before. Weight is now the key cap font's, and a
  change there is the point, but say if it reads worse.
- An icon in Hammerspoon's own swift list changes colour. It should not, since it was already
  drawn in the text colour there.

## 3.8, a tool's own key opens its list in the app

Written on 2026-11-18, while checking the resting point. Its first condition says every list a
person opens is drawn by Olm.app. Since 3.5 that holds for the launcher and everything its rows
lead to, but a tool's own key, Clipboard History's or Display Profiles', still opens
Hammerspoon's list. 3.6's line in the plan named that ("a tool's own chord opens its list in the
app") and what was built covered the launcher's rows only. This step is that missing half.

**One door, not one key at a time.** Every plugin shows its own list through one root word,
`stagePresent(name)`, which asks the registry for the presentation and hands it to the Lua stage.
That word asks the bridge first. Where the app can show the list, the bridge opens it there and
the Lua stage is not touched. Otherwise the Lua stage shows it, as today. So every tool's own key,
and anything else a plugin opens its list from, follows one rule, and a tool added to `hosts`
later gets its key in the app with no further edit.

**When the app takes it.** All of these, asked at every press, as Hyper and Space is:
- the olmapp piece is on, the app is built and the socket is up, so a quit app hands every key
  back to Hammerspoon at once, as 3.5 does for the launcher
- the tool is in `hosts`, so it is a list the app already shows from the launcher
- the new switch `keysFlip` in `config/plugins.lua` is true, so this can be turned off alone,
  without touching the launcher

**What grows:**
- **The bridge host** gains `presentInApp(name, presentation)`. It answers false where the app
  cannot take the list, and otherwise opens `olm://launcher?tool=<name>` with the placement and
  answers true. The root's `stagePresent` asks it before the Lua stage.
- **The bridge's `open`** serves `{"tool": name}`, which the protocol already describes and which
  answers `-32013` today. It opens the same hosted level a launcher row pushes, the presentation's
  placeholder, ranking, row limit, fit, preview pane and actions, as the only level. A tool the
  config does not host still answers `-32013`.
- **The app** reads `tool=` on `olm://launcher` and opens its bridged source with
  `{"tool": name}` instead of `{"launcher": true}`. Backspace on the empty field asks the level's
  `back` as now, and with nothing under it does nothing, as the Lua list opened by its key does.
  If `open` answers `-32013`, a race with a reload, the app closes and logs it.

**Not in this step:**
- A list stepped through with one repeated key, Input Sources' cycle, which the Lua stage shows
  bare. The app has no bare mode yet, so a cycle key stays Hammerspoon's. It is a list a person
  opens, so the resting point's first condition is not met until it moves too, its own step after
  this one.
- Opening a list over a password field. The Lua stage takes focus there through `focusHold`, and
  whether the app's panel hears typing while another app holds secure input is not known. The
  trial checks it, and if it does not, a list opened over a secure field stays Hammerspoon's.

**Tests:**
- `test/bridgeserve.lua` and the shared fixtures pin `open` for a hosted tool, its level as the
  push's, and `-32013` for one not hosted.
- `test/bridge.lua` pins `presentInApp`, false with the piece off, the socket down, the switch off
  or the tool not hosted, and the URL otherwise.
- `olm-bridge-check` gains a case opening a tool's level by name, and one the Lua side refuses.
- `stagePresent` asking the bridge first is three lines inside `root/compose.lua`, which no offline
  test reaches, so the trial is what checks it, step 4 for the Lua list when the app is gone.

**As built, 2026-11-18.** The app opens `olm://tool?name=<name>`, a host of its own rather than a
field on `olm://launcher`, since the app asks the Lua side for the level before the stage opens it,
its manifest being read as it opens. The stage's Backspace on an empty field now asks a list with
nothing under it for its `back` too, and does nothing when it declines.

**The trial, once built, with the app running:**
1. Press Clipboard History's own key. Expect its list and preview pane in the app's window, not
   Hammerspoon's. Return pastes the entry where you were typing.
2. Do the same for Display Profiles, Workspaces, Obsidian, Text Case, VPN, Emoji and Browser Tabs,
   each by its own key. Expect each in the app, as from the launcher.
3. In one of them, press Backspace on the empty field. Expect nothing to happen, and the list to
   stay.
4. Quit the app with the Quit Olm App row and press Clipboard History's key. Expect Hammerspoon's
   list.
5. Start the app, click into a password field in Safari, and press Clipboard History's key. Expect
   the list in the app and your typing to reach its field. If it does not, say so.

What can go wrong, and what to tell me:
- A key opens nothing. The console says which tool, "the app could not open".
- A key opens Hammerspoon's list while the app runs. Say which tool, since it may open its list
  some other way than `stagePresent`.
- Text Case shows no rows. It reads the selection as it opens, so say which app had it.
- The first press after the app starts is slow.

**Back out:** `keysFlip = false` in `config/plugins.lua` and a reload. Every key opens
Hammerspoon's list again and the launcher stays in the app.

## Back out

Remove a tool from `hosts` and reload. The row answers `unserved` again. For File Search, set the
bridge's `serves` back to empty, which every key already reads.
