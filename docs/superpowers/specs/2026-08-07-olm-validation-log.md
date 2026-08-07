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

Validation on 2026-08-07 found that Quick Look opened on the display holding the mouse
pointer rather than on the chooser's own display. The fix carries the chooser frame into
the Swift helper, which now picks the screen containing that frame instead of guessing from
the pointer. Alongside the fix, the side panel becomes the docked preview provider, while
the q key keeps Quick Look available through a new peek viewer seam. This follows the packet
at `docs/superpowers/packets/2026-08-07-packet-filesearch-preview.md`, landed at merge commit
93ce40a6846646879739d09c4e0dff0fd3ead894, awaiting the user's revalidation.

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
- [x] retired

Validation passed on 2026-08-07 with no findings. The carried in retirement note below
still applies.

Retirement note, confirm the copy's `regenerate.sh` kept its executable bit before the
original goes. The copy already carried the executable bit, so nothing needed restoring.
The retirement landed at merge commit 4983fc104fd54b812ed30373f8aec156731c3a3e.

### MenuSearch

- [x] validated
- [x] retired

Validation passed on 2026-08-07 with no findings. The carried in retirement note below
still applies.

The original is the inline false branch in the root `init.lua` rather than a spoon.
Retirement deletes that block and corrects the module `CLAUDE.md` sentence that still calls
menu search root policy. The retirement landed at merge commit
9fee4be459c07639c6c678fd2916f4cd602dbd87, and the module `CLAUDE.md` sentence now names menu
search as an olm plugin configured from the root instead of grouping it with the alias
directory as root policy.

### Processes

- [x] validated
- [x] retired

Validation passed on 2026-08-07 with no findings. The retirement landed at merge commit
f2d412047a896ad5ec159744c1ed21812a57e49e, and needed both a depsFor repoint to the consumer
name the resolver actually stamps under Olm and a one level deeper walk in the resolver so
the copy's nested source declarations stopped going unread.

### DisplayProfiles

- [ ] validated
- [ ] retired

Looked good in the chooser on 2026-08-07. The user wants to watch it over time before
calling it a full pass, and will report anything worth fixing or changing once it shows up.

### Eyedropper

- [x] validated
- [x] retired

Validation passed on 2026-08-07 with no findings. The retirement landed at merge commit
c2a70ed54a06c9ab1f8e9453f75d3024742a3ad7, and needed a depsFor repoint to the consumer name
the resolver actually stamps under Olm, the same reconciliation Processes needed.

### TextCase

- [x] validated
- [x] retired

Validation passed on 2026-08-07 with no findings. The retirement landed at merge commit
8d6e58282fb9e9f63c12835091f83cd929e282b2.

### SystemSettings

- [x] validated
- [x] retired

Validation passed on 2026-08-07 with no findings. The retirement landed at merge commit
34a71e571ab4eecbd5a0408e598140ecdbbe4b0e.

### TerminalHandler

- [ ] validated
- [ ] retired

The user decided on 2026-08-07 that this tool stays out of Olm. It moves back to its own
standalone spoon, initialized directly in the root `init.lua` the way it stood before the
migration, rather than following the validate and retire path below. Tracked as its own
piece of work, separate from this loop, alongside WorkspaceEngine, DockAutoHide, and
StageManager below.

The extraction landed at merge commit 9d5df341b694866ef5afc4bbd0e05e713eab000c, and
TerminalHandler runs standalone again. The boxes above stay unticked, since this tool left
the validate and retire loop.

### Arithmetic

- [ ] validated
- [ ] retired

Validation on 2026-08-07 found the four basic operators plus modulo, exponent, and
parentheses all work, but a trailing percent as in `2+2%` is not read as a percentage. The
fix lands before this tool counts as a full pass.

The fix for that finding landed at merge commit 33f8134d361162870ee62ac75319eeea078a2cc5
on feat/olm, rewriting a number followed by a percent sign into a division by one hundred
whenever the percent is not followed by a digit or a decimal point, so `2+2%` answers 2.02
and `7%3` still answers 1 as modulo. The boxes above stay unchecked, awaiting the user's
revalidation.

### Convert

- [x] validated
- [x] retired

Validation passed on 2026-08-07 with no findings. The retirement landed at merge commit
a276c2e46d76bc47ac2bc87f715e508ed375cfc7, and needed a depsFor repoint to the consumer name
the resolver actually stamps under Olm, the same reconciliation Processes and Eyedropper
needed, with the parity init call beside the toggle assignment kept unchanged.

### WorkspaceEngine

- [ ] validated
- [ ] retired

