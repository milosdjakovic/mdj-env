# Work packet, adversarial review of the bundling pass

Written 2026-08-06 against `feat/plugin-bundle` at `05f4813` in the worktree beside the repo.
This is the phase 6 whole branch review the plan orders before anything lands. The build packet
is `docs/superpowers/packets/2026-08-06-packet-plugin-bundle.md`.

## Goal

The branch claims no behaviour change, twenty three plugin copies live behind toggles defaulted
true and every original untouched behind them, plus one collector fix and one recency
conversion. Refute it. You succeed by finding a real difference a user would feel, and if you
find none you report what you tried and why each attempt failed, not a blessing.

## Model

Opus. A no behaviour change claim across roughly twenty five thousand copied lines and twenty
six toggles is judgment work.

## Read

The build packet, the batch commits and the three wiring commits ending at `05f4813`, the
originals as ground truth where you sample, the root `init.lua` toggle blocks, the collector
fix in `dotfiles/hammerspoon/dependencies-collect`, the regenerated manifest, and the
BrowserTabs conversion, `plugins/browsertabs/init.lua` against `Spoons/BrowserTabs.spoon/` with
its `recency.lua`.

## Where to attack

The loads first. A copy arrives by `dofile` where the original arrived by `hs.loadSpoon`, which
also printed a console line, set `spoonPath` and `spoonMeta` on the object, and called `init`.
Check every one of the twenty three for a read of anything `hs.loadSpoon` alone provides, an
`init` that does real work and is never called on the copy side, or a load time side effect
whose order moved. KeyRemap deserves its own look, it shells to hidutil and the machine's keys
depend on it.

The toggles second. Per tool independence is the point of twenty four booleans, the user will
flip one tool back while the rest stay on olm. Hunt for a pair of copies or a copy and an
original that secretly share state or order such that a mixed flip misbehaves where all true
and all false both pass, the window group and the terminal placement closures are the likely
places, and the clipboard against text case and emoji, which inject engine pieces across tool
lines.

The conversion third. The original `recency.lua` against `lib/recency.lua` order semantics,
byte for byte identity of the stored key and the cap, what happens to an existing persisted
order the first time the copy reads it, and the degradation path when the injection is nil.
The `keyFor` inlining, prove the encoded key is identical for every bundle id and url shape
including nils.

The collector fix fourth. Every consumer label in the regenerated manifest against where its
declaration sits, no label may have changed for any original spoon, the olm side labels must
name plugin directories, and probe the fix against a declaration directly under
`Olm.spoon/plugins/<dir>/` and one nested two deep, plus the pathological cases, a directory
named like a suffix of another and a declaration at `Olm.spoon/lib/`.

The reconciler fifth. With the copies present twice, once capitalized and once lowercase, check
no check in `src/check-dependencies.sh` silently double counts, and that the core name level
check still holds with the new browsertabs declaration.

## Out of scope

Style and prose. The scripted gates, they ran. The live feel of anything, the user's final
checklist owns that. Proposing improvements.

## Deliverable

Findings ranked most severe first, each with file and line on both sides, the concrete scenario
a user feels, and your confidence. Default to refuted when uncertain and say what evidence
would settle it. If nothing survives, list the attacks and what killed each. You change
nothing, you run nothing live, you never touch bin/hs-devlock or the live config.
