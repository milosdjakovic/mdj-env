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

- [ ] validated
- [ ] retired

### WindowCheatSheet

- [ ] validated
- [ ] retired

### AppToggler

- [ ] validated
- [ ] retired

### FileSearch

- [ ] validated
- [ ] retired

### BrowserTabs

- [ ] validated
- [ ] retired

Carried in from the build, the copy's test harness at `plugins/browsertabs/test/agent.lua`
line 241 still calls `bt.recency.touch`, which the copy no longer has. The retirement pass
fixes the harness, points the suite at the copy, and runs it once before deleting the
original.

### Caffeinate

- [ ] validated
- [ ] retired

### Capture

- [ ] validated
- [ ] retired

### Emoji

- [ ] validated
- [ ] retired

Retirement note, confirm the copy's `regenerate.sh` kept its executable bit before the
original goes.

### MenuSearch

- [ ] validated
- [ ] retired

The original is the inline false branch in the root `init.lua` rather than a spoon.
Retirement deletes that block and corrects the module `CLAUDE.md` sentence that still calls
menu search root policy.

### Processes

- [ ] validated
- [ ] retired

### DisplayProfiles

- [ ] validated
- [ ] retired

### Eyedropper

- [ ] validated
- [ ] retired

### TextCase

- [ ] validated
- [ ] retired

### SystemSettings

- [ ] validated
- [ ] retired

### TerminalHandler

- [ ] validated
- [ ] retired

### Arithmetic

- [ ] validated
- [ ] retired

### Convert

- [ ] validated
- [ ] retired

### WorkspaceEngine

- [ ] validated
- [ ] retired

### DockAutoHide

- [ ] validated
- [ ] retired

### DisplayMemory

- [ ] validated
- [ ] retired

### WindowMemory

- [ ] validated
- [ ] retired

### StageManager

- [ ] validated
- [ ] retired

### KeyRemap

- [ ] validated
- [ ] retired

### ClipboardHistory

- [ ] validated
- [ ] retired

Retirement note, the module level `CLAUDE.md` paste trail becomes a pointer to
`Olm.spoon/CLAUDE.md` in the same pass, per the note both files carry.

### Vpn

- [ ] validated
- [ ] retired

## Host, after their own row passes

### Launcher

- [ ] validated
- [ ] retired

### QueryScope

- [ ] validated
- [ ] retired

### HyperCheatSheet

- [ ] validated
- [ ] retired

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
