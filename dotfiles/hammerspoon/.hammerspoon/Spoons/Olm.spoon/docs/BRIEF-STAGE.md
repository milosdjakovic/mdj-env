# Stage design brief, 2026-08-27

The phase 1 output of docs/PLAN-CHOOSER-STAGE.md. Decisions here were made by the
orchestrator from docs/PROBE-FINDINGS-2026-08-27.md and docs/CONSUMER-MAP-2026-08-27.md,
and a builder follows them rather than relitigating them. Where this brief and the code
disagree, stop and report rather than improvising.

## What the stage is

One host unit, host/stage, owning the single live chooser instance every tool presents
into. A presentation is a plain table of policy, and the stage is the engine that shows
whichever presentation is current. Presentations stack, present pushes, backspace on an
empty field pops, hide clears. The shape is Strategy for the presentations over one
engine, and Chain of Responsibility for the intercept and back hooks, panel first, then
the presentation, then the stack. The composition root wires all of it, nothing else
names concretions.

## Decisions, each carrying its evidence

1. One instance, built once, never rebuilt. Probe A, construction plus first show is
   90 to 160 ms, a choices swap into a visible window is 5 ms, a reshow of a kept
   instance is 60 to 90 ms. So a handoff while visible is a swap, an open from cold is
   a reshow, and teardown never happens between tools.

2. present resets the highlight to row one, since the list means something new. The
   probe confirmed a swap resets the highlight anyway and that restoring works, so
   preservation stays possible for later quiet corrections, but present itself resets.

3. Field mode is a constant, filter. Surprise 9.3, the other modes and setFieldMode
   have zero consumers. The presentation contract does not carry a field mode. The
   dead modes are left in the atom untouched for now, their removal is close out work.

4. Layout is a constant, the atom defaults, width 480, ten rows. Surprise 9.4 through
   9.6, nobody overrides width, only Caffeinate changes row count, the clipboard's
   layout block is eight restated defaults plus one pane width. A presentation MAY
   declare rowCount, and when it differs from the window's current one the stage takes
   the one resize path that exists, hide, rows(n), show, which the probe proved applies
   on the next show of the same instance. That blink is rare and only Caffeinate pays
   it. The same path serves a future width change, per the probe width() also applies
   on a plain hide and show.

5. The ActionPanel decorator stays exactly where it is and the stage sits under it.
   Surprise 9.8, the decorator already wraps intercept and back on every instance by
   mutating config in place, legally, because the atom reads config live. The stage
   passes its own intercept and back in the config it hands to Chooser.new, the
   decorator wraps them once at construction, and at runtime the panel answers when it
   is open and falls through otherwise. Under that, the stage routes to the current
   presentation's own intercept or back first, and when the presentation declines a
   back, the stage pops the stack. The stage never touches the decorator and never
   rewires config after construction.

6. Stack semantics. present(p) shows p and pushes it. pop() returns to the presentation
   below, restoring its placeholder with an empty query and the highlight at row one,
   answering false when the stack is at one, in which case backspace stays an ordinary
   press exactly as today. hide() clears the whole stack. A tool opened by its own
   hotkey presents over an empty stack, so backspace there has nothing to pop and the
   launcher does not appear uninvited. Opening the launcher presents it as the bottom
   of a fresh stack.

7. The world capture. The stage records openId and the frontmost app once per stack,
   at the first present over a hidden window, guarded against recording Hammerspoon
   itself the way the launcher's own capture is at host/launcher/init.lua:1008. It
   exposes world() returning the pair. In this phase the launcher keeps its own
   capture untouched, unification is phase 3 work, but the stage's capture exists from
   day one so phase 3 deletes rather than invents.

8. Out of scope, named so nobody drifts into them. The overlay display picker stays
   its own window, it has no manifest to declare a presentation in, and its dead panel
   and nav wiring, surprise 9.2, is a live defect to fix separately. BrowserTabs and
   DisplayProfiles keep their private Return taps and inner stacks until their own
   migration steps, surprise 9.9. The registry's unused surfaces resolver, surprise
   9.10, is close out work. The row number highlight hazard and the triplicated anchor
   arithmetic, surprises 9.11 and 9.12, are absorbed when the stage grows geometry and
   a rows engine, not now.

## The presentation contract, version one

