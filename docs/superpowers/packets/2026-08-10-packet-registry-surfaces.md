# Work packet, the navigation surface and the hosted bit fold into the descriptor

Phase 7 of the build plan, packet two of four. Written 2026-08-10 against `feat/plugin-contract`
after packet one landed. Work in the worktree at `../.worktrees/plugin-contract` on the branch
already checked out there. Never work from the primary checkout, never push, never merge.

Packet one built `Spoons/Olm.spoon/lib/registry.lua`, the descriptor, the five refusals, the api
version check, and the activation list, and proved them against one join point, the launcher's
special row dispatch. This packet folds two more join points into that same descriptor, the
`choosers` registry and `hostedInPlace`. Read packet one's file and the registry before starting.

## The ordering hazard, which is the whole reason to read this section first

Two of the surfaces this packet moves are built inside their own tool's `configure` and handed
back by a method. `spoon.Emoji:surface()` and `spoon.TextCase:surface()` both return a field that
`configure` created, and both of those `configure` calls run far below the registration block this
packet adds to. Writing `surface = spoon.Emoji:surface()` at a registration would therefore capture
nothing at all, permanently and silently, and the tool would simply never receive a navigation key
again with no warning anywhere.

That is why `open` in packet one is always a closure. Every field this packet adds obeys the same
discipline. **`surface` is a function returning the surface, never the surface itself.** The other
seven are plain module references and would survive either way, which makes this the worst kind of
hazard, one that works for most of the set and fails for two.

Two guards, both required. The registry refuses a descriptor whose `surface` is present and is not
a function, naming the tool. And when a surface is resolved and the result is missing or has no
`isShowing`, the registry logs one warning naming the tool and skips it, so the failure is loud at
the moment it would otherwise have been invisible.

## The descriptor gains two fields

`surface`, optional, a function of no arguments returning this tool's navigation adapter, the
object answering `isShowing` and whatever navigation methods its context binds. Refused when
present and not a function.

`hosted`, optional, true when choosing this tool's launcher row should host its list in place
rather than open its own picker. Nothing else, a plain boolean.

Nothing more. Not the scope, not the predicate, not the chord.

## The registry gains one accessor

`surfaces(spec)` takes an ordered list and answers an ordered list. A string entry names a
registered tool, and resolves to that tool's surface when the tool is active and has one, is
skipped silently when the tool is registered and inactive, since that is what inactive means, and
logs one warning naming it when nothing is registered under that name at all. Any entry that is not
a string passes straight through, which is how a surface with no tool behind it keeps its place.

The mixed list is deliberate and worth one comment in the file. A string names something the
registry knows. Anything else is an object the root holds and the registry has never heard of.

Resolution happens inside this call, never at registration, which is what the hazard section above
is about.

## The composition root

`dotfiles/hammerspoon/.hammerspoon/init.lua`.

**The nine surfaces that move.** Add a `surface` closure to the registrations for `clipboard`,
`caffeinate`, `vpn`, `displayProfiles`, `emoji`, `textCase`, `browserTabs`, `processes`, and
`fileSearch`, each returning exactly the expression that sits in the `choosers` table today. Two
registered tools get none, `colorPicker` because the eyedropper has no list, and `dockAutoHide`
because its list is rows inside the launcher rather than a picker of its own.

**The three that stay outside.** `spoon.Launcher:surface()` is the host that holds the registry, so
it cannot be a tool inside its own registry. `overlayDisplaySurface` is built from root local code
with no plugin behind it, and packet one's comment already says not to invent a plugin to tidy a
table. `menuSearchSurface` is a genuine plugin and has a surface, a scope, a predicate, and a
chord, everything a registered tool has except a launcher row, so it should become one, but not
here. Both it and its open function are forward declared locals assigned below the registration
block, so registering it means moving declarations, which is a different kind of edit from folding
a join point. Packet three registers it beside its scope, where the declarations are already in
scope. Write that reason down where the leftover sits, so the next reader knows it was decided
rather than missed.

**The list itself.** Replace the `choosers` table with one call to `registry.surfaces`, carrying
the same twelve entries in the same order, the nine as strings and the three as the objects they
are today.

Order is preserved exactly and that is not decoration. `activeChooser` answers with the first
surface that says it is showing, so the order decides the answer if two are ever up at once, and
nothing in the tree proves they cannot be. Preserving it costs one ordered list and removes the
question entirely, so do not reorder to suit the registry and do not sort.

**The hosted bit.** Add `hosted = true` to the registrations for `caffeinate`, `vpn`, `emoji`,
`fileSearch`, `browserTabs`, and `dockAutoHide`, which is six of the seven entries in
`hostedInPlace`. The seventh is the alias directory, which is a scope rather than a tool, so it has
no descriptor to carry the flag yet.

Then delete `hostedInPlace` entirely rather than leaving it holding one entry. In
`actions.rowIntercept`, the hosted test becomes the tool's own flag when the registry knows the
name, or the alias directory by name when it does not, with one comment saying the directory is a
scope and packet three is where it moves. A one entry table pretending to be a list is worse than
naming the one thing.

