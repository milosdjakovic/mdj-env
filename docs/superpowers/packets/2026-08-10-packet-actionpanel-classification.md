# Work packet, the verb classification and the measurement that has to exist first

Phase 8 of the build plan, the action panel, packet one of three. Written 2026-08-10 against
`feat/action-panel`. Work in the worktree at `../.worktrees/action-panel` on the branch already
checked out there. Never work from the primary checkout, never push, never merge.

Read `docs/superpowers/specs/2026-08-04-hammerspoon-olm-build-plan.md` phase 8, and the section of
`docs/superpowers/specs/2026-07-27-hammerspoon-olm-core-and-plugins-design.md` headed "The action
panel, every chooser's verbs as a searchable list", before starting. The design's line citations
have drifted repeatedly across this project, so verify every one you rely on.

## What this packet is not

It builds no panel, binds no key, and changes no behaviour a person can see. Nothing in it opens
anything, and after it lands every chooser behaves exactly as it does today. That is deliberate.

## The gap that has to be closed first

The action panel's whole promise is that it lists a chooser's verbs and never its navigation. That
distinction does not exist anywhere in this repository today. Every binding in `config/keys.lua` is
one undifferentiated shape, and nothing anywhere records which of them is a verb.

So a panel built before this packet would classify at the moment it drew, and a mistake in the
classification would be a row silently present or silently missing, in a list nobody has a
committed record of. Both gates in this repository would stay green. This is the same hole packet
three of phase seven found in launcher rows and packet five found in key bindings, and the answer
is the same one, measure the thing before moving it.

The measurement is also the interesting half of the design. Once every action is classified, the
verb list per context is a fact, and the gate for the whole phase, file search and the clipboard
having different verb sets and a third chooser having none, becomes a number in a committed file
rather than something a person checks by eye.

## The classification, decided here rather than left to the builder

The design settles what a verb is. The shared rows, moving up and down, insert, close, and the
preview scrolls, are navigation and the panel never lists them. The verbs are the things a person
forgets the chord for, and the design names reveal in Finder, copy path, and opening the folder as
its examples, which settles `browseInto` and `browseUp` as verbs rather than as movement.

Eighteen action names appear across the twelve contexts. Every one is classified, none is left to a
default, because a default is how a nineteenth action added later joins the wrong side in silence.

Navigation, eight. `selectNext`, `selectPrev`, `insertSelected`, `enter`, `closeChooser`,
`scrollPreviewDown`, `scrollPreviewUp`, `leavePage`.

Verb, ten. `appendSelected`, `deleteSelected`, `sortByLoad`, `stopForced`, `refreshList`,
`peekPreview`, `browseInto`, `browseUp`, `revealInFinder`, `copyPath`.

`leavePage` is navigation and also the one action with no entry in `contextActions`, since the
chooser atom reads Backspace for itself and the root only lists the key. It is classified anyway,
because the classification is about what a binding means and not about who runs it, and leaving one
action out would mean the completeness check below has an exception to remember.

## Where the classification lives, and why not in config/keys.lua

The design says the kind is stamped by the host, from a named set, per the named values rule. Read
that as the host owning the classification and `config/keys.lua` staying the pure data it says it
is. Putting `kind` on each of the sixty odd bindings by hand would be the same word written out
forty times for navigation alone, and the twelve contexts would drift against each other the first
time somebody added a thirteenth.

So the set of kinds is named by the module that defines the behaviour, and the map from an action
name to a kind is concrete policy in the composition root, beside `contextActions`, which is
already the one place that knows what every action name means. This is the same split the whole
config runs on, the engine names the set and the root names the members.

## The engine

New file, `dotfiles/hammerspoon/.hammerspoon/Spoons/Olm.spoon/host/actionpanel/init.lua`. A
configured singleton, colon called, in the shape `host/launcher` and `host/queryscope` already use,
never a dot called factory like `lib/registry.lua`. Find how the root loads and assigns those two
and follow it exactly, including the assignment to a `spoon.` global and the `init` call.

It exposes three things and nothing else in this packet.

`obj.kinds`, the named set, with a `navigation` member and a `verb` member. Two members, closed,
and the module validates membership against its own table rather than comparing to a literal
anywhere.

