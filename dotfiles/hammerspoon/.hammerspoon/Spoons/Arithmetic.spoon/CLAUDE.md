# Arithmetic.spoon

Evaluates a typed expression and offers the result as a launcher row. It is a
query row source, not a picker, so it owns no chooser, no key, and no window. The
launcher side of the contract, and why the two calculators are separate spoons,
are in the Launcher `CLAUDE.md`. This file keeps the evaluator's decisions.

## Why native Lua and no tool at all

Lua evaluates arithmetic itself and already has the four operators plus modulo,
exponent, and parentheses, so there is nothing to install, nothing to declare, and
no process to spawn. A calculator tool was considered for this half too, since one
tool could serve both arithmetic and conversion, and rejected because it would
make the common case, a quick sum, depend on a process launch and on something
being installed. This spoon therefore has no `dependencies` file, which is itself
the point, it can never be unavailable.

## Safety comes from the alphabet, then from the empty environment

A query is evaluated only after it matches a whitelist of digits, whitespace, the
operators, the decimal point, parentheses, and the letter `e`. Because letters are
otherwise excluded, the string cannot name a function or a variable, so there is
nothing to call. It is then compiled with `load` into an empty environment and run
under `pcall`, so every name would be nil even if the whitelist were later
loosened, and a malformed expression is a failed match rather than an error.

`e` is in the set only so scientific notation parses. It cannot reach anything for
the same reason, and a stray `e` either fails to compile or faults under `pcall`,
which in both cases yields no row.

## The two Lua traps that are handled explicitly

A double minus opens a comment, so `5--3` would evaluate to `5` and the row would
be confidently wrong rather than absent. That is the worst possible failure for a
calculator, so it is refused outright. A double dot concatenates and yields a
string, which the numeric type check would drop anyway, but it is refused in the
same place so both reasons live together.

## What is not a result

A bare number returns no row, since restating what was typed earns nothing. So
does an expression with no digit. Infinity and not a number are refused, so a
division by zero or an overflow shows nothing rather than the word `inf`. All of
these are silence rather than an error row, because the launcher list is full of
other rows and a complaint about a half typed expression would be noise on the way
to a real answer. That is the opposite of the Caffeinate picker, which shows a
disabled hint row precisely because its list is otherwise empty.

## Formatting is display only

Lua division always yields a float, so an integral result is printed without its
decimal tail because `33.0` reads as noise. Anything else keeps ten significant
digits with trailing zeros trimmed, so a third reads as `0.3333333333` rather than
in exponent form. Thousands separators were left out so the shown value and the
copied value are the same string, which matters because the row exists to be
copied.

## What it deliberately does not do

No variables, no history, no functions, and no units. Units belong to `Convert`,
which is a separate spoon because it needs a tool that can be absent. Adding
functions would mean putting names back in the alphabet and giving up the reason
evaluation is safe, so it would need a real parser rather than a whitelist.
