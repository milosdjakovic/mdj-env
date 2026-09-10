# Canvas field brief, phase 2 of the canvas chooser track, 2026-09-07

The phase 2 output of docs/PLAN-CANVAS-CHOOSER.md, promoted ahead of phase 1 because it
depends on nothing and it is the only part of this track that can fail on feel rather than
on logic, so it belongs in front of a person while it is still cheap to discard. Decisions
here were made by the orchestrator. A builder follows them rather than relitigating them.
Where this brief and the code disagree, stop and report rather than improvising.

## What to build

A text field for a surface that has no keyboard. `hs.canvas` offers mouse tracking and
nothing else, so the field is a buffer this configuration owns plus an event tap that
drives it. Nothing in this phase draws a row, filters a list, or touches
`lib/chooser`, `host/stage`, or the composition root.

## The shape, and why it is three units rather than one

The editing behaviour is arithmetic on a string and two integers. The event tap is a
side effecting shell around it. Text measurement needs a live font. Those are three
different things to be wrong about, so they are three files under
`lib/chooser/providers/canvas/field/`.

    model.lua    pure Lua. A buffer, a caret, a selection anchor, and one function per
                 editing operation, each taking a state and answering the next state.
                 No hs, no timers, no drawing. This is where the editing key set lives
                 and it is provable offline with no screen and no Hammerspoon.
    keymap.lua   pure data. Keycode plus modifier set to the name of a model operation.
                 A table rather than a chain of conditionals, so what the field honours
                 is readable in one place and a gap is visible rather than buried.
    input.lua    the event tap. Reads an event, resolves it through keymap, applies the
                 named operation to the model, and hands anything it does not claim to
                 the consumer. The only file here that touches hs.eventtap.

Rendering is deliberately NOT a fourth file in this phase. It is one function,
`elements(state, rect, style)` on model.lua's sibling `render.lua`, answering canvas
elements for a rect at an origin, because a caller that owns a canvas is the only thing
that can place it. This is the same division `lib/cheatsheet.lua` already takes against
`lib/panel.lua`, content answers elements and never owns the surface, and it is what
keeps this field placeable inside the three pane window later instead of owning a window
of its own.

Do not call this Strategy. Nothing here is an interchangeable policy behind one contract.
It is a pure core with a side effecting shell around it, and naming it for a pattern it
is not would mislead the next reader.

## Decisions

1. The model is pure and total. Every operation takes `(state, arg)` and answers a new
   state, never mutating the one it was given, and never raising. A caret or an anchor
   out of range is clamped rather than refused, since the shell can hand it anything.
   State is `{ text, caret, anchor }` with `anchor` nil when there is no selection, and
   `caret` counted in CHARACTERS rather than bytes, since a buffer holding one accented
   character is not a hypothetical and a byte caret would split it.

2. The editing set is the one macOS honours in every text field, not a chosen subset, and
   a key this brief lists and the build skips is a gap to report rather than to leave
   silent. Insert a character. Delete backward and forward. Delete by word in both
   directions. Delete to the start of the line. Move by character, by word, and to either
   end. The same six moves again with shift, extending the selection. Select all. Copy,
   cut and paste against `hs.pasteboard`, which is the one place the model may not answer
   alone, so those three are the shell's and the model is handed the resulting text.
   The emacs bindings macOS honours are part of this set rather than a nicety, ctrl a,
   ctrl e, ctrl k, ctrl b, ctrl f, ctrl d and ctrl h, because a hand that uses them in
   every other field will use them here and their absence reads as the field being broken.

3. Word boundaries are stated rather than assumed. A word run is a maximal run of
   characters that are not whitespace and not punctuation, and a move by word crosses any
   run of separators before the run it lands on, which is what makes deleting back through
   a path or a snippet behave the way a person expects. Write the rule down in the file.

4. The caret does not blink in the model or the renderer. `elements` takes the caret
   visibility as a plain boolean and the owner runs the timer, so nothing in these files
   holds a clock. Half a second on and half a second off, and the owner resets it to
   visible on every keystroke, which is what makes typing read as continuous.

