# Chooser stage probe findings, live instance, 2026-08-27

Every number here was measured against the running Hammerspoon on this Mac through the
`hs` CLI with `dofile` scripts. No reload was issued, no `hs.settings` key was touched,
and the devlock was never taken. Four probe scripts and their raw JSON sit beside this
file in the scratchpad, `probe-a.lua`, `probe-b.lua`, `probe-c.lua`, `probe-c2.lua`,
`probe-c3.lua`, and `final-check.lua`. The final check confirms no stray chooser window
was left visible.

One environment fact matters for reading the width numbers. The main screen changed
between the earlier and the later probes, from a 1512 point display to a 3440 point one,
because the focused window moved. That is not noise, it is the very behaviour
`native.lua` documents, since `hs.chooser` measures its width percentage against
`hs.screen.mainScreen()`. Every width figure below states which main screen it was
measured on.

## A. Open economics

All times in milliseconds. Three runs, every run reported. A call time is the
synchronous cost of the API call. A visible time polls the real Hammerspoon window
titled `Chooser` at four millisecond intervals from the moment of the call until the
window is actually up, so it is the latency a person would perceive.

| measurement | run 1 | run 2 | run 3 |
|---|---|---|---|
| build 500 styled row pairs, cold | 30.27 | 29.74 | 37.02 |
| build 500 styled row pairs, second list in the same run | 11.58 | 19.22 | 18.01 |
| `hs.chooser.new` plus `choices()` with 500 rows | 5.08 | 6.86 | 7.23 |
| first `show()`, call | 58.79 | 60.15 | 41.18 |
| first `show()`, until the window is visible | 116.16 | 130.30 | 99.14 |
| `hide()`, call | 35.44 | 30.34 | 31.78 |
| `show()` again on the same instance, call | 30.28 | 35.14 | 12.13 |
| `show()` again on the same instance, until visible | 90.19 | 72.49 | 61.60 |
| `choices()` swap plus `show()`, call | 58.95 | 69.27 | 54.21 |
| `choices()` swap plus `show()`, until visible | 104.91 | 103.06 | 88.12 |

What this says. Building the rows is not where the money goes. Five hundred styled row
pairs cost about thirty milliseconds cold and about fifteen once the font and the colour
objects are warm, and handing them to a chooser costs another five to seven. The
expensive thing is the window. A first show costs roughly a hundred to a hundred and
thirty milliseconds before anything is on screen, and a reshow of the same instance
still costs sixty to ninety. Hiding costs a further thirty.

So a close and reopen between two lists spends somewhere between ninety and a hundred
and sixty milliseconds of window work, none of which produces a single new row. The
answer to whether keeping one window alive is the win is yes, and the size of the win is
the whole of that figure, because a swap into a window that is already up costs about
five milliseconds for the same five hundred rows. See section C for that measurement.

## D. Construction alone

`hs.chooser.new` with no choices at all, three runs, milliseconds.

| run 1 | run 2 | run 3 |
|---|---|---|
| 18.13 | 7.93 | 10.08 |

The first is a warm up. Construction settles at roughly eight to ten milliseconds, so of
the five to seven milliseconds measured for construction plus five hundred choices in
section A, the choices themselves are close to free and the number is dominated by
allocation noise. Construction is cheap and is not what makes an open feel slow.

## B. Menu walk cost

Every running GUI application, filtered to `kind() == 1`, walked sequentially with
`getMenuItems` and a callback, nothing activated or focused. Seventeen applications, no
timeouts, the whole sweep finished in about six seconds. Item counts are flattened
leaves, meaning a titled node carrying no children of its own.

| app | bundle id | leaf items | ms |
|---|---|---|---|
| Safari | com.apple.Safari | 1259 | 552.2 |
| Preview | com.apple.Preview | 228 | 541.1 |
| System Settings | com.apple.systempreferences | 131 | 525.3 |
| Mail | com.apple.mail | 357 | 498.7 |
| Stickies | com.apple.Stickies | 153 | 459.2 |
| Books | com.apple.iBooksX | 197 | 421.8 |
| Zed | dev.zed.Zed | 167 | 391.6 |
| Passwords | com.apple.Passwords | 107 | 314.3 |
| Notes | com.apple.Notes | 221 | 273.2 |
| Google Chrome | com.google.Chrome | 282 | 263.1 |
| Finder | com.apple.finder | 220 | 221.3 |
| Calendar | com.apple.iCal | 133 | 121.6 |
| Activity Monitor | com.apple.ActivityMonitor | 151 | 98.5 |
| Ghostty | com.mitchellh.ghostty | 125 | 88.8 |
| Slack | com.tinyspeck.slackmacgap | 152 | 76.7 |
| Claude | com.anthropic.claudefordesktop | 108 | 70.8 |
| Docker Desktop | com.electron.dockerdesktop | 31 | 50.2 |

