# Canvas geometry and truncation brief, phase three a of the canvas chooser track, 2026-09-11

Part one of phase three of docs/PLAN-CANVAS-CHOOSER.md. Read docs/CONTRACT-PICKER.md first,
in particular the Placement and Measurement sections, and read docs/BRIEF-CANVAS-LIST.md for
the geometry decisions already made by hand. Decisions were made by the orchestrator. Follow
them rather than relitigating them, and where this brief and the code disagree, stop and
report rather than improvising.

This part is the arithmetic the canvas picker stands on. It depends on nothing that is being
built beside it and it touches no surface, no timer and no event tap, which is why it is
separated out. Another builder is working on `lib/chooser/contract.lua`,
`lib/chooser/providers/native.lua`, `host/stage/init.lua` and `host/actionpanel/init.lua` at
the same time. Do not open any of those four files for writing.

## Where the numbers come from

`Spoons/Olm.spoon/test/probe-canvasfield.lua` carries a `GEOMETRY` table settled by hand
across five rounds with the user judging each one. Those values are the design and they are
not yours to change. Read them from the probe and carry them across. At the time of writing
they are a width of 620, a field height and a row height both 38, nine rows, the system UI
font, a uniform text size of 16 with a subtitle size of 12, a horizontal pad of 16, an icon
of 28 with a gap of 10, a text top pad of 5 for a stacked row, an edge margin of 12, and the
row numerals shown.

The native provider's own `DEFAULT_LAYOUT` is NOT the source. Its proportions came from a
compiled nib rather than from a design and the user rejected copying them outright. What the
canvas layout does inherit from it is the NAMES, `rowH`, `baseH`, `rowCount`, `gap`,
`paneMaxW`, `topFrac`, `minVPad`, `font`, `titleLineBreak`, `companionWidth`, so the stage's
accessors and a future reader meet one vocabulary rather than two.

## What to build

### 1. lib/chooser/providers/canvas/geometry.lua

Pure Lua. No `hs.canvas`, no timer, no drawing. It may call `hs.screen` nowhere, the caller
resolves the screen and hands in a frame, which is what keeps this provable offline.

`M.DEFAULT_LAYOUT`, the canvas layout, every field named above with the probe's values.

`M.resolve(screenFrame, layout, paneWidth)` answering one table of rectangles, all in
absolute screen points, the same space `hs.window` frames and `hs.eventtap` event locations
already use.

    canvas      the whole surface this provider draws, its own window
    field       the text field rect inside the canvas
    list        the row band rect inside the canvas
    chooser     what onPositioned reports as the chooser frame
    companion   what onPositioned reports as the companion frame, or nil
    rowCount    the row count actually usable after trimming to the screen

The rules. The canvas height is the edge margin twice, plus the field height, plus the row
band, which is the row count times the row height. The row count is trimmed the way the
native provider trims it, the screen height less twice the minimum vertical padding, less
the field height and the margins, divided by the row height, floored, and never more than
the requested count. The pair is centred horizontally on the screen as one unit, the canvas
width plus the gap plus the companion width when there is one. The vertical position is the
top fraction down from the top of the screen, clamped never closer than the minimum padding
to either edge, and when the surface is too tall to keep both pads the top pad wins. The
companion width resolves from `paneWidth`, true meaning it inherits the canvas width, a
number overriding it, nil or zero meaning none, and every answer capped by `paneMaxW`.

The chooser frame is the canvas frame. They are the same rectangle and this function answers
both names anyway, because `onPositioned` consumers speak of a chooser frame and the provider
speaks of its canvas, and one of them renaming the other's word would be worse than answering
twice.

The field rect and the list rect sit inside the canvas at the edge margin, the field on top
at the field height, the list directly beneath it filling the band. Nothing between them.

`M.rowAtPoint(point, rects, layout, scrollTop)` answering a visible slot number and the
point offset within that row, or nil when the point is outside the list rect. The arithmetic
is the list rect's own top subtracted from the point, plus the scroll offset, divided by the
row height, floored, plus one. A point in the field rect answers nil rather than row zero,
and a point outside the canvas answers nil. Say in the file that this answers a slot in the
VISIBLE band and not an index into the filtered set, because the caller turns one into the
other through `list/model.lua`'s own `rowAtVisibleSlot`, and confusing the two is the exact
off by one this separation exists to prevent.

