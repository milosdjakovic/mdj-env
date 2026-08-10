# Work packet, the dedicated shortcut joins the descriptor and answers to activation

Phase 7 of the build plan, packet five of five, the last. Written 2026-08-10 against
`feat/plugin-contract` after packets one through four landed. Work in the worktree at
`../.worktrees/plugin-contract` on the branch already checked out there. Never work from the
primary checkout, never push, never merge.

Read the four earlier packets and `Spoons/Olm.spoon/lib/registry.lua` before starting.

## The promise this packet finally keeps

Since packet one the registry has held an activation list, and since packet one that list has been
half a lie. Deactivating a tool today takes away its launcher row, its query scope and its
navigation keys, and leaves its keyboard shortcut bound and firing. The registry's own header says
so in as many words. This packet is what makes that sentence deletable.

Nothing in this config ever unbinds a key. `HyperKey` has no removal and `hs.hotkey` is never
asked for one, and inventing teardown is exactly the single caller ceremony with a silent failure
mode that the design rejects. So the answer is not to unbind an inactive tool. It is to never bind
it. The registrations already sit below every declaration they need, and the binds can sit below
the registrations, so at bind time the registry already knows what is active.

## The gap that has to be closed first

Nothing measures a binding. The snapshot records the two physical leader keys and nothing about
which letter reaches which tool, the cheat sheet's app section but not its actions section, and the
in chooser navigation keys but never the base chord that opens the chooser in the first place. If
somebody deleted the line that binds Hyper and P to the VPN, every gate in this repository would
stay green.

**The first code commit is instrumentation and nothing else**, the same discipline packet three
used. Add two sections to `test/inventory.lua`. One reads `spoon.HyperKey._bindings` live, sorted
by key code, recording per key how many bindings exist and how many of them are base bindings,
meaning those carrying no `when`. The other reads `hs.hotkey.getHotkeys()`, sorted, which is what
covers the two global combinations that never touch the leader. Reaching into a private field is
consistent with what this file already does for the chord tree and the cheat sheet. Update
`test/inventory.golden` in the same commit, change no behaviour, and that commit is the baseline
everything after it is measured against.

## The descriptor gains a shortcut

`shortcut`, optional, one of exactly two strings. `"leader"` means this tool's entry in
`config/keys.lua` names a key that is bound through the Hyper leader to this tool's `open`.
`"global"` means the entry names a whole modifier combination bound directly, which is what the two
clipboard commands are and the only thing they are. A command inside `commands` may carry the same
field, and `appendCopy` and `pasteNext` are the two that will.

Refused when present and not one of those two strings, naming the tool and what it said. Refused
when a tool or command declares a shortcut and has no `open` or no function to bind, naming it,
since a shortcut bound to nothing is worse than no shortcut.

Do not put the key itself on the descriptor. The key lives in `config/keys.lua` and this registry
reads no configuration, exactly as it does not hold a scope's title or aliases.

The registry gains `shortcuts()`, answering in registration order one entry per active tool or
active tool's command that declares one, each carrying the name, the kind, and the function to
bind. An inactive tool contributes nothing, itself or its commands, and that single sentence is the
whole feature.

## The composition root

Seven tools are bound today by a direct `spoon.HyperKey:bind` call, `menuSearch`, `vpn`,
`caffeinate`, `emoji`, `browserTabs`, `fileSearch`, and `colorPicker`, the last through the local
`bindHyper` wrapper. The clipboard is bound differently, through
`spoon.ClipboardHistory:bindHotkeys`, which binds its own open through the leader and its two
commands as global combinations.

Give `shortcut = "leader"` to those seven and to `clipboard`, and `shortcut = "global"` to
`appendCopy` and `pasteNext`. Then delete those eight bind sites and replace them with one loop
below the activation call, walking `registry.shortcuts()` and binding each entry, resolving the
keys entry the same way `addTool` does, through the row's `keysName` or the name itself, and
choosing `spoon.HyperKey:bind` or `hs.hotkey.bind` from the kind.

The root stops calling `spoon.ClipboardHistory:bindHotkeys` entirely. Leave that method in the
plugin untouched, since the plugin is still shaped to stand alone and three other spoons implement
the same convention. Say in a comment that the root no longer calls it and why.

