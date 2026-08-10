# Convert.spoon

Converts units and currencies from a typed query and offers the answer as a
launcher row. Like `Arithmetic` it is a query row source, not a picker. The
launcher side of the contract is in the Launcher `CLAUDE.md`, and how its tool is
declared and resolved is in the hammerspoon `CLAUDE.md` and
`Dependencies.spoon/CLAUDE.md`. This file keeps its own decisions.

## Why this is a separate spoon from Arithmetic

The two fail differently, and that is the whole reason. Arithmetic is native Lua
and can never be unavailable. Conversion is a front end onto a calculator tool
from outside Hammerspoon, plus unit and currency knowledge nothing here has, so it
can legitimately be absent. Keeping them apart lets the composition root drop this
spoon out of the launcher's sources entirely when its tool is missing while
arithmetic keeps working. One spoon carrying both would have to disable half of
itself at runtime and would still need to decide what to show for the half that
was gone. This is the worked example of the required policy actually meaning
something.

## Why the tool is required rather than optional

This spoon is nothing but a front end. With no tool there is no partial service to
offer, so a row that failed when chosen, or a row explaining its own absence, would
both be worse than no row. So the declaration is `required`, the root reads
`satisfied()` and leaves the spoon out of the source list, and the console says once
that conversion will not appear. That is the rule the whole dependency layer serves,
an absent tool removes its feature from the interface and explains itself in the
console rather than leaving something broken in a list.

## Why an explicit target is required, and that it is a narrowing not a limit

The tool runs as a separate process, tens of milliseconds, so it must never run
while someone is searching for an app. A query counts as a conversion only when it
carries a number and names a target after `to` or the arrow, with something on both
sides. The tool itself understands far more than that, a bare quantity or a mixed
expression, and none of that reaches it. That is deliberate. The gate was tested
against the real app names in this config, and `1password`, `Visual Studio Code`,
`intellij`, and `notion` all correctly fail it, which is the property worth
protecting. Widening the gate later means measuring how often a process is spawned
during an ordinary search, not just accepting more shapes.

The keyword match is anchored on whitespace both sides, so `into` and `token` do
not count as the keyword, which is the kind of thing an unanchored match gets
wrong on a word like `install`.

## Why `in` is not accepted as a conversion word

It reads naturally and it was accepted at first, and it was wrong. The tool parses
`in` as inches, so `5 ft in cm` is read as feet times inches times centimetres and
answers `387096 mm³` with a success exit code. Nothing can tell that reading apart
from the one the user meant, and an answer that is confidently wrong is worse than
no answer, so only the operators the tool documents are accepted. This is also the
reason the query is split at its **last** operator rather than its first, since
`10 in to cm` has a unit named `in` before the real operator.

## Why every run carries the same three flags

Terse output keeps stdout to the answer alone. The other two exist because the
defaults are wrong for this use.

Limiting implicit multiplication is what makes an unknown word fail. Without it the
tool reads `bogus` as a product of the single letter units `b`, `o`, `g`, `u`, and
`s`, so `5 bogus to miles` answers with a number rather than failing. With the flag
that query exits non zero and is recorded as a miss, which shows nothing.

Note that the flag makes a query fail without making its output empty. `5 bogus to
miles` still prints a number, it just exits non zero, which is exactly why the exit
status is checked and not only the text. Judging that answer by its output alone
would put a wrong number in the row.

The same flag is what keeps a wrong temperature answer off the screen, which is worth
knowing because the failing spelling looks reasonable. `degF` and `degC` are not unit
names here. Without the flag `-40 degF to degC` exits zero and answers `-40 C·°/V`,
which would have been shown as if it were right. With the flag it exits non zero and
shows nothing. The spellings that do work are the full words and the degree symbols,
so `-40 fahrenheit to celsius` and `-40 °F to °C` both give `-40 °C`, and kelvin
converts either way. This is a property of the tool's unit vocabulary rather than
something this spoon can fix, and no answer is the correct outcome for a spelling the
tool does not know.

Never updating exchange rates keeps a keystroke off the network. The tool's default
is to ask, and either a prompt or a download inside a background task is a hang
waiting to happen. Currency therefore uses the rate file already on disk, which for
a fresh install is the one shipped with the formula, so a rate can be days old.
Refreshing it is a deliberate `qalc -e` in a terminal. Doing that automatically
would mean a network call on the launcher's path, which is the trade this avoids.

