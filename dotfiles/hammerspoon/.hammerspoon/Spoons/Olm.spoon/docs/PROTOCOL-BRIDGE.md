# The bridge protocol, version 1

Written 2026-11-07, step 0.4 of `docs/PLAN-STANDALONE.md`, and revised the same day after its
adversarial review, whose findings and what became of each are in `decisions/olm-standalone.md`.
On paper only, no code implements it yet. It is what Olm.app and the Lua side running in
Hammerspoon say to each other from stage 2 on, so that the app can draw, search and navigate every
list while the rows, the actions and the preview panes of a plugin not yet native still come from
Lua. Everything after stage 2 stands on it.

## What it is for, and the rules it serves

The app owns the input field, the list, the highlight, the search and the chooser's window. The
Lua side owns what a plugin knows, which rows a list has, what choosing one does, which actions a
row offers and what its preview pane shows. Only that crosses, and five rules hold for every
message here.

1. **The app never waits for Lua to show a key typed or to move the highlight.** Every request is
   sent and answered on the app's own background work, and a late answer is merged or dropped. One
   thing waits by design, Return, see Choosing below, and it holds only itself, never typing.
2. **The app is the one authority on the highlight and the query.** Whatever Lua runs for a row,
   the request names that row by its ref and carries the query, and Lua answers about that row,
   never about a highlight it remembers. A key Hammerspoon hears while the app's list is open is
   handed to the app, which decides the row.
3. **A stale answer is recognised and dropped.** Two counters do it, one for the query and one for
   the highlight, below.
4. **Nothing that only Lua can hold crosses.** No function, no `hs.image`, no `hs.styledtext`, no
   table with a closure in it. A Lua value the app refers back to stays on the Lua side behind a
   ref. Pictures cross as file paths, icons as keys, styled text as plain text with runs.
5. **What a plugin does to its list is answered as effects, in order.** A handler may set the
   query, push, pop and redraw in one go, and the answer says all of it, so neither side guesses.

## The Lua side holds no chooser of its own for a bridged list

While the app shows a list, there is no Lua chooser behind it. The bridge host, `host/bridge`,
keeps its own table of the levels the app has open, each one the presentation it was opened from,
and it is a facade of the `Stage`, the same methods, `query`, `setQuery`, `setPlaceholder`,
`isShowing`, `isCurrent`, `push`, `pop`, `present`, `hide`, `refresh`, `selectedItem`, `textBudget`
and `textWidth`. The composition root hands the facade, rather than the `Stage`, to everything that
is handed a stage while the app shows the list, the stage words of every plugin and the hosts that
hold a stage of their own, the launcher's `_stage` and the `run` that hides before a verb, so no
caller reaches past it. Each of the facade's methods answers from the level table and the request
being handled, and records an effect, below. That is what makes the earlier rejection of an app
picker provider not reach this plan, `decisions/olm-standalone.md`, since nothing on the Lua side
mirrors the panel's state and no synchronous question crosses. The stage words and what each
becomes are in their own section.

## Transport and framing

The byte stream is open question 2 of the plan, a Unix domain socket or local HTTP, decided by
step 2.1. This protocol needs one ordered, reliable, two way stream per connection, and either
gives that.

- One message is one JSON object on one line, UTF-8, ended by a single `\n`.
- A line is at most 8 MiB. A peer that receives a longer one closes the connection. No answer is
  allowed to come near it, see Size below.
- The messages are JSON-RPC 2.0. A request has `jsonrpc`, `id`, `method` and `params`, an answer
  has `jsonrpc`, `id` and either `result` or `error`, and a notification has no `id` and is never
  answered. Either peer may send requests and notifications.
- An `id` is a string, unique among that peer's outstanding requests, `a1` from the app, `l1`
  from the Lua side.
- Each peer handles messages in the order it reads them, apart from the coalescing rule under
  Generations.
- A JSON number used as an identity, a key or a generation, is an integer within 2^53, since
  larger ones lose precision in a JSON reader. A key outside that is sent as a string.

**Access.** The socket, or the token an HTTP transport needs, lives under `~/.olm/run/`, a
directory of mode 0700, the socket or token file 0600. A Unix socket's peer must be checked with
`getpeereid` and refused unless it is the person's own user. An HTTP transport binds 127.0.0.1
only, requires the token in a header on every request, and refuses a request whose `Host` is not
`127.0.0.1:<port>` or that carries an `Origin`, so a web page cannot reach it.

