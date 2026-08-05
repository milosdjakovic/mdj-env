# Olm build plan, the checklist the design gets executed against

## What this file is

The design at `2026-07-27-hammerspoon-olm-core-and-plugins-design.md` holds every decision and its
reasoning. This file holds the execution, the sequence, the checkboxes, and the loop each step goes
through. It is a living document, boxes get ticked as steps land, and nothing here repeats the
design's reasoning, it points at it. When the two disagree the design wins and this file gets
fixed.

The user opened the build on 2026-08-05. The first dispatch was the two phase 0 scaffold packets,
sent to Sonnet agents in parallel worktrees the same day. Until that date this plan was standing
but closed, per the plan only rule that governed the design phase.

## The two laws over every step

**Originals are read only.** No existing spoon is destroyed, moved, or edited. New code is built
beside the old, `init.lua` carries both wirings with one commented out, and the user flips between
them to compare. Retiring an original is its own step at the very end, ordered per tool by the
user, never bundled into anything.

**The roles are split.** The architect and QA orchestrates and writes no implementation code.
Subagents build from work packets, and every result is reviewed against the packet's gate. A
result that falls short goes back with a concrete list of what to fix, it does not get patched in
review.

## Which model builds what

The rule is one question asked of every packet. Can its correctness be fully written down. When
the packet can specify the work completely and a gate can mechanically catch the failure, a Sonnet
agent builds it. When correctness lives in judgment the packet cannot encode, an Opus agent builds
it. The builder never certifies itself either way, and the architect remains the last check on
everything.

Sonnet work, the scaffolds, storage, recency, the dependency kind, the atoms, the bundling batches,
and the README sweep. All of it is mechanical or precisely specifiable, and each has an objective
gate, a unit run, a line count, a reconciler pass, or an empty inventory diff.

Opus work, the paste extraction, whose correctness is a measured delay the packet can only gesture
at, the plugin contract, the seam every plugin registers through where a wrong shape taxes every
later phase, the action panel and snippets, new behaviour judged against the interaction grammar
rather than against a diff.

Opus has a second job, adversarial review. For the two dangerous steps, paste and the bundling
branch, an Opus agent receives a packet that says try to refute the claim that nothing changed,
and it runs before the architect's own pass. Rescans split the same way, cheap read only agents
gather facts, and judging what a drifted fact means stays with the architect.

One packet, one agent, one branch. Phases run in sequence, and inside a phase independent packets
fan out in parallel worktrees, the bundling batches and the READMEs being the obvious wins.

## The loop every step runs

Each step below goes through the same cycle, and skipping a stage is how a mechanical migration
goes wrong quietly.

1. **Rescan.** Spoons change under this plan, so the step's citations and assumptions are
   reverified against HEAD before anything else. A drifted assumption updates the design first.
2. **Packet.** The architect writes the work packet, files to read, files that are read only,
   the deliverable, the gate, and the toggle expected in `init.lua`.
3. **Build.** An agent implements the packet on a feature branch in a worktree under
   `../.worktrees/`, per the repo convention, Sonnet or Opus per the model rule above. The agent
   never sees an instruction to edit an original.
4. **QA.** The architect reads the full diff against the packet, runs the gates, and checks the
   one rule that spans everything, a step gated on an empty inventory diff changed no behaviour.
   Shortfalls go back for rework with a list.
5. **Live test.** The user flips the `init.lua` toggle and uses the machine. The old wiring stays
   in place commented out. Only the user says a step feels right.
6. **Land.** Merge to main when the user asks. The toggle stays until the retirement step, so
   flipping back remains one comment away.

## Work packet template

Every packet an agent receives has these parts, so no packet relies on the agent guessing.

    Goal          one sentence, what exists when this is done
    Model         Sonnet or Opus, per the model rule, decided when the packet
                  is written and never left to the moment
    Read          the design sections and files that define the work
    Read only     the original spoons this step must not touch, named explicitly
    Deliverable   the new files and the init.lua toggle block
    Style         the repo CLAUDE.md rules, comments in plain prose, no install
                  commands anywhere, no absolute paths
    Gate          the exact commands and the expected result
    Out of scope  what the agent must leave alone even if it looks easy to fix

