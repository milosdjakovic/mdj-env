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

It runs the shadow of step 1.3e for each tool `config/plugins.lua` lists under `shadows`, file
search today, where the piece is on. The Lua list stays the daily one, so `serves` is empty while
the shadow runs. Each answer the list settles on, after it has stayed put for `SHADOW_SETTLE`, is
ranked as the stage ranks it, without the bonus a person's use adds, and written to
`~/.olm/run/filesearchshadow.json`. Then a distributed notification, `local.olm.Olm.shadow` with the object `filesearch:N`, asks the app, started once hidden when the shadow is wired, to answer the same query with
its own engine, and the app appends what it found to `~/.olm/log/shadow-filesearch.jsonl`, one line
per query, `same` true or what differs. The root wires it through `shadowWith`, from the tool's
`watch` and `held` and its presentation's `searchText` and `rowLimit`, and names no tool.

