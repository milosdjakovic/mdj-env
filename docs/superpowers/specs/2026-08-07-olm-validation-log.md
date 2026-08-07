# Olm validation and retirement log

Started 2026-08-07 on feat/olm. This file tracks the validate and retire loop, one section
per tool, in the order of the test checklist. Each section carries two boxes, validated
means the user exercised the tool live and passed it, retired means the original was deleted
and the toggle collapsed so only the olm side remains. Findings and their fixes are written
into the tool's own section as they happen, with commit hashes, so the trail of what broke
and what fixed it lives in one place. The procedure behind the boxes is
`2026-08-07-olm-validate-and-retire-plan.md`, the per row test instructions are
`2026-08-07-olm-live-test-checklist.md`.

## Plugins

### WindowManager

- [x] validated
- [x] retired

Validation passed on 2026-08-07 with no findings. The retirement landed at merge commit
fef05a9061f5acb5c29375490c2922fc2522a05a.

### WindowLeader

- [x] validated
- [x] retired

Validation passed on 2026-08-07 with no findings. The retirement landed at merge commit
8790554ed0476ddee142d05c80b2b46e617f4d8e.

### WindowCheatSheet

- [x] validated
- [x] retired

Validation passed on 2026-08-07 with no findings. The retirement landed at merge commit
34b2d3f229a8b8e026101a7ea60cfbaa1c803514.

### AppToggler

- [x] validated
- [x] retired

Validation passed on 2026-08-07, and the only finding was stale checklist row text
describing the old hide behavior, corrected in this commit since the frontmost app cycles
its windows instead. The retirement landed at merge commit
ce02e7265991816579aecbcc2be7851f3e20168b.

### FileSearch

- [ ] validated
- [ ] retired

### BrowserTabs

- [x] validated
- [ ] retired

Validation passed on 2026-08-07 with no findings. The carried in test harness note below
still applies at retirement time.

Carried in from the build, the copy's test harness at `plugins/browsertabs/test/agent.lua`
line 241 still calls `bt.recency.touch`, which the copy no longer has. The retirement pass
fixes the harness, points the suite at the copy, and runs it once before deleting the
original.

### Caffeinate

- [x] validated
- [x] retired

Validation passed on 2026-08-07 with no findings. The retirement landed at merge commit
88ad72c357e7bccd005a8b1a49c52bfe9bb8a2db.

### Capture

- [ ] validated
- [ ] retired

Validation on 2026-08-07 passed using the macshot backend. The user wants the native
backend switched on next purely for a test pass, and this tool only counts as fully
validated once native has been exercised live too.

### Emoji

- [x] validated
- [ ] retired

Validation passed on 2026-08-07 with no findings. The carried in retirement note below
still applies.

Retirement note, confirm the copy's `regenerate.sh` kept its executable bit before the
original goes.

### MenuSearch

- [x] validated
- [ ] retired

Validation passed on 2026-08-07 with no findings. The carried in retirement note below
still applies.

The original is the inline false branch in the root `init.lua` rather than a spoon.
Retirement deletes that block and corrects the module `CLAUDE.md` sentence that still calls
menu search root policy.

### Processes

- [x] validated
- [ ] retired

Validation passed on 2026-08-07 with no findings.

### DisplayProfiles

- [ ] validated
- [ ] retired

Looked good in the chooser on 2026-08-07. The user wants to watch it over time before
calling it a full pass, and will report anything worth fixing or changing once it shows up.

### Eyedropper

- [x] validated
- [ ] retired

Validation passed on 2026-08-07 with no findings.

### TextCase

- [x] validated
- [ ] retired

Validation passed on 2026-08-07 with no findings.

### SystemSettings

- [x] validated
- [ ] retired

Validation passed on 2026-08-07 with no findings.

### TerminalHandler

- [ ] validated
- [ ] retired

The user decided on 2026-08-07 that this tool stays out of Olm. It moves back to its own
standalone spoon, initialized directly in the root `init.lua` the way it stood before the
migration, rather than following the validate and retire path below. Tracked as its own
piece of work, separate from this loop, alongside WorkspaceEngine, DockAutoHide, and
StageManager below.

### Arithmetic

- [ ] validated
- [ ] retired

Validation on 2026-08-07 found the four basic operators plus modulo, exponent, and
parentheses all work, but a trailing percent as in `2+2%` is not read as a percentage. The
fix lands before this tool counts as a full pass.

### Convert

- [x] validated
- [ ] retired

Validation passed on 2026-08-07 with no findings.

### WorkspaceEngine

- [ ] validated
- [ ] retired

The user decided on 2026-08-07 that this tool stays out of Olm too. It moves back to its own
standalone spoon, initialized directly in the root `init.lua` alongside TerminalHandler,
DockAutoHide, and StageManager, rather than following the validate and retire path below.

### DockAutoHide

- [ ] validated
- [ ] retired

The user decided on 2026-08-07 that this tool stays out of Olm too. It moves back to its own
standalone spoon, initialized directly in the root `init.lua` alongside TerminalHandler,
WorkspaceEngine, and StageManager, rather than following the validate and retire path below.

### DisplayMemory

- [x] validated
- [ ] retired

Validation passed on 2026-08-07 with no findings. It still needs to work smoothly once
TerminalHandler moves back to its own standalone spoon, worth a recheck once that lands.

### WindowMemory

- [ ] validated
- [ ] retired

### StageManager

- [ ] validated
- [ ] retired

The user decided on 2026-08-07 that this tool stays out of Olm too. It moves back to its own
standalone spoon, initialized directly in the root `init.lua` alongside TerminalHandler,
WorkspaceEngine, and DockAutoHide, rather than following the validate and retire path below.

### KeyRemap

- [x] validated
- [ ] retired

Validation passed on 2026-08-07 with no findings, and the user noted that every plugin
above already proved it works, since every one of them depends on it.

### ClipboardHistory

- [x] validated
- [ ] retired

Validation passed on 2026-08-07 with no findings. The carried in retirement note below still
applies.

Retirement note, the module level `CLAUDE.md` paste trail becomes a pointer to
`Olm.spoon/CLAUDE.md` in the same pass, per the note both files carry.

### Vpn

- [x] validated
- [ ] retired

Validation passed on 2026-08-07 with no findings.

## Host, after their own row passes

### Launcher

- [ ] validated
- [ ] retired

Validation on 2026-08-07 passed for the launcher rows and the alias scope grammar, but
found that `launcherRecency` picks up any app the user focuses, not only the ones chosen
through the launcher itself. The fix should make recency reflect launcher driven
selections alone, so nothing outside the launcher moves the order, and this tool counts as
a full pass once that lands.

### QueryScope

- [x] validated
- [ ] retired

Validation passed on 2026-08-07 with no findings, exercised together with Launcher and
HyperCheatSheet under the combined Host checklist row.

### HyperCheatSheet

- [x] validated
- [ ] retired

Validation passed on 2026-08-07 with no findings, exercised together with Launcher and
QueryScope under the combined Host checklist row.

## Atoms, last and together

### Dependencies, ChordKey, CheatSheet, Chooser, CanvasPanel, HyperKey

- [ ] validated, implicitly by everything above passing
- [ ] retired, six originals in one pass

Retirement note, `lean-init.lua` still loads the original Chooser and Dependencies, the
atoms pass swaps those loads onto the olm libs or deletes the file, ask the user which at
that point.

## After the last retirement

- [ ] docs sweep, module `CLAUDE.md` prose pointed at the olm tree
- [ ] feat/olm merged to main, only on the user's explicit word