## Who starts, and what happens when the connection goes

The Lua side listens and the app connects, since Hammerspoon is the one running when the app
starts and the one that knows every plugin. The app reconnects with a backoff of 0.25 s doubling
to 5 s while it runs.

On a lost connection the Lua side closes every level the app had, calling each presentation's
`onClose`, and forgets every ref. The app drops every level, and a list that was showing hands back
to the Lua Olm, condition 5 of the resting point, reopening in the Lua chooser with the input
field's text kept. Nothing outlives a connection, so a reconnect starts from `hello`.

## hello

The app's first request is `hello`, and the Lua side answers nothing else first.

```json
{"jsonrpc":"2.0","id":"a1","method":"hello","params":{"protocol":1,"app":"0.1.0","features":[]}}
{"jsonrpc":"2.0","id":"a1","result":{"protocol":1,"olm":"2026-11-07","features":[],
  "limits":{"line":8388608,"rowLimit":200,"name":65536}}}
```

`protocol` is the major version. A Lua side that does not speak the app's answers `-32010` and the
app stays unconnected. Inside one version a field nobody knows is ignored, a method nobody knows
answers `-32601`, and a value of an enumeration nobody knows, a new effect, a new outcome, is read
as nothing and logged, so a newer peer never makes an older one act. A feature both sides list in
`features` may be used. Removing a field or changing its meaning is a new major version.
`limits.rowLimit` is the Lua engine's own default, `ROW_LIMIT` in `lib/chooser/engine/init.lua`,
which a level that declares no limit of its own uses.

After `hello` the app sends `metrics`, below, and the session is open.

## The words both sides use

**A level** is one list the app shows, the launcher, a tool's own list, or a child a row pushed.
It has an id the Lua side mints, `v7`, valid until it is closed or the connection goes.

**A ref** names a Lua item the app cannot hold. A row's ref is `<level>.<n>`, `v7.112`, and the
Lua side gives the same ref to the same key for as long as the level is open, so a ref outlives any
one answer. An unknown ref answers `-32012`.

**A key** is a row's identity across answers. The plugin's own `item.key` is it where one is set,
as the stage holds the highlight by today, `host/stage/init.lua`. Most plugins set none, Clipboard
History and File Search among them, and rule 5 of the plan forbids asking them to, so the bridge
host mints one. It keeps a table keyed weakly by the item table itself and gives an item it has
seen before the key it had, so a supplier that hands back the same item tables across builds, as
Clipboard History's cache does, keeps its keys. An item built afresh on every call gets a fresh key
each time, and its rows are sent whole, which is the cost of such a supplier, measured at the step
that serves it.

**Two generations**, both whole numbers the app counts per level. `q` is raised on every change of
the input field. `h` is raised whenever the highlighted row becomes another row, a different ref,
and never by typing that leaves the same row highlighted. See Generations.

## The row

A row is a JSON object. Every field but `ref` and `title` may be absent, an absent one reads as
its default exactly as `lib/chooser/rank.lua` reads it, and the search fields mean what that file's
vocabulary says. The fixtures in `test/fixtures/ranking/` are what the app's ranking is checked
against.

| Field | Type | Meaning |
|---|---|---|
| `ref` | string | the Lua side's handle for this row's item |
| `key` | string or integer | identity across answers, the plugin's `item.key` |
| `title` | Text | the name, the primary search field |
| `subtitle` | Text | the line under the name, a secondary search field |
| `keywords` | list of strings | words it answers to without showing them |
| `names` | list of strings | further names, matched like the title, never shown |
| `filterText` | string | replaces the title and the subtitle as the primary field |
| `pinned` | bool | never scored, trails under a typed query |
| `fromQuery` | bool | made from what was typed, leads under a typed query |
| `tier` | number | a smaller tier sorts first |
| `bonus` | number | 0 to 1, orders equally good matches only |
| `memoryKey` | string | the launcher's memory key for this row, see The launcher |
| `enabled` | bool, default true | a disabled row is shown and never chosen |
| `chord` | Chord | the shortcut drawn at the row's end |
| `section` | string | the heading of the group the row starts |
| `icon` | Icon | what is drawn before the title |
| `picture` | Picture | a real picture, drawn instead of the icon |
| `tint` | Role | the colour role the icon is drawn in |
| `labels` | object | `primary` and `secondary`, the words the bottom bar uses for this row |

