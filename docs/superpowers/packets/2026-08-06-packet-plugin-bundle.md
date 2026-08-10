# Work packet, the bundling pass

Written 2026-08-06 against main at `c23dbbf`. This is phase 6 of the olm build plan, the copy of
every remaining plugin spoon under `Spoons/Olm.spoon/plugins/`, originals untouched behind per
tool root toggles, landing whole or discarded whole. The roster rescan of this date governs the
copy list. Menu search is deliberately absent, it waits on the user's word.

## Shape of the work

Two waves on one integration branch named `feat/plugin-bundle`. Wave one is parallel batch
builders, each on its own branch named `feat/bundle-<batch>` from main `c23dbbf` in its own
worktree under `../.worktrees/`, each touching only the new plugin directories it creates, so no
two batches share a file. Wave two is one wiring agent that merges the batch branches into the
integration branch, fixes the collector, regenerates the manifest exactly once, and adds every
root toggle in one reviewed series. Batch builders never regenerate
`dotfiles/hammerspoon/DEPENDENCIES` and never edit the root `init.lua`, both belong to wave two
alone, and a batch that thinks it needs either is wrong and says so in its report instead.

## The copy rules, binding on every batch

A copy is byte for byte, every lua file, every `CLAUDE.md`, every `.dependencies` file, plus one
short header paragraph at the top of the plugin's entry file naming it the olm side copy, the
phase, and where the original lives, following the clipboard and vpn precedent. The plugin
directory name is the spoon name lowercased with the `.spoon` suffix dropped. Hardcoded cache
paths and `hs.settings` keys are kept byte for byte, continuity across the toggle depends on
both sides naming the same path and the same key, and inventing a fresh one is a defect. Entry
files that lean on `hs.loadSpoon` mechanics cannot, a copy is loaded by `dofile`, so where the
original derives paths through `debug.getinfo` it keeps working unchanged, and where it does
not, the copy takes the smallest edit that restores its own path resolution, commented the way
the deps copy in core commented its one changed line. BrowserTabs carries the one real
conversion of the phase, its hand rolled recency moves onto the injected core recency service
exactly the way the vpn copy did, same shape, a required guard is wrong here, the plan records
it as optional degradation, and a five field core declaration for recency goes beside the file
that takes it. The BrowserTabs test harness is copied like everything else and never run, it
takes the machine wide test lock and no builder may touch that lock.

## The batches

Batch a, small surfaces, Arithmetic, Convert, Caffeinate, TextCase, Eyedropper, SystemSettings.
Batch b, Capture and DisplayProfiles.
Batch c, the pure behaviour set, AppToggler, DockAutoHide, KeyRemap, StageManager,
TerminalHandler, DisplayMemory, WindowMemory, WindowManager, WindowLeader, WindowCheatSheet,
WorkspaceEngine.
Batch d, BrowserTabs, with the recency conversion.
Batch e, Emoji, whose vendored `data.lua` is copied as the artifact it is.
Batch f, FileSearch.
Batch g, Processes.

Each batch runs `test/units.sh` from the hammerspoon config directory as its only gate, the
copies load nothing yet so units passing proves nothing broke rather than that the copies work,
and each reports its branch head and any file whose copy could not be byte faithful, with the
reason.

## Wave two, the wiring

Merge the seven batch branches into `feat/plugin-bundle`, disjoint directories so any conflict
means a batch broke its lane, stop and report rather than resolve. Then the collector fix in
`dotfiles/hammerspoon/dependencies-collect`, `owner_of` strips a leading `Olm.spoon/plugins/`,
`Olm.spoon/host/`, or `Olm.spoon/lib/` from the relative path before taking the first segment,
so a declaration at `plugins/vpn/providers/mullvad.dependencies` reports `vpn/mullvad` rather
than `Olm/mullvad`, per the design near lines 397 to 421. Regenerate the manifest once and
carry the relabelling of the existing olm rows in the same commit. Then the toggles, one
boolean per tool in the root `init.lua`, named `<TOOL>_ON_OLM` in the clipboard's style, true
loading the copy by `dofile` off `hs.configdir` and false keeping today's `hs.loadSpoon`, every
consumer site of that tool reading the same boolean, and the vpn comment swap at lines 123 to
124 normalized into a proper named boolean the same way. The root injects the copy exactly what
it injects the original, plus recency for the BrowserTabs copy on its olm side only, built the
way the vpn injection at line 1701 is, with a settings key matching the original's so remembered
order survives the flip. Every toggle ships defaulted true, the point of the branch is the
copies live, and one edit per tool flips back.

Wave two's gate is the full set, `test/units.sh`, `src/check-dependencies.sh` clean with no new
warnings, and `test/inventory.sh` three times, as committed, with every toggle flipped false in
one temporary edit, and restored, all empty diffs, the script owns the lock. The reconciler must
show the collector fix worked, the generated manifest's consumer column names plugin directories
rather than Olm for every copied declaration.

## Out of scope

Menu search. The host, Launcher, QueryScope, HyperCheatSheet stay where they are. The plugin
contract and registration door, phase 7. Migrating hardcoded caches onto core storage, the
copies inherit them and the sweep is phase 10's. Editing any original spoon. Running any test
harness that takes the test lock. The apps extraction, phase 10.

## Deliverable

Per batch, the branch head and the faithfulness report. For wave two, the integration branch
head, the gate outputs, the manifest relabelling shown by example rows, and the toggle count.
Every commit ends after a blank line with Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>.
The repository writing rules bind every authored line, no colons, no semicolons, no hyphens or
dashes, periods and commas only, copied lines keep their form.