---

## Phase 0, unblock and scaffold

Nothing in this phase writes olm code, and the first build step cannot start until the boxes that
block it are ticked.

- [x] Commit the design's current revision, the action panel material is the only unprotected part
      of it.
- [x] Decide the content root. Settled 2026-08-04, one visible home directory for everything
      durable, two roots not three, `~/Olm` proposed as the name, recorded in the design's storage
      section. This was the decision blocking storage, so phase 1 is now unblocked.
- [x] Pick the action panel chord. Settled 2026-08-04, Hyper period.
- [x] Name the new manifest kind for a core dependency. Settled 2026-08-04, `core`.
- [x] Decide how the api version is numbered. Settled 2026-08-04, a single integer starting at
      one, bumped only on a breaking change.
- [x] Scaffold, `units.sh` and `cases/` driving `hs -c`, covering `match.lua` first. Landed
      2026-08-05 in `10d1629`, built by a Sonnet agent from
      `docs/superpowers/packets/2026-08-04-packet-units-scaffold.md`, one rework round on style,
      gate rerun by the architect.
- [x] Scaffold, `inventory.sh` plus the committed `inventory.golden`, reading this config's own
      registries and not Hammerspoon's. Landed 2026-08-05 in `2047b36`, built by a Sonnet agent
      from `docs/superpowers/packets/2026-08-04-packet-inventory-scaffold.md`, one rework round on
      style, gate rerun by the architect. One finding for the record, the design's registry
      counts were node counts, the golden counts entries, verified equivalent by a live probe.
- [x] Full rescan of the design's older citations. Done 2026-08-04 against `6bd5b8d`, about two
      thirds had drifted and all were corrected. The material finding is the paste block, roughly
      doubled to about 610 lines and no longer a clean tail of `monitor.lua`, so the phase 3
      packet must draw the primitive versus entry knowledge line rather than cut at a line number.

## Phase 1, storage into core

The smallest core that does real work. Design section, storage roots.

- [x] Rescan the storage sites named in the design's files list. Done 2026-08-05 against
      `f72ea93`, all five citations hold at their exact lines, `manager.configure` still accepts
      every path override, no drift.
- [x] Packet, `Olm.spoon/init.lua` plus `lib/storage.lua`, the `paths` block in
      `config/settings.lua`, roots resolved and injected from the root. Written 2026-08-05 at
      `docs/superpowers/packets/2026-08-05-packet-storage-core.md`, and it also owns the golden
      regeneration, since loading the new spoon adds exactly one `spoon Olm` line.
- [ ] Build, QA, rework until the gate holds.
- [ ] Gate, path building covered in the unit runner as it is written, and the reconciler clean.
- [ ] Live test through the toggle.
- [ ] Land.

## Phase 2, recency into core, the proof

If this deletes less than it adds, the core idea is wrong and the plan stops here. That outcome is
a finding, not a failure of the phase.

- [ ] Rescan the five callers, the set may have changed.
- [ ] Packet, `lib/recency.lua` and the five callers converted in their olm side copies.
- [ ] Build, QA, rework.
- [ ] Gate, unit tests for the ordering, plus a recorded line count before and after.
- [ ] Decision point, count deleted more than added, continue. Otherwise stop and take the finding
      back to the design.
- [ ] Live test, land.

## Phase 3, paste into core

The riskiest extraction, measured timing rather than obvious behaviour. After recency proves the
pattern, never before.

- [ ] Rescan `monitor.lua`, the clipboard work is the part of the tree moving most.
- [ ] Packet, `lib/paste.lua` from the insertion primitives, three consumers pointed at it. Opus
      builds this one.
- [ ] Adversarial review, an Opus agent packeted to refute the claim that timing and behaviour are
      unchanged, before the architect's own pass.
- [ ] Build, QA, rework.
- [ ] Gate, the live tier only. Paste into a terminal, a browser field, and an Electron app, and
      run the sequential walk to the end of a full history, before the diff is committed.
