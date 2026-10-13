# Canvas list brief, phase 3a of the canvas chooser track, 2026-09-10

A step docs/PLAN-CANVAS-CHOOSER.md does not name, inserted ahead of the contract freeze and
ahead of the provider for the same reason the field was, so there is something to look at and
judge before anything is committed to. This builds a picker that LOOKS and MOVES like the real
one and satisfies no contract, wired to nothing. Whether it becomes the provider is decided
after it has been seen, not before.

Decisions here were made by the orchestrator. A builder follows them rather than relitigating
them. Where this brief and the code disagree, stop and report rather than improvising.

## What to build

A list drawn under the field that already exists, on one canvas, filtering as a person types,
moving under the keyboard, and scrolling when there are more rows than fit. It must be close
enough to the current chooser in geometry and wording that the two can be opened side by side
and compared honestly, because that comparison is the whole point of this step.

## The shape

The same division the field already took, because it worked and because a second shape here
would make the eventual provider a translation layer rather than a composition.

    list/model.lua   pure Lua. Rows in, a query, and out comes the filtered and ranked set,
                     the highlighted index, and the scroll offset. One function per movement.
                     No hs, no timers, no drawing, so all of it is provable offline.
    list/render.lua  elements for a rect, given the model state and a style. Draws rows,
                     the highlight, titles, subtitles and the icon slot, and never owns a
                     canvas.

There is no new input file. The field's own tap already claims every key down and offers what
it does not name to its consumer through `onKey`, which is exactly the seam the list navigation
hangs off. Do not modify `input.lua`, `keymap.lua` or `model.lua` under `field/`. If the list
genuinely cannot be driven through the existing `onKey`, stop and report rather than widening
the field to suit it.

## Decisions

1. The row shape is the one the atom already takes, `title`, `subTitle`, `image`, `enabled`,
   `item` and `filterText`, exactly as documented at the head of
   `lib/chooser/providers/native.lua`. A row this list can draw must be a row the native
   provider could have drawn, so the eventual provider needs no translation and no consumer
   ever learns which backend it is talking to.

2. Filtering uses the real matcher, `lib/chooser/match.lua`, loaded by path. Do not write a
   second matching rule. That file is pure and its fuzzy strategy is the one every list in
   this configuration uses today, so reusing it is what makes the comparison honest, and a
   difference in what ranks first would otherwise read as the canvas backend being worse when
   it is only different. `filterText` is the haystack when a row carries one, otherwise the
   title and the subtitle joined, matching `haystackOf` in the native provider.

3. Geometry matches the current chooser rather than being chosen fresh, so the two can be put
   side by side. Width 480, row height 42, ten visible rows, and the field area the height the
   native layout calls `baseH`. Take these from a layout table using the same field names as
   `DEFAULT_LAYOUT` in the native provider, so the real layout can later be handed straight in.

4. Scrolling is a viewport over the filtered set, moved by whole rows, keeping the highlight
   visible. Moving past the bottom scrolls by one, moving past the top scrolls back, and the
   highlight never leaves the visible band. No momentum and no rubber banding, since neither
   is reachable from a canvas and pretending otherwise would only look broken. The wheel is
   out of scope for this step, the keyboard is what is being judged.

5. The highlight wraps at both ends, the way the native chooser does, so holding a movement key
   never dead ends. An empty filtered set has no highlight at all rather than a highlight on
   nothing, and the model must answer that state without raising.

6. Chrome is inherited, not invented. The surface, the border and the corner radius come from
   `CanvasPanel.surfaceElements`, and the row colours from the style the caller passes, which
   the probe fills from `settings.chooserTheme`. The renderer reads no settings of its own.

7. A disabled row draws dimmed and cannot be chosen, matching what the native provider does
   with `enabled` today, since a guidance row that looks actionable is worse than no guidance
   row.

## The probe

Extend the existing probe rather than writing a second one, since a field with no list is no
longer the interesting thing to look at. It keeps everything it has, the blink timer, escape,
and the watchdog with its configurable seconds.

Rows come from the running applications, name as the title and bundle path as the subtitle,
with their real icons in the image slot. That is a real list with real proportions, enough of
it to scroll, and it makes the comparison against menu search or the launcher immediate rather
than abstract. Pad it with synthetic rows if a machine does not have enough applications open
to fill more than one screen of list.

Print what the keys are when it opens, as it already does for the field.

## What not to do

Do not touch `lib/chooser/init.lua`, `lib/chooser/providers/native.lua`, `host/stage`,
`root/compose.lua`, any manifest, or any plugin. Do not implement the picker contract, that is
the provider's job and it comes after the contract freeze. Do not modify anything under
`field/`. Do not reload the live config, restow, or take the devlock. Do not drive the screen
or the keyboard, a person opens the probe.

## Acceptance

