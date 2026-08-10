# Work packet, storage into core, the birth of Olm.spoon

Written 2026-08-05 against the tree at `f72ea93`. Rescan before dispatching if the tree has moved.
This is phase 1 of the build plan at `docs/superpowers/specs/2026-08-04-hammerspoon-olm-build-plan.md`,
the smallest core that does real work. The five storage citations in the design were reverified
against this tree on the day of writing and all hold exactly.

## Goal

`Spoons/Olm.spoon` exists, holding `init.lua` and `lib/storage.lua`, the two storage roots are
pure data in a `paths` block in `config/settings.lua`, the composition root loads the spoon and
injects the expanded roots, and path building is covered by the unit runner. No existing consumer
is rewired, every spoon keeps writing exactly where it writes today.

## Model

Sonnet. The work is fully specifiable and the gates catch failure mechanically.

## Read

The design's storage roots section in
`docs/superpowers/specs/2026-07-27-hammerspoon-olm-core-and-plugins-design.md`, which fixes the
two roots, `~/.cache/hammerspoon` for regenerable data and `~/Olm` for durable data, fixes the
rule that the root owns the concatenation and hands a consumer a finished absolute path, and fixes
that the `paths` block is pure data with the join done elsewhere. The design's Olm.spoon layout
section, which places shared mechanisms under `lib/`. The settled phase 0 decision that the api
version is a single integer starting at one.

`config/settings.lua`, the flat data table the `paths` block joins. `dotfiles/hammerspoon/.hammerspoon/init.lua`
around line 2525, where `storePath` for DisplayProfiles is injected from the root, the existing
model for this kind of wiring. `test/units.sh` and `test/cases/match.lua`, the unit runner and the
case pattern this packet adds a case to. `test/inventory.sh` and `test/inventory.golden`, because
loading a new spoon changes the snapshot and this packet owns that change.

## Read only

Every existing spoon. In particular `ClipboardHistory.spoon`, `Eyedropper.spoon`,
`BrowserTabs.spoon`, and `config/filesearch.lua` keep their current paths untouched, rewiring them
is later work. `test/units.sh` and `test/inventory.sh` are not edited, this packet only adds a
case file and regenerates the golden through the existing script.

## Deliverable

`Spoons/Olm.spoon/init.lua`, a standard spoon table with `name`, `version`, and `apiVersion = 1`.
It loads `lib/storage.lua` relative to its own location, never from a hardcoded path, and exposes
it as `obj.lib.storage`. Nothing else. No registry, no activation list, no plugin machinery, those
are later phases.

`Spoons/Olm.spoon/lib/storage.lua`, the path mechanism. It owns tilde expansion, one function that
turns a leading tilde into the home directory from the environment and leaves any other path
untouched. It owns the join, `configure` receives the two roots as written in settings, expands
them once, and after that `cacheDir(name)` and `dataDir(name)` each return the finished absolute
path of that tool's directory under the matching root, with no trailing slash and no double slash
regardless of how the root was written. Calling a builder before `configure` fails loudly with a
readable error rather than returning a nil or a partial path. Path building is pure string work so
the unit case can cover it without touching the filesystem. A separate `ensure(path)` creates the
directory if missing and returns the path, so a consumer can ask for its directory in one call,
and it is the only function in the file that touches the disk.

The `paths` block in `config/settings.lua`, pure data beside the existing blocks,

    paths = {
      cacheRoot = "~/.cache/hammerspoon",
      olmRoot = "~/Olm",
    },

The composition root wiring in `dotfiles/hammerspoon/.hammerspoon/init.lua`. One block that loads
the Olm spoon and calls `spoon.Olm.lib.storage.configure` with the two roots from
`settings.paths`. The block carries a comment saying it is the olm toggle, commenting these lines
out removes olm entirely, and nothing else references it yet. Place it with the other spoon loads.

`test/cases/storage.lua`, a unit case in the pattern of `cases/match.lua`, locating the checkout
through its own path and loading `lib/storage.lua` with `loadfile`. It asserts at least, that
expansion turns a leading tilde into the value of the HOME environment variable and leaves an
already absolute path alone, that a builder called before `configure` raises a readable error,
that after configuring with the settings values `cacheDir("clipboard")` is exactly the expanded
cache root plus slash clipboard and `dataDir("clipboard")` is exactly the expanded olm root plus
slash clipboard, and that a root written with a trailing slash still produces a single slash join.
The case never creates a directory and never calls `ensure`.

The regenerated `test/inventory.golden`. Loading the spoon adds exactly one `spoon Olm` line to
the snapshot, so run `test/inventory.sh` from this worktree to regenerate, confirm the diff
against the committed golden is only the Olm additions and the count it feeds, and commit the new
golden. Any other line changing means this packet changed behaviour and is a failure to fix, not
a golden to accept.

## Style

The repository rules. Comments in plain prose following the punctuation rules, no install
commands anywhere, no absolute paths in any file, no package manager named anywhere. The spoon
follows the structure conventions in `dotfiles/hammerspoon/.hammerspoon/CLAUDE.md`.

## Gate

From this worktree with Hammerspoon running, `test/units.sh` exits zero with the storage
assertions counted in, and deliberately breaking one expected value makes it exit nonzero naming
the assertion before restoring it. `src/check-dependencies.sh` from the repository root exits
zero. `test/inventory.sh --check` run twice around the golden regeneration shows the before diff
is only the Olm lines and the after diff is empty. `bin/hs-devlock status` at the end shows the
lock free and the main config live.

## Out of scope

Rewiring any existing consumer onto storage, that is phase 2 and later work per consumer. Any
migration of existing files on disk, `~/.cache/hs-clipboard` and the two Library Caches
directories stay where they are. `lib/recency.lua` and every other lib module. The plugin
contract, the registry, and the activation list. Any manifest, map, or Brewfile change. Creating
`~/Olm` or anything under either root at load time, directories appear only when a consumer asks
`ensure`, and no consumer asks yet.
