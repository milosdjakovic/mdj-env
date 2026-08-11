# Work packet, a hosted list carries its own verbs

Phase 8 of the build plan, the action panel, the last packet. Written 2026-08-11 against
`feat/action-panel` after packets one and two landed and the user drove the panel by hand. Work in
the worktree at `../.worktrees/action-panel` on the branch already checked out there. Never work
from the primary checkout, never push, never merge.

Read the two earlier packets and the code they built. Read
`Spoons/Olm.spoon/host/queryscope/init.lua` in full, `actions.rowIntercept` and `rowsFor` in
`dotfiles/hammerspoon/.hammerspoon/init.lua`, and `enterPage` and `_commandRows` in
`Spoons/Olm.spoon/host/launcher/init.lua`.

## The gap, which the configuration named itself long before this

`actions.rowIntercept` in the root carries a comment saying that a hosted list does not carry the
tool's own verbs, only the shared navigation, and that the gap closes when a scope can carry a
tool's extra verbs. The design quotes that sentence and says the action panel is that sentence
built. This packet is that.

Concretely. Open the launcher, choose the file search row, and its list appears inside the launcher
rather than in its own picker. The live context is `launcher`, whose only bindings are navigation,
so the panel offers Back and nothing else. Worse, even if it offered Reveal in Finder, running it
would do nothing at all, because `contextActions` sends every verb through `routeNav`, `routeNav`
asks which surface is showing, the answer is the launcher, and the launcher has no `reveal` method,
so the method guard makes it a silent no operation.

So two separate problems. Working out whose verbs to show, and making one of them actually run
against a row in somebody else's list.

## Showing the right verbs

The launcher stores only `_page`, an opaque query prefix, and nothing anywhere maps that back to a
tool. But `QueryScope:resolve` already parses a leading alias out of any query and answers the
scope, which carries the tool's own name, so the mapping exists as a capability and simply has
never been asked for.

Give the launcher one accessor answering the whole query its rows are currently being built from,
which is `_page` followed by whatever is typed, exactly the string `_commandRows` already assembles
for itself. One accessor rather than exposing `_page` raw, because the caller should not have to
reassemble something the launcher already knows how to say, and because it makes the typed case and
the chosen case answer the same way. Typing the file search alias and a space into the launcher
shows the same rows as choosing its row does, and both should offer the same verbs.

Then in the root's `openActionPanel`, when the live context is the launcher, resolve that query
through `QueryScope` and, when it names a scope, hand the panel that tool's context name instead of
the launcher's. Nothing in `ActionPanel` changes for this. It is told which context's rows to show
and it has never cared how the root decided.

## Making a verb run

The registry descriptor's `scope` gains `verbs`, an optional map from an action name to a function
taking the row's payload. That is the tool saying, once, which of its verbs make sense when
somebody else is holding its list. Validate it the way the other scope fields are validated, a
`verbs` present and not a table is refused naming the tool, and a value inside it that is not a
function is refused naming the tool and the action.

`QueryScope` gains `verbFor(item, action)`, answering a callable or nil, mirroring `actFor` exactly,
same routing home through the item's own scope, same `pcall` wrapping so a scope that raises costs
a console line rather than a broken chooser, and answering a callable rather than having already
run for the same reason `actFor` gives.

The panel's injected `run` grows a second argument, the item the panel captured, so the root can
route on it. The panel already holds `_capturedItem` and hands it straight through, and this is the
only change to `ActionPanel` in the whole packet.

The root's `run` then asks `verbFor` first and falls through to `contextActions` when it answers
nil. No branch on whether anything is hosted is needed anywhere, because a row from a tool's own
picker is not a scope row and answers nil by construction, so the ordinary path is untouched by
being second.

## Which verbs file search declares, and why not all five

File search is the only tool this affects. Six tools are marked `hosted`, and of those only file
search has any verb at all, so every other hosted list already shows Back alone and correctly
continues to.

Declare three, `revealInFinder`, `copyPath`, and `peekPreview`. The first two are the gate. The
third is nearly free and worth having, because `chooser.peekRow(row)` already exists in the plugin,
split out of `peekPreview` for exactly this case, and its own comment says why, that a caller
holding its own list is a different owner with a different lifetime and must not be held to this
picker's. That is the precedent this whole packet follows.

Do not declare `browseInto` or `browseUp`. They are about moving through a list rather than acting
on a row, they work by rewriting the query, and inside the launcher that means driving the
launcher's own page mechanism, which is a real design question and is not this. Say that in a
comment where the verbs are declared, so the absence reads as a decision rather than an oversight.

**A verb the scope does not declare is not offered at all in a hosted list.** No greyed row, no row
that does nothing. The hosted panel lists exactly what can actually happen, which is the honest
answer and needs no new concept to express.

## The plugin gains two row taking entry points

`chooser.reveal()` and `chooser.copyPath()` both read the highlighted row out of file search's own
private picker, so neither can act on a row the launcher is holding. Split each the way
`peekPreview` and `peekRow` are already split, a function taking a row and doing the work, and the
existing no argument function becoming the thin caller that reads its own highlighted row and
passes it in. One implementation each, two entry points each, and the existing behaviour byte for
byte unchanged.

Copy exactly what each already does, including `noteUse` and including which of them hides the
picker afterwards, and think about that last part rather than copying it blindly. Hiding file
search's own picker is right when the verb ran from that picker. When it ran from the launcher,
that picker is not open and hiding it must be harmless, but the launcher probably should close the
way it does when a scope row is run. Work out what actually happens, say what you found, and if the
right answer is not obvious from the code, stop and tell me rather than guessing.

## The chord column, a question the design left open

