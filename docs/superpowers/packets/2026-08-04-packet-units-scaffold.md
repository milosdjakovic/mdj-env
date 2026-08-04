# Work packet, the unit runner and the first cases

Written 2026-08-04 against the tree at `0aaed46`. Rescan before dispatching if the tree has moved.
This is the first of the two phase 0 scaffolds in the build plan at
`docs/superpowers/specs/2026-08-04-hammerspoon-olm-build-plan.md`, and it is dispatched only when
the user opens the build.

## Goal

A runner at `dotfiles/hammerspoon/.hammerspoon/test/units.sh` and a `test/cases/` directory beside
it, running pure Lua unit cases through the live Hammerspoon's own interpreter with no test lock
taken, covering `Chooser.spoon/match.lua` first.

## Model

Sonnet. The work is fully specifiable and the gate catches failure mechanically.

## Read

The design's section on proving a step changed nothing, the unit tier, in
`docs/superpowers/specs/2026-07-27-hammerspoon-olm-core-and-plugins-design.md`. It records the two
verified facts this packet stands on, that the `hs` command line tool runs Lua 5.4 inside the
running Hammerspoon over `hs.ipc`, and that `dofile` loads a module straight out of a working tree
without that checkout being the live config, which is why no lock is needed.

The module under test, `dotfiles/hammerspoon/.hammerspoon/Spoons/Chooser.spoon/match.lua`, 177
lines at this writing. It exposes three pure strategies, `M.fuzzy`, `M.substring`, and `M.words`,
each a function of a query and a haystack returning a score or nil, where nil drops a row and a
higher number ranks higher. Its top comment block documents every property worth asserting.

## Read only

Every existing file. This packet creates new files only, all under
`dotfiles/hammerspoon/.hammerspoon/test/`. The module under test is loaded, never edited.

## Deliverable

`test/units.sh`, a bash runner that resolves the repository root from its own location, never from
a hardcoded path, finds every Lua file under `test/cases/`, and runs each one through the `hs`
command line tool by handing the case's absolute path to `dofile`. It must never inline Lua source
at the shell, because a `<` or `>` character in inline Lua wedges the `hs` client, so the only Lua
that ever crosses the command line is a `dofile` call carrying a path. The runner counts passing
and failing assertions across all cases, prints one line per failure naming the case and the
assertion, and exits nonzero when anything failed. When the `hs` tool is absent or does not answer,
it fails with one readable line saying Hammerspoon must be running, rather than a hang or a stack
trace.

`test/cases/match.lua`, the first case file. It locates the checkout through
`debug.getinfo(1).source`, its own path when loaded by `dofile`, and derives the path to the module
under test from there, so no absolute path appears anywhere. It asserts at least the documented
properties of each strategy. For `fuzzy`, that a query whose letters are present matches and one
whose letters are mostly absent returns nil, that a near contiguous match outranks the same letters
scattered across separate words, the recorded example being `dspl` against `Displays` versus a
scattered keyword bag, that one wrong letter inside an otherwise good query still matches through
the typo tolerance, and that a low scoring scattered alignment falls under the relevance floor. For
`substring`, that a plain substring matches, a non substring returns nil, and every match scores
the same so the supplier's order survives. For `words`, that a row is kept when every whitespace
separated word of the query is a substring of the haystack in any order, dropped when one word is
missing, and that a prefix of a word still hits.

No `init.lua` toggle. Nothing in this packet loads at config time.

## Style

The repository rules. Comments in plain prose following the punctuation rules, no install
commands anywhere, no absolute paths, no package manager named in any file.

## Gate

From this checkout with Hammerspoon running and the test lock untouched,
`dotfiles/hammerspoon/.hammerspoon/test/units.sh` exits zero and reports how many assertions ran.
Deliberately breaking one expected value makes it exit nonzero naming the failing assertion, then
restoring it goes green again. `bin/hs-devlock status` before and after shows the same lock state
and the same live config, proving the runner took nothing.

## Out of scope

The inventory scaffold, which is its own packet. Any edit to `match.lua` or any spoon. Any
manifest, map, or Brewfile change. Any CI or scheduling wiring. Cases for modules other than
`match.lua`, which arrive with the phases that touch them.