A presentation is pure data plus closures, serialisable nowhere, held only by the
stage. Fields, all optional except name, rows, and onSelect.

    name          the context name, matching the manifest surface context of the tool
    placeholder   the field placeholder while this presentation is current
    rows          function(query) returning the row tables the atom already takes
    onSelect      function(item) run when a row completes
    onPresent     function() told when this presentation becomes current, through present
                  or push, never through pop, added in the handoff phase for a tool whose
                  rows depend on something async nothing else has necessarily warmed
    intercept     function(item) answering true when the row swapped the list in place
    back          function() answering true when an inner level was popped
    onHighlight   function(item) for a companion consumer, nil for none
    onScroll      function(points) a trackpad or a wheel scrolled over the companion rect,
                  nil for none, found during the trickle migrations rather than named by
                  this brief, filesearch and clipboard both already wiring one directly,
                  routed the identical way onHighlight is
    onRightClick  function(item, row) a canvas row right clicked, nil for none, found
                  alongside onScroll, clipboard's own retired Chooser.new call being the
                  only consumer anywhere
    onPositioned  function(chooserFrame, companionFrame) told whenever the stage repositions
                  the pair for this presentation, companionFrame nil when paneWidth is
                  absent, added in the geometry phase for a pane consumer to draw or clear.
                  Also told with both frames nil, once, when present, push, or pop makes a
                  different presentation current, so a pane this one drew clears rather than
                  sitting beside a window that already moved past it, adversarial review
                  finding H2
    onClose       function() told when the stage hides entirely, not on a swap. Widened in
                  the handoff phase for a stack deeper than one, every discarded level is
                  told, top down, except the one that survives a reopen at any depth
    rowCount      a number when the tool genuinely differs from ten, else absent
    paneWidth     a number in points, true to inherit the chooser's own width, or a member
                  spec resolved once at register the same way placeholder is, for a plugin
                  whose own reservation depends on state only its own wiring settles, added
                  to the rework following the trickle migrations, review finding M1, since a
                  plain true papered over a viewer or a surface that resolved to no pane at
                  all. Absent means no pane, added in the geometry phase, matching the atom's
                  own companionWidth semantics
    matcher       false, meaning the supplier owns filtering, or a string naming a strategy
                  in Chooser.matchers, absent inherits the root default, added in contract
                  v2 for the three trickle plugins that each declare their own matching
                  policy today, written onto the live instance before every show and swap
                  the same way paneWidth already is
    titleLineBreak a string naming where a title too long for its row loses characters,
                  "truncateMiddle" for filesearch's own filenames, absent everywhere else,
                  restored in the rework following the trickle migrations after the first
                  pass silently dropped it, the one layout field with no other seat on this
                  contract, written onto the live instance the identical live way matcher is
                  rather than resolved once at construction
    enter         function(proceed) called instead of showing immediately, when a tool must
                  gather something before its first row means anything, added in contract v2
                  for Processes' own documented rule that its picker never appears before its
                  scan lands. proceed is a function of no arguments the presentation calls
                  once it is ready, and the stage never learns what it was waiting for.
                  Answers true when it actually made the presentation current and false when
                  the stage's own generation guard found it stale, added in the rework
                  following the trickle migrations, review finding H4, so a caller with more
                  than one proceed in flight can tell which one, if any, was honoured

The stage owns everything else the thirteen call sites pass today, screen policy,
theme, panel callbacks, poll interval. A presentation cannot override them. matcher was one
of these in version one and stopped being one in contract v2, docs/BRIEF-CONTRACT-V2.md,
once three separate plugins resisted the fixed default on grounds that could not be papered
over, filesearch and clipboard ranking their own structured queries and disabling the atom's
matching outright, processes preferring word matching for digit and path heavy haystacks.

## The stage api

    stage.present(p)     show p, pushing it on the stack, swapping live when visible
    stage.pop()          back one presentation, false at the bottom
    stage.hide()         hide the window and clear the stack
    stage.refresh()      re run the current presentation's rows, keeping the highlight
    stage.isShowing()
    stage.current()      the current presentation's name, for predicates and hints
    stage.world()        the captured app and openId for this stack
    stage.surface        the one nav adapter, the five functions plus peekPreview
                         delegated to the current presentation when it answers one

## Phase 2, what to build now

Create host/stage with a manifest per docs/PLUGIN-CONTRACT.md. The stage builds the
one Chooser.new at configure with the config translation described above, and the
composition root wires it before the launcher.

Migrate the launcher onto it as the first presentation and change nothing else. The
launcher stops calling Chooser.new and stops owning an instance. Its existing rows
supplier, dispatcher, intercept routing, back to leavePage, placeholder, page
mechanism, recency, and seedQuery all stay in host/launcher and are handed to the
stage as one presentation table. The launcher's surface delegates to stage.surface.
Its show becomes stage.present of its presentation, its hide stage.hide, its refresh
stage.refresh. The _page mechanism is internal launcher state and does not become
stage stack levels, one tool is one presentation, the launcher's pages stay its own
business behind its intercept and back hooks, which is exactly what decision 5 makes
work.

Every plugin keeps its own window and its own wiring in this phase. The registry, the
deferral, and _runItem are untouched, that is phase 3. The stage having a stack of
depth one everywhere is correct and expected here.

## Acceptance for phase 2

The launcher behaves identically under a hand on the keyboard. Open on hyper space,
rows and recency and matching unchanged, typed aliases swap the list and deleting the
space steps out, hosted pages enter and leave on the same keys, the action panel
opens and its verbs run, j and k and the hint panel work, choosing an app row focuses
the app, choosing a tool row still opens that tool's own window after the deferral.
The console shows no new warnings on load. Nothing outside host/stage, host/launcher,
the manifest set, and the composition root changed. Work happens in a worktree under
../.worktrees/ per the repo convention, and no live test runs until Milos says start.

## What the builder must not do

Do not migrate any plugin. Do not touch lib/chooser or the ActionPanel. Do not add a
rows engine, caching, or geometry. Do not fix the overlay display defect in passing.
Do not rename anything the consumer map cites. Report any place where the launcher
resists the presentation shape rather than bending either side quietly.