The user decided on 2026-08-07 that this tool stays out of Olm too. It moves back to its own
standalone spoon, initialized directly in the root `init.lua` alongside TerminalHandler,
DockAutoHide, and StageManager, rather than following the validate and retire path below.

The extraction landed at merge commit 9d5df341b694866ef5afc4bbd0e05e713eab000c, and
WorkspaceEngine runs standalone again. The boxes above stay unticked, since this tool left
the validate and retire loop.

### DockAutoHide

- [ ] validated
- [ ] retired

The user decided on 2026-08-07 that this tool stays out of Olm too. It moves back to its own
standalone spoon, initialized directly in the root `init.lua` alongside TerminalHandler,
WorkspaceEngine, and StageManager, rather than following the validate and retire path below.

The extraction landed at merge commit 9d5df341b694866ef5afc4bbd0e05e713eab000c, and
DockAutoHide runs standalone again. The boxes above stay unticked, since this tool left
the validate and retire loop.

### DisplayMemory

- [x] validated
- [x] retired

Validation passed on 2026-08-07 with no findings. It still needs to work smoothly once
TerminalHandler moves back to its own standalone spoon, worth a recheck once that lands.
The retirement landed at merge commit 89a8237b97530dd2705bc7595c17d4f64fc0ebdb.

### WindowMemory

- [ ] validated
- [ ] retired

### StageManager

- [ ] validated
- [ ] retired

The user decided on 2026-08-07 that this tool stays out of Olm too. It moves back to its own
standalone spoon, initialized directly in the root `init.lua` alongside TerminalHandler,
WorkspaceEngine, and DockAutoHide, rather than following the validate and retire path below.

The extraction landed at merge commit 9d5df341b694866ef5afc4bbd0e05e713eab000c, and
StageManager runs standalone again. The boxes above stay unticked, since this tool left
the validate and retire loop.

### KeyRemap

- [x] validated
- [x] retired

Validation passed on 2026-08-07 with no findings, and the user noted that every plugin
above already proved it works, since every one of them depends on it. The retirement
landed at merge commit 5f6b8441ec26ca565809db5048a4e430bce39976. Standing follow up,
the `USAGE` table mapping friendly key names to HID usage codes knows six keys today,
caps lock, right command, right option, and the three F keys they become, so pointing a
leader at any other physical key means adding one row to that table in the olm copy,
noted 2026-08-07 as a follow up the user may ask for later.

### ClipboardHistory

- [x] validated
- [x] retired

Validation passed on 2026-08-07 with no findings. The retirement landed at merge commit
077b2d10ca2449b2b65237374602fbae809025b5, and needed a depsFor repoint to the consumer name
the resolver actually stamps under Olm, the same reconciliation Processes, Eyedropper, Convert,
and Vpn needed. The module level `CLAUDE.md` paste trail collapsed to a pointer at
`Olm.spoon/CLAUDE.md` in the same pass, per the note both files carried, and the now stale
paragraph describing that future collapse was removed from `Olm.spoon/CLAUDE.md` itself.

### Vpn

- [x] validated
- [x] retired

Validation passed on 2026-08-07 with no findings. The retirement landed at merge commit
86bc3602324e2b64cabc6660d7b3425c3681ec0e, and needed a depsFor repoint to the consumer name
the resolver actually stamps under Olm, the same reconciliation Processes, Eyedropper, and
Convert needed.

## Host, after their own row passes

### Launcher

- [ ] validated
- [ ] retired

Validation on 2026-08-07 passed for the launcher rows and the alias scope grammar, but
found that `launcherRecency` picks up any app the user focuses, not only the ones chosen
through the launcher itself. The fix should make recency reflect launcher driven
selections alone, so nothing outside the launcher moves the order, and this tool counts as
a full pass once that lands.

The fix for that finding landed at merge commit f1e883244a5d603455a3b4522fadcdbd89d6e00c
on feat/olm, removing the ambient promote from the app watcher and from the start seed, so
the timeline is now fed by launcher picks alone. The boxes above stay unchecked, awaiting
the user's revalidation.

### QueryScope

- [x] validated
- [x] retired

Validation passed on 2026-08-07 with no findings, exercised together with Launcher and
HyperCheatSheet under the combined Host checklist row. The retirement landed at merge
commit 23a170932c96e5ce8821b9b774a2f04ccd7716af.

### HyperCheatSheet

- [x] validated
- [x] retired

Validation passed on 2026-08-07 with no findings, exercised together with Launcher and
QueryScope under the combined Host checklist row. The retirement landed at merge commit
475e6dd1d84de9f92d1caa6c5b442519f0fb9e6e.

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
