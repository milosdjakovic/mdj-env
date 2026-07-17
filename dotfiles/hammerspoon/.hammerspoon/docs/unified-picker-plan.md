# Unified webview picker plan

## Revision, keep both backends behind a provider seam

The original goal was to retire `hs.chooser` outright. That changed. The native
chooser stays as a swappable backend rather than being deleted, so styling can be
compared side by side and a regression is one setting away from reverting. The
`Chooser` spoon is now a facade over two providers, `native` wrapping
`hs.chooser` (the original atom, moved to `providers/native.lua`) and `web` built
on the `Surface` spoon. Every consumer calls the same `Chooser.new(config)`, and
`settings.chooserProvider` picks the default for all of them at once, while a
single instance can override with `config.provider` during a one at a time
migration. This is the Strategy pattern behind a provider seam, the same shape
the other spoons use. The sections below still describe the webview foundation,
which is now the `web` backend rather than a replacement.

## Goal

Paint every picker surface through one webview foundation, so styling is
cohesive and a single edit restyles them all, offered as the `web` backend
alongside the retained `native` one.
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

Status. The clipboard split is built on the web backend. The searchable list now
carries an optional preview pane on the right of the same window, off when
`layout.previewWidth` is zero and on when it is positive, drawn by the page and
themed from the same palette so it matches the list. The list gained `hasPreview`
and `setPreview`, plus right click on a row and a highlight preserving refresh, so
it holds the full clipboard contract. The clipboard `ui.lua` asks the picker once
whether it embeds a preview. On the web backend it pushes preview fragments into
the pane, on the native backend it keeps docking its companion window, so both
backends work and swapping stays one setting. Both paths were verified live with
no errors on the same clipboard code. Still to do below, migrate the VPN locations
and the command palette, and wire the palette icons through the disk cache.

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

Status. The cheat sheet grids now draw through the Surface. A new passive grid
surface type hosts a block of positioned HTML inside the same frosted panel the
lists use, themed from the same palette, so the overlays and the pickers share one
background. WebKit keeps a
`backdrop-filter` alive only while the webview is the key window with a real text
field focused, so a standalone sheet activates and focuses a hidden sink to hold
its frosted panel, the same trick the Panel uses. Without it the blur drops about a
second after the sheet appears, and a screen recording drops it at once, both by
pulling key status away.

The context peek over an open picker was dropped. Two overlapping frosted webviews
of one app cannot both be the key window, so a peek shown over a picker either
went transparent itself (passive) or made the picker behind it go transparent
(activating). Instead each searchable list carries a persistent footer bar inside
its own window, drawn from the same `hyperContexts` bindings through `footerFor` in
the composition root, so the shortcuts are always visible under the surface and one
window hosts both, nothing competing for the backdrop. A single reveal deferral
was also added so switching between the Hyper and window leader sheets no longer
flashes the previous sheet's still painted content, the shared grid webview waits
for the new page to report ready before it shows. `CheatSheet.spoon` kept its whole model contract, its geometry
math, and `glyphFor`, and only swapped the drawing primitive from canvas elements
to absolutely positioned divs, so `HyperCheatSheet`, `WindowCheatSheet`, and the
context overlays were not touched. The background now comes from `chooserTheme`
through the grid, and the `cheatSheet` settings block still tunes the content, font
size, padding, and badge radius. Verified live on all three, the Hyper sheet, the
window leader sheet, and the content sized badge peek.

Still open. Fold the fixed list `Panel` behavior onto the same Surface so caffeinate
and the VPN panel share one base, the last renderer still on its own. Lowest
payoff, do only if the cohesion is wanted end to end.

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
