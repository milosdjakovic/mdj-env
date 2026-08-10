# Work packet, the inventory snapshot and its golden

Written 2026-08-04 against the tree at `0aaed46`. Rescan before dispatching if the tree has moved,
and note that the registry counts recorded in the design were taken at `6bd5b8d`, so the golden
records whatever the tree holds when it is generated, not those numbers. This is the second of the
two phase 0 scaffolds in the build plan at
`docs/superpowers/specs/2026-08-04-hammerspoon-olm-build-plan.md`, and it is dispatched only when
the user opens the build.

## Goal

A script at `dotfiles/hammerspoon/.hammerspoon/test/inventory.sh` that prints a deterministic
fingerprint of this config's whole binding surface read from the config's own registries, plus the
committed `test/inventory.golden` it must match, so every later step that claims no behaviour
change is checkable by an empty diff across the toggle flip.

## Model

Sonnet. The work is fully specifiable and the gate catches failure mechanically.

## Read

The design's section on proving a step changed nothing, the inventory tier, in
`docs/superpowers/specs/2026-07-27-hammerspoon-olm-core-and-plugins-design.md`. It names the
registries the snapshot reads and the fact that makes them the only honest source, that the
binding surface is enumerable from this config's own tables, the loaded `spoon` table, the chord
tree in `ChordKey._keys`, the cheat sheet models in `HyperCheatSheet`, the `hyperContexts`
bindings in `config/keys.lua`, and the `choosers` registry in `init.lua`, while Hammerspoon's own
`hs.hotkey.getHotkeys()` sees almost none of it, so a probe on Hammerspoon's side would be blind.

The lock discipline, in the hammerspoon `CLAUDE.md` under testing a change in an isolated worktree,
and its worked example `Spoons/BrowserTabs.spoon/test/suite.sh`, which shows the full shape, take
the lock with `bin/hs-devlock acquire`, trap so every exit path releases it, and wait for the
relaunched config to answer over `hs.ipc` by polling rather than by sleeping a guessed number of
seconds. This script needs no harness marker, since it only reads, so it borrows the lock and the
trap and the wait and nothing else.

## Read only

Every existing file. This packet creates new files only, all under
`dotfiles/hammerspoon/.hammerspoon/test/`. No registry, spoon, or config file is edited.

## Deliverable

`test/inventory.sh`. It resolves the repository root from its own location, takes the test lock
through `bin/hs-devlock acquire` so this checkout becomes the live config, and installs a trap
that releases the lock on exit, interrupt, or failure, so the resting state is always main. It
then waits for the relaunch by polling the `hs` tool until `hs.configdir` answers with this
checkout's path, which both confirms the config is up and confirms it is the right one, since a
reload asked for but never taken is a known silent failure. It runs the dump described below,
prints the snapshot to stdout by default, and with a `--check` flag diffs the snapshot against
`test/inventory.golden` instead, exiting zero on an empty diff and nonzero with the diff shown
otherwise.

`test/inventory.lua`, the dump the script runs inside Hammerspoon through `dofile`, never as
inline Lua at the shell, because a `<` or `>` in inline Lua wedges the `hs` client. It walks the
registries the design names and prints one line per fact, every listing sorted, no timestamps, no
addresses, no table identity, nothing that varies between two runs on one tree, so the output is
byte stable. Each line carries where it came from, so a future diff reads as which surface changed
rather than as a bare string.

`test/inventory.golden`, committed beside the script, produced by the first honest run against
this tree and reviewed by the architect before commit.

No `init.lua` toggle. Nothing in this packet loads at config time.

## Style

The repository rules. Comments in plain prose following the punctuation rules, no install
commands anywhere, no absolute paths, no package manager named in any file.

## Gate

Two consecutive runs of `test/inventory.sh` produce byte identical output.
`test/inventory.sh --check` against the committed golden exits zero. Killing the script mid run
with an interrupt still leaves `bin/hs-devlock status` showing the lock free and main live, which
is the trap doing its job. And one deliberate check, editing the golden by one character makes
`--check` exit nonzero showing that line, then restoring it goes green again.

## Out of scope

The unit runner, which is its own packet. Reading `hs.hotkey.getHotkeys()` or anything else on
Hammerspoon's side of the line, since the design records it as blind. Any edit to a registry,
spoon, or config file. Any manifest, map, or Brewfile change. Any behaviour comparison logic
beyond the plain diff, since the empty diff across a toggle flip is performed by the QA loop, not
by this script.