5. Caret position is measured, never summed. `lib/chooser/providers/native.lua`'s
   memoised per character sum runs about zero point seven percent high, which is invisible
   in truncation and visible as a caret drifting off the glyph it belongs to, so the
   renderer measures the prefix with `hs.drawing.getTextDrawingSize`. One measure per
   keystroke on a query length string is about a tenth of a millisecond, which this can
   afford where a per row measure could not.

6. While the field is up the tap claims every key down. A surface with no focus does not
   stop the frontmost app receiving keys, so anything not claimed would reach whatever is
   in front. Keys the keymap does not name and that are not printable go to the consumer's
   `onKey` and are claimed either way, and the consumer answering nothing means the key is
   simply swallowed. Escape is the exception that is never delegated, it always ends the
   field, because the way out must not depend on a consumer being wired correctly.

7. The tap is armed on show and stopped on hide, never left running. `1ccab6f` is the
   record of what a leader left believed held costs on this machine, and a field that
   swallows every keystroke is the same hazard with a wider blast radius. Nothing in the
   tap callback may raise, so the operation is applied inside a pcall and a failure leaves
   the buffer as it was and reports rather than abandoning the callback halfway.

8. Theming is inherited. The renderer takes a style table and draws no chrome of its own,
   since the surface, the border and the corner radius come from
   `CanvasPanel.surfaceElements` and the text colours from `settings.chooserTheme`. Do not
   add a settings block and do not read `settings` from these files at all, the style
   arrives as an argument.

9. Input method composition is out of reach and is said so in the file rather than left to
   be discovered. An event tap sees keycodes and characters, and marked text, a candidate
   window and dead key accent sequences all live in a text input client this surface does
   not have. A field that quietly mangles a composition would be worse than one that
   states it cannot compose.

## What to deliver

The four files above. An offline unit case at `test/cases/canvasfield.lua`, following the
convention every case there already follows, one PASS or FAIL line per check, loading the
model by path with `loadfile` and driving it with no Hammerspoon behind it, covering every
operation in decision 2, the word rule in decision 3, the clamping in decision 1, and a
character caret over a multi byte character. And a live probe under the spoon's own probe
convention that loads the field into the RUNNING Hammerspoon by `dofile`, draws it on its
own canvas with a plausible style, and lets a person type. The probe owns the blink timer,
dismisses on escape, and arms a hard watchdog that tears the field down after sixty seconds
whatever else has happened, so a mistake in the tap cannot leave a keyboard swallowed.

## What not to do

Do not touch `lib/chooser`, `host/stage`, `root/compose.lua`, any manifest, or any plugin.
Do not draw a row, a highlight or a list. Do not take the devlock, restow, or reload the
live config, the probe loads over the instance that is already running. Do not drive the
screen or the keyboard for a test, the probe is opened by a person. Report any place the
brief resists the code rather than bending either side quietly.

## Acceptance

The unit case is green through `./test/units.sh` with the suite's total rising and no
existing case changing its result. The reconciler stays clean. The probe puts a field on
screen that types, deletes, moves, selects, copies and pastes under a hand, and escape ends
it. Milos judges the feel and that judgment is the gate on phase 3, not the test count.

## Round two, from the first hand test, 2026-09-10

Nineteen checks were run by hand against the probe. Everything passed except the two below,
and item eighteen behaved exactly as the file predicted, option e followed by e types a
plain e with no composition and no accent, which moves that limitation from a claim to a
measurement.

### 1. The selection highlight is the wrong height

It is drawn spanning the full height of the field rather than the height of the text it
covers, so a selection reads as a band across the whole control instead of as marked words.
The highlight is a property of the text, so its height is the rendered line height and it
sits centred on the same baseline the text is drawn from, which is a number
`hs.drawing.getTextDrawingSize` already answers alongside the width the caret placement
uses. A field that later sits inside a taller pane makes this worse rather than better,
which is why it is worth fixing at the renderer rather than by choosing a tighter rect.

### 2. Undo and redo are missing

