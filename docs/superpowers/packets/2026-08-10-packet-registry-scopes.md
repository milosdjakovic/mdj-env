# Work packet, the query scope moves onto the descriptor

Phase 7 of the build plan, packet four of five. Written 2026-08-10 against `feat/plugin-contract`
after packets one, two and three landed. Work in the worktree at `../.worktrees/plugin-contract`
on the branch already checked out there. Never work from the primary checkout, never push, never
merge.

Read packets one through three and `Spoons/Olm.spoon/lib/registry.lua` before starting.

## The move that has to happen first, and why it is the whole trick

Every earlier packet fought the same hazard. A descriptor is built at roughly line 1411 in
`dotfiles/hammerspoon/.hammerspoon/init.lua`, and most of what a tool is made of does not exist
yet at that point. Surfaces were solved with closures. Rows were plain data and needed nothing. A
scope cannot be solved either way, because a scope's `rows` and `run` are the very functions that
are assigned hundreds of lines below, and `scopeMenuRows` and `scopeMenuRun` are not merely
unassigned there, their `local` statement itself sits below, so naming them in a closure written at
1411 would silently reach a nil global instead.

The answer is not more closures. It is that the registrations are simply in the wrong place.

**Move the `registry.register` calls, the `registry.activate` call, and the `spoon.Olm.registry`
publish down to sit immediately above the `queryScopes` table.** Leave `registry.new` where it is,
since `spoon.Launcher:configure` needs the instance to inject and only stores the reference.

Nothing reads the registry during load. `rowIntercept` and `addTool` both hold it as an upvalue and
call it when a row is chosen or when the launcher first builds its rows, which is after load in
both cases, and `registry.surfaces` already runs far below. So an instance created early and filled
late is correct, and it is ordinary composition root sequencing, you build the container where a
collaborator needs the reference and you fill it once everything it describes exists.

The move pays for itself three times over. Every declaration a scope could need is above the new
position, so scopes need no closures and no discipline. The emoji scope's condition,
`spoon.Emoji:lists()`, can finally be asked at registration because that spoon is configured by
then. And menu search stops needing a declaration move to be registered at all.

**Do this as its own commit, a pure move with not one character of the moved lines changed.** The
whole point is that the diff can be read as a move and nothing else.

## The descriptor gains a scope

`scope`, optional, a table carrying exactly the fields the `scope` helper passes through today,
`matcher`, `rows`, `run`, `peek`, `redirect`, and `act`. Nothing else. The identity fields the
helper adds, `name`, `title`, `glyph` and `aliases`, are not on the descriptor and must not be,
because three of them come from `config/keys.lua` and this registry reads no configuration.

Validated the way `row` is. A `scope` present and not a table is refused, naming the tool. A
`scope` whose `rows` or `run` is missing or is not a function is refused, naming the tool and which
one, since `QueryScope` requires both and would otherwise reject the assembled scope later with a
line that names the scope rather than the registration that produced it. Any of `matcher`, `peek`,
`redirect` or `act` present and not of the right type is refused, naming the tool and the field.
`matcher` is the one that is not a function, it is `false` on four scopes today, so accept `false`
or a function and refuse anything else.

The registry gains `scopeFor(name)`, answering the scope table of an active tool or nil, in the
same shape as `rowFor`.

## The composition root

Move seven scopes onto their tools' descriptors, `caffeinate`, `dockAutoHide`, `vpn`,
`browserTabs`, `fileSearch`, `emoji`, and `menuSearch`. Copy each body exactly as it stands. The
emoji one keeps its condition, now asked inline at registration since the move above makes that
possible, so its descriptor carries a scope only when `spoon.Emoji:lists()` answers.

**Menu search becomes the twelfth registered tool.** It has a surface, a scope, an open predicate
and a chord, everything a registered tool has except a launcher row, and the move above removes the
only reason it could not be registered. Give it `name`, `apiVersion`, `open` and `surface` as
closures, and its scope. Do not give it a `row`, since it has none today and adding one is a
visible change to your launcher that this packet is not. Do not give it `hosted`, since it is not
hosted today.

**Add `menuSearch` to `settings.toolActivation`.** This is the one step that will quietly ruin the
packet if it is missed. A registered tool absent from the activation list is inactive, and an
inactive tool now answers nil to `surfaceFor`, `rowFor` and `scopeFor` alike, so menu search would
lose its navigation keys and its scope in one go with nothing failing loudly. The list becomes
twelve.

Then replace `menuSearchSurface` with the string `"menuSearch"` in the `registry.surfaces` spec,
in the position it already occupies, which leaves `spoon.Launcher:surface()` and
`overlayDisplaySurface` as the only two objects still passed through by hand.

