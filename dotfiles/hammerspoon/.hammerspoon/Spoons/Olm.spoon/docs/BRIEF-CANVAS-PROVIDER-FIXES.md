# Canvas provider fix round, from the adversarial review of 2026-09-11

An Opus review went through `lib/chooser/providers/canvas/init.lua` against
docs/CONTRACT-PICKER.md and against `lib/chooser/providers/native.lua` as the reference.
Eleven findings, plus two riders. The orchestrator verified the three load bearing ones by
hand and triaged the rest. This is the work order. Each item names the finding, the file,
the trigger and the fix. Do them all. Where this brief and the code disagree, stop and
report rather than improvising.

## 1. config.rows is the one consumer callback with no guard

`init.lua:319`, inside `_rankedRows`, calls `self.config.rows(query)` bare. Every other
outward call in the file goes through `safeCall`, and that helper's own comment says it is
used for every config callback this file calls outward.

Why it matters here and not on native. `field/input.lua`'s `_apply` runs the model mutation
inside a `pcall` and then calls `_notify` OUTSIDE it, so a raise in the supplier unwinds out
of `Field:_handle` before its own `return true`. The eventtap callback errors, Hammerspoon
passes the event through unmodified, and the character the person typed lands in the
application the picker is covering, on every keystroke, while the picker stays up showing a
stale list. Native's identical bare call sits inside `hs.chooser`'s own callback, which
claims no keys, so the same supplier costs nothing there.

Fix. Route it through `safeCall` and fall back to an empty list.

## 2. selectRow moves the highlight without bringing it into view

`init.lua:864` to `875` sets the highlight and renormalises, and `list/model.lua` deliberately
never pulls `scrollTop` toward the highlight, which its own header explains at length and
which is the decision that lets a wheel scroll survive.

Trigger. `host/actionpanel/init.lua:358` restores the row a person was on when they opened
the action panel. Any captured row past the visible band lands off screen, so the highlight
is invisible, `selectedItem` answers a row nobody can see, and a chord acting on the
highlight acts on that invisible row. It only corrects itself on the next arrow press. Native
gets this free, `hs.chooser:selectedRow(n)` scrolls its table.

Fix. After clamping, bring the row into view through the PUBLIC `listModel.scrollTo`, pulling
`scrollTop` up to `(n - 1) * rowH` when the row starts above the viewport and down to
`n * rowH - rowH * visibleCount` when it ends below. Do not change `list/model.lua`.

## 3. refresh tests resetRow == true where the contract says truthy

`init.lua:794`. The contract document says a truthy argument resets, native uses a plain
`if resetRow then`, and `host/stage/init.lua` forwards whatever a caller handed it unexamined.
Latent today since every caller passes `true` or nothing, and silent rather than loud when it
lands.

Fix. Test truthiness.

## 4. The caret blink timer can be armed outside an open and never stopped

`_restartBlink` at `init.lua:394` is reached unconditionally from `_onFieldChange`.
`setQuery` called while `self.active` is false starts a repeating timer redrawing a hidden
canvas, and `_teardown` returns on its first line because `active` is already false, so
nothing stops it until the next show.

Fix. Return early from `_restartBlink` when `self.active` is false.

## 5. setQuery does not rebuild the list, and native's does

`init.lua:810`. The file's comment claims the stage and the action panel refresh themselves
right after, and that is not true as stated. `host/launcher/init.lua:929`, `952`, `991` and
`1406` all call `setQuery` with no refresh of their own. They survive today only because each
is reached from inside an `intercept` or a `back` handler and `_choose` refreshes after the
handler answers, which is luck rather than design.

The evidence this is real. `Launcher:enterPage` writes `self._page`, which changes what the
list MEANS, then calls `setQuery("")` and `setPlaceholder(title)` and nothing else. On native
the rebuild arrives through the query changed callback that `hs.chooser:query(text)` fires.

Fix. Rebuild inside `setQuery` the way native does, preserving the highlight reset behaviour
a fresh query implies, and correct the comment to say what is actually true.

## 6. The trimmed row count and layout.rowCount disagree, and three readers split

`geometry.resolve` trims the row count to the screen and answers it as `rects.rowCount`,
sizing `rects.list` and the canvas from the trimmed number. The provider then hands the
UNTRIMMED `self.layout` to `listModel.newState` at `init.lua:350` and to
`listRender.elements` at `init.lua:378`, where the clip band is `layout.rowCount * layout.rowH`.

Trigger, a screen short enough to trim, under roughly 524 points of frame height. Three wrong
answers at once. The clip band is taller than the list rect so rows draw past the bottom of
the surface. `maxScrollTop` is too small so the last rows can never be reached. And
`rowAtVisibleSlot` answers slots that are not on screen, so cmd plus a digit acts on a row
nobody can see.

Fix. Build a per show copy of the layout carrying `rowCount = self._rects.rowCount` and pass
that copy to both `listModel.newState` and `listRender.elements`. Keep `self.layout` as the
requested policy, which is what `rowCount()` and `setRows` speak about.