The Lua side builds each row from what the supplier returned. A `subTitleFn` is called and its
answer sent, an `hs.styledtext` is sent as Text, the item stays behind the ref, and a field this
table does not name is not sent. `labels` is sent only when the presentation declares
`labels(item)`. The engine's own Show more row is the app's, never sent.

**Text** is a plain string, or `{"runs":[{"text":"...","role":"...","weight":"..."}]}` whose texts
joined make the string, so no offset is counted in one encoding and read in another. A run names a
typography role and a colour role of the UI kit. Search reads the joined text.

**Bytes that are not UTF-8.** Every string the Lua side sends is made valid UTF-8 first, each
invalid sequence replaced by U+FFFD, since one bad byte in a clipboard entry must not fail a whole
answer. A row whose text was changed this way carries `"lossy":true`, and a shadow comparison
skips it.

**Chord** is a list of key names from `lib/kbd.lua`, `["cmd","return"]`, as `kbd.wire` gives the
Swift library today, never glyphs and never one joined string.

**Icon** is one of these, and the app resolves it itself.

- `{"owner":"clipboard","key":"pin"}`, an icon a manifest declares, see `icons`.
- `{"emoji":"🍕"}` or `{"sf":"folder.fill"}`, a content icon spelled directly.
- `{"app":"com.apple.Safari"}`, an application's own icon, taken from the system.
- `{"file":"/Users/.../report.pdf"}`, the icon the system shows for that path.
- `{"mark":"chosen"}` or `{"mark":"on"}`, the state marks `lib/icons/rows.lua` stamps today.

**Picture** is `{"path":"/abs/path.png"}`, a file NSImage opens. Where the Lua side holds a
picture only as an `hs.image`, it writes it once into `~/.olm/cache/bridge/` under a name taken
from its content and sends that path, and the cache is pruned by age, never while a level that
sent it is open.

**Role** is one of the eight colour role names of the UI kit.

## Size

No answer may come near the line limit, so three bounds hold.

- **Rows are sent as changes.** A level's rows have a revision, and an answer sends only what
  changed since the revision the app says it has, by key, see Rows.
- **A long name is sent once and cut.** Each entry of `names` is at most `limits.name` bytes,
  64 KiB, cut at a character boundary, and the row carries `"namesCut":true`. A clipboard body is
  the case this exists for, and a match that only the cut part held is a known difference the
  shadow log allows. `names` travels apart from the rest of the row, as `namesId`, a hash of its
  content, and the list itself is sent only the first time that hash is sent on the connection, so
  a body crosses once whatever the row around it does. The host hashes a names list once per list
  table it is handed and reuses the hash while the same table comes back, so a supplier that keeps
  its tables costs no hashing per keystroke.
- **An answer over 4 MiB is split.** The Lua side sends the change in parts, each its own `rows`
  notification with `part` and `of`, and the app applies them when the last has come.

## icons

`icons` asks for every icon one owner's manifest declares, once per connection and again after a
`catalogChanged`.

```json
{"jsonrpc":"2.0","id":"a2","method":"icons","params":{"owner":"clipboard"}}
{"jsonrpc":"2.0","id":"a2","result":{"icons":{"pin":{"sf":"pin.fill","emoji":"📌"}}}}
```

The app draws them by the same preference the Lua side has today, `lib/icons/`, and a key the
table lacks is drawn blank and logged once.

## metrics

The app sends the notification `metrics` after `hello` and whenever the chooser's width changes.

```json
{"jsonrpc":"2.0","method":"metrics","params":{"textBudget":612,"font":{"title":"body","subtitle":"caption"}}}
```

`textBudget` is the pixel room a row's text has, what `stageTextBudget` answers, and `font` names
the typography roles the rows are drawn in, so `stageTextWidth` can measure a string on the Lua
side in the same role and answer pixels without a round trip. A measurement is approximate across
the two renderers, and FileSearch's eliding of a long path, its one reader, tolerates that.

## Opening a level, and a fresh list

`open` asks the Lua side to open a list.

```json
{"jsonrpc":"2.0","id":"a4","method":"open","params":{"what":{"tool":"clipboard"},"query":""}}
{"jsonrpc":"2.0","id":"a4","result":{"level":{"id":"v7","placeholder":"Clipboard History",
  "previewPane":true,"previewPaneWidth":480,"rowCount":9,"titleLineBreak":"truncateTail",
  "ranking":"app","rowLimit":"default"}}}
```