An offline unit case covering the model, filtering through the real matcher, movement and
wrapping, the viewport following the highlight in both directions, and the empty set. The
suite total rises and no existing case changes its result. The reconciler stays clean. And a
picker on screen that a person can type into, move through, and compare against the real one,
which is the actual gate and is Milos's call rather than the test count's.

## Round two, from the first hand test, 2026-09-10

The list ranks, moves, scrolls and empties correctly. Two things are wrong and the second one
overrides a decision this brief made.

### 1. The last row is short

Scrolled to the bottom, the final visible row draws a few points shorter than every row above
it, reported as roughly 96 or 98 against a full 100. Every other row is uniform. That is the
bottom of the list being clipped by whatever edge it is drawn against rather than the row
being sized differently, so the rect the rows are laid into is a little shorter than the whole
number of rows it is asked to hold, and the shortfall lands entirely on the last one.

Measure where it goes rather than adding a few points until it looks right. The row band's
height must be exactly the visible row count times the row height, and whatever padding, border
inset or rounding is currently eating into it has to be accounted for above that band rather
than subtracted from it. A row that is uniform except at one end is the kind of fault that
looks like a rendering detail and is actually arithmetic.

### 2. Decision three is withdrawn, do not match the native proportions

Decision three said to match the current chooser's geometry so the two could be put side by
side, and that was the wrong instruction. The point of this backend is not to reproduce a
widget we already have, it is to be better than it, and the native proportions are a
constraint that widget's own nib imposed rather than a design anybody chose. Judged by hand
the field is far too tall for what it holds and the whole thing reads as badly proportioned.

So the geometry is designed rather than copied. The field is a search input, it should be
comfortable to read and never dominant, since it holds one short line while the list below it
is what a person is actually looking at. The rows carry a title and a subtitle, so they need
enough room to separate the two without the list becoming so airy that ten of them cannot be
scanned at a glance.

Start from these and expect them to move, they are a considered opening position rather than
a specification. A surface 620 wide. A field band 58 tall carrying text at 21. Rows 52 tall
with the title at 15 and the subtitle at 12. Nine visible rows. Sixteen points of horizontal
padding, and an icon column sized to what a 28 point icon needs.

The numbers must live in ONE clearly marked table at the top of the probe, named so it is
obvious that is where to edit, because the next few rounds are going to be a person looking at
it and saying taller or tighter. A geometry spread across three files cannot be tuned in one
edit and will be tuned wrongly instead.

Keep taking the field names the native layout uses where they already fit, width, rowH,
rowCount, baseH, font, titleSize and subSize, since the eventual provider is handed a layout
table and matching the names is what keeps that a hand off rather than a translation. Add new
names for anything the native layout has no word for.

### What to deliver for round two

Both fixes. No new unit case is required for the proportions, they are judged by eye, but the
row band arithmetic in the first item is exactly the kind of thing a case should hold, so add
one that asserts the band height is the row count times the row height with no remainder.

## Round three, the ends of the list, 2026-09-11

Decided by hand on 2026-09-11 after both behaviours were switched between live in the probe.
The highlight WRAPS. Down on the last row lands on the first and up on the first lands on the
last, so holding a movement key circles the list rather than dead ending.

This is a deliberate divergence from the native chooser and must not be quietly corrected
later to match it. Decision five of this brief originally justified wrapping as what the
native chooser does, and that was simply wrong. `native.lua`'s own `_move`, the function
behind selectNext and selectPrev, clamps at the ends and says so in its own comment. The
builder followed the instruction, flagged the contradiction rather than silently picking one,
and the contradiction was then resolved by looking at both rather than by reading either file.

So decision five stands on its own reasoning now instead of on a false comparison. The cost of
wrapping is that a long press can carry somebody from the bottom of a list back to the top
without their noticing, which gets worse the longer the list. The cost of clamping is a dead
key press every time you are already at the end, with no movement and no feedback to say why.
The second cost is paid constantly and the first is paid rarely, which is what settled it.

The demonstration switch that made this comparison possible lived in the probe rather than in
the model, so nothing had to be removed from the model when the answer came back, and the
switch is now gone. The model wraps, it never learned a second mode, and no option was built
for a question that has been answered.

## Round four, one type size and a compact uniform row, 2026-09-11

From the second hand test. The proportions from round two were closer but still wrong in kind
rather than in degree, so this round replaces the sizing model rather than nudging its numbers.

### 1. One type size for the whole surface

The field text and the row title are the same size, 16, and they read from ONE value in the
geometry table rather than from two that happen to agree. Two keys that must always match are
two keys that will eventually stop matching, and the whole point of this being one table is
that a person changes one number and the surface stays coherent. Name it for what it is, the
surface's text size, not for either of the two places it lands.

The secondary text keeps a size of its own, since it is deliberately smaller and is the one
place a second value earns itself.

### 2. The search box and a row are the same height, and both are compact

`baseH` and `rowH` become the same number and that number is small. A row holds one line of 16
point text, so the height it needs is that line plus enough room to breathe and no more. Start
at 38 and expect to tune it.