This is a gap in the original brief rather than a build error. Decision two enumerated the
movement, deletion and clipboard sets and never named undo, so nothing was skipped, it was
never asked for. Cmd z is in every macOS text field and its absence reads as the field
being broken, so it joins the required set along with cmd shift z for redo.

Where the history lives is the decision worth stating. It goes in the model state, not in
the shell, because keeping it pure is what lets every grouping rule below be proven offline
with no Hammerspoon and no screen, which is the whole reason the model was split out. The
state grows a bounded history of prior snapshots, capped at one hundred entries with the
oldest dropped, so a field left open for a long session cannot grow without limit.

Undo must GROUP the way macOS does, or it is worse than not having it. Undoing a typed word
one character at a time is not what a hand expects and reads as the key repeating rather
than working. So consecutive plain character insertions join one group, consecutive backward
deletions join one group, and everything else opens a new group, a paste, a cut, a word
delete, a line kill, and a replacement of a selection. Any caret movement closes the current
group, since moving away means the next edit is somewhere else and joining them would undo
two unrelated things at once. Redo walks back the other way and its stack is cleared by any
fresh edit, which is the ordinary rule everywhere else.

### What to deliver for round two

Both fixes, the unit case extended to cover the grouping rules above, the cap, the caret
movement closing a group, redo being cleared by a new edit, and undo on an empty history
answering the state unchanged rather than raising. The renderer's height fix needs no case,
it is judged by eye at the probe. Do not touch anything outside the four field files, the
unit case, and the probe.

## Round three, from the second hand test, 2026-09-10

Round two's undo, its grouping and the selection highlight all passed by hand. Two visual
faults remain and they are one fault, so fix them together.

The text sits oddly within the field, and the highlight leaves more room below the descender
of a y than above the ascender of a d. Both are the same mismatch. The renderer computes a
box from `hs.drawing.getTextDrawingSize` and centres things inside it, while the canvas text
element places its glyphs by its own rule inside the frame it is given, so two boxes are
being centred independently and the glyphs end up somewhere neither of them predicted.

### The measurements this rests on

Taken from the live instance on this machine at size 16 in the system font, so they are
numbers rather than assumptions. Ascender 15.47, descender negative 3.375, cap height 11.27,
x height 8.42, leading zero, and `getTextDrawingSize` answering 19 points of height for a
string carrying both an ascender and a descender. So the drawing box is the ascender to
descender span rounded up, it carries no leading on this font, and the glyphs of ordinary
Latin text occupy far less of it than its height suggests, since the ascender reserves room
for diacritics that a plain d never reaches into.

### The rule to build on

One baseline, derived once, and everything placed from it.

The baseline is chosen so the text reads as optically centred, which for a single line of
Latin text means centring the CAP HEIGHT band rather than the ascender to descender box.
Centring the full box is what makes text look low, because the room the ascender reserves
above is much larger than the descender takes below, 4.2 points against 3.375 on the numbers
above, and none of the reserved room is occupied by the letters actually on screen.

The text element's frame is then positioned so its glyphs land on that baseline, and the
highlight spans from the baseline less the ascender to the baseline less the descender, so
it is a band around the line rather than a band around the control. Because both come from
the same baseline they cannot drift apart again, which is the actual defect being fixed here
rather than the pixel offsets it produced.

Read the metrics through `hs.styledtext.fontInfo` for the style in use rather than writing
any of the numbers above into the code. They are this font at this size on this machine, and
the field takes its font from the style it is handed.

VERIFY WHERE THE CANVAS PUTS THE BASELINE rather than taking this brief's word for it. The
claim above is that a canvas text element draws its first baseline at the top of its frame
plus the ascender, which is what the symptom implies, but it is an inference from a fault
rather than a measurement. If the canvas centres text in its frame instead, the arithmetic
that places the frame changes and this brief is wrong about the mechanism while still being
right about the rule. Measure it, state what you found, and build on the measurement.

### What to deliver for round three

The fix in render.lua only. No new unit case, this is judged by eye at the probe, but say in
the file what the baseline rule is and what was measured, so the next reader does not have to
rediscover why the arithmetic is shaped this way. Do not touch the model, the keymap or the
input.
