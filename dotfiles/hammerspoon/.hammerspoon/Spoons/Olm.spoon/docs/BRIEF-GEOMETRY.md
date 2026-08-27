# Geometry brief, phase 4 of the chooser stage track, 2026-08-27

Orchestrator decisions from PROBE-FINDINGS-2026-08-27.md section C and the consumer
map sections 7.3 and 9.11. This phase gives the stage live geometry so phase 5 can
migrate the pane consumers, filesearch, processes, clipboard, and the row count
consumer, caffeinate.

## Decisions

1. A presentation may declare paneWidth, a number in points or true to inherit the
   chooser width, absent means no pane, matching the atom's companionWidth semantics.
   On present and push the stage recomputes the pair geometry with the atom's own
   arithmetic, shifts the visible window by setTopLeft so the pair stays centered,
   the probe proved a live move is exact and the widget stays live, updates
   paneFrames so the click watcher keeps hit testing honestly, and refires
   onPositioned so the pane consumer draws or clears. A swap between two paneless
   presentations moves nothing.

2. The window's width never changes while visible, uniform 480 stands. Row count
   changes take the one resize path, hide, rows(n), show, roughly a hundred
   milliseconds, paid only when a presentation declares a rowCount different from
   the window's current one, which today is only caffeinate's two. This needs a
   small addition to the chooser atom, a public setRows the stage calls between
   hide and show, the probe proved rows applies on the next show of the same
   instance. This is the one permitted lib/chooser change of the phase, keep it a
   passthrough.

3. The anchor arithmetic the consumer map found triplicated in clipboard, filesearch,
   and processes, spanning the list and its pane for the hint panel anchor, moves
   into the stage as one function the pane consumers will call when they migrate.
   Do not touch the three plugins now, build the one true copy where phase 5 can
   reach it and leave the copies to die with their migrations.

4. Out of scope, the onHighlight row number hazard, rows engine work, any plugin
   migration, and any change to how the pane content is drawn, the stage owns where
   the pane sits, never what is in it.

## Acceptance

With no pane consumer migrated yet, the observable behavior of everything must be
unchanged, launcher and VPN swaps included, since neither declares a pane or a row
count. The geometry paths are proven by the stage's own dry checks and by one
scripted probe at the live gate that presents a synthetic paneWidth presentation and
verifies the window shifted and the frames report the pane rect. Console clean,
check-dependencies clean, dependencies-collect byte identical.
