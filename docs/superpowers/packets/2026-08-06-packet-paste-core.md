# Work packet, paste into core

Written 2026-08-06 against the tree at `bbd8d9e`. Rescan before building if the tree has moved.
This is phase 3 of the build plan at `docs/superpowers/specs/2026-08-04-hammerspoon-olm-build-plan.md`,
the riskiest extraction, measured timing rather than obvious behaviour. The design's paste section
was rescanned on 2026-08-06 and every landmark cited here was verified exact at this commit.

## Goal

`Spoons/Olm.spoon/lib/paste.lua` exists as the shared insertion engine carved from the insertion
half of `ClipboardHistory.spoon/manager/monitor.lua`. A full olm side copy of the clipboard spoon
lives under `Spoons/Olm.spoon/plugins/clipboard/` with its internal callers repointed at the lib.
The two root injected consumers, Emoji and TextCase, take the primitives from the olm door on the
olm side of one toggle in the composition root. The measurement trail that justifies every delay
in this code travels into documentation beside the lib. The original spoon is never edited and
behaves exactly as today when the toggle restores it.

## Model

Opus. The primitive versus entry boundary and the two guard seams are design decisions inside the
most carefully measured code in the config. A regression here is felt on every paste, and no
scripted gate can see a delay that is wrong by thirty milliseconds, so the build itself carries
judgment that cannot be checked cheaply after the fact.

## Read

The design's paste section, "Paste, the same split one layer over", in
`docs/superpowers/specs/2026-07-27-hammerspoon-olm-core-and-plugins-design.md`, current as of the
2026-08-06 rescan, and the documentation section of the same file for the trail split rule.

`Spoons/ClipboardHistory.spoon/manager/monitor.lua` in full, 918 lines. The capture half runs to
line 243, the watcher, the poll, `contentSig` at 140, `selfWritten` at 151, `capture` at 165, and
the guard state `selfSigs` at 132 and `ownPasteCount` at 122. The insertion half runs from
`heldModifiers` at 244 through `M.copySelection` at 790, taking in `stroke` 257, `encodePath` 268,
`writtenFilePaths` 295, `fileURLObjects` 320, `writeEntry` 335, `cancelPendingRestore` 377,
`currentSig` 390, `describePasteboard` 407, `pasteboardStillOurs` 437, `restorePasteboard` 450,
`pasteOp` 480, `M.paste` 584, `M.insertText` 625, `M.readSelection` 652, `M.snapshotClipboard`
669, `M.writeClipboard` 678, `batchOps` 690, `M.pasteBatch` 715, `M.pasteText` 750, and
`M.isReading` 771. The walk watcher from `isPlainCmdV` at 858 with `watchPaste` and `M.start`, and
`M.configure` at 905, stay with the capture half.

The internal callers being repointed inside the copy. `manager/init.lua` at 222, 232, 241, 337,
and 371. `manager/session.lua` at 207, 223, 249, 275, 279, 429, 459, and 476. `manager/ui.lua` at
1024 and 1026.

The composition root `dotfiles/hammerspoon/.hammerspoon/init.lua`. The load at 57, the spoon level
configure near 620 through 650, the launcher rows at 1349, the Emoji block near 1655 through 1673,
the TextCase block near 1675 through 1704, and the manager configure and start at 2167 through
2201. Note that Emoji and TextCase today reach the primitives through the manager wrappers
`pasteText` and `copySelection`, not through monitor directly.

The measurement trail in `dotfiles/hammerspoon/.hammerspoon/CLAUDE.md`, the block from 1040 to
1234. Lines 1108 to 1230 are properties of the insertion primitives, the `insertText` versus paste
finding with its measured latencies, the restore guard reasoning, the held modifier chord
findings and the two removed fix attempts, `copyDelay`, `sequenceDrainDelay`, the queue and cap
behaviour, the debug timeline tooling, and the probing hazards. The rest of the block, 1040 to
1106 and 1232 to 1234, is the append and walk feature built on the primitives and stays put.