## Why a mixed unit answer is asked for twice

Mixed units are the tool's default for customary lengths and for time, so `10 km to
miles` answers `6 mi + 376 yd + 4.787401575 in`. That reads well and copies badly,
and copying is the entire point of the row. The only lever the tool offers is a
minus in front of the target, and there is no setting for it, which was checked
against every plausible spelling, so the target has to be rewritten.

The rewrite happens only after seeing a sum in the answer, never on the first run.
A target can also be a presentation command like `hex`, `base`, or `roman` rather
than a unit, and a minus in front of one of those yields an unevaluated expression
such as `−((1024(−hex())) / hex()) B`. Waiting for the sum means the vocabulary of
those commands never has to be known here, which matters because it is long and
belongs to a tool this spoon does not control. The second answer is used only when
it is one clean value, so a rewrite that produced nonsense is discarded and the
first answer stands.

The cost is measured. A single unit answer, a currency answer, and a presentation
target each cost one process, a mixed unit answer costs two, and a cached answer or
a query that fails the gate costs none.

## Why the unicode minus is replaced

The tool prints U+2212 for a negative sign, so `-40 celsius to fahrenheit` answers
with a character that no parser and no spreadsheet accepts. Since the answer exists
to be copied, that one character is replaced with a plain hyphen and nothing else in
the answer is touched. This is not configurable in the tool, which was checked.

## How a late answer is handled

A process cannot answer inside the synchronous call that builds rows, so three
things work together. A new query returns a disabled placeholder row, so the row
does not appear out of nowhere and the list does not visibly jump when the answer
replaces it. The run is debounced, so a burst of keystrokes launches one process
rather than one per character. And every answer, hit or miss, is cached, so
repeated builds for the same query cost nothing and a query already known to have
no answer shows nothing rather than a stale row.

The debounce timer is kept in a field, and dropping it on the floor is a real defect
rather than a style question. A Hammerspoon timer is userdata whose finalizer stops
it, so a pending timer nothing refers to can be collected before it fires. Building a
launcher list rebuilds every row on every keystroke, which allocates enough to bring a
collection down inside that quarter second, and the run then disappears with no error
anywhere. The visible symptom is the placeholder row sitting there forever, and it
sticks to that exact query, because the pending slot is released only by an answer and
the guard refuses to schedule a second run for a query it thinks is already running.
Retyping the same thing therefore does nothing while a different conversion works,
which reads like a parsing bug and is not one. This was reproduced with a forced
collection, and holding the timer fixes it.

Each run carries a generation number and a stale answer is discarded. Without it
an answer to a query the user has already typed past could replace a newer one,
which is the classic async ordering bug and is invisible until it happens.

The presenter is told through an injected `onResult` callback rather than being
named, so this spoon still knows nothing about what shows its rows. The launcher
gets that callback wired to its own refresh in the composition root.

## Why the cache is per session and capped

Conversions are typed in bursts and currency rates move, so nothing here is worth
keeping across a reload, which the cache being in memory gives for free. The cap
exists only so a long session cannot grow it without bound, and it clears wholesale
rather than evicting cleverly, since at this size the difference is not worth the
code.

## What it deliberately does not do

It does not refresh exchange rates, retry a miss, or explain a failed conversion in
the list. A failed run is recorded as a miss so the same query is not retried on
every keystroke, and the reason goes to the console at debug level rather than into
a row. It also does not do plain arithmetic, even though its tool can, because that
would mean two sources answering the same query and a process launch for a sum that
`Arithmetic` already answered instantly.

It also never writes the tool's own config. The flags are passed per run, which was
checked to leave the saved settings untouched, so nothing here changes how `qalc`
behaves in a terminal.

## How to test it without Hammerspoon

The tool is the interesting part and a stub hides its behaviour, which is how the
`in` reading and the mixed unit output both got through a first pass. Standing
`hs.task` on a synchronous `io.popen` and draining `hs.timer` by hand runs this
spoon against the real tool from plain `lua`, with no Hammerspoon and no test lock.
That is worth rebuilding rather than trusting a stub, because every defect found
here was in what the tool actually returns rather than in the control flow around
it.
