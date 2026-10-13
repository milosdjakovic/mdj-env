# Canvas provider brief, phase three c of the canvas chooser track, 2026-09-11

The last part of phase three of docs/PLAN-CANVAS-CHOOSER.md. Read docs/CONTRACT-PICKER.md
completely first, it is the specification this implements. Decisions were made by the
orchestrator. Follow them rather than relitigating them, and where this brief and the code
disagree, stop and report rather than improvising.

Everything this provider stands on already exists. `geometry.lua` answers the arithmetic,
`surface.lua` owns the window, `mouse.lua` owns the mouse tap, `field/` is a complete text
field judged by hand across three rounds, `list/` is a complete row list judged across five,
`lib/chooser/contract.lua` says what a provider must offer, and `lib/chooser/textwidth.lua`
measures text for both backends. This part is mostly wiring, and the places where it is not
are named below.

## Section 0, lib/chooser/rank.lua

This section is a separate job from the rest of this brief and another builder may hold it.
If you were told to do only section 0, do only this. If you were told to do the rest, assume
this module exists exactly as described and call it.

`lib/chooser/providers/native.lua`'s own `_build`, around lines 213 to 239, ranks the
supplier's candidates. It asks `config.rows(query)`, and when a matcher is present and the
query is not empty it scores every candidate through `matcher(query, haystack)`, drops the
ones scoring nil, and sorts by score descending with the original index ascending as the tie
break, which is what lets a stable secondary order like the launcher's recency still show
through. The haystack is a row's own `filterText` when it carries one, otherwise its title and
subtitle joined with a space. With no matcher, with an empty query, or with the matcher set to
false, every candidate is kept in the order the supplier gave them.

None of that is coupled to `hs.chooser`. It is this configuration's ranking policy and it is
about to have a second consumer, so it moves into `lib/chooser/rank.lua` as a pure module,
`M.apply(items, query, matcher)` answering the ranked list, with the haystack rule as a local
inside it. Native's `_build` then calls it and keeps only its own styling step. This is a pure
move and the order it answers after the move must be identical to the order before, because
a difference here would read as one backend being worse when it would only be different.

Deliver it with an offline unit case at `test/cases/chooserrank.lua` following the convention
every case in that directory already follows. Cover the no matcher path, the empty query path,
the matcher set to false path, a matcher dropping a candidate, the score ordering, the tie
break preserving the supplier's own order for two equal scores, and `filterText` winning over
title and subtitle.

## Section 1, the one addition to field/input.lua

An empty field taking a backspace pops a level, which is what `config.back` is for and what
the native provider does. The field's keymap claims backspace unconditionally as
`deleteBackward`, so that key never reaches `onKey` and the provider cannot see it.

Add `opts.onEmptyBackspace` to `Field.new`. In `Field:_handle`, once `keymap.resolve` has
answered `deleteBackward`, and only then, if the buffer is empty and nothing is selected and
that callback is set, call it and claim the key without applying anything. Every other path
through that function is untouched, and a non empty buffer behaves exactly as it does today,
which matters because that behaviour was judged by hand and is not being reopened.

Say in the file why this could not be a plain `onKey` case.

## Section 2, lib/chooser/providers/canvas/init.lua

### How it is wired

`M.configure(opts)` at module level, taking `opts.panel`, the CanvasPanel module. It has to
be injected rather than loaded by path here, because `lib/panel.lua` holds the shared surface
style that the composition root configures exactly once, and a second copy loaded fresh by
path would answer an unconfigured one and draw chrome that does not match every other surface
in this configuration. Wiring it at the root is phase four. For now the probe injects it, and
`M.new` refuses with a plain reason when nothing has been configured, rather than drawing
something that looks subtly wrong.

`M.new(config)` answers an instance satisfying `lib/chooser/contract.lua` exactly. Validate
against that module yourself at the end of `new` and raise on a gap, rather than waiting for
the facade to notice, so a missing name is found by the probe rather than by a person.

