# Olm canvas chooser, a layout clone of the swift chooser

Status. Merged into main on 2026-10-31 (63151f13). The canvas chooser shares swift's rects, spans its pane as one surface, draws the bar as swift's two floating groups and the info pane and the actions pane as floating panes above them, and serves as the fallback provider while swift is the shipped one.

## Now

The canvas chooser, the `default` provider, is a clone of the swift chooser's layout, the same
parts in the same places at the same sizes, while it keeps its own theming, solid fills in the
kit's colour roles rather than glass. The swift chooser itself was not touched. Swift is the
shipped provider in `config/settings.lua`, and the canvas chooser draws every chooser until swift's
first build is done and whenever swift cannot build or load. The work was merged into main on
2026-10-31 in 63151f13, and the parts were renamed by `decisions/olm-names.md` on 2026-11-02.

The canvas view answers `spansBottomBar` and `bottomBarHeight` exactly as the swift view does, so
the engine hands both the same rects, the bar across the canvas, the gap and the pane, the pane
stopping at the bar's top edge, and no gap beside the pane. Its surface spans the canvas, the gap
and the pane as one rounded shape with a hairline of the border role between list and pane. A
preview pane draws inside that surface through the provider's `paneBackend`, which the root wraps
around the plain canvas backend whenever the native pane is not used. `Olm.spoon/AGENTS.md`, under
the preview pane, has how it matches a pane to its chooser.

The bar is swift's two floating groups, drawn by `lib/chooser/providers/default/bar.lua` from the
same tokens swift's view hands Swift, each filled with the background role and outlined in the
border role, and the list runs on behind them to the window's bottom edge, drawn from a copy of the
engine's list state with its `padEnd` grown by the bar's height. The divider runs the full height
under the bar. `Olm.spoon/AGENTS.md`, under the bottom bar, has the measurements and how a press
and a hover are answered.

The info pane and the actions pane are floating panes, `providers/default/floatingpane.lua`, one
drawing routine for both cloned from swift's `native/FloatingPane.swift`, each standing above its
group's rect, which `bar.lua` answers, and the view answers `floatsActionsPane`, so the actions pane
has no Back row and the list keeps the rows it showed. A point on a group or a floating pane is on
no row, and a scroll over either moves no list. `bottombar.lua` keeps the bar's height, which the
engine, the swift view, `bar.lua` and `floatingpane.lua` all read, and the key caps both draw.

## Rejected

- **2026-10-30, a solid surface option on the swift chooser.** All of this work goes into the
  canvas chooser, and swift keeps its glass, which is why it was chosen.
- **2026-10-30, porting the native scroll work to the canvas chooser.** It is drawn by Lua into
  `hs.canvas` with a 60 Hz ease, and the clone is about layout and parts, not scroll smoothness.
- **2026-10-30, leaving the pane in its own window behind a spanning chooser.** The chooser's
  canvas stands at the popUpMenu level and a pane's at floating, so the spanning surface covers
  the pane, and raising the pane above it would cover the bar's actions group, which floats over
  the pane's bottom edge. The pane's content is drawn inside the chooser's canvas instead, the way
  the swift library hosts its pane in the chooser's window.

- **2026-10-30, growing the list model's viewport for the rows behind the bar.** Raising
  `visibleCount` or the list rect's height would have shown the rows, but list model bounds the
  scroll and keeps the highlight in view by `visibleCount`, so the furthest scroll would have
  stopped a bar's height short and the arrows would have left the highlight behind the bar. swift
  grows its viewport and its bottom content inset by the same height, which leaves both where they
  were, and the canvas equivalent is a drawing copy whose `padEnd` alone grows, which list model
  reads only for the rows it answers as visible.
- **2026-10-30, the key glyphs as hint badges in the canvas groups.** The canvas row drew each chord
  as a badge on the highlight, and swift's groups draw the chord as plain body text beside the
  label. A badge inside a group puts a filled chip inside a filled shape and makes the group taller
  than swift's, so the canvas groups take swift's body text.
- **2026-10-30, a press anywhere else in the chooser closing an open popover.** Asked for in the
  brief, but the swift chooser does not do it. Its popover claims presses on itself, its list
  ignores presses while the action panel is open, and nothing closes either popover but Escape,
  the key button and the panel's own chord, so the clone does the same.
- **2026-10-30, routing the arrows and Return to the action panel in the view.** The swift view
  only stops its native list from taking the arrows while the panel is open, so they reach the
  engine, whose rows are the panel's. The canvas field already hands every key to the engine, so
  there is nothing to route.

## Log

### 2026-10-30 19:47

The canvas field's caret measure goes through the kit's cached `exact`, see
`decisions/olm-chooser-performance.md`. The first step of the clone, done alone.

### 2026-10-30 19:53

The canvas view answers `spansFooter` and `footerHeight`, spans its pane as one surface with the
divider, and hosts the pane's content. Commit bb69fbc9 on main had given every spanning view a
zero gap the same evening, so the canvas view took it with no change of its own. The dry suite
passes, with new cases in `test/panebackends.lua` for the hosting backend. Not yet seen live.

### 2026-10-30 20:02

The bar is two floating groups. `bar.lua` lays out the keys group and the actions group by swift's
own numbers, `pad`, `inner`, `space.s`, `space.l`, `footer.lua`'s height and the hint icon size, in
the background role outlined at `stroke.border`, and `canvas.lua` draws the rows on behind them,
answers a press on an action entry through `footerAction` and lets a press or a scroll between the
groups reach the row behind. `footer.lua` lost its row and keeps the height and the key panel. The
dry suite passes, with `test/canvasbar.lua` new, and `test/swiftview.lua` gains the zero gap that
bb69fbc9 gave a spanning view and left the test still asserting a gap for. Not yet seen live.

### 2026-10-30 20:06

The key panel and the action panel are popovers in the canvas chooser, `popover.lua` beside the
view and `View:_barAnchors` as the seam the bar work feeds, and the view answers
`floatsActionPanel`. The old key panel over the bottom rows is no longer drawn. A popover's
heading is the caption role, as swift's popover draws it, and its corner is the highlighted row's,
the radius swift hands its popover. `test/swiftview.lua` still asserted the gap beside the pane
that commit bb69fbc9 took away, so the dry suite failed on main and here, and the case now pins a
zero gap. The dry suite passes with `test/canvaspopover.lua` added to it. Not yet seen live.

### 2026-10-30 20:09

The two branches merged into canvas-glass-layout. The popovers' placeholder anchors went, and the
bar's own group rects are the anchors now, the keys group's for the key panel and the actions
group's for the action panel. A point on a group or a popover is on no row, a scroll over either
moves no list, and the rows held behind a floating action panel scroll through the same span the
rows run on behind the bar. `footer.lua`'s key panel, unused since the popovers, was removed.

### 2026-11-16 15:59

Status and Now were out of date. They said the work was in progress on the canvas-glass-layout
branch and not yet seen live, and they named `popover.lua`, `footer.lua`, the key panel, the action
panel, `spansFooter`, `footerHeight` and `floatsActionPanel`. The branch was merged into main on
2026-10-31 in 63151f13, the files are `floatingpane.lua` and `bottombar.lua` since the rename of
2026-11-02, and the view answers `spansBottomBar`, `bottomBarHeight` and `floatsActionsPane`. Now
also called the canvas chooser the default provider, which it is only by name, since
`config/settings.lua` ships swift and the canvas chooser is its fallback. Whether it was seen live
beside the swift chooser is not recorded here, so Now no longer says either way. Found by an audit
against the repo on 2026-11-16.
