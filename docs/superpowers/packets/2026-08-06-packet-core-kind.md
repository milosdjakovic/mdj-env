# Work packet, the core dependency kind

Written 2026-08-06 against main at `295af17`. This is phase 4 of the olm build plan, the new
dependency kind named `core`, settled in the design at
`docs/superpowers/specs/2026-07-27-hammerspoon-olm-core-and-plugins-design.md` lines 490 to 504.
Work on a branch named `feat/deps-core-kind` in a worktree under `../.worktrees/` beside the repo.

## Goal

A plugin under `Spoons/Olm.spoon/plugins/` declares which Olm core capabilities it needs in the
same manifest that already declares outside tools, through one new kind named `core` alongside
`path`, `system`, `app`, `manual`, and `package`. The reconciler then makes the declaration mean
something, a core capability handed out by the root without a declaration is an error, and a
declared one nothing uses is a question. The declaration decides injection rather than
installation, which is the one asymmetry against every existing kind, and the documentation must
say so.

## Model

Sonnet. The judgment calls are settled below, the rest is specifiable shell and manifest work.

## Read

The design lines 490 to 504. The collector `dotfiles/hammerspoon/dependencies-collect`, whose
five field leaf format and consumer stamping you extend nothing about, a core line flows through
it untouched. The reconciler `src/check-dependencies.sh` in full, its numbered checks, its `err`
and `warn` helpers, the kind dispatch in check five at lines 283 to 310, and the leak checks of
check four at lines 216 to 274. `DEPENDENCIES.map` and `map_detail` at line 125. The dependency
contract section of `dotfiles/hammerspoon/.hammerspoon/CLAUDE.md` lines 16 to 98. The two
existing injection sites in the root `init.lua`, recency into Vpn at line 1629 and paste into the
clipboard manager at line 2213, plus the two paste reads for emoji at 1693 and text case at 1721.

## Decisions already made, build to these

The declaration is the ordinary five field leaf line beside whatever knows the need. The
clipboard manager knows it needs the insertion engine, so a `dependencies` snippet beside
`plugins/clipboard/manager/` declares `paste | core | lib/paste.lua | required | ...`, and the
vpn plugin declares `recency | core | lib/recency.lua | optional | ...` beside the file that
consumes it, optional because only its location ordering degrades without it. The locator names
the lib file relative to `Olm.spoon`, documentation the same way the package kind's locator is.

The map gains one origin named `olm`, whose detail is the lib path relative to
`Spoons/Olm.spoon`, so `DEPENDENCIES.map` stays the single place that says where a name comes
from and the reconciler stays free of hardcoded module paths. Presence in check five for the
`core` kind asks the map for the detail and tests that the file exists under the repo's
`Olm.spoon`, and that one resolution is the single commented seam where the script may name
`Olm.spoon`, keep it in one place and say in the comment that it is the seam.

The declared against used check reconciles at the name level, not the consumer level, and lives
as a new numbered check beside check four. Three directions. Every `spoon.Olm.lib.` reference
under `dotfiles` must name a capability that some manifest line declares with kind `core`, so
handing out an undeclared capability is an error. Every declared core capability must be
referenced somewhere, an unused declaration is a warning in the spirit of check two. And no file
under `Spoons/Olm.spoon/plugins/` may reference `spoon.Olm` at all, a plugin takes injection
through its own configure and never reaches around that door, an offense is an error. Name level
matters because emoji and text case are original spoons that also receive paste from the root,
originals are read only and will never carry declarations, and the name level rule lets the
clipboard manager's declaration cover the capability while still catching a capability nobody
declared.

The contract documentation gains one bold lead paragraph in the dependency section of the
hammerspoon `CLAUDE.md`, in the same voice as its neighbours, saying what `core` is, that it
decides injection rather than installation, that its map origin is `olm`, and that the reconciler
ties every `spoon.Olm.lib.` reference to a declaration.

## Build

The two declaration snippets, the map rows for `paste` and `recency` under origin `olm`, the
`core)` branch in check five, the new numbered check, and the `CLAUDE.md` paragraph. Regenerate
the hammerspoon manifest through the collector rather than editing the generated file by hand.
Every new string you author follows the repository writing rules, no colons, no semicolons, no
hyphens or dashes, periods and commas only.

## Gate

`src/check-dependencies.sh` exits zero with no new warnings beyond any that already exist on
main. Then one deliberate violation refused readably, delete the clipboard manager's core
declaration line, run the reconciler, capture the error text, confirm it names the capability and
reads as a sentence a person can act on, and restore the line. Do the same for a planted
`spoon.Olm` reference inside a plugin file, then remove the plant. Both captures go in your
report. `test/units.sh` from `dotfiles/hammerspoon/.hammerspoon` still passes. No devlock, no
live config, nothing here loads into Hammerspoon.

## Out of scope

The registration door and api version, that is phase 7. Editing any original spoon. Editing the
Brewfile. The storage capability, nothing injects it into a plugin today, the root configures it
directly, so it gets no declaration until a plugin actually takes it. Any change to how the root
injects.

## Deliverable

Commits on the branch, small and honestly messaged, each ending with the line
Co-Authored-By: Claude Fable 5 <noreply@anthropic.com> after a blank line. A report with the
branch head, the gate outputs including both refusal captures, and any place where these
decisions did not survive contact with the code, flagged rather than silently reinterpreted.
