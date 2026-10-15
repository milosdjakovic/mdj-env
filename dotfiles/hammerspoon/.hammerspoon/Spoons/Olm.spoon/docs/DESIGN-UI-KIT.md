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

`measure.lua` answers how wide a piece of text is. It folded in `lib/chooser/textwidth.lua`,
since deleted, and the copies of `hs.drawing.getTextDrawingSize` the survey found, cached by font and size.

`kit.lua` answers what can be drawn. Every primitive returns a node, a plain table with a
kind and its fields. Nodes never hold a colour, a font or a size, only a variant name such
as `title` or `caption`. Containers hold child nodes. This is the Composite pattern, a tree in
which a stack and a single text answer the same layout call.

`layout.lua` answers where everything goes. `layout(node, rect, tokens, opts)` walks the
tree, measures through `measure.lua`, resolves every variant through the tokens, and returns
canvas elements plus the content height, so a scrolling pane can compute its own limit.
`opts.scrollY` offsets the result and the engine wraps it in a clip for the rect, closing
every clip it opens. Only a `group` takes an `id`, and a group with an `id` comes back with
`trackMouseUp` set, so a click reaches the owner's existing handler.

Nothing in the kit owns a window. The default chooser's surface, CanvasPanel and the plugin
panes keep their own windows and draw what the engine answers, which is the same division
`field/render.lua` and `lib/cheatsheet.lua` already take.

## The tokens

```
colors   foreground subtext background border highlight primary secondary tertiary
fonts    ui mono
text     title body sub label heading mono big       each {font, size, lineHeight}
space    xs s m l xl                                  points
radius   surface nested                               points, nested derived from surface
pad      one number                                   points, every panel's padding
stroke   border graph                                 points, outline and divider, graph line
alpha    dim fade                                     multipliers, one rule each
icon     row list sheet                               points
```

The colours are exactly eight, and nothing derives a ninth. They once numbered fourteen, and
the merge was path and meta into subtext, dim and overlay and the faint baseline into border,
surface into background, selection and badge into highlight, accent into foreground, outline
into border, and note into an accent by rank or into subtext when it was text. The kit refuses
any other colour name at build time. An alpha a rule needs, such as the dim alpha of a disabled
row, is in the alpha group and is not a role. The rule and what each role is for are in
"Olm colour, eight roles and nothing else" in the config's `AGENTS.md`.

## Corners, one radius and one formula

`surface.cornerRadius` in `config/settings.lua` is the only corner a person sets, and every
other corner Olm draws is derived from it by one formula, inner radius equals outer radius less
the padding between the two edges, never below zero. `ui.nestedRadius(outer, gap)` is that
formula and `radius.nested` is it applied once, the surface radius less `pad`, the padding every
panel and pane takes on all four sides. So the hint bar's key badges, the Dismiss chip, the
colour toast's swatch, a preview picture in a pane and the clipboard's colour chip all take
`radius.nested`. Something with its own padding works out its own corner with the same call,
the chooser's highlighted row from the list margin and the cheat sheet's badges from its doubled
padding. The inside of a surface's border takes the surface radius less the border width, the
same rule again, which is what a scroll clip follows.

The radius is dynamic and never cached beside the shape it rounds, so changing the surface
radius changes every corner on the next draw, and a surface set to 0 squares everything inside
it. Padding has to be the same on all four sides for the corners to fit, which is why `pad` is
one number rather than an x and a y. The dry gate refuses a number written into a radius
anywhere outside `lib/ui`, through the same scan as the typography rule.

## Borders

`surface.borderWidth` in `config/settings.lua` is the only border width a person sets, and the
kit hands it on as `stroke.border`. Every outline and every divider takes that width and the
`border` colour role, the surface's own border, the colour swatch's outline and a graph's
baseline. A line in a graph is a mark rather than a border and takes `stroke.graph`.

The padding the corner formula subtracts is measured from the outer edge of the surface, border
included, so a border needs no change to the formula. A stroke is drawn inside its shape, its
frame inset by half the width and its corner less half the width, the nested rule once more, so
the line follows the curve of the fill it outlines rather than straddling it. Chips, badges and
the highlighted row carry no border, they read by their `highlight` fill. The dry gate refuses a
number written into a stroke width outside `lib/ui`, the same scan as the corners.