`obj:configure(deps)`, the one injection door. `deps.kindOf` is required, a function taking an
action name and answering a member of `obj.kinds` or nil. `deps.log` is optional and exists only so
a unit case can hand in a small table answering `w(message)` and read a warning back directly
without going through `hs.logger`'s shared process wide history, which is the same reason and the
same wording `lib/registry.lua` gives for its own `opts.log`. The composition root never passes it.
A missing or non function `deps.kindOf` raises, since that is a caller misusing the module rather
than a tool's own data, matching the line `lib/registry.lua` draws between the two.

`obj:verbsIn(bindings)`, taking a context's binding list and answering a new ordered list holding
only the bindings whose action classifies as a verb, in declaration order. It never mutates the
list it is given. A binding whose action classifies as navigation is dropped in silence, which is
the entire point of the function. A binding whose action classifies as neither, because `kindOf`
answered nil or answered something that is not a member of `obj.kinds`, is dropped and costs one
warning naming the action, since an unclassified action is a defect rather than a legitimate
absence. Dropping rather than keeping is the safer of the two, because the panel's promise is that
it never lists navigation, and an unclassified action that turns out to be navigation would break
that promise where an unclassified verb only goes missing loudly.

This function knows nothing about `needs`, about `when`, or about whether a chooser is open. Those
filters are the root's, they already exist as `bindingApplies` and `bindingActive`, and composing
them with this is packet two's work. Keeping them out is what makes this function a statement about
the declarations rather than about a moment, which is what lets the snapshot below stay true.

## The policy, in the composition root

Beside `contextActions` in `dotfiles/hammerspoon/.hammerspoon/init.lua`, a local table naming all
eighteen action names and the kind each one carries, written against `spoon.ActionPanel.kinds`
rather than against a bare string, since that is the named values rule the design cites. Then one
`spoon.ActionPanel:configure` call injecting a `kindOf` that reads that table.

Watch the ordering hazard that bit three times in phase seven. Whatever this touches must have its
`local` statement lexically above it, or Lua resolves the name to a nil global in silence.

**Then a completeness check, once at load and never per panel open.** Walk every binding of every
context in `keys.hyperContexts`, and warn naming the action for any whose name has no entry in the
table. Walk the table and warn naming the entry for any whose action no context uses any more. Both
are one line each at warning level, both name what they found, and neither raises, since a
classification gap should be visible and harmless rather than fatal at config load. This is the
recurring defect class from phase seven, silence where a warning belongs, answered before it can
happen rather than after.

Do not fold the check into `verbsIn`. The check is about the whole of `config/keys.lua` against the
whole of the policy, which is the root's business and is asked once, and `verbsIn` is about one
context's bindings, which is the engine's business and is asked every time the panel opens.

## The measurement

Two changes to `dotfiles/hammerspoon/.hammerspoon/test/inventory.lua`, and the golden regenerated
to match, in one commit.

First, the existing `hypercontexts.binding` line gains a `kind` field, asked of the live wiring
rather than of a copy, so what the golden records is what the root actually injected. Put it in the
line's existing field order somewhere stable and keep every other field exactly as it is, since the
lines are sorted as whole strings and moving a field reorders the section for no reason.

Second, a new section reporting, per context, the verb list the engine answers, again asked of the
live module rather than recomputed. Follow the shape the `hypercontexts` section already uses, a
count line, then one line per context carrying its name and its verb count, then the individual
verb lines sorted. A verb line carries at least the context, the key, the mods, the action, and the
description. Name the section for what it measures, a fact about the declarations, and say in a
comment that it is deliberately not filtered by `needs` or by a live predicate, so a later packet
that adds those filters to the panel does not read this section as stale and change it.

**The section is the baseline for the rest of phase eight.** Packets two and three must leave both
of these byte identical, since neither of them changes what a verb is.

## What the numbers have to be

Nine of the twelve contexts have no verb at all, `caffeinate`, `vpn`, `launcher`, `menuSearch`,
`displayProfiles`, `emoji`, `overlayDisplay`, `textCase`, and `browserTabs`. The clipboard has two,
`appendSelected` and `deleteSelected`. `processes` has three, `sortByLoad`, `stopForced`, and
`refreshList`. `fileSearch` has five, `peekPreview`, `browseInto`, `browseUp`, `revealInFinder`,
and `copyPath`.

