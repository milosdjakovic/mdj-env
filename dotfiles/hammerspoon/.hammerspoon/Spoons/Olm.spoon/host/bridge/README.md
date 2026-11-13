# Bridge

The Lua side of Olm.app, the native app `docs/PLAN-STANDALONE.md` moves Olm into. Today it does one
thing, step 1.2. Where this machine's `olmapp` piece is on and the app is built, file search's open
key opens the app's file search through `olm://filesearch` rather than the Lua one, told to a running
app by the distributed notification `local.olm.Olm.open` and handed to one not running by `open`.

It shows nothing and binds nothing itself. The root asks it which tools the app serves, after the
keymap is built, and hands each such tool's open key its function. The keymap is unchanged, so the
key, its cheat sheet row and its launcher row stay where they are, and the Lua file search is still
reached from the launcher. Switching the piece off gives the key back on the next load.

Where the piece is on it also writes what the app reads of this config into `~/.olm/run/`, so the
config keeps one owner. `filesearch.json` is file search's types, limits, preview block and placeholder, from
`config/plugins.lua`. `chooser.json` is the swift chooser's look, both halves of its style, its
sizes, its layout, its motion and what a preview pane is laid out with, each half's under `pane`, which the root builds through the swift provider's `look` and
hands over with `share`, so the app's list looks like the Lua one. The open key's URL carries
Olm's placement choice at the press, which the root hands over with `placeWith`.

Where `config/plugins.lua` sets the bridge's `socket` to true and the piece is on, it also connects to
the Unix socket Olm.app listens on, `~/.olm/run/bridge.sock`, step 2.2, and serves the launcher there
read only, the catalog, the rows for a query and the query memory, as `docs/PROTOCOL-BRIDGE.md`
writes them. It connects on load and whenever the app posts `local.olm.Olm.listening`, retries quietly
while no socket is there, and serves nothing that could run a row. `frame.lua`, `rpc.lua` and
`serve.lua` beside it are pure and replayed by `test/bridgeserve.lua` and the transcripts under
`test/fixtures/bridge/`, `transport.lua` is the one file over `hs.socket`, and `test/bridgecheck.sh`
stands in for the app on the socket. The setting is on since step 2.3, and turning it off again is
the way back. After each pick the launcher records it tells the app the queries whose memory moved,
the `memory` notification, through `memoryChanged`, and a spelling the store cut inside a letter,
which is not UTF-8, never crosses.

It runs the shadow of step 1.3e for each tool `config/plugins.lua` lists under `shadows`, file
search today, where the piece is on. The Lua list stays the daily one, so `serves` is empty while
the shadow runs. Each answer the list settles on, after it has stayed put for `SHADOW_SETTLE`, is
ranked as the stage ranks it, without the bonus a person's use adds, and written to
`~/.olm/run/filesearchshadow.json`. Then a distributed notification, `local.olm.Olm.shadow` with the object `filesearch:N`, asks the app, started once hidden when the shadow is wired, to answer the same query with
its own engine, and the app appends what it found to `~/.olm/log/shadow-filesearch.jsonl`, one line
per query, `same` true or what differs. The root wires it through `shadowWith`, from the tool's
`watch` and `held` and its presentation's `searchText` and `rowLimit`, and names no tool.

The launcher is shadowed too since step 2.3, and its answers go the other road. The app holds the
launcher's level over the socket, so each settled answer is sent there as the notification `shadow`,
the query, whether a scope claimed it and the keys, each row's memory key, and the app ranks the
rows the bridge sends with the bonus it works out from the memory and logs to
`~/.olm/log/shadow-launcher.jsonl`. The root marks that tool's source `socket`, and names the
launcher only as the identity it already hands `serveLauncher`.