## The primitives

```
text(str, variant, {color, align, lineBreak, wrap, width})
badge(key, size)              size names cheat, hint or button
icon(imageOrGlyph, size)      a glyph or an icon spec is drawn by the root's icon engine, so the same call
                              also feeds a legacy chooser row
row(children, {gap, align, fillIndex})
                              left to right, the last child takes the remaining width, or the
                              one fillIndex names, so a header can truncate its name and keep
                              its facts whole
heading(label, facts)         a section label left and optional facts flush right in subtext, see below
stack(children, {gap})        top to bottom
flow(children, {gapX, gapY})  left to right, wrapping at the rect width, the hint bar
grid(children, {columns})     the cheat sheet
divider()
spacer(size)
surface()                     the chrome, CanvasPanel.surfaceElements behind it
group(children, {alpha, id})  multiplies every child colour and image alpha, and carries
                              the click id
code(lines, {maxHeight, more}) preformatted block in the code role, see below
raw(height, draw, {width})    room the caller draws into itself, see below
image(img, {upscale})         a picture at the slot width in its own aspect, top left, see below
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
a `[light]` section of the eight colour keys, read by `lib/ui/toml.lua` and kept by `lib/ui/themes.lua`.
`default.toml` is hand chosen and holds the look the config had before themes were files, and
`aura.toml` is generated from the repository palette by the package's `theme-map` and
`theme-emit`. `root/uispec.lua` builds the spec from the live theme's colours and from the
`cheatSheet` radius and type settings, and a switch is the store handing the kit a new spec, so
the next draw shows it. The OLM settings page lists the themes and switches them. Two views
of the theme, a `chooserTheme` shaped table and a `surface` shaped one, are rewritten in place
on every switch from the eight roles, for the readers outside the kit that still take them, the
legacy provider and the panel surface, and stage four retires both.

## Stages

1. The four units with offline unit cases, wired into compose and offered as `needs.lib.ui`.
   Nothing draws through them yet.
2. The default chooser, CanvasPanel's empty state, the hint bar, the toasts and the cheat
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
`lib/chooser/textwidth.lua` stayed for the legacy provider alone then, and the typography plan's
step five deleted it. Stage three replaces the parity variants with the new look.

## What the typography plan added, code, the visible slice and raw

Three pieces with more than one consumer each, from docs/PLAN-TYPOGRAPHY.md.

`code(lines, {maxHeight, more})` is a block of lines in the code role. Whitespace is
kept exactly, a tab is expanded to the next multiple of four columns when the node is built,
nothing wraps, and each line is cut at the rect width with truncateTail. When `maxHeight` is
given and the lines do not fit, as many lines as fit minus one are drawn and then a closing
line in the caption role, worded by `more(count)` and defaulting to "N more lines". The
content height is the drawn height.

The lines that are drawn go out as one text element, joined by newlines with the code line height
pinned and truncateTail so each line is still cut at the width, rather than one element per line.
A styled text per line was measured to make every scroll event cost dozens of constructions, and a
trackpad sends dozens of events a second. The closing line stays its own caption element.
The code role also sets `tighteningFactorForTruncation` to 0, since macOS otherwise tightens the letter spacing of a line it is about to cut, which draws a cut line narrower than its neighbours and shifts its columns left.

The visible slice applies when `ui.layout` gets `scrollY`. A code line wholly outside the
window, the rect shifted by the scroll, is left out of the element and is not measured, and the content
height still counts every line, since every line in the role is the same height.

`raw(height, draw, {width})` reserves `height` points at its position and inserts what
`draw(rect, tokens)` returns, in order, with the absolute rect after the scroll offset. The
tokens are passed so every colour comes from them. It is as wide as its slot unless `width`
is given, which lets it sit beside other children in a row, the clipboard header's app icon. Group alpha and the click id do not reach
raw elements.

`image(img, {upscale})` draws a picture at the width of its slot, keeping its aspect, aligned top
left and scaled proportionally. Its height is derived from the width it is laid out at, so a stack
sizes it right whatever the pane width turns out to be. `upscale` is true unless given as false,
and false never draws it wider than its own size, which is how the file search pane keeps a small
icon from being blown up. A picture that cannot say its size draws as a square. Group alpha and the
click id reach it the way they reach an icon. It is a primitive rather than a raw node because the
clipboard pane and the file search pane both draw one and would otherwise each carry the same
arithmetic.

## The text slot, and why digits do not slide

`text` takes a `width`, a number of points, which makes the text a slot of exactly that width,
never wider than the room it is given, with `align` placing the text inside it. In a row that
means the children after it start at a fixed place, and in a stack, which offers every child the
whole width, the slot still applies. A wrapping text wraps at the slot. It exists for a figure
that changes under the eye, added 2026 10 14 with the speedtest step. The title role is the
proportional system font and its digits have different widths, so a number drawn at its own width
pushes the unit beside it sideways as it changes. The kit cannot ask for tabular digits instead,
since a canvas takes a font by name and size and nothing else, so the caller measures the widest
value its format can produce with `ui.measure`, makes that the slot, aligns the number right
inside it and puts the unit after. `plugins/speedtest/pane-nodes.lua` is the one consumer.

## The section heading

`heading(label, facts)` answers the row a pane heads a section with, the label in section at the
left and the facts, when there are any, in section and subtext flush against the right edge. With
no facts it is the label alone. The label is the child that takes the remaining width, so the facts
keep their whole width and it is the label that gives way in a pane too narrow for both. It is in
the kit because the file search pane, the processes pane and the speedtest pane all head a section
this way, and three private copies would each drift. Added 2026 10 14 with the processes step, and
the file search pane's own copy was deleted.

## What the typography plan's step three removed

The empty pane state, the hint bar, the toasts and the cheat sheet moved onto the five roles
and the parity variants went. Every text variant outside title, body, caption, section and
code is deleted, with the legacy mono font, the pin, frameY and extraW fields, the quiet
colour, the text override in the spec and `cheatSheet.fontSize`. A badge size is now a rule,
the line height of the role its glyph is drawn in plus twice a space step, with the padding
a space step too, so there is no textY and no height literal. The layout engine centres the
cap height of every text in its line band, from the real font metrics through `measure:metrics`,
the way the canvas list centres a row, so no caller nudges a frame. The empty state is caption
and subtext, the hint bar is a section badge beside a caption label, the message toast is
title, the colour toast's hex is code, the report toast is title, body and caption, and the
cheat sheet is body for the row label and the key glyph, caption for the separator and section
for a title. The cheat sheet's row, badge and title heights are derived from the role line
heights and the space steps unless a model gives its own. The parity probes for these
surfaces were removed, since they asserted the old look, and `test/cases/surfaces.lua` pins
the derived geometry instead.

## The typography check, and how an icon declares itself

The dry gate, `test/drygate.sh`, reports any font name, text size or line height written outside
`lib/ui`, the way `src/check-theme.sh` reports a hex value, so the five roles cannot drift again.
`test/drygate-typography.lua` holds the patterns and `test/cases/typographycheck.lua` plants a
violation and an exempted line to prove it finds one and accepts the other. It reads every Lua
file under the spoon except `lib/ui` and `test/`, and it looks for a value written by hand. That
is a numeric or constant `textSize`, a quoted `textFont`, a `font` table naming a literal name or
size, a quoted font name such as the system or monospace font, and a line height field. A value
read from a variable the kit filled is the kit's own passing through and is not flagged, so the
default and legacy providers, which are handed the roles, stay clean. A comment line, and the
comment at the end of a code line, never count.

An icon is not text. A glyph or an emoji drawn into a small canvas to make a row icon, a keycap
or a filter glyph is an image, and its size is the box it fills. Such a site declares itself with
a comment on its line or the line directly above reading `type-exempt`, a comma and the reason,
the same form as `theme-exempt`. The gate prints every exempted line as an accepted item and
counts it, and an exemption with no reason is a finding. Row icons no longer need the exemption in
a plugin, since Olm draws them through the icon engine in `lib/icons`, and the one canvas that draws
an emoji there carries it. Moving other sites onto icon tokens in the kit is a separate decision,
recorded in `docs/PLAN-TYPOGRAPHY.md`.
