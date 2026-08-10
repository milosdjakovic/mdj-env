# Work packet, four tools leave Olm and stand alone again

Written 2026-08-08 against feat/olm at `c4088db`, executing the user's decision of 2026-08-07
recorded in the plan and the validation log. TerminalHandler, WorkspaceEngine, DockAutoHide,
and StageManager stay out of Olm for good. Each returns to its own standalone spoon,
initialized directly in the root `init.lua` the way it stood before the migration, and the
four olm plugin copies get deleted. This is one pass on one branch, `feat/extract-standalone`
from feat/olm, in a worktree under `../.worktrees/` beside the repo, never from main.

## The facts from the scout of this date

All four toggle blocks have the same minimal shape, a boolean, a true branch assigning the
spoon global from dofile of the olm plugin path, and a false branch calling `hs.loadSpoon`,
with no parity init line in any of them. StageManager sits near lines 96 to 105,
WorkspaceEngine near 153 to 162, TerminalHandler near 163 to 172, DockAutoHide near 197 to
206, locate each by searching since lines drift. Every copy is byte identical to its original
beyond the added header paragraph, exactly one commit ever touched the four copies, the
bundling commit, so nothing needs carrying back to the originals. None of the four declares
dependencies on either side, no depsFor call names them, and the manifest carries no rows for
them, so nothing about dependencies changes. All downstream wiring lives in the root and
reads plain spoon globals, StageManager is read by WindowManager's margin closure, the
WorkspaceEngine and TerminalHandler configure blocks inject AppToggler and WindowManager,
DisplayMemory reaches TerminalHandler only through a root side targetScreen closure, and
DockAutoHide takes a plain init and bindHotkeys. None of that changes.

## Decisions already made, build to these

One, each toggle collapses to its false branch. The block becomes one `hs.loadSpoon("Name")`
line preceded by a comment of one or two lines saying the user kept this tool standalone,
outside Olm, on the decision of 2026-08-07. The boolean and the dofile branch go away. The
established collapsed comment style of the retired blocks is the model, adapted to say
standalone rather than lives in Olm.

Two, the four copies die. Delete the directories
`Spoons/Olm.spoon/plugins/terminalhandler/`, `Spoons/Olm.spoon/plugins/workspaceengine/`,
`Spoons/Olm.spoon/plugins/dockautohide/`, and `Spoons/Olm.spoon/plugins/stagemanager/`.

Three, prose inside Olm that enumerates these four as plugins gets corrected in the same
pass. Grep `Spoons/Olm.spoon/CLAUDE.md` and the design references it keeps for the four
names, and where they are listed as olm plugins, remove or reword the entries to say they
stood alone again from this date. Only Olm's own file, the wider docs sweep stays a later
pass. Report the exact edits.

Four, nothing else. No dependency files, no manifest regeneration, no map row, no edit to
any original spoon, no docs ticks in the checklist, and the validation log edit below is the
landing step's own docs commit rather than part of the branch.

## Gate

`test/units.sh` from the worktree hammerspoon directory passes. `src/check-dependencies.sh`
from the worktree root passes with no new warnings. `test/inventory.sh` three times as
committed, each passing, the script owns the machine lock itself. After the land and the
scheduled reload, the console must show the four originals loading through `hs.loadSpoon`,
the Loading Spoon lines for TerminalHandler, WorkspaceEngine, DockAutoHide, and StageManager
are the positive proof the false branches took over, alongside the usual no errors after the
reload timestamp and the resolver summary at all present.

## Deliverable

Commits on the branch, small steps, each ending after a blank line with
Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>. After the merge to feat/olm with no
fast forward, run `stow -R -t ~ hammerspoon` from the dotfiles directory as cheap insurance
even though the deletions sit inside the folded Olm link, and verify the four olm plugin
paths are gone from the home view while the four original spoon directories still resolve.
Then the reload with the console gate above, then one docs commit on feat/olm appending to
each of the four sections in `docs/superpowers/specs/2026-08-07-olm-validation-log.md` a
sentence that the extraction landed at the merge commit, naming the hash, and that the tool
runs standalone again, boxes left unticked since these four left the loop. A report with the
merge hash, the docs hash, each gate's numbers, the four Loading Spoon console lines, and
any decision above that did not survive contact with the code, flagged loudly. Every line
you author follows the repository writing rules, no colons, no semicolons, no hyphens or
dashes, periods and commas only, copied lines keep their form.
