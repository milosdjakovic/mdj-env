# Chooser stage and menu search, plan of 2026-08-27

## Goal

Two tracks. Track one unifies how choosers open, hand off, and come back. One live
window owned by a new host unit, the stage, and every tool becomes a presentation
shown into it, so moving from the launcher to a plugin, deeper inside a plugin, and
back is a content swap with a presentation stack, never a close and open. The shape
is Strategy, presentations are interchangeable policy tables and the stage is the one
engine that runs whichever is current, wired at the composition root. Width stays
fixed at the uniform default, with one private stage path for the rare width change,
a hidden rebuild and reshow, so the capability exists without consumers knowing the
widget cannot resize live.

Track two makes menu search open instantly. A per app snapshot on disk drawn
immediately, a fresh accessibility read in the background, a quiet correction when
they differ, equal means no redraw at all, new rows append at the bottom, gone rows
dim in place, the correction defers while the user has moved the highlight. Recency
per app through lib/recency, pruned against each fresh read. All of it stays plugin
internal code, no lib extraction until a second slow source asks.

## Roles

The main session orchestrates, writes briefs, makes decisions, and verifies. Opus
subagents do research and adversarial review. Sonnet subagents implement from
briefs. Milos is architect and QA and says start before any live screen test.

## Checklist

Track one, unification.

- [x] 0a. Probe session on the live instance. Timings for chooser construct versus
      reshow and styled row building, getMenuItems timings per running app, live
      window behavior for choices swap, rows resize, setTopLeft move, width while
      visible, placeholder and field mode flips. Findings doc gates phases 3 and 6.
      Ran 2026-08-27, findings in docs/PROBE-FINDINGS-2026-08-27.md.
- [x] 0b. Consumer map. Every Chooser.new site with the config keys it uses, every
      surface adapter, panel callback shape, nav wiring, the launcher alias and
      scope mechanics, the registry open path, every deferred handoff site.
      Evidence doc with citations. Ran 2026-08-27, findings in
      docs/CONSUMER-MAP-2026-08-27.md.
- [ ] 1. Design brief for the stage and the presentation contract, written by the
      orchestrator from 0a and 0b. Decision points, stack semantics, back behavior,
      what the manifest declares, what the registrar automates.
- [x] 2. Implement host/stage with the launcher as the first presentation. Sonnet
      from the brief. Adversarial review by Opus, live test gate with Milos.
      Landed on main 2026-08-27, three commits merged at eaaba33, review in
      docs/REVIEW-STAGE-PHASE2.md, findings 4 and 12 inherited by phase 3.
- [ ] 3. Handoff becomes a swap. Registry opens a presentation declaring tool
      through stage.present, backspace on empty pops back to the launcher, hotkey
      opens present over an empty stack. Deferral survives only for dispatch into
      the outside world. Review and live test.
- [ ] 4. Live geometry. Reposition and pane show or hide on present, built from the
      settle mechanics, paneFrames kept honest for the click watcher. Row count per
      the 0a answer. Review and live test.
- [ ] 5. Menu search, promoted ahead of the other migrations on 2026-08-27 because
      the slow hyper e open was the original complaint and it does not need them.
      One step, the menusearch migration onto a presentation block plus the
      snapshot cache of BRIEF-MENUSEARCH-CACHE.md, one review, one live test on
      the heaviest app from the 0a timings.
- [ ] 6. The remaining migrations become trickle work rather than a scheduled
      phase, one plugin whenever convenient, each mechanical against the proven
      contract, old path and new path coexisting by design. BrowserTabs suite
      before its own step merges. Caffeinate exercises the row count path,
      filesearch and processes the pane path.

Close.

- [ ] 7. Retire dead surface plumbing, update docs/PLUGIN-CONTRACT.md, sweep
      reconciler warnings. Runs after the trickle finishes, whenever that is.

## Testing discipline

Probes run against the live instance through the hs CLI with dofile scripts, no
inline angle brackets, no config reload, no devlock. Live tests of changed config
follow the worktree and devlock rules in the hammerspoon CLAUDE.md, and the screen
is never driven until Milos says start.
