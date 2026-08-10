# Work packet, recency into core, the proof

Written 2026-08-05 against the tree at `7876295`. Rescan before dispatching if the tree has moved.
This is phase 2 of the build plan at `docs/superpowers/specs/2026-08-04-hammerspoon-olm-build-plan.md`,
and it is the proof phase. The user settled the scope on 2026-08-05, the shared service plus one
converted caller, Vpn, with the other two lift to front callers converting inside their phase 6
copies. The line count this packet records is what the decision point judges, so record it honestly
rather than favourably.

## Goal

`Olm.spoon/lib/recency.lua` exists as the shared lift to front ordering service, covered by the
unit runner, and a converted copy of the Vpn spoon lives under `Spoons/Olm.spoon/plugins/vpn/`
using that service in place of its own hand rolled recency block, wired behind a toggle in the
composition root that leaves the original one comment away and the inventory snapshot identical
across the flip.

## Model

Sonnet. The extraction is mechanical, the conversion is one small block, and the gates catch
failure.

## Read

The design's recency sections in
`docs/superpowers/specs/2026-07-27-hammerspoon-olm-core-and-plugins-design.md`, the remembered
ordering finding near the top and the recency split section, both corrected on 2026-08-05. They
fix that the service is the generic half of `BrowserTabs.spoon/recency.lua`, that key building
stays with each caller, and that the decayed score implementations in Emoji and FileSearch stay
out.

`Spoons/BrowserTabs.spoon/recency.lua`, 131 lines, the donor. Its generic half is `touch`, the
rank memo behind `rankOf`, the stable partition in `order`, the lazy load, the cap, and the one
writer discipline its comments record. Its `keyFor` and its browser reasoning stay behind.

`Spoons/Vpn.spoon/init.lua`, the caller being converted. Its recency block is lines 73 to 110 at
this writing, `RECENCY_KEY`, the `recency` local, `touchLocation`, and `orderByRecency`. Read the
whole file to find every use of those four names, and read the spoon's other files to confirm
none of them reaches the block.

The composition root `dotfiles/hammerspoon/.hammerspoon/init.lua`. The Vpn load at line 59, the
configure block near line 1595, and every other `spoon.Vpn` reference, the predicate near 371,
the launcher action near 1349, the query scope near 1945, and the choosers registry near 2207,
which is why the copy must back the same `spoon.Vpn` name.

`Spoons/Olm.spoon/init.lua` and `lib/storage.lua` for the lib loading pattern, and
`test/cases/storage.lua` for the case pattern.

## Read only

`Spoons/Vpn.spoon` in its entirety, it is copied and never edited. `Spoons/BrowserTabs.spoon`,
`Spoons/Launcher.spoon`, `Spoons/Emoji.spoon`, and `Spoons/FileSearch.spoon`, their recency code
converts in later phases or never. `test/units.sh`, `test/inventory.sh`, and `test/inventory.golden`,
the golden must not change in this packet, an inventory diff is a failure to fix.

## Deliverable

`Spoons/Olm.spoon/lib/recency.lua`, the service. A factory, `M.new(opts)`, returning an
independent instance, since Vpn, Launcher, and BrowserTabs each keep their own list. `opts` carries
`settingsKey`, where the order persists through `hs.settings`, and an optional `limit` capping the
stored list. The instance exposes three functions carrying the donor's semantics exactly. `touch(key)`
lifts a key to the front, dropping any earlier entry for the same key and anything past the cap,
and persists. `rankOf(key)` answers the position, one being most recent, or nil for a key never
touched, built through a memo that is dropped whenever the order changes, the donor's own
performance reasoning. `order(items, keyOf)` returns the items with remembered ones leading in
remembered order and the rest following in arrival order, stable for items sharing a key, with
`keyOf` the caller's function from an item to its key, since key building is caller policy. The
stored order loads lazily on first use, and there is no start or stop.

`Spoons/Olm.spoon/init.lua` gains one line exposing it, `recency` beside `storage` in `obj.lib`.

`Spoons/Olm.spoon/plugins/vpn/`, a full copy of every file under `Spoons/Vpn.spoon/` with exactly
one functional change. The recency block is removed and its four names are served by an instance
of the shared service handed in through `configure`, a new `recency` field in its opts, used with
the same semantics and the same ordering the block gave. The copy keeps its `CLAUDE.md`, its
`contract.lua`, its providers, and its `mullvad.dependencies` declaration unchanged, so the
dependency layer still records what the code runs. Adjust the copy's top comment with one line
saying it is the olm side copy of Vpn, converted to the shared recency service, and where the
original lives.

The composition root toggle. The Vpn load at line 59 becomes a two line toggle with the olm side
active, loading the copy through its absolute path built from `hs.configdir` and assigning the
returned module to `spoon.Vpn`, with `hs.loadSpoon("Vpn")` commented out beside it and a comment
saying flipping the two lines restores the original. Every downstream `spoon.Vpn` reference then
works unchanged and the inventory snapshot is identical either way. In the Vpn configure block,
create the service instance and pass it, `recency = spoon.Olm.lib.recency.new({ settingsKey =
"Vpn.recentLocations" })`, the same settings key the original uses, so the remembered order the
user already has carries across the flip in both directions.

`test/cases/recency.lua`, a unit case in the established pattern. It uses a scratch settings key
of its own, cleared with `hs.settings.clear` or a nil set both before and after its assertions, so
no run touches real data and a failed run leaves nothing behind. It asserts at least, that a
touched key leads the order and a second touch of another key takes the front, that touching an
existing key moves it rather than duplicating it, that `rankOf` answers positions in order and nil
for a key never touched, that `order` puts remembered items first in remembered order and leaves
the rest in arrival order behind them, that two items sharing a key keep their relative order,
that a `limit` drops the oldest key past the cap, and that a second instance created on the same
settings key sees the persisted order.

## Style

The repository rules. Comments in plain prose following the punctuation rules, no colons or
semicolons in any output or error string, no install commands anywhere, no absolute paths written
in any file, no package manager named anywhere.

## Gate

From this worktree with Hammerspoon running. `test/units.sh` exits zero with the recency
assertions counted in, and deliberately breaking one expected value makes it exit nonzero naming
the assertion before restoring it. `src/check-dependencies.sh` from the repository root exits
zero. `test/inventory.sh --check` exits zero with the olm wiring active, then flip the toggle to
the original, run it again, confirm it exits zero, and flip back, proving the swap is invisible to
the whole binding surface. `bin/hs-devlock status` at the end shows the lock free and the main
config live.

The recorded count, in the report and not in any file. Lines removed from the Vpn copy relative
to the original, lines added to the copy, lines added to the composition root, and the size of
`lib/recency.lua` split into code and comment lines. Count with a diff, not by eye.

## Out of scope

Converting Launcher or BrowserTabs, they convert inside their phase 6 copies. Touching the decayed
score implementations in Emoji or FileSearch. Retiring or editing the original Vpn spoon. The
plugin contract, the registry, and the activation list, the copy is loaded directly by the root
until phase 7 exists. Any manifest, map, or Brewfile hand edit, the generated manifest may change
only through the collector picking up the copy's own declarations, and the reconciler staying
clean is the gate on that.
