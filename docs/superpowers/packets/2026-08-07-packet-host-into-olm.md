# Work packet, the host into Olm

Written 2026-08-07 against feat/olm at `d53dccc`, on the user's word that everything moves
into Olm now. The three host spoons, Launcher, QueryScope, and HyperCheatSheet, are the last
originals still loading, and they become copies under `Spoons/Olm.spoon/host/` behind three
root toggles, byte faithful with no reshape, the reshape stays with phases 7 and 8 and will
happen on these copies. The design names exactly these three as the host and gives the path
shape `host/launcher`, `host/queryscope`, `host/hypercheatsheet`, near its lines 311 to 313
and 359. Work on a branch named `feat/host-into-olm` from feat/olm, never from main, in a
worktree under `../.worktrees/` beside the repo.

## The facts from the rescan of this date

Launcher is `Spoons/Launcher.spoon/`, an `init.lua` of 933 lines plus a `CLAUDE.md`, loaded
at root line 252 with 22 reference lines all after the load, a real `init` at its lines 100
to 107, real `start` and `stop`, the `launcherRecency` settings key, and the three app
directory paths. QueryScope is `Spoons/QueryScope.spoon/`, an `init.lua` of 376 lines plus a
`CLAUDE.md`, loaded at line 358 with 12 reference lines all after the load, a real `init`, no
start or stop. HyperCheatSheet is `Spoons/HyperCheatSheet.spoon/`, a single `init.lua` of 192
lines, loaded at line 97 with 4 reference lines all after the load, a pure `init`. None of
the three uses `debug.getinfo`, `spoonPath`, `spoonMeta`, or any `hs.loadSpoon` mechanic to
find its own files, none declares any dependency, and no row of the generated manifest names
any of them, so nothing about dependencies changes in this pass. The root explicitly calls
`init` on all three well after their loads, HyperCheatSheet at line 479, QueryScope at 1524,
Launcher at 1582, and between each load and its init call the only references are closure
bodies that run later, which is why the toggles below need no parity init call of their own.
No file under `Olm.spoon` references any of the three spoon globals, the menu search toggle's
two launcher closures resolve the global at call time rather than capturing it.

## Decisions already made, build to these

The copies. `Spoons/Olm.spoon/host/launcher/init.lua` and its `CLAUDE.md`,
`Spoons/Olm.spoon/host/queryscope/init.lua` and its `CLAUDE.md`, and
`Spoons/Olm.spoon/host/hypercheatsheet/init.lua`. Each entry file is byte for byte its
original plus one short header paragraph at the top naming it the olm side copy, this
packet's date, and where the original lives, the exact precedent of every plugin copy. The
`CLAUDE.md` files are byte for byte with no header. Hardcoded paths and the `launcherRecency`
settings key are kept byte for byte, continuity across the toggle depends on both sides
naming the same key.

The toggles. Three booleans in the root `init.lua`, `HYPERCHEATSHEET_ON_OLM` at the line 97
load site, `LAUNCHER_ON_OLM` at the line 252 load site, and `QUERYSCOPE_ON_OLM` at the line
358 load site, each defaulted true, each in the established comment style of the existing
`_ON_OLM` blocks. True assigns the spoon global from `dofile(hs.configdir ..
"/Spoons/Olm.spoon/host/<dir>/init.lua")`, false keeps today's `hs.loadSpoon`. No parity init
call on the true branch, the root's own later init calls cover all three, but verify that
claim against the code as you build rather than trusting this packet, and if you find any
genuine read of one of the three spoon globals between its load site and its init call, add
the parity call and flag it loudly in your report. Every downstream reference stays untouched,
the choosers array, the queryProviders list, the queryScopes handoff, and the hyperActions
block all read the same globals whichever branch assigned them.

Nothing else. No dependencies file, no manifest regeneration, no map row, no edit to any
original spoon, no edit to `lean-init.lua` which loads none of the three.

## Gate

`test/units.sh` from `dotfiles/hammerspoon/.hammerspoon` passes. `src/check-dependencies.sh`
from the repo root passes with no new warnings. `test/inventory.sh` three times, as
committed, with every `_ON_OLM` boolean including the three new ones flipped false in one
temporary edit, and restored through git, all empty diffs, the script owns the machine wide
lock itself, never acquire it any other way. Verify each copy byte faithful with a diff
against its original showing only the header paragraph. The live feel is not your gate.

## Out of scope

Any reshape of the three, the plugin contract and the action panel are phases 7 and 8.
Editing any original spoon. Running anything live or touching `bin/hs-devlock`. Retirement.

## Deliverable

Commits on the branch, small steps, the copies first then the toggles, each ending after a
blank line with Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>. A report with the
branch head, each gate's numbers, the byte faithfulness proof per copy, the exact line ranges
of the three toggle blocks, and any decision above that did not survive contact with the
code, flagged loudly rather than silently reinterpreted. Every line you author follows the
repository writing rules, no colons, no semicolons, no hyphens or dashes, periods and commas
only, copied lines keep their form.
