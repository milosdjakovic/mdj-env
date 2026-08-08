# Work packet, one shared companion pane width in the chooser atom

Written 2026-08-08 against feat/olm at `5442e28`, on the user's decision of this date. The
chooser is 480 wide by one default in the atom, and every companion pane invents its own
number today, clipboard 480, processes 480, filesearch 420, each hardcoded in its own file.
From now the atom's one width serves both the chooser and the pane, a consumer that wants a
pane inherits it, an explicit number stays available as the independent override, and no
consumer of ours customizes. Work on `feat/companion-width` from feat/olm in a worktree
under `../.worktrees/`, never from main. Only the olm side changes, the originals
`Spoons/Chooser.spoon` and `Spoons/FileSearch.spoon` keep their own literals untouched.

## The facts from the scout of this date

The atom's layout defaults live at `lib/chooser/providers/native.lua` near lines 100 to
113, `width = 480`, `paneMaxW = 480`, `companionWidth = 0`, merged once per instance in
`obj.new` near lines 961 to 965, never mutated at runtime. Three read sites consume
`companionWidth`, `_companionFrame` near 296 to 300, the settle path near 325 to 327, and
the initial position near 390 to 391, each as `math.min(L.companionWidth, L.paneMaxW)` with
a `not L.companionWidth or L.companionWidth &lt;= 0` guard for the no pane case. The consumers
that reserve a pane, clipboard at `plugins/clipboard/manager/ui.lua` near 1239 to 1250 fed
by `previewW = 480` in `plugins/clipboard/manager/init.lua` near 131, processes at
`plugins/processes/chooser.lua` near 582 to 587 fed by its own `PREVIEW_WIDTH = 480` near
68 with a `cfg.previewWidth` override nothing supplies, and filesearch at
`plugins/filesearch/chooser.lua` near 557 to 561 reading the side panel's
`companionWidth(policy)` which answers `policy.width or 420`, with the real 420 living in
`config/filesearch.lua` near 135 to 139 behind a comment arguing narrower on taste. Every
other chooser consumer passes no layout and reserves no pane. The shortcut hint panel spans
the frames the atom reports and needs no change. Line numbers drift, rescan.

## Decisions already made, build to these

One, the semantics in the atom. `companionWidth = true` means the pane takes the chooser's
own width in force, the resolved width the frame math already holds, capped by `paneMaxW`
exactly as a number is capped today. A number keeps today's meaning, the independent
override. Zero, nil, and false keep meaning no pane. The comparison sites must never see
the boolean, resolve it to a number in one small helper or one resolution point before any
arithmetic or comparison, since a boolean against a number is a runtime error in Lua, and
route all three read sites through that one resolution. When the chooser runs its
responsive fallback with `width = false`, true still resolves against the actual chooser
width computed for that show, not against the unset default.

Two, the layout comment at the defaults block gains the rule in two or three sentences, one
width serves the chooser and the pane, true inherits it, a number overrides it
independently, `paneMaxW` caps both.

Three, the consumers stop naming numbers. Clipboard, `previewW = true` in the manager's
defaults with its comment updated to say it inherits the atom's width, the passthrough into
the layout stays as is. Processes, the `PREVIEW_WIDTH` local goes away and the layout line
becomes `preview.isEnabled() and (cfg.previewWidth or true) or 0`, the `cfg.previewWidth`
override seam staying alive and unsupplied, the comment above it updated. Filesearch, the
`width = 420` line and the sentence arguing for it leave `config/filesearch.lua`, and the
side panel's `companionWidth` answers `policy.width or true` so an explicit policy width
still overrides. Verify no other consumer names a pane width, the scout found none.

Four, nothing else. No change to the originals, no change to the hint panel, no dependency
work, no docs ticks.

## Gate

`luac -p` on every touched file parses. `test/units.sh` from the worktree hammerspoon
directory passes. `src/check-dependencies.sh` from the worktree root passes with no new
warnings. `test/inventory.sh` three times as committed, each passing. The user retests the
panes live after the land.

## Deliverable

Commits on the branch, small steps, the atom first then the three consumers, each ending
after a blank line with Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>. The landing
slot is yours once gates pass, merge to feat/olm with no fast forward, reload scheduled
never inline, the console gate scoped to the fresh load with the resolver summary at all
present, expect 46 declared, and one docs commit on feat/olm appending a short paragraph to
the FileSearch section of `docs/superpowers/specs/2026-08-07-olm-validation-log.md` noting
the shared pane width landed at the merge hash as part of the preview retest surface. A
report with the merge hash, the docs hash, each gate's numbers, the exact resolution helper
you wrote, and any decision that did not survive contact with the code, flagged loudly.
Every line you author follows the repository writing rules, no colons, no semicolons, no
hyphens or dashes, periods and commas only, copied lines keep their form.