Load every sibling by path with the `loadfile` idiom the field and the list already use.

### Show

Reselect the theme from `config.theme` against `hs.host.interfaceStyle()`, the same rule the
native provider's `_selectTheme` follows and for the same reason, so a light and dark switch
is picked up at the next open. Resolve the screen through `config.screen` with the same
fallbacks. Ask `geometry.resolve` for the rectangles. Place the surface. Build rows for an
empty query. Put the highlight on row one. Clear the field. Draw. Show. Arm the field tap, the
mouse tap and the caret blink. Report `onPositioned` ONCE with the final frames, since this
backend knows them before it draws and has no correction pass. Then call `onHighlight` with
the first row synchronously, which is not a seed for a poll that is about to start, it is the
whole mechanism, because this provider knows the instant its own highlight moves and never
polls for it.

### Hide and teardown

One idempotent path every dismissal funnels through, a selection, escape, a click outside, or
a programmatic call, and `onClose` fires exactly once per open.

STOP THE TWO TAPS FIRST, before anything else in teardown, and only then tear down timers,
the surface and the state, and only then fire `onClose`. Commit `1ccab6f` is this
configuration's own record of what happens when a consumer callback raises above the line that
was supposed to release an input grab. A keyboard tap that claims every key down is the worst
thing in this configuration to leave armed, and ordering is the protection, not hope. Guard
the consumer callback so a raise inside it cannot abandon the rest of teardown.

### Ranking and the list, and the one trap in it

`list/model.lua` does its own matching through `lib/chooser/match.lua`, because it was built
standalone before this provider existed. This provider must NOT let it, or every query is
filtered twice, once by the contract's live `matcher` and again by the list's own fuzzy
strategy, which would silently ignore a presentation that set `matcher` to false to own its
filtering and would quietly answer a different order than the native backend for the same
query.

So the provider ranks through `lib/chooser/rank.lua` using the live `matcher()`, and hands the
already ranked rows to the list model with an EMPTY query, so the list model ranks nothing and
only holds, highlights and scrolls what it was given. Say this in the file at the call site,
because it reads like a bug to anyone who has not been told.

### Keys

The field claims everything it knows. What reaches `onKey` is what this provider handles, and
everything it does not handle is swallowed rather than let through, because the frontmost app
still has focus and would otherwise receive it.

Return, keycode 36, and keypad enter, keycode 76, choose the highlighted row, which means
asking `config.intercept(item, enabled)` first and honouring a disabled row, exactly as
`insertSelected` does. Up, 126, and down, 125, move the highlight through the list model,
fire `onHighlight` and redraw. Cmd with a digit one through nine chooses that VISIBLE slot,
which is `list/model.lua`'s own `rowAtVisibleSlot` and not an index into the filtered set, the
off by one the list round already has a test for. Escape arrives through the field's own
`onDismiss` and hides, never delegated. Backspace on an empty field arrives through section
one's callback and calls `config.back`, and when back answers falsy the key does nothing
rather than dismissing.

`config.onActivity` fires on every key, which is what the docked hint panel's idle timing
reads.

### Mouse

A move over a row sets the highlight and fires `onHighlight`, because the native widget
highlights on hover for free and its absence would read as this backend being broken. Do not
claim a move.

A left press inside the list records the row, and the release chooses it when it is the same
row, which is ordinary click behaviour and also what the native provider measured the widget
doing. Claim both. A press outside the surface dismisses and is NOT claimed, so the click also
reaches whatever the person meant to click, which is what happens today.

A right press on a row calls `config.onRightClick(item, row)`. Read that callback LIVE from
the config on each use. The native provider reads it once at construction and never again, and
the stage's own comment records that as a past defect, so this backend does not reproduce it.
The contract document says so.

A scroll over the list moves the viewport without moving the highlight, through the list
model's `scrollBy`. A trackpad, which the mouse shell reports as continuous, is followed
directly. A wheel is eased, because a wheel sends coarse notches and following them reads as
jumping. Both were settled by hand in round five and the constants are in
`Spoons/Olm.spoon/test/probe-canvasfield.lua`'s own GEOMETRY table, carry them across rather
than choosing again. A scroll over the companion rect calls `config.onScroll(points)` instead.

