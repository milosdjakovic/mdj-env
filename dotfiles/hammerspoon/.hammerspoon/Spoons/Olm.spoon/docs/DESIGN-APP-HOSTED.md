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

## Back out

Remove a tool from `hosts` and reload. The row answers `unserved` again.