Rider at the same root. `setRows(n)` writes `self.layout.rowCount` live while the list model
captured the old value and `_rects` was sized from the old one. The stage always hides before
it resizes so nothing hits it today. The per show copy closes it, note that in the file.

## 7. onActivity fires after onClose on Return

`init.lua:561`, the unconditional `safeCall(self.config.onActivity)` at the FOOT of
`_onFieldKey`. On Return the branch above reaches `insertSelected`, `_choose`, `onSelect`,
`hide` and `onClose`, all before line 561 runs, so a consumer using it as an idle signal is
told a key was pressed in a picker that is already gone. Native fires it at the top of its
key watcher before it looks at the keycode.

Fix. Move it to the top of the function, above the dispatch.

## 8. Both taps drop their own userdata while their callback is on the stack

`field/input.lua` and `mouse.lua` each call `tap:stop()` and then set `self.tap = nil`,
releasing the last Lua reference from inside the tap's own callback, since escape and an
outside press both reach teardown from there. If the collector ran before the callback
returned, the finalizer would disable and release a tap mid flight. The review classified
this PLAUSIBLE rather than confirmed, since Lua will not collect synchronously there, and
both files predate the provider.

Fix, as cheap insurance rather than as a known failure. Hold the retired userdata in a
separate field so a reference survives the callback, clearing it on the next `start`. Keep
`isRunning` answering exactly what it answers today. Say in both files that this is
insurance and why.

## 9. The probe's watchdog is not a hard watchdog

`test/probe-canvaspicker.lua:258` calls `instance:hide()`, which is the same `active` guarded
path it exists to back up, so it cannot recover a state where `active` is already false and a
tap is still armed. `Field:isRunning` and `Mouse:isRunning` both say in their own comments
that they exist for a watchdog to check, and the probe reads neither.

Fix. After the hide, stop both taps directly and report what it found armed.

## 10. reposition persists the pane width policy and native does not

`init.lua:934` writes `self._paneWidth`, the field `setPaneWidth` owns. Native's `reposition`
reads its argument and leaves `layout.companionWidth` alone. Invisible today since the stage
passes the same value to both, but a reposition silently rewriting a presentation's policy is
wrong.

Fix. Read the argument, do not store it.

## 11. The list state holds styled rows and its own setQuery must never be used

`_rebuildList` puts styled rows into both `rows` and `filtered`. Nothing calls
`listModel.setQuery` on that state today, and the empty query is what keeps its internal
ranking from running, but if anything ever did, `list/model.lua` would concatenate an
`hs.styledtext` into a haystack and hand it to `match.fuzzy`.

Fix. A note at the call site saying the state holds styled rows and that `listModel.setQuery`
must never be called on it. No code change.

## 12. A truncating title's ellipsis lands under the row numeral

`list/render.lua:305`, the title frame runs to `rect.w - padX`, overlapping the numeral column
by `layout.iconSize`. `geometry.textBudget` reserves that column correctly, so a consumer
formatting against the budget is safe, but a supplier handing over a long raw title is not.
The overlap predates the styled title, a plain string was hard clipped at the same x.

Fix. Subtract the numeral column from the title's own width when `showRowNumbers` is on and
the slot is one of the first nine, matching what `textBudget` already reserves.

## 13. The placeholder is accepted and never drawn

`field/render.lua` draws the buffer unconditionally and has no empty state, so this backend
has no visible placeholder at all. The review recorded it as a gap to schedule. It is being
fixed now instead, because `host/launcher/init.lua`'s own comment says the title is what
tells you where you are once no word is visible, so on a hosted page the placeholder is the
navigational cue and not a hint.

Fix. `field/render.lua` draws the placeholder dim when the buffer is empty, on the same
baseline the text uses so the two cannot drift, taking it as a field on the style table or as
a new argument, your choice, stated in the file. The provider passes its stored placeholder
through. The caret still draws over it.

## Not being fixed, record only

A left click in the field area is claimed and does nothing, where the native widget places
the caret. `field/model.lua` exposes no hit test, so this is a feature rather than a defect.
Add it to docs/BRIEF-CANVAS-FIELD.md as a known gap with one short paragraph saying what it
would take.

## What to deliver

Items 1 through 13, the recorded gap, and nothing else. No new offline case is required,
though if any fix above is cleanly provable offline in an existing case, add the assertion
rather than skipping it.

## Acceptance

`./test/units.sh` with the total unchanged or risen, never fallen, and no existing case
changing its result. There is one known preexisting failure in the actionpanel case about a
substring, leave it and say it was already there. `luac -p` clean on every file touched.
`src/check-dependencies.sh` clean. Do not run the probe, the user decides when a live test
starts.

## Writing style, a hard requirement

Never use em dashes, en dashes, or hyphens in prose. Only periods and commas, no colons and
no semicolons. This applies to every code comment you write and to your report. It does not
apply to code itself or to file paths.
