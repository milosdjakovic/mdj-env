# Work packet, percent in the launcher calculator

Written 2026-08-08 against feat/olm at `83c8c54`, from the user's validation finding of
2026-08-07, typing 2+2% into the launcher produces nothing while the four operators, modulo,
exponent, and parentheses all work. The fix lands on the olm copy at
`Spoons/Olm.spoon/plugins/arithmetic/init.lua`, the original `Spoons/Arithmetic.spoon` stays
untouched as the toggle fallback. Work on `feat/arithmetic-percent` from feat/olm in a
worktree under `../.worktrees/`, never from main. Do not land while another landing is in
flight, the dispatcher sequences that, your instructions will say when to land.

## The facts from the scout of this date

The plugin is a regex whitelist gate followed by a Lua load of the expression in an empty
sandbox, evaluate near lines 90 to 115. The percent sign is already in the ALLOWED alphabet
and in HAS_OP, admitted as Lua's modulo operator. 2+2% passes every gate and fails at the
load, since a trailing percent is not valid Lua, and the failed compile silently becomes no
row. The natural seam is a rewrite of the query string between the double minus guard near
line 102 and the load near line 106. Convert never sees such queries, its gate requires a to
keyword or an arrow, and that split is deliberate per its own CLAUDE.md. No unit case
exercises this plugin at all today. Line numbers drift, rescan.

## Decisions already made, build to these

One, the semantics. Percent is a postfix unit meaning hundredths, N% reads as N divided by
one hundred wherever it appears, so 2+2% answers 2.02, 200*10% answers 20, 50%*80 answers
40, and 10%^2 answers 0.01 by the same rule. The figure originally written here was 0.0001,
an arithmetic slip the builder caught and refused to bake into a test, the rule as stated
produces 0.01 and the tests assert that. The business calculator reading where the
percent binds to the other operand of a plus or minus is explicitly not chosen, it needs a
real parser the plugin's own doc refuses, and the user can veto the chosen rule at
revalidation.

Two, the rewrite. Between the guards and the load, rewrite a number followed by a percent
sign into a parenthesized division by one hundred, only when the percent is not followed by
an operand, so modulo survives. Concretely, a percent followed by an operator, a closing
parenthesis, or the end of the string is a unit, a percent followed by a number is modulo
and stays untouched. A percent directly after a closing parenthesis, as in (2+2)%, is out of
scope and stays a silent no row, note it in the code comment. The transform must be applied
repeatedly or written so multiple percent terms in one query all rewrite, 2%+5% answers
0.07.

Three, the doc comment above evaluate and the plugin `CLAUDE.md` gain a short paragraph
naming the unit rule, the modulo disambiguation, and the out of scope case. Authored lines
follow the repository writing rules.

Four, unit cases. Add a case file under `test/cases/` for this plugin, read an existing case
file first for the harness shape and match it. Cover at least, a baseline sum still
answering, 2+2% answering 2.02, 7%3 still answering 1 as modulo, 200*10% answering 20, a
lone percent producing no row, and one malformed expression still producing no row. The
inventory golden must not change.

Five, nothing else. No change to the original spoon, no change to Convert, no dependency
work.

## Gate

`test/units.sh` from the worktree hammerspoon directory passes including the new cases.
`src/check-dependencies.sh` from the worktree root passes with no new warnings.
`test/inventory.sh` three times as committed, each passing. A luac parse of the touched
file. The live feel is the user's revalidation, not your gate.

## Deliverable

Commits on the branch, small steps, each ending after a blank line with
Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>. Then, only when your instructions
say the landing slot is yours, merge to feat/olm with no fast forward, reload scheduled
never inline, the console gate scoped to the fresh load with the resolver summary at all
present, and one docs commit on feat/olm appending to the Arithmetic section of
`docs/superpowers/specs/2026-08-07-olm-validation-log.md` a short paragraph naming the
finding, the chosen unit rule, the merge hash, and awaiting the user's revalidation, boxes
untouched. A report with the merge hash, the docs hash, each gate's numbers, the exact
rewrite implementation, and any decision that did not survive contact with the code,
flagged loudly. Every line you author follows the repository writing rules, no colons, no
semicolons, no hyphens or dashes, periods and commas only, copied lines keep their form.