Two facts about that branch stay exactly as they are. It still asks `QueryScope:queryFor` for the
live alias and still falls through to the tool's own picker when there is none, and it still reads
the title from `config/keys.lua`. This packet moves where the boolean comes from and nothing else.

**Publishing the registry.** Assign the built instance to `spoon.Olm.registry` so the inventory can
read it live. The composition root publishing what it built is the point, and the rule that a
plugin never reaches for `spoon.Olm` is already enforced by `src/check-dependencies.sh`, which is
what makes the door safe to open. Write one comment saying both halves.

## The inventory, and why its diff cannot be empty this time

`test/inventory.lua` reads the `choosers` table as source text, matching
`local%s+choosers%s*=%s*{(.-)}` and recording one line per entry. This packet changes the shape
that pattern matches, so the pattern will stop matching and the snapshot will fail loudly, which is
correct behaviour and not a defect to work around.

Two changes there. Point the existing pattern at the new call so the section keeps measuring the
same twelve things, now read as nine names and three expressions. And add a new section reading
`spoon.Olm.registry.all()` live, one line per registered tool with its active flag, which is a
better net than a regex and is what will catch an accidental deregistration in packets three and
four.

Then update `test/inventory.golden` in the same commit as the change that moved it, never in a
commit of its own, so the golden is never a separate act from the thing it records.

## What not to change

Do not touch the open predicates. Twelve of them exist, exactly one per chooser entry, and each is
the same fact as a surface stated a second time, so folding them is the obvious next step and it is
deliberately not this packet. A predicate that silently always answers false disables a tool's
navigation with no gate anywhere that would catch it, and stacking that risk on top of this one
would leave a failure nobody could bisect. Say so in a comment beside them so the next reader knows
it was weighed.

Do not touch `queryScopes`, the `scope` helper, `_buildActionRows`, `config/keys.lua`,
`hyperContexts`, `hyperActions`, or any `HyperKey:bind` call. Do not register `menuSearch`. Do not
gate any plugin's `dofile`, `configure`, or `start` on the activation list. Do not add a field to
the descriptor that this packet does not name.

## Gates

`luac -p` parses every touched file.

`test/units.sh` passes, with new cases in `test/cases/registry.lua` covering the refusal of a non
function `surface`, a surface closure that resolves to nothing being skipped with a warning naming
the tool, a surface resolving to an object with no `isShowing` treated the same way, order
preserved across a spec list mixing names and objects, an inactive tool's surface skipped without a
warning, and an unknown name in a spec list warned about by name. Report the assertion count before
and after.

`src/check-dependencies.sh` passes with no new warnings. Report whether `spoon.Olm.registry`
triggers the core capability check, and if it does, resolve it the way packet one resolved the
`spoon.Olm.lib.registry` reference rather than by weakening the check.

`test/inventory.sh --check` run three times. **This gate is different from packet one's and read it
carefully.** The diff will not be empty. What is required is that every section other than the
choosers section is byte identical to the golden before your change, that the choosers section
still holds twelve entries, and that the twelve map one to one onto today's twelve. Print the
before and after of that section in your report so the mapping can be checked by eye, and state
plainly that every other section was unchanged. A diff anywhere else is a failing gate.

## Deliverable

This packet committed first, then the registry change with its cases, then the root, then the
inventory and its golden together, then the documentation. Small commits. Every message ends after
a blank line with

    Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>

and every subject has the form scope subject with no colon after the scope. Do not merge.

Documentation is the Registry section of `Spoons/Olm.spoon/CLAUDE.md`, which packet one wrote.
Extend it rather than adding a second section. It needs the two new fields, why `surface` is a
function and not a surface with the measurement that forced it, why the order of the surface list
is preserved rather than derived, what the mixed spec list means, why the alias directory is named
by hand for now, and why the predicates were left alone. Do not touch any other CLAUDE.md.

Report the accessor you wrote, the commit hashes, each gate's real numbers, the inventory section
before and after, and anything in this packet that did not survive contact with the code, flagged
loudly rather than worked around. If a decision here turns out wrong once you can see the code,
stop and say so rather than choosing for yourself.

Every line you author follows the repository writing rules, no colons, no semicolons, no hyphens or
dashes, periods and commas only. Copied names and existing identifiers keep their form.

## Hazards

Never run `bin/hs-devlock`, the inventory script owns the lock. Never call
`hs.logger.setGlobalLogLevel`, it floods every logger and pins the process. Never pass an angle
bracket inside inline Lua to `hs -c`. Never call `hs.reload` inline, schedule it with
`hs.timer.doAfter` and poll `hs.configdir`. A console read can take minutes and is not hung. Never
run `git reset`, `git checkout` on a path, or `git stash` to clean the tree, read `git status` and
report instead. Never write an absolute path into any file.