### Colours

`config.theme` carries `bgDark`, `titleColor`, `subColor` and `preview` and nothing else. It
has no highlight colour and no caret colour, because it was written for a widget that drew
its own. Derive those from what the theme gives, and let the renderers' own defaults stand
where they already read well. Do NOT add a settings block, decision five of the plan says
theming is inherited. If a derived colour reads wrong under a hand test, that is a finding to
report and a candidate for a later settings addition, not something to invent now.

### The rest of the contract

`refresh`, `query`, `setQuery`, `setPlaceholder`, `setRows`, `rowCount`, `selectNext`,
`selectPrev`, `selectRow`, `selectedRow`, `selectedItem`, `insertSelected`, `isShowing`,
`isActive`, `matcher`, `setMatcher`, `titleLineBreak`, `setTitleLineBreak`, `setPaneWidth`,
`textBudget`, `textWidth`, `reposition` and `settleDelay` all follow the contract document
directly. Two worth naming. `settleDelay` answers zero, this surface is final on its first
frame. `reposition` is cheap and live here, it recomputes through `geometry.resolve` and moves
the surface, which is the gain this whole backend was built for, so say that in the file.

`setRows` is documented as taking effect on the next show. This backend CAN resize live. Honour
the contract's promise rather than the capability, take effect on the next show, and note in
the file that the restriction is inherited rather than required, so phase five knows it is free
to lift it deliberately.

## What not to do

Do not touch `host/stage/init.lua`, `host/actionpanel/init.lua`, `root/compose.lua`, any
manifest or any plugin. Do not wire this provider into the facade, that is phase four. Do not
change `list/model.lua`, `list/render.lua`, `field/model.lua`, `field/keymap.lua`,
`field/render.lua`, `geometry.lua`, `surface.lua` or `mouse.lua`, they are done. The one
exception is section one's addition to `field/input.lua`. Do not take the devlock, restow, or
reload the live config. Do not drive the screen or the keyboard, and do not run the probe
yourself.

## What to deliver

`lib/chooser/providers/canvas/init.lua`, section one's addition, and a live probe at
`Spoons/Olm.spoon/test/probe-canvaspicker.lua` following the convention
`probe-canvasfield.lua` already sets, loaded by `dofile` over the running Hammerspoon. It
builds a real provider instance with a hand written supplier of thirty or so rows carrying a
mix of subtitles and no subtitles and at least one disabled row and at least one image, injects
CanvasPanel from the running instance, wires every callback to a printed line so a person can
see `intercept`, `back`, `onHighlight`, `onSelect`, `onScroll`, `onRightClick`, `onPositioned`
and `onClose` actually firing, and shows it. Escape dismisses. A hard watchdog tears everything
down after a bounded time read from a global the way the other probes read theirs and clamped
the same way, whatever else has happened.

No offline unit case for `init.lua` itself. It is a shell wiring real resources together and a
case built on a fake `hs` would prove only that the fake matched. Section 0 is where the
offline coverage goes.

## Acceptance

`./test/units.sh` green with the suite total risen by section 0's case only, and no existing
case changing its result. There is one known preexisting failure in the actionpanel case about
a substring, leave it and say it was already there. `luac -p` clean on every file touched.
`src/check-dependencies.sh` clean. `lib/chooser/contract.lua`'s own validate answering true for
a freshly built canvas instance, proved by a line in the probe rather than asserted.

Report every place the brief resisted the code. The ranking trap and the teardown ordering are
the two most likely to bite, and a clear report that this brief was wrong about one of them is
worth more than code written quietly around it.

## Writing style, a hard requirement

Never use em dashes, en dashes, or hyphens in prose. Only periods and commas, no colons and no
semicolons. This applies to every code comment you write and to your report. It does not apply
to code itself or to file paths.
