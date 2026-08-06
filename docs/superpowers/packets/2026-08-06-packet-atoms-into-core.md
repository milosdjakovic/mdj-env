# Work packet, the remaining atoms into core

Written 2026-08-06 against main at `c276695`. This is phase 5 of the olm build plan. Work on a
branch named `feat/atoms-into-core` in a worktree under `../.worktrees/` beside the repo.

## Goal

The six remaining atom spoons move into `Olm.spoon` as core libs, as copies beside untouched
originals behind one root toggle, and the trigger that means Hyper becomes pure data in
`config/settings.lua`, a single key or a modifier chord, with the seam between those two shapes
designed rather than bolted on. The plan says five atoms in two places and the design names six
in three, the count was never corrected when Dependencies stayed on the roster, so this packet
settles it as six and the plan tick will record that.

## Model

Opus. The copies are mechanical but the trigger seam is judgment work entangled with a measured
event tap engine, and a mistake there is invisible until a key is physically held.

## Read

The design `docs/superpowers/specs/2026-07-27-hammerspoon-olm-core-and-plugins-design.md`, the
core table near line 170 and the Hyper trigger requirement near lines 186 to 196, quoted at the
end of this packet in the decisions. The six spoons in full, `Spoons/Chooser.spoon/` with its
three files, and the single file `CanvasPanel.spoon`, `CheatSheet.spoon`, `ChordKey.spoon`,
`HyperKey.spoon`, and `Dependencies.spoon`. `Spoons/Olm.spoon/init.lua` for the loadfile
pattern the libs use. The root `init.lua` wiring for all six, the loads near lines 44 to 50, the
lifecycle calls near 171 to 174 and 195 to 272, and the leader resolution at line 259 where
`keyCode = leaderCode(keys.appLeader)` is the one site that says Hyper is a keycode.
`config/keys.lua` lines 5 and 26 to 38 for the leader catalog and the literal HYPER modifier
list. `config/settings.lua` for the shape a settings block takes. The hammerspoon `CLAUDE.md`
sections on the leader keys and on ChordKey's engine, synthetic events are deliberately ignored
by its tap, which matters for the gate below.

## Decisions already made, build to these

The copies. Each single file spoon becomes one lib file, `lib/panel.lua`, `lib/cheatsheet.lua`,
`lib/chordkey.lua`, `lib/hyperkey.lua`, and `lib/deps.lua`. Chooser becomes `lib/chooser/` with
`init.lua`, `match.lua`, and `providers/native.lua`, its init loading siblings through
`debug.getinfo` exactly as the spoon does today. Every copy keeps its public surface identical,
the colon methods, the tables, the factory shapes, so that assigning it to the spoon global is a
drop in. `Olm.spoon/init.lua` gains the six entries in `obj.lib` through the existing `load`
helper. Originals are never edited.

The toggle. One boolean named `ATOMS_ON_OLM` in the root `init.lua`, beside the clipboard's in
style and reasoning. False is today's config, byte for byte the same behaviour. True skips the
six `hs.loadSpoon` calls and assigns each spoon global from `spoon.Olm.lib`, with
`hs.loadSpoon("Olm")` moved early enough to answer, so every one of the roughly eighty three
existing call sites keeps working untouched on both sides. The observable order of effects at
load stays the same on both sides. The six assignments flip together on the one boolean, no site
may flip alone, and the comment on the block enumerates them the way the clipboard's does.
`lean-init.lua` is out of scope, it keeps loading the original Chooser and Dependencies until a
later phase swaps its tool section.

The trigger seam. `config/settings.lua` gains one block named `hyperTrigger`, pure data, present
in the file so a reader sees what to edit. Its default is `{ kind = "leader" }`, which means
exactly today's path, the `appLeader` row of the keys catalog, the hidutil remap, the keycode
through the hold and tap engine, and on that default the behaviour must be indistinguishable
from today down to the code path taken. The alternative shape is `{ kind = "chord", mods =
{ "shift", "ctrl", "alt", "cmd" } }`, any subset of the four, and it is a Strategy split inside
the hyperkey lib, two trigger strategies behind the one contract the rest of the config already
consumes, `bind`, `isActive`, and `start`. The root reads the block and hands the lib the
descriptor, the lib names no setting and the settings file names no mechanism.

The chord strategy binds each declared binding through `hs.hotkey.bind` on the union of the
chord mods and the binding's own sub mods, so every binding declared against Hyper keeps working
whichever trigger is configured. `isActive` answers whether every chord mod is currently held,
through `hs.eventtap.checkKeyboardModifiers`, and this semantic is pinned, the paste seams query
`isActive` to defer keystrokes while the trigger is physically asserted, so it must be true
exactly while the chord is held. The hold reveal of the cheat sheet comes from a small
flagsChanged watcher owned by the chord strategy, showing after the same hold delay the engine
uses when exactly the chord mods are held and nothing else has fired, hiding when the flags
change. There is no tap behaviour in the chord shape, the caps lock toggle is a property of the
key shape and stays there. Unbound combos need no passthrough machinery, `hs.hotkey` only claims
what it binds. Keep the strategy split inside the hyperkey lib copy only, the chordkey lib copy
stays a faithful copy, and the original spoons learn nothing of any of this.

Dependency declarations change nothing here, atoms are the core rather than consumers of it, and
none of the six declares an external tool today.

## Build

The six copies, the `obj.lib` entries, the root toggle block, the settings block, and the trigger
strategy split in the hyperkey lib. Commit in small steps, copies first, then the toggle, then
the seam. Every line you author follows the repository writing rules, no colons, no semicolons,
no hyphens or dashes, periods and commas only, existing lines you copy keep their form.

## Gate

`test/units.sh` from `dotfiles/hammerspoon/.hammerspoon` passes. `src/check-dependencies.sh`
from the repo root passes with no new warnings. `test/inventory.sh` runs three times, on the
toggle as committed, with the toggle flipped false, and restored, each with an empty diff, and
that script takes and releases the machine wide test lock itself, so run it as it is and never
acquire the lock any other way, never hold it between runs, and leave the tree clean afterward
with the flip reverted through git. The hold and tap engine cannot be driven synthetically, its
tap ignores synthetic events by design, so the live feel of the leader is deliberately not your
gate, it belongs to the adversarial review and the live tier that follow.

## Out of scope

Editing any original spoon. `lean-init.lua`. The plugin contract and registration, phase 7. Any
change to `config/keys.lua` semantics, the catalog and `appLeader` stay exactly as they are and
the leader shape keeps reading them. Retirement of anything. The window leader, it stays on the
original ChordKey wiring through the same toggle like every other call site, do not give it a
strategy of its own.

## Deliverable

Commits on the branch, each ending after a blank line with
Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>. A report with the branch head, each
gate's result, the exact shape you gave the settings block and the descriptor, any place a
decision above did not survive contact with the code, flagged loudly rather than silently
reinterpreted, and the file and line of the seam where the two trigger strategies meet, since
the review that follows will attack exactly there.
