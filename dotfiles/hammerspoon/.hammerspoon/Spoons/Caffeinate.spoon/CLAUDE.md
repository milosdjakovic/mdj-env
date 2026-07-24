# Caffeinate.spoon

A keep awake tool. One native chooser whose search field doubles as
the value entry, showing a single row that morphs with what you type. Empty is
the on and off toggle, a clock holds until a time, a duration holds for a span,
and anything unfinished or wrong shows a disabled hint so Return can never apply
a bad value. `init.lua` is the composition root and the command policy,
`engine.lua` is the keep awake mechanism, and the picker is the shared Chooser
atom injected by the main root.

**Why this file exists.** It records the behaviour and the decisions behind the
input parsing, in particular the Hammerspoon limits that shaped them, so the
reasoning survives even though the code only shows the result. Update it whenever
the grammar or the display rules change.

**What started it.** The empty field Activate row once read "Indefinite. Time
18:45 or duration 2h30m", which sounded like a value had to be typed. Rewording
it to "Activate indefinitely" with the time and duration framed as examples
exposed that the parser itself had holes, so the work grew into a proper grammar
with defined states.

**The grammar.** The allowed alphabet is digits, `h`, `m`, and a colon. Three
shapes resolve, checked in order. A colon means a clock, `HH:MM` or `H:MM`, hours
0 to 23 and two minute digits. An `h` or `m` span is a duration. A bare number
with no colon and no unit is a duration in hours.

**Why the colon stays required, and why a bare number is hours.** We considered
letting a plain number mean a time so the colon became optional, then decided
against it. Keeping the colon mandatory for a clock means a value without a colon
can never be a time, which makes a bare number unambiguously a duration. That one
rule removed the overlap between the two formats and simplified everything
downstream. A bare number is read as hours, so `25` means twenty five hours.

**The 24 boundary.** A bare number resolves to a duration only once it cannot be
a clock hour, which is 24 and above, since `24:00` is not a valid time. A number
from 0 to 23 is held back as an unfinished value rather than guessed, because it
might still be the start of a clock like `18:45`. So `25` shows a duration at
once with no `h` needed, while `18` waits for you to add a colon or a unit.

**Strict durations.** At most one hours part before at most one minutes part.
Repeats or a swapped order like `18h20h`, `20m30m`, or `30m2h` are rejected
rather than silently keeping the first unit, which the old first match parser
did. A lone minutes part may exceed 59, so `120m` is two hours, but when hours
and minutes are both written the minutes must stay under 60, since `2h90m` is a
typo, not a value.

**No cap, only a rail.** There is no maximum a user may pick, because the row
shows the resolved end on every keystroke, so an absurd value is visible and self
correcting. The only bound is a one month safety rail so `os.date` is never
handed a pathological number, and past it the input reads as an error rather than
a value.

**Five states, two of them disabled.** Empty is the toggle. A valid clock and a
valid duration are the two live rows. A value still forming, a bare hour under 24
or a half typed clock like `18:`, is a disabled keep typing hint with the
keyboard icon. Anything malformed is a disabled error row with the warning icon.
Neither disabled row can be submitted, so Return is always safe.

**Why validate and guide rather than block keystrokes.** The picker is the shared
native Chooser atom that also backs the other list tools. Blocking illegal
characters as they are typed would mean rewriting
the field, which needs a new sanitize seam in the shared atom that every other
picker would carry but never use, and that is the single consumer indirection the
design principles reject. The morphing row already gives instant feedback the
moment a character is wrong, since `hs.chooser` reruns the supplier on every
keystroke in filter mode, so we get the same clarity for free and leave the atom
untouched.

**Why the icon carries the error.** This Hammerspoon has no SF Symbol API, so a
row icon is an emoji rendered to a small image through a canvas and cached. The
keep typing state uses a keyboard and the error state a warning triangle, which
is how the two disabled states read apart at a glance.

**Day aware end labels.** A duration that crosses midnight used to show only
`ends HH:MM`, which quietly lied about which day it ended. One shared `endLabel`
helper now names the day, used by both the typed rows and the running session
status so the wording lives in one place. Today shows the time alone, tomorrow
shows the word tomorrow with the time, and anything further out shows the full
date like `Mon 27 Jul 2026, 06:00`. A clock only ever rolls within the next 24
hours, so it lands today or tomorrow and never reaches the full date form. We
chose this two tier split over spelling the full date for everything, since a
next morning clock written as a full date would be needlessly long.