`what` is `{"launcher":true}`, `{"tool":"name"}` with the registry's name, or `{"alias":"vpn"}`.
A tool the bridge does not serve yet answers error `-32013` and no level, and the app keeps the row
that led there in place rather than closing and opening the Lua chooser, step 3.3.

The level's fields are the presentation's own, sent as values, and sent again in the effect
`level` whenever the Lua side sees one change, since `rowCount` and the placeholder may be
functions it calls.

- `ranking` is `"app"`, the app ranks with its port of `rank.apply` and the shared matcher, which
  is every presentation that declares no matcher, or `"source"`, the presentation declared
  `matcher = false` and the Lua side's order is final.
- `rowLimit` is a number, `"none"` for a presentation that declared `false`, or `"default"` for
  one that declared nothing, which is `limits.rowLimit`. The Show more row and its paging are the
  app's own.

**A list opened by Lua.** A plugin that opens its own list, `stagePresent`, about seventeen plugins
today and Caffeinate the first one step 3.3 serves, and the launcher's hand over to a scope, both
start a fresh stack. The Lua side sends the notification `present` with a level as above and an
initial `query`, and the app shows it as the only level, replacing whatever was showing. The same
reaches a list Hammerspoon opens by a chord, step 3.6.

## Rows

`rows` asks for a level's rows for what is in the input field.

```json
{"jsonrpc":"2.0","id":"a5","method":"rows","params":{"level":"v7","q":12,"query":"img cat","have":"r3"}}
{"jsonrpc":"2.0","id":"a5","result":{"q":12,"revision":"r4","changes":{
  "upsert":[{"ref":"v7.991","key":"k991","title":"cat.png","namesId":"n5e1","picture":{"path":"..."}}],
  "remove":["k12"],"order":["k991","k7","k3"]},"names":{"n5e1":["a cat on a mat"]},
  "fromQuery":[],"exclusive":false,"rankText":"cat"}}
```

- `revision` names the level's rows after this answer. With `have` equal to it the answer carries
  no `changes`. Otherwise `changes` holds the rows that are new or differ, by key, those removed,
  and `order`, every key in the supplier's order. A level whose rows have no keys is sent whole,
  as `"rows":[...]` in place of `changes`, which is why a row with no key costs more.
- `names` holds each names list whose `namesId` this connection has not carried before, see Size.
- `fromQuery` are the rows made from what was typed, a calculator answer, a conversion, a hosted
  scope's rows, leading as rank.lua says.
- `exclusive` true means `fromQuery` replaces the supplier's rows for this query, the launcher's
  query source that claims the query, so `vpn foo` shows only the scope's rows.
- `rankText` is what the presentation's `searchText` made of the query, the text the app ranks by,
  absent when it declares none. An empty one keeps the supplier's order. One that raised is sent
  empty with `rankTextError`.

The Lua side runs the supplier for every `rows` it does not coalesce away, then compares each
row's fields, `names` by its hash, with what it last sent for that key and sends only the
difference, so a field a supplier rewrites on a cached row, a bonus, is still seen. The supplier
still runs once per pause in typing, on Hammerspoon's thread, the cost the resting point names. It
no longer holds a key typed in the app.

**Between a keystroke and its answer** the app ranks the rows it holds by the newest `rankText` it
has. A list whose supplier narrows by what was typed, Clipboard History's kind prefix among them,
can show for a moment rows the answer will remove. That is drawn and never acted on, see Return.

The launcher is a level like any other. Its rows carry `memoryKey`, and its memory is described
under The launcher.

## Generations

`rows` carries `q`. `describe`, `actions`, `choices`, `run`, `choose` and `key` carry both `q` and
`h`. Every answer and every notification about a level carries the `q` it was computed from, and
`paneDrawn` and `bar` carry the `h` too.

- The app drops a `rows` answer whose `q` is older than the newest `q` it sent for that level, and
  only then. Moving the highlight never makes a rows answer stale.
- The app drops a highlight answer, `paneDrawn`, `bar`, `actions`, `choices`, whose `h` is older
  than the level's newest, which happens only when the highlight moved to another row since. A
  preview or a bar computed while the person typed over the same row is kept.