What this says. Nothing here is fast enough to sit in front of a keypress. The cheapest
application on this machine costs fifty milliseconds and the median is about two hundred
and seventy, which is already two to five times the whole cost of opening a chooser
window. The heaviest, Safari, costs over half a second, and it is also by far the
largest list at 1259 leaves, so the worst case for the snapshot correction and the worst
case for the redraw are the same application.

Two things are worth noting beyond the headline. The cost does not track the item count
closely, since Preview costs almost as much as Safari for a fifth of the items and
Google Chrome returns 282 items in half of Preview's time, so the expense is in the Apple
Events round trip and the application's own responsiveness rather than in the size of the
tree. And no application timed out, so the ten second guard was never exercised and a
timeout policy remains untested by this run.

Safari is the right subject for the live test in phase seven of the plan, being both the
slowest and the largest.

## C. Live window behaviour

The first pass at this, `probe-c.lua`, lost its window part way through, which made every
step after the third unanswerable. A controlled second pass, `probe-c2.lua`, applied each
mutator in isolation against a control that did nothing, sampling visibility, frame,
highlight, and the frontmost application at six offsets from fifty milliseconds to 1.6
seconds. A third pass, `probe-c3.lua`, closed the questions the first pass could not
answer. The dismissal is discussed under surprises below. Every answer here comes from
the second and third passes, which agree with each other.

### C1. Swapping `choices()` while visible

The window stays up. Measured with a raw chooser carrying a `queryChangedCallback`, so
the widget's own filtering is disabled exactly as the atom disables it, the window
remained visible through a swap to another twenty rows, to three rows, to an empty list,
and to forty rows, with `isVisible` true at every sample.

The highlight resets. `selectedRow` was set to 6, read back as 6 before the swap, and
read 1 immediately after `choices()` and still 1 after a three hundred millisecond
settle. An empty list reads 0. Setting `selectedRow(6)` again after the swap restores it
and it sticks, so a stage that wants to preserve a position has to capture the row number
and put it back, which is precisely what `Chooser:refresh` already does.

The frame does not change. The window measured `213,-1212 1032x621` before the swap and
`213,-1212 1032x621` after every one of the four swaps above, including the swap to an
empty list and the swap to forty rows. A list becoming shorter or longer moves nothing.

The swap is cheap. Five hundred fully styled rows swapped into the visible window three
times cost 5.90, 5.08, and 5.59 milliseconds, and the window stayed visible and stayed
the same size through all three. That is the number that makes the stage worth building,
against roughly ninety to a hundred and sixty milliseconds for a close and reopen.

### C2. `rows(3)` while visible

The visible window does not resize. The frame read `529,142 454x514` before the call and
`529,142 454x514` at fifty milliseconds, a hundred and fifty milliseconds, three hundred
milliseconds, six hundred milliseconds, one second, and 1.6 seconds after it. A choices
swap afterwards does not apply it either.

It does apply on the next show of the same instance. After `rows(3)` the next show of
that same chooser came up at `454x220`, and 220 is exactly the height `native.lua`
computes from its own numbers, a base of 94 plus three rows of 42. The ten row window
before it was 514, which is 94 plus ten times 42, so the widget and the atom's arithmetic
agree to the point.

So a presentation cannot change height live. It can change height across a hide and a
show, and it needs no rebuilt instance to do it.

### C3. `setTopLeft` on the window element

It works, immediately, and the widget stays live. A window at x 604 moved to x 404 within
the first fifty millisecond sample and stayed there, with width and height untouched.
After the move the chooser answered `query()` with text set programmatically, accepted a
`selectedRow`, accepted a `choices()` swap, remained visible, and the accessibility tree
reported twenty rows under its table. A second run moved a window from x 213 to x 13 with
the same result.

