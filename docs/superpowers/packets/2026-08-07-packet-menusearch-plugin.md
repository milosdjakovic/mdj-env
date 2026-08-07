# Work packet, menu search becomes a plugin

Written 2026-08-07 against main at `fee9856`, on the user's word of this date. Menu search
today is not a spoon, it is inline composition root policy in the root `init.lua`, so unlike
every phase 6 plugin this is an extraction rather than a copy, and the toggle's false branch
keeps the inline code rather than an `hs.loadSpoon`. Work on a branch named
`feat/menusearch-plugin` in a worktree under `../.worktrees/` beside the repo.

## What menu search is, from the rescan of this date

The main block sits at root `init.lua` lines 1689 to 1842, the helpers `menuShortcutGlyph`,
`flattenMenus`, and `buildMenuRows`, the module locals `menuRows`, `menuTargetApp`,
`menuAppIcon`, and `menuAppKey`, the `menuSearch` Chooser instance built over
`shortcutPanelFor("menuSearch")` and `settings.chooserTheme`, the `menuSearchSurface` dot
called adapter assigned to the forward declaration at line 601, `openBuiltinMenuSearch`, a
disabled commented external combo block, and the `spoon.HyperKey:bind` at line 1842. The
launcher scope block sits at lines 1844 to 1897, `scopeMenu` state, `scopeMenuRows` reading
`spoon.Launcher:coveredApp()` and calling `spoon.Launcher:refresh()` when async rows land, and
`scopeMenuRun`, both registered at lines 2306 to 2309. The surface also appears in the
`choosers` array at line 2557, the `menuSearchOpen` predicate at 671 to 674, and the cheat
sheet row push at line 469. It declares no external tool, touches no `hs.settings` key, and
persists nothing. Every identifier above appears nowhere else in the file. The shared `after`
helper at line 32 is not menu search's own, it stays in root and is injected.

## Decisions already made, build to these

The plugin. One file, `Spoons/Olm.spoon/plugins/menusearch/init.lua`, following the spoon
lifecycle contract. `init()` returns self with no side effects. `configure(opts)` takes every
collaborator and returns self. No `start` or `stop`, it owns no watcher. Its doc header names
it the olm side extraction of menu search, this packet's date, and that the original lives
inline in the root `init.lua` behind the toggle rather than in a spoon directory, since that
is where a reader must look for the other side.

The injected collaborators, and the plugin names nothing else. `chooser`, the Chooser atom
table whose `.new` builds the picker. `theme`, the chooser theme table. `panel`, a table
carrying the three shortcut panel callbacks `onPositioned`, `onActivity`, and `onClose`,
built in root by `shortcutPanelFor("menuSearch")` exactly as today. `coveredApp`, a function
answering the app the launcher covers. `refreshLauncher`, a function poking the launcher when
async rows land. `after`, the root's deferred call helper. The plugin never names a `spoon`
global, never reads `config/keys.lua` or `config/settings.lua`, and never learns which key
opens it, per the module rule that a spoon never knows how it is used.

The public surface. `obj.surface`, the same dot called adapter shape as today with
`isShowing`, `selectNext`, `selectPrev`, `insertSelected`, and `hide`. `obj.open`, today's
`openBuiltinMenuSearch`. `obj.scopeRows` and `obj.scopeRun`, today's scope functions. The
moved logic stays line for line what it is today wherever possible, the only edits are the
seams, `spoon.Launcher` calls become the two injected functions, `shortcutPanelFor` becomes
the injected `panel`, `settings.chooserTheme` becomes the injected `theme`, and `after` the
injected one. The disabled external combo block does not travel, it is dead code whose
resurrection would be root wiring anyway, and the plan tick records that it stays only on the
inline side.

The toggle. One boolean named `MENUSEARCH_ON_OLM` in the root `init.lua`, defaulted true,
placed at the current implementation site near line 1689 rather than in the top load section,
because `configure` needs `shortcutPanelFor` and the launcher which exist only by then, with a
comment in the established toggle style saying so. True loads the plugin by `dofile` off
`hs.configdir`, calls `init` and `configure`, and assigns the shared names from it. False
keeps today's inline code byte for byte, wrapped without editing any inner line, so the
false branch diff is pure wrapping. Both branches must produce the same four names for the
code downstream, `menuSearchSurface`, `openBuiltinMenuSearch`, `scopeMenuRows`, and
`scopeMenuRun`, which means hoisting forward declarations for the last three the way line 601
already does for the surface. The key bind, the predicate, the cheat sheet row push, the
scope registration, and the choosers entry all stay outside the toggle and read the shared
names, so not one of those sites flips.

Dependencies change nothing. The plugin references no `spoon.Olm.lib` name and no external
tool, so no leaf declaration, no manifest change, and no map row, the Arithmetic precedent.

## Gate

`test/units.sh` from `dotfiles/hammerspoon/.hammerspoon` passes. `src/check-dependencies.sh`
from the repo root passes with no new warnings. `test/inventory.sh` runs three times, as
committed, with every `_ON_OLM` boolean including the new one flipped false in one temporary
edit, and restored through git, all empty diffs, and the script owns the machine wide lock
itself, never acquire it any other way. The live feel is not your gate, it joins the user's
checklist pass.

## Out of scope

Editing `config/keys.lua` or `config/settings.lua` semantics. The alias directory. Any doc
rewrite, the module `CLAUDE.md` sentence calling menu search root policy is retirement's to
fix and the plan records it. The disabled external combo path. Any original spoon. Running
anything live or touching `bin/hs-devlock`.

## Deliverable

Commits on the branch, small steps, the plugin first then the toggle, each ending after a
blank line with Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>. A report with the
branch head, each gate's result, the exact line ranges of the toggle block and the hoisted
declarations, and any place a decision above did not survive contact with the code, flagged
loudly rather than silently reinterpreted. Every line you author follows the repository
writing rules, no colons, no semicolons, no hyphens or dashes, periods and commas only,
moved lines keep their form.