- An effect that writes the input field, `setQuery`, carries the `q` it was computed from, and the
  app applies it only if the field has not changed since that `q`, otherwise it drops it and logs,
  so a plugin never overwrites what the person typed after it. A `push` or a `present` that
  arrives as a notification, outside any handler, the launcher's hand over on its next tick among
  them, is gated the same way. Effects in the answer to a request apply as sent.

The Lua side is one thread. When it reads a `rows` or a highlight request, it first reads every
complete line already waiting, and a request superseded by a newer one of the same method for the
same level is answered at once with `-32011`, stale, and never run.

## The highlight

The app sends the notification `highlight` whenever the highlighted row or the input field of the
top level changes, and when a level opens, closes or comes to the top.

```json
{"jsonrpc":"2.0","method":"highlight","params":{"showing":true,"level":"v7","q":14,"h":31,"ref":"v7.112","row":3,"query":"img cat"}}
```

The Lua side calls the presentation's `onHighlight` with that item, once per change of `ref`, so
a plugin that draws its preview pane on highlight still does, and keeps the latest for two readers
only, `isShowing` of the surface `lib/nav.lua` routes list keys to, and `stageSelectedRow` outside a
handler, which is why it carries `row`, the highlighted row's place in the list as shown. No action, verb or choice ever
reads it to decide which row it is for, rule 2 above.

## Running anything, and the effects that come back

Every way a person acts on a row is a request that names the row and the query, and every answer
is the same shape, `{"effects":[...]}`, the ordered list of what the handler did.

| Request | What it is | Lua runs |
|---|---|---|
| `choose {level, q, h, ref, row, query, mods}` | Return on a row | `intercept`, then `select` |
| `run {level, q, h, ref, row, query, action, choice}` | an action from the actions pane or a bar item | the action, with the item |
| `key {level, q, h, ref, row, query, chord}` | a chord the app's input field heard that the app does not own | what the keymap binds to it there |
| `back {level, q}` | Backspace on an empty input field | the presentation's `back` |
| `close {level}` | the app closed the level | `onClose` |

While a handler runs, the facade answers `stageSelectedItem`, `stageSelectedRow` and `stageQuery`
from the request's own `ref`, `row` and `query`, never from the latest highlight. A deferral the
host itself schedules for that request, the actions pane's run on the next tick, the launcher's
deferred `_runItem`, captures the same context and answers from it when it runs. That is what keeps
a delete on the row the person chose even when the highlight moved a moment later. A plugin that
defers work of its own and reads the stage words later reads the latest highlight, as it does
today, and the step that serves that plugin checks whether that matters for it. The requests that
act on a row carry `row` beside `ref` for this.

The effects are recorded as the handler calls the stage words, in order, and sent when it returns.

| Effect | Comes from | The app |
|---|---|---|
| `{"rows":{"level":"v7","hold":true}}` | `intercept` answered `"stay"`, or `redrawPresented` with resetRow false | asks for rows again, the highlight kept on its key |
| `{"rows":{"level":"v7","hold":false}}` | `intercept` answered `true` with no other effect, or `redrawPresented` with resetRow true | asks for rows again, the highlight on the first row |
| `{"push":{"parent":"v7","level":{...}}}` | `stagePush`, or `select` returning a presentation | shows the child |
| `{"pop":{"level":"v7"}}` | `stagePop` | pops that level if it is still open, and every level above it |
| `{"setQuery":{"level":"v7","q":14,"query":"vpn "}}` | `stageSetQuery` | writes the field if it has not changed since `q` |
| `{"setPlaceholder":{"level":"v7","text":"..."}}` | `stageSetPlaceholder` | changes it |
| `{"level":{...}}` | a level field changed | replaces those fields |
| `{"present":{"level":{...},"query":""}}` | `stagePresent`, a hand over | shows a fresh stack |
| `{"unserved":{"tool":"name"}}` | a push or present of a tool the bridge does not serve | keeps the row in place, step 3.3 |
| `{"hide":{}}` | `stageHide`, or `select` returning nothing | hides the chooser |
| `{"after":"hidden"}` | work the host deferred until the chooser is gone | sends `hidden` once it is |
| `{"requery":{...}}` | `choose` on a row the supplier no longer shows for that query | shows the fresh rows, chooses nothing |

`intercept` answering `true` is a swap only when the handler did nothing else. The launcher's own
intercept answers `true` after seeding a query or pushing a tool, `lib/rowintercept.lua`, and then
its effects say what happened, `setQuery` or `push`, and no rows effect is added.