A row carrying a subtitle does NOT get taller. The height is uniform down the whole list,
because a list whose rows change height as the query changes reads as jumping rather than
filtering, and the highlight would move by a different distance on every press.

### 3. The subtitle is optional and its absence changes the layout

A row with no `subTitle` centres its title vertically in the row rather than leaving it sitting
high with a gap underneath where a subtitle would have been. A row with one keeps the pair
stacked as now. This is not cosmetic. Most lists in this configuration carry a subtitle on some
rows and not others, so a fixed title position means a list that looks broken on exactly the
rows that are simplest.

Use the real font metrics for the centring, the way `field/render.lua` already does. Centre the
cap height band rather than the full ascender to descender box, for the same reason that file
already records.

### 4. Cmd and a digit chooses a row

Cmd 1 through cmd 9 choose the first through ninth VISIBLE row, counted down the screen from
whatever the viewport is currently showing, not the first nine of the filtered set. Choosing
means exactly what return means on that row, including refusing a disabled one, so there is one
answer to what choosing does and not two that can drift.

None of those combinations are named in `field/keymap.lua`, so they reach `onKey` unclaimed the
same way up, down and return already do. Do not widen the field to carry them.

THE CONSEQUENCE WORTH NAMING. A shortcut nobody can see is a shortcut nobody presses, which is
this repository's own rule about the hint panel and applies here unchanged. So the first nine
visible rows draw their own number, dim and small and on the trailing edge, in the column the
native chooser reserves for exactly this. Draw it quietly enough that a person reading titles
does not see it until they look for it. If it turns out to cost more than it gives, it comes
out behind one flag in the geometry table rather than by unpicking the renderer, so build it
reachable that way.

### What to deliver for round four

All four, the geometry table still being the single place every number lives. Extend the unit
case for the vertical centring rule, a row with a subtitle and a row without placing their
titles differently, and for the visible row that a given digit resolves to when the viewport is
scrolled, since that is the part most likely to be off by one.

## Round five, scrolling, 2026-09-11

Asked for alongside round four. Decision four of this brief is replaced. It said the viewport
moves by whole rows and that the wheel was out of scope, and both of those are now wrong.

### The offset stops being a row and becomes points

`scrollTop` is a pixel offset, not an index. That is the whole of what makes scrolling smooth
and it is the part that ripples, since a viewport that can sit between two rows means the top
and bottom rows are partial and have to be CLIPPED rather than simply not drawn.
`hs.canvas` carries a clip action for exactly this, so the row band is clipped to its own rect
and the rows either side of the edge are cut by it rather than by arithmetic that omits them.

The offset is bounded so the list cannot be dragged past its own ends, no rubber banding, since
the spring back is the part a canvas cannot do convincingly and a list that bounces badly looks
worse than one that stops.

### The wheel and the trackpad

An `hs.eventtap` on scroll events, restricted to the surface's own rect, the same mechanism
`native.lua` already uses for its companion pane and for the same reason, that a canvas reports
no scroll of its own.

A trackpad sends continuous point deltas and macOS sends the momentum tail itself, so following
those deltas directly gives inertia for free and nothing here needs to simulate it. A mouse
wheel sends coarse line steps instead, and following those directly is what makes a wheel feel
like it jumps, so a line step is converted to points and the offset eases toward that target
over a short interval rather than arriving at once. Read which kind of event it is rather than
assuming, the event carries it.

### The highlight does not follow the wheel

Scrolling with the wheel moves the viewport and leaves the highlight on the row it was on, even
when that row leaves the visible band. This is what every picker does and the reason is that
scrolling is looking while the highlight is choosing, and moving what is chosen because somebody
glanced further down the list would be acting on a look. The next keyboard movement brings the
viewport back to the highlight, so the way out is the same key that would have moved it anyway.

### The keyboard still moves instantly

Up and down keep the highlight visible by snapping the offset, with no animation. This is
deliberately not symmetrical with the wheel. An animated keyboard scroll lags behind key repeat,
so holding a movement key makes the list slide behind the highlight and feel heavy, and every
picker worth copying scrolls instantly on the keyboard and smoothly on the trackpad. Snapping
means the offset lands on a whole row boundary, which is also what keeps a keyboard driven list
from coming to rest showing two half rows.

### What to deliver for round five

The model carrying a point offset with its bounds, the renderer clipping the band and drawing
partial rows, the probe owning the scroll tap and the easing timer and tearing both down with
everything else it already tears down. The unit case follows the model change, the existing
viewport assertions being rewritten in points rather than deleted, plus the bounds at both ends
and the snap landing on a row boundary.

The scroll tap is a second tap alive at the same time as the field's. It is armed on show and
stopped on hide like the first one, since a scroll tap left running is the same class of fault
as a key tap left running, and this probe's watchdog has to take both down.
