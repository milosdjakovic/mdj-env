---
allowed-tools: Read, Glob, Grep, Edit, Write, Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(./src/check-dependencies.sh:*), Bash(dotfiles/hammerspoon/.hammerspoon/Spoons/Olm.spoon/test/drygate.sh:*), Bash(dotfiles/hammerspoon/.hammerspoon/Spoons/Olm.spoon/test/suite.sh:*)
argument-hint: [plugin name or what it should do]
description: Build or modify an Olm Hammerspoon plugin against the authoring guide
---

# Olm plugin work

You are about to build or change a plugin in the Olm Hammerspoon config. Do not start from
memory of how these plugins look. The contract has moved several times and a plugin written
from a stale mental model registers, reports success, and shows nothing.

`$ARGUMENTS` names the plugin or describes what it should do. If it is empty, ask what the
plugin is before reading anything.

## Step 1, read the guide

Read `dotfiles/hammerspoon/.hammerspoon/Spoons/Olm.spoon/docs/PLUGIN-AUTHORING.md` in full
before touching a file. It is short and it is a recipe. It tells you the two files, the three
things you must declare, what declaring only those already buys you, what each optional field
costs and earns, how a level nests, which words the composition root publishes, the exact list
of mistakes the wiring layer refuses loudly, and the shorter list nothing catches at all.

Read `docs/PLUGIN-CONTRACT.md` in the same directory only for depth on a field the guide sent
you there for. Do not read it front to back instead of the guide.

If you are changing an existing plugin rather than writing a new one, read that plugin's own
`manifest.lua` and its `CLAUDE.md` or `README.md` where it has one, and treat its stated design
record as binding. A plugin's own author already decided things the wiring layer does not get
to overrule.

## Step 2, rescan before trusting a citation

The guide cites `lib/registrar.lua`, `lib/registry.lua`, `host/stage/init.lua`, and
`root/compose.lua`. These files change. Before you rely on any behavior the guide describes,
open the file and confirm it still says that. Where the guide and the code disagree, the code
is reality and the disagreement is a finding to report, never something to work around
quietly.

## Step 3, follow the build order

Work the ten step checklist at the end of the guide in order. It exists because the failure
modes here are silent. A plugin with a wrong call kind, a missing row category, or a root
sourced need nothing publishes still loads, still registers in appearance, and still answers
its key with an empty list and a clean console.

Add optional presentation fields one at a time, and only because something was actually wrong
without one. Declaring a field speculatively is how this contract accumulated dead wiring
before.

## Step 4, dependencies

A plugin declares what it needs and installs nothing. Every external binary or bundle belongs
in `needs.tools` with a kind, a policy, a reason, and an origin, declared there and nowhere
else.

Never write an install command anywhere, including in a comment or in help text a person
reads. The repository root holds the answer key. When the plugin declares something new, add
the line to `DEPENDENCIES.map` and the matching entry to the `Brewfile`, then run
`./src/check-dependencies.sh` and leave it with no error and no new warning naming this
plugin. The full rule is the dependencies section of the repository root `CLAUDE.md`.

## Step 5, the gate before committing

Run the dry contract gate, `dotfiles/hammerspoon/.hammerspoon/Spoons/Olm.spoon/test/drygate.sh`,
or `test/suite.sh dry` from the same directory. It is the lock free check that reads a manifest
and its module and reports every registrar and registry refusal without Hammerspoon running, in
well under a second. A finding fails it; a module that will not load or configure under its stub
prints as unknown and does not fail it unless `--strict` is given. Run it and read the line it
prints naming your tool before committing.

Never run `hs`, never reload the live config, and never take the devlock as part of this
command. Making a change live is a separate decision with its own discipline in the hammerspoon
`CLAUDE.md`, and the screen is never driven for a test until Milos says start.

## Step 6, write it the way this tree writes

Comments and docs explain why, not what. Dense prose, plain sentences, only periods and commas.
No em dashes, no en dashes, no hyphens in prose. This applies to the manifest comments, the code
comments, and the commit message alike.

Commit on a branch in `olm(scope) ...` style matching the recent history, where the scope is the
plugin or the layer touched. Do not merge and do not push unless asked.