An effect naming a level that is no longer open is skipped by the app. A `pop` that closed levels
already answers `close` for none of them, since the Lua side closed them itself. An unknown ref or
level answers `-32012`, and the app closes that level and asks for nothing again, so no request
can loop.

**Work after hiding.** A row that opens an app, pastes or moves a window must run after the
chooser is gone, or it lands in Olm.app. Two things guard it. Olm.app's chooser is a nonactivating
panel, as the swift chooser is today, so Olm.app never becomes the active application and the app
the person was in stays frontmost under it. And the app applies a `hide` effect before anything
else in an answer and before reading the next message. Work the host defers itself, the launcher's
`_runItem`, waits behind the effect `{"after":"hidden"}`, the app sends the notification `hidden
{level}` once its window is ordered out, and the host runs the work then, with a fallback of 1 s if
`hidden` never comes, replacing the launcher's 0.1 s timer. Work a plugin defers on its own timer,
`lib/paste.lua` waiting for the modifiers to lift, starts inside the handler and lands wherever the
frontmost app is when it fires, which the nonactivating panel keeps the right app, so it needs no
handshake. The step that serves Clipboard History checks it live.

**Return while an answer is out.** `choose` carries the `q` and the query it was pressed on, and the
Lua side never chooses a row its supplier would not show for that query. When the rows it last
computed for the level were for an older query, it runs the supplier for the request's query first,
and when the ref is not among those rows it runs nothing and answers the effect `{"requery":{"level":"v7","q":14}}`,
on which the app shows the fresh rows and chooses nothing, so a quick Return after `img cat` never
pastes a text entry. A person presses Return again on the list they now see. The app sends
`choose` at once and keeps typing and the highlight live while it is out, and a key typed before
the answer raises `q` and the app ignores whatever that answer would have shown.

## The actions pane

`actions` asks for the actions pane of a row. The Lua side builds the rows as `lib/hints.lua` does
today, calling each action's `applies` for that item itself.

```json
{"jsonrpc":"2.0","id":"a7","method":"actions","params":{"level":"v7","q":14,"h":31,"ref":"v7.112"}}
{"jsonrpc":"2.0","id":"a7","result":{"h":31,"actions":[
  {"action":"paste","title":"Paste","chord":["return"],"section":"Clipboard History","closes":true},
  {"action":"pin","title":"Pin","chord":["cmd","p"],"icon":{"owner":"clipboard","key":"pin"}},
  {"action":"forget","title":"Delete","confirm":"Delete This Entry"},
  {"action":"saveAs","title":"Save As","choices":true}]}}
```

An action that does not apply is left out. `confirm` is the confirm row's title, `choices` says
picking it opens a level of choices, which `choices` asks for, each with a `choice` ref and
`title`, `subtitle`, `icon`, `current` and `enabled`. `run` takes the action and the choice.

## The keys

Two places hear keys, and each hands the decision to the side that owns it.

**The app's input field** owns typing, Backspace, the arrows, Return, Escape, Tab, Command and a
digit, which chooses that slot as the engine does today, `_chooseSlot`, and Command and slash, which
opens the info pane the app draws. A chord it does not own, Command and Return for the secondary
action, an action's own chord such as Command and P, is sent as `key` with the highlighted row, and the Lua side resolves it against the keymap
and the gates it holds, `lib/nav.lua`, and runs it. The app does not keep a copy of the keymap
until stage 5 moves the keys, rule 1 of the plan.

**Hammerspoon's leaders**, Hyper and META, still bind every chord until stage 5. A list key heard
there while the app's list is open, Hyper and J among them, is never run on the Lua side against a
remembered highlight. The surface `lib/nav.lua` routes to is an adapter that forwards it to the app
as the request `verb`, and the app acts on its own highlight.

```json
{"jsonrpc":"2.0","id":"l3","method":"verb","params":{"verb":"selectNext"}}
{"jsonrpc":"2.0","id":"l3","result":{}}
```

The verbs the app runs itself are `selectNext`, `selectPrev`, `close`, `openActionsPane`,
`showInfo`, `insertSelected` and `refresh`. Any other verb, `primary`, `secondary` or a plugin's
own, is sent as `{"verb":"run","action":"..."}`, and the app answers it by sending `run` for its
highlighted row, so the row is the app's. The Lua side never waits for a `verb` answer, and a key
is never held for the app. `leaderHeld` stays Hammerspoon's own state and is answered there.

