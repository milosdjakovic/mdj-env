# Work packet, launcher recency follows picks alone

Written 2026-08-08 against feat/olm at `83c8c54`, from the user's validation finding of
2026-08-07, the launcherRecency order follows any app focused on the machine while it should
follow only apps actually picked through the launcher. The fix lands on the olm copy at
`Spoons/Olm.spoon/host/launcher/init.lua`, the original `Spoons/Launcher.spoon` stays
untouched and falls behind by exactly this fix, acceptable since it exists only as the toggle
fallback until its own retirement. Work on `feat/launcher-recency` from feat/olm in a
worktree under `../.worktrees/`, never from main.

## The facts from the scout of this date

Every persistence write goes through one function, `Launcher:_promote` near lines 112 to 128,
writing the `launcherRecency` settings key. Four call sites. The chooser onSelect near line
175 and the intercept near line 201 are genuine launcher picks and stay. The start seed near
lines 841 to 843 promotes whatever app happens to be frontmost when the config starts, and
the hs.application.watcher callback near lines 844 to 854 promotes every app activation on
the machine, both ambient. The watcher also does a second unrelated job, clearing
`_appRowsCache` and `_orderedRowsCache` on activated, launched, and terminated, which must
survive. The sole reader is `_orderedRows` near lines 514 to 537, internal. Nothing else in
the tree reads the key, calls the writer, or shares the watcher, and the shared
`lib/recency.lua` service is not involved. Line numbers drift, rescan.

## Decisions already made, build to these

One, the activated branch of the watcher callback keeps its cache invalidation and loses its
promote line. The launched and terminated branches stay whole.

Two, the start seed promote goes too, the frontmost app at reload time was never a pick.
Whatever surrounding lines exist only to serve that seed go with it, whatever also serves
the watcher setup stays, read before cutting.

Three, the prose that described ambient feeding as intended design gets rewritten to match,
the two observers block near lines 72 to 84, the start doc comment near lines 832 to 836,
and the Recency ordering section of the launcher module `CLAUDE.md` beside the init file.
Say the timeline is fed by launcher picks alone, on the user's decision of 2026-08-07, and
that the app watcher remains only to refresh the running set. Authored lines follow the
repository writing rules.

Four, the persisted list is not cleared, not migrated, and not rewritten. Entries that
ambient focus wrote before this fix decay naturally past the cap as real picks accumulate.
The settings key name and the cap stay byte for byte.

Five, nothing else. No change to the original spoon, no change to any other tool, no
dependency work.

## Gate

`test/units.sh` from the worktree hammerspoon directory passes. `src/check-dependencies.sh`
from the worktree root passes with no new warnings. `test/inventory.sh` three times as
committed, each passing. A luac parse of the touched file. The live feel is the user's
revalidation, not your gate.

## Deliverable

Commits on the branch, small steps, each ending after a blank line with
Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>. Then land, merge to feat/olm with no
fast forward, reload scheduled never inline, the console gate scoped to the fresh load with
the resolver summary at all present, and one docs commit on feat/olm appending to the
Launcher section of `docs/superpowers/specs/2026-08-07-olm-validation-log.md` a short
paragraph naming the finding, this fix, the merge hash, and awaiting the user's
revalidation, boxes untouched. A report with the merge hash, the docs hash, each gate's
numbers, the exact lines removed, and any decision that did not survive contact with the
code, flagged loudly. Every line you author follows the repository writing rules, no colons,
no semicolons, no hyphens or dashes, periods and commas only, copied lines keep their form.
