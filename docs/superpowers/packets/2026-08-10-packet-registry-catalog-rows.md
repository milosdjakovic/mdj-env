# Work packet, the launcher's catalog row moves onto the descriptor

Phase 7 of the build plan, packet three. Written 2026-08-10 against `feat/plugin-contract` after
packets one and two landed. Work in the worktree at `../.worktrees/plugin-contract` on the branch
already checked out there. Never work from the primary checkout, never push, never merge.

Phase 7 was planned as four packets and is now five. Packet three was going to fold the query
scopes and the catalog rows together. Measured, those are two substantial folds with separate
silent failure modes, so they are separated for the same reason packet one was separated from the
rest. This packet is the rows. Scopes are next, then the chords.

Read packets one and two before starting, and read
`Spoons/Olm.spoon/lib/registry.lua` and the registration block in the root.

## The gap this packet has to close before it moves anything

Nothing in this repository measures the launcher's rows. The inventory records spoons, chord keys,
cheat sheet entries, Hyper contexts, the navigation surfaces, and the registered tools, and not one
launcher row. So a row that vanished in this fold, or one that came back with the wrong subtitle,
would pass every gate we have.

**The first code commit is therefore instrumentation and nothing else.** Add a section to
`test/inventory.lua` recording every command row, read live through `spoon.Launcher:rowsOfKind`
for the special kind, sorted by name so the snapshot is stable, one line per row carrying the
row's name and its full subtitle. The subtitle is the part most likely to break quietly, since it
carries the chord label, the category, and the alias hint, so record it whole rather than
summarised. Update `test/inventory.golden` in the same commit.

That commit must change no behaviour at all. Its diff to the golden is one new section and nothing
else, and it becomes the baseline every later commit in this packet is measured against.

## What moves

Thirteen `add` calls in `Spoons/Olm.spoon/host/launcher/init.lua`'s `_buildActionRows` describe a
registered tool or one of its commands. Eleven are the tools, `colorPicker`, `emoji`, `caffeinate`,
`vpn`, `clipboard`, `browserTabs`, `displayProfiles`, `textCase`, `processes`, `dockAutoHide`, and
`fileSearch`. Two are clipboard commands, `appendCopy` and `pasteNext`.

Everything each of those thirteen reads out of the injected `keys` table, and every literal beside
it, is presentation data about one tool sitting in a file that is supposed to name no tool. That is
what moves onto the descriptor.

Eight `add` calls stay exactly where they are, the capture loop, the window management loop,
`lock`, `sleep`, `searchSettings`, `overlayDisplay`, and the alias directory. None of them is a
registered tool, and the alias directory is a scope whose fold is the next packet.

## The descriptor gains a row

`row`, optional, a table describing this tool's launcher row. A tool with no `row` gets none, which
is what a tool reachable only as a scope will want.

`keysName`, optional, the key in `config/keys.lua` this row reads its description and chord from,
defaulting to the tool's own name. Only the clipboard needs it, since its row reads
`keys.clipboardHistory` while the tool is named `clipboard`. Write it only there.

`category`, the word before the separator in the subtitle, `Tools`, `System`, `Network`,
`Clipboard`, `Displays`, or `Text` today.

`detail`, optional, the literal remainder of the subtitle for a row that does not show a chord.
When absent the launcher renders the chord label exactly as it does now. Never write both.

`glyph`, optional, a literal glyph. When absent the launcher takes the glyph from the keys entry,
which is what five rows do today. Never write both.

`keywords`, optional, the hidden search terms three rows carry today.

`chord`, optional, either absent for a Hyper chord, which is every tool, or the string naming the
other rendering. The two clipboard commands are a modifier combination rather than a Hyper chord
and their subtitle is built differently, so this field exists for exactly those two and must not be
generalised further.

A command inside `commands` may carry its own `row` with the same shape. That is how `appendCopy`
and `pasteNext` keep their rows while remaining commands of the clipboard rather than tools.

Validate `row` the way `surface` is validated. A `row` present and not a table is refused, naming
the tool. A `row` with no `category` is refused, naming the tool, since a subtitle with no category
would render wrong rather than absent, and wrong is worse. Add the refusals to the file's header
comment and to the unit cases.

## The registry gains one accessor

`rowFor(name)` answers the row table of an active tool or of a command of an active tool, or nil.
It resolves through the same flat index `run` uses, so a command's row is found under the command's
own name, and an inactive tool answers nil for itself and for every command it owns. That last part
is the point, it is what will make an inactive tool's rows disappear when the activation list
finally means something.

## The launcher