## The preview pane

The Lua side is a backend of the shared preview pane, `lib/previewpane.lua`, so a plugin draws
exactly as it does today, through `pane.show`, `pane.draw` and `pane.clear` from its own
`onHighlight`, `onPositioned` or a later callback, and the backend sends what was drawn. A plugin is
handed one pane at `configure` and keeps it, while the list it draws for may be shown by the app or,
with the app gone, by the Lua chooser. So the pane a plugin holds becomes a router over two
backends, the one it has today and the bridge's, and the host points it at the bridge while the
app shows that plugin's level and back when it does not, so the plugin never learns which,
rule 5 of the plan.

The app sends the notification `positioned {level, frame, paneFrame}` when the chooser or the pane
is placed, and the Lua side calls `onPositioned` with those frames, so `pane.inner()` answers the
pane's inner size from then on, as it does today once docked. `paneFrame` null is the pane gone,
`pane.hide()`.

What a plugin drew arrives as the notification `paneDrawn`.

```json
{"jsonrpc":"2.0","method":"paneDrawn","params":{"level":"v7","q":14,"h":31,"ref":"v7.112",
  "elements":[ ],"contentHeight":900,"keepScroll":false}}
```

`ref` and `h` are those of the highlight the plugin was last told, and the app drops a `paneDrawn`
older than its `h`. `{"empty":true}` in place of `elements` is the shared empty state,
`pane.clear()`. `keepScroll` keeps the app's scroll offset rather than returning to the top.

`elements` is the list `native/Pane.swift` draws and `PaneReader` in `native/Lua.swift` reads, as
JSON, every attribute that reader reads: `type` of `rectangle`, `segments`, `image`, `text` or
`resetClip`, `action` of `fill`, `stroke`, `strokeAndFill`, `clip` or `skip`, `frame` in points or
percent strings, `fillColor`, `strokeColor`, `strokeWidth`, `strokeCapStyle`, `strokeJoinStyle`,
`roundedRectRadii`, `coordinates`, `closed`, `imageAlpha`, `imageAlignment`, `imageScaling`,
`text`, `textFont`, `textSize`, `textColor`, `textAlignment`, `textLineBreak`, `id` and
`trackMouseUp`. The kit resolves a typography role to `textFont` and `textSize` before an element
is handed over, which is why a pane element may carry a font when a row may not. Three values
differ from today, since what Lua hands the canvas now cannot cross. `image` is a Picture, `text`
is Text, and a colour is a Role or `{red, green, blue, alpha}`, the second only for a colour that is
content, a colour sample's swatch.

The app owns the scroll and moves the content at once. It sends the notification `scrolled {level,
y}` when the scroll settles, which the backend keeps as `view.scrollY`, so a painter with a fixed
header reads the offset it reads today and redraws its header after the scroll rather than during
it, the one place a preview is behind the person, accepted until that painter is native.
A press on an element with `id` and `trackMouseUp` is the notification `clicked {level, ref, id}`.

## The bottom bar

The Lua side sends the notification `bar` with the model `lib/hints.lua`'s `bottomBarModel` builds,
`right` and `keys` as bar items `{label, chord, action, section, lead, fit}`, `keysChord`, `title`,
`infoIcon` as an Icon and `panelTitle`, with the level, `q` and `h`. It sends it when a level
opens, after a `highlight`, and when its own quarter second check of gates and live labels, the
one the engine runs today, finds the model changed. A bar item's `action` is sent back as `run`
for the highlighted row.

## The launcher

The launcher is opened with `{"launcher":true}` and served like any level, its rows carrying
`memoryKey`, the launcher's `recencyKey`, a kind prefix and an identity, `app:com.apple.mail`. A row
that is live, a subtitle from `subTitleFn` or a `when` predicate, is re-evaluated on each `rows`
and sent as a change only when it differs.

Its learned memory, `lib/queryassoc.lua`, stays with the Lua side, which records a pick on every
`choose` from the query the request carries, since the launcher reads the query through its
`_stage`, which is the facade. So that ranking never waits for it, the Lua side
sends the memory itself rather than a bonus per query. `open` for the launcher carries
`"memory":{"<query>":["<memoryKey>", ...]}`, each query's order as `orderFor` answers it, and after
each pick the Lua side sends the notification `memory` with the queries that changed. The app works
the bonus out as the launcher does, `_memoryBonus`, one for the leader down to one over the count
for the last, by the longest remembered prefix of the query, and pinned by
`test/fixtures/ranking/launcher.json`. The query is folded to lower case byte by byte, A to Z only,
as Lua's `string.lower` does, never by Unicode case rules, or a query with a capital outside ASCII
would find another memory. In the launcher the memory is the bonus. In any other level
the row's own `bonus` is.