- [ ] Live test, land.

## Phase 4, the dependency kind

- [ ] Packet, the new kind in `src/check-dependencies.sh` and the map.
- [ ] Build, QA, rework.
- [ ] Gate, the reconciler clean, including one deliberate violation refused readably.
- [ ] Land.

## Phase 5, the remaining atoms into core

- [ ] Rescan the five atoms.
- [ ] Packet, one pass, copies under `Olm.spoon`, originals untouched, toggle in `init.lua`.
- [ ] Build, QA, rework.
- [ ] Gate, an empty inventory diff across the toggle flip.
- [ ] Live test, land.

## Phase 6, the bundling pass

The hard to reverse step, so it is a branch that lands whole or is thrown away whole. Copies, not
moves, per the read only law, and the design records the honest cost, a fix landing in an original
while its copy exists is carried across by hand, so this window stays short per tool.

- [ ] Rescan the roster, the spoon count and names may have moved since thirty four.
- [ ] Packet per batch of plugins, copied under `Spoons/Olm.spoon/plugins/`, each keeping its own
      directory, `CLAUDE.md`, and declarations.
- [ ] Packet, the `dependencies-collect` owner fix, the one real break the design found.
- [ ] Build, QA, rework, in batches small enough to review honestly, Sonnet per batch in parallel
      worktrees.
- [ ] Adversarial review, an Opus agent packeted to refute the no behaviour change claim across
      the whole branch, before the soak.
- [ ] Gate, an empty inventory diff across the toggle flip, this is the step the snapshot was
      built for.
- [ ] Live test across several days of normal use before landing, this step earns the soak.
- [ ] Land whole, or discard whole.

## Phase 7, the plugin contract

- [ ] Packet, dispatch by plugin name, the registration door, the api version check, the
      activation list read.
- [ ] Build, QA, rework.
- [ ] Gate, an empty inventory diff, plus two deliberate failures refused readably, an activation
      list naming a plugin that is not there, and a plugin declaring an api version too old.
- [ ] Live test, land.

## Phase 8, the action panel

- [ ] Rescan `hyperContexts` and the binding declarations.
- [ ] Packet, the panel as a consumer of the binding declarations, in place swap through the
      existing hooks, chord from phase 0, kind stamped on shared navigation rows.
- [ ] Build, QA, rework.
- [ ] Gate, three choosers with different verb sets, file search, the clipboard, and one with no
      verbs showing only Back, plus a hosted file search list offering reveal and copy path.
- [ ] Live test, land.

## Phase 9, snippets, the first plugin born inside olm

The real test of the contract, everything before it was adapted to fit.

- [ ] Packet, store, surface, git versioning module, `DEPENDENCIES` beside it, one file per
      snippet.
- [ ] Build, QA, rework.
- [ ] Gate, the contract needed no special case for it. A special case is a contract finding, not
      a snippets finding.
- [ ] Live test, land.
- [ ] Afterwards, the query scope for snippets, an hour or two, file search is the worked example.

## Phase 10, sweeps and the tail

- [ ] READMEs, every plugin gets its short gist, none repeating its `CLAUDE.md`.
- [ ] Named values, placement first, the rest as modules are touched.
- [ ] Apps as a plugin, last of the extractions, it owns the watcher and the shared timeline.
- [ ] Interaction grammar written into `Olm.spoon`'s `CLAUDE.md`, and the two rules that bind the
      whole tree into the module level `CLAUDE.md`.

## Phase 11, retirement, only ever by name

Nothing here happens on a schedule. The user names a tool whose olm side has earned trust, and only
then does its original go.

- [ ] Per tool, on the user's word, remove the original spoon and the commented wiring.
- [ ] Gate per tool, the inventory diff against the golden stays empty after the removal.
- [ ] Last of all, the old load block leaves `init.lua`.

## Deferred, deliberately outside this plan

The plugin roster surface waits until olm ships to someone. Text expansion and snippet placeholders
stay out per the design. The pathwatcher removal is its own decision and is not bundled in.
