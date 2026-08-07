# Work packet, the FileSearch preview pair

Written 2026-08-07 against feat/olm at `6a8863d`, from the user's FileSearch validation
verdict. Two items in one pass. QuickLook opens on whatever screen holds the mouse pointer
rather than the screen the chooser resolved to, and the user wants the canvas side panel
enabled for live testing while the q key keeps opening QuickLook. FileSearch does not retire
in this pass, the user revalidates after the land. Work on a branch named
`feat/filesearch-preview` from feat/olm, never from main, in a worktree under
`../.worktrees/` beside the repo. Only the olm copy changes, the original
`Spoons/FileSearch.spoon` is never touched.

## The facts from the scout of this date

The q key runs `peekPreview` in `Spoons/Olm.spoon/plugins/filesearch/chooser.lua` near lines
637 to 664, which calls `viewer.show(row)` on the single session viewer. The QuickLook
viewer at `plugins/filesearch/viewers/quicklook.lua`, `M.show` near lines 199 to 257, spawns
a small compiled Swift helper per file through `hs.task`, passing only the file path. The
helper source is `plugins/filesearch/viewers/quicklook.swift`, and at its lines 92 to 104 it
picks its screen from `NSEvent.mouseLocation` with a comment claiming the pointer sits on
the picker's screen. That claim is the bug, no geometry ever crosses the process boundary.
`ensureBinary` near lines 122 to 144 caches the compiled binary.

The chooser atom resolves its target screen once per open, before stealing focus, at
`Spoons/Olm.spoon/lib/chooser/providers/native.lua` near lines 373 to 378, and publishes
absolute frames outward through `onPositioned(chooserFrame, companionFrame)`. The filesearch
chooser already receives those frames at `plugins/filesearch/chooser.lua` near lines 394 to
415. The side panel viewer at `plugins/filesearch/viewers/sidepanel.lua` docks straight into
`companionFrame`, so it has no screen defect of its own.

The provider choice is one hardcoded root line,
`local filePreviewProvider = spoon.FileSearch.PreviewProvider.QuickLook` at root `init.lua`
line 391 as of the stamp commit, injected into the configure call near line 2220, and the
binding needs near lines 397 to 404 derive `askedPreview` and `scrollablePreview` from that
same local. The session activates exactly one viewer, `plugins/filesearch/init.lua`
`previewChain` near lines 125 to 131 and `chooser.lua` `M.start` near lines 435 to 469 pick
the first available candidate, and that one viewer answers highlight, positioning, and peek
alike. Line numbers drift, rescan rather than trust them.

## Decisions already made, build to these

One, the chooser frame crosses into the Swift helper. The filesearch chooser keeps the
latest `chooserFrame` it receives in `onPositioned`. The peek path hands it to the viewer,
`viewer.show(row, chooserFrame)`, and a viewer that does not use the second argument ignores
it. QuickLook's `M.show` forwards the four numbers as extra string arguments to the task.
The Swift helper reads the optional four arguments, picks the `NSScreen` whose frame
contains the center point of that rect, and falls back to today's pointer based pick only
when the arguments are absent. The misleading comment there gets corrected, and every
authored line follows the repository writing rules.

Two, rebuild awareness. Check what `ensureBinary` does today. If it only checks that the
binary exists, add a comparison so a swift source newer than the binary forces a recompile,
otherwise this fix would demo against the stale binary. If it already compares, say so in
the report and change nothing.

Three, the docked viewer and the peek viewer become two seams. The side panel becomes the
docked provider through the one root line, `filePreviewProvider` set to
`spoon.FileSearch.PreviewProvider.SidePanel`. The q key keeps opening QuickLook, so the
filesearch chooser resolves a separate peek viewer, QuickLook when its `available()` answers
true, and the peek path dispatches to that peek viewer while highlight, positioning, and
docking stay with the docked viewer. The binding needs must keep q bound, `askedPreview` is
wrong to drop since the peek viewer exists, so derive it from the peek viewer's presence
rather than from the docked provider name, and the side panel's scroll keys keep working as
the sidepanel path defines. Keep the change small, no viewer registry, no third seam, one
docked viewer plus one optional peek viewer. The peek viewer closes with the chooser the
same way the current single viewer does, whatever stop or hide call the session already
makes on close must reach both.

Four, QuickLook receives the same frame plumbing regardless of which seat it sits in, one
code path whether it is the docked provider or the peek viewer.

Five, nothing else. No dependency manifest changes, the plugin's declarations already cover
what it uses. No retirement, no docs ticks, no edits to the original spoon, no edits to any
other plugin.

## Gate

`test/units.sh` from the worktree hammerspoon directory passes. `src/check-dependencies.sh`
from the worktree root passes with no new warnings. `test/inventory.sh` three times as
committed, each run passing, the script owns the machine lock itself. The live feel is not
your gate, the user validates after the land. A syntax load check of every touched Lua file
through luac or an equivalent parse is cheap and expected.

## Deliverable

Commits on the branch, small steps, each ending after a blank line with
Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>. A report with the branch head, each
gate's numbers, the exact line ranges touched per file, what `ensureBinary` did before and
after, how the four arguments are encoded on the task invocation, and any decision above
that did not survive contact with the code, flagged loudly rather than silently
reinterpreted. Every line you author follows the repository writing rules, no colons, no
semicolons, no hyphens or dashes, periods and commas only, copied lines keep their form.