`catalog` asks for the launcher's rows at rest outside any level, for step 2.3's shadow ranking,
and answers `{"revision":"c41","rows":[...]}`, with `unchanged` against `have` and the notification
`catalogChanged` when an app is installed or a plugin reloaded. Its refs are for reading only, and
choosing a row is done in a launcher level.

## Errors

| Code | Meaning | The receiver |
|---|---|---|
| `-32700` `-32600` `-32601` `-32602` | JSON-RPC's own | logs it, the app drops the request |
| `-32010` | protocol version not spoken | the app stays unconnected |
| `-32011` | stale, superseded, never run | ignored |
| `-32012` | unknown level or ref | the app closes that level, asks nothing again |
| `-32013` | not served yet | the app keeps the row in place, step 3.3 |
| `-32014` | the plugin raised, `data.message` says what | logged, the list kept |

A plugin that raises never takes the bridge down, the bridge host catching it per request as the
stage catches a supplier today.

## How long anything takes

No timeout is set beyond the two above, Return's 300 ms and the 1 s fallback after hiding, since
a slow answer is merged or dropped rather than waited for. The app logs any answer that took over
250 ms with its method and level, the measure the plan asks for from stage 1 on, and shows a
waiting row only in a list that has no rows at all.

## The olm:// URLs

The pilot, stage 1, reaches the app before any bridge exists, through URLs Hammerspoon opens with
`hs.urlevent.openURL`. A URL carries a command one way.

| URL | What the app does |
|---|---|
| `olm://filesearch?query=TEXT` | shows its file search with TEXT in the input field |
| `olm://launcher?query=TEXT` | shows its launcher, from step 3.2 |
| `olm://ping?nonce=N` | writes N and the time to `~/.olm/run/ping`, the test step 1.1 names |

Any program on the machine can open a URL, so a URL only ever shows a list with text in its input
field and never runs anything. A launcher level opened from a URL is opened with `"fromURL":true`,
and the host holds back the hand over the launcher's supplier would schedule, the one a query such
as `vpn ` starts, until a `rows` arrives with a `q` above the one the level opened at, so it starts
only once the person types. A query is percent encoded UTF-8,
and an unknown URL is ignored and logged.

## The stage words, and what each becomes for a bridged level

| Stage word | For a bridged level |
|---|---|
| `stagePush(child)` | the effect `push`, or `unserved` |
| `stagePop` | the effect `pop` |
| `stageHide` | the effect `hide` |
| `stagePresent(name)` | the notification or effect `present`, or `unserved` |
| `redrawPresented(name, resetRow, token)` | the effect or notification `rows`, landing only on an open level the token names |
| `stageSetQuery` | the effect `setQuery`, with its `q` |
| `stageSetPlaceholder` | the effect `setPlaceholder` |
| `stageSelectedItem`, `stageSelectedRow`, `stageQuery` | inside a handler and its host deferrals the request's own, otherwise the latest `highlight` |
| `stageTextBudget`, `stageTextWidth` | from `metrics`, in pixels |
| `leaderHeld`, `stagePluginSwitch` | Hammerspoon's own, unchanged |

An effect raised outside any handler, a plugin's async redraw, is sent as a notification of the
same shape, `{"method":"effects","params":{"level":"v7","q":14,"effects":[...]}}`, and the app
applies it with the same rules.

## How it is tested

The plan's bridge transcripts are this protocol as recorded conversations under
`test/fixtures/bridge/`, added at step 2.2 with the first method served. The Lua side replays them
over fakes in the dry gate and the app replays them against a fake Lua side in `swift test`.

## What it leaves out on purpose

- **The launcher's memory moving to the app.** It stays with the Lua side, one owner, and only its
  read crosses.
- **`enter(proceed)`, `onScroll`, `onRightClick` and `peekPreview`.** The step that serves a tool
  using one adds what it needs, announced in `features`.
- **Toasts and cheat sheets.** Hammerspoon draws them until stage 5.
- **Anything run from a URL.**