The design's own open questions end by asking whether a hosted list's panel should show the chord
for a verb whose chord is not active there, notes that showing it is honest but could teach a chord
that will not work until the tool is opened directly, and says to decide it when it is built.

Decided. Show the chord, qualified by where it works, so the row reads as the chord followed by the
name of the list it belongs to, taken from that tool's own description in `config/keys.lua`. The
chord is worth teaching, that is the whole reason this feature exists, and a bare chord that does
nothing where it is printed is the one thing that would be a lie. Record the decision in the design
document by replacing that open question with the answer, since leaving a settled question open is
how it gets decided a second time differently.

## The measurement

`rowsFor` takes the hosted case as an explicit argument rather than working it out by asking the
launcher, so that `test/inventory.lua` can ask for the hosted rows of every context with nothing
open, exactly as it already asks for the ordinary rows of all twelve.

Add a section recording, per context, the rows a hosted list would show. Today only file search
answers anything beyond Back, so the section is mostly Back rows and one interesting entry, and
that is fine. It is the only measurement of this path that exists, and it is what would catch a
scope's verb quietly disappearing.

Everything from packets one and two stays byte identical, `actionpanel`, `panelrows`,
`actionpaneldecorated`, `launcherrows`, `choosers`, `tools`, `hyperkey`, `hotkeys`, and the spoon
list. The `scopes` section may gain nothing since `verbs` is not part of what it reports, so check
rather than assume.

## Verify rather than assume

A hosted row's item is `{ kind = "scope", scope = name, payload = r.item }`, built in
`QueryScope:rows`. So the payload handed to a verb is whatever the file search scope's own `rows`
put in each row's `item` field. **Confirm what that actually is and that it carries what `reveal`
and `copyPath` need before writing either.** If it is not the same shape the plugin's own
`selectedRow` answers, stop and tell me, because then the split above needs rethinking rather than
adapting.

## What not to change

Do not change the swap, the capture, the restore, the deferral, `decorate`, `toggle` beyond passing
the captured item through, or any of the six wrapped functions. Do not change what a verb is or what
any action classifies as. Do not change `routeNav`, `activeChooser`, or the `choosers` list. Do not
change the launcher's rows, its page mechanism, or `enterPage` beyond the one accessor. Do not
declare verbs on any scope other than file search. Do not touch `hyperActions`.

While you are in `Chooser:selectRow`, add a nil guard so a nil row number answers by doing nothing
rather than raising on a comparison. It cannot be reached today and it is one line.

## Gates

`luac -p` parses every touched file.

`test/units.sh` from `dotfiles/hammerspoon/.hammerspoon` passes. It is 217 assertions today. Add
cases for the registry refusing a bad `verbs` and accepting a good one, `QueryScope:verbFor`
answering a callable for a declared verb and nil for an undeclared one and for a row that is not a
scope row, the root's run preferring a scope verb and falling through when there is none, and the
hosted rows carrying only the declared verbs with qualified chords. Report the count before and
after.

`src/check-dependencies.sh` from the repository root passes with no new warnings, and the tree is
clean afterwards.

`test/inventory.sh --check` three times, five minute timeout on each. Print the new section in full
and print the `panelrows` and `launcherrows` count lines to show they did not move.

Do not live test this yourself and do not take the devlock. The user tests it, and the phase's own
gate is exactly this case, a file search list inside the launcher offering reveal and copy path
even though their chords are not active there.

## Deliverable

This packet committed first. Then the plugin's two row taking entry points, alone, with the
existing functions calling through and nothing else using them. Then the registry field with its
cases. Then `QueryScope:verbFor` with its cases. Then the launcher accessor. Then the root, the
scope's verbs, the resolution, the run routing and the hosted rows. Then the inventory and the
golden together. Then the documentation. Small commits. Every message ends after a blank line with

    Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>

and every subject has the form scope subject with no colon after the scope. Do not merge.

Documentation covers the hosted path in `Spoons/Olm.spoon/host/actionpanel/CLAUDE.md`, the new scope
field in `Spoons/Olm.spoon/CLAUDE.md`'s Registry section and in the queryscope `CLAUDE.md` if one
exists, and the chord column decision in the design document as described above. The comment in
`actions.rowIntercept` that says the gap closes when a scope can carry a tool's extra verbs is now
false, since the gap has closed, so make it say what is true.

Report the commit hashes, each gate's real numbers, what the hosted payload turned out to be, what
you found about hiding the picker, the new inventory section in full, and anything in this packet
that did not survive contact with the code, flagged loudly.

Every line you author follows the repository writing rules, no colons, no semicolons, no hyphens or
dashes, periods and commas only, plain flowing prose rather than bullet lists. Copied names and
existing identifiers keep their form.

## Hazards

The ordering hazard bit three times in phase seven, and the scope's verbs are declared in the
registration block, which is exactly where it bit. Every name inside those closures must have its
`local` statement lexically above the registration or Lua resolves it to a nil global in silence.

Silence where a warning belongs produced six of ten review findings in phase seven. A verb the scope
does not declare is a legitimate absence and says nothing. A verb that is declared but whose
payload is not what it expected is a mistake and must name itself.

Never run `bin/hs-devlock` yourself. `test/inventory.sh` takes the lock and gives it back, and
killing it mid run strands the lock and blocks the user, which is why it gets five minutes. Never
call `hs.logger.setGlobalLogLevel`. Never pass an angle bracket inside inline Lua to `hs -c`. Never
call `hs.reload` inline, schedule it with `hs.timer.doAfter` and poll `hs.configdir`. A console read
can take minutes and is not hung. Never run `git reset`, `git checkout` on a path, or `git stash` to
clean the tree, read `git status` and report instead. Never write an absolute path into any file.
