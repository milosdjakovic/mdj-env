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

## Back out

Remove `caffeinate` from `hosts` and reload. The row answers `unserved` again.
