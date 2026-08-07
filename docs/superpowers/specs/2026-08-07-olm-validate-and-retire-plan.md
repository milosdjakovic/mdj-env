# The validate and retire plan, one spoon at a time

Written 2026-08-07 on the user's word, immediately after the host landing at `98b9cb7` made
every tool load from Olm. This replaces the old shape where all live testing happened first
and retirement waited for a distant phase 11. The new loop is per tool. The user validates
one tool live from the checklist at
`docs/superpowers/specs/2026-08-07-olm-live-test-checklist.md`, and the moment a tool passes,
its original is deleted in the same breath, leaving only the olm lib or plugin it moved to.
Defects found during validation are fixed on the olm side first, with the toggle as the
instant fallback while the fix is built, and the tool is revalidated before it retires.

## The loop, per tool

One. The user exercises the tool's checklist row and gives a verdict. A pass moves to
retirement. A defect gets the fix loop, a packet if the fix has any real shape, a builder in
a worktree branched from feat/olm, review proportional to risk, the gates, a land on
feat/olm, a reload with the console gate, then revalidation.

Two. On the pass, retirement runs through a subagent on a branch named `feat/retire-<tool>`
from feat/olm in a worktree under `../.worktrees/`. The steps, in order.

Delete the original. For a plugin or host tool that is the whole `Spoons/<Name>.spoon/`
directory. For menu search it is the inline false branch block in the root `init.lua`, since
its original was never a spoon. For the six atoms it is six directories at once, see the
ordering rule below.

Collapse the toggle. The `if <TOOL>_ON_OLM then` block becomes the unconditional olm load,
the boolean goes away, and the comment shrinks to one or two lines naming where the tool
lives now. Every downstream site already reads the spoon global or the hoisted names, so
nothing else in the root changes.

Reconcile dependencies where the tool carried any. The copy's declarations already sit
beside the copy, so deleting the original halves the doubled rows. Regenerate the manifest
through the collector and check one known coupling per tool, the root's `depsFor("<Name>")`
calls resolve against the manifest's consumer labels, which for the copies are the lowercase
plugin directory names rather than the originals' capitalized spoon names. Any `depsFor`
still naming the capitalized label must be pointed at the copy's label in the same commit,
verified by running the reconciler and by the resolver summary line staying at all present
after the reload. Tools with declarations today, Vpn, Capture, Eyedropper, Convert,
DisplayProfiles, Clipboard, BrowserTabs with its core recency line, and FileSearch.

Restow. Deleting a spoon directory leaves a dead symlink in the folded
`~/.hammerspoon/Spoons` tree, and a plain stow does not prune it, so run `stow -R -t ~
hammerspoon` from the dotfiles directory and confirm the dead link is gone and the olm
paths still resolve. Learned at the WindowManager retirement, where the plain restow left
the dangling link behind.

Gates and land. `test/units.sh`, `src/check-dependencies.sh` with no new warnings,
`test/inventory.sh` three times across the shrinking toggle set, then merge to feat/olm with
no fast forward, reload scheduled never inline, the console gate scoped to the fresh load,
and the checklist row marked ticked and retired in the same docs commit.

Three. Next tool. Any order the user likes for the plugins, subject to the ordering rule.

## The ordering rule

Plugins and KeyRemap retire in any order as they pass. The three host spoons retire after
their own row passes. The six atoms behind `ATOMS_ON_OLM`, Dependencies, ChordKey,
CheatSheet, Chooser, CanvasPanel, and HyperKey, retire last and together, only after every
other tool has passed, because every chooser, cheat sheet, chord, and injected adapter runs
through them and their validation is the sum of everything else passing. The clipboard and
vpn rows retire like any plugin once their short confirmation rows pass.

## Per tool notes that must not be forgotten

BrowserTabs. The copy's test harness at `plugins/browsertabs/test/agent.lua` line 241 still
calls `bt.recency.touch`, which does not exist on the copy since recency is injected core
there. Fix the harness as part of the BrowserTabs retirement, point the suite at the copy,
and run it once through its own `suite.sh` before the original is deleted, since that suite
is the one integration harness in the config and it currently points at the original.

Clipboard. The module level `CLAUDE.md` carries the full paste engine trail duplicated from
`Olm.spoon/CLAUDE.md` on purpose while the original exists. At clipboard retirement the
module level copy becomes a pointer to the olm file, per the note both files already carry.

Menu search. The module `CLAUDE.md` sentence calling menu search root policy rather than a
spoon becomes false at its retirement, correct it in the same commit that deletes the inline
block.

Atoms. `lean-init.lua` still loads the original Chooser and Dependencies spoons. The atoms
retirement swaps its loads onto the olm libs in the same pass, or deletes the file if the
user says the lean surface has served its purpose, ask at that point.

Emoji. The original carries the vendored `data.lua` and `regenerate.sh`. The copy already
carries both, so the deletion is plain, just confirm the copy's `regenerate.sh` kept its
executable bit before deleting the original.

TerminalHandler, WorkspaceEngine, DockAutoHide, and StageManager. The user decided on
2026-08-07 that these four stay out of Olm entirely. Each moves back to its own standalone
spoon, initialized directly in the root `init.lua` the way it stood before the migration,
and none of the four follows the validate and retire path in this plan. See their sections
in `2026-08-07-olm-validation-log.md` for the standing note.

## After the last retirement

A docs sweep, the module `CLAUDE.md` prose that names original spoon paths gets pointed at
the olm tree, done as its own small pass. Then feat/olm merges to main on the user's
explicit word and nothing else, and the build plan continues with phase 7, the plugin
contract, now against a tree where Olm is the only thing there is.