**Build `queryScopes` from an ordered spec**, the same shape `registry.surfaces` takes, since a
string naming a registered tool and an object the registry never heard of is a distinction that
already has a precedent here. The order is preserved exactly, entry for entry, because
`QueryScope` gives a colliding alias to whichever scope claims it first, so order decides who owns
a word. The four that stay as objects are the three `launcherCatalogScope` scopes, `apps`,
`windowActions` and `settingsPanes`, which narrow the launcher's own catalog rather than reaching a
tool, and the alias directory, which is a scope about scopes with no tool behind it.

The root's `scope(name, opts)` helper stays and keeps doing the `config/keys.lua` join. A string
entry resolves through `registry.scopeFor` and is then passed through that same helper, so the
identity fields are added in exactly one place as they are today.

## The cross check, and why it is a snapshot rather than a warning

The point of scopes joining the registry is that a tool marked `hosted` with no scope behind it
becomes visible. Today those two facts live in different tables with nothing comparing them, and
the only symptom of a mismatch is a row that opens a picker instead of hosting, which reads as
ordinary behaviour.

The obvious answer is a warning at assembly time, and it is wrong. The emoji scope is registered
only when its backend owns a list, so with the Character Viewer fronted, emoji is legitimately
hosted with no scope, and that is documented existing behaviour rather than a defect. A warning
would cry wolf on the one case the design deliberately built.

So record it instead. Add `scope` presence to what `all()` reports, beside `surface` and `hosted`,
which puts it in the inventory golden. A tool that is hosted with no scope then reads as
`hosted=true scope=false` in a committed file, so the legitimate case is visible and stable and any
drift is a diff against the golden. That is a stronger net than a log line nobody reads, and it
costs one field on a function that already reports three.

Say all of this in the documentation, including that the warning was considered and rejected, so
nobody adds it later thinking it was overlooked.

## What not to change

Do not change any scope's body, not one character, in the move or the fold. Do not give menu search
a row or a hosted flag. Do not touch the open predicates, the alias directory's own scope body,
`aliasHint`, `enterScope`, `_buildActionRows` beyond nothing at all, `config/keys.lua`,
`hyperContexts`, `hyperActions`, or any `HyperKey:bind` call. Do not gate a plugin's `dofile`,
`configure`, or `start` on the activation list, which is the last packet's work.

Do not remove the `scope` helper or `launcherCatalogScope`. Do not change `QueryScope` at all.

## Gates

`luac -p` parses every touched file.

`test/units.sh` passes, with new cases covering every scope refusal named above, `scopeFor`
answering an active tool's scope, `scopeFor` answering nil for an inactive tool and for an unknown
name, and `all()` reporting scope presence. Report the assertion count before and after.

`src/check-dependencies.sh` passes with no new warnings.

`test/inventory.sh --check` three times. The golden changes in exactly two ways and no others. The
`registry tools` section gains a twelfth entry for menu search and gains a `scope` field on every
line. The `registry choosers` section changes `menuSearchSurface` to `"menuSearch"` in the position
it already held. Everything else, and the whole of the launcher rows section in particular, is byte
identical. Print the tools section and the choosers section before and after in your report.

**The move commit is its own gate.** Run the three inventory checks after the move and before the
fold, and report that the golden was completely unchanged at that point. A move that changes the
snapshot is not a move.

## Deliverable

This packet committed first. Then the move, alone. Then the registry with its cases. Then the root
fold. Then the inventory and golden together. Then the documentation. Small commits. Every message
ends after a blank line with

    Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>

and every subject has the form scope subject with no colon after the scope. Do not merge.

Documentation extends the Registry section of `Spoons/Olm.spoon/CLAUDE.md`, covering the scope
field and its refusals, why the identity fields are not on the descriptor, why the registrations
moved and what that bought, why menu search could not be registered before and can now, why the
scope order is preserved rather than derived, and the cross check reasoning above including the
rejected warning. `Spoons/Olm.spoon/host/queryscope/CLAUDE.md` if it exists should say where a
scope now comes from. Touch no other CLAUDE.md.

Report the accessor, the commit hashes, each gate's real numbers, the two golden sections before
and after, the confirmation that the golden was unchanged by the move commit, and anything in this
packet that did not survive contact with the code, flagged loudly. If a decision here turns out
wrong once you can see the code, stop and say so rather than choosing for yourself.

Every line you author follows the repository writing rules, no colons, no semicolons, no hyphens or
dashes, periods and commas only. Copied names and existing identifiers keep their form.

## Hazards

Never run `bin/hs-devlock`, the inventory script owns the lock, and give that script a five minute
timeout, since killing it mid run strands the lock. Never call `hs.logger.setGlobalLogLevel`. Never
pass an angle bracket inside inline Lua to `hs -c`. Never call `hs.reload` inline, schedule it with
`hs.timer.doAfter` and poll `hs.configdir`. A console read can take minutes and is not hung. Never
run `git reset`, `git checkout` on a path, or `git stash` to clean the tree, read `git status` and
report instead. Never write an absolute path into any file.
