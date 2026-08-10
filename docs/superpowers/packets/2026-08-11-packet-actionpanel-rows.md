# Work packet, Back leads and every row carries a glyph

Phase 8 of the build plan, the action panel, a follow up to packet two after a live test. Written
2026-08-11 against `feat/action-panel`. Work in the worktree at `../.worktrees/action-panel` on the
branch already checked out there. Never work from the primary checkout, never push, never merge.

Read `docs/superpowers/packets/2026-08-10-packet-actionpanel-swap.md` and the code it built before
starting, in particular `rowsFor` in `dotfiles/hammerspoon/.hammerspoon/init.lua` and
`Spoons/Olm.spoon/host/actionpanel/init.lua`.

Both findings came from the user driving the real thing. Neither is a mechanism problem, the panel
works, so nothing about the swap, the capture, the restore or the deferral changes here.

## Back leads

`rowsFor` appends Back after the verbs. The design says first row Back, and the user asked for the
same thing independently, so move it to the front. It is one line moving, and it is worth a moment
of thought about why it belongs there rather than at the end. The panel is a place you land in and
step back out of, so the way out is the thing your highlight is already sitting on when the list
opens, which makes leaving a single press. Its ordering in the snapshot is sorted rather than
positional, so update the comment above `rowsFor` that currently promises Back last, and check
whether `Spoons/Olm.spoon/host/actionpanel/CLAUDE.md` says the same thing anywhere.

## Every row carries a glyph

A panel row shows a title and a chord and no icon, which reads as unfinished beside every other
list in this configuration.

The mechanism already exists and is private. `Launcher:_glyphIcon(glyph)` in
`Spoons/Olm.spoon/host/launcher/init.lua` draws an emoji into a cached `hs.image` sized to line up
with real app icons, and the launcher is its only caller. The panel is now a genuine second
consumer, which is exactly the bar this repository sets before a helper is extracted, so extract it
rather than copying it or reaching into the launcher.

Move it to `Spoons/Olm.spoon/lib/glyphicon.lua`, a dot called module owning its own cache, in the
style `lib/recency.lua` and `lib/registry.lua` already use. The launcher keeps its `_glyphIcon`
method as the thin caller it becomes, so no launcher behaviour and no launcher row changes. Copy the
drawing exactly, the same canvas size, text size, alignment and frame, and the same `false` marking
a glyph that produced no image, since app rows and panel rows have to line up and any change to
those numbers is a visible change to the launcher this packet is not.

**A new `lib` module owes a core capability declaration.** `src/check-dependencies.sh` enforces
that every `spoon.Olm.lib` reference names one. Follow how `registry` was declared in phase seven
and run the reconciler, which should tell you plainly if you got it wrong.

## Where a glyph comes from

`config/keys.lua`, on the binding, beside `description`. That file already carries a glyph on its
tool entries, so this is the same data in the same place rather than a second convention, and it
keeps the panel's presentation as pure data the way every other row in this configuration is.

Ten verbs need one. Use these, which are a starting point the user can change in one line each
rather than a decision this packet is making permanently.

`appendSelected` gets ➕, `deleteSelected` gets 🗑️, `sortByLoad` gets 🔥, `stopForced` gets ⛔,
`refreshList` gets 🔄, `peekPreview` gets 👁️, `browseInto` gets 📂, `browseUp` gets ⬆️,
`revealInFinder` gets 🔍, and `copyPath` gets 📋. The Back row gets ⬅️, written where Back itself is
built rather than in `config/keys.lua`, since no context declares Back and nothing else should have
to know it exists.

A binding with no glyph yields no icon and says nothing about it. That is a legitimate absence
rather than a mistake, since a verb added later is allowed to arrive before somebody has picked its
emoji, and a warning there would be crying wolf. Do not add one.

`rowsFor` carries the glyph through onto the row it builds, and `ActionPanel:_buildRows` turns it
into the row's `image` through the new module, which is the field the chooser atom already reads.
Nothing else in the atom changes.

## The measurement

The `panelrows` section gains a glyph field on every row line, so a glyph going missing is a diff
rather than something noticed by eye months later. Everything else about that section stays as it
is, including that it is sorted rather than positional.

**Back leading is therefore invisible to the snapshot**, since the lines are sorted. Say so in your
report and say how you convinced yourself the order is actually right, by reading `rowsFor` back or
by any means that is not the golden, because this is the one change here that no gate can see.

## What not to change

Do not touch the swap, the capture, the restore, the deferral, `decorate`, `toggle`, `_leave`, or
any of the six wrapped functions. Do not change what a verb is, what any action classifies as, or
any `description` in `config/keys.lua`. Do not change the launcher's rows, its glyph sizing, or any
other consumer of `_glyphIcon`. Do not touch the hosted path, which is the next packet.

## Gates

`luac -p` parses every touched file.

`test/units.sh` from `dotfiles/hammerspoon/.hammerspoon` passes. It is 210 assertions today. Add
cases for the extracted module, a glyph answering an image, the same glyph answering the same
cached object twice, and nil answering nil. Add one for the panel's rows putting Back first and
carrying a glyph through onto the row. Report the count before and after.

`src/check-dependencies.sh` from the repository root passes with no new warnings, and the tree is
clean afterwards. This is the gate most likely to catch a mistake in this packet, since a new `lib`
module is exactly what it watches.

`test/inventory.sh --check` three times, five minute timeout on each. The `panelrows` section gains
its glyph field and nothing else moves, in particular `launcherrows` must be byte identical, which
is what proves the extraction did not change a single launcher row. Print the `panelrows` section in
full and print the `launcherrows` count line.

Do not live test this yourself and do not take the devlock. The user tests it.

## Deliverable

This packet committed first. Then the extraction, alone, with the launcher calling through to it
and no behaviour changed. Then the glyphs in `config/keys.lua` and the panel reading them. Then
Back moving to the front. Then the inventory and the golden together. Then the documentation. Small
commits. Every message ends after a blank line with

    Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>

and every subject has the form scope subject with no colon after the scope. Do not merge.

Report the commit hashes, each gate's real numbers, the `panelrows` section in full, how you
convinced yourself Back leads, and anything here that did not survive contact with the code.

Every line you author follows the repository writing rules, no colons, no semicolons, no hyphens or
dashes, periods and commas only, plain flowing prose rather than bullet lists. Copied names and
existing identifiers keep their form.

## Hazards

Never run `bin/hs-devlock` yourself. `test/inventory.sh` takes the lock and gives it back, and
killing it mid run strands the lock and blocks the user, which is why it gets five minutes. Never
call `hs.logger.setGlobalLogLevel`. Never pass an angle bracket inside inline Lua to `hs -c`. Never
call `hs.reload` inline, schedule it with `hs.timer.doAfter` and poll `hs.configdir`. A console read
can take minutes and is not hung. Never run `git reset`, `git checkout` on a path, or `git stash` to
clean the tree, read `git status` and report instead. Never write an absolute path into any file.
