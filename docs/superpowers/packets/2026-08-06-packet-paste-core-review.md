# Work packet, adversarial review of paste into core

Written 2026-08-06 against `feat/paste-into-core` at `f250e54` in the worktree beside the repo.
This is the phase 3 adversarial review the build plan orders before the architect's own pass. The
build packet it judges against is `docs/superpowers/packets/2026-08-06-packet-paste-core.md`.

## Goal

The builder claims the carve preserves paste timing and behaviour exactly, on both sides of the
toggle. Your job is to refute that claim. You succeed by finding a real difference, and if you
find none, you report what you tried and why each attempt failed, not a blessing.

## Model

Opus. Adversarial review of timing measured code is judgment work.

## Read

The build packet, then the builder's four commits `c846aff`, `43fb633`, `1783092`, and `f250e54`
in full. The donor `Spoons/ClipboardHistory.spoon/manager/monitor.lua` at 918 lines, the ground
truth every claim is measured against. The new `Spoons/Olm.spoon/lib/paste.lua`, the copy under
`Spoons/Olm.spoon/plugins/clipboard/`, the changed root `init.lua`, the swapped tool section of
`lean-init.lua`, and the trail in `Spoons/Olm.spoon/CLAUDE.md` against its source in the module
level `CLAUDE.md` lines 1108 to 1230.

## Where to attack

Timing first. Every delay, queue rule, cap, settle callback, and scheduling order in the donor's
insertion half against the lib, including anything that moved from a direct call to a threaded
injection, since an extra function hop is free but an extra timer hop is not. The builder claims
six constants unchanged and several functions byte identical, verify rather than trust.

The seams second. The builder reports three crossings where the design counted two, `selfSigs`
behind `wroteRecently`, `ownPasteCount` behind `ownPasteInFlight`, and `lastChange` behind
`accountChange`, plus `isReading` consulted by the poll. Hunt for races and holes the split
introduces, an echo arriving inside or outside the window it would have hit in the donor, an
image paste whose changeCount accounting differs by one, a poll tick landing between a write and
its accounting where the donor's single file made that impossible, the walk watcher seeing the
walk's own Cmd+V during any instant the count sits at zero where the donor's did not.

The descriptor third. The lib takes `kind`, `text`, `full`, and `files` of `{ stored, path }`.
Check every caller builds exactly what the lib reads, that `media.resolveForPaste` still runs at
the moment of the write, and that a paste of every kind, text, url, image, and file, walks the
same code path at the same instants as the donor.

The toggle fourth. The original side of every branching site must be the donor's behaviour
verbatim, Emoji and TextCase closures included, and the olm side must never leak into it. Check
the three sites cannot be flipped independently, that the manager validation fires when the
injection is missing, and that the lean surface exercises the real wiring rather than a kinder
copy of it.

The removals last. The manager's outward wrappers are gone and `store` left the lib with reorder
moving to `ui.lua`. Find any caller, timing, or ordering that silently changed because of either,
including `setLogLevel` and the debug timeline, and check the moved reorder happens at the same
point in the paste's lifecycle as before.

## Out of scope

Style and prose, the architect reads for that. The unit runner and the scripted gates, they ran.
Proposing improvements, your only question is whether behaviour or timing changed.

## Deliverable

Findings ranked most severe first, each with the exact file and line on both sides, the concrete
scenario in which a user feels the difference, and your confidence. Default to refuted when
uncertain and say what evidence would settle it. If nothing survives your best attempts, list the
attacks you ran and what killed each one. Raw findings for the architect, no polish. You change
nothing, you run nothing live, you never touch bin/hs-devlock or the live config.