This is the mechanism `_settleFrames` already uses and it is safe to keep using while a
window stays alive, which is what phase four of the plan needs.

### C4. `width(20)` while visible

Confirmed no, exactly as `native.lua` claims. The frame stayed 454 points wide through
every sample from fifty milliseconds to 1.6 seconds after the call, on a 1512 point main
screen where twenty percent would be 302.

The useful half of this answer is what happens next. The pending width applies on the
next show of the same instance with no rebuild at all. A chooser at 454 points, thirty
percent of 1512, was given `width(20)` while visible, hidden, and shown again, and came
up at 303 points, against an expected 302.4. Setting it back to thirty and hiding and
showing again returned it to 454. So the private stage path the plan reserves for a rare
width change is a hide and a show, not a rebuilt chooser, which is simpler than the plan
assumed.

### C5. `placeholderText` while visible

It takes effect and it is visible. The getter returned the new string immediately, and
the accessibility tree confirmed the rendering rather than only the stored value, with
`AXPlaceholderValue` reading `probe c3 placeholder` before and `live changed placeholder
text` after. There are no observable side effects in the frame, which measured
`213,-1212 1032x621` before and after, and the window stayed visible.

### C6. Query and `refreshChoicesCallback`

Setting a query programmatically does not close the window and does not clear on a swap.
`query("test")` left the window visible, and the accessibility read of the field returned
`test`, confirming the field really holds it. A `choices()` swap immediately afterwards
left the query as `test`, the window visible, and the highlight at 1, both immediately
and after a settle.

`refreshChoicesCallback` works and keeps everything. With a function supplier installed,
the supplier had been called once, `refreshChoicesCallback` called it a second time in
4.1 milliseconds, and after the refresh the window was still visible, the query was still
`test`, and the frame was unchanged.

No key was typed by hand at any point. Every query in this section was set through
`chooser:query`.

## Surprises, called out

**The first pass lost its window and the second pass could not reproduce it.** In
`probe-c.lua` the chooser was visible a hundred milliseconds after the `rows(3)` call and
gone by five hundred milliseconds, and every step after that ran against no window, which
is why that file records a string of empty frames. The obvious reading was that `rows()`
dismisses a visible chooser. That reading is wrong. `probe-c2.lua` applied `rows(3)` in
isolation and the window stayed visible for a full 1.6 seconds, and the same held for the
placeholder change, the width change, the choices swap, the query, the highlight move,
`bgDark`, and `setTopLeft`, nine phases in a row with no dismissal anywhere. So no call
tested here dismisses a visible chooser. The most likely cause of the first pass is an
ordinary external dismissal during a ten second window in which a chooser sat on the
user's screen, an Escape or a click. It is recorded as unexplained rather than explained,
because nothing was captured that could prove it.

**Losing key focus does not dismiss the chooser.** This is worth stating because a stage
that keeps one window alive depends on it. Through all nine phases of the second pass the
frontmost application was Claude, never Hammerspoon, and the chooser stayed visible the
whole time. So a chooser can be up while another application owns the keyboard.

**The chooser's own height arithmetic matches the atom's exactly.** The window came up at
514 points for ten rows and 220 for three, against `native.lua`'s base of 94 plus 42 per
row, which gives 514 and 220. That means the atom's seed frame is not an approximation
that the settle corrects, at least at these row counts.

**A first show renders taller than the steady state.** The chooser opened at 621 points
high for a ten row list where the settled height for ten rows is 514. `native.lua`
already warns that the widget settles to a more compact height after the first show, and
this is that behaviour measured. A stage that keeps one window alive pays this once per
session rather than once per open, which is a quiet extra argument for the design.

## Unanswered

**The timeout policy for `getMenuItems` is untested.** No application timed out, so the
ten second guard never fired and nothing here says what a hung application does.

**Nothing was measured about a companion pane on a live window.** Every question in
section C was asked of a bare chooser with no companion, so whether a pane can be shown
or hidden beside a window that stays up is still open, and phase four of the plan will
have to answer it.

**No answer about what a swap does to the scroll position.** The lists used were small
enough to fit or the highlight reset to the top before it could be observed, so whether a
long list keeps its scroll offset across a swap was not established.

**Nothing was tested about two choosers alive at once.** Every probe used a single
instance, so the assumption both `_settleFrames` and the accessibility helpers make, that
only one chooser window is ever visible, was neither tested nor challenged.