**Prove the order does not matter rather than assuming it.** Two bindings on the same key never
warn, and among equal priorities the first registered silently wins forever. Before you move
anything, list every key bound as a base binding, the eight tools plus the launcher plus lock and
sleep, and confirm no two share one. Report that list. If any two do share a key, stop and tell me,
because then order is load bearing and this packet needs rethinking rather than reordering.

Leave the launcher, `lock` and `sleep` bound exactly where and how they are. None is a registered
tool.

## Then delete the sentence

`Spoons/Olm.spoon/lib/registry.lua`'s header says inactive still does not unbind a chord. Once
this lands that is false, and the file must say what is now true, that an inactive tool is never
bound in the first place, and why never binding is the right answer rather than tearing down.

## Known defect, deliberately not fixed here

The scan found that `keys.fileSearch` is never added to `hyperActions`, so file search has a live
Hyper and slash chord that the Hyper hold overlay does not list, while every other chorded tool is
listed. That is a real defect and it is exactly the drift this whole phase exists to prevent, since
the cheat sheet list is hand maintained beside everything else.

Do not fix it in this packet. Making a new row appear in that overlay is a visible change to what
the user sees and it is theirs to ask for. Note it where `hyperActions` is built, saying plainly
that the list is hand maintained, that file search is missing from it today, and that deriving it
from the registry is the obvious next step and was deliberately left.

## What not to change

Do not touch `hyperActions`, the `hyperContexts` loop, `config/keys.lua`, any plugin file, the
predicates, the launcher, `QueryScope`, or anything to do with rows, scopes or surfaces. Do not add
an unbind to anything. Do not change `HyperKey`. Do not gate a plugin's `dofile`, `configure`, or
`start` on activation, which stays out of scope for the whole phase.

## Gates

`luac -p` parses every touched file.

`test/units.sh` passes, with new cases covering both shortcut refusals, the refusal of a shortcut
with nothing to bind, `shortcuts()` listing an active tool and its command, an inactive tool
contributing neither itself nor its commands, and registration order preserved. Report the
assertion count before and after.

`src/check-dependencies.sh` passes with no new warnings.

`test/inventory.sh --check` three times with a five minute timeout each. After the instrumentation
baseline lands, **every section including both new ones must be byte identical for the rest of the
packet**. The whole point is that the same keys are bound to the same things by a different route.
A single key moving is a failing gate and a real finding. Print both new sections from the baseline
and from the end state.

## Deliverable

This packet committed first. Then the instrumentation with its golden. Then the registry with its
cases. Then the root. Then the documentation. Small commits. Every message ends after a blank line
with

    Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>

and every subject has the form scope subject with no colon after the scope. Do not merge.

Documentation extends the Registry section of `Spoons/Olm.spoon/CLAUDE.md`, covering the shortcut
field and its two kinds, why the key is not on the descriptor, why never binding beats unbinding,
and what activation now means in full, which after this packet is a tool's row, its surface, its
scope and its shortcut all together. The hammerspoon `CLAUDE.md` or the launcher's may carry a
claim about how a tool's chord is wired that is now stale, so grep for one and correct it if it
exists. Touch nothing else.

Report the accessor, the commit hashes, each gate's real numbers, the base binding key list proving
no two collide, both new inventory sections at baseline and at the end, and anything in this packet
that did not survive contact with the code, flagged loudly. If a decision here turns out wrong once
you can see the code, stop and say so rather than choosing for yourself.

Every line you author follows the repository writing rules, no colons, no semicolons, no hyphens or
dashes, periods and commas only. Copied names and existing identifiers keep their form.

## Hazards

This packet touches the most visible thing in the config, so a mistake here is one the user feels
immediately rather than one a gate catches. Bind nothing you cannot see bound in the snapshot.

Never run `bin/hs-devlock`, the inventory script owns the lock, and give that script a five minute
timeout since killing it mid run strands the lock. Never call `hs.logger.setGlobalLogLevel`. Never
pass an angle bracket inside inline Lua to `hs -c`. Never call `hs.reload` inline, schedule it with
`hs.timer.doAfter` and poll `hs.configdir`. A console read can take minutes and is not hung. Never
run `git reset`, `git checkout` on a path, or `git stash` to clean the tree, read `git status` and
report instead. Never write an absolute path into any file.
