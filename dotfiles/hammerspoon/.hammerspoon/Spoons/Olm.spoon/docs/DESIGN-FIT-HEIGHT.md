# A list as tall as its rows

A design note agreed with Milos on 2026-11-15, before step 3.3 of `docs/PLAN-STANDALONE.md`, which
needed Keep Awake's one row in Olm.app. Until then a plugin set its list's height, `rowCount`, a
number or a member answering one, and the stage applied it by hiding the window, rebuilding it at
that height and showing it again, which blinked. Keep Awake and Volume asked for one row, and Input
Sources for one row per source.

## The rule

A list's height is never a plugin's to set. Every list is the chooser's own height. A list may
declare `fit = true`, a real boolean, and is then as tall as its rows:
- at least one row
- never past the chooser's own height, past which it scrolls and wraps, as every list already does

There are no numbers, so a plugin can ask to be shorter and never for a size. `rowCount` is refused
by name, and so is `fit` beside a preview pane, whose height is the list's and would change with
every key. Keep Awake, Volume and Input Sources declare it.

## How it moves

- **One rule, in geometry.** `geometry.resolve` takes `fitRows`, the rows drawn, a status row
  counted. Below what the screen holds, the window is that many rows tall with no peek. Otherwise it
  is the full height. The top edge is the full height's either way, so the field stays where it is
  and only the bottom edge moves. Olm.app's port, `OlmLook/Geometry.swift`, takes the same input,
  and `test/fixtures/chooser/geometry.json` pins both.
- **Placed again only when the count changes.** The engine compares the count after every rebuild
  of the list and places again only on a difference, so a keystroke that keeps the count costs
  nothing. The height follows rows that have landed, never the keystroke itself.
- **The right height at once.** A place made before the window shows lays it out with nothing
  moving:
  - The Lua chooser builds its rows before it shows, so it places once, at their count.
  - Olm.app holds the window until its first rows land, places there, and remembers each list's
    count for a list whose rows come after the reveal's cap.
- **Animated while it is up, snappy.** The native panel steps the window's real frame, the reshape
  a preview pane's arrival already takes, accepted on 2026-11-06, about 2 ms a step.
  - A height alone plays on the kit's `fitCurve`, which eases out only. The edge moves the moment
    the rows land, and a change turned mid way runs on rather than starting from rest.
  - Its length is `reshape` in `config/settings.lua`.
  - The rows are the new ones at once. The list is laid out once at the taller shape, the bottom
    edge covers or uncovers rows, and the bar and the fade under the list move with the edge.
  - Going into a list, back out of one and typing in one are the same change. Keys, Escape and
    Return are heard through it.
- **The canvas chooser** cannot animate, so it resizes in one step, with no hide.
- **The list's reload is guarded.** It reloads only when the row height, the insets or the style
  changed, so a reshape redraws no row.

## Turned down

- **A min and a max per plugin**, proposed by Milos and talked through on 2026-11-15. For every
  list that fits, the two would be its row count and the chooser's own height, so the numbers add
  nothing and are exactly the lever that lets a plugin force a size.
- **Measuring once at the open and holding it.** It is calmer, but a list's rows changing as it is
  typed in would leave a gap or a scroll. Milos chose that the height follows the rows throughout.
- **A mask over the glass, a drawn shadow, AppKit's animated resize.** All were tried for the width
  reshape and turned down, `decisions/olm-swift-chooser.md`.
