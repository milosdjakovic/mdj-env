# The UI kit, one style and one set of drawing primitives

Agreed 2026 10 13 as phase 4b of docs/PLAN-CANVAS-CHOOSER.md. The survey it rests on found
four type scales, the light and dark pick copied into about a dozen files, three canvas
layout tables that disagree, the same four fallback preview colours repeated in three
plugins, and plugin panes that receive colours but no font, size, spacing or radius from
anywhere, so each picks its own.

## The shape

Four units under `lib/ui/`, each answering one question.

`style.lua` answers what the current look is. It takes one style spec at configure time and
answers a resolved token table for the half the system is on now. It is the only file that
asks `hs.host.interfaceStyle`, and that call is injected so the unit loads in plain Lua.

`measure.lua` answers how wide a piece of text is. It folds in `lib/chooser/textwidth.lua`
and the copies of `hs.drawing.getTextDrawingSize` the survey found, cached by font and size.

`kit.lua` answers what can be drawn. Every primitive returns a node, a plain table with a
kind and its fields. Nodes never hold a colour, a font or a size, only a variant name such
as `title` or `dim`. Containers hold child nodes. This is the Composite pattern, a tree in
which a stack and a single text answer the same layout call.

`layout.lua` answers where everything goes. `layout(node, rect, tokens, opts)` walks the
tree, measures through `measure.lua`, resolves every variant through the tokens, and returns
canvas elements plus the content height, so a scrolling pane can compute its own limit.
`opts.scrollY` offsets the result and the engine wraps it in a clip for the rect, closing
every clip it opens. Only a `group` takes an `id`, and a group with an `id` comes back with
`trackMouseUp` set, so a click reaches the owner's existing handler.

Nothing in the kit owns a window. The canvas provider's surface, CanvasPanel and the plugin
panes keep their own windows and draw what the engine answers, which is the same division
`field/render.lua` and `lib/cheatsheet.lua` already take.

## The tokens

```
colors   foreground subtext dim overlay accent note path
         background surface border selection highlight badge
fonts    ui mono
text     title body sub label heading mono big       each {font, size, lineHeight}
space    xs s m l xl                                  points
radius   surface badge chip
alpha    dim fade                                     multipliers, one rule each
icon     row list sheet                               points
```

The colour names are the theme palette's roles where one fits, so the later palette step
maps them one to one rather than renaming anything. `path` and `note` are the two preview
colours with no role yet.

## The primitives

```
text(str, variant, {color, align, lineBreak, wrap})
badge(key, size)              size names cheat, hint or button
icon(imageOrGlyph, size)      a glyph is drawn to an hs.image, cached, so the same call
                              also feeds a native chooser row
row(children, {gap, align})   left to right, the last child may take the remaining width
stack(children, {gap})        top to bottom
flow(children, {gapX, gapY})  left to right, wrapping at the rect width, the hint bar
grid(children, {columns})     the cheat sheet
divider()
spacer(size)
surface()                     the chrome, CanvasPanel.surfaceElements behind it
group(children, {alpha, id})  multiplies every child colour and image alpha, and carries
                              the click id
```

Text is always emitted as `hs.styledtext`, since only styledtext carries a line break mode
and a pinned line height, and both are in use.

Three drawings stay bespoke and read tokens directly rather than becoming primitives,
because each has exactly one consumer. The field's caret and selection, the canvas list's
scrolled rows, and the graph curves in the speedtest and processes panes. A primitive for
any of them waits for a second consumer.

## How it is wired

`root/compose.lua` builds the style once from policy and configures it, the way it already
configures CanvasPanel. The kit is offered to plugins as `needs.lib.ui`, the same door
`glyphIcon` and `cheatSheet` already use, and arrives as a table holding the primitives, the
layout call and the current tokens. A plugin never names a colour, a font or a size.

## The style spec, and where colours come from

Colours come from theme files, `config/themes/<name>.toml`, one per theme, each a `[dark]` and
a `[light]` section of ten keys, read by `lib/ui/toml.lua` and kept by `lib/ui/themes.lua`.
`default.toml` is hand chosen and holds the look the config had before themes were files, and
`aura.toml` is generated from the repository palette by the package's `theme-map` and
`theme-emit`. `root/uispec.lua` builds the spec from the live theme's colours and from the
`cheatSheet` radius and type settings, and a switch is the store handing the kit a new spec, so
the next draw shows it. The OLM settings page lists the themes and switches them. Two views
of the theme, a `chooserTheme` shaped table and a `surface` shaped one, are rewritten in place
on every switch for the readers outside the kit that still take them, and stage four retires
both.

## Stages

1. The four units with offline unit cases, wired into compose and offered as `needs.lib.ui`.
   Nothing draws through them yet.
2. The canvas provider, CanvasPanel's empty state, the hint bar, the toasts and the cheat
   sheet draw through the kit, and the three disagreeing layout tables become one. Judged
   by eye against main for visual parity.
3. The palette step, the new look.
4. Each plugin pane moves onto the kit, one plugin at a time, and its fallback colours go.

## What stage two added to hold parity

Stage two moved the empty state, the hint bar, the toasts, the cheat sheet and the canvas
provider onto the kit with nothing a person sees changing, proven by the probes that
`test/parity.sh` runs. Holding that needed a few additions, each holding a literal a surface
drew with. Text variants may set `pin` false, which leaves the line height unpinned and draws
exactly what a plain canvas text element draws, and `frameY` and `extraW`, which place the
frame against its box without taking room. The variants hintKey, hintLabel, cheat, cheatTitle,
toast, report, reportDetail and empty hold each surface's old type. Badge geometry may set
`minWidth`, `textY` and `radius`, and a badge may take `fill`. The colours quiet and outline,
the space steps sm and lg, the radius swatch, the icon swatch and the alpha muted joined the
tokens. The layout engine measures each laid out string whole through `measure:exact`.
`root/uispec.lua` builds the spec from settings for the root and the probes alike.
`lib/chooser/textwidth.lua` stays for the native provider alone. Stage three replaces the
parity variants with the new look.
