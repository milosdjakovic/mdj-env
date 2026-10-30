# Olm canvas chooser, a layout clone of the swift chooser

Status. In progress on the canvas-glass-layout branch. The canvas chooser shares swift's rects, spans its pane as one surface and draws the bar as swift's two floating groups, and the popovers are still to come.

## Now

The canvas chooser, the default provider, is being made a clone of the swift chooser's layout,
the same parts in the same places at the same sizes, while it keeps its own theming, solid fills
in the kit's colour roles rather than glass. The swift chooser itself is not touched.

Since 2026-10-30 the canvas view answers `spansFooter` and `footerHeight` exactly as the swift view
does, so the engine hands both the same rects, the bar across the canvas, the gap and the pane, the
pane stopping at the bar's top edge, and no gap beside the pane. Its surface spans the canvas, the
gap and the pane as one rounded shape with a hairline of the border role between list and pane.
A docked pane draws inside that surface through the provider's `paneBackend`, which the root wraps
around the plain canvas backend whenever the native pane is not used. `Olm.spoon/AGENTS.md`, under
the docked pane, has how it matches a pane to its chooser.

Since 2026-10-30 the bar is swift's two floating groups, drawn by
`lib/chooser/providers/default/bar.lua` from the same tokens swift's view hands Swift, each filled
with the background role and outlined in the border role, and the list runs on behind them to the
window's bottom edge, drawn from a copy of the engine's list state with its `padEnd` grown by the
bar's height. The divider runs the full height under the bar. `Olm.spoon/AGENTS.md`, under the
action bar, has the measurements and how a press and a hover are answered.

Still to do. The key panel and the action panel as popovers above their
groups, at which point the view answers `floatsActionPanel` too. Answering it before the popovers
exist would leave the action panel nowhere to draw.

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
