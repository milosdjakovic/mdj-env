# Unified webview picker plan

## Goal

Retire the native `hs.chooser` and paint every picker surface through one
webview foundation, so styling is cohesive and a single edit restyles them all.
Today three renderers draw the overlays, `hs.canvas` for the cheat sheets,
`hs.webview` for the panels, and native `hs.chooser` for the searchable lists,
and the native chooser is the one that cannot match a webview's corners, blur,
padding, row layout, or font, which is the whole reason `Chooser.spoon` is full
of workarounds. The theme is already unified as data in `settings.chooserTheme`,
and every consumer already speaks one contract, `isShowing`, `selectNext`,
`selectPrev`, `insertSelected`, `hide`, plus `show` and `refresh`, routed
through `choosers` and `routeNav` in `init.lua`. So the data and the seam are
already in place, only the painting is split.

## Design shape

The reusable mechanism is a themed webview **Surface**, the engine, owning the
invariant scaffolding, geometry, focus, the frosted backdrop, click away
dismissal, previous window restore, the message bridge, and the theme. `Panel`
already is roughly 80 percent of this, so the Surface is a generalization of it
rather than a new idea. On top of the Surface sit the concrete surface types,
each filling in its own row model and interaction policy, which is the injected
Strategy the config already uses everywhere.

- Fixed list, the current `Panel` behavior, used by caffeinate and the VPN panel.
- Searchable list, the new custom chooser that replaces `hs.chooser`, used by the
  clipboard, the VPN locations, and the command palette.
- Split, the clipboard, a searchable list on the right and the preview on the
  left inside one webview.
- Grid, the cheat sheet. Left on `hs.canvas` for now, since canvas is fast for
  the small grids and moving it buys the least.

The user facing atoms are presets composed on this base. One going into another
is composition, a search bar over a list, a split placing a list beside a
preview. Consumers keep injecting content and callbacks exactly as now, and the
stable contract stays the seam so the composition root and the Hyper context
wiring barely change.

## Performance decisions baked in from the start

Leaving the native control means losing native cell reuse and direct
`hs.image` rows, so two mechanisms are part of the foundation, not bolted on.

### Row virtualization

A webview has no cell reuse, and the clipboard store caps at 1000 entries while
the app list runs to a few hundred, so the page never renders the whole list.
It renders only the visible window plus a small buffer and recycles rows as the
list scrolls, keeping the highlighted row in view as j and k move. This bounds
both the DOM size and, crucially, the number of images encoded at any moment to
what is on screen, so a full clipboard and the whole app list collapse to the
same small cost.

### Disk backed icon cache, reconciled against the directory

A webview cannot take an `hs.image`, it needs a file it can load, and encoding
PNGs is synchronous on the main thread, so the cost is paid once and persisted.
Each app icon is written to a PNG named by bundle id in a dedicated cache
folder, and rows load it by path rather than building base64 in memory. The
cache survives reloads, so a warm machine pays nothing.

The cache directory is its own manifest. The live scan of the app directories is
the current truth. Reconcile is the diff of the two sets. Bundle ids in the scan
but not in the folder are new and get encoded, files in the folder whose bundle
id is not in the scan are stale and get deleted. No companion manifest file,
since the files themselves are the record and cannot drift out of sync. A
metadata file is added later only if update detection is wanted, an app changing
its icon without changing its bundle id, in which case an `hs.json` map keyed by
bundle id carrying the name and a version stamp catches it and also skips
re-reading `infoForBundlePath`. Not in scope for phase one.

Encoding runs chunked over an `hs.timer`, a few per tick, so the reconcile on
load never blocks, which also warms the common icons before the first open.
Icons are additionally encoded lazily for any visible row not yet cached, so a
newly installed app shows even before the warmer reaches it.

The command palette action rows are out of this entirely. They are a small fixed
list already in `config/keys.lua` with glyph drawn icons cached in memory, so
there is nothing to scan or persist, and applying the app machinery to them
would be ceremony with no second consumer.

## What the switch deletes

The migration is not all cost. The clipboard runs a timer polling the chooser's
selected row every 80 milliseconds only because `hs.chooser` has no highlight
callback, and a webview posts a highlight message the instant it changes, so
that poll loop is removed. Folding the preview into the same webview retires the
second window, the seed height guessing, `_settleFrames`, and
`matchPreviewToChooser`, all of which exist only to keep two windows aligned. So
the clipboard ends up lighter at rest than it is now.

## Phases

### Phase 1, the foundation

Build the Surface engine as a generalization of `Panel`, and the searchable list
type on top of it, with search input and live filter, numbered rows, optional
left icon, subtitle below, Cmd plus 1 through 9 quick select, scroll into view,
row virtualization, and the disk backed icon cache with directory reconcile and
chunked warming. Expose the existing stable contract, `show`, `hide`,
`isShowing`, `refresh`, `selectNext`, `selectPrev`, `insertSelected`, plus
`query`, `selectedItem`, `setFieldMode`, `setPlaceholder`, and `activeTheme`, so
consumers are near drop in. This is roughly 60 percent of the effort.

Riskiest single behavior, focus and paste. The native chooser restores focus to
the previous app for free, which is what makes the clipboard paste land. A
webview that holds key focus for its search field means the Surface owns that
restore, focus the previous window then paste, which is what `Panel` already
does with `prevWindow:focus()` on close. Get this right here so every consumer
inherits it.

### Phase 2, migrate the searchable consumers

Repoint the three `hs.chooser` consumers at the new atom. The command palette and
the VPN locations picker are near drop in, since they already hand plain row
tables to a supplier and speak the contract. The clipboard is the big one,
because of the split pane and the paste focus, so do it last of the three and
lean on the split being a simplification rather than new complexity.

Order, VPN locations first as the smallest real consumer, then the clipboard as
the highest value, then the command palette. The command palette is the worst
performance case, all distinct app icons, and is a transient launcher rather
than a lingering panel, so it is the one that could stay on the native chooser
longest if scope needs trimming. Decide once the base atom has been felt under
load.

### Phase 3, optional total cohesion

Fold the fixed list `Panel` behavior onto the same Surface so caffeinate and the
VPN panel share one base, and consider moving the cheat sheet grid off canvas
onto the Surface. Lowest payoff, do only if the cohesion is wanted end to end.

## Out of scope

The composition root structure, the contracts, the predicates, the Hyper context
wiring, and the theme data all keep their shape. The cheat sheet stays on canvas
through phase one and two. No companion manifest file in phase one.

## Files touched, expected

- New or generalized, the Surface engine, likely `Panel.spoon` generalized or a
  sibling `Surface.spoon`, plus the searchable list type and the icon cache.
- `Chooser.spoon` retired once its three consumers move.
- `init.lua`, repoint the command palette build and the injected factories.
- `Vpn.spoon`, point the locations picker at the new atom.
- `ClipboardHistory.spoon/manager/ui.lua`, move to the split surface and drop the
  preview window, the poll, and the frame settling.
- `config/settings.lua`, no shape change, possibly new tokens for the unified
  row style.