The precedents. `Spoons/Olm.spoon/init.lua` for the `obj.lib` loading pattern,
`Spoons/Olm.spoon/plugins/vpn/init.lua` for the copy conventions and the top comment shape, and
`dotfiles/hammerspoon/.hammerspoon/lean-init.lua` for the scaffold and the swappable tool section.

## Read only

`Spoons/ClipboardHistory.spoon` in its entirety, it is copied and never edited.
`Spoons/Emoji.spoon` and `Spoons/TextCase.spoon`, only their root wiring blocks change, never the
spoons. `dotfiles/hammerspoon/.hammerspoon/CLAUDE.md`, the trail is copied out and adapted, never
cut, since the original monitor still embodies it on the other side of the toggle and the pointer
consolidation happens at retirement. `test/units.sh`, `test/inventory.sh`, and
`test/inventory.golden`, the golden must not change, an inventory diff is a failure to fix.
`Spoons/Olm.spoon/plugins/vpn`, the phase 2 land, untouched.

## Deliverable

### The lib

`Spoons/Olm.spoon/lib/paste.lua`, a module table with `M.configure(opts)` in the monitor pattern,
one instance and no factory, since the machine has one pasteboard and one guard state and a second
instance would split the guard. It carries the insertion half listed above with its semantics and
its timing values byte for byte where possible, every delay, every queue rule, every settle
callback exactly as the donor has them. `Spoons/Olm.spoon/init.lua` gains one line exposing it,
`paste` beside `storage` and `recency` in `obj.lib`. Configure splits along the same boundary,
`pasteDelay` and `resolveFilePaths` and whatever else only the insertion half reads move to the
lib's configure, while `readers`, `store`, `skipTypes`, `onCapture`, `onUserPaste`, and
`pollInterval` stay with the copy's monitor. Small helpers both halves use, `clock`, `after`, and
`frontID`, may simply be duplicated, three lines twice beats a shared utility file.

### The boundary decision

`writeEntry`, `writtenFilePaths`, and `batchOps` know the shape of a clipboard entry, `kind`,
`text`, and the file paths. Drawing the line between primitive and entry knowledge is yours to
decide and record. The deciding test, the lib's public vocabulary must never name clipboard
history concepts, no store, no session, no walk, but a neutral content descriptor of kind, text,
and paths is acceptable if that is the smaller cut. Record the decision and its reasoning in the
lib's header comment and in your report.

### The two seams

Exactly two pieces of state cross the boundary today, and they stay exactly two commented seams,
no observer machinery, no event bus, nothing generic. First, `selfSigs`, written by `writeEntry`
at 358 to 361 so the receiving app's echo is not re ingested, consulted by `capture` at 191
through `selfWritten`. Second, `ownPasteCount`, raised and lowered by `pasteOp` at 504 and 506
around its synthetic Cmd+V, consulted by `watchPaste` at 872 so the walk's own paste does not end
the walk it belongs to. The design rule for both is the same, olm owns the knowledge of not
polluting a history it does not own, so the lib is the natural owner of the state, exposing the
smallest question the capture side can ask, with a comment on both ends naming the other. The
`pasteboardStillOurs` restore guard crosses nothing and stays wholly inside the lib. If the carve
uncovers a third crossing, stop and name it in your report before inventing a shape for it.

### The copy

`Spoons/Olm.spoon/plugins/clipboard/`, a full copy of every file under
`Spoons/ClipboardHistory.spoon/`, keeping `manager/preview.dependencies` unchanged so the
dependency layer still records what the code runs. The copy's `manager/monitor.lua` loses the
insertion half and keeps the capture half, the walk watcher, start, and its share of configure.
The copy's internal callers, `manager/init.lua`, `manager/session.lua`, and `manager/ui.lua`,
repoint at the lib. The lib reaches the copy through injection, the root passes
`spoon.Olm.lib.paste` into the manager's configure and the manager threads it where its files
need it, the same door every other collaborator already uses. Whether the manager keeps its
outward `pasteText` and `copySelection` wrappers once the root consumers stop calling them is
your call, recorded in a comment either way. The copy's top comment says in one line that it is
the olm side copy of ClipboardHistory, that its insertion half lives in `lib/paste.lua`, and
where the original lives.

