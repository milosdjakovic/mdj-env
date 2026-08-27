# Handoff brief, phase 3 of the chooser stage track, 2026-08-27

Decisions by the orchestrator on top of BRIEF-STAGE.md, PROBE-FINDINGS-2026-08-27.md,
CONSUMER-MAP-2026-08-27.md with its section 3 erratum, and REVIEW-STAGE-PHASE2.md
findings 4, 10, and 12. Phase 2 is merged, the stage is live with the launcher as its
only presentation. This phase makes moving between tools a content swap and proves it
with one migrated plugin.

## Decisions

1. Two doors into the stage, not one flag. stage.present(p) means a fresh stack, the
   hotkey door, replacing whatever stack exists even while visible, which closes review
   finding 4. stage.push(p) means stack on top of what is showing, the row selection
   door. present over a hidden window keeps its phase 2 meaning, fresh stack plus the
   world capture.

2. A presentation tool's launcher row completes through the intercept path, not
   through onSelect. The widget hardwires Return to dismiss, so the only way a row can
   become another list without a close and reopen is the intercept hook the launcher
   already routes through rowIntercept, exactly how alias scope rows work today. The
   root's rowIntercept answers a callable for such a row, and the callable calls
   stage.push with the tool's presentation. No hide, no deferral, one redraw.

3. The manifest declares it. A plugin that presents adds a presentation block naming
   module members for the contract fields of BRIEF-STAGE.md version one, rows, select,
   placeholder, and the optional ones it uses. The registrar resolves members to
   closures once at wire time, the same way registry.open resolves today, and the
   registry learns one new question, presentationFor(name), answering nil for an
   unmigrated tool. The launcher row build does not change, the root's rowIntercept
   asks the registry, so an unmigrated tool falls through to the old close, defer,
   open path untouched. Document the new block in PLUGIN-CONTRACT.md in this phase,
   the contract file must never lag a field that exists.

4. The deferral moves inside the dispatcher branches. The special branch runs a
   presenting tool synchronously through the intercept path above, and everything
   else, app, window, capture, settingsPane, calc, scope, and unmigrated special,
   keeps the 0.1 deferral after the close, since those genuinely act on the world once
   focus returns. Review 9.7 warned this splits _runItem, accepted, split it honestly.

5. Backspace on an empty field pops the stack, landing back on the launcher with an
   empty query and its placeholder, phase 2 pop already does this. The chain order is
   unchanged, panel first, then the current presentation's own back, then the pop. A
   presentation opened by hotkey sits on a stack of one, so its empty backspace pops
   nothing and stays an ordinary press.

6. onClose semantics widen for stacks, closing review finding 12. When the stage hides
   or a present replaces a live stack, every stacked presentation that declared
   onClose is told, top down. A push tells nobody and a pop tells only the one leaving.

7. Contexts and hints follow current(). The nav registry, the hint panel, and the
   action panel must treat the presented tool as the active context the moment
   push lands, and the launcher again the moment pop lands. Review finding 10 warned
   the two isShowing meanings diverge exactly here, resolve it the way the stage
   comment records, routing by stage.current() plus window visibility, and delete the
   warning comment once the routing exists.

8. VPN is the proving consumer, chosen from the consumer map as a standard shaped
   plugin, five function surface, recency, one async status refresh, no pane, no
   private eventtap. Its Chooser.new block, surface adapter, and redraw plumbing are
   deleted in favor of the manifest presentation block, its scope stays as is, and its
   async status lands through stage.refresh. Only VPN migrates in this phase, every
   other plugin keeps its own window and the old handoff, including both hosts of
   private stacks.

## Acceptance

Choosing the VPN row in the launcher swaps the list in place with no blink and no
0.1 second wait, backspace brings the launcher back, choosing a city connects exactly
as before, the VPN status refresh lands while its list is up, the hint panel shows
VPN's keys while VPN is presented and the launcher's again after pop, every
unmigrated tool opens its own window exactly as today, and app, window, capture, and
calc rows behave exactly as today. Console loads with no new lines. check-dependencies
clean, dependencies-collect byte identical for untouched modules, BrowserTabs suite
not required since its plugin is untouched.

## Out of scope

Geometry and panes, phase 4. Every plugin except VPN, phase 5. BrowserTabs and
DisplayProfiles private stacks. The overlay display picker and its known dead panel
defect. Menu search caching, track two. The dead field modes in the atom.
