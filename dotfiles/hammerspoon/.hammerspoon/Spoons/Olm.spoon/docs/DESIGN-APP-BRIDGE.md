# The app on the bridge, and the launcher's shadow, step 2.3

A design note for step 2.3 of `docs/PLAN-STANDALONE.md`, written and agreed with Milos on
2026-11-13, both questions at the end answered as proposed, and built the same day. Step 2.2 left Hammerspoon able to serve the launcher over `~/.olm/run/bridge.sock`, read
only and switched off, with nothing on the other end but a test client. This step puts the app on
the other end and has it rank every real launcher query beside the Lua launcher, logging every
difference. Nothing a person sees changes. Hyper and Space still opens the Lua launcher.

## What it proves

The gate is the plan's, the shadow log empty over a few days of real use. An empty log means the
app, handed the same rows over the socket, puts them in the same order the Lua launcher shows,
the shared search, the row limit, a query source claiming the query, and the learned memory
together. Stage 3 then only has to draw what the shadow already agrees on.

## How it works

1. **The app listens.** A listener of its own in the app, on its own queue and never the main
   thread, rule 8. It makes `~/.olm/run` mode 0700, removes a stale socket, binds, sets the socket
   0600, checks each peer with `getpeereid` and refuses one that is not this user, keeps one
   connection and takes a new one in place of the old, and posts `local.olm.Olm.listening`, so a
   Hammerspoon already loaded connects at once. Framing is 2.1's, a length line and the JSON, at
   most 8 MiB. `test/bridgecheck.swift` already listens this way and is the model.
2. **The session.** On each connection the app sends `hello`, then `metrics`, then opens the
   launcher, `open` with `{"launcher":true}`, which answers a level and the whole memory. A lost
   connection drops the level and the memory, and the next connection starts from `hello`.
3. **The bridged source.** The launcher level is answered by one `ListSource` for all of
   Hammerspoon, the bridged source `docs/DESIGN-APP.md` names. `open` and `rows` turn into bridge
   requests, and the rows it holds are kept by key and patched by each answer's changes, upsert,
   remove and order. `choose` and the rest answer nothing in this step. In the launcher it puts the
   memory on each row as its bonus, one for the leader down to one over the count, by the longest
   remembered prefix of the query folded A to Z only, as `_memoryBonus` and `orderFor` do, so the
   searcher that ranks file search ranks the launcher unchanged.
4. **What the Lua launcher settled on.** The Lua launcher answers `watch` and `held` as file
   search's engine does, its query and the rows it last handed the stage, and the bridge reuses
   1.3e's shadow, the same 0.8 second settle and the same rank the stage runs. The answer goes over
   the socket as a notification, `shadow`, `{"tool":"launcher","query":"...","keys":[...]}`, each
   key a row's memory key, since the app is connected anyway and a file plus a distributed
   notification would be a second road. File search keeps its road, since the app answers it from
   its own source.
5. **The comparison.** The app asks the bridged source for that query's rows, ranks them, and
   hands both lists to the shadow file search already uses, so the log is
   `~/.olm/log/shadow-launcher.jsonl` with the same fields. A row with no memory key is left out on
   both sides, a calculator answer among them, and a query a source claims compares the rows the
   claim leaves, which are fromQuery and left out, so it is logged as claimed rather than as same.
6. **The memory stays current.** After each pick the Lua launcher records, the bridge sends the
   notification `memory` with the queries that changed, as the protocol says, so the shadow ranks
   with the memory the Lua launcher ranks with.

## What has to grow for it

- **The row the app ranks.** `OlmKit`'s `Row` gains `keywords`, `names` and `tier`, and the
  searcher reads them, since the launcher's rows are found by their keywords and file search's are
  not. A keyword string is cut into phrases at its commas, as `rank.lua` reads one.
- **The memory, ported and pinned.** `lib/queryassoc.lua`'s store ported into `OlmSearch`, only so
  `olm-fixtures` can run `test/fixtures/ranking/memory.json` and `launcher.json`, which record
  picks and expect an order. The app itself only reads the memory Hammerspoon sends, through the
  same lookup the fixtures check. Stage 3, when the app records picks itself, finds the store
  already ported and pinned.
- **The socket setting on.** `socket = true` in `config/plugins.lua`. The bridge acts only where
  the olmapp piece is on, which is this Mac alone, so committing it changes no other machine.
- **The protocol.** The `shadow` notification joins it, Lua to app, read only, gone again at the
  flip of Hyper and Space, which is 3.5, corrected on 2026-11-13 from 3.2, the trial key.

## Tests

- `olm-fixtures` runs the two ranking fixtures above, the launcher's order with the memory.
- A Swift check program, as `olm-index-check` is for file search, starts the app's listener on a
  path of its own, connects as Hammerspoon would, replays `test/fixtures/bridge/launcher.json`'s
  answers to it, and checks the session, the patched rows and the bonus.
- `test/bridgeserve.lua` grows the `memory` notification and the launcher's `watch` and `held`.
- Live, after the dry gate and the unit cases, a reload, then the app built and relaunched, and the
  log read after a few queries typed by me through `hs` with no list shown, never the screen. Then
  the few days of Milos's own use the gate asks for.

## Back out

`socket = false` and a reload. The app listening with nobody connecting costs nothing.

## As built, 2026-11-13

- The app's end is the target `OlmBridge`, `JSON.swift`, `Frame.swift`, `Listener.swift`,
  `Bridge.swift` and `BridgedLauncher.swift`, with `QueryMemory.swift` in `OlmSearch`.
  `olm-bridge-check`, run by `test/olmbridge.sh` in the dry suite, is the check program above.
- `metrics` is not sent yet. No stage word asks the Lua side for a width before the app has a list
  of its own, so it joins at 3.2, where there is a list to measure.
- `limits.rowLimit` is the chooser's `chooser.rowLimit`, which the root hands `serveLauncher`, 50
  as shipped, rather than the 200 2.2 sent, since that is the limit the Lua stage cuts a list that
  names none at, so both sides rank to the same length.
- The memory store keeps a spelling's prefixes cut by bytes, so a query of letters outside ASCII
  can be stored cut inside a letter, which is not UTF-8 and would have failed the JSON of the whole
  open answer. `serve.lua` leaves such a spelling out, and the app walks a query's prefixes only
  at letter boundaries. A query reaching its memory only through such a cut, at least twelve bytes
  with a letter outside ASCII across the twelfth, is the one the two sides can rank apart.
- Live, with the lock, Hammerspoon connected to the app moments after it loaded, and fourteen
  queries through the launcher's supplier, among them an empty one, one letter cut at the row
  limit, a calculator answer, a capital and a claimed scope, all logged same.

## Two things Milos decided, 2026-11-13, both as proposed

1. **The socket setting.** Proposed: committed as `true`, since the olmapp piece already confines
   it to this Mac. The other way is a per machine row, which is a second switch for the same thing.
2. **How Lua's answer reaches the app.** Proposed: over the socket, the new `shadow`
   notification. The other way is file search's road, a file and a distributed notification, which
   needs nothing added to the protocol but leaves two roads to retire at the flip.
