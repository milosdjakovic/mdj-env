# Work packet, DockAutoHide becomes an Olm plugin with a launcher row

Written 2026-08-09 against feat/olm at `7ddbd64`, on the user's decision of this date. The
Dock auto hide tool moves out of its standalone spoon and into Olm as a plugin. It loses its
keyboard shortcut entirely and gains one launcher row instead, whose title names the action
it will take rather than the state it is in, so the row reads Turn Dock Hiding On while
hiding is off, and Turn Dock Hiding Off while hiding is on. StageManager, which was to be its
companion, was removed from the config entirely earlier today, so this plugin covers the Dock
alone. That is why it is a plain Dock plugin rather than a general toggle engine, one
consumer does not earn an engine, and a second system toggle later is when that shape gets
built.

## The facts from the scout of this date

A launcher command row today needs three cooperating places. A description entry in
`config/keys.lua` beside its siblings `displayProfiles`, `textCase`, and `processes`. One
`add` call inside `_buildActionRows` in `Spoons/Olm.spoon/host/launcher/init.lua`, guarded by
`if keys.<name> then`, whose signature is `add(title, subTitle, item, glyph, when, keywords)`
and whose `item` is the serializable descriptor `{ kind = "special", name = "<name>" }`. And a
leaf function under `actions.special` in the root's `Launcher:configure` call, which
`_runItem` dispatches to by that same name. ClipboardHistory is the precedent for one tool
owning several rows, each row being an independent description, add block, and dispatch entry.

Row titles are computed exactly once. `_ensureStaticRows` guards on `if self._actionRows then
return end`, so `_buildActionRows` runs on first open and its title strings live forever
after. The rows are consumed far more often, `_commandRows(query)` builds the final list on
every open and again on every keystroke, since the chooser atom's `queryChangedCallback` calls
`_build(q)` which calls the rows supplier. Measured cost of reading the Dock preference on this
machine is about five milliseconds, so resolving a title inside that per keystroke path would
be felt while typing. `show()` already increments `self._openId` once per open, which is the
natural thing to key a memo to.

The Dock spoon writes the preference with `defaults` and also drives System Events, and never
restarts the Dock. The suspicion is that the System Events call is what makes the change
visible and the plain write may be inert on its own, unproven.

`osascript` is already declared elsewhere as kind `system` at `/usr/bin/osascript` and already
carries a `DEPENDENCIES.map` row. `defaults` is declared nowhere yet. Every declaration nested
under Olm resolves through `depsFor("Olm")`, which is what every Olm plugin wiring site in the
root already uses. Line numbers drift, rescan.

## Decisions already made, build to these

One, the plugin. `Spoons/Olm.spoon/plugins/dockautohide/init.lua`, keeping the global name
`spoon.DockAutoHide` so nothing else has to learn a new word. It keeps reading state, enabling,
disabling, and toggling. It loses `bindHotkeys` entirely, since nothing will call it and dead
code is not carried across a move. It gains one method that answers the row wording from live
state, returning Turn Dock Hiding On when hiding is currently off and Turn Dock Hiding Off when
hiding is currently on. The plugin owns that wording, no other file spells those strings.

Two, the launcher seam, and it must stay generic. The launcher never learns what a Dock is.
`Launcher:configure` accepts a new injected table `actions.titles`, keyed by the same names as
`actions.special`, each value a function returning a string. A helper on the launcher resolves
a row's display title, answering the static string when no provider is registered for that
row's `item.name`, and otherwise calling the provider. The result is memoized against the
current `_openId` so it is computed once per open no matter how many keystrokes follow, and a
fresh open recomputes it. Every place that reads `row.title` to build the list the chooser
sees must go through that helper, including the `filterText` that concatenates title and
subtitle, so typing Turn or Hiding still finds the row. Nothing else about row building
changes and no other row's behavior may shift.

Three, the row. `config/keys.lua` gains a `dockAutoHide` description entry whose string is the
plain fallback used if no title provider is registered, and the `toggleDock` key entry goes
away with its comment. The add block sits beside the other system rows with a subtitle in the
established `System · ...` voice, a fitting glyph consistent with the existing set, and search
keywords covering dock and hide and hiding. The root registers both the action and the title
provider, the action calling the plugin's toggle and the title provider calling the plugin's
wording method.

Four, dependencies, declared rather than assumed. A `dependencies` file beside the plugin
declares `defaults` as kind `system` at `/usr/bin/defaults`, policy required since without it
the tool cannot read or write anything, and `osascript` as kind `system` at
`/usr/bin/osascript`, policy required or optional according to what finding six proves. Add the
`defaults` row to `DEPENDENCIES.map` in the shape its neighbours use for tools that ship with
macOS, `osascript` already has one. The plugin takes the resolved scope through its configure
call the way its sibling plugins do, using `depsFor("Olm")` at the wiring site, and asks that
scope for its paths rather than naming absolute paths in its own code or probing for anything.

Five, prove the redundancy rather than guessing. Determine empirically whether the plain
preference write, the System Events call, or both together are needed for the change to be
visible immediately and to survive a Dock restart. Toggle at most twice, observe, and return
the Dock to the state you found it in, this is the user's live machine and their Dock must end
exactly as it started. Keep the minimum that both applies immediately and persists, and if the
answer is genuinely ambiguous keep both calls, which is harmless. Write the finding into the
plugin's own `CLAUDE.md` as the reason the code looks the way it does.

Six, the original dies in this same pass. Delete `Spoons/DockAutoHide.spoon`, remove its
`hs.loadSpoon` block and its `bindHotkeys` wiring from the root, and update the committed
inventory snapshot so the spoon list and its count match. There is no toggle boolean here and
no validation loop, the tool is small and the launcher row is its own proof.

Seven, documentation. The plugin gets a `CLAUDE.md` in the house style, saying what it is, why
it has no key, why the title is dynamic and where that seam lives, and the finding from
decision five. Olm's own `CLAUDE.md` gains this plugin wherever it lists them. The launcher's
module documentation gains a short paragraph on the title provider seam, since a future row
will want it.

Eight, nothing else. No new keyboard binding anywhere, no change to any other row, no change to
any other plugin, and no restructuring of the launcher beyond the one seam.

## Gate

`luac -p` on every touched lua file. `test/units.sh` passes. `src/check-dependencies.sh` passes
with no new warnings and with the new declaration reconciled. `test/inventory.sh` three times,
each passing. After the land and the scheduled reload, the console is clean and the resolver
reports all present, and the declared count rises by the number of new rows the manifest gained.
The live proof is the user opening the launcher, seeing the row read the action rather than the
state, running it, reopening, and seeing the wording flipped.

## Deliverable

Commits on the branch, small steps, the packet first, then the plugin, the launcher seam, the
wiring, the deletion, and the docs. A report with the merge hash, each gate's numbers, the
resolver line, the finding from decision five stated plainly, and any decision that did not
survive contact with the code, flagged loudly.