Report these counts from the real run. If any of them differs, stop and tell me rather than
adjusting anything, because a different number means the classification above is wrong and that is
mine to fix, not yours. These twelve numbers are also exactly the phase's own gate, three choosers
with different verb sets and one with none, so they are worth being sure about.

## What not to change

Do not create a panel, do not add a row, do not bind or declare any key, and do not touch
`config/keys.lua` at all. Do not touch the chooser atom under `lib/chooser`, any file under
`Spoons/Olm.spoon/plugins`, the launcher, `QueryScope`, `lib/registry.lua`, the registrations, the
`hyperContexts` binding loop, `footerFor`, `hyperActions`, or `lib/panel.lua`. Do not add a
`kind` field to any binding in the data. Do not filter anything by `needs` or by a predicate.

## Dependencies

A new module may owe a declaration. Look at how the `registry` core capability was declared in
phase seven, in `dotfiles/hammerspoon/dependencies-collect` and whatever sits beside the code, and
follow the same pattern if this module owes one. Then run the reconciler and confirm the tree is
still clean afterwards, so no generated manifest drifted.

## Gates

`luac -p` parses every touched file.

`test/units.sh` from `dotfiles/hammerspoon/.hammerspoon` passes. It is 145 assertions today. Add a
case file for this module covering the raise on a missing `kindOf`, a verb kept, navigation
dropped, declaration order preserved, an unclassified action dropped with the warning read back
through the injected log, an action classified as something outside the set treated the same way,
and the input list left unmutated. Report the assertion count before and after.

`src/check-dependencies.sh` from the repository root passes with no new warnings, and the working
tree is clean afterwards.

`test/inventory.sh --check` three times, with a five minute timeout on each run. The golden changes
in exactly two ways, the new `kind` field on the existing binding lines and the new section.
Everything else is byte identical. Print the new section in full in your report, and print one
`hypercontexts.binding` line before and after so the field addition can be read.

## Deliverable

This packet committed first. Then the module with its unit cases. Then the root policy and the
completeness check. Then the inventory and the golden together. Then the documentation. Small
commits. Every message ends after a blank line with

    Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>

and every subject has the form scope subject with no colon after the scope. Do not merge.

Documentation is a new `CLAUDE.md` beside the module if that is what `host/launcher` and
`host/queryscope` do, otherwise a section in `Spoons/Olm.spoon/CLAUDE.md`. Match whichever
convention those two already follow rather than inventing a third. It covers what a kind is, why
the set is named rather than written as a string, why the classification is the root's and not
`config/keys.lua`'s, why an unclassified action is dropped rather than kept, and why the snapshot
section is unfiltered. Correct any existing sentence elsewhere that this packet makes false. Touch
no other `CLAUDE.md`.

Report the commit hashes, each gate's real numbers, the twelve verb counts, the new inventory
section in full, and anything in this packet that did not survive contact with the code, flagged
loudly. If a decision here turns out wrong once you can see the code, stop and say so rather than
choosing for yourself.

Every line you author follows the repository writing rules, no colons, no semicolons, no hyphens or
dashes, periods and commas only, plain flowing prose rather than bullet lists. Copied names and
existing identifiers keep their form.

## What comes next, for context only, build none of it

Packet two builds the panel itself on a tool's own chooser, and packet three handles a list hosted
inside the launcher. One thing found in the rescan is worth recording now. The design claims the
chooser atom already exposes everything the swap needs. It does not. `config.rows` is fixed at
construction with no setter, and the highlighted row number can be read and written only from
inside the atom, so packet two will need two small accessors and one injection door on
`Chooser.configure`. That is packet two's problem and nothing in this packet should anticipate it.

## Hazards

Never run `bin/hs-devlock` yourself. `test/inventory.sh` takes the lock and gives it back, and
killing it mid run strands the lock and blocks the user, which is why it gets five minutes. Never
call `hs.logger.setGlobalLogLevel`, it floods every logger and wedges the ipc port. Never pass an
angle bracket inside inline Lua to `hs -c`. Never call `hs.reload` inline, schedule it with
`hs.timer.doAfter` and poll `hs.configdir`. A console read can take minutes and is not hung. Never
run `git reset`, `git checkout` on a path, or `git stash` to clean the tree, read `git status` and
report instead. Never write an absolute path into any file. This packet adds a new file inside a
stow package, so say plainly in your report whether the inventory run saw it, since a new file that
the live config never loaded would make every gate meaningless.