One local inside `_buildActionRows`, `addTool(name)`, which asks the injected registry for the
row, returns doing nothing when there is none, and otherwise builds the row exactly as the
thirteen hand written calls build theirs today, reading the description and the chord out of
`self._keys` under the row's `keysName` or the name itself.

Then replace the thirteen `add` calls with thirteen `addTool` calls, each in the position its
`add` call occupies now.

**The order is preserved exactly, call for call, and nothing is regrouped.** A used row floats on
recency, so this order governs only untouched rows, which is precisely the list a person sees on a
fresh install and after a reload. Changing it is a change to what the user sees and this packet is
not that.

Say plainly in a comment what this does not finish. Adding a tool still costs one `addTool` line
here, so this is not yet one registration. Removing that last line means moving the whole row
order into the composition root, which would take the capture loop and the window loop with it,
and that is a decision for later rather than a thing to sneak in.

The launcher must end this packet reading no tool's glyph, category, keywords, or description. It
reads a name, and it reads the keys entry that name points at. Check that by grepping the file for
every one of the eleven tool names and the two command names after you are done, and report what
you find.

## What not to change

Do not touch `queryScopes`, the `scope` helper, `QueryScope`, the alias directory, `aliasHint`, the
open predicates, `config/keys.lua`, `hyperContexts`, `hyperActions`, or any `HyperKey:bind` call.
Do not touch the capture loop, the window loop, or the four rows that are not tools. Do not change
`_glyphIcon`, `_chordLabel`, or `_glyphFor`. Do not gate a plugin's `dofile`, `configure`, or
`start` on the activation list.

Do not change the subtitle any row produces. Every one of the thirteen must come out byte identical,
and the inventory section added in your first commit is what proves it.

## Gates

`luac -p` parses every touched file.

`test/units.sh` passes, with new cases covering the two `row` refusals, `rowFor` answering a tool's
row, `rowFor` answering a command's row through its owner, `rowFor` answering nil for an inactive
tool and for every command that tool owns, and `rowFor` answering nil for an unknown name. Report
the assertion count before and after.

`src/check-dependencies.sh` passes with no new warnings.

`test/inventory.sh --check` three times. **The pass condition is the strongest in this phase so
far.** After your instrumentation commit establishes the baseline, every later commit must leave
the new launcher rows section byte identical, and the choosers section and every other section
byte identical too. The only golden change permitted in this whole packet is the one your first
commit makes. If any row's subtitle moves by a single character, that is a failing gate and a real
finding, not something to rebaseline. Print the launcher rows section from the baseline and from
the end state in your report so the equality can be checked by eye.

## Deliverable

This packet committed first. Then the inventory instrumentation with its golden. Then the registry
with its cases. Then the launcher and the root together, since a row's data leaving one and
arriving in the other is one change. Then the documentation. Small commits. Every message ends
after a blank line with

    Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>

and every subject has the form scope subject with no colon after the scope. Do not merge.

Documentation extends the Registry section of `Spoons/Olm.spoon/CLAUDE.md` rather than adding a
second one, covering the row fields, why `keysName` exists and that only one tool needs it, why
`chord` exists for exactly two commands, why the order was preserved rather than derived, and what
this leaves unfinished. The launcher's own `CLAUDE.md` has a paragraph saying adding a row is a new
entry in the build, which is now half true, so correct it there with what is actually required
today. Touch no other CLAUDE.md.

Report the accessor, the commit hashes, each gate's real numbers, the launcher rows section from
the baseline and the end state, the result of grepping the launcher for the thirteen names, and
anything in this packet that did not survive contact with the code, flagged loudly. If a decision
here turns out wrong once you can see the code, stop and say so rather than choosing for yourself.

Every line you author follows the repository writing rules, no colons, no semicolons, no hyphens or
dashes, periods and commas only. Copied names and existing identifiers keep their form.

## Hazards

The ordering hazard has now bitten three times in this phase, twice from a surface built by a later
`configure` and once from a local declared later in the same chunk. Anything you put on a
descriptor that is not plain data must be a closure, and anything you name inside a closure must
have its `local` statement lexically above that closure or it silently resolves to a nil global.
Row data is plain data and carries no such hazard, which is worth stating so nobody wraps it in a
function for the wrong reason.

Never run `bin/hs-devlock`, the inventory script owns the lock. Never call
`hs.logger.setGlobalLogLevel`. Never pass an angle bracket inside inline Lua to `hs -c`. Never call
`hs.reload` inline, schedule it with `hs.timer.doAfter` and poll `hs.configdir`. A console read can
take minutes and is not hung. Never run `git reset`, `git checkout` on a path, or `git stash` to
clean the tree, read `git status` and report instead. Never write an absolute path into any file.
