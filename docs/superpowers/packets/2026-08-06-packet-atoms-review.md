# Work packet, adversarial review of the atoms into core

Written 2026-08-06 against `feat/atoms-into-core` at `5463ae2` in the worktree beside the repo.
This is the phase 5 adversarial review, before the architect's own pass and the live tier. The
build packet it judges against is `docs/superpowers/packets/2026-08-06-packet-atoms-into-core.md`.

## Goal

The builder claims two things. On the default leader shape, both sides of the `ATOMS_ON_OLM`
toggle behave identically, down to the code path taken. And the chord strategy honours every
pinned decision in the build packet, the isActive semantic above all. Refute either. You succeed
by finding a real difference or a broken decision, and if you find none you report what you
tried and why each attempt failed, not a blessing.

## Model

Opus. Event tap timing and a toggle across six load bearing atoms is judgment work.

## Read

The build packet, then the builder's four commits ending at `5463ae2` in full. The six original
spoons as ground truth. The seam in `Spoons/Olm.spoon/lib/hyperkey.lua`, the `TRIGGERS` table at
line 266, both strategies, and the lazy build at line 474. The root toggle at `init.lua:70` and
the descriptor resolution near lines 309 to 319. `config/settings.lua` near line 183. The six
core lines added to `dotfiles/hammerspoon/dependencies-module` and the six map rows. The timer
law in the hammerspoon `CLAUDE.md`, never start a timer without keeping its handle, the chord
hold reveal is new timer code and answers to it.

## Where to attack

The toggle first. The builder hoisted `hs.loadSpoon("Olm")` and moved `KeyRemap` one slot, and
the packet demands the observable order of effects at load stays the same on both sides. Check
what each moved load does at load time and whether anything, the hidutil remap above all, can
land in a different order relative to anything that observes it. Check the six assignments
against every one of the roughly eighty three call sites, especially the lifecycle calls, colon
methods on an object that was never given to `hs.loadSpoon`, and anything reading `spoon.X`
before the toggle block runs.

The leader shape second. The builder says the leader branch is the original start body verbatim
and both shapes share `_resolve`. Verify by diffing the code paths, not by trusting. The keyCode
is now passed twice, check both sides agree when the catalog names a different key, and check
the original side still falls back to 79 identically.

The chord strategy third. The pinned isActive semantic, true exactly while every chord mod is
physically held, including inside a binding callback, during the hold reveal, and in the instant
after `hs.hotkey` fires. The hold reveal timer against the timer law, its handle must live
somewhere collection cannot reach. The sub modifier collision the builder flagged, Hyper plus
Shift plus a key under a chord already holding shift, confirm the analysis and check whether any
binding in `config/keys.lua` today would be silently unreachable under the documented example
chord. The swallow difference, a gated shut binding still claims its combo under `hs.hotkey`
where the leader shape leaked it downstream, say how a user would feel it.

The declarations fourth. Six core lines in `dependencies-module` and six map rows. Check the
collector accepts them, the generated manifest carries them with the module consumer, the
reconciler's name level check is satisfied by them, and the runtime resolver skips them without
a sound, the phase 4 behaviour. Check the map details name lib paths that actually exist,
`lib/chooser/init.lua` against `lib/chooser.lua` being the kind of slip to hunt for.

The copies last. The two zero delta files aside, confirm the header only deltas change nothing
loaded, and attack the deps path walk, a trailing slash, a symlinked config dir, the resting
main stow view where `hs.configdir` differs from the repo worktree, since that match pattern now
strips two components and the original strips one and both must resolve to the same Spoons
directory in every one of those layouts.

## Out of scope

Style and prose. The scripted gates, they ran. The live feel of a held leader, that is the tier
after you and it cannot be driven synthetically. Proposing improvements.

## Deliverable

Findings ranked most severe first, each with file and line on both sides, the concrete scenario
a user feels, and your confidence. Default to refuted when uncertain and say what evidence would
settle it. If nothing survives, list the attacks and what killed each. You change nothing, you
run nothing live, you never touch bin/hs-devlock or the live config.