`M.textBudget(rects, layout)` answering the pixel room a row's title has, the list rect
width less the leading pad, the icon and its gap, less the trailing pad and the numeral
column. This replaces the native provider's measured 126 point constant, which was read off
the accessibility tree and includes a command number badge this backend draws differently.
Compute it from the layout, never from a measurement.

### 2. Truncation, but VERIFY BEFORE YOU BUILD IT

A canvas text element given a frame narrower than its text does something, and this brief
does not know what. Find out before writing a line of truncation code.

An `hs.canvas` text element accepts an `hs.styledtext` value for its `text` key, and an
`hs.styledtext` carries a `paragraphStyle` with a `lineBreak` of `truncateTail` or
`truncateMiddle`, which is exactly the mechanism `lib/chooser/providers/native.lua` already
uses at its `styledText` function around line 155. If a canvas text element honours that
paragraph style inside its own frame, then truncation is free, this configuration already
has the code for it, and building a truncation module would be pure ceremony.

Measure it. Render offscreen with `hs.canvas.new` plus `imageFromCanvas`, a long string in a
narrow frame, once as a plain string and once as a styled text carrying a tail truncating
paragraph style, and look at what comes out. The previous builder on this track verified
`hs.canvas` clip semantics the same way, against the Hammerspoon source and then visually,
and that is the standard here.

Report what you found either way, with how you found it.

If the paragraph style is honoured, deliver no truncation module. Write down what you
measured in `lib/chooser/providers/canvas/geometry.lua`'s own header so the next reader does
not rebuild it, and note which element key carries the styled value.

If it is NOT honoured, deliver `lib/chooser/providers/canvas/truncate.lua`, pure Lua,
`M.fit(str, budget, measure, mode)` where `measure` is a function of a string answering
pixels, injected so the module stays offline provable. It steps by UTF8 sequence rather than
by byte, honours `truncateTail` and `truncateMiddle`, uses a single character ellipsis and
counts its real measured width rather than assuming one, answers the string untouched when
it already fits, and answers something sane rather than raising for a budget smaller than
the ellipsis itself.

### 3. One addition to lib/chooser/providers/canvas/list/model.lua

That file is uncommitted work in progress and it is yours to extend for this one function
only. Do not change anything else in it and do not touch `list/render.lua`.

`M.rowAtPoint(state, yOffsetIntoBand)` answering the index into the filtered set for a point
that many points below the top of the row band, or nil when it falls past the last row. It
is the composition of the arithmetic above with the existing `rowAtVisibleSlot`, and it lives
here rather than in geometry.lua because only this file knows how many rows the filtered set
actually has. Add its assertions to `test/cases/canvaslist.lua`, including a point in the
partially visible top row after a fractional scroll, and a point below the last row of a
short filtered set.

## What not to do

Do not open `lib/chooser/contract.lua`, `lib/chooser/providers/native.lua`,
`host/stage/init.lua` or `host/actionpanel/init.lua`, another builder holds those. Do not
create the provider itself, that is part two of this phase. Do not draw anything permanent,
the offscreen renders above are throwaway measurement. Do not touch the field files, any
plugin, any manifest, or the composition root. Do not take the devlock, restow, or reload
the live config. Do not drive the screen or the keyboard.

## What to deliver

`geometry.lua`, the truncation answer with its evidence, the one model addition, and an
offline unit case at `test/cases/canvasgeometry.lua` following the convention every case in
that directory already follows, one PASS or FAIL line per check, loading by path with
`loadfile` and driving with plain tables. Cover the row trim on a short screen, the centring
with and without a companion, the top clamp when the surface is taller than the screen can
pad, `paneWidth` as true and as a number and as nil with the cap applied, a point in the
field answering nil, a point in the first and last visible rows, a point outside the canvas,
and the text budget arithmetic. If you built `truncate.lua`, cover both modes, the exact fit
boundary, a multi byte string, and the budget smaller than the ellipsis.

## Acceptance

`./test/units.sh` green with the suite total risen and no existing case changing its result.
`luac -p` clean on every file touched. `src/check-dependencies.sh` clean.

Report anything where this brief resists the code rather than bending either side quietly.
The truncation verification is the part most likely to contradict this brief, and a clear
report that it was wrong is worth more than code written around it.

## Writing style, a hard requirement

Never use em dashes, en dashes, or hyphens in prose. Only periods and commas, no colons and
no semicolons. This applies to code comments and to your report. It does not apply to code
itself or to file paths.