### The root toggle

One boolean local in the composition root beside the load at line 57, olm side true, with a
comment saying one edit restores the original everywhere. Three sites branch on it. The load,
either `dofile` of the copy's `init.lua` off `hs.configdir` assigned to `spoon.ClipboardHistory`,
which is safe because the spoon derives its own path through `debug.getinfo` and never leans on
`hs.loadSpoon`, or the original `hs.loadSpoon("ClipboardHistory")`. The Emoji `onInsert` and the
TextCase `read` and `apply`, which on the olm side take the primitives from `spoon.Olm.lib.paste`
and on the original side keep their current manager backed closures verbatim. The three sites
flip together because a consumer pointing at the lib while the original watcher is live would
paste past the original's guard and pollute the history, and each branch carries a comment saying
so. The manager configure at 2168 gains the paste injection on the olm side. Everything else,
`bindHotkeys`, the launcher rows, the predicate at 369, reaches the swapped
`spoon.ClipboardHistory` name and works unchanged on both sides.

### The lean surface

Swap the tool section of `dotfiles/hammerspoon/.hammerspoon/lean-init.lua` for this phase's tool,
per its own boundary comments. The section loads the copy, configures the manager with only the
fields the lean surface needs plus the paste injection, starts it, and binds three plain ways in,
one hotkey opening the history, and the append and walk combos the trail describes so the
sequential walk is exercisable end to end. Print each binding on load in the scaffold's style.

### The trail

`Spoons/Olm.spoon/CLAUDE.md`, created, opening with one short paragraph saying it documents olm's
core libs, then a paste section carrying the insertion primitive trail adapted from the module
level file's lines 1108 to 1230, with function references updated to their new home and the
clipboard feature references left pointing at the clipboard. `sequenceDrainDelay` is a property of
the primitives even though the number is passed in from the clipboard's session, so its paragraph
travels and says where the number comes from. The module level file is not edited, the temporary
duplication is the same short window the code copies live in, and retirement consolidates it.

## Style

The repository rules. Comments in plain prose following the punctuation rules, no colons or
semicolons in any output or error string, no install commands anywhere, no absolute paths written
in any file, no package manager named anywhere. Commits end with the Claude Fable trailer.

## Gate

From this worktree with Hammerspoon running. `test/units.sh` exits zero at 29 of 29, no new case
is asked for since timing cannot be unit tested. `src/check-dependencies.sh` from the repository
root exits zero, the generated manifest may change only through the collector picking up the
copy's declarations. `test/inventory.sh --check` exits zero with the olm side active, then with
the toggle flipped to the original, then flipped back, proving the swap is invisible to the whole
binding surface. `bin/hs-devlock status` at the end shows the lock free. Do not take the devlock
and do not reload the live config, the live tier, pasting into a terminal, a browser field, and
an Electron app, and walking a full history to the end, belongs to the architect and the user on
the lean surface before this lands.

The recorded count, in the report and not in any file. Lines the copy's `monitor.lua` lost
against the original, lines the copy gained elsewhere, the size of `lib/paste.lua` split into
code and comment lines, and lines the root changed. Count with a diff, not by eye.

## Out of scope

Snippets, it consumes the lib in its own phase. Any behaviour change to the append and walk
features, they move only their pointer at the lib. Retiring or editing the original spoon.
Editing the module level `CLAUDE.md`. Converting the launcher rows, they consume clipboard
features, not primitives. The plugin contract and the registry, the copy is loaded directly by
the root until phase 7 exists. Any manifest, map, or Brewfile hand edit. Any change to
`test/inventory.golden`.
