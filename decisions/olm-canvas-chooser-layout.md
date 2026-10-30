# Olm canvas chooser, a layout clone of the swift chooser

Status. In progress on the canvas-glass-layout branch. The canvas chooser shares swift's rects and spans its pane as one surface, and the floating bar groups and the popovers are still to come.

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

Still to do. The bar as two floating groups, keys on the left and actions on the right, with the
list running on under them, then the key panel and the action panel as popovers above their
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

## Log

### 2026-10-30 19:47

The canvas field's caret measure goes through the kit's cached `exact`, see
`decisions/olm-chooser-performance.md`. The first step of the clone, done alone.

### 2026-10-30 19:53

The canvas view answers `spansFooter` and `footerHeight`, spans its pane as one surface with the
divider, and hosts the pane's content. Commit bb69fbc9 on main had given every spanning view a
zero gap the same evening, so the canvas view took it with no change of its own. The dry suite
passes, with new cases in `test/panebackends.lua` for the hosting backend. Not yet seen live.
